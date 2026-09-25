#!/usr/bin/env bash
#
# survey.sh - read-only survey of a machine before the dotfiles installer runs.
#
# Changes nothing: no installs, no writes, no sudo prompts. Prints one report
# with the home path and hostname redacted, ready to paste into a chat.
#
#   ./tools/survey.sh                  # print the report
#   ./tools/survey.sh > /tmp/survey.txt  # or save it
#
# Works with macOS's /bin/bash 3.2 and Linux bash 5. See docs/DESIGN.md.

set -u

REPO_URL="https://github.com/rmadhira/dotFiles.git"

# Tools the design installs (command names), plus a few that inform decisions.
TOOLS="git vim tmux curl wget glow task timew fzf rg jq tree gh htop bat batcat
taskwarrior-tui taskopen mosh zsh python3 conda shellcheck docker"

# apt package names for the base list (checked on Linux only).
APT_PKGS="git vim tmux curl wget glow taskwarrior timewarrior fzf ripgrep jq tree
gh htop bat taskopen mosh taskwarrior-tui"

# Files the design manages, relative to $HOME.
DOTFILES=".zshrc .zprofile .zshenv .bashrc .bash_aliases .profile .gitconfig
.vimrc .tmux.conf .taskrc"

section() { printf '\n== %s\n' "$1"; }
have()    { command -v "$1" >/dev/null 2>&1; }
yesno()   { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

survey_common() {
    section "survey"
    echo "script   : tools/survey.sh ($(git -C "$(dirname "$0")" rev-parse --short HEAD 2>/dev/null || echo 'no git'))"
    echo "date     : $(date '+%Y-%m-%d %H:%M %Z')"

    section "system"
    echo "kernel   : $(uname -s) $(uname -r) $(uname -m)"
    echo "bash     : $(/bin/bash --version 2>/dev/null | head -1)"
    echo "shell    : ${SHELL:-unset}"

    section "tools on PATH"
    for t in $TOOLS; do
        if have "$t"; then
            printf '  %-16s %s\n' "$t" "$(command -v "$t")"
        else
            printf '  %-16s -\n' "$t"
        fi
    done

    section "dotfiles in home"
    for f in $DOTFILES; do
        p="$HOME/$f"
        if [ -L "$p" ]; then
            printf '  %-14s symlink -> %s\n' "$f" "$(readlink "$p")"
        elif [ -f "$p" ]; then
            printf '  %-14s file, %s lines\n' "$f" "$(wc -l < "$p" | tr -d ' ')"
        else
            printf '  %-14s -\n' "$f"
        fi
    done

    section "vim and tmux add-ons"
    for d in .vim/bundle/Vundle.vim .vim/colors .tmux/plugins/tpm .tmux/plugins/tmux; do
        if [ -d "$HOME/$d" ]; then echo "  $d present"; else echo "  $d -"; fi
    done
    if [ -d "$HOME/.vim/bundle" ]; then
        echo "  vim plugins: $(ls "$HOME/.vim/bundle" | tr '\n' ' ')"
    fi

    section "git"
    echo "global user.email set : $(yesno git config --global user.email)"
    echo "global user.name set  : $(yesno git config --global user.name)"
    echo "includeIf entries     : $(git config --global --get-regexp '^includeif\.' 2>/dev/null | wc -l | tr -d ' ')"
    # Key file names can contain personal words, so only counts are shown.
    if [ -d "$HOME/.ssh" ]; then
        all="$(cd "$HOME/.ssh" && ls *.pub 2>/dev/null | wc -l | tr -d ' ')"
        conv="$(cd "$HOME/.ssh" && ls *_key.pub 2>/dev/null | wc -l | tr -d ' ')"
        echo "ssh public keys       : $all ($conv named <account>_key; names not shown)"
    else
        echo "ssh public keys       : no ~/.ssh folder"
    fi
    echo "github reachable (https): $(yesno env GIT_TERMINAL_PROMPT=0 git \
        -c http.lowSpeedLimit=1 -c http.lowSpeedTime=15 ls-remote "$REPO_URL" HEAD)"

    section "conda"
    for d in anaconda3 miniconda3 miniforge3; do
        [ -d "$HOME/$d" ] && echo "  ~/$d present"
    done
    have conda && echo "  conda: $(conda --version 2>/dev/null)"
    if have crontab; then
        echo "  crontab lines: $(crontab -l 2>/dev/null | grep -cv '^#') total," \
             "$(crontab -l 2>/dev/null | grep -ci conda) mention conda"
    fi
}

survey_macos() {
    section "macOS"
    echo "version  : $(sw_vers -productVersion 2>/dev/null)"
    echo "admin    : $(id -Gn | tr ' ' '\n' | grep -qx admin && echo yes || echo no)"
    echo "MDM      : $(profiles status -type enrollment 2>&1 | tr '\n' ' ')"
    echo "CLT      : $(xcode-select -p 2>&1)"

    section "Homebrew"
    brew_bin=""
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$b" ] && brew_bin="$b" && break
    done
    if [ -z "$brew_bin" ]; then
        echo "not installed"
    else
        brew_root="$("$brew_bin" --prefix 2>/dev/null)"
        owner="$(ls -ld "$brew_root" | awk '{print $3}')"
        [ "$owner" = "$(id -un)" ] && owner="me" || owner="another account"
        echo "binary   : $brew_bin"
        echo "on PATH  : $(have brew && echo yes || echo no)"
        echo "version  : $("$brew_bin" --version 2>/dev/null | head -1)"
        echo "owner    : $owner"
        echo "formulae : $("$brew_bin" list --formula 2>/dev/null | tr '\n' ' ')"
        echo "casks    : $("$brew_bin" list --cask 2>/dev/null | tr '\n' ' ')"
    fi

    section "apps"
    for app in iTerm.app; do
        where="-"
        for dir in /Applications "$HOME/Applications"; do
            [ -d "$dir/$app" ] && where="$dir/$app"
        done
        echo "  $app: $where"
    done
    if [ -n "$brew_bin" ]; then
        echo "  iterm2 managed by Homebrew: $(yesno "$brew_bin" list --cask iterm2)"
    fi
}

survey_linux() {
    section "Linux"
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        echo "release  : ${PRETTY_NAME:-unknown} (ID=${ID:-?} ID_LIKE=${ID_LIKE:-})"
    fi
    echo "sudo without password: $(yesno sudo -n true)"
    echo "in sudo group        : $(id -Gn | tr ' ' '\n' | grep -qxE 'sudo|wheel|admin' && echo yes || echo no)"

    if have apt-cache; then
        section "apt candidates (from the local package cache; '(none)' = not available)"
        for p in $APT_PKGS; do
            cand="$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/ {print $2}')"
            inst="$(apt-cache policy "$p" 2>/dev/null | awk '/Installed:/ {print $2}')"
            printf '  %-16s candidate %-28s installed %s\n' "$p" "${cand:-(none)}" "${inst:-(none)}"
        done
        echo "  apt lists last updated: $(ls -ld --time-style=+%Y-%m-%d /var/lib/apt/lists 2>/dev/null | awk '{print $6}')"
    fi
}

main() {
    survey_common
    case "$(uname -s)" in
        Darwin) survey_macos ;;
        Linux)  survey_linux ;;
        *)      section "unknown platform: $(uname -s)" ;;
    esac
    section "end of survey"
}

# Redact the home path and hostname before anything reaches the screen.
host_full="$(hostname 2>/dev/null)"
host_short="${host_full%%.*}"
main 2>&1 | sed -e "s#$HOME#~#g" \
                -e "s#${host_full:-@@none@@}#<host>#g" \
                -e "s#${host_short:-@@none@@}#<host>#g"
