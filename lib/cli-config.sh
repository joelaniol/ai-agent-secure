# Read this file first when working on the Shell-Secure CLI config path.
# Purpose: parse, normalize, and write Shell-Secure CLI configuration files.
# Scope: configuration serialization only; install, runtime state, and CLI actions live in sibling CLI modules.

cfg_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

cfg_unescape() {
    local s="$1"
    local marker=$'\001'
    s="${s//\\\\/$marker}"
    s="${s//\\\"/\"}"
    s="${s//\\\$/\$}"
    s="${s//\\\`/\`}"
    s="${s//$marker/\\}"
    printf '%s' "$s"
}

cfg_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//\$/\\\$}"
    s="${s//\`/\\\`}"
    printf '%s' "$s"
}

cfg_load() {
    local config="$1"
    local state="" raw trimmed

    SHELL_SECURE_ENABLED=true
    SHELL_SECURE_DELETE_PROTECT=true
    SHELL_SECURE_GIT_PROTECT=true
    SHELL_SECURE_GIT_FLOOD_PROTECT=true
    SHELL_SECURE_GIT_FLOOD_THRESHOLD=4
    SHELL_SECURE_GIT_FLOOD_WINDOW=60
    SHELL_SECURE_PS_ENCODING_PROTECT=true
    SHELL_SECURE_LANGUAGE=en
    SHELL_SECURE_LOG="$HOME/.shell-secure/blocked.log"
    SHELL_SECURE_PROTECTED_DIRS=()
    SHELL_SECURE_SAFE_TARGETS=()

    [ -f "$config" ] || return 1

    while IFS= read -r raw || [[ -n "$raw" ]]; do
        raw="${raw%$'\r'}"
        trimmed=$(cfg_trim "$raw")

        if [[ -n "$state" ]]; then
            if [[ "$trimmed" == ")" ]]; then
                state=""
                continue
            fi
            if [[ "$trimmed" =~ ^\"(([^\"\\]|\\.)*)\"$ ]]; then
                local value
                value=$(cfg_unescape "${BASH_REMATCH[1]}")
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
            SHELL_SECURE_LOG=$(cfg_unescape "${BASH_REMATCH[1]}")
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
    done < "$config"
}

cfg_write() {
    local config="$1"
    local tmpfile dir safe

    tmpfile=$(mktemp)
    {
        echo "# AI Agent Secure Configuration (Shell-Secure core)"
        echo "# ==========================="
        echo ""
        echo "# Protection enabled (true/false)"
        echo "SHELL_SECURE_ENABLED=$SHELL_SECURE_ENABLED"
        echo ""
        echo "# Delete command protection enabled (true/false)"
        echo "SHELL_SECURE_DELETE_PROTECT=${SHELL_SECURE_DELETE_PROTECT:-true}"
        echo ""
        echo "# Git destructive command protection enabled (true/false)"
        echo "SHELL_SECURE_GIT_PROTECT=${SHELL_SECURE_GIT_PROTECT:-true}"
        echo ""
        echo "# Git flood protection: rate-limit network git calls (push/pull/fetch/clone/ls-remote)"
        echo "SHELL_SECURE_GIT_FLOOD_PROTECT=${SHELL_SECURE_GIT_FLOOD_PROTECT:-true}"
        echo "SHELL_SECURE_GIT_FLOOD_THRESHOLD=${SHELL_SECURE_GIT_FLOOD_THRESHOLD:-4}"
        echo "SHELL_SECURE_GIT_FLOOD_WINDOW=${SHELL_SECURE_GIT_FLOOD_WINDOW:-60}"
        echo ""
        echo "# PowerShell UTF-8 enforcement: block PS writes without -Encoding utf8"
        echo "SHELL_SECURE_PS_ENCODING_PROTECT=${SHELL_SECURE_PS_ENCODING_PROTECT:-true}"
        echo ""
        echo "# Language for block messages and UI text (en/de)"
        echo "SHELL_SECURE_LANGUAGE=${SHELL_SECURE_LANGUAGE:-en}"
        echo ""
        echo "# Log file for blocked operations"
        printf 'SHELL_SECURE_LOG="%s"\n' "$(cfg_escape "$SHELL_SECURE_LOG")"
        echo ""
        echo "# Protected areas - recursive deletes in these trees will be blocked"
        echo "# Use forward slashes, one entry per array element"
        echo "# Fresh Windows installs add C:/ automatically when the drive exists."
        echo "SHELL_SECURE_PROTECTED_DIRS=("
        for dir in "${SHELL_SECURE_PROTECTED_DIRS[@]}"; do
            printf '    "%s"\n' "$(cfg_escape "$dir")"
        done
        echo ")"
        echo ""
        echo "# Safe directory names that CAN be recursively deleted (build artifacts etc.)"
        echo "# Only the basename is checked, not the full path"
        echo "SHELL_SECURE_SAFE_TARGETS=("
        for safe in "${SHELL_SECURE_SAFE_TARGETS[@]}"; do
            printf '    "%s"\n' "$(cfg_escape "$safe")"
        done
        echo ")"
    } > "$tmpfile"
    cp "$tmpfile" "$config"
    rm -f "$tmpfile"
}

normalize_path_key() {
    local path="${1//\\//}"
    if [[ "$path" =~ ^([a-zA-Z]): ]]; then
        local drive="${BASH_REMATCH[1],,}"
        path="/${drive}${path:2}"
    fi
    path="${path%/}"
    [ -z "$path" ] && path="/"
    printf '%s' "${path,,}"
}

normalize_name_key() {
    printf '%s' "${1,,}"
}

cfg_windows_c_drive_available() {
    if [ -n "${SHELL_SECURE_TEST_WINDOWS_C_ROOT+x}" ]; then
        [ -d "$SHELL_SECURE_TEST_WINDOWS_C_ROOT" ]
        return $?
    fi
    [ -d "/c" ] || [ -d "C:/" ] || [ -d "/mnt/c" ]
}

cfg_add_fresh_install_default_areas() {
    local config="$1"
    cfg_windows_c_drive_available || return 0
    cfg_load "$config" || return 0

    local default_area="C:/"
    local default_key existing
    default_key=$(normalize_path_key "$default_area")
    for existing in "${SHELL_SECURE_PROTECTED_DIRS[@]}"; do
        [ "$(normalize_path_key "$existing")" = "$default_key" ] && return 0
    done

    SHELL_SECURE_PROTECTED_DIRS+=("$default_area")
    cfg_write "$config"
}
