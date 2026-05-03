# Read this file first when working on the Shell-Secure setup UI slice.
# Purpose: provide setup UI runtime helpers, BASH_ENV detection, status classification, and header rendering.
# Scope: shared runtime state only; install and management actions stay in focused setup modules.

clear_screen() { printf '\033[2J\033[H'; }

is_installed() {
    [ -f "$INSTALL_DIR/protection.sh" ] && [ -f "$INSTALL_DIR/config.conf" ]
}

is_active() {
    is_installed || return 1
    cfg_load "$INSTALL_DIR/config.conf" || return 1
    [ "${SHELL_SECURE_ENABLED:-false}" = "true" ]
}

press_enter() {
    echo ""
    echo -ne "  ${D}Enter zum Fortfahren...${NC}"
    read -r
}

has_bashrc_hook() {
    grep -q "$MARKER_BEGIN" "$BASHRC" 2>/dev/null
}

expected_env_loader() {
    printf '%s' "$INSTALL_DIR/env-loader.sh"
}

normalize_env_path() {
    local path="$1"
    path="${path//$'\r'/}"
    path="${path//\\//}"
    if [[ "$path" =~ ^([a-zA-Z]):(/.*)?$ ]]; then
        local drive="${BASH_REMATCH[1],,}"
        local rest="${BASH_REMATCH[2]}"
        path="/$drive$rest"
    fi
    path="${path%/}"
    printf '%s' "${path,,}"
}

previous_bash_env_file() {
    printf '%s' "$INSTALL_DIR/previous-bash-env.txt"
}

read_previous_bash_env() {
    local file line
    file=$(previous_bash_env_file)
    if [ -f "$file" ]; then
        IFS= read -r line < "$file" || true
        printf '%s' "$line"
    fi
}

write_previous_bash_env() {
    local file current="$1"
    file=$(previous_bash_env_file)
    if [ -z "$current" ]; then
        rm -f "$file"
    elif [ "$(normalize_env_path "$current")" != "$(normalize_env_path "$(expected_env_loader)")" ]; then
        printf '%s\n' "$current" > "$file"
    fi
}

has_live_previous_bash_env() {
    local previous
    previous=$(read_previous_bash_env)
    # Match env-loader.sh: a recorded previous loader is active only while the file exists.
    [ -n "$previous" ] && [ -f "$previous" ]
}

current_user_bash_env() {
    if command -v powershell >/dev/null 2>&1; then
        powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('BASH_ENV', 'User')" 2>/dev/null | tr -d '\r'
    else
        printf '%s' "${BASH_ENV:-}"
    fi
}

powershell_quote() {
    local value="$1"
    value="${value//\'/\'\'}"
    printf "'%s'" "$value"
}

is_session_active() {
    [ "${SHELL_SECURE_ACTIVE:-}" = "true" ]
}

has_runtime_files() {
    [ -f "$INSTALL_DIR/protection.sh" ] && [ -f "$INSTALL_DIR/config.conf" ] && [ -f "$INSTALL_DIR/env-loader.sh" ]
}

is_owned_bash_env() {
    [ "$(normalize_env_path "$(current_user_bash_env)")" = "$(normalize_env_path "$(expected_env_loader)")" ]
}

has_foreign_bash_env() {
    local current
    current=$(current_user_bash_env)
    [ -n "$current" ] && [ "$(normalize_env_path "$current")" != "$(normalize_env_path "$(expected_env_loader)")" ]
}

protection_state() {
    if ! is_installed; then
        printf '%s' "not_installed"
    elif ! is_active; then
        printf '%s' "disabled"
    elif ! has_runtime_files; then
        printf '%s' "repair_needed"
    elif has_foreign_bash_env; then
        printf '%s' "env_conflict"
    elif is_owned_bash_env && has_bashrc_hook; then
        if is_session_active; then
            printf '%s' "active_full"
        else
            printf '%s' "reload_needed"
        fi
    elif has_bashrc_hook || is_owned_bash_env; then
        if is_session_active; then
            printf '%s' "active_partial"
        else
            printf '%s' "reload_needed"
        fi
    else
        printf '%s' "repair_needed"
    fi
}

# ── Header ───────────────────────────────────────────────────

show_header() {
    clear_screen
    local status_text status_color
    case "$(protection_state)" in
        not_installed) status_text="Nicht installiert"; status_color="$R" ;;
        disabled) status_text="AUS - Schutz deaktiviert"; status_color="$Y" ;;
        active_full) status_text="AN - Vollschutz aktiv"; status_color="$G" ;;
        active_partial) status_text="AN - Teilweise aktiv"; status_color="$Y" ;;
        reload_needed) status_text="AN - Neu laden nötig"; status_color="$Y" ;;
        env_conflict) status_text="AN - BASH_ENV Konflikt"; status_color="$Y" ;;
        *) status_text="AN - Reparatur nötig"; status_color="$R" ;;
    esac

    echo ""
    echo -e "  ${B}┌────────────────────────────────────────────┐${NC}"
    echo -e "  ${B}│${NC}   AI Agent Secure v${VERSION}                    ${B}│${NC}"
    echo -e "  ${B}│${NC}   ${D}Shell- und Git-Schutz für Agents${NC}      ${B}│${NC}"
    echo -e "  ${B}│${NC}                                            ${B}│${NC}"
    echo -e "  ${B}│${NC}   Status: ${status_color}${status_text}${NC}$(printf '%*s' $((20 - ${#status_text})) '')${B}│${NC}"
    echo -e "  ${B}└────────────────────────────────────────────┘${NC}"
    echo ""
}
