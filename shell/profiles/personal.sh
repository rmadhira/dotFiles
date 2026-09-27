# shellcheck shell=bash  # also sourced by zsh
# Personal profile: generic extras for my own machines.
# Nothing identifying goes here; personal aliases and paths live in the private
# layer (~/.config/dotfiles/private/shell/personal.sh), loaded right after this.

# ZeroTier, where it is installed. Starting and stopping differ by OS.
if command -v zerotier-cli >/dev/null 2>&1; then
    case "${OSTYPE:-}" in
        darwin*)
            alias ztstart='sudo launchctl load /Library/LaunchDaemons/com.zerotier.one.plist'
            alias ztstop='sudo launchctl unload /Library/LaunchDaemons/com.zerotier.one.plist'
            alias ztsts='zerotier-cli status'
            ;;
        *)
            alias ztstart='sudo systemctl start zerotier-one'
            alias ztstop='sudo systemctl stop zerotier-one'
            alias ztsts='sudo zerotier-cli status'
            ;;
    esac
    alias ztlsnw='sudo zerotier-cli listnetworks'
fi
