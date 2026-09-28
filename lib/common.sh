# lib/common.sh - shared logic for install.sh. See docs/DESIGN.md.
# shellcheck shell=bash
#
# bash 3.2 compatible: no associative arrays, ${var,,}, mapfile or readarray.
# Commands whose flags differ between BSD and GNU go through lib/platform/*.sh.
#
# Read-only modes: --check, --dry-run, --report. Everything that changes the
# machine lives in lib/actions.sh.

set -Eeu

STEPS=9
MODE=""
DRY_RUN=0
READ_ONLY=1
ADOPT_PATH=""
ADOPT_AS=""
RESTORE_ID=""
LINK_ONLY=0
PKG_FLAG=""          # yes | no, from --packages / --no-packages
PKG_MODE=""          # yes | no | ask: will this run install packages?
PKG_NOTE=""
PKG_ASKED=0
PROFILE=""
PROFILE_NOTE=""
ONLY=""
PLATFORM=""
VERBOSE=0
CURRENT_STEP="preflight"
CURRENT_ACTION=""
CONFIG_DIR="$HOME/.config/dotfiles"
COMPONENTS="packages vim tmux shell git task private"
N_OK=0; N_TODO=0; N_ASK=0; N_WARN=0; N_FAIL=0; N_SKIP=0

# shellcheck source=lib/actions.sh
. "$DOTFILES_DIR/lib/actions.sh"

# run_confirmed <mode function>: ask once, then run it.
run_confirmed() { confirm_run; "$@"; }

# ---------------------------------------------------------------- output

item() {
    # item <result word> <text>
    case "$1" in
        ok)   N_OK=$((N_OK + 1)) ;;
        todo) N_TODO=$((N_TODO + 1)) ;;
        ask)  N_ASK=$((N_ASK + 1)) ;;
        warn) N_WARN=$((N_WARN + 1)) ;;
        FAIL) N_FAIL=$((N_FAIL + 1)) ;;
        skip) N_SKIP=$((N_SKIP + 1)) ;;
    esac
    printf '  %-5s %s\n' "$1" "$2"
}
cmd_line() { printf '        + %s\n' "$1"; }
note()     { printf '        %s\n' "$1"; }
section()  { CURRENT_STEP="$1"; printf '\n%s\n' "$1"; }
step()     { section "[$1/$STEPS] $2"; }

# shellcheck disable=SC2088  # "~" is display text here, never expanded
tildify() {
    case "$1" in
        "$HOME")   printf '~\n' ;;
        "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;;
        *)         printf '%s\n' "$1" ;;
    esac
}
# shellcheck disable=SC2088  # matches the literal "~/" prefix used in links.txt
expand_home() {
    case "$1" in
        "~/"*) printf '%s/%s\n' "$HOME" "${1#"~/"}" ;;
        *)     printf '%s\n' "$1" ;;
    esac
}

# in_list <word> <newline-separated list>: exact line match without a subprocess.
in_list() {
    case "
$2
" in
        *"
$1
"*) return 0 ;;
    esac
    return 1
}

usage() {
    cat <<'EOF'
Usage: ./install.sh [mode] [options]

Read-only modes (change nothing):
  --check                show how this machine differs from the repo
  --dry-run              show every step and command a real run would take
  --report               one redacted block to paste into a chat

Modes that change the machine (everything replaced is backed up first):
  (no mode)              full install
  --link-only            links and stubs only, no packages or plugins
  --adopt PATH [--as P]  move a file into the repo and link it
  --update-addons        git pull the add-ons
  --restore [RUN]        undo a run (the latest by default)
  --uninstall-hooks      turn off this clone's pre-commit hook

Options:
  --profile base|personal|office   default: saved profile; a real run asks
  --only packages|vim|tmux|shell|git|task|private
  --yes                  no questions: confirm, and keep the repo version
  --packages             install missing packages (remembered for this machine)
  --no-packages          never install packages here; use what is installed (remembered)
  --platform macos|debian|linux    override detection (for testing)
  --verbose                        write a line-by-line trace to a temp file
  -h, --help

See docs/DESIGN.md for the design and the phases.
EOF
}

die_usage() {
    echo "install.sh: $1" >&2
    echo "Try: ./install.sh --help" >&2
    exit 2
}


# ---------------------------------------------------------------- failure report

ERR_FILE="${TMPDIR:-/tmp}/dotfiles-err.$$"

on_error() {
    local rc=$? cmd="$BASH_COMMAND" src line fn
    src="${BASH_SOURCE[1]:-install.sh}"; src="${src#"$DOTFILES_DIR"/}"
    line="${BASH_LINENO[0]:-?}"
    fn="${FUNCNAME[1]:-main}"
    trap - ERR
    if [ "${BASH_SUBSHELL:-0}" -gt 0 ]; then
        # Inside $(...): record the real failure for the top level to print.
        [ -s "$ERR_FILE" ] || printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$rc" "$cmd" "$src" "$line" "$fn" "$CURRENT_STEP" "$CURRENT_ACTION" > "$ERR_FILE"
        exit "$rc"
    fi
    if [ -s "$ERR_FILE" ]; then
        IFS="$(printf '\t')" read -r rc cmd src line fn CURRENT_STEP CURRENT_ACTION < "$ERR_FILE" || true
    fi
    # A command run through run_cmd leaves its own text and last output behind.
    [ -s "$ERR_FILE.cmd" ] && cmd="$(cat "$ERR_FILE.cmd")"
    {
        echo
        echo "==================== dotfiles: FAILED ===================="
        echo "step      : $CURRENT_STEP"
        [ -n "$CURRENT_ACTION" ] && echo "action    : $CURRENT_ACTION"
        echo "command   : $cmd"
        echo "exit code : $rc"
        echo "location  : $src:$line ($fn)"
        echo "platform  : $(platform_line 2>/dev/null || echo unknown)"
        echo "repo      : $(repo_line 2>/dev/null || echo unknown) | profile: ${PROFILE:-?}"
        if [ -s "$ERR_FILE.out" ]; then
            echo "last output:"
            sed 's/^/  /' "$ERR_FILE.out"
        fi
        [ -n "${LOG_FILE:-}" ] && echo "log       : $(tildify "$LOG_FILE")"
        if [ -n "${RUN_DIR:-}" ] && [ -s "${MANIFEST:-/nonexistent}" ]; then
            echo "undo      : ./install.sh --restore $RUN_ID"
        fi
        echo "next      : paste this block into the chat, or run ./install.sh --report"
        echo "==========================================================="
    } | redact | if [ -n "${LOG_FILE:-}" ] && [ -f "$LOG_FILE" ]; then tee -a "$LOG_FILE"; else cat; fi
    rm -f "$ERR_FILE" "$ERR_FILE.cmd" "$ERR_FILE.out"
    exit 1
}

# Replace the home path, hostname and username so output can be pasted anywhere.
redact() {
    local host user
    host="$(hostname 2>/dev/null || echo)"; host="${host%%.*}"
    user="$(id -un 2>/dev/null || echo)"
    sed -e "s#$HOME#~#g" \
        -e "s#${host:-@@no-host@@}#<host>#g" \
        -e "s#/${user:-@@no-user@@}/#/<user>/#g" \
        -e "s#${user:-@@no-user@@}@#<user>@#g"
}

# ---------------------------------------------------------------- options and detection

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --check|--dry-run|--report)
                [ -n "$MODE" ] && die_usage "choose one mode: $MODE or ${1#--}"
                MODE="${1#--}" ;;
            --profile)  shift; [ $# -gt 0 ] || die_usage "--profile needs a value"; PROFILE="$1" ;;
            --profile=*) PROFILE="${1#*=}" ;;
            --only)     shift; [ $# -gt 0 ] || die_usage "--only needs a value"; ONLY="$1" ;;
            --only=*)   ONLY="${1#*=}" ;;
            --platform) shift; [ $# -gt 0 ] || die_usage "--platform needs a value"; PLATFORM="$1" ;;
            --platform=*) PLATFORM="${1#*=}" ;;
            --verbose)  VERBOSE=1 ;;
            --yes)      ASSUME_YES=1 ;;
            --packages)    PKG_FLAG=yes ;;
            --no-packages) PKG_FLAG=no ;;
            --link-only|--update-addons|--uninstall-hooks)
                [ -n "$MODE" ] && die_usage "choose one mode: $MODE or ${1#--}"
                MODE="${1#--}" ;;
            --adopt)
                [ -n "$MODE" ] && die_usage "choose one mode: $MODE or adopt"
                shift; [ $# -gt 0 ] || die_usage "--adopt needs a file"; MODE=adopt; ADOPT_PATH="$1" ;;
            --as)       shift; [ $# -gt 0 ] || die_usage "--as needs a repo path"; ADOPT_AS="$1" ;;
            --restore)
                [ -n "$MODE" ] && die_usage "choose one mode: $MODE or restore"
                MODE=restore
                if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then shift; RESTORE_ID="$1"; fi ;;
            -h|--help)  usage; exit 0 ;;
            *) die_usage "unknown option: $1" ;;
        esac
        shift
    done
    [ -n "$MODE" ] || MODE=install
    [ -z "$ADOPT_AS" ] || [ "$MODE" = adopt ] || die_usage "--as only goes with --adopt"
    case "$MODE" in check|dry-run|report) READ_ONLY=1 ;; *) READ_ONLY=0 ;; esac
    [ "$MODE" = link-only ] && LINK_ONLY=1
    case "${PROFILE:-base}" in base|personal|office) ;; *) die_usage "unknown profile: $PROFILE" ;; esac
    if [ -n "$ONLY" ]; then
        case " $COMPONENTS " in
            *" $ONLY "*) ;;
            *) die_usage "unknown component for --only: $ONLY (one of: $COMPONENTS)" ;;
        esac
    fi
    case "$PLATFORM" in ""|macos|debian|linux) ;; *) die_usage "unknown platform: $PLATFORM" ;; esac
    [ "$MODE" = dry-run ] && DRY_RUN=1
    return 0
}

detect_platform() {
    local id id_like
    if [ -n "$PLATFORM" ]; then return 0; fi
    case "$(uname -s)" in
        Darwin) PLATFORM=macos ;;
        Linux)
            if [ -r /etc/os-release ]; then
                # shellcheck source=/dev/null
                id="$(. /etc/os-release; printf '%s' "${ID:-}")"
                # shellcheck source=/dev/null
                id_like="$(. /etc/os-release; printf '%s' "${ID_LIKE:-}")"
                case " $id $id_like " in
                    *" debian "*|*" ubuntu "*) PLATFORM=debian ;;
                esac
            fi
            # Any other Linux: no package manager support, tools already installed are used.
            [ -n "$PLATFORM" ] || PLATFORM=linux ;;
    esac
    if [ -z "$PLATFORM" ]; then
        echo "install.sh: unsupported platform: $(uname -s) ${id:-} ${id_like:-}" >&2
        echo "Supported: macOS, Debian and Ubuntu. Override with --platform for testing." >&2
        exit 3
    fi
    return 0
}

resolve_profile() {
    if [ -n "$PROFILE" ]; then
        PROFILE_NOTE="from --profile"
    elif [ -r "$CONFIG_DIR/profile" ]; then
        read -r PROFILE < "$CONFIG_DIR/profile" || true
        PROFILE_NOTE="saved in ~/.config/dotfiles/profile"
    elif [ "$MODE" = install ] || [ "$MODE" = link-only ]; then
        if [ "$ASSUME_YES" = 0 ] && has_tty; then
            printf 'Which profile is this machine? [b]ase / [p]ersonal / [o]ffice: ' > /dev/tty
            read -r PROFILE < /dev/tty || PROFILE=""
            case "$PROFILE" in b|base) PROFILE=base ;; p|personal) PROFILE=personal ;; o|office) PROFILE=office ;; esac
            PROFILE_NOTE="chosen now; saved at the end of the run"
        else
            die_usage "no profile saved yet: add --profile base, personal or office"
        fi
    else
        PROFILE=base
        PROFILE_NOTE="assumed: none saved yet and no --profile given"
    fi
    case "$PROFILE" in
        base|personal|office) ;;
        *) die_usage "unknown profile '$PROFILE' ($PROFILE_NOTE)" ;;
    esac
    return 0
}

# A failure inside a pipeline runs in a subshell and cannot stop the run itself;
# it leaves ERR_FILE behind. Call this after such a pipeline to report it.
check_subshell_failure() {
    if [ -s "$ERR_FILE" ]; then false; fi
    return 0
}

platform_line() {
    local release
    # shellcheck source=/dev/null
    case "$PLATFORM" in
        macos)  release="macOS $(sw_vers -productVersion 2>/dev/null || echo '?')" ;;
        debian|linux) release="$(os_release_name)" ;;
    esac
    printf '%s | %s | %s | bash %s\n' "$PLATFORM" "${release:-unknown release}" "$(uname -m)" "${BASH_VERSION%%(*}"
}

# os_release_name: "CentOS Linux 7 (Core)", or the kernel name without /etc/os-release.
os_release_name() {
    local n=""
    # shellcheck source=/dev/null
    [ -r /etc/os-release ] && n="$( (. /etc/os-release && printf '%s' "${PRETTY_NAME:-}") || true)"
    printf '%s\n' "${n:-$(uname -s)}"
}

# resolve_packages_mode: will this run install missing packages? Sets PKG_MODE
# (yes | no | ask) and PKG_NOTE. A machine without sudo uses what is installed.
resolve_packages_mode() {
    local saved=""
    [ -r "$CONFIG_DIR/packages" ] && read -r saved < "$CONFIG_DIR/packages"
    if [ -n "$PKG_FLAG" ]; then
        PKG_MODE="$PKG_FLAG"
        if [ "$PKG_FLAG" = yes ]; then PKG_NOTE="from --packages"; else PKG_NOTE="from --no-packages"; fi
    elif [ "$PKG_MANAGER" = none ]; then
        PKG_MODE=no; PKG_NOTE="no supported package manager on $(os_release_name)"
    elif [ "$saved" = yes ] || [ "$saved" = no ]; then
        PKG_MODE="$saved"; PKG_NOTE="saved in ~/.config/dotfiles/packages"
    elif [ "$PKG_MANAGER" = brew ]; then
        PKG_MODE=yes; PKG_NOTE="Homebrew installs as this user"
    elif ! command -v sudo >/dev/null 2>&1; then
        PKG_MODE=no; PKG_NOTE="no sudo on this machine"
    elif sudo -n true 2>/dev/null; then
        PKG_MODE=yes; PKG_NOTE="sudo works here"
    elif [ "$READ_ONLY" = 1 ]; then
        PKG_MODE=ask; PKG_NOTE="a real run asks whether sudo can be used"
    elif [ "$ASSUME_YES" = 1 ] || ! has_tty; then
        PKG_MODE=no; PKG_NOTE="sudo needs a password and nobody can be asked; add --packages to install"
    else
        printf '\nCan this run use sudo to install packages?\n[y]es, install what is missing / [n]o, use what is already installed: ' > /dev/tty
        read -r saved < /dev/tty || saved=""
        case "$saved" in y|Y|yes) PKG_MODE=yes ;; *) PKG_MODE=no ;; esac
        PKG_NOTE="answered now; saved at the end of the run"; PKG_ASKED=1
    fi
    return 0
}

repo_line() {
    local branch commit state
    branch="$(git_in "$DOTFILES_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    commit="$(git_in "$DOTFILES_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
    if [ -z "$(git_in "$DOTFILES_DIR" status --porcelain 2>/dev/null)" ]; then state=clean
    else state="uncommitted changes"; fi
    printf '%s | %s @ %s | %s\n' "$(tildify "$DOTFILES_DIR")" "$branch" "$commit" "$state"
}

wants() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

# git_in <dir> <git args...>: git run inside a folder. "git -C" needs git 1.8.5;
# CentOS 7 ships 1.8.3, so this works everywhere.
git_in() { local dir="$1"; shift; (cd "$dir" && git "$@"); }

# git_at_least <major> <minor>: is the installed git at least that version?
git_at_least() {
    local v maj min
    v="$(git --version 2>/dev/null | awk '{ print $3 }')"
    maj="${v%%.*}"; v="${v#*.}"; min="${v%%.*}"
    case "$maj$min" in *[!0-9]*|"") return 1 ;; esac
    [ "$maj" -gt "$1" ] || { [ "$maj" -eq "$1" ] && [ "$min" -ge "$2" ]; }
}

# bashrc_loads_aliases: does ~/.bashrc load ~/.bash_aliases (Ubuntu's default does)?
bashrc_loads_aliases() { [ -f "$HOME/.bashrc" ] && grep -q '\.bash_aliases' "$HOME/.bashrc"; }

# plural <count> <noun>: "1 line", "5 lines".
plural() { if [ "$1" = 1 ]; then printf '1 %s\n' "$2"; else printf '%s %ss\n' "$1" "$2"; fi; }

# ---------------------------------------------------------------- lists

# read_list <file>: lines without comments and blanks.
read_list() {
    [ -f "$1" ] || return 0
    sed -e 's/#.*$//' -e 's/[[:space:]]*$//' "$1" | grep -v '^[[:space:]]*$' || true
}

# pkg_name_for <list name>: the name on this platform, or "-" to skip.
pkg_name_for() {
    local hit
    hit="$(read_list "$DOTFILES_DIR/packages/map.txt" | awk -v n="$1" -v c="$PKG_COLUMN" '$1 == n { print $c; exit }')"
    printf '%s\n' "${hit:-$1}"
}

package_lines() {
    read_list "$DOTFILES_DIR/packages/common.txt"
    if [ "$PROFILE" != base ]; then read_list "$DOTFILES_DIR/packages/$PROFILE.txt"; fi
}

# link_lines: links.txt lines for this platform, as "repo live mechanism".
link_lines() {
    local repo live mech os
    read_list "$DOTFILES_DIR/links.txt" | while read -r repo live mech os; do
        [ -z "${os:-}" ] || [ "$os" = "$PLATFORM_OS" ] || continue
        printf '%s %s %s\n' "$repo" "$live" "$mech"
    done
    return 0
}

# ---------------------------------------------------------------- state of each kind of item

# link_state <repo path> <live path> <mechanism>: prints "state|detail".
link_state() {
    local src="$DOTFILES_DIR/$1" live="$2" mech="$3"
    if [ ! -e "$src" ]; then echo "repo-missing|$1"; return 0; fi
    case "$mech" in
        link|link:late)
            if [ -L "$live" ]; then
                if [ ! -e "$live" ]; then echo "broken|$(readlink "$live")"
                elif [ "$(resolve_path "$live")" = "$(resolve_path "$src")" ]; then echo "linked|"
                else echo "elsewhere|$(readlink "$live")"; fi
            elif [ -d "$live" ]; then echo "directory|"
            elif [ -f "$live" ]; then
                if cmp -s "$src" "$live"; then echo "identical|"; else echo "differs|"; fi
            elif [ -e "$live" ]; then echo "other|"
            else echo "missing|"; fi ;;
        stub:*)
            if [ -L "$live" ]; then echo "stub-symlink|$(readlink "$live")"
            elif [ -f "$live" ]; then
                if grep -q '>>> dotfiles >>>' "$live"; then echo "stub-present|"
                else echo "stub-missing|$(wc -l < "$live" | tr -d ' ')"; fi
            elif [ -e "$live" ]; then echo "other|"
            else echo "stub-absent|"; fi ;;
        *) echo "bad-mechanism|$mech" ;;
    esac
}

# addon_state <url> <destination>: ok, missing, or "conflict|reason".
addon_state() {
    local url="$1" dest="$2" remote
    if [ ! -e "$dest" ]; then echo "missing|"; return 0; fi
    if [ ! -d "$dest/.git" ]; then echo "conflict|exists but is not a git clone"; return 0; fi
    remote="$(git_in "$dest" config --get remote.origin.url 2>/dev/null || true)"
    if [ "$(normalize_url "$remote")" = "$(normalize_url "$url")" ]; then echo "ok|"
    else echo "conflict|cloned from ${remote:-an unknown remote}"; fi
}
normalize_url() { local u="${1%/}"; printf '%s\n' "${u%.git}"; }

# vim_declared_plugins: plugin folder names the vimrc declares on this machine.
# vimrc loads some plugins only on a new enough vim, so vim itself is asked; the
# file is read instead (every Plugin line) until Vundle is there to answer.
vim_declared_plugins() {
    local out="${TMPDIR:-/tmp}/dotfiles-vimplugins.$$"
    rm -f "$out"
    if command -v vim >/dev/null 2>&1 && [ -f "$HOME/.vim/bundle/Vundle.vim/autoload/vundle.vim" ]; then
        vim -E -s -N -n -i NONE --cmd 'filetype on' -u "$DOTFILES_DIR/vim/vimrc" \
            -c "call writefile(map(copy(g:vundle#bundles), 'v:val.name'), '$out')" -c 'qa!' \
            < /dev/null > /dev/null 2>&1 || true
    fi
    if [ -s "$out" ]; then
        cat "$out"
    else
        sed -n "s/^[[:space:]]*Plugin '\([^']*\)'.*/\1/p" "$DOTFILES_DIR/vim/vimrc" | sed 's#.*/##'
    fi
    rm -f "$out"
    return 0
}

# plugin_missing <component>: names of declared plugins not yet installed.
plugin_missing() {
    local name
    case "$1" in
        vim)
            vim_declared_plugins | while read -r name; do
                [ -d "$HOME/.vim/bundle/$name" ] || printf '%s ' "$name"
            done ;;
        tmux)
            sed -n "s/^set -g @plugin '\([^']*\)'.*/\1/p" "$DOTFILES_DIR/tmux/tmux.conf" | while read -r name; do
                [ -d "$HOME/.tmux/plugins/${name##*/}" ] || printf '%s ' "${name##*/}"
            done ;;
    esac
    return 0
}

# ---------------------------------------------------------------- reporting each kind of item

show_packages() {
    local first app kind name state
    while read -r first app; do
        [ -n "$first" ] || continue
        case "$first" in
            cask:*) kind=cask; name="${first#cask:}" ;;
            *)      kind=formula; name="$first" ;;
        esac
        CURRENT_ACTION="pkg_installed $name"
        state="$(pkg_installed "$kind" "$name" "${app:-}")"
        case "$state" in
            ok)      item ok "$name" ;;
            outside) item ok "$name (installed outside Homebrew, left as is)" ;;
            skip)    item skip "$name (not for this platform)" ;;
            unknown|missing)
                if [ "$PKG_MODE" = no ]; then
                    item skip "$name (not installed; package installs are off here)"
                elif [ "$READ_ONLY" = 1 ]; then
                    if [ "$state" = unknown ]; then item todo "$name (cannot query packages here)"; else item todo "$name"; fi
                    [ "$DRY_RUN" = 1 ] && pkg_install "$kind" "$name"
                else
                    CURRENT_ACTION="pkg_install $name"
                    pkg_install "$kind" "$name"
                    record installed "$name"
                    done_item "$name installed"
                fi ;;
        esac
    done <<EOF
$(package_lines)
EOF
    [ -z "${PKG_AFTER_NOTE:-}" ] || note "$PKG_AFTER_NOTE"
    CURRENT_ACTION=""
    return 0
}

show_addons() {
    local comp url dest live state
    while read -r comp url dest; do
        [ -n "$comp" ] || continue
        wants "$comp" || continue
        live="$(expand_home "$dest")"
        CURRENT_ACTION="addon $comp $(tildify "$live")"
        state="$(addon_state "$url" "$live")"
        case "${state%%|*}" in
            ok)       item ok "$(tildify "$live")" ;;
            missing)  if [ "$READ_ONLY" = 1 ]; then
                          item todo "$(tildify "$live") (not cloned)"
                          [ "$DRY_RUN" = 1 ] && cmd_line "git clone --depth 1 $url $(tildify "$live")"
                      else
                          clone_addon "$url" "$live"
                          done_item "$(tildify "$live") cloned"
                      fi ;;
            conflict) item warn "$(tildify "$live") ${state#*|}; left alone" ;;
        esac
    done <<EOF
$(read_list "$DOTFILES_DIR/addons.txt")
EOF
    CURRENT_ACTION=""
    return 0
}

# show_links <which>: all, early (link and stub) or late (link:late).
show_links() {
    local which="$1" repo live mech comp path state detail shown=0
    while read -r repo live mech; do
        [ -n "$repo" ] || continue
        comp="${repo%%/*}"
        wants "$comp" || continue
        case "$which:$mech" in early:link:late|late:link|late:stub:*) continue ;; esac
        shown=1
        path="$(expand_home "$live")"
        if [ "$path" = "$HOME/.bash_aliases" ] && ! bashrc_loads_aliases; then
            item skip "$(tildify "$path"): ~/.bashrc does not load it, so the stub goes in ~/.bashrc"
            path="$HOME/.bashrc"
        fi
        CURRENT_ACTION="link_state $repo"
        state="$(link_state "$repo" "$path" "$mech")"
        detail="${state#*|}"; state="${state%%|*}"
        if [ "$READ_ONLY" = 1 ]; then
            show_link_state "$repo" "$path" "$mech" "$state" "$detail"
        else
            act_link_state "$repo" "$path" "$mech" "$state" "$detail"
        fi
    done <<EOF
$(link_lines)
EOF
    [ "$shown" = 1 ] || item skip "nothing selected"
    CURRENT_ACTION=""
    return 0
}

show_link_state() {
    local repo="$1" path="$2" mech="$3" state="$4" detail="$5" t
    t="$(tildify "$path")"
    case "$state" in
        linked)       item ok "$t (linked to $repo)" ;;
        stub-present) item ok "$t (stub present)" ;;
        missing)      item todo "$t (missing)"
                      if [ "$DRY_RUN" = 1 ]; then
                          if [ ! -d "$(dirname "$path")" ]; then
                              if [ "$mech" = link:late ]; then note "(its folder comes from the plugin install in step 6)"
                              else cmd_line "mkdir -p $(tildify "$(dirname "$path")")"; fi
                          fi
                          cmd_line "ln -s $repo $t"
                      fi ;;
        identical)    item todo "$t (same as $repo, not linked yet)"
                      [ "$DRY_RUN" = 1 ] && cmd_line "back up $t, then ln -s $repo $t" ;;
        differs)      item ask "$t (differs from $repo)"
                      if [ "$DRY_RUN" = 1 ]; then
                          note "a real run asks: keep repo / take live / merge by hand / skip"
                      else
                          show_diff "$DOTFILES_DIR/$repo" "$path" "$repo" "$t"
                      fi ;;
        elsewhere)    item ask "$t (links elsewhere: $(tildify "$detail"))" ;;
        broken)       item warn "$t (broken link to $(tildify "$detail")); left alone" ;;
        stub-missing) item todo "$t (no stub yet; keeps its $(plural "$detail" line) below the stub)"
                      [ "$DRY_RUN" = 1 ] && cmd_line "back up $t, then add the ${mech#stub:} stub block at the top" ;;
        stub-absent)  item todo "$t (missing; would be created with the stub)"
                      [ "$DRY_RUN" = 1 ] && cmd_line "create $t with the ${mech#stub:} stub block" ;;
        stub-symlink) item warn "$t (is a symlink to $(tildify "$detail"); stub files must be regular files)" ;;
        directory)    item warn "$t (is a directory); left alone" ;;
        other)        item warn "$t (not a regular file); left alone" ;;
        repo-missing) item FAIL "$t (repo file $detail is missing)" ;;
        *)            item FAIL "$t (unknown state: $state $detail)" ;;
    esac
    return 0
}

show_diff() {
    # show_diff <repo file> <live file> <repo label> <live label>
    local out total
    out="$(diff -u -L "repo: $3" -L "live: $4" "$1" "$2" || true)"
    total="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
    printf '%s\n' "$out" | head -n 30 | sed 's/^/          /'
    [ "$total" -le 30 ] || note "  ($((total - 30)) more diff lines)"
    return 0
}

show_plugins() {
    local comp missing runner
    for comp in vim tmux; do
        wants "$comp" || continue
        missing="$(plugin_missing "$comp")"
        # shellcheck disable=SC2088  # the runner is printed, not run
        case "$comp" in
            vim)  runner="vim +PluginInstall +qall" ;;
            tmux) runner="~/.tmux/plugins/tpm/bin/install_plugins" ;;
        esac
        if [ -z "$missing" ]; then item ok "$comp plugins"
        elif [ "$READ_ONLY" = 1 ]; then
            item todo "$comp plugins missing: ${missing% }"
            [ "$DRY_RUN" = 1 ] && cmd_line "$runner"
        elif [ -n "${DOTFILES_TEST_NO_PLUGINS:-}" ]; then
            item skip "$comp plugins: not installed in tests"
        else
            CURRENT_ACTION="$comp plugins: ${missing% }"
            if [ "$comp" = vim ]; then install_vim_plugins; else install_tmux_plugins; fi
        fi
    done
    return 0
}

# show_bootstrap: step 2, unless this machine does not install packages.
show_bootstrap() {
    if [ "$PKG_MODE" = no ] && [ "$PKG_MANAGER" != none ]; then
        item skip "package installs: off ($PKG_NOTE)"
        return 0
    fi
    pkg_bootstrap
}

show_private() {
    if ! wants private && ! wants git; then return 0; fi
    if [ "$PROFILE" = personal ]; then
        item skip "private layer and git identities: built in phase 5"
    else
        item skip "private layer: not used by the $PROFILE profile"
    fi
}

# show_git_identity: with user.useConfigOnly on (from git/gitconfig), git refuses to
# commit without an identity. Say so before it surprises anyone.
show_git_identity() {
    local only email folders
    wants git || return 0
    # Asked from / so per-folder includeIf rules for the current directory do not count.
    only="$(git_in / config --global --includes --get user.useConfigOnly 2>/dev/null || true)"
    email="$(git_in / config --global --includes --get user.email 2>/dev/null || true)"
    folders="$(git config --global --get-regexp '^includeif\.' 2>/dev/null | wc -l | tr -d ' ')"
    if [ -n "$email" ]; then
        item ok "git identity: a default is set in ~/.gitconfig"
    elif [ "$folders" -gt 0 ]; then
        item ok "git identity: set per folder ($(plural "$folders" "includeIf rule"))"
    elif [ "$only" = true ]; then
        item warn "git identity: none set, so git refuses to commit (user.useConfigOnly)"
        if [ "$PROFILE" = personal ]; then note "the personal identities come with the private layer (phase 5)"
        else note "set one: git config --global user.name \"...\"; git config --global user.email \"...\""; fi
    else
        item skip "git identity: none set (user.useConfigOnly not active yet)"
    fi
    return 0
}

show_hook() {
    if ! git_at_least 2 9; then
        item skip "pre-commit hook: needs git 2.9 or newer (this is $(git --version 2>/dev/null | awk '{ print $3 }')); not used here"
        return 0
    fi
    if [ "$(git_in "$DOTFILES_DIR" config --get core.hooksPath 2>/dev/null || true)" = hooks ]; then
        item ok "pre-commit hook turned on for this clone"
    else
        if [ "$READ_ONLY" = 1 ]; then
            item todo "pre-commit hook not turned on for this clone"
            [ "$DRY_RUN" = 1 ] && cmd_line "cd $(tildify "$DOTFILES_DIR") && git config core.hooksPath hooks"
        else
            enable_hook
        fi
    fi
    return 0
}

# ---------------------------------------------------------------- modes

preflight() {
    echo "dotfiles install.sh --$MODE"
    echo "  platform : $(platform_line)"
    echo "  profile  : $PROFILE ($PROFILE_NOTE)"
    if [ -n "$PKG_MODE" ] && [ "$LINK_ONLY" = 0 ]; then
        # (a case inside $( ) trips a bash 3.2 parser bug, so the text is picked first)
        local what="install missing"
        [ "$PKG_MODE" = no ] && what="use what is installed"
        [ "$PKG_MODE" = ask ] && what="to be asked"
        echo "  packages : $what ($PKG_NOTE)"
    fi
    echo "  repo     : $(repo_line)"
    echo "  selected : ${ONLY:-all components}"
}

summary() {
    local r
    echo
    if [ "$READ_ONLY" = 1 ]; then
        printf 'Summary: ok %d, todo %d, ask %d, warn %d, FAIL %d, skip %d\n' \
            "$N_OK" "$N_TODO" "$N_ASK" "$N_WARN" "$N_FAIL" "$N_SKIP"
        if [ "$DRY_RUN" = 1 ]; then
            echo "A real run would make $N_TODO changes and ask $N_ASK questions. Nothing was changed."
        else
            echo "Nothing was changed."
        fi
        return 0
    fi
    printf 'Summary: done %d, ok %d, warn %d, skip %d\n' "$N_DONE" "$N_OK" "$N_WARN" "$N_SKIP"
    if [ -s "$MANIFEST" ]; then
        echo "Backup and manifest: $(tildify "$RUN_DIR")"
        echo "Undo this run:       ./install.sh --restore $RUN_ID"
    elif [ "$N_DONE" -gt 0 ]; then
        echo "Nothing to undo: this run only downloaded plugins."
    else
        echo "Nothing needed changing."
    fi
    if [ -n "$REPO_CHANGES" ]; then
        echo "The repo has changes to review and commit:"
        for r in $REPO_CHANGES; do echo "  $r"; done
    fi
    echo "Log: $(tildify "$LOG_FILE")"
}

mode_check() {
    preflight
    if wants packages; then
        section "Package manager"; show_bootstrap
        section "Packages";        show_packages
    fi
    section "Add-ons";        show_addons
    section "Managed files";  show_links all
    section "Plugins";        show_plugins
    section "Private layer and git identity"; show_private; show_git_identity
    section "This clone";     show_hook
    summary
}

mode_dry_run() {
    step 1 "Preflight"; preflight | sed 's/^/  /'; check_subshell_failure
    if wants packages && [ "$LINK_ONLY" = 0 ]; then
        step 2 "Package manager"; show_bootstrap
        step 3 "Packages";        show_packages
    else
        step 2 "Package manager"; item skip "not selected"
        step 3 "Packages";        item skip "not selected"
    fi
    if [ "$LINK_ONLY" = 0 ]; then step 4 "Add-ons"; show_addons
    else step 4 "Add-ons"; item skip "--link-only"; fi
    step 5 "Links and stubs";     show_links early
    if [ "$LINK_ONLY" = 0 ]; then step 6 "Plugins"; show_plugins
    else step 6 "Plugins"; item skip "--link-only"; fi
    step 7 "Late links";          show_links late
    step 8 "Private layer and git identities"; show_private; show_git_identity
    step 9 "Finish";              show_hook
    [ "$READ_ONLY" = 1 ] || { save_profile; save_packages_mode; }
    summary
}

# A real run follows the same nine steps; the show_* functions act when READ_ONLY=0.
mode_install() {
    confirm_run
    mode_dry_run
}

mode_report() {
    {
        echo "==================== dotfiles: REPORT ===================="
        # Only tools known not to write anything when asked for a version.
        # (glow, for one, creates config files in the home folder on any run.)
        echo "tool versions:"
        local v
        v="$(git --version 2>/dev/null || true)";                  printf '  %-5s %s\n' git "${v:-not found}"
        v="$(vim --version 2>/dev/null | head -n 1 || true)";      printf '  %-5s %s\n' vim "${v:-not found}"
        v="$(tmux -V 2>/dev/null || true)";                        printf '  %-5s %s\n' tmux "${v:-not found}"
        printf '  %-5s %s\n' bash "$BASH_VERSION (running); login shell: ${SHELL:-unknown}"
        echo
        mode_check
        echo
        report_latest_log
        echo "==========================================================="
    } | redact
    check_subshell_failure
}

report_latest_log() {
    local latest
    local f
    latest=""
    for f in "$HOME/.local/state/dotfiles"/install-*.md; do [ -e "$f" ] && latest="$f"; done   # timestamps: last is newest
    if [ -z "$latest" ]; then echo "install logs: none yet"; return 0; fi
    echo "latest install log: $(tildify "$latest")"
    if grep -q 'dotfiles: FAILED' "$latest"; then
        sed -n '/dotfiles: FAILED/,/^=========================/p' "$latest"
    else
        echo "  (it finished without a failure)"
    fi
}

main() {
    trap on_error ERR
    parse_args "$@"
    detect_platform
    # shellcheck source=/dev/null
    . "$DOTFILES_DIR/lib/platform/$PLATFORM.sh"
    resolve_profile
    case "$MODE" in check|dry-run|report|install|link-only) resolve_packages_mode ;; esac

    if [ "$VERBOSE" = 1 ]; then
        TRACE_FILE="${TMPDIR:-/tmp}/dotfiles-trace.$(date +%Y%m%d-%H%M%S).log"
        exec 2>"$TRACE_FILE"
        PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
        set -x
    fi

    case "$MODE" in
        check)   mode_check ;;
        dry-run) mode_dry_run ;;
        report)  mode_report ;;
        install|link-only|adopt|restore|update-addons|uninstall-hooks)
            start_run
            case "$MODE" in
                install|link-only) run_logged mode_install ;;
                adopt)             run_logged run_confirmed mode_adopt ;;
                restore)           run_logged run_confirmed mode_restore ;;
                update-addons)     run_logged run_confirmed mode_update_addons ;;
                uninstall-hooks)   run_logged mode_uninstall_hooks ;;
            esac ;;
    esac

    if [ "$VERBOSE" = 1 ]; then
        set +x
        echo "trace written to $(tildify "$TRACE_FILE")"
    fi
    rm -f "$ERR_FILE"
    return 0
}
