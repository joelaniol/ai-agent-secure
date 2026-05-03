# Read this file first when changing config loading, path normalisation, or block rendering.
# Purpose: shared variables, config parser, path utilities, log writer, and the generic
#          delete-block diagnostic. Used by every other protection slice.
# Scope: no command wrappers; those live in protection-delete.sh / protection-ps.sh /
#        protection-git.sh / protection-env.sh.

# Robust HOME detection (fallback if HOME is empty)
: "${HOME:=$(cd ~ 2>/dev/null && pwd)}"
: "${HOME:=/c/Users/$(whoami 2>/dev/null || echo "$USERNAME")}"

SHELL_SECURE_DIR="$HOME/.shell-secure"
SHELL_SECURE_CONFIG="$SHELL_SECURE_DIR/config.conf"
SHELL_SECURE_LOG="$SHELL_SECURE_DIR/blocked.log"
SHELL_SECURE_ENABLED=true
# Kategorie-Toggles. Default = an; Configs ohne diese Keys verhalten sich
# damit wie bisher ("alles an"), sodass Upgrade-Pfade rueckwaertskompatibel
# bleiben.
SHELL_SECURE_DELETE_PROTECT=true
SHELL_SECURE_GIT_PROTECT=true
# Git-Flood-Schutz: zaehlt Netzwerk-git-Calls (push/pull/fetch/clone/ls-remote)
# in einem Zeitfenster. Default 4 Calls pro 60 s. Schuetzt vor durchdrehenden
# Agents, die Auth-Prompts spammen oder versehentliche Push/Pull-Loops bauen.
SHELL_SECURE_GIT_FLOOD_PROTECT=true
SHELL_SECURE_GIT_FLOOD_THRESHOLD=4
SHELL_SECURE_GIT_FLOOD_WINDOW=60
# PowerShell-UTF-8-Schutz: blockt schreibende PS-Aufrufe ohne -Encoding utf8.
# Windows PowerShell 5.1 schreibt sonst UTF-16 LE BOM (Out-File, >) bzw. ANSI
# (Set-Content, Add-Content), was Quellcode-Dateien beschaedigt.
SHELL_SECURE_PS_ENCODING_PROTECT=true
# Language: "en" (default) or "de". Drives block-message text and GUI labels.
# Validated leniently - any value other than "de" falls back to English.
SHELL_SECURE_LANGUAGE=en
declare -ag SHELL_SECURE_PROTECTED_DIRS=()
declare -ag SHELL_SECURE_SAFE_TARGETS=()

# ── Helpers ──────────────────────────────────────────────────

_ss_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

_ss_unescape_config() {
    local s="$1"
    local marker=$'\001'
    s="${s//\\\\/$marker}"
    s="${s//\\\"/\"}"
    s="${s//\\\$/\$}"
    s="${s//\\\`/\`}"
    s="${s//$marker/\\}"
    printf '%s' "$s"
}

_ss_expand_config_path() {
    local p="$1"
    # Config-Dateien schreiben Logpfade oft als "$HOME/...", aber Bash
    # expandiert Variablen nicht erneut, wenn der Wert spaeter benutzt wird.
    # Deshalb loesen wir nur die explizit unterstuetzten Home-Prefixe auf.
    case "$p" in
        '$HOME'|'$HOME'/*)
            p="${HOME}${p#\$HOME}"
            ;;
        '${HOME}'|'${HOME}'/*)
            p="${HOME}${p#\$\{HOME\}}"
            ;;
        '~'|'~'/*)
            p="${HOME}${p#\~}"
            ;;
    esac
    printf '%s' "$p"
}

_ss_load_config() {
    local state="" line trimmed

    SHELL_SECURE_ENABLED=true
    # Default-on bei fehlendem Key -> bestehende Configs behalten vollen Schutz.
    SHELL_SECURE_DELETE_PROTECT=true
    SHELL_SECURE_GIT_PROTECT=true
    # Flood-Defaults bewusst konservativ: 4 Netzwerk-git-Calls pro 60 s. Das
    # blockt typische Agent-Loops, ohne normales Push-Pull-Pull-Push-Verhalten
    # zu stoeren.
    SHELL_SECURE_GIT_FLOOD_PROTECT=true
    SHELL_SECURE_GIT_FLOOD_THRESHOLD=4
    SHELL_SECURE_GIT_FLOOD_WINDOW=60
    SHELL_SECURE_PS_ENCODING_PROTECT=true
    SHELL_SECURE_LANGUAGE=en
    SHELL_SECURE_LOG="$SHELL_SECURE_DIR/blocked.log"
    SHELL_SECURE_PROTECTED_DIRS=()
    SHELL_SECURE_SAFE_TARGETS=()

    [ -f "$SHELL_SECURE_CONFIG" ] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        trimmed=$(_ss_trim "$line")

        if [[ -n "$state" ]]; then
            if [[ "$trimmed" == ")" ]]; then
                state=""
                continue
            fi
            if [[ "$trimmed" =~ ^\"(([^\"\\]|\\.)*)\"$ ]]; then
                local value
                value=$(_ss_unescape_config "${BASH_REMATCH[1]}")
                if [[ "$state" == "protected" ]]; then
                    SHELL_SECURE_PROTECTED_DIRS+=("$value")
                else
                    SHELL_SECURE_SAFE_TARGETS+=("$value")
                fi
            fi
            continue
        fi

        [[ -z "$trimmed" || "${trimmed:0:1}" == "#" ]] && continue

        if [[ "$trimmed" =~ ^SHELL_SECURE_ENABLED[[:space:]]*=[[:space:]]*(true|false)$ ]]; then
            SHELL_SECURE_ENABLED="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$trimmed" =~ ^SHELL_SECURE_DELETE_PROTECT[[:space:]]*=[[:space:]]*(true|false)$ ]]; then
            SHELL_SECURE_DELETE_PROTECT="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$trimmed" =~ ^SHELL_SECURE_GIT_PROTECT[[:space:]]*=[[:space:]]*(true|false)$ ]]; then
            SHELL_SECURE_GIT_PROTECT="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$trimmed" =~ ^SHELL_SECURE_GIT_FLOOD_PROTECT[[:space:]]*=[[:space:]]*(true|false)$ ]]; then
            SHELL_SECURE_GIT_FLOOD_PROTECT="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$trimmed" =~ ^SHELL_SECURE_GIT_FLOOD_THRESHOLD[[:space:]]*=[[:space:]]*([0-9]+)$ ]]; then
            SHELL_SECURE_GIT_FLOOD_THRESHOLD="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$trimmed" =~ ^SHELL_SECURE_GIT_FLOOD_WINDOW[[:space:]]*=[[:space:]]*([0-9]+)$ ]]; then
            SHELL_SECURE_GIT_FLOOD_WINDOW="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$trimmed" =~ ^SHELL_SECURE_PS_ENCODING_PROTECT[[:space:]]*=[[:space:]]*(true|false)$ ]]; then
            SHELL_SECURE_PS_ENCODING_PROTECT="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$trimmed" =~ ^SHELL_SECURE_LANGUAGE[[:space:]]*=[[:space:]]*\"?([a-zA-Z-]+)\"?$ ]]; then
            SHELL_SECURE_LANGUAGE="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$trimmed" =~ ^SHELL_SECURE_LOG[[:space:]]*=[[:space:]]*\"(([^\"\\]|\\.)*)\"$ ]]; then
            SHELL_SECURE_LOG=$(_ss_expand_config_path "$(_ss_unescape_config "${BASH_REMATCH[1]}")")
            continue
        fi

        if [[ "$trimmed" == "SHELL_SECURE_PROTECTED_DIRS=(" ]]; then
            state="protected"
            continue
        fi

        if [[ "$trimmed" == "SHELL_SECURE_SAFE_TARGETS=(" ]]; then
            state="safe"
            continue
        fi
    done < "$SHELL_SECURE_CONFIG"
}

_ss_log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$(dirname "$SHELL_SECURE_LOG")" 2>/dev/null || true
    echo "[$timestamp] $1" >> "$SHELL_SECURE_LOG" 2>/dev/null
}

_ss_canonicalize() {
    local p="$1"
    local -a parts stack=()
    local part

    p="${p//\\//}"

    if [[ ! "$p" =~ ^/ ]]; then
        p="$(pwd)/$p"
    fi

    IFS='/' read -r -a parts <<< "$p"
    for part in "${parts[@]}"; do
        case "$part" in
            ""|".")
                ;;
            "..")
                if ((${#stack[@]} > 0)); then
                    unset 'stack[${#stack[@]}-1]'
                fi
                ;;
            *)
                stack+=("$part")
                ;;
        esac
    done

    if ((${#stack[@]} == 0)); then
        printf '/'
        return
    fi

    printf '/%s' "${stack[0]}"
    for part in "${stack[@]:1}"; do
        printf '/%s' "$part"
    done
}

_ss_normalize() {
    local p="$1"
    p="${p#\"}"
    p="${p%\"}"
    p="${p#\'}"
    p="${p%\'}"
    p="${p//\\//}"
    if [[ "$p" =~ ^([a-zA-Z]): ]]; then
        local drive="${BASH_REMATCH[1],,}"
        p="/${drive}${p:2}"
    fi
    p=$(_ss_canonicalize "$p")
    p="${p%/}"
    if [[ -z "$p" ]]; then
        p="/"
    fi
    printf '%s' "${p,,}"
}

_ss_resolve() {
    _ss_normalize "$1"
}

_ss_is_protected() {
    local target norm
    target=$(_ss_normalize "$1")
    for dir in "${SHELL_SECURE_PROTECTED_DIRS[@]}"; do
        norm=$(_ss_normalize "$dir")
        if [[ "$target" == "$norm" || "$target" == "$norm/"* ]]; then
            return 0
        fi
    done
    return 1
}

_ss_is_safe_target() {
    local target_base safe_base
    target_base=$(basename "$(_ss_normalize "$1")")
    for safe in "${SHELL_SECURE_SAFE_TARGETS[@]}"; do
        safe_base=$(basename "$(_ss_normalize "$safe")")
        if [[ "$target_base" == "$safe_base" ]]; then
            return 0
        fi
    done
    return 1
}

_ss_has_recursive_flag() {
    local arg lower
    for arg in "$@"; do
        lower="${arg,,}"
        case "$lower" in
            --)
                return 1
                ;;
            --recursive)
                return 0
                ;;
            -[!-]*)
                if [[ "${lower#-}" == *r* ]]; then
                    return 0
                fi
                ;;
        esac
    done
    return 1
}

_ss_strip_wrapping_quotes() {
    local s="$1"
    s="${s#\"}"
    s="${s%\"}"
    s="${s#\'}"
    s="${s%\'}"
    printf '%s' "$s"
}

_ss_runtime_enabled() {
    _ss_load_config
    [ "$SHELL_SECURE_ENABLED" = "true" ]
}

# Windows callers often capture this output through legacy code pages instead
# of a UTF-8 terminal. Keep separator lines ASCII so block diagnostics stay
# readable even when stderr is decoded outside Git Bash.
_ss_block_rule() {
    echo "  ------------------------------------" >&2
}

# Kategorie-Checks bauen auf dem Master-Schalter auf: ist der Master aus,
# ist automatisch auch jede Kategorie aus. Config wird genau einmal pro
# Aufruf neu gelesen (via _ss_runtime_enabled), damit Toggles aus der GUI
# ohne Shell-Reload wirken.
_ss_delete_protect_enabled() {
    _ss_runtime_enabled && [ "$SHELL_SECURE_DELETE_PROTECT" = "true" ]
}

_ss_git_protect_enabled() {
    _ss_runtime_enabled && [ "$SHELL_SECURE_GIT_PROTECT" = "true" ]
}

_ss_git_flood_protect_enabled() {
    _ss_runtime_enabled && [ "$SHELL_SECURE_GIT_FLOOD_PROTECT" = "true" ]
}

_ss_ps_encoding_protect_enabled() {
    _ss_runtime_enabled && [ "$SHELL_SECURE_PS_ENCODING_PROTECT" = "true" ]
}

_ss_block() {
    local cmd_name="$1"
    local target="$2"
    local reason="$3"
    # Optional: konkreter Alternativvorschlag. Default passt fuer generische
    # Loesch-Blocks; die Wrapper uebergeben kontextspezifische Vorschlaege.
    local safer="${4:-}"
    if [ -z "$safer" ]; then
        if [ "$(_ss_lang)" = "de" ]; then
            safer="Einzelne Dateien gezielt ohne -rf loeschen, oder den Ordner zuerst umbenennen (mv \"$target\" \"$target.old\") statt direkt zu loeschen."
        else
            safer="Delete individual files without -rf, or rename the folder first (mv \"$target\" \"$target.old\") instead of removing it outright."
        fi
    fi

    echo "" >&2
    echo "  [Shell-Secure] $(_ss_t block.title)" >&2
    _ss_block_rule
    echo "  $(_ss_t block.label.blocked_by)$(_ss_t block.layer.delete)" >&2
    echo "  $(_ss_t block.label.command)$cmd_name" >&2
    echo "  $(_ss_t block.label.target)$target" >&2
    echo "  $(_ss_t block.label.reason)$reason" >&2
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    echo "    $safer" >&2
    _ss_block_rule
    echo "  $(_ss_t block.section.bypass)" >&2
    echo "    command rm -rf <path>" >&2
    echo "    command cmd /c \"rmdir /s /q <path>\"" >&2
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $cmd_name | $target | $reason"
    return 1
}
