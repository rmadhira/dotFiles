# lib/platform/debian.sh - Debian and Ubuntu: apt and GNU command flags.
# Defines exactly the six platform functions (see docs/DESIGN.md, Platform layer).
# shellcheck shell=bash

PLATFORM_OS=linux
PKG_COLUMN=3    # apt column in packages/map.txt

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
pkg_bootstrap() {
    if [ "$DRY_RUN" = 1 ]; then
        item todo "apt needs root: one password prompt, up front"
        cmd_line "sudo -v"
        cmd_line "sudo apt update"
        _dpkg_load
        if [ "$_DPKG_OK" = 0 ]; then
            item skip "glow source: apt is not available here, cannot tell"
        elif in_list glow "$_DPKG_INSTALLED" || command -v glow >/dev/null 2>&1; then
            item ok "glow source: glow is already installed"
        elif [ -n "$(_apt_candidate glow)" ]; then
            item ok "glow source: Ubuntu's own apt has glow"
        else
            item todo "glow source: apt has no glow, the charm.sh apt repo would be added"
        fi
        return 0
    fi
    not_built_yet "preparing apt"
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
    if [ "$DRY_RUN" = 1 ]; then
        cmd_line "sudo apt install -y $(pkg_name_for "$2")"
        return 0
    fi
    not_built_yet "installing packages"
}

# sed_inplace <expression> <file>
sed_inplace() { sed -i "$1" "$2"; }

# file_mtime <file>: modification time in seconds.
file_mtime() { stat -c %Y "$1"; }

# resolve_path <path>: absolute path with symlinks followed.
resolve_path() { readlink -f "$1" 2>/dev/null || printf '%s\n' "$1"; }
