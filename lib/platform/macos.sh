# lib/platform/macos.sh - macOS: Homebrew and BSD command flags.
# Defines exactly the six platform functions (see docs/DESIGN.md, Platform layer).
# shellcheck shell=bash

PLATFORM_OS=macos
PKG_COLUMN=2    # brew column in packages/map.txt

BREW=""
for _b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$_b" ]; then BREW="$_b"; break; fi
done
unset _b

_BREW_LOADED=0
_BREW_FORMULAE=""
_BREW_CASKS=""
_brew_load() {
    [ "$_BREW_LOADED" = 1 ] && return 0
    _BREW_LOADED=1
    if [ -n "$BREW" ]; then
        _BREW_FORMULAE="$("$BREW" list --formula -1 2>/dev/null || true)"
        _BREW_CASKS="$("$BREW" list --cask -1 2>/dev/null || true)"
    fi
    return 0
}

# pkg_bootstrap: get Homebrew ready.
pkg_bootstrap() {
    if [ -n "$BREW" ]; then
        item ok "Homebrew: $(tildify "$BREW")"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        item todo "Homebrew is not installed"
        cmd_line '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        return 0
    fi
    not_built_yet "installing Homebrew"
}

# pkg_installed <kind> <list name> [app bundle]: prints ok, outside, missing or skip.
pkg_installed() {
    local kind="$1" name="$2" app="${3:-}" brew_name
    brew_name="$(pkg_name_for "$name")"
    if [ "$brew_name" = "-" ]; then echo skip; return 0; fi
    _brew_load
    if [ "$kind" = cask ]; then
        if in_list "$brew_name" "$_BREW_CASKS"; then echo ok; return 0; fi
        # An app installed by hand counts: "brew install --cask" would fail on it.
        if [ -n "$app" ] && { [ -d "/Applications/$app" ] || [ -d "$HOME/Applications/$app" ]; }; then
            echo outside; return 0
        fi
        echo missing; return 0
    fi
    if in_list "$brew_name" "$_BREW_FORMULAE"; then echo ok; else echo missing; fi
    return 0
}

# pkg_install <kind> <list name>: in a dry run, prints the command.
pkg_install() {
    local kind="$1" brew_name
    brew_name="$(pkg_name_for "$2")"
    if [ "$DRY_RUN" = 1 ]; then
        if [ "$kind" = cask ]; then cmd_line "brew install --cask $brew_name"
        else cmd_line "brew install $brew_name"; fi
        return 0
    fi
    not_built_yet "installing packages"
}

# sed_inplace <expression> <file>
sed_inplace() { sed -i '' "$1" "$2"; }

# file_mtime <file>: modification time in seconds.
file_mtime() { stat -f %m "$1"; }

# resolve_path <path>: absolute path with symlinks followed (no readlink -f on older macOS).
resolve_path() {
    local p="$1" target n=0 dir
    while [ -L "$p" ] && [ "$n" -lt 40 ]; do
        target="$(readlink "$p")"
        case "$target" in
            /*) p="$target" ;;
            *)  p="$(dirname "$p")/$target" ;;
        esac
        n=$((n + 1))
    done
    if dir="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)"; then
        printf '%s/%s\n' "$dir" "$(basename "$p")"
    else
        printf '%s\n' "$p"
    fi
}
