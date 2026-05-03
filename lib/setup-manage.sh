# Read this file first when working on the Shell-Secure setup UI slice.
# Purpose: manage protected areas and safe target names in the setup UI and CLI.
# Scope: configuration list edits only; parser/writer semantics belong to setup-config.sh.

do_manage_dirs() {
    if ! is_installed; then
        echo -e "  ${R}Nicht installiert.${NC} Zuerst installieren."
        press_enter
        return
    fi

    while true; do
        show_header
        cfg_load "$INSTALL_DIR/config.conf"

        echo -e "  ${B}Geschützte Verzeichnisse${NC}"
        echo "  ────────────────────────────────────"
        echo ""

        if [ ${#SHELL_SECURE_PROTECTED_DIRS[@]} -eq 0 ]; then
            echo -e "  ${D}Keine Verzeichnisse geschützt.${NC}"
        else
            local i=1
            for dir in "${SHELL_SECURE_PROTECTED_DIRS[@]}"; do
                echo -e "    ${C}${i}.${NC} $dir"
                ((i++))
            done
        fi

        echo ""
        echo "  ────────────────────────────────────"
        echo -e "  ${B}[a]${NC}  Verzeichnis hinzufügen"
        echo -e "  ${B}[d]${NC}  Verzeichnis entfernen"
        echo -e "  ${B}[w]${NC}  Whitelist verwalten"
        echo -e "  ${B}[z]${NC}  Zurück"
        echo ""
        echo -ne "  Auswahl: "
        read -r choice

        case "$choice" in
            a|A) do_add_dir ;;
            d|D) do_remove_dir ;;
            w|W) do_manage_whitelist ;;
            z|Z) return ;;
            *) ;;
        esac
    done
}

do_add_dir_cli() {
    local new_path="$*"
    if [ -z "$new_path" ]; then
        echo -e "  ${R}Pfad angeben:${NC} setup.sh add <pfad>"
        echo ""
        echo "  Beispiele:"
        echo "    setup.sh add \"F:/Projekte\""
        echo "    setup.sh add \"//server/freigabe\""
        echo "    setup.sh add \"Z:/Netzlaufwerk\""
        return 1
    fi
    if ! is_installed; then
        echo -e "  ${R}Nicht installiert.${NC} Zuerst: setup.sh install"
        return 1
    fi
    cfg_load "$INSTALL_DIR/config.conf"
    local new_key
    new_key=$(normalize_path_key "$new_path")
    for dir in "${SHELL_SECURE_PROTECTED_DIRS[@]}"; do
        if [ "$(normalize_path_key "$dir")" = "$new_key" ]; then
            echo -e "  ${Y}Bereits geschützt:${NC} $new_path"
            return 0
        fi
    done
    SHELL_SECURE_PROTECTED_DIRS+=("$new_path")
    cfg_write "$INSTALL_DIR/config.conf"
    echo -e "  ${G}+${NC} Hinzugefügt: ${B}$new_path${NC}"
    echo -e "  ${Y}Hinweis:${NC} source ~/.bashrc"
}

do_add_dir() {
    echo ""
    echo -e "  ${B}Verzeichnis hinzufügen${NC}"
    echo ""
    echo -e "  ${D}Beispiele:${NC}"
    echo -e "  ${D}  D:/Projekte/MeinCode${NC}"
    echo -e "  ${D}  F:/Projekte${NC}"
    echo -e "  ${D}  //server/freigabe/daten${NC}"
    echo -e "  ${D}  Z:/Netzlaufwerk${NC}"
    echo ""
    echo -ne "  Pfad: "
    read -r new_path

    if [ -z "$new_path" ]; then
        echo -e "  ${D}Abgebrochen.${NC}"
        press_enter
        return
    fi

    # Trim whitespace
    new_path=$(echo "$new_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Check if already exists
    cfg_load "$INSTALL_DIR/config.conf"
    local new_key
    new_key=$(normalize_path_key "$new_path")
    for dir in "${SHELL_SECURE_PROTECTED_DIRS[@]}"; do
        if [ "$(normalize_path_key "$dir")" = "$new_key" ]; then
            echo -e "  ${Y}Bereits geschützt:${NC} $new_path"
            press_enter
            return
        fi
    done

    SHELL_SECURE_PROTECTED_DIRS+=("$new_path")
    cfg_write "$INSTALL_DIR/config.conf"

    echo ""
    echo -e "  ${G}+${NC} Hinzugefügt: ${B}$new_path${NC}"
    echo -e "  ${Y}Hinweis:${NC} Neue Shell öffnen oder: ${C}source ~/.bashrc${NC}"
    press_enter
}

do_remove_dir() {
    cfg_load "$INSTALL_DIR/config.conf"

    if [ ${#SHELL_SECURE_PROTECTED_DIRS[@]} -eq 0 ]; then
        echo -e "  ${D}Keine Verzeichnisse vorhanden.${NC}"
        press_enter
        return
    fi

    echo ""
    echo -ne "  Nummer des zu entfernenden Verzeichnisses: "
    read -r num

    if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt ${#SHELL_SECURE_PROTECTED_DIRS[@]} ]; then
        echo -e "  ${R}Ungültige Nummer.${NC}"
        press_enter
        return
    fi

    local target="${SHELL_SECURE_PROTECTED_DIRS[$((num-1))]}"
    unset 'SHELL_SECURE_PROTECTED_DIRS[$((num-1))]'
    SHELL_SECURE_PROTECTED_DIRS=("${SHELL_SECURE_PROTECTED_DIRS[@]}")
    cfg_write "$INSTALL_DIR/config.conf"

    echo -e "  ${G}-${NC} Entfernt: ${B}$target${NC}"
    echo -e "  ${Y}Hinweis:${NC} Neue Shell öffnen oder: ${C}source ~/.bashrc${NC}"
    press_enter
}

do_manage_whitelist() {
    while true; do
        show_header
        cfg_load "$INSTALL_DIR/config.conf"

        echo -e "  ${B}Whitelist (dürfen gelöscht werden)${NC}"
        echo "  ────────────────────────────────────"
        echo ""

        local i=1
        local col=0
        local line_buf=""
        for safe in "${SHELL_SECURE_SAFE_TARGETS[@]}"; do
            line_buf+=$(printf "  ${D}%-18s${NC}" "$safe")
            ((col++))
            if [ $col -ge 3 ]; then
                echo -e "$line_buf"
                line_buf=""
                col=0
            fi
        done
        [ -n "$line_buf" ] && echo -e "$line_buf"

        echo ""
        echo "  ────────────────────────────────────"
        echo -e "  ${B}[a]${NC}  Name hinzufügen"
        echo -e "  ${B}[z]${NC}  Zurück"
        echo ""
        echo -ne "  Auswahl: "
        read -r choice

        case "$choice" in
            a|A)
                echo -ne "  Verzeichnisname (z.B. .mypy_cache): "
                read -r name
                if [ -n "$name" ]; then
                    local norm
                    norm=$(normalize_name_key "$name")
                    local safe
                    for safe in "${SHELL_SECURE_SAFE_TARGETS[@]}"; do
                        if [ "$(normalize_name_key "$safe")" = "$norm" ]; then
                            echo -e "  ${Y}Bereits vorhanden:${NC} $name"
                            press_enter
                            continue 2
                        fi
                    done
                    SHELL_SECURE_SAFE_TARGETS+=("$name")
                    cfg_write "$INSTALL_DIR/config.conf"
                    echo -e "  ${G}+${NC} Whitelist: ${B}$name${NC}"
                    echo -e "  ${Y}Hinweis:${NC} source ~/.bashrc"
                    press_enter
                fi
                ;;
            z|Z) return ;;
            *) ;;
        esac
    done
}
