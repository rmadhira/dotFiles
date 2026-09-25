# Shell load order, shared by shell/zshrc and shell/bashrc (see docs/DESIGN.md,
# Private layer). Later files override earlier ones. Every file is optional, so
# a machine without the private layer still gets a working shell.
#
# Expects DOTFILES_DIR (the repo root) to be set by the caller.

DOTFILES_CONFIG="$HOME/.config/dotfiles"

DOTFILES_PROFILE=base
if [ -r "$DOTFILES_CONFIG/profile" ]; then
    read -r DOTFILES_PROFILE < "$DOTFILES_CONFIG/profile"
fi

# Short hostname without starting a process: bash sets HOSTNAME, zsh sets HOST.
DOTFILES_HOST="${HOSTNAME:-${HOST:-}}"
DOTFILES_HOST="${DOTFILES_HOST%%.*}"

_dotfiles_source() { [ -f "$1" ] && . "$1"; }

_dotfiles_source "$DOTFILES_DIR/shell/aliases.sh"                              # 1. shared
_dotfiles_source "$DOTFILES_DIR/shell/profiles/$DOTFILES_PROFILE.sh"           # 2. profile, public
_dotfiles_source "$DOTFILES_CONFIG/private/shell/$DOTFILES_PROFILE.sh"         # 3. profile, private layer
_dotfiles_source "$DOTFILES_CONFIG/private/shell/hosts/$DOTFILES_HOST.sh"      # 4. this host, private layer
_dotfiles_source "$DOTFILES_CONFIG/$DOTFILES_PROFILE.local.sh"                 # 5. this machine only
# 6. The rest of the local ~/.zshrc or ~/.bashrc runs after this file returns.

unset -f _dotfiles_source
