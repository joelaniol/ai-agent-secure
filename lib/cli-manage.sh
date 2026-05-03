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
            info "Bereits geschuetzt: $dir"
            return 0
        fi
    done

    SHELL_SECURE_PROTECTED_DIRS+=("${path//\\//}")
    cfg_write "$config"
    ok "Geschuetztes Verzeichnis hinzugefuegt: $path"
    info "Neue Shell oeffnen oder: source ~/.bashrc"
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
    info "Neue Shell oeffnen oder: source ~/.bashrc"
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
    ok "Whitelist-Eintrag hinzugefuegt: $name"
    info "Neue Shell oeffnen oder: source ~/.bashrc"
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
    ok "Schutz aktiviert. Neue Shell oeffnen oder: source ~/.bashrc"
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
    ok "Schutz deaktiviert. Neue Shell oeffnen oder: source ~/.bashrc"
}

# Lädt Config und ruft warn-Pfad ab; gibt 0 zurück wenn die Config gelesen
# werden konnte. Helper für die per-Layer-Subkommandos, damit die immer
# erst die aktuelle Config sehen, bevor sie schreiben.
_cli_load_config_or_err() {
    local config="$INSTALL_DIR/config.conf"
    if [ ! -f "$config" ]; then
        err "Nicht installiert. Zuerst: shell-secure install"
        return 1
    fi
    cfg_load "$config" || {
        err "Konfiguration konnte nicht gelesen werden."
        return 1
    }
    return 0
}

do_flood() {
    local sub="${1:-show}"
    local arg="${2:-}"
    _cli_load_config_or_err || return 1
    local config="$INSTALL_DIR/config.conf"

    case "$sub" in
        enable|on)
            SHELL_SECURE_GIT_FLOOD_PROTECT=true
            cfg_write "$config"
            ok "Git-Flood-Schutz aktiviert (max ${SHELL_SECURE_GIT_FLOOD_THRESHOLD:-4} / ${SHELL_SECURE_GIT_FLOOD_WINDOW:-60}s)."
            ;;
        disable|off)
            SHELL_SECURE_GIT_FLOOD_PROTECT=false
            cfg_write "$config"
            ok "Git-Flood-Schutz deaktiviert."
            ;;
        threshold)
            if [[ ! "$arg" =~ ^[0-9]+$ ]] || [ "$arg" -lt 1 ]; then
                err "Schwellwert muss eine positive Zahl sein: shell-secure flood threshold <n>"
                return 1
            fi
            SHELL_SECURE_GIT_FLOOD_THRESHOLD="$arg"
            cfg_write "$config"
            ok "Git-Flood-Schwellwert: ${arg} Calls / ${SHELL_SECURE_GIT_FLOOD_WINDOW:-60}s."
            ;;
        window)
            if [[ ! "$arg" =~ ^[0-9]+$ ]] || [ "$arg" -lt 1 ]; then
                err "Fenster muss eine positive Zahl in Sekunden sein: shell-secure flood window <s>"
                return 1
            fi
            SHELL_SECURE_GIT_FLOOD_WINDOW="$arg"
            cfg_write "$config"
            ok "Git-Flood-Fenster: ${SHELL_SECURE_GIT_FLOOD_THRESHOLD:-4} Calls / ${arg}s."
            ;;
        show|"")
            local state="${SHELL_SECURE_GIT_FLOOD_PROTECT:-true}"
            local th="${SHELL_SECURE_GIT_FLOOD_THRESHOLD:-4}"
            local win="${SHELL_SECURE_GIT_FLOOD_WINDOW:-60}"
            echo "  Git-Flood-Schutz: $state"
            echo "  Schwellwert:      $th Calls"
            echo "  Zeitfenster:      ${win}s"
            ;;
        *)
            err "Unbekanntes Sub-Kommando: shell-secure flood $sub"
            echo "  Verwendung: shell-secure flood enable|disable|threshold <n>|window <s>|show"
            return 1
            ;;
    esac
}

do_ps_utf8() {
    local sub="${1:-show}"
    _cli_load_config_or_err || return 1
    local config="$INSTALL_DIR/config.conf"

    case "$sub" in
        enable|on)
            SHELL_SECURE_PS_ENCODING_PROTECT=true
            cfg_write "$config"
            ok "PowerShell-UTF-8-Pflicht aktiviert."
            ;;
        disable|off)
            SHELL_SECURE_PS_ENCODING_PROTECT=false
            cfg_write "$config"
            ok "PowerShell-UTF-8-Pflicht deaktiviert."
            ;;
        show|"")
            local state="${SHELL_SECURE_PS_ENCODING_PROTECT:-true}"
            echo "  PowerShell-UTF-8-Pflicht: $state"
            ;;
        *)
            err "Unbekanntes Sub-Kommando: shell-secure ps-utf8 $sub"
            echo "  Verwendung: shell-secure ps-utf8 enable|disable|show"
            return 1
            ;;
    esac
}
