# lib/platform/debian.sh - Debian and Ubuntu: apt and GNU command flags.
# Defines exactly the six platform functions (see docs/DESIGN.md, Platform layer).
# shellcheck shell=bash

# Both are read by lib/common.sh, which shellcheck checks separately.
# shellcheck disable=SC2034
PLATFORM_OS=linux
# shellcheck disable=SC2034
PKG_COLUMN=3    # apt column in packages/map.txt

# apt must never stop to ask: no debconf dialogs (defaults are taken), needrestart
# only lists services instead of asking or restarting them, and a config file I
# changed is kept on upgrade. Found when needrestart's blue dialog took over server B.
# NEEDRESTART_SUSPEND skips needrestart's report after every package; one note at
# the end of the step points to "sudo needrestart" instead.
APT_GET="env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1 apt-get"
APT_OPTS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

_DPKG_LOADED=0
_DPKG_OK=0
_DPKG_INSTALLED=""
_dpkg_load() {
    [ "$_DPKG_LOADED" = 1 ] && return 0
    _DPKG_LOADED=1
    if command -v dpkg-query >/dev/null 2>&1; then
        _DPKG_OK=1
        _DPKG_INSTALLED="$(dpkg-query -W -f='${Package} ${Status}\n' 2>/dev/null |
                           awk '$4 == "installed" { print $1 }' || true)"
    fi
    return 0
}

# _apt_candidate <package>: the version apt would install, or empty.
_apt_candidate() {
    command -v apt-cache >/dev/null 2>&1 || return 0
    apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ { if ($2 != "(none)") print $2 }'
}

# pkg_bootstrap: one sudo prompt up front, apt update, charm.sh only if apt lacks glow.
# In the read-only modes it only reports.
pkg_bootstrap() {
    if [ "$DRY_RUN" = 1 ]; then
        item todo "apt needs root: one password prompt, up front"
        cmd_line "sudo -v"
        cmd_line "sudo $APT_GET update"
    elif [ "$READ_ONLY" = 0 ]; then
        CURRENT_ACTION="prepare apt"
        echo "        apt needs root: sudo asks for your password once, now."
        run_interactive sudo -v
        # shellcheck disable=SC2086  # APT_GET is a command with words, split on purpose
        run_cmd sudo $APT_GET update
        done_item "apt package lists updated"
    fi
    _dpkg_load
    if [ "$_DPKG_OK" = 0 ]; then
        item skip "glow source: apt is not available here, cannot tell"
    elif in_list glow "$_DPKG_INSTALLED" || command -v glow >/dev/null 2>&1; then
        item ok "glow source: glow is already installed"
    elif [ -n "$(_apt_candidate glow)" ]; then
        item ok "glow source: Ubuntu's own apt has glow"
    elif [ "$READ_ONLY" = 1 ]; then
        item todo "glow source: apt has no glow, the charm.sh apt repo would be added"
    else
        CURRENT_ACTION="add the charm.sh apt repo"
        run_cmd sudo mkdir -p /etc/apt/keyrings
        run_cmd sudo bash -c 'curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg'
        run_cmd sudo bash -c 'echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list'
        # shellcheck disable=SC2086
        run_cmd sudo $APT_GET update
        record system "-" "added the charm.sh apt repo"
        done_item "glow source: charm.sh apt repo added"
    fi
    return 0
}

# pkg_installed <kind> <list name> [app bundle]: prints ok, missing, skip or unknown.
pkg_installed() {
    local kind="$1" name="$2" apt_name
    if [ "$kind" = cask ]; then echo skip; return 0; fi
    apt_name="$(pkg_name_for "$name")"
    if [ "$apt_name" = "-" ]; then echo skip; return 0; fi
    _dpkg_load
    if [ "$_DPKG_OK" = 0 ]; then echo unknown; return 0; fi
    if in_list "$apt_name" "$_DPKG_INSTALLED"; then echo ok; else echo missing; fi
    return 0
}

# pkg_install <kind> <list name>: in a dry run, prints the command.
pkg_install() {
    if [ "$READ_ONLY" = 1 ]; then
        cmd_line "sudo $APT_GET install $APT_OPTS $(pkg_name_for "$2")"
        return 0
    fi
    # shellcheck disable=SC2086  # command and options are split into words on purpose
    run_cmd sudo $APT_GET install $APT_OPTS "$(pkg_name_for "$2")"
    if command -v needrestart >/dev/null 2>&1; then
        PKG_AFTER_NOTE="Some services may use updated libraries; 'sudo needrestart' lists any that need a restart."
    fi
}

# sed_inplace <expression> <file>
sed_inplace() { sed -i "$1" "$2"; }

# file_mtime <file>: modification time in seconds.
file_mtime() { stat -c %Y "$1"; }

# resolve_path <path>: absolute path with symlinks followed.
resolve_path() { readlink -f "$1" 2>/dev/null || printf '%s\n' "$1"; }
