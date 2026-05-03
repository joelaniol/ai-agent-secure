#!/bin/bash
# ============================================================
#  AI Agent Secure - shell-secure CLI
#  Usage: shell-secure <command> [args]
#  Purpose: thin scriptable CLI entry point.
#  Scope: initialize shared constants, source focused CLI modules, and dispatch main().
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.shell-secure"
BASHRC="$HOME/.bashrc"
MARKER_BEGIN="# >>> shell-secure >>>"
MARKER_END="# <<< shell-secure <<<"
VERSION="1.0.0"

# CLI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

source "$SCRIPT_DIR/lib/cli-config.sh"
source "$SCRIPT_DIR/lib/cli-runtime.sh"
source "$SCRIPT_DIR/lib/cli-install.sh"
source "$SCRIPT_DIR/lib/cli-manage.sh"
source "$SCRIPT_DIR/lib/cli-report.sh"
source "$SCRIPT_DIR/lib/cli-dispatch.sh"

main "$@"
