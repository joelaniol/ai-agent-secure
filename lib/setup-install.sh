# Read this file first when working on the Shell-Secure setup UI slice.
# Purpose: install, uninstall, and toggle Shell-Secure from the setup UI or CLI.
# Scope: filesystem installation and enabled flag changes only; status rendering and directory management stay separate.

# Konkateniert die Slice-Dateien lib/protection-*.sh in der gleichen Reihen-
# folge wie build-gui.ps1 und lib/cli-install.sh in eine einzige Runtime-Datei.
write_protection_bundle() {
    local target="$1"
    local slices=(
        "protection-core.sh"
        "protection-i18n.sh"
        "protection-tokenize.sh"
        "protection-delete.sh"
        "protection-ps.sh"
        "protection-git.sh"
        "protection-env.sh"
    )
    {
        local s
        for s in "${slices[@]}"; do
            cat "$SCRIPT_DIR/lib/$s"
        done
        printf '\nexport SHELL_SECURE_ACTIVE=true\n'
    } > "$target"
}

do_install() {
    show_header
    echo -e "  ${B}Installation${NC}"
    echo "  ────────────────────────────────────"
    echo ""

    if is_installed; then
        echo -e "  ${Y}Bereits installiert.${NC} Moechtest du neu installieren?"
        echo -ne "  [j/N]: "
        read -r answer
        if [[ ! "$answer" =~ ^[jJyY]$ ]]; then
            return
        fi
    fi

    # 1. Verzeichnis erstellen
    mkdir -p "$INSTALL_DIR"
    echo -e "  ${G}+${NC} Verzeichnis erstellt: ~/.shell-secure/"

    # 2. Dateien kopieren
    write_protection_bundle "$INSTALL_DIR/protection.sh"
    echo -e "  ${G}+${NC} Schutz-Script kopiert"

    if [ ! -f "$INSTALL_DIR/config.conf" ]; then
        cp "$SCRIPT_DIR/config/default.conf" "$INSTALL_DIR/config.conf"
        cfg_add_fresh_install_default_areas "$INSTALL_DIR/config.conf"
        echo -e "  ${G}+${NC} Standard-Konfiguration erstellt"
    else
        echo -e "  ${C}=${NC} Bestehende Konfiguration beibehalten"
    fi

    # 3. Log-Datei
    touch "$INSTALL_DIR/blocked.log"

    # 4. Env-Loader fuer nicht-interaktive Shells
    cat > "$INSTALL_DIR/env-loader.sh" << 'EOF'
#!/bin/bash
prev_file="$HOME/.shell-secure/previous-bash-env.txt"
if [ -f "$prev_file" ]; then
    IFS= read -r prev < "$prev_file"
    if [ -n "$prev" ] && [ "$prev" != "$HOME/.shell-secure/env-loader.sh" ] && [ -f "$prev" ]; then
        source "$prev"
    fi
fi
if [ -f "$HOME/.shell-secure/protection.sh" ]; then
    source "$HOME/.shell-secure/protection.sh"
fi
EOF
    chmod +x "$INSTALL_DIR/env-loader.sh"
    write_previous_bash_env "$(current_user_bash_env)"

    # 5. .bashrc aktualisieren
    if has_bashrc_hook; then
        echo -e "  ${C}=${NC} .bashrc Eintrag existiert bereits"
    else
        touch "$BASHRC"
        cat >> "$BASHRC" << 'BASHRC_BLOCK'

# >>> shell-secure >>>
# AI Agent Secure: Shell-Secure Schutz-Core
if [ -f "$HOME/.shell-secure/protection.sh" ]; then
    source "$HOME/.shell-secure/protection.sh"
fi
# <<< shell-secure <<<
BASHRC_BLOCK
        echo -e "  ${G}+${NC} .bashrc aktualisiert"
    fi

    echo ""
    echo -e "  ${G}${B}Fertig!${NC}"
    echo ""
    echo "  Was jetzt geschuetzt ist:"
    echo "  ─────────────────────────"
    cfg_load "$INSTALL_DIR/config.conf"
    for dir in "${SHELL_SECURE_PROTECTED_DIRS[@]}"; do
        echo -e "    ${G}>${NC} $dir"
    done
    echo ""
    echo "  Was blockiert wird:"
    echo "  ─────────────────────────"
    echo -e "    ${R}x${NC} rm -rf <ordner>         (in geschuetzten Pfaden)"
    echo -e "    ${R}x${NC} cmd /c rmdir /s /q ...  (in geschuetzten Pfaden)"
    echo -e "    ${R}x${NC} powershell Remove-Item   (in geschuetzten Pfaden)"
    echo ""
    echo "  Was erlaubt bleibt:"
    echo "  ─────────────────────────"
    echo -e "    ${G}>${NC} rm -rf node_modules, dist, build, .cache ..."
    echo -e "    ${G}>${NC} rm einzelne Dateien (ohne -r)"
    echo -e "    ${G}>${NC} Alles ausserhalb der geschuetzten Pfade"
    echo ""
    echo -e "  ${Y}Wichtig:${NC} Neue Shell oeffnen oder ausfuehren:"
    echo -e "  ${C}source ~/.bashrc${NC}"

    press_enter
}

# ── Uninstall ────────────────────────────────────────────────

do_uninstall() {
    show_header
    echo -e "  ${B}Deinstallation${NC}"
    echo "  ────────────────────────────────────"
    echo ""

    if ! is_installed; then
        echo -e "  ${D}Nicht installiert - nichts zu tun.${NC}"
        press_enter
        return
    fi

    echo "  Alles wird auf Standard zurueckgesetzt:"
    echo -e "    - ~/.shell-secure/ wird ${R}geloescht${NC}"
    echo -e "    - .bashrc Eintrag wird ${R}entfernt${NC}"
    echo ""
    echo -ne "  Bist du sicher? [j/N]: "
    read -r answer
    if [[ ! "$answer" =~ ^[jJyY]$ ]]; then
        echo -e "  ${D}Abgebrochen.${NC}"
        press_enter
        return
    fi

    # .bashrc bereinigen
    if has_bashrc_hook; then
        local tmpfile
        tmpfile=$(mktemp)
        local in_block=false
        local prev_empty=false
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == *"$MARKER_BEGIN"* ]]; then
                in_block=true
                continue
            fi
            if [[ "$line" == *"$MARKER_END"* ]]; then
                in_block=false
                continue
            fi
            if ! $in_block; then
                echo "$line" >> "$tmpfile"
            fi
        done < "$BASHRC"
        cp "$tmpfile" "$BASHRC"
        rm -f "$tmpfile"
        echo -e "  ${G}+${NC} .bashrc bereinigt"
    fi

    # Log sichern
    if [ -s "$INSTALL_DIR/blocked.log" ]; then
        local backup="$HOME/shell-secure-log-backup.txt"
        cp "$INSTALL_DIR/blocked.log" "$backup"
        echo -e "  ${C}=${NC} Block-Log gesichert: $backup"
    fi

    # BASH_ENV aufraumen
    if is_owned_bash_env; then
        local previous_env
        previous_env=$(read_previous_bash_env)
        if [ -n "$previous_env" ]; then
            powershell -c "[Environment]::SetEnvironmentVariable('BASH_ENV', $(powershell_quote "$previous_env"), 'User')" 2>/dev/null
            echo -e "  ${G}+${NC} Vorheriges BASH_ENV wiederhergestellt"
        else
            powershell -c "[Environment]::SetEnvironmentVariable('BASH_ENV', \$null, 'User')" 2>/dev/null
            echo -e "  ${G}+${NC} BASH_ENV Umgebungsvariable entfernt"
        fi
    fi

    # Verzeichnis loeschen
    command rm -rf "$INSTALL_DIR"
    echo -e "  ${G}+${NC} ~/.shell-secure/ entfernt"

    echo ""
    echo -e "  ${G}${B}Komplett deinstalliert - alles ist wieder Standard.${NC}"
    echo ""
    echo -e "  ${Y}Hinweis:${NC} Neue Shell oeffnen damit die Aenderung greift."

    press_enter
}

# ── Toggle On/Off ────────────────────────────────────────────

do_toggle_on() {
    if ! is_installed; then
        echo -e "  ${R}Nicht installiert.${NC} Zuerst installieren."
        press_enter
        return
    fi
    cfg_load "$INSTALL_DIR/config.conf"
    SHELL_SECURE_ENABLED=true
    cfg_write "$INSTALL_DIR/config.conf"
    show_header
    echo -e "  ${G}${B}Schutz ist jetzt AN${NC}"
    echo ""
    echo -e "  ${Y}Hinweis:${NC} Neue Shell oeffnen oder: ${C}source ~/.bashrc${NC}"
    press_enter
}

do_toggle_off() {
    if ! is_installed; then
        echo -e "  ${R}Nicht installiert.${NC}"
        press_enter
        return
    fi
    cfg_load "$INSTALL_DIR/config.conf"
    SHELL_SECURE_ENABLED=false
    cfg_write "$INSTALL_DIR/config.conf"
    show_header
    echo -e "  ${Y}${B}Schutz ist jetzt AUS${NC}"
    echo ""
    echo "  Rekursives Loeschen ist nicht mehr blockiert."
    echo -e "  Wieder aktivieren: ${C}Menue > Schutz AN${NC}"
    press_enter
}
