# lib/platform/linux.sh - any other Linux (CentOS, RHEL, Alpine, ...): no package manager.
# Defines exactly the six platform functions (see docs/DESIGN.md, Platform layer).
# Packages are never installed here; the installer uses the tools already on PATH.
# shellcheck shell=bash

# Both are read by lib/common.sh, which shellcheck checks separately.
# shellcheck disable=SC2034
PLATFORM_OS=linux
# shellcheck disable=SC2034
PKG_COLUMN=4    # command column in packages/map.txt
# shellcheck disable=SC2034
PKG_MANAGER=none

pkg_bootstrap() {
    item skip "package installs: not supported on $(os_release_name); using the tools already installed"
    return 0
}

# pkg_installed <kind> <list name>: ok if any of its commands is on PATH, else missing.
pkg_installed() {
    local cmds c
    if [ "$1" = cask ]; then echo skip; return 0; fi
    cmds="$(pkg_name_for "$2")"
    if [ "$cmds" = "-" ]; then echo skip; return 0; fi
    for c in $(printf '%s\n' "$cmds" | tr '|' ' '); do
        if command -v "$c" >/dev/null 2>&1; then echo ok; return 0; fi
    done
    echo missing
    return 0
}

pkg_install() { stop_run "package installs are not supported on this Linux; $2 was not installed."; }

sed_inplace() { sed -i "$1" "$2"; }
file_mtime() { stat -c %Y "$1"; }
resolve_path() { readlink -f "$1" 2>/dev/null || printf '%s\n' "$1"; }
