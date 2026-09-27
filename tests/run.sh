#!/usr/bin/env bash
#
# tests/run.sh - check install.sh against throwaway fake home folders.
#
# Every test runs install.sh with HOME pointing at a fresh temporary folder, so
# the real home folder is never read for state or touched. Run it with the
# oldest bash we support:  /bin/bash tests/run.sh
#
# bash 3.2 compatible. See docs/DESIGN.md.

# Expected output contains literal "~/" paths.
# shellcheck disable=SC2088

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PASS=0
FAIL=0
H=""

new_home() {
    [ -n "$H" ] && rm -rf "$H"
    H="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")"
    H="$(cd "$H" && pwd -P)"
}
cleanup() { [ -n "$H" ] && rm -rf "$H"; return 0; }
trap cleanup EXIT

# run <args...>: install.sh output with the fake home; exit code in RC.
run() {
    OUT="$(HOME="$H" /bin/bash "$REPO/install.sh" "$@" 2>&1)"
    RC=$?
}

pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
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
git -C "$H/.vim/bundle/Vundle.vim" init -q
git -C "$H/.vim/bundle/Vundle.vim" remote add origin https://github.com/VundleVim/Vundle.vim
run --check --only vim;            expect "add-on from the declared URL" "ok    ~/.vim/bundle/Vundle.vim"
git -C "$H/.vim/bundle/Vundle.vim" remote set-url origin https://example.com/other.git
run --check --only vim;            expect "add-on from another URL" "warn  ~/.vim/bundle/Vundle.vim cloned from https://example.com/other.git"

echo
echo "plugins"
new_home
run --check --only tmux;           expect "tmux plugins missing" "todo  tmux plugins missing: tpm vim-tmux-navigator tmux"
mkdir -p "$H/.tmux/plugins/tpm" "$H/.tmux/plugins/vim-tmux-navigator" "$H/.tmux/plugins/tmux"
run --check --only tmux;           expect "tmux plugins present" "ok    tmux plugins"

echo
echo "dry run"
new_home
run --dry-run --only vim;          expect_rc "dry run: exit 0" 0
expect "nine numbered steps" "\[9/9\] Finish"
expect "link command" "\+ ln -s vim/vimrc ~/.vimrc"
expect "clone command" "\+ git clone --depth 1 https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim"
expect "plugin command" "\+ vim \+PluginInstall \+qall"
expect "says nothing changed" "Nothing was changed"
run --dry-run --only packages --platform debian
expect "debian: one sudo prompt" "\+ sudo -v"
expect "debian: apt-get install, never asking" "\+ sudo env DEBIAN_FRONTEND=noninteractive .*NEEDRESTART_MODE=l .*apt-get install -y .* git$"
expect_not "debian: macOS-only package skipped" "apt-get install .* taskopen$"
run --dry-run --only packages --platform macos
expect "macOS: cask install" "\+ brew install --cask iterm2|ok    iterm2"

echo
echo "a clone with the pre-commit hook off (like a fresh clone on another machine)"
new_home
CLONE="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-clone.XXXXXX")"
cp -R "$REPO/." "$CLONE/"
git -C "$CLONE" config --unset core.hooksPath 2>/dev/null || true
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

# ---------------------------------------------------------------- write path
# Real runs change the repo too (hook setting, --adopt), so they use a copy.

C=""
new_copy() {
    [ -n "$C" ] && rm -rf "$C"
    C="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-copy.XXXXXX")"; C="$(cd "$C" && pwd -P)"
    cp -R "$REPO/." "$C/"
    git -C "$C" config --unset core.hooksPath 2>/dev/null || true
}
# runc <args...>: install.sh from the copy, fake home, no plugin installs, no terminal input.
runc() {
    OUT="$(HOME="$H" DOTFILES_TEST_NO_PLUGINS=1 /bin/bash "$C/install.sh" "$@" 2>&1 < /dev/null)"
    RC=$?
}
check_file() {  # check_file <label> <test expression...>
    local label="$1"; shift
    if "$@"; then pass "$label"; else OUT="(file check failed: $*)"; fail "$label"; fi
}
cleanup_copy() { [ -n "$C" ] && rm -rf "$C"; cleanup; }
trap cleanup_copy EXIT

echo
echo "write path: link, stub, re-run, restore"
new_home; new_copy
cp "$C/vim/vimrc" "$H/.vimrc"
printf '[pull]\n\tff = only\n' > "$H/.gitconfig"; cp "$H/.gitconfig" "$H/gitconfig.orig"
runc --link-only --yes --profile base
expect_rc "link-only run: exit 0" 0
check_file "identical ~/.vimrc became a link" test -L "$H/.vimrc"
check_file "~/.gitconfig starts with the stub" test "$(head -n 1 "$H/.gitconfig")" = "# >>> dotfiles >>>"
check_file "~/.gitconfig keeps its lines below" grep -q "ff = only" "$H/.gitconfig"
check_file "~/.zshrc created with the stub" grep -q ">>> dotfiles >>>" "$H/.zshrc"
check_file "profile saved" test "$(cat "$H/.config/dotfiles/profile")" = base
check_file "hook turned on in the clone" test "$(git -C "$C" config --get core.hooksPath)" = hooks
expect "late link without its plugin folder: warns" "warn  ~/.tmux/plugins/tmux/scripts/task_timew.sh"
check_file "late link did not create the plugin folder" test ! -e "$H/.tmux/plugins/tmux"
expect "summary names the undo command" "Undo this run: +./install.sh --restore"
log="$(ls "$H"/.local/state/dotfiles/install-*.md | head -n 1)"
check_file "a log was written" test -s "$log"
check_file "the log is redacted" sh -c "! grep -qF '$H' '$log'"
runc --link-only --yes
expect_rc "re-run: exit 0" 0
expect "re-run changes nothing" "Nothing needed changing"
runc --restore --yes
expect_rc "restore: exit 0" 0
check_file "restore: ~/.gitconfig byte-identical" cmp -s "$H/.gitconfig" "$H/gitconfig.orig"
check_file "restore: ~/.vimrc a regular file again" sh -c "[ -f '$H/.vimrc' ] && [ ! -L '$H/.vimrc' ]"
check_file "restore: created ~/.zshrc removed" test ! -e "$H/.zshrc"
check_file "restore: profile removed" test ! -e "$H/.config/dotfiles/profile"
check_file "restore: hook setting back" test -z "$(git -C "$C" config --get core.hooksPath || true)"
runc --restore --yes
expect_rc "restore again: exit 1" 1
expect "restore again: clean message" "no run to restore"
expect_not "restore again: no failure block" "FAILED"

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
git -C "$ADDON" init -q && git -C "$ADDON" -c user.name=t -c user.email=t@users.noreply.github.com commit -q --allow-empty -m init
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
if (exec < /dev/tty) 2>/dev/null; then
    pass "no-terminal check skipped (running in a terminal)"
else
    runc --link-only --profile base
    expect_rc "no --yes and no terminal: exit 1" 1
    expect "stops before changing anything" "needs a terminal to confirm"
    check_file "nothing was changed" test ! -e "$H/.vimrc"
fi

echo
printf 'Result: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
