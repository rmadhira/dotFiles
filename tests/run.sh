#!/usr/bin/env bash
#
# tests/run.sh - check install.sh against throwaway fake home folders.
#
# Every test runs install.sh with HOME pointing at a fresh temporary folder, so
# the real home folder is never read for state or touched. Run it with the
# oldest bash we support:  /bin/bash tests/run.sh
#
# bash 3.2 compatible. See docs/DESIGN.md.

# File-wide, so before the first command: expected output contains literal "~/"
# paths (SC2088), and ls picks logs and backups of a fresh fake home (SC2012).
# shellcheck disable=SC2088,SC2012

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# install.sh must never ask anything in a test, even when this runs in a terminal:
# with this set it behaves as if there were no terminal and stops instead of asking.
export DOTFILES_NO_TTY=1
PASS=0
FAIL=0
H=""

new_home() {
    [ -n "$H" ] && rm -rf "$H"
    H="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")"
    H="$(cd "$H" && pwd -P)"
}
cleanup() { [ -n "$H" ] && rm -rf "$H"; return 0; }
trap cleanup_copy EXIT

# run <args...>: install.sh output with the fake home; exit code in RC.
run() {
    case " $* " in *" --yes "*) echo "tests/run.sh: real runs use runc (a repo copy), not run" >&2; exit 1 ;; esac
    OUT="$(HOME="$H" /bin/bash "$REPO/install.sh" "$@" 2>&1)"
    RC=$?
}

pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
# git_in <dir> <args...>: git inside a folder, for git older than 1.8.5 (CentOS 7).
git_in() { local dir="$1"; shift; (cd "$dir" && git "$@"); }

# Real runs change the repo too (hook setting, --adopt), so they use a copy.
C=""
new_copy() {
    [ -n "$C" ] && rm -rf "$C"
    C="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-copy.XXXXXX")"; C="$(cd "$C" && pwd -P)"
    cp -R "$REPO/." "$C/"
    git_in "$C" config --unset core.hooksPath 2>/dev/null || true
}
# guard_real_run <args...>: a real run in a test may never reach packages (sudo, apt, brew).
guard_real_run() {
    case " $* " in *" --check "*|*" --dry-run "*|*" --report "*|*" --help "*) return 0 ;; esac
    case " $* " in
        *" --only vim "*|*" --only tmux "*|*" --only shell "*|*" --only git "*|*" --only task "*|\
        *" --link-only "*|*" --restore"*|*" --adopt "*|*" --as "*) return 0 ;;
    esac
    case " $* " in *" --yes "*) ;; *) return 0 ;; esac    # without --yes it stops before changes
    echo "tests/run.sh: refusing a real run that could install packages: install.sh $*" >&2
    exit 1
}
# runc <args...>: install.sh from the copy, fake home, no plugin installs, no terminal input.
runc() {
    guard_real_run "$@"
    OUT="$(HOME="$H" DOTFILES_TEST_NO_PLUGINS=1 /bin/bash "$C/install.sh" "$@" 2>&1 < /dev/null)"
    RC=$?
}
# check_file <label> <test...>: a file check; leaves OUT (the last install.sh output) alone.
check_file() {
    local label="$1"; shift
    if "$@"; then pass "$label"
    else FAIL=$((FAIL + 1)); printf '  FAIL  %s\n          | file check failed: %s\n' "$label" "$*"; fi
}
cleanup_copy() { [ -n "$C" ] && rm -rf "$C"; [ -n "${FAKEGIT_DIR:-}" ] && rm -rf "$FAKEGIT_DIR"; cleanup; }

# A fake git 1.8.3, as on CentOS 7: rejects -C and --shallow-submodules like the real one.
FAKEGIT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-oldgit.XXXXXX")"
cat > "$FAKEGIT_DIR/git" <<GIT
#!/bin/sh
[ "\$1" = --version ] && { echo "git version 1.8.3.1"; exit 0; }
for a in "\$@"; do
    [ "\$a" = -C ] && { echo "Unknown option: -C" >&2; exit 129; }
    [ "\$a" = --shallow-submodules ] && { echo "error: unknown option shallow-submodules" >&2; exit 129; }
done
exec "$(command -v git)" "\$@"
GIT
chmod +x "$FAKEGIT_DIR/git"
fail() {
    FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"
    printf '%s\n' "$OUT" | sed 's/^/          | /' | head -n 25
}

# expect <label> <extended regex>: the last output must match.
expect() {
    if printf '%s\n' "$OUT" | grep -Eq -- "$2"; then pass "$1"; else fail "$1 (wanted /$2/)"; fi
}
# expect_not <label> <extended regex>: the last output must not match.
expect_not() {
    if printf '%s\n' "$OUT" | grep -Eq -- "$2"; then fail "$1 (did not want /$2/)"; else pass "$1"; fi
}
expect_rc() {
    if [ "$RC" = "$2" ]; then pass "$1"; else fail "$1 (wanted exit $2, got $RC)"; fi
}

echo "install.sh tests with $(/bin/bash --version | head -n 1)"

echo
echo "usage"
new_home
run;                               expect_rc "no mode (a real run) without a profile: exit 2" 2; expect "asks for --profile" "add --profile"
run --check --dry-run;             expect_rc "two modes: exit 2" 2
run --check --only nope;           expect_rc "bad --only: exit 2" 2
run --check --profile work;        expect_rc "bad --profile: exit 2" 2
run --check --as x;                expect_rc "--as without --adopt: exit 2" 2
mkdir -p "$H/.config/dotfiles"; echo bogus > "$H/.config/dotfiles/profile"
run --check;                       expect_rc "bad saved profile: exit 2" 2
run --help;                        expect_rc "--help: exit 0" 0; expect "--help shows modes" "--dry-run"

echo
echo "profile"
new_home
run --check --only vim;            expect "no profile: base, assumed" "profile  : base \(assumed"
mkdir -p "$H/.config/dotfiles"; echo personal > "$H/.config/dotfiles/profile"
run --check --only vim;            expect "saved profile is read" "profile  : personal \(saved"
run --check --only vim --profile office; expect "--profile wins" "profile  : office \(from --profile\)"

echo
echo "managed files: symlinks"
new_home
run --check --only vim;            expect "missing" "todo  ~/.vimrc \(missing\)"
cp "$REPO/vim/vimrc" "$H/.vimrc"
run --check --only vim;            expect "identical" "todo  ~/.vimrc \(same as vim/vimrc"
cp "$REPO/vim/vimrc" "$H/.vimrc"; echo '" a local change' >> "$H/.vimrc"
run --check --only vim;            expect "differs" "ask   ~/.vimrc \(differs"; expect "differs shows a diff" '\+" a local change'
rm "$H/.vimrc"; ln -s "$REPO/vim/vimrc" "$H/.vimrc"
run --check --only vim;            expect "linked" "ok    ~/.vimrc \(linked to vim/vimrc\)"
rm "$H/.vimrc"; ln -s "$H/does-not-exist" "$H/.vimrc"
run --check --only vim;            expect "broken link" "warn  ~/.vimrc \(broken link"
rm "$H/.vimrc"; echo x > "$H/other"; ln -s "$H/other" "$H/.vimrc"
run --check --only vim;            expect "links elsewhere" "ask   ~/.vimrc \(links elsewhere: ~/other\)"
rm "$H/.vimrc"; mkdir "$H/.vimrc"
run --check --only vim;            expect "directory" "warn  ~/.vimrc \(is a directory\)"

echo
echo "managed files: stubs"
new_home
run --check --only git;            expect "stub file absent" "todo  ~/.gitconfig \(missing; would be created"
printf '[pull]\n\tff = only\n' > "$H/.gitconfig"
run --check --only git;            expect "no stub yet" "todo  ~/.gitconfig \(no stub yet; keeps its 2 lines"
printf '# >>> dotfiles >>>\n[include]\n# <<< dotfiles <<<\n' > "$H/.gitconfig"
run --check --only git;            expect "stub present" "ok    ~/.gitconfig \(stub present\)"
rm "$H/.gitconfig"; ln -s "$REPO/git/gitconfig" "$H/.gitconfig"
run --check --only git;            expect "stub file that is a symlink" "warn  ~/.gitconfig \(is a symlink"

echo
echo "shell hook: ~/.zshrc on macOS, ~/.bash_aliases on Linux"
new_home
run --check --only shell --platform macos
expect "macOS: zshrc managed" "~/.zshrc"
expect_not "macOS: zprofile left alone" "~/.zprofile"
expect_not "macOS: zshenv left alone" "~/.zshenv"
expect_not "macOS: no bash files" "~/.bash"
printf '# ~/.bashrc: Ubuntu default\nif [ -f ~/.bash_aliases ]; then\n    . ~/.bash_aliases\nfi\n' > "$H/.bashrc"
run --check --only shell --platform debian
expect "Linux: stub goes in ~/.bash_aliases" "todo  ~/.bash_aliases \(missing; would be created"
expect_not "Linux: ~/.bashrc left alone" "~/.bashrc \("
expect_not "Linux: no zshrc" "~/.zshrc"
echo "alias ll='ls -l'" > "$H/.bash_aliases"
run --check --only shell --platform debian
expect "Linux: existing ~/.bash_aliases keeps its lines" "todo  ~/.bash_aliases \(no stub yet; keeps its 1 line"
printf '# a ~/.bashrc that does not load the aliases file\n' > "$H/.bashrc"
run --check --only shell --platform debian
expect "Linux fallback: says why" "~/.bashrc does not load it, so the stub goes in ~/.bashrc"
expect "Linux fallback: ~/.bashrc gets the stub" "todo  ~/.bashrc \(no stub yet"

echo
echo "macOS: ~/.zprofile only gets Homebrew's line, and only when missing"
new_home
run --check --only packages --platform macos
expect "no ~/.zprofile: Homebrew line would be added" "~/.zprofile has no Homebrew line"
# shellcheck disable=SC2016  # Homebrew's line, written literally
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' > "$H/.zprofile"
run --check --only packages --platform macos
expect "Homebrew line present: left as is" "ok    ~/.zprofile loads Homebrew \(left as is\)"

echo
echo "every read-only mode, both platforms, packages selected"
new_home
for plat in macos debian; do
    for mode in --check --dry-run --report; do
        run "$mode" --only packages --platform "$plat"
        expect_rc "$plat $mode: exit 0" 0
    done
done

echo
echo "add-ons"
new_home
run --check --only vim;            expect "add-on missing" "todo  ~/.vim/bundle/Vundle.vim \(not cloned\)"
mkdir -p "$H/.vim/bundle/Vundle.vim"
run --check --only vim;            expect "add-on not a git clone" "warn  ~/.vim/bundle/Vundle.vim exists but is not a git clone"
git_in "$H/.vim/bundle/Vundle.vim" init -q
git_in "$H/.vim/bundle/Vundle.vim" remote add origin https://github.com/VundleVim/Vundle.vim
run --check --only vim;            expect "add-on from the declared URL" "ok    ~/.vim/bundle/Vundle.vim"
git_in "$H/.vim/bundle/Vundle.vim" remote set-url origin https://example.com/other.git
run --check --only vim;            expect "add-on from another URL" "warn  ~/.vim/bundle/Vundle.vim cloned from https://example.com/other.git"

echo
echo "plugins"
new_home
run --check --only tmux;           expect "tmux plugins missing" "todo  tmux plugins missing: tpm vim-tmux-navigator tmux"
mkdir -p "$H/.tmux/plugins/tpm" "$H/.tmux/plugins/vim-tmux-navigator" "$H/.tmux/plugins/tmux"
run --check --only tmux;           expect "tmux plugins present" "ok    tmux plugins"

echo
echo "vim plugins: vim decides which apply here (guards in vimrc)"
if command -v vim >/dev/null 2>&1; then
    new_home; new_copy
    # A copy of the vimrc with one more plugin behind a guard that is always false.
    awk '/^call vundle#end\(\)/ { print "if 0"; print "    Plugin '"'"'x/never-declared'"'"'"; print "endif" } { print }' \
        "$C/vim/vimrc" > "$C/vim/vimrc.new" && mv "$C/vim/vimrc.new" "$C/vim/vimrc"
    runc --check --only vim
    expect "no Vundle yet: every Plugin line counts" "vim plugins missing: .*never-declared"
    # A minimal stand-in for Vundle, enough for vim to report what the vimrc declares.
    mkdir -p "$H/.vim/bundle/Vundle.vim/autoload"
    cat > "$H/.vim/bundle/Vundle.vim/autoload/vundle.vim" <<'VIM'
let g:vundle#bundles = []
function! vundle#begin(...) abort
    command! -nargs=+ Plugin call add(g:vundle#bundles, {'name': split(eval(<q-args>), '/')[-1]})
endfunction
function! vundle#end(...) abort
endfunction
VIM
    runc --check --only vim
    expect "with Vundle: plugins still missing are listed" "vim plugins missing: .*vim-atom-dark"
    expect_not "with Vundle: a plugin behind a false guard is not expected" "never-declared"
else
    pass "vim not installed; vim guard checks skipped"
fi

echo
echo "vim plugins: a PluginInstall that downloads nothing is a failure"
if command -v vim >/dev/null 2>&1; then
    new_home; new_copy
    # Stand-in Vundle whose PluginInstall does nothing, like a download that failed
    # without vim reporting an error (vim 9 exits 0 then).
    mkdir -p "$H/.vim/bundle/Vundle.vim/autoload" "$H/.vim/bundle/Vundle.vim/.git"
    cat > "$H/.vim/bundle/Vundle.vim/autoload/vundle.vim" <<'VIM'
let g:vundle#bundles = []
let g:vundle#log = ['$ git clone --depth 1 --recursive --shallow-submodules ...', '> fatal: stand-in failure']
function! vundle#begin(...) abort
    command! -nargs=+ Plugin call add(g:vundle#bundles, {'name': split(eval(<q-args>), '/')[-1]})
    command! PluginInstall echo ''
endfunction
function! vundle#end(...) abort
endfunction
VIM
    guard_real_run --yes --profile base --only vim
    OUT="$(HOME="$H" PATH="$FAKEGIT_DIR:$PATH" /bin/bash "$C/install.sh" --yes --profile base --only vim 2>&1 < /dev/null)"; RC=$?
    expect_rc "plugins still missing: exit 1" 1
    expect "names the plugins still missing" "still missing after PluginInstall: .*vim-atom-dark"
    expect "shows Vundle's log" "fatal: stand-in failure"
    expect "old git: explains the --shallow-submodules workaround" "lacks --shallow-submodules, which Vundle always passes"
else
    pass "vim not installed; PluginInstall checks skipped"
fi

echo
echo "dry run"
new_home
run --dry-run --only vim;          expect_rc "dry run: exit 0" 0
expect "nine numbered steps" "\[9/9\] Finish"
expect "link command" "\+ ln -s vim/vimrc ~/.vimrc"
expect "clone command" "\+ git clone --depth 1 https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim"
expect "plugin command" "\+ vim \+PluginInstall \+qall"
expect "says nothing changed" "Nothing was changed"
new_copy
printf 'git\ndotfiles-no-such-package\ntaskopen\n' > "$C/packages/common.txt"
runc --dry-run --only packages --platform debian
expect "debian: one sudo prompt" "\+ sudo -v"
expect "debian: apt-get install, never asking" "\+ sudo env DEBIAN_FRONTEND=noninteractive .*NEEDRESTART_MODE=l .*apt-get install -y .* dotfiles-no-such-package$"
expect_not "debian: macOS-only package skipped" "apt-get install .* taskopen$"
run --dry-run --only packages --platform macos
expect "macOS: cask install" "\+ brew install --cask iterm2|ok    iterm2"

echo
echo "a clone with the pre-commit hook off (like a fresh clone on another machine)"
new_home
CLONE="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-clone.XXXXXX")"
cp -R "$REPO/." "$CLONE/"
git_in "$CLONE" config --unset core.hooksPath 2>/dev/null || true
for mode in --check --report --dry-run; do
    OUT="$(HOME="$H" /bin/bash "$CLONE/install.sh" "$mode" --only vim 2>&1)"; RC=$?
    expect_rc "$mode: exit 0 with the hook off" 0
    expect "$mode: reports the hook as todo" "todo  pre-commit hook not turned on"
done
rm -rf "$CLONE"

echo
echo "report"
new_home
run --report --only vim;           expect_rc "report: exit 0" 0
expect "report header" "dotfiles: REPORT"
expect_not "report hides the home path" "$H"
host="$(hostname 2>/dev/null)"; host="${host%%.*}"
if [ -n "$host" ]; then expect_not "report hides the hostname" "$host"; fi

echo
echo "read-only: nothing in the fake home changes"
new_home
cp "$REPO/vim/vimrc" "$H/.vimrc"
echo "local" > "$H/.zshrc"
printf '[pull]\n' > "$H/.gitconfig"
mkdir -p "$H/.vim/bundle/Vundle.vim" "$H/.tmux/plugins"
ln -s "$H/nowhere" "$H/.tmux.conf"
before="$(cd "$H" && find . | sort | wc -l | tr -d ' ')"
touch "$H/.marker"; sleep 1
for mode in --check --dry-run --report; do run "$mode" --profile personal; done
changed="$(cd "$H" && find . -newer .marker | grep -v '^\.$' || true)"
after="$(cd "$H" && find . | sort | wc -l | tr -d ' ')"
OUT="changed: ${changed:-none}; files before $before, after $((after - 1))"
if [ -z "$changed" ] && [ "$after" = "$((before + 1))" ]; then pass "no file created, changed or removed"; else fail "fake home changed"; fi

echo
echo "shell files: aliases load in bash and zsh"
new_home
FAKEBIN="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bin.XXXXXX")"
probe='alias tls tattach tnewd cronls cactivate sbrc vbrc 2>&1; type ta 2>&1 | head -n 1; alias ztsts 2>&1; alias vdrc'
OUT="$(HOME="$H" /bin/bash --norc -i -c ". '$REPO/shell/bashrc'; $probe; echo dir=\$DOTFILES_DIR" 2>&1)"
expect "bash: vdrc opens the shared aliases file" "vdrc='vim \"\\\$DOTFILES_DIR/shell/aliases.sh\"'"
expect "bash: DOTFILES_DIR points at the repo" "dir=$REPO\$"
expect "bash: tmux aliases" "tattach='tmux attach-session -t'"
expect "bash: ta is a function" "ta is a function"
expect "bash: cron and conda aliases" "cactivate='conda activate'"
expect "bash: vbrc edits ~/.bash_aliases" "vbrc='vim ~/.bash_aliases'"
expect_not "bash: no ZeroTier aliases on the base profile" "ztsts='"
mkdir -p "$H/.config/dotfiles"; echo personal > "$H/.config/dotfiles/profile"
printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/zerotier-cli"; chmod +x "$FAKEBIN/zerotier-cli"
OUT="$(HOME="$H" PATH="$FAKEBIN:$PATH" OSTYPE=linux-gnu /bin/bash --norc -i -c ". '$REPO/shell/bashrc'; alias ztsts ztstart" 2>&1)"
expect "personal + zerotier-cli (Linux): ztsts uses sudo" "ztsts='sudo zerotier-cli status'"
expect "personal + zerotier-cli (Linux): systemctl" "ztstart='sudo systemctl start zerotier-one'"
if command -v zsh >/dev/null 2>&1; then
    OUT="$(HOME="$H" PATH="$FAKEBIN:$PATH" zsh -f -i -c ". '$REPO/shell/zshrc'; alias vbrc tls; whence -w ta; alias ztsts" 2>&1)"
    expect "zsh: vbrc edits ~/.zshrc" "vbrc='vim ~/.zshrc'"
    expect "zsh: tmux aliases" "tls='tmux ls'"
    expect "zsh: ta is a function" "ta: function"
    case "$(uname -s)" in
        Darwin) expect "personal + zerotier-cli (macOS): launchctl, no sudo for status" "ztsts='zerotier-cli status'" ;;
    esac
else
    pass "zsh not installed; zsh checks skipped"
fi
rm -rf "$FAKEBIN"

# ---------------------------------------------------------------- write path

echo
echo "write path: link, stub, re-run, restore"
new_home; new_copy
cp "$C/vim/vimrc" "$H/.vimrc"
printf '[pull]\n\tff = only\n' > "$H/.gitconfig"; cp "$H/.gitconfig" "$H/gitconfig.orig"
runc --link-only --yes --profile base --platform macos
expect_rc "link-only run: exit 0" 0
check_file "identical ~/.vimrc became a link" test -L "$H/.vimrc"
check_file "~/.gitconfig starts with the stub" test "$(head -n 1 "$H/.gitconfig")" = "# >>> dotfiles >>>"
check_file "~/.gitconfig keeps its lines below" grep -q "ff = only" "$H/.gitconfig"
check_file "~/.zshrc created with the stub" grep -q ">>> dotfiles >>>" "$H/.zshrc"
check_file "profile saved" test "$(cat "$H/.config/dotfiles/profile")" = base
check_file "hook turned on in the clone" test "$(git_in "$C" config --get core.hooksPath)" = hooks
expect "late link without its plugin folder: warns" "warn  ~/.tmux/plugins/tmux/scripts/task_timew.sh"
check_file "late link did not create the plugin folder" test ! -e "$H/.tmux/plugins/tmux"
expect "summary names the undo command" "Undo this run: +./install.sh --restore"
log="$(ls "$H"/.local/state/dotfiles/install-*.md | head -n 1)"
check_file "a log was written" test -s "$log"
check_file "the log is redacted" sh -c "! grep -qF '$H' '$log'"
runc --link-only --yes --platform macos
expect_rc "re-run: exit 0" 0
expect "re-run changes nothing" "Nothing needed changing"
runc --restore --yes
expect_rc "restore: exit 0" 0
check_file "restore: ~/.gitconfig byte-identical" cmp -s "$H/.gitconfig" "$H/gitconfig.orig"
check_file "restore: ~/.vimrc a regular file again" sh -c "[ -f '$H/.vimrc' ] && [ ! -L '$H/.vimrc' ]"
check_file "restore: created ~/.zshrc removed" test ! -e "$H/.zshrc"
check_file "restore: profile removed" test ! -e "$H/.config/dotfiles/profile"
check_file "restore: hook setting back" test -z "$(git_in "$C" config --get core.hooksPath || true)"
runc --restore --yes
expect_rc "restore again: exit 1" 1
expect "restore again: clean message" "no run to restore"
expect_not "restore again: no failure block" "FAILED"

echo
echo "git identity check"
new_home
run --check --only git
expect "no stub yet: useConfigOnly not active" "skip  git identity: none set \(user.useConfigOnly not active yet\)"
printf '[include]\n\tpath = %s/git/gitconfig\n' "$REPO" > "$H/.gitconfig"
run --check --only git --profile office
expect "stub, no identity: warns" "warn  git identity: none set, so git refuses to commit"
expect "office: says how to set one" "git config --global user.email"
run --check --only git --profile personal
expect "personal: points to phase 5" "private layer \(phase 5\)"
printf '[user]\n\temail = someone@users.noreply.github.com\n' >> "$H/.gitconfig"
run --check --only git
expect "default identity: ok" "ok    git identity: a default is set"
printf '[include]\n\tpath = %s/git/gitconfig\n[includeIf "gitdir/i:~/projects/a/"]\n\tpath = ~/.gitconfig.a\n' "$REPO" > "$H/.gitconfig"
mkdir -p "$H/projects/a"; git_in "$H/projects/a" init -q
printf '[user]\n\temail = a@users.noreply.github.com\n' > "$H/.gitconfig.a"
OUT="$(cd "$H/projects/a" && HOME="$H" /bin/bash "$REPO/install.sh" --check --only git 2>&1)"
expect "per-folder identities: ok, even run inside such a folder" "ok    git identity: set per folder \(1 includeIf rule\)"

echo
echo "packages: whether this machine installs them"
new_home; new_copy
printf 'git\ndotfiles-no-such-package\n' > "$C/packages/common.txt"
runc --check --only packages --platform linux
expect "generic Linux: uses what is installed" "packages : use what is installed \(no supported package manager"
expect "generic Linux: tools found by command" "ok    git"
expect "generic Linux: a missing tool is skipped, not todo" "skip  dotfiles-no-such-package \(not installed; package installs are off here\)"
runc --dry-run --only packages --platform linux
expect_not "generic Linux: dry run installs nothing" "brew install|apt-get install"
runc --dry-run --only packages --platform debian --no-packages
expect "--no-packages: step 2 is off" "skip  package installs: off \(from --no-packages\)"
expect_not "--no-packages: no apt-get" "apt-get"
mkdir -p "$H/.config/dotfiles"; echo no > "$H/.config/dotfiles/packages"
runc --dry-run --only packages --platform debian
expect "saved 'no' is used" "packages : use what is installed \(saved"
runc --dry-run --only packages --platform debian --packages
expect "--packages wins over the saved answer" "apt-get install .* dotfiles-no-such-package"
rm -f "$H/.config/dotfiles/packages"
runc --link-only --yes --profile base --only vim --no-packages
check_file "a --no-packages real run saves the answer" test "$(cat "$H/.config/dotfiles/packages")" = no
runc --restore --yes
check_file "restore removes the saved answer" test ! -e "$H/.config/dotfiles/packages"

echo
echo "old git (1.8.3, as on CentOS 7): no 'git -C', no core.hooksPath"
FAKEGIT="$FAKEGIT_DIR"
new_home; new_copy
for mode in --check --dry-run --report; do
    OUT="$(HOME="$H" PATH="$FAKEGIT:$PATH" /bin/bash "$C/install.sh" "$mode" --only vim 2>&1 < /dev/null)"; RC=$?
    expect_rc "old git: $mode exit 0" 0
done
expect "old git: the hook is reported as unsupported" "pre-commit hook: needs git 2.9 or newer \(this is 1.8.3.1\)"
OUT="$(HOME="$H" PATH="$FAKEGIT:$PATH" DOTFILES_TEST_NO_PLUGINS=1 /bin/bash "$C/install.sh" --link-only --yes --profile office --only git 2>&1 < /dev/null)"; RC=$?
expect_rc "old git: a real run works" 0
expect_not "old git: no -C error anywhere" "Unknown option: -C"

echo
echo "write path: logs and runs are found in time order"
new_home; new_copy
mkdir -p "$H/.local/state/dotfiles"
i=10; while [ "$i" -lt 35 ]; do echo old > "$H/.local/state/dotfiles/install-20200101-0000$i.md"; i=$((i + 1)); done
runc --link-only --yes --profile base --only vim
logs="$(ls "$H"/.local/state/dotfiles/install-*.md | wc -l | tr -d ' ')"
check_file "only the 20 newest logs are kept (25 old + 1 new)" test "$logs" = 20
check_file "the oldest logs went first" test ! -e "$H/.local/state/dotfiles/install-20200101-000010.md"
first="$(ls -d "$H"/.local/state/dotfiles/backup/*/ | head -n 1)"; first="${first%/}"; first="${first##*/}"
sleep 1
runc --link-only --yes --only git
runc --restore --yes
expect "restore picks the newest run" "Restore run [0-9-]+"
check_file "the newer run was restored first" sh -c "! grep -q 'Restore run $first' <<EOF
$OUT
EOF"
runc --restore --yes
expect "the next restore picks the older run" "Restore run $first"

echo
echo "write path: a file that differs, with --yes"
new_home; new_copy
echo '" my old vimrc' > "$H/.vimrc"
runc --link-only --yes --profile base --only vim
check_file "--yes keeps the repo version: now a link" test -L "$H/.vimrc"
bk="$(ls -d "$H"/.local/state/dotfiles/backup/*/ | head -n 1)"
check_file "the old file is in the backup" grep -q "my old vimrc" "${bk}files/.vimrc"

echo
echo "write path: late link once the plugin folder exists"
new_home; new_copy
mkdir -p "$H/.tmux/plugins/tmux/scripts"
runc --link-only --yes --profile base --only tmux
check_file "task_timew.sh linked into the plugin folder" test -L "$H/.tmux/plugins/tmux/scripts/task_timew.sh"

echo
echo "write path: add-ons"
new_home; new_copy
ADDON="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-addon.XXXXXX")"
git_in "$ADDON" init -q && git_in "$ADDON" -c user.name=t -c user.email=t@users.noreply.github.com commit -q --allow-empty -m init
printf 'vim  file://%s  ~/.vim/bundle/Vundle.vim\n' "$ADDON" > "$C/addons.txt"
runc --yes --profile base --only vim
expect_rc "install --only vim: exit 0" 0
check_file "add-on cloned" test -d "$H/.vim/bundle/Vundle.vim/.git"
expect "plugins not installed in tests" "vim plugins: not installed in tests"
runc --restore --yes
check_file "restore moves the clone aside" test ! -e "$H/.vim/bundle/Vundle.vim"
printf 'vim  file:///nonexistent/dotfiles-test  ~/.vim/bundle/Vundle.vim\n' > "$C/addons.txt"
new_home
runc --yes --profile base --only vim
expect_rc "failing clone: exit 1" 1
expect "failure block" "dotfiles: FAILED"
expect "failure block names the command" "command   : git clone --depth 1 file:///nonexistent"
expect "commands show ~, not the home path" "\+ git clone --depth 1 file:///nonexistent/dotfiles-test ~/.vim/bundle/Vundle.vim"
expect "failure block shows its output" "last output:"
log="$(ls "$H"/.local/state/dotfiles/install-*.md | head -n 1)"
check_file "failure block is in the log" grep -q "dotfiles: FAILED" "$log"
runc --report --only vim
expect "report shows the latest failure" "latest install log:.*"
expect "report includes the failure block" "command   : git clone"
rm -rf "$ADDON"

echo
echo "write path: --adopt"
new_home; new_copy
mkdir -p "$H/.config/htop"; echo "color_scheme=1" > "$H/.config/htop/htoprc"
runc --adopt "$H/.config/htop/htoprc" --as htop/htoprc --yes
expect_rc "adopt: exit 0" 0
check_file "adopt: live file is now a link" test -L "$H/.config/htop/htoprc"
check_file "adopt: file is in the repo copy" grep -q "color_scheme=1" "$C/htop/htoprc"
check_file "adopt: links.txt has the line" grep -q "^htop/htoprc .*~/.config/htop/htoprc .*link" "$C/links.txt"
runc --restore --yes
check_file "restore after adopt: original file back" sh -c "[ ! -L '$H/.config/htop/htoprc' ] && grep -q color_scheme=1 '$H/.config/htop/htoprc'"
printf 'server=/%s/alice/x\n' Users > "$H/personal.conf"    # built at runtime: the hook scans this file too
runc --adopt "$H/personal.conf" --yes
expect_rc "adopt refuses personal data: exit 1" 1
expect "adopt says why" "look personal"
echo "x" > "$H/.zshrc"
runc --adopt "$H/.zshrc" --yes
expect_rc "adopt refuses a stub-managed file: exit 1" 1

echo
echo "write path: safety"
new_home; new_copy
runc --link-only --profile base
expect_rc "no --yes and no terminal: exit 1" 1
expect "stops before changing anything" "needs a terminal to confirm"
check_file "nothing was changed" test ! -e "$H/.vimrc"
runc
expect_rc "no mode, no profile, no terminal: exit 2 without asking" 2

echo
printf 'Result: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
