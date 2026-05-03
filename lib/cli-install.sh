# Read this file first when working on Shell-Secure CLI install/update behavior.
# Purpose: install, uninstall, update runtime files, and write the non-interactive shell loader.
# Scope: status rendering and config list edits stay in sibling CLI modules.

# Konkateniert die Slice-Dateien lib/protection-*.sh in genau der gleichen
# Reihenfolge wie build-gui.ps1 zu einer einzigen ~/.shell-secure/protection.sh
# zusammen. Nach dem Refactor ist lib/protection.sh nur noch ein Loader fuer
# Source-Level-Tests; der Runtime-Install liefert weiterhin EINE Datei,
# byte-identisch zum embedded Stand der GUI.
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

write_env_loader() {
    local bash_env_file="$INSTALL_DIR/env-loader.sh"
    cat > "$bash_env_file" << 'ENV_LOADER'
#!/bin/bash
# Shell-Secure env loader for non-interactive shells
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
ENV_LOADER
    chmod +x "$bash_env_file"
}

do_install() {
    echo ""
    echo -e "  ${BOLD}AI Agent Secure v${VERSION} - Installation${NC}"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    mkdir -p "$INSTALL_DIR"
    ok "Verzeichnis $INSTALL_DIR erstellt"

    write_protection_bundle "$INSTALL_DIR/protection.sh"
    ok "Protection-Script installiert"

    if [ -f "$INSTALL_DIR/config.conf" ]; then
        info "Bestehende Konfiguration beibehalten"
        info "Neue Defaults: $SCRIPT_DIR/config/default.conf"
    else
        cp "$SCRIPT_DIR/config/default.conf" "$INSTALL_DIR/config.conf"
        cfg_add_fresh_install_default_areas "$INSTALL_DIR/config.conf"
        ok "Standard-Konfiguration installiert"
    fi

    touch "$INSTALL_DIR/blocked.log"

    if has_bashrc_hook; then
        info ".bashrc Eintrag existiert bereits"
    else
        touch "$BASHRC"
        cat >> "$BASHRC" << 'BASHRC_BLOCK'

# >>> shell-secure >>>
# AI Agent Secure: Shell-Secure protection core
# Managed by shell-secure - do not edit this block manually
if [ -f "$HOME/.shell-secure/protection.sh" ]; then
    source "$HOME/.shell-secure/protection.sh"
fi
# <<< shell-secure <<<
BASHRC_BLOCK
        ok ".bashrc aktualisiert"
    fi

    local bash_env_file="$INSTALL_DIR/env-loader.sh"
    write_env_loader
    write_previous_bash_env "$(current_user_bash_env)"

    echo ""
    echo -e "  ${GREEN}${BOLD}Installation abgeschlossen!${NC}"
    echo ""
    echo "  Naechste Schritte:"
    echo "  ──────────────────"
    echo "  1. Neue Shell oeffnen oder: source ~/.bashrc"
    echo ""
    echo "  2. Fuer VOLLSTAENDIGEN Schutz (auch nicht-interaktive Shells):"
    echo "     Systemumgebungsvariable setzen:"
    echo ""
    echo "     BASH_ENV=$bash_env_file"
    echo ""
    echo "     PowerShell (Admin):"
    echo "     [Environment]::SetEnvironmentVariable('BASH_ENV',"
    echo "       '$bash_env_file', 'User')"
    echo ""
    echo "  3. Schutz testen: shell-secure test"
    echo ""
}

do_uninstall() {
    echo ""
    echo -e "  ${BOLD}AI Agent Secure - Deinstallation${NC}"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local previous_env=""
    if is_owned_bash_env; then
        previous_env=$(read_previous_bash_env)
    fi

    if grep -q "$MARKER_BEGIN" "$BASHRC" 2>/dev/null; then
        local tmpfile
        tmpfile=$(mktemp)
        local in_block=false
        while IFS= read -r line; do
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
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmpfile" 2>/dev/null || true
        cp "$tmpfile" "$BASHRC"
        rm -f "$tmpfile"
        ok ".bashrc bereinigt"
    else
        info ".bashrc hatte keinen AI Agent Secure Eintrag"
    fi

    if [ -d "$INSTALL_DIR" ]; then
        if [ -s "$INSTALL_DIR/blocked.log" ]; then
            local log_backup="$HOME/shell-secure-blocked.log.bak"
            cp "$INSTALL_DIR/blocked.log" "$log_backup"
            info "Block-Log gesichert: $log_backup"
        fi
        command rm -rf "$INSTALL_DIR"
        ok "$INSTALL_DIR entfernt"
    fi

    unset SHELL_SECURE_ACTIVE 2>/dev/null || true

    if is_owned_bash_env; then
        if [ -n "$previous_env" ]; then
            powershell -NoProfile -Command "[Environment]::SetEnvironmentVariable('BASH_ENV', $(powershell_quote "$previous_env"), 'User')" 2>/dev/null || true
            ok "Vorheriges BASH_ENV wiederhergestellt"
        else
            powershell -NoProfile -Command "[Environment]::SetEnvironmentVariable('BASH_ENV', \$null, 'User')" 2>/dev/null || true
            ok "BASH_ENV entfernt"
        fi
    fi

    echo ""
    echo -e "  ${GREEN}${BOLD}Deinstallation abgeschlossen!${NC}"
    echo ""
    if has_foreign_bash_env; then
        echo "  Hinweis: Vorhandenes fremdes BASH_ENV wurde nicht veraendert:"
        echo "  $(current_user_bash_env)"
        echo ""
    fi
    echo "  Neue Shell oeffnen um Aenderungen zu uebernehmen."
    echo ""
}

do_update() {
    if [ ! -d "$INSTALL_DIR" ]; then
        err "Nicht installiert. Zuerst: shell-secure install"
        return 1
    fi
    write_protection_bundle "$INSTALL_DIR/protection.sh"
    write_env_loader
    ok "Protection-Script und Env-Loader aktualisiert"
    info "Neue Shell oeffnen oder: source ~/.bashrc"
}
