# Read this file first when changing Shell-Secure CLI layer toggles.
# Purpose: manage per-protection-layer CLI subcommands such as flood, git-leak,
#          ps-utf8, and http-api.
# Scope: protected path and whitelist mutations stay in cli-manage.sh.

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

do_git_leak() {
    local sub="${1:-show}"
    local arg="${2:-}"
    _cli_load_config_or_err || return 1
    local config="$INSTALL_DIR/config.conf"

    case "$sub" in
        enable|on)
            SHELL_SECURE_GIT_LEAK_PROTECT=true
            cfg_write "$config"
            ok "Git-Leak-Schutz aktiviert (Timeout ${SHELL_SECURE_GIT_LEAK_TIMEOUT:-60}s)."
            ;;
        disable|off)
            SHELL_SECURE_GIT_LEAK_PROTECT=false
            cfg_write "$config"
            ok "Git-Leak-Schutz deaktiviert."
            ;;
        timeout)
            if [[ ! "$arg" =~ ^[0-9]+$ ]] || [ "$arg" -lt 1 ]; then
                err "Timeout muss eine positive Zahl in Sekunden sein: shell-secure git-leak timeout <s>"
                return 1
            fi
            SHELL_SECURE_GIT_LEAK_TIMEOUT="$arg"
            cfg_write "$config"
            ok "Git-Leak-Timeout: ${arg}s."
            ;;
        show|"")
            echo "  Git-Leak-Schutz: ${SHELL_SECURE_GIT_LEAK_PROTECT:-true}"
            echo "  Allow-Timeout:   ${SHELL_SECURE_GIT_LEAK_TIMEOUT:-60}s"
            ;;
        *)
            err "Unbekanntes Sub-Kommando: shell-secure git-leak $sub"
            echo "  Verwendung: shell-secure git-leak enable|disable|timeout <s>|show"
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

do_http_api() {
    local sub="${1:-show}"
    _cli_load_config_or_err || return 1
    local config="$INSTALL_DIR/config.conf"

    case "$sub" in
        enable|on)
            SHELL_SECURE_HTTP_API_PROTECT=true
            cfg_write "$config"
            ok "HTTP/API-Schutz aktiviert."
            ;;
        disable|off)
            SHELL_SECURE_HTTP_API_PROTECT=false
            cfg_write "$config"
            ok "HTTP/API-Schutz deaktiviert."
            ;;
        show|"")
            echo "  HTTP/API-Schutz: ${SHELL_SECURE_HTTP_API_PROTECT:-true}"
            ;;
        *)
            err "Unbekanntes Sub-Kommando: shell-secure http-api $sub"
            echo "  Verwendung: shell-secure http-api enable|disable|show"
            return 1
            ;;
    esac
}
