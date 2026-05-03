#!/bin/bash
# ============================================================
#  AI Agent Secure - simple installer
#  Run with: bash setup.sh
#  Purpose: thin setup entrypoint for Git Bash users.
#  Scope: initialize shared constants, source focused setup modules, and dispatch main().
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Robust HOME detection (fallback if HOME is unset or empty).
if [ -z "${HOME:-}" ]; then
    HOME="$(cd ~ 2>/dev/null && pwd || true)"
fi
if [ -z "${HOME:-}" ]; then
    HOME="/c/Users/$(whoami 2>/dev/null || printf '%s' "${USERNAME:-User}")"
fi
export HOME

INSTALL_DIR="$HOME/.shell-secure"
BASHRC="$HOME/.bashrc"
MARKER_BEGIN="# >>> shell-secure >>>"
MARKER_END="# <<< shell-secure <<<"
VERSION="1.1.0"

# Setup UI colors
R='\033[0;31m'    # Red
G='\033[0;32m'    # Green
Y='\033[1;33m'    # Yellow
C='\033[0;36m'    # Cyan
B='\033[1m'       # Bold
D='\033[2m'       # Dim
NC='\033[0m'      # Reset

source "$SCRIPT_DIR/lib/setup-config.sh"
source "$SCRIPT_DIR/lib/setup-runtime.sh"
source "$SCRIPT_DIR/lib/setup-install.sh"
source "$SCRIPT_DIR/lib/setup-status.sh"
source "$SCRIPT_DIR/lib/setup-manage.sh"
source "$SCRIPT_DIR/lib/setup-menu.sh"

main "$@"
