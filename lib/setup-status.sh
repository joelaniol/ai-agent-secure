# Read this file first when working on the Shell-Secure setup UI slice.
# Purpose: render detailed Shell-Secure setup status for files, shell hooks, config, and logs.
# Scope: read-only status display only; mutations belong to install and management modules.

do_status() {
    show_header
    local current_env state
    state=$(protection_state)
    current_env=$(current_user_bash_env)
    echo -e "  ${B}Details${NC}"
    echo "  ────────────────────────────────────"
    echo ""

    if ! is_installed; then
        echo -e "  ${R}Nicht installiert.${NC}"
        press_enter
        return
    fi

    # Files
    echo -e "  ${B}Dateien:${NC}"
    [ -f "$INSTALL_DIR/protection.sh" ] && echo -e "    ${G}+${NC} protection.sh" || echo -e "    ${R}x${NC} protection.sh fehlt"
    [ -f "$INSTALL_DIR/config.conf" ]   && echo -e "    ${G}+${NC} config.conf"   || echo -e "    ${R}x${NC} config.conf fehlt"
    [ -f "$INSTALL_DIR/blocked.log" ]   && echo -e "    ${G}+${NC} blocked.log"   || echo -e "    ${D}-${NC} blocked.log"

    # .bashrc
    echo ""
    echo -e "  ${B}.bashrc:${NC}"
    if has_bashrc_hook; then
        echo -e "    ${G}+${NC} Eintrag vorhanden"
    else
        echo -e "    ${R}x${NC} Eintrag fehlt"
    fi

    # BASH_ENV
    echo ""
    echo -e "  ${B}BASH_ENV:${NC}"
    if is_owned_bash_env; then
        if has_live_previous_bash_env; then
            echo -e "    ${G}+${NC} Verkettet mit bestehendem Loader"
        else
            echo -e "    ${G}+${NC} Gesetzt (voller Schutz)"
        fi
    elif has_foreign_bash_env; then
        echo -e "    ${Y}!${NC} Fremder Loader gesetzt"
        echo -e "    ${D}  $current_env${NC}"
    else
        echo -e "    ${Y}!${NC} Nicht gesetzt (nur interaktive Shells geschützt)"
        echo -e "    ${D}  Setzen mit PowerShell (Admin):${NC}"
        echo -e "    ${D}  [Environment]::SetEnvironmentVariable('BASH_ENV',${NC}"
        echo -e "    ${D}    '$INSTALL_DIR/env-loader.sh', 'User')${NC}"
    fi

    cfg_load "$INSTALL_DIR/config.conf"

    echo ""
    echo -e "  ${B}Schutzstatus:${NC}"
    case "$state" in
        active_full) echo -e "    ${G}+${NC} Vollschutz aktiv" ;;
        active_partial) echo -e "    ${Y}!${NC} Teilweise aktiv" ;;
        reload_needed) echo -e "    ${Y}!${NC} Neu laden nötig" ;;
        env_conflict) echo -e "    ${Y}!${NC} BASH_ENV-Konflikt" ;;
        repair_needed) echo -e "    ${R}x${NC} Reparatur nötig" ;;
        disabled) echo -e "    ${Y}!${NC} Schutz deaktiviert" ;;
    esac

    echo ""
    echo -e "  ${B}Schutzarten:${NC}"
    if [ "${SHELL_SECURE_DELETE_PROTECT:-true}" = "true" ]; then
        echo -e "    ${G}+${NC} Rekursives Löschen"
    else
        echo -e "    ${Y}!${NC} Rekursives Löschen deaktiviert"
    fi
    if [ "${SHELL_SECURE_GIT_PROTECT:-true}" = "true" ]; then
        echo -e "    ${G}+${NC} Destruktive Git-Befehle"
    else
        echo -e "    ${Y}!${NC} Destruktive Git-Befehle deaktiviert"
    fi
    if [ "${SHELL_SECURE_GIT_FLOOD_PROTECT:-true}" = "true" ]; then
        local flood_t="${SHELL_SECURE_GIT_FLOOD_THRESHOLD:-4}"
        local flood_w="${SHELL_SECURE_GIT_FLOOD_WINDOW:-60}"
        echo -e "    ${G}+${NC} Git-Flood-Schutz (max ${flood_t} Calls / ${flood_w}s)"
    else
        echo -e "    ${Y}!${NC} Git-Flood-Schutz deaktiviert"
    fi
    if [ "${SHELL_SECURE_GIT_LEAK_PROTECT:-true}" = "true" ]; then
        local leak_timeout="${SHELL_SECURE_GIT_LEAK_TIMEOUT:-60}"
        echo -e "    ${G}+${NC} Git-Leak-Schutz (Allow-Timeout ${leak_timeout}s)"
    else
        echo -e "    ${Y}!${NC} Git-Leak-Schutz deaktiviert"
    fi
    if [ "${SHELL_SECURE_HTTP_API_PROTECT:-true}" = "true" ]; then
        echo -e "    ${G}+${NC} HTTP/API-Schutz für curl"
    else
        echo -e "    ${Y}!${NC} HTTP/API-Schutz deaktiviert"
    fi
    if [ "${SHELL_SECURE_PS_ENCODING_PROTECT:-true}" = "true" ]; then
        echo -e "    ${G}+${NC} PowerShell-UTF-8-Pflicht"
    else
        echo -e "    ${Y}!${NC} PowerShell-UTF-8-Pflicht deaktiviert"
    fi

    # Protected directories
    echo ""
    echo -e "  ${B}Geschützte Verzeichnisse:${NC}"
    for dir in "${SHELL_SECURE_PROTECTED_DIRS[@]}"; do
        echo -e "    ${G}>${NC} $dir"
    done

    # Whitelist
    echo ""
    echo -e "  ${B}Whitelist (darf gelöscht werden):${NC}"
    local list=""
    for safe in "${SHELL_SECURE_SAFE_TARGETS[@]}"; do
        list+="$safe, "
    done
    echo -e "    ${D}${list%, }${NC}"

    # Log
    echo ""
    echo -e "  ${B}Block-Log:${NC}"
    if [ -s "$INSTALL_DIR/blocked.log" ]; then
        local count
        count=$(wc -l < "$INSTALL_DIR/blocked.log")
        echo -e "    ${Y}${count}${NC} blockierte Operationen"
        echo ""
        echo -e "  ${B}Letzte 5 Einträge:${NC}"
        tail -5 "$INSTALL_DIR/blocked.log" | while IFS= read -r line; do
            echo -e "    ${D}$line${NC}"
        done
    else
        echo -e "    ${D}Noch keine blockierten Operationen${NC}"
    fi

    press_enter
}
