#!/bin/bash
# ============================================================
#  AI Agent Secure - Einfacher Installer
#  Einfach ausfuehren: bash setup.sh
#  Purpose: thin setup entrypoint for Git Bash users.
#  Scope: initialize shared constants, source focused setup modules, and dispatch main().
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Robust HOME detection (fallback if HOME is empty)
: "${HOME:=$(cd ~ 2>/dev/null && pwd)}"
: "${HOME:=/c/Users/$(whoami 2>/dev/null || echo $USERNAME)}"
export HOME

INSTALL_DIR="$HOME/.shell-secure"
BASHRC="$HOME/.bashrc"
MARKER_BEGIN="# >>> shell-secure >>>"
MARKER_END="# <<< shell-secure <<<"
VERSION="1.0.3"

# Setup UI colors
R='\033[0;31m'    # Rot
G='\033[0;32m'    # Gruen
Y='\033[1;33m'    # Gelb
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
