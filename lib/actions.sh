# lib/actions.sh - the write path of install.sh: everything that changes a machine.
# shellcheck shell=bash
#
# Every change is recorded in the run's manifest, and every file replaced or
# edited is backed up first, so --restore can undo a run (docs/DESIGN.md,
# Safety). bash 3.2 compatible.

STATE_DIR="$HOME/.local/state/dotfiles"
RUN_ID=""
RUN_DIR=""
MANIFEST=""
LOG_FILE=""
RAW_LOG=""
ASSUME_YES=0
N_DONE=0
REPO_CHANGES=""

# ---------------------------------------------------------------- runs, logs, manifest

start_run() {
    mkdir -p "$STATE_DIR/backup"
    RUN_ID="$(date +%Y%m%d-%H%M%S)"
    if [ -e "$STATE_DIR/backup/$RUN_ID" ]; then RUN_ID="$RUN_ID-$$"; fi
    RUN_DIR="$STATE_DIR/backup/$RUN_ID"      # created on the first change only
    MANIFEST="$RUN_DIR/manifest.txt"
    LOG_FILE="$STATE_DIR/install-$RUN_ID.md"
    RAW_LOG="$STATE_DIR/.install-$RUN_ID.raw"
    rm -f "$ERR_FILE" "$ERR_FILE.cmd" "$ERR_FILE.out"
    return 0
}

# run_logged <function>: run it with output shown and saved; the log is redacted.
run_logged() {
    local rc
    : > "$RAW_LOG"
    set +e
    ( "$@" ) | tee -a "$RAW_LOG"
    rc=${PIPESTATUS[0]}
    set -e
    redact < "$RAW_LOG" > "$LOG_FILE"
    rm -f "$RAW_LOG"
    prune_logs
    check_subshell_failure          # a real failure: prints the failure block
    # A clean stop (stop_run) ends with its own message and exit code, no block.
    [ "$rc" = 0 ] || exit "$rc"
    return 0
}

# prune_logs: keep the 20 newest logs. Names are timestamps, so the glob's
# alphabetical order is also the time order, oldest first.
prune_logs() {
    local f total=0 n=0
    for f in "$STATE_DIR"/install-*.md; do [ -e "$f" ] && total=$((total + 1)); done
    for f in "$STATE_DIR"/install-*.md; do
        [ -e "$f" ] || continue
        n=$((n + 1))
        [ "$n" -gt $((total - 20)) ] || rm -f "$f"
    done
    return 0
}

# record <action> <path relative to $HOME> [extra]: one manifest line.
record() {
    mkdir -p "$RUN_DIR"
    printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$MANIFEST"
}

rel_of() { printf '%s\n' "${1#"$HOME"/}"; }

# "~" kept in a variable: bash 5 tilde-expands a literal ~ in the replacement of
# ${var//pattern/replacement}, which turned "~" back into the home path on Linux.
TILDE='~'
# home_to_tilde <text>: every occurrence of the home path shown as ~.
home_to_tilde() { printf '%s\n' "${1//"$HOME"/$TILDE}"; }

# backup_move <path>: move a file or link out of the way, into the run's backup.
backup_move() {
    local rel dst
    rel="$(rel_of "$1")"; dst="$RUN_DIR/files/$rel"
    mkdir -p "$(dirname "$dst")"
    mv "$1" "$dst"
    record moved "$rel"
}

# backup_copy <path>: keep a copy before editing a file in place.
backup_copy() {
    local rel dst
    rel="$(rel_of "$1")"; dst="$RUN_DIR/files/$rel"
    mkdir -p "$(dirname "$dst")"
    cp -p "$1" "$dst"
    record copied "$rel"
}

done_item() { N_DONE=$((N_DONE + 1)); printf '  %-5s %s\n' "done" "$1"; }

# ---------------------------------------------------------------- commands and prompts

# run_cmd <command...>: show it, stream its output indented, stop the run on failure.
run_cmd() {
    local out rc line shown="$*" cr
    cr="$(printf '\r')"
    cmd_line "$(home_to_tilde "$shown")"
    out="$STATE_DIR/.last-output.$$"
    set +e
    # Progress lines end in carriage returns; keep only what follows the last one.
    "$@" < /dev/null 2>&1 | tee "$out" | while IFS= read -r line; do
        line="${line##*"$cr"}"; line="${line//"$HOME"/$TILDE}"
        printf '          %s\n' "$line"
    done
    rc=${PIPESTATUS[0]}
    set -e
    if [ "$rc" -ne 0 ]; then
        home_to_tilde "$shown" > "$ERR_FILE.cmd"
        tail -n 20 "$out" > "$ERR_FILE.out" 2>/dev/null || true
    fi
    rm -f "$out"
    return "$rc"
}

# run_interactive <command...>: for commands that talk to the terminal (sudo -v).
run_interactive() {
    local shown="$*"
    cmd_line "$(home_to_tilde "$shown")"
    "$@" < /dev/tty
}

# has_tty: can we ask questions? DOTFILES_NO_TTY=1 (set by tests/run.sh) says no,
# so a test can never reach a prompt, even when run from a terminal.
has_tty() { [ -z "${DOTFILES_NO_TTY:-}" ] && (exec < /dev/tty) 2>/dev/null; }

# stop_run <message>: end the run cleanly, without the failure block.
stop_run() {
    echo
    echo "install.sh: $1"
    [ -n "$RUN_DIR" ] && [ -d "$RUN_DIR" ] && echo "Changes so far are in the backup; undo them with: ./install.sh --restore $RUN_ID"
    exit 1
}

# ask <question> <letters> <answer with --yes>: prints the chosen letter.
ask() {
    local answer
    if [ "$ASSUME_YES" = 1 ]; then printf '%s\n' "$3"; return 0; fi
    while :; do
        printf '        %s ' "$1" > /dev/tty
        read -r answer < /dev/tty || answer=""
        case "$answer" in
            [$2]) printf '%s\n' "$answer"; return 0 ;;
        esac
    done
}

# can_ask: questions need a terminal or --yes.
can_ask() {
    [ "$ASSUME_YES" = 1 ] && return 0
    has_tty && return 0
    stop_run "a question needs an answer, but there is no terminal. Re-run in a terminal, or with --yes (keeps the repo version; your file goes to the backup)."
}

confirm_run() {
    local answer
    [ "$ASSUME_YES" = 1 ] && return 0
    has_tty || stop_run "this run changes the machine and needs a terminal to confirm. Re-run in a terminal, or add --yes."
    printf '\nThis run changes files in your home folder. Everything replaced is backed up first.\nContinue? [y/N] ' > /dev/tty
    read -r answer < /dev/tty || answer=""
    case "$answer" in y|Y|yes) return 0 ;; esac
    stop_run "stopped before changing anything."
}

# ---------------------------------------------------------------- stubs and links

# stub_text <kind> <repo path>: the marked block that loads the repo file.
stub_text() {
    local f="$DOTFILES_DIR/$2" shown
    case "$f" in
        "$HOME"/*) shown="\$HOME/${f#"$HOME"/}" ;;
        *)         shown="$f" ;;
    esac
    case "$1" in
        sh)        printf '# >>> dotfiles >>>\n[ -f "%s" ] && . "%s"\n# <<< dotfiles <<<\n' "$shown" "$shown" ;;
        gitconfig) printf '# >>> dotfiles >>>\n[include]\n\tpath = %s\n# <<< dotfiles <<<\n' "$f" ;;
        taskrc)    printf '# >>> dotfiles >>>\ninclude %s\n# <<< dotfiles <<<\n' "$f" ;;
        *)         return 1 ;;
    esac
}

# insert_stub <path> <kind> <repo path>: block at the top; the file keeps its inode.
insert_stub() {
    local tmp="$STATE_DIR/.stub.$$"
    backup_copy "$1"
    { stub_text "$2" "$3"; echo; cat "$1"; } > "$tmp"
    cat "$tmp" > "$1"
    rm -f "$tmp"
    record stubbed "$(rel_of "$1")"
}

# create_stub <path> <kind> <repo path>: a new file holding only the block.
create_stub() {
    local rel
    rel="$(rel_of "$1")"
    mkdir -p "$(dirname "$1")"
    stub_text "$2" "$3" > "$1"
    mkdir -p "$(dirname "$RUN_DIR/created/$rel")"
    cp -p "$1" "$RUN_DIR/created/$rel"
    record created "$rel"
}

# remove_block <path> <label>: delete the marked block "# >>> <label> >>>".
remove_block() {
    local start="# >>> $2 >>>" end="# <<< $2 <<<" tmp="$STATE_DIR/.unstub.$$"
    awk -v s="$start" -v e="$end" '
        $0 == s { skip = 1; next }
        skip && $0 == e { skip = 0; drop_blank = 1; next }
        skip { next }
        drop_blank && $0 == "" { drop_blank = 0; next }
        { drop_blank = 0; print }
    ' "$1" > "$tmp"
    cat "$tmp" > "$1"
    rm -f "$tmp"
}

# make_link <repo path> <live path>
make_link() {
    ln -s "$DOTFILES_DIR/$1" "$2"
    record linked "$(rel_of "$2")" "$DOTFILES_DIR/$1"
}

repo_file_dirty() { [ -n "$(git_in "$DOTFILES_DIR" status --porcelain -- "$1" 2>/dev/null)" ]; }

# resolve_differs <repo path> <live path>: the keep repo / take live / merge / skip question.
resolve_differs() {
    local repo="$1" path="$2" src="$DOTFILES_DIR/$1" t choice
    t="$(tildify "$path")"
    show_diff "$src" "$path" "$repo" "$t"
    can_ask
    while :; do
        choice="$(ask "$t differs from $repo: [k]eep repo / [t]ake live / [m]erge by hand / [s]kip?" ktms k)"
        case "$choice" in
            k)  backup_move "$path"; make_link "$repo" "$path"
                done_item "$t linked to $repo (your version is in the backup)"
                return 0 ;;
            t)  if repo_file_dirty "$repo"; then
                    note "$repo has uncommitted changes; taking the live version would lose them. Choose again."
                    continue
                fi
                cp "$path" "$src"
                backup_move "$path"; make_link "$repo" "$path"
                record took-live "$repo"
                REPO_CHANGES="$REPO_CHANGES $repo"
                done_item "$t taken into $repo and linked (review with git diff)"
                return 0 ;;
            m)  vimdiff "$src" "$path" < /dev/tty > /dev/tty
                if cmp -s "$src" "$path"; then
                    backup_move "$path"; make_link "$repo" "$path"
                    done_item "$t merged and linked to $repo"
                    REPO_CHANGES="$REPO_CHANGES $repo"
                    return 0
                fi
                note "the files still differ; choose again." ;;
            s)  item skip "$t (left as is)"
                return 0 ;;
        esac
    done
}

# act_link_state <repo> <path> <mechanism> <state> <detail>: the real-run action.
act_link_state() {
    local repo="$1" path="$2" mech="$3" state="$4" detail="$5" t choice
    t="$(tildify "$path")"
    case "$state" in
        linked)       item ok "$t (linked to $repo)" ;;
        stub-present) item ok "$t (stub present)" ;;
        missing)
            if [ "$mech" = link:late ] && [ ! -d "$(dirname "$path")" ]; then
                item warn "$t: $(tildify "$(dirname "$path")") is missing (plugin not installed?); not creating it"
                return 0
            fi
            mkdir -p "$(dirname "$path")"
            make_link "$repo" "$path"
            done_item "$t linked to $repo" ;;
        identical)
            backup_move "$path"; make_link "$repo" "$path"
            done_item "$t linked to $repo (was an identical copy)" ;;
        differs)
            item ask "$t (differs from $repo)"
            resolve_differs "$repo" "$path" ;;
        elsewhere)
            item ask "$t (links elsewhere: $(tildify "$detail"))"
            can_ask
            choice="$(ask "replace it with a link to $repo (the old link goes to the backup)? [r]eplace / [s]kip" rs r)"
            if [ "$choice" = r ]; then
                backup_move "$path"; make_link "$repo" "$path"
                done_item "$t linked to $repo"
            else
                item skip "$t (left as is)"
            fi ;;
        stub-missing)
            insert_stub "$path" "${mech#stub:}" "$repo"
            done_item "$t: stub added at the top (its $(plural "$detail" line) kept below)" ;;
        stub-absent)
            create_stub "$path" "${mech#stub:}" "$repo"
            done_item "$t created with the stub" ;;
        *)  show_link_state "$@" ;;
    esac
    return 0
}

# ---------------------------------------------------------------- add-ons, plugins, hook, profile

clone_addon() {
    mkdir -p "$(dirname "$2")"
    run_cmd git clone --depth 1 "$1" "$2"
    record cloned "$(rel_of "$2")"
}

install_vim_plugins() {
    if ! command -v vim >/dev/null 2>&1; then item warn "vim not found; vim plugins skipped"; return 0; fi
    if [ ! -d "$HOME/.vim/bundle/Vundle.vim" ]; then item warn "Vundle missing; vim plugins skipped"; return 0; fi
    # vim -E -s prints nothing, even on errors, and exits 1 on any error message.
    # -V1<file> writes vim's messages to a file, so a failure can show them.
    local vlog="$STATE_DIR/.vim-plugins.$$.log" ulog="$STATE_DIR/.vundle.$$.log" rc=0 still
    rm -f "$vlog" "$ulog"
    # "filetype on" first, as the system vimrc would: -u skips it, and vimrc's
    # "filetype off" then raises E216 on vim 7.4 (CentOS 7), which fails the run.
    # After PluginInstall, Vundle's own log (each git command and its output) is
    # written out, so a failed download can show why.
    local shim="" path="$PATH"
    if ! git_at_least 2 9; then
        # Vundle always clones with --shallow-submodules (git 2.9+). On older git
        # (CentOS 7: 1.8.3) every clone fails, so a stand-in git drops that one
        # option for this vim run and passes everything else to the real git.
        shim="$STATE_DIR/.git-shim.$$"
        mkdir -p "$shim"
        cat > "$shim/git" <<SHIM
#!/bin/sh
# Written by install.sh for one PluginInstall run; drops --shallow-submodules.
n=\$#
while [ "\$n" -gt 0 ]; do
    a="\$1"; shift; n=\$((n - 1))
    [ "\$a" = --shallow-submodules ] || set -- "\$@" "\$a"
done
exec "$(command -v git)" "\$@"
SHIM
        chmod +x "$shim/git"
        path="$shim:$PATH"
        note "git $(git --version | awk '{ print $3 }') lacks --shallow-submodules, which Vundle always passes; dropping it for this run"
    fi
    # PATH only for this call (a variable prefix on a function call is temporary in bash).
    PATH="$path" run_cmd vim -E -s --cmd 'filetype on' -u "$DOTFILES_DIR/vim/vimrc" "-V1$vlog" +PluginInstall \
        +"call writefile(get(g:, 'vundle#log', []), '$ulog')" +qall || rc=$?
    [ -z "$shim" ] || rm -rf "$shim"
    # vim 9 exits 0 even when a download failed, so check what is still missing.
    still="$(plugin_missing vim)"
    if [ -n "$still" ] && [ "$rc" = 0 ]; then rc=1; fi
    if [ "$rc" != 0 ]; then
        {
            [ -z "$still" ] || echo "still missing after PluginInstall: ${still% }"
            echo "vim errors (E185, the colour scheme not installed yet, left out):"
            grep -E 'E[0-9]+:|[Ee]rror|[Ff]ailed' "$vlog" 2>/dev/null | grep -v 'E185' | tail -n 10
            echo "Vundle's log, last lines (git commands and their output):"
            grep -v '^[[:space:]]*$' "$ulog" 2>/dev/null | tail -n 20
        } | while IFS= read -r line; do printf '          %s\n' "$(home_to_tilde "$line")"; done | tee -a "$ERR_FILE.out"
        rm -f "$vlog" "$ulog"
        return "$rc"
    fi
    rm -f "$vlog" "$ulog"
    done_item "vim plugins installed"
}

# TPM needs a tmux server. A private one (own socket) keeps any running tmux untouched.
install_tmux_plugins() {
    local sock="dotfiles-install-$$" conf="$HOME/.tmux.conf" spath rc=0
    local tpm="$HOME/.tmux/plugins/tpm/bin/install_plugins"
    if ! command -v tmux >/dev/null 2>&1; then item warn "tmux not found; tmux plugins skipped"; return 0; fi
    if [ ! -x "$tpm" ]; then item warn "TPM missing; tmux plugins skipped"; return 0; fi
    [ -e "$conf" ] || conf="$DOTFILES_DIR/tmux/tmux.conf"
    run_cmd tmux -L "$sock" -f "$conf" new-session -d -s dotfiles-install
    spath="$(tmux -L "$sock" display-message -p '#{socket_path}')"
    run_cmd env TMUX="$spath,0,0" "$tpm" || rc=$?
    tmux -L "$sock" kill-server 2>/dev/null || true
    [ -S "$spath" ] && rm -f "$spath"    # tmux can leave the socket file behind
    [ "$rc" = 0 ] || return "$rc"
    done_item "tmux plugins installed"
}

enable_hook() {
    local prev
    prev="$(git_in "$DOTFILES_DIR" config --get core.hooksPath 2>/dev/null || true)"
    git_in "$DOTFILES_DIR" config core.hooksPath hooks
    record hook "-" "${prev:-none}"
    done_item "pre-commit hook turned on for this clone"
}

save_profile() {
    local prev=none
    [ -r "$CONFIG_DIR/profile" ] && read -r prev < "$CONFIG_DIR/profile"
    [ "$prev" = "$PROFILE" ] && return 0
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$PROFILE" > "$CONFIG_DIR/profile"
    record profile "-" "$prev"
    done_item "profile '$PROFILE' saved in ~/.config/dotfiles/profile"
}

# save_packages_mode: remember an answer or a --packages/--no-packages flag.
save_packages_mode() {
    local prev=none
    [ "$PKG_ASKED" = 1 ] || [ -n "$PKG_FLAG" ] || return 0
    [ -r "$CONFIG_DIR/packages" ] && read -r prev < "$CONFIG_DIR/packages"
    [ "$prev" = "$PKG_MODE" ] && return 0
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$PKG_MODE" > "$CONFIG_DIR/packages"
    record packages "-" "$prev"
    done_item "package installs '$PKG_MODE' saved in ~/.config/dotfiles/packages"
}

# ---------------------------------------------------------------- restore

# latest_run: the newest run with a manifest that is not restored yet. Run names are
# timestamps, so the glob's order is the time order; the last match is the newest.
latest_run() {
    local d found=""
    for d in "$STATE_DIR"/backup/*/; do
        d="${d%/}"
        if [ -s "$d/manifest.txt" ] && [ ! -e "$d/restored" ]; then found="${d##*/}"; fi
    done
    [ -z "$found" ] || printf '%s\n' "$found"
    return 0
}

mode_restore() {
    local id="${RESTORE_ID:-}" dir action rel extra path tmpdir
    [ -n "$id" ] || id="$(latest_run)"
    [ -n "$id" ] || stop_run "no run to restore in ~/.local/state/dotfiles/backup."
    dir="$STATE_DIR/backup/$id"
    [ -s "$dir/manifest.txt" ] || stop_run "no manifest for run $id."
    [ ! -e "$dir/restored" ] || stop_run "run $id was already restored."
    section "Restore run $id"
    tmpdir="$RUN_DIR/files"    # anything restore moves aside goes to its own backup
    while IFS="$(printf '\t')" read -r action rel extra; do
        path="$HOME/$rel"
        case "$action" in
            linked)
                if [ -L "$path" ] && [ "$(readlink "$path")" = "$extra" ]; then
                    rm "$path"; done_item "$(tildify "$path"): link removed"
                else item warn "$(tildify "$path"): changed since the run; left as is"; fi ;;
            moved)
                if [ -e "$path" ] || [ -L "$path" ]; then
                    item warn "$(tildify "$path") exists; the old version stays in $(tildify "$dir/files/$rel")"
                else
                    mkdir -p "$(dirname "$path")"; mv "$dir/files/$rel" "$path"
                    done_item "$(tildify "$path") put back"
                fi ;;
            stubbed|edited)
                if [ -f "$path" ]; then
                    remove_block "$path" "$( [ "$action" = edited ] && echo 'dotfiles: Homebrew' || echo dotfiles)"
                    done_item "$(tildify "$path"): dotfiles block removed"
                fi ;;
            created)
                if [ -f "$path" ] && cmp -s "$path" "$dir/created/$rel"; then
                    rm "$path"; done_item "$(tildify "$path") removed (it only held the stub)"
                elif [ -f "$path" ]; then
                    remove_block "$path" dotfiles
                    done_item "$(tildify "$path"): dotfiles block removed; your later lines kept"
                fi ;;
            cloned)
                if [ -d "$path" ]; then
                    mkdir -p "$(dirname "$tmpdir/$rel")"; mv "$path" "$tmpdir/$rel"; record moved-aside "$rel"
                    done_item "$(tildify "$path") moved to $(tildify "$tmpdir/$rel")"
                fi ;;
            hook)
                if [ "$extra" = none ]; then git_in "$DOTFILES_DIR" config --unset core.hooksPath || true
                else git_in "$DOTFILES_DIR" config core.hooksPath "$extra"; fi
                done_item "pre-commit hook setting restored" ;;
            profile)
                if [ "$extra" = none ]; then rm -f "$CONFIG_DIR/profile"
                else printf '%s\n' "$extra" > "$CONFIG_DIR/profile"; fi
                done_item "profile setting restored" ;;
            packages)
                if [ "$extra" = none ]; then rm -f "$CONFIG_DIR/packages"
                else printf '%s\n' "$extra" > "$CONFIG_DIR/packages"; fi
                done_item "package-install setting restored" ;;
            installed)
                item skip "package $rel stays installed (remove it by hand if unwanted)" ;;
            copied|took-live|adopted|moved-aside) ;;
        esac
    done <<EOF
$(awk '{ lines[NR] = $0 } END { for (i = NR; i > 0; i--) print lines[i] }' "$dir/manifest.txt")
EOF
    date > "$dir/restored"
    echo
    echo "Run $id restored. Its backup stays in $(tildify "$dir")."
}

# ---------------------------------------------------------------- adopt

mode_adopt() {
    local path rel repo t
    path="$ADOPT_PATH"
    case "$path" in /*) ;; *) path="$PWD/$path" ;; esac
    t="$(tildify "$path")"
    section "Adopt $t"
    case "$path" in "$HOME"/*) ;; *) stop_run "$t is not under your home folder." ;; esac
    [ -L "$path" ] && stop_run "$t is already a symlink."
    [ -f "$path" ] || stop_run "$t is not a regular file (directories are not supported yet)."
    rel="$(rel_of "$path")"
    # shellcheck disable=SC2088  # links.txt holds the literal text "~/..."
    if read_list "$DOTFILES_DIR/links.txt" | awk '{ print $2 }' | grep -qx "~/$rel"; then
        stop_run "$t is already managed in links.txt."
    fi
    case "/$rel" in
        /.zshrc|/.bashrc|/.bash_aliases|/.gitconfig|/.taskrc|/.zprofile|/.zshenv)
            stop_run "$t is a stub-managed or tool-owned file; move shared lines into the repo by hand instead." ;;
    esac
    if ! /bin/bash "$DOTFILES_DIR/hooks/pre-commit" --file "$path"; then
        stop_run "$t contains lines that look personal (above). Move them to the private layer or a local file first."
    fi
    repo="${ADOPT_AS:-${rel#.}}"
    if [ -e "$DOTFILES_DIR/$repo" ]; then
        if cmp -s "$DOTFILES_DIR/$repo" "$path"; then
            backup_move "$path"; make_link "$repo" "$path"
            done_item "$t linked to $repo (identical)"
        else
            item ask "$t (differs from $repo)"
            resolve_differs "$repo" "$path"
        fi
    else
        mkdir -p "$(dirname "$DOTFILES_DIR/$repo")"
        cp -p "$path" "$DOTFILES_DIR/$repo"
        cmp -s "$path" "$DOTFILES_DIR/$repo"
        backup_move "$path"; make_link "$repo" "$path"
        # shellcheck disable=SC2088  # written literally into links.txt
        printf '%-22s %-46s %s\n' "$repo" "~/$rel" link >> "$DOTFILES_DIR/links.txt"
        REPO_CHANGES="$REPO_CHANGES $repo links.txt"
        done_item "$t moved into $repo and linked; added to links.txt"
    fi
    record adopted "$rel" "$repo"
}

# ---------------------------------------------------------------- other write modes

mode_update_addons() {
    local comp url dest live
    section "Update add-ons"
    while read -r comp url dest; do
        [ -n "$comp" ] || continue
        wants "$comp" || continue
        live="$(expand_home "$dest")"
        if [ "$(addon_state "$url" "$live")" = "ok|" ]; then
            run_cmd git_in "$live" pull --ff-only
            done_item "$(tildify "$live") updated"
        else
            item skip "$(tildify "$live") (not a clone of $url)"
        fi
    done <<EOF
$(read_list "$DOTFILES_DIR/addons.txt")
EOF
}

mode_uninstall_hooks() {
    section "Pre-commit hook"
    if [ -n "$(git_in "$DOTFILES_DIR" config --get core.hooksPath 2>/dev/null || true)" ]; then
        git_in "$DOTFILES_DIR" config --unset core.hooksPath
        done_item "pre-commit hook turned off for this clone"
    else
        item ok "pre-commit hook was not turned on"
    fi
}
