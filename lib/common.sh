# lib/common.sh - shared logic for install.sh. See docs/DESIGN.md.
# shellcheck shell=bash
#
# bash 3.2 compatible: no associative arrays, ${var,,}, mapfile or readarray.
# Commands whose flags differ between BSD and GNU go through lib/platform/*.sh.
#
# Phase 2: only the read-only modes (--check, --dry-run, --report) exist.

set -Eeu

STEPS=9
MODE=""
DRY_RUN=0
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

tildify() {
    case "$1" in
        "$HOME")   printf '~\n' ;;
        "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;;
        *)         printf '%s\n' "$1" ;;
    esac
}
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
Usage: ./install.sh MODE [options]

Modes (phase 2: read-only only, nothing is changed):
  --check        show how this machine differs from the repo
  --dry-run      show every step and command a real run would take
  --report       one redacted block to paste into a chat

Options:
  --profile base|personal|office   default: saved profile, else base
  --only packages|vim|tmux|shell|git|task|private
  --platform macos|debian          override detection (for testing)
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

not_built_yet() {
    echo "install.sh: $1 is part of the write path, which is built in phase 3." >&2
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
    rm -f "$ERR_FILE"
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
        echo "next      : paste this block into the chat, or run ./install.sh --report"
        echo "==========================================================="
    } | redact
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
            -h|--help)  usage; exit 0 ;;
            --yes|--link-only|--adopt|--as|--update-addons|--restore|--uninstall-hooks)
                die_usage "$1 belongs to the write path, which is built in phase 3" ;;
            *) die_usage "unknown option: $1" ;;
        esac
        shift
    done
    [ -n "$MODE" ] || die_usage "choose a mode: --check, --dry-run or --report"
    case "${PROFILE:-base}" in base|personal|office) ;; *) die_usage "unknown profile: $PROFILE" ;; esac
    if [ -n "$ONLY" ] && ! in_list "$ONLY" "$(printf '%s\n' $COMPONENTS)"; then
        die_usage "unknown component for --only: $ONLY (one of: $COMPONENTS)"
    fi
    case "$PLATFORM" in ""|macos|debian) ;; *) die_usage "unknown platform: $PLATFORM" ;; esac
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
                id="$(. /etc/os-release; printf '%s' "${ID:-}")"
                id_like="$(. /etc/os-release; printf '%s' "${ID_LIKE:-}")"
                case " $id $id_like " in
                    *" debian "*|*" ubuntu "*) PLATFORM=debian ;;
                esac
            fi ;;
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
    case "$PLATFORM" in
        macos)  release="macOS $(sw_vers -productVersion 2>/dev/null || echo '?')" ;;
        debian) release="$( (. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-}") || true)" ;;
    esac
    printf '%s | %s | %s | bash %s\n' "$PLATFORM" "${release:-unknown release}" "$(uname -m)" "${BASH_VERSION%%(*}"
}

repo_line() {
    local branch commit state
    branch="$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    commit="$(git -C "$DOTFILES_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
    if [ -z "$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null)" ]; then state=clean
    else state="uncommitted changes"; fi
    printf '%s | %s @ %s | %s\n' "$(tildify "$DOTFILES_DIR")" "$branch" "$commit" "$state"
}

wants() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

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
    remote="$(git -C "$dest" config --get remote.origin.url 2>/dev/null || true)"
    if [ "$(normalize_url "$remote")" = "$(normalize_url "$url")" ]; then echo "ok|"
    else echo "conflict|cloned from ${remote:-an unknown remote}"; fi
}
normalize_url() { local u="${1%/}"; printf '%s\n' "${u%.git}"; }

# plugin_missing <component>: names of declared plugins not yet installed.
plugin_missing() {
    local name
    case "$1" in
        vim)
            sed -n "s/^Plugin '\([^']*\)'.*/\1/p" "$DOTFILES_DIR/vim/vimrc" | while read -r name; do
                [ -d "$HOME/.vim/bundle/${name##*/}" ] || printf '%s ' "${name##*/}"
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
            unknown) item todo "$name (cannot query packages here)"; [ "$DRY_RUN" = 1 ] && pkg_install "$kind" "$name" ;;
            missing) item todo "$name"; [ "$DRY_RUN" = 1 ] && pkg_install "$kind" "$name" ;;
        esac
    done <<EOF
$(package_lines)
EOF
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
            missing)  item todo "$(tildify "$live") (not cloned)"
                      [ "$DRY_RUN" = 1 ] && cmd_line "git clone --depth 1 $url $(tildify "$live")" ;;
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
        CURRENT_ACTION="link_state $repo"
        state="$(link_state "$repo" "$path" "$mech")"
        detail="${state#*|}"; state="${state%%|*}"
        show_link_state "$repo" "$path" "$mech" "$state" "$detail"
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
                          [ -d "$(dirname "$path")" ] || cmd_line "mkdir -p $(tildify "$(dirname "$path")")"
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
        case "$comp" in
            vim)  runner="vim +PluginInstall +qall" ;;
            tmux) runner="~/.tmux/plugins/tpm/bin/install_plugins" ;;
        esac
        if [ -z "$missing" ]; then item ok "$comp plugins"
        else
            item todo "$comp plugins missing: ${missing% }"
            [ "$DRY_RUN" = 1 ] && cmd_line "$runner"
        fi
    done
    return 0
}

show_private() {
    if ! wants private && ! wants git; then return 0; fi
    if [ "$PROFILE" = personal ]; then
        item skip "private layer and git identities: built in phase 5"
    else
        item skip "private layer: not used by the $PROFILE profile"
    fi
}

show_hook() {
    if [ "$(git -C "$DOTFILES_DIR" config --get core.hooksPath 2>/dev/null || true)" = hooks ]; then
        item ok "pre-commit hook turned on for this clone"
    else
        item todo "pre-commit hook not turned on for this clone"
        [ "$DRY_RUN" = 1 ] && cmd_line "git -C $(tildify "$DOTFILES_DIR") config core.hooksPath hooks"
    fi
}

# ---------------------------------------------------------------- modes

preflight() {
    echo "dotfiles install.sh --$MODE"
    echo "  platform : $(platform_line)"
    echo "  profile  : $PROFILE ($PROFILE_NOTE)"
    echo "  repo     : $(repo_line)"
    echo "  selected : ${ONLY:-all components}"
}

summary() {
    echo
    printf 'Summary: ok %d, todo %d, ask %d, warn %d, FAIL %d, skip %d\n' \
        "$N_OK" "$N_TODO" "$N_ASK" "$N_WARN" "$N_FAIL" "$N_SKIP"
    case "$MODE" in
        dry-run) echo "A real run would make $N_TODO changes and ask $N_ASK questions. Nothing was changed." ;;
        *)       echo "Nothing was changed." ;;
    esac
}

mode_check() {
    preflight
    if wants packages; then section "Packages"; show_packages; fi
    section "Add-ons";        show_addons
    section "Managed files";  show_links all
    section "Plugins";        show_plugins
    section "Private layer";  show_private
    section "This clone";     show_hook
    summary
}

mode_dry_run() {
    step 1 "Preflight"; preflight | sed 's/^/  /'; check_subshell_failure
    if wants packages; then
        step 2 "Package manager"; pkg_bootstrap
        step 3 "Packages";        show_packages
    else
        step 2 "Package manager"; item skip "not selected"
        step 3 "Packages";        item skip "not selected"
    fi
    step 4 "Add-ons";             show_addons
    step 5 "Links and stubs";     show_links early
    step 6 "Plugins";             show_plugins
    step 7 "Late links";          show_links late
    step 8 "Private layer and git identities"; show_private
    step 9 "Finish";              show_hook
    summary
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
        MODE=check
        mode_check
        MODE=report
        echo
        echo "install logs: none yet (logs start with the write path in phase 3)"
        echo "==========================================================="
    } | redact
    check_subshell_failure
}

main() {
    trap on_error ERR
    parse_args "$@"
    detect_platform
    # shellcheck source=/dev/null
    . "$DOTFILES_DIR/lib/platform/$PLATFORM.sh"
    resolve_profile

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
    esac

    if [ "$VERBOSE" = 1 ]; then
        set +x
        echo "trace written to $(tildify "$TRACE_FILE")"
    fi
    rm -f "$ERR_FILE"
    return 0
}
