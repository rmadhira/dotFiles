#!/usr/bin/env bash
#
# tests/run.sh - check install.sh against throwaway fake home folders.
#
# Every test runs install.sh with HOME pointing at a fresh temporary folder, so
# the real home folder is never read for state or touched. Run it with the
# oldest bash we support:  /bin/bash tests/run.sh
#
# bash 3.2 compatible. See docs/DESIGN.md.

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
run;                               expect_rc "no mode: exit 2" 2
run --check --dry-run;             expect_rc "two modes: exit 2" 2
run --check --only nope;           expect_rc "bad --only: exit 2" 2
run --check --profile work;        expect_rc "bad --profile: exit 2" 2
run --adopt x;                     expect_rc "write-path option: exit 2" 2; expect "write-path option explains" "phase 3"
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
echo "platform columns in links.txt"
new_home
run --check --only shell --platform macos;  expect "macOS: zshrc managed" "~/.zshrc"; expect_not "macOS: no bashrc" "~/.bashrc"
run --check --only shell --platform debian; expect "Linux: bashrc managed" "~/.bashrc"; expect_not "Linux: no zshrc" "~/.zshrc"

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
expect "debian: apt install" "\+ sudo apt install -y git"
expect_not "debian: macOS-only package skipped" "apt install -y taskopen"
run --dry-run --only packages --platform macos
expect "macOS: cask install" "\+ brew install --cask iterm2|ok    iterm2"

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
printf 'Result: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
