# Read this file first when changing how PowerShell command lines are parsed.
# Purpose: tokenize raw PowerShell argument strings and provide helpers used by
#          both the delete-protect (Remove-Item) and PS-UTF-8 layers.
# Scope: pure parsing - no command execution, no block rendering.

declare -ag _ss_ps_tokens=()

_ss_tokenize_powershell_args() {
    local s="$1"
    local token="" quote="" ch
    local i
    _ss_ps_tokens=()

    for ((i = 0; i < ${#s}; i++)); do
        ch="${s:i:1}"
        if [ -n "$quote" ]; then
            if [ "$ch" = "$quote" ]; then
                quote=""
            else
                token+="$ch"
            fi
            continue
        fi

        case "$ch" in
            "'"|'"')
                quote="$ch"
                ;;
            " "|$'\t'|$'\r'|$'\n'|";")
                if [ -n "$token" ]; then
                    _ss_ps_tokens+=("$token")
                    token=""
                fi
                ;;
            *)
                token+="$ch"
                ;;
        esac
    done

    if [ -n "$token" ]; then
        _ss_ps_tokens+=("$token")
    fi
}

_ss_ps_is_remove_item_command() {
    local token="${1,,}"
    case "$token" in
        remove-item|rm|del|ri|rd|erase|rmdir) return 0 ;;
    esac
    return 1
}

_ss_find_powershell_remove_item_index() {
    local i
    for ((i = 0; i < ${#_ss_ps_tokens[@]}; i++)); do
        if _ss_ps_is_remove_item_command "${_ss_ps_tokens[$i]}"; then
            printf '%s' "$i"
            return 0
        fi
    done
    return 1
}

_ss_ps_is_recursive_flag() {
    local token="${1,,}"
    token="${token%%:*}"
    case "$token" in
        -r|-re|-rec|-recu|-recur|-recurs|-recurse) return 0 ;;
    esac
    return 1
}

_ss_powershell_has_recursive_flag() {
    local start_index="$1"
    local i
    for ((i = start_index + 1; i < ${#_ss_ps_tokens[@]}; i++)); do
        if _ss_ps_is_recursive_flag "${_ss_ps_tokens[$i]}"; then
            return 0
        fi
    done
    return 1
}

_ss_ps_is_path_option() {
    local token="${1,,}"
    token="${token%%:*}"
    case "$token" in
        -pa|-pat|-path|-l|-li|-lit|-lite|-liter|-litera|-literal|-literalp|-literalpa|-literalpat|-literalpath) return 0 ;;
    esac
    return 1
}

_ss_ps_option_value_from_colon() {
    local token="$1"
    if [[ "$token" == *:* ]]; then
        printf '%s' "${token#*:}"
        return 0
    fi
    return 1
}

_ss_ps_option_takes_value() {
    local token="${1,,}"
    token="${token%%:*}"
    case "$token" in
        -filter|-include|-exclude|-credential|-stream|-erroraction|-ea|-warningaction|-wa|-informationaction|-ia|-outvariable|-ov|-pipelinevariable|-pv) return 0 ;;
    esac
    return 1
}

_ss_extract_powershell_target() {
    local start_index="$1"
    local i token value
    for ((i = start_index + 1; i < ${#_ss_ps_tokens[@]}; i++)); do
        token="${_ss_ps_tokens[$i]}"
        if _ss_ps_is_path_option "$token"; then
            if value=$(_ss_ps_option_value_from_colon "$token"); then
                printf '%s' "$value"
                return 0
            fi
            if ((i + 1 < ${#_ss_ps_tokens[@]})); then
                printf '%s' "${_ss_ps_tokens[$((i + 1))]}"
                return 0
            fi
            return 1
        fi

        if [[ "$token" == -* ]]; then
            if _ss_ps_option_takes_value "$token" && [[ "$token" != *:* ]]; then
                ((i++))
            fi
            continue
        fi

        printf '%s' "$token"
        return 0
    done
    return 1
}
