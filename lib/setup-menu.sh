# Read this file first when working on the Shell-Secure setup UI slice.
# Purpose: own the interactive setup menu and command dispatch.
# Scope: entrypoint orchestration only; concrete actions stay in sibling setup modules.

show_menu() {
    show_header
    local state
    state=$(protection_state)

    if ! is_installed; then
        echo -e "  ${B}[1]${NC}  Installieren"
        echo -e "  ${D}[2]  Deinstallieren${NC}"
        echo ""
        echo -e "  ${D}[3]  Schutz AN${NC}"
        echo -e "  ${D}[4]  Schutz AUS${NC}"
        echo ""
        echo -e "  ${D}[5]  Status & Details${NC}"
        echo -e "  ${D}[6]  Verzeichnisse verwalten${NC}"
        echo ""
        echo -e "  ${B}[q]${NC}  Beenden"
    elif [ "$state" = "disabled" ]; then
        echo -e "  ${D}[1]  Installieren${NC}"
        echo -e "  ${B}[2]${NC}  Deinstallieren"
        echo ""
        echo -e "  ${B}[3]${NC}  Schutz AN"
        echo -e "  ${D}[4]  Schutz AUS  ${Y}(deaktiviert)${NC}"
        echo ""
        echo -e "  ${B}[5]${NC}  Status & Details"
        echo -e "  ${B}[6]${NC}  Verzeichnisse verwalten"
        echo ""
        echo -e "  ${B}[q]${NC}  Beenden"
    else
        echo -e "  ${D}[1]  Installieren${NC}"
        echo -e "  ${B}[2]${NC}  Deinstallieren"
        echo ""
        if [ "$state" = "active_full" ]; then
            echo -e "  ${D}[3]  Schutz AN  ${G}(voll aktiv)${NC}"
        elif [ "$state" = "reload_needed" ]; then
            echo -e "  ${D}[3]  Schutz AN  ${Y}(neu laden)${NC}"
        elif [ "$state" = "env_conflict" ]; then
            echo -e "  ${D}[3]  Schutz AN  ${Y}(BASH_ENV Konflikt)${NC}"
        elif [ "$state" = "repair_needed" ]; then
            echo -e "  ${D}[3]  Schutz AN  ${R}(reparieren)${NC}"
        else
            echo -e "  ${D}[3]  Schutz AN  ${Y}(teilweise aktiv)${NC}"
        fi
        echo -e "  ${B}[4]${NC}  Schutz AUS"
        echo ""
        echo -e "  ${B}[5]${NC}  Status & Details"
        echo -e "  ${B}[6]${NC}  Verzeichnisse verwalten"
        echo ""
        echo -e "  ${B}[q]${NC}  Beenden"
    fi

    echo ""
    echo -ne "  Auswahl: "
}

# ── Main Loop ────────────────────────────────────────────────

main() {
    # Direct command mode (for CLI usage)
    if [ $# -gt 0 ]; then
        case "$1" in
            install)    do_install ;;
            uninstall)  do_uninstall ;;
            on)         do_toggle_on ;;
            off)        do_toggle_off ;;
            status)     do_status ;;
            dirs)       do_manage_dirs ;;
            add)        shift; do_add_dir_cli "$@" ;;
            *)
                echo "Verwendung: setup.sh [install|uninstall|on|off|status|dirs]"
                echo "            setup.sh add <pfad>"
                echo "Ohne Argumente: Interaktives Menü"
                ;;
        esac
        return
    fi

    # Interactive menu mode
    while true; do
        show_menu
        read -r choice
        case "$choice" in
            1) do_install ;;
            2) do_uninstall ;;
            3) do_toggle_on ;;
            4) do_toggle_off ;;
            5) do_status ;;
            6) do_manage_dirs ;;
            q|Q) clear_screen; echo -e "  ${D}Bye!${NC}"; echo ""; break ;;
            *) ;;
        esac
    done
}
