# Read this file first when working on Shell-Secure CLI status, logs, or diagnostics.
# Purpose: render CLI status, show blocked-operation logs, and run the interactive protection self-test.
# Scope: install/update and config mutations stay in sibling CLI modules.

do_status() {
    echo ""
    echo -e "  ${BOLD}AI Agent Secure Status${NC}"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local state current_env
    state=$(protection_state)
    current_env=$(current_user_bash_env)

    if is_installed; then
        ok "Installiert in $INSTALL_DIR"
    else
        err "Nicht installiert"
        echo ""
        return 1
    fi

    if has_bashrc_hook; then
        ok ".bashrc Eintrag vorhanden"
    else
        warn ".bashrc Eintrag fehlt"
    fi

    if is_session_active; then
        ok "Aktiv in dieser Shell-Session"
    else
        warn "Nicht aktiv in dieser Session (source ~/.bashrc ausführen)"
    fi

    if is_owned_bash_env; then
        if has_live_previous_bash_env; then
            ok "BASH_ENV gesetzt und mit bestehendem Loader verkettet"
        else
            ok "BASH_ENV gesetzt (nicht-interaktive Shells geschützt)"
        fi
    elif has_foreign_bash_env; then
        warn "BASH_ENV wird von anderem Loader verwendet: $current_env"
    else
        warn "BASH_ENV nicht gesetzt (nicht-interaktive Shells ungeschützt)"
    fi

    echo ""
    echo -e "  ${BOLD}Schutzstatus:${NC}"
    case "$state" in
        active_full)
            echo -e "    ${GREEN}Vollschutz aktiv${NC}"
            ;;
        active_partial)
            echo -e "    ${YELLOW}Teilweise aktiv${NC} (aktuelle Shell geschützt, aber nicht alle Startpfade)"
            ;;
        reload_needed)
            echo -e "    ${YELLOW}Neu laden nötig${NC} (Konfiguration aktiv, aktuelle Shell noch nicht neu geladen)"
            ;;
        env_conflict)
            echo -e "    ${YELLOW}BASH_ENV-Konflikt${NC} (anderer Loader gesetzt, AI Agent Secure nicht global aktiv)"
            ;;
        repair_needed)
            echo -e "    ${RED}Reparatur nötig${NC} (.bashrc/BASH_ENV oder Runtime-Dateien unvollständig)"
            ;;
        disabled)
            echo -e "    ${YELLOW}Deaktiviert${NC}"
            ;;
    esac

    if cfg_load "$INSTALL_DIR/config.conf"; then
        ok "Konfiguration vorhanden"
        echo ""
        echo -e "  ${BOLD}Schutzarten:${NC}"
        echo "    Delete:   ${SHELL_SECURE_DELETE_PROTECT:-true}"
        echo "    Git:      ${SHELL_SECURE_GIT_PROTECT:-true}"
        echo "    GitFlood: ${SHELL_SECURE_GIT_FLOOD_PROTECT:-true}"
        echo "    GitLeak:  ${SHELL_SECURE_GIT_LEAK_PROTECT:-true} (${SHELL_SECURE_GIT_LEAK_TIMEOUT:-60}s)"
        echo "    HTTP/API: ${SHELL_SECURE_HTTP_API_PROTECT:-true}"
        echo "    PS-UTF8:  ${SHELL_SECURE_PS_ENCODING_PROTECT:-true}"
        echo ""
        echo -e "  ${BOLD}Geschützte Verzeichnisse:${NC}"
        for dir in "${SHELL_SECURE_PROTECTED_DIRS[@]}"; do
            echo "    $dir"
        done
        echo ""
        echo -e "  ${BOLD}Erlaubte Löschziele:${NC} ${#SHELL_SECURE_SAFE_TARGETS[@]} Einträge"
        echo -e "  ${DIM}(node_modules, dist, build, .cache, ...)${NC}"
    fi

    if [ -f "$INSTALL_DIR/blocked.log" ]; then
        local count
        count=$(wc -l < "$INSTALL_DIR/blocked.log" 2>/dev/null || echo 0)
        echo ""
        echo -e "  ${BOLD}Blockierte Operationen:${NC} $count"
    fi

    echo ""
}

do_log() {
    local logfile="$INSTALL_DIR/blocked.log"
    if [ ! -f "$logfile" ] || [ ! -s "$logfile" ]; then
        info "Keine blockierten Operationen bisher."
        return 0
    fi

    local lines="${1:-20}"
    echo ""
    echo -e "  ${BOLD}Letzte $lines blockierte Operationen:${NC}"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    tail -n "$lines" "$logfile" | while IFS= read -r line; do
        echo "  $line"
    done
    echo ""
}

do_test() {
    echo ""
    echo -e "  ${BOLD}AI Agent Secure Test${NC}"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if ! is_session_active; then
        err "AI Agent Secure ist nicht aktiv in dieser Session."
        info "Führe aus: source ~/.bashrc"
        echo ""
        return 1
    fi

    local test_dir=""
    if cfg_load "$INSTALL_DIR/config.conf"; then
        if [ ${#SHELL_SECURE_PROTECTED_DIRS[@]} -gt 0 ]; then
            local first_protected="${SHELL_SECURE_PROTECTED_DIRS[0]}"
            test_dir="$first_protected/__shell_secure_test_$$"
        fi
    fi

    if [ -z "$test_dir" ]; then
        err "Keine geschützten Bereiche konfiguriert."
        return 1
    fi

    command mkdir -p "$test_dir"
    echo "test" > "$test_dir/testfile.txt"

    info "Test-Verzeichnis erstellt: $test_dir"

    echo ""
    echo -e "  ${BOLD}Test 1:${NC} rm -rf (sollte blockiert werden)"
    if rm -rf "$test_dir" 2>/dev/null; then
        err "FEHLGESCHLAGEN - rm -rf wurde NICHT blockiert!"
    else
        ok "rm -rf wurde blockiert"
    fi

    echo ""
    echo -e "  ${BOLD}Test 2:${NC} cmd /c rmdir /s /q (sollte blockiert werden)"
    if cmd /c "rmdir /s /q \"$test_dir\"" 2>/dev/null; then
        err "FEHLGESCHLAGEN - cmd rmdir wurde NICHT blockiert!"
    else
        ok "cmd rmdir wurde blockiert"
    fi

    echo ""
    echo -e "  ${BOLD}Test 3:${NC} rm -rf node_modules (sollte erlaubt sein)"
    local safe_dir="$first_protected/__shell_secure_test_$$/node_modules"
    command mkdir -p "$safe_dir"
    echo "test" > "$safe_dir/package.json"
    if rm -rf "$safe_dir" 2>&1 | grep -q "BLOCKIERT"; then
        err "FEHLGESCHLAGEN - Safe target wurde fälschlich blockiert!"
    else
        ok "Safe target (node_modules) wurde durchgelassen"
    fi

    command rm -rf "$test_dir" 2>/dev/null
    info "Test-Verzeichnis bereinigt"

    echo ""
    echo -e "  ${GREEN}${BOLD}Tests abgeschlossen.${NC}"
    echo ""
}
