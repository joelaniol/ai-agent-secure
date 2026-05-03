# Read this file first when working on Shell-Secure CLI config mutations.
# Purpose: add/remove protected paths, whitelist safe targets, and toggle protection.
# Scope: parser/writer semantics belong to cli-config.sh; install/update belongs to cli-install.sh.

do_add() {
    local path="$1"
    local key
    if [ -z "$path" ]; then
        err "Pfad angeben: shell-secure add <pfad>"
        return 1
    fi

    local config="$INSTALL_DIR/config.conf"
    if [ ! -f "$config" ]; then
        err "Nicht installiert. Zuerst: shell-secure install"
        return 1
    fi

    cfg_load "$config" || {
        err "Konfiguration konnte nicht gelesen werden."
        return 1
    }

    key=$(normalize_path_key "$path")
    for dir in "${SHELL_SECURE_PROTECTED_DIRS[@]}"; do
        if [ "$(normalize_path_key "$dir")" = "$key" ]; then
            info "Bereits geschützt: $dir"
            return 0
        fi
    done

    SHELL_SECURE_PROTECTED_DIRS+=("${path//\\//}")
    cfg_write "$config"
    ok "Geschütztes Verzeichnis hinzugefügt: $path"
    info "Neue Shell öffnen oder: source ~/.bashrc"
}

do_remove_dir() {
    local path="$1"
    local key
    local -a kept=()
    if [ -z "$path" ]; then
        err "Pfad angeben: shell-secure remove <pfad>"
        return 1
    fi

    local config="$INSTALL_DIR/config.conf"
    if [ ! -f "$config" ]; then
        err "Nicht installiert."
        return 1
    fi

    cfg_load "$config" || {
        err "Konfiguration konnte nicht gelesen werden."
        return 1
    }

    key=$(normalize_path_key "$path")
    for dir in "${SHELL_SECURE_PROTECTED_DIRS[@]}"; do
        if [ "$(normalize_path_key "$dir")" != "$key" ]; then
            kept+=("$dir")
        fi
    done

    if [ ${#kept[@]} -eq ${#SHELL_SECURE_PROTECTED_DIRS[@]} ]; then
        warn "Nicht gefunden: $path"
        return 1
    fi

    SHELL_SECURE_PROTECTED_DIRS=("${kept[@]}")
    cfg_write "$config"
    ok "Entfernt: $path"
    info "Neue Shell öffnen oder: source ~/.bashrc"
}

do_whitelist() {
    local name="$1"
    local key
    if [ -z "$name" ]; then
        err "Name angeben: shell-secure whitelist <verzeichnisname>"
        return 1
    fi

    local config="$INSTALL_DIR/config.conf"
    if [ ! -f "$config" ]; then
        err "Nicht installiert."
        return 1
    fi

    cfg_load "$config" || {
        err "Konfiguration konnte nicht gelesen werden."
        return 1
    }

    key=$(normalize_name_key "$name")
    for safe in "${SHELL_SECURE_SAFE_TARGETS[@]}"; do
        if [ "$(normalize_name_key "$safe")" = "$key" ]; then
            info "Bereits erlaubt: $safe"
            return 0
        fi
    done

    SHELL_SECURE_SAFE_TARGETS+=("$name")
    cfg_write "$config"
    ok "Whitelist-Eintrag hinzugefügt: $name"
    info "Neue Shell öffnen oder: source ~/.bashrc"
}

do_enable() {
    local config="$INSTALL_DIR/config.conf"
    if [ ! -f "$config" ]; then
        err "Nicht installiert."
        return 1
    fi
    cfg_load "$config" || {
        err "Konfiguration konnte nicht gelesen werden."
        return 1
    }
    SHELL_SECURE_ENABLED=true
    cfg_write "$config"
    ok "Schutz aktiviert. Neue Shell öffnen oder: source ~/.bashrc"
}

do_disable() {
    local config="$INSTALL_DIR/config.conf"
    if [ ! -f "$config" ]; then
        err "Nicht installiert."
        return 1
    fi
    cfg_load "$config" || {
        err "Konfiguration konnte nicht gelesen werden."
        return 1
    }
    SHELL_SECURE_ENABLED=false
    cfg_write "$config"
    ok "Schutz deaktiviert. Neue Shell öffnen oder: source ~/.bashrc"
}
