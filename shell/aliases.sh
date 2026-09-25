# Shared aliases and settings for zsh and bash, on every machine.
# Personal aliases live in the private layer; one-machine ones in the local rc file.

# Locale: set on macOS only. Ubuntu servers may not have en_US.UTF-8 generated,
# and setting it there makes every program warn.
case "${OSTYPE:-}" in
    darwin*)
        export LANG=en_US.UTF-8
        export LC_CTYPE=en_US.UTF-8
        ;;
esac

# Edit and reload the local rc files. The same names work in both shells.
if [ -n "${ZSH_VERSION:-}" ]; then
    alias vbrc='vim ~/.zshrc'
    alias sbrc='source ~/.zshrc'
else
    alias vbrc='vim ~/.bash_aliases'
    alias sbrc='source ~/.bashrc'
fi
alias vtrc='vim ~/.taskrc'

# Taskwarrior
alias tui='taskwarrior-tui'
alias tann='task annotate'
alias topen='taskopen'
alias tstart='task start'
alias tstop='task stop'

# Ubuntu installs bat as batcat.
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    alias bat='batcat'
fi
