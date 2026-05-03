# Read this file first when changing Shell-Secure CLI command dispatch.
# Purpose: render help and map CLI commands to focused action modules.
# Scope: concrete install, status, diagnostics, and config behavior stays in sibling CLI modules.

do_help() {
    echo ""
    echo -e "  ${BOLD}AI Agent Secure v${VERSION}${NC}"
    echo "  Shell- und Git-Schutz fuer AI Coding Agents"
    echo ""
    echo -e "  ${BOLD}Verwendung:${NC} shell-secure <befehl> [argumente]"
    echo ""
    echo -e "  ${BOLD}Befehle:${NC}"
    echo "    install           Schutz installieren"
    echo "    uninstall         Schutz komplett entfernen"
    echo "    update            Protection-Script aktualisieren"
    echo "    enable            Schutz aktivieren"
    echo "    disable           Schutz temporaer deaktivieren"
    echo "    status            Aktuellen Status anzeigen"
    echo "    test              Schutz testen"
    echo ""
    echo "    add <pfad>        Geschuetztes Verzeichnis hinzufuegen"
    echo "    remove <pfad>     Geschuetztes Verzeichnis entfernen"
    echo "    whitelist <name>  Verzeichnisname zur Whitelist hinzufuegen"
    echo "    log [n]           Letzte n blockierte Operationen (Standard: 20)"
    echo ""
    echo "    flood <sub>       Git-Flood-Schutz steuern:"
    echo "                        enable|disable|show"
    echo "                        threshold <n>   max Netzwerk-Calls"
    echo "                        window <s>      Zeitfenster in Sekunden"
    echo "    ps-utf8 <sub>     PowerShell-UTF-8-Pflicht steuern:"
    echo "                        enable|disable|show"
    echo ""
    echo -e "  ${BOLD}Beispiele:${NC}"
    echo "    shell-secure install"
    echo "    shell-secure add \"F:/-=Projekte=-\""
    echo "    shell-secure whitelist .mypy_cache"
    echo "    shell-secure disable"
    echo "    shell-secure flood threshold 8"
    echo "    shell-secure ps-utf8 disable"
    echo ""
    echo -e "  ${BOLD}Umgehen (fuer manuelle Operationen):${NC}"
    echo "    command rm -rf <pfad>       # Echten rm aufrufen"
    echo "    command cmd /c \"...\"        # Echtes cmd aufrufen"
    echo ""
}

main() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "$cmd" in
        install)    do_install ;;
        uninstall)  do_uninstall ;;
        update)     do_update ;;
        enable)     do_enable ;;
        disable)    do_disable ;;
        status)     do_status ;;
        test)       do_test ;;
        add)        do_add "${1:-}" ;;
        remove)     do_remove_dir "${1:-}" ;;
        whitelist)  do_whitelist "${1:-}" ;;
        flood)      do_flood "${1:-}" "${2:-}" ;;
        ps-utf8)    do_ps_utf8 "${1:-}" ;;
        log)        do_log "${1:-20}" ;;
        help|--help|-h)
                    do_help ;;
        version|--version|-v)
                    echo "AI Agent Secure v${VERSION} (shell-secure CLI)" ;;
        *)
            err "Unbekannter Befehl: $cmd"
            do_help
            exit 1
            ;;
    esac
}
