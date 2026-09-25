#!/usr/bin/env bash
#
# install.sh - dotfiles installer for macOS and Ubuntu. See docs/DESIGN.md.
#
#   ./install.sh --check      what differs from the repo (changes nothing)
#   ./install.sh --dry-run    what a real run would do (changes nothing)
#   ./install.sh --report     one redacted block to paste into a chat
#   ./install.sh --help
#
# Phase 2 builds only the read-only modes; nothing here writes yet.

# Refuse to run under sh or zsh before any bash-only syntax is parsed.
if [ -z "${BASH_VERSION:-}" ]; then
    echo "install.sh: run it with bash: ./install.sh" >&2
    exit 2
fi

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"

main "$@"
