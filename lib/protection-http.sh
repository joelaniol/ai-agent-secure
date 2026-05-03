# Read this file first when changing curl / HTTP API protection.
# Purpose: block authenticated curl calls that carry destructive API intent.
# Scope: command wrapper only; config loading and block labels live in
#        protection-core.sh and protection-i18n.sh.

_ss_curl_option_takes_value() {
    case "$1" in
        --url|--output|-o|--user-agent|-A|--referer|-e|--connect-timeout|--max-time|--retry|--retry-delay|--cacert|--cert|--key|--proxy|--resolve|--connect-to|--request-target|--form-string|--upload-file|-T|--cookie-jar|-c|--cookie|-b)
            return 0
            ;;
    esac
    return 1
}

_ss_curl_note_target() {
    local value="$1"
    local display
    [ -z "$value" ] && return 0
    display=$(_ss_curl_redact_url_userinfo "$value")
    if [ -z "$_ss_curl_target" ]; then
        _ss_curl_target="$display"
    else
        _ss_curl_target="$_ss_curl_target $display"
    fi
    if [[ "${value,,}" =~ ^[a-z][a-z0-9+.-]*://[^/?#[:space:]]+@ ]]; then
        _ss_curl_has_auth=true
    fi
}

_ss_curl_redact_url_userinfo() {
    local value="$1"
    if [[ "$value" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@[:space:]][^/@[:space:]]*@(.*)$ ]]; then
        printf '%s<redacted>@%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
        printf '%s' "$value"
    fi
}

_ss_curl_note_header() {
    local header="${1,,}"
    case "$header" in
        authorization:*|proxy-authorization:*|x-api-key:*|x-api-token:*|x-auth-token:*|private-token:*|gitlab-token:*|x-github-token:*|x-railway-*:*|railway-token:*|api-key:*|apikey:*)
            _ss_curl_has_auth=true
            ;;
    esac
}

_ss_curl_redact_header() {
    local header="$1"
    local lower="${header,,}"
    case "$lower" in
        authorization:*|proxy-authorization:*|x-api-key:*|x-api-token:*|x-auth-token:*|private-token:*|gitlab-token:*|x-github-token:*|x-railway-*:*|railway-token:*|api-key:*|apikey:*)
            if [[ "$header" == *:* ]]; then
                printf '%s' "${header%%:*}: <redacted>"
            else
                printf '%s' "<redacted>"
            fi
            ;;
        *)
            printf '%s' "$header"
            ;;
    esac
}

_ss_curl_append_redacted_arg() {
    local current="$1"
    local value="$2"
    if [ -z "$current" ]; then
        printf '%s' "$value"
    else
        printf '%s %s' "$current" "$value"
    fi
}

_ss_curl_redacted_command() {
    local cmd_name="$1"
    shift
    local redacted="$cmd_name"
    local arg safe_arg pending=""
    for arg in "$@"; do
        if [ -n "$pending" ]; then
            case "$pending" in
                header)
                    redacted=$(_ss_curl_append_redacted_arg "$redacted" "$(_ss_curl_redact_header "$arg")")
                    ;;
                secret)
                    redacted=$(_ss_curl_append_redacted_arg "$redacted" "<redacted>")
                    ;;
                payload)
                    redacted=$(_ss_curl_append_redacted_arg "$redacted" "<redacted-payload>")
                    ;;
                *)
                    redacted=$(_ss_curl_append_redacted_arg "$redacted" "$arg")
                    ;;
            esac
            pending=""
            continue
        fi

        case "$arg" in
            -H|--header)
                redacted=$(_ss_curl_append_redacted_arg "$redacted" "$arg")
                pending="header"
                ;;
            -H*)
                redacted=$(_ss_curl_append_redacted_arg "$redacted" "-H$(_ss_curl_redact_header "${arg#-H}")")
                ;;
            --header=*)
                redacted=$(_ss_curl_append_redacted_arg "$redacted" "--header=$(_ss_curl_redact_header "${arg#--header=}")")
                ;;
            -d|--data|--data-raw|--data-binary|--data-ascii|--data-urlencode|--form|-F|--form-string|--json)
                redacted=$(_ss_curl_append_redacted_arg "$redacted" "$arg")
                pending="payload"
                ;;
            -d*|-F*)
                redacted=$(_ss_curl_append_redacted_arg "$redacted" "${arg:0:2}<redacted-payload>")
                ;;
            --data=*|--data-raw=*|--data-binary=*|--data-ascii=*|--data-urlencode=*|--form=*|--form-string=*|--json=*)
                redacted=$(_ss_curl_append_redacted_arg "$redacted" "${arg%%=*}=<redacted-payload>")
                ;;
            -u|--user|--oauth2-bearer|--proxy-user|-b|--cookie)
                redacted=$(_ss_curl_append_redacted_arg "$redacted" "$arg")
                pending="secret"
                ;;
            -u*|-b*)
                redacted=$(_ss_curl_append_redacted_arg "$redacted" "${arg:0:2}<redacted>")
                ;;
            --user=*|--oauth2-bearer=*|--proxy-user=*|--cookie=*)
                redacted=$(_ss_curl_append_redacted_arg "$redacted" "${arg%%=*}=<redacted>")
                ;;
            --url=*)
                redacted=$(_ss_curl_append_redacted_arg "$redacted" "--url=$(_ss_curl_redact_url_userinfo "${arg#--url=}")")
                ;;
            *)
                safe_arg=$(_ss_curl_redact_url_userinfo "$arg")
                redacted=$(_ss_curl_append_redacted_arg "$redacted" "$safe_arg")
                ;;
        esac
    done
    printf '%s' "$redacted"
}

_ss_curl_note_payload_value() {
    local value="$1"
    _ss_curl_has_data=true
    # Keep only a bounded text sample; this layer is a heuristic, not a full
    # HTTP client parser, and large binary uploads must not balloon shell memory.
    if [ ${#_ss_curl_payload} -lt 65536 ]; then
        _ss_curl_payload="${_ss_curl_payload}${value}"$'\n'
    fi
}

_ss_curl_note_payload_file() {
    local value="$1"
    local file="${value#@}"
    if [[ "$value" != @* ]]; then
        _ss_curl_note_payload_value "$value"
        return 0
    fi
    [ "$file" = "-" ] && return 0
    if [ -f "$file" ]; then
        _ss_curl_note_payload_value "$(head -c 65536 "$file" 2>/dev/null || true)"
    fi
}

_ss_curl_collect_context() {
    _ss_curl_method=""
    _ss_curl_target=""
    _ss_curl_payload=""
    _ss_curl_has_auth=false
    _ss_curl_has_data=false
    _ss_curl_get_mode=false

    local arg pending=""
    for arg in "$@"; do
        if [ -n "$pending" ]; then
            case "$pending" in
                method)
                    _ss_curl_method="$(_ss_strip_wrapping_quotes "$arg")"
                    ;;
                header)
                    _ss_curl_note_header "$arg"
                    ;;
                data)
                    _ss_curl_note_payload_file "$arg"
                    ;;
                json)
                    _ss_curl_note_header "content-type: application/json"
                    _ss_curl_note_payload_file "$arg"
                    ;;
                user)
                    _ss_curl_has_auth=true
                    ;;
                url)
                    _ss_curl_note_target "$arg"
                    ;;
            esac
            pending=""
            continue
        fi

        case "$arg" in
            --)
                continue
                ;;
            -X|--request)
                pending="method"
                continue
                ;;
            -X*)
                _ss_curl_method="${arg#-X}"
                continue
                ;;
            --request=*)
                _ss_curl_method="${arg#--request=}"
                continue
                ;;
            -H|--header)
                pending="header"
                continue
                ;;
            -H*)
                _ss_curl_note_header "${arg#-H}"
                continue
                ;;
            --header=*)
                _ss_curl_note_header "${arg#--header=}"
                continue
                ;;
            -d|--data|--data-raw|--data-binary|--data-ascii|--data-urlencode|--form|-F|--form-string)
                pending="data"
                continue
                ;;
            -d*|-F*)
                _ss_curl_note_payload_file "${arg:2}"
                continue
                ;;
            --data=*|--data-raw=*|--data-binary=*|--data-ascii=*|--data-urlencode=*|--form=*|--form-string=*)
                _ss_curl_note_payload_file "${arg#*=}"
                continue
                ;;
            --json)
                pending="json"
                continue
                ;;
            --json=*)
                _ss_curl_note_header "content-type: application/json"
                _ss_curl_note_payload_file "${arg#--json=}"
                continue
                ;;
            -u|--user|--oauth2-bearer|--proxy-user|-b|--cookie)
                pending="user"
                continue
                ;;
            -u*)
                _ss_curl_has_auth=true
                continue
                ;;
            --user=*|--oauth2-bearer=*|--proxy-user=*)
                _ss_curl_has_auth=true
                continue
                ;;
            --netrc-file)
                _ss_curl_has_auth=true
                pending="skip"
                continue
                ;;
            -b*|-n|--cookie=*|--netrc|--netrc-optional|--aws-sigv4|--negotiate|--anyauth|--basic|--digest|--ntlm|--delegation)
                _ss_curl_has_auth=true
                continue
                ;;
            -G|--get)
                _ss_curl_get_mode=true
                continue
                ;;
            --url)
                pending="url"
                continue
                ;;
            --url=*)
                _ss_curl_note_target "${arg#--url=}"
                continue
                ;;
        esac

        if _ss_curl_option_takes_value "$arg"; then
            pending="skip"
            continue
        fi

        if [[ "$arg" == -* ]]; then
            continue
        fi

        _ss_curl_note_target "$arg"
    done
}

_ss_curl_text_has_destructive_operation() {
    local haystack="${1,,}"
    haystack="${haystack//$'\r'/ }"
    haystack="${haystack//$'\n'/ }"
    local compact="${haystack//[^a-z0-9]/}"
    local marker_re="delete|destroy|drop|truncate|purge|wipe|erase|terminate|deprovision|decommission|remove|detach|revoke"
    local object_re="databases?|dbs?|volumes?|backups?|projects?|environments?|envs?|services?|deployments?|tokens?|keys?|secrets?|users?|workspaces?|buckets?|clusters?|instances?|disks?|repos?|repositories|branches|caches?"

    [[ "$haystack" =~ (^|[^[:alnum:]_])($marker_re)[[:alnum:]_./:-]{0,32}($object_re)([^[:alnum:]_]|$) ]] && return 0
    [[ "$haystack" =~ (^|[^[:alnum:]_])($object_re)[[:alnum:]_./:-]{0,32}($marker_re)([^[:alnum:]_]|$) ]] && return 0
    [[ "$compact" =~ ($marker_re)($object_re)|($object_re)($marker_re) ]]
}

_ss_curl_payload_has_destructive_marker() {
    local haystack="${1,,}"
    haystack="${haystack//$'\r'/ }"
    haystack="${haystack//$'\n'/ }"
    local marker_re="delete|destroy|drop|truncate|purge|wipe|erase|terminate|deprovision|decommission|remove|detach|revoke"
    local object_re="databases?|dbs?|volumes?|backups?|projects?|environments?|envs?|services?|deployments?|tokens?|keys?|secrets?|users?|workspaces?|buckets?|clusters?|instances?|disks?|repos?|repositories|branches|caches?"
    local action_value_re="(^|[^[:alnum:]_])(operation|action|command|op|type)[^:=&]{0,24}[:=][^[:alnum:]_]*($marker_re)"
    local marker_key_re="(^|[^[:alnum:]_])($marker_re)[[:alnum:]_:-]{0,24}($object_re)[^[:alnum:]_]*:"
    local object_key_re="(^|[^[:alnum:]_])($object_re)[[:alnum:]_:-]{0,24}($marker_re)[^[:alnum:]_]*:"
    local mutation_re="(^|[^[:alnum:]_])mutation([^[:alnum:]_]|$)"

    # Only treat payload text as destructive when it is shaped like an API
    # operation. This avoids blocking ordinary search strings or labels such
    # as "drop shadow" while keeping action/operation fields and GraphQL
    # mutations conservative.
    [[ "$haystack" =~ $action_value_re ]] && return 0
    [[ "$haystack" =~ $marker_key_re ]] && return 0
    [[ "$haystack" =~ $object_key_re ]] && return 0
    [[ "$haystack" =~ $mutation_re ]] && _ss_curl_text_has_destructive_operation "$haystack"
}

_ss_curl_target_has_destructive_marker() {
    local haystack="${1,,}"
    haystack="${haystack//$'\r'/ }"
    haystack="${haystack//$'\n'/ }"
    local marker_re="delete|destroy|drop|truncate|purge|wipe|erase|terminate|deprovision|decommission|remove|detach|revoke"
    local preview_re="preview|dryrun|dry-run|dry_run|plan|validate|validation"
    local preview_marker_re="($marker_re)[_-]?($preview_re)|($preview_re)[_-]?($marker_re)"
    local exact_marker_re="(^|[/?&=])($marker_re)($|[/?&=])"

    [[ "$haystack" =~ $preview_marker_re ]] && return 1
    [[ "$haystack" =~ $exact_marker_re ]] && return 0
    _ss_curl_text_has_destructive_operation "$haystack"
}

_ss_curl_should_block() {
    _ss_curl_effective_method="${_ss_curl_method^^}"
    _ss_curl_effective_method="$(_ss_strip_wrapping_quotes "$_ss_curl_effective_method")"
    if [ -z "$_ss_curl_effective_method" ]; then
        if $_ss_curl_has_data && ! $_ss_curl_get_mode; then
            _ss_curl_effective_method="POST"
        else
            _ss_curl_effective_method="GET"
        fi
    fi

    $_ss_curl_has_auth || return 1

    case "$_ss_curl_effective_method" in
        DELETE)
            if [ "$(_ss_lang)" = "de" ]; then
                _ss_curl_block_reason="Authentifizierter HTTP DELETE-Aufruf"
            else
                _ss_curl_block_reason="Authenticated HTTP DELETE request"
            fi
            return 0
            ;;
        POST|PUT|PATCH)
            if _ss_curl_payload_has_destructive_marker "$_ss_curl_payload" ||
                _ss_curl_target_has_destructive_marker "$_ss_curl_target"; then
                if [ "$(_ss_lang)" = "de" ]; then
                    _ss_curl_block_reason="Authentifizierter API-Aufruf mit destruktiver Payload"
                else
                    _ss_curl_block_reason="Authenticated API request with destructive payload"
                fi
                return 0
            fi
            ;;
    esac
    return 1
}

_ss_block_http_api() {
    local cmd_name="$1"
    local method="$2"
    local target="$3"
    local reason="$4"
    shift 4
    local full
    full=$(_ss_curl_redacted_command "$cmd_name" "$@")
    local lang
    lang=$(_ss_lang)
    [ -n "$target" ] || target="(not detected)"

    echo "" >&2
    echo "  [Shell-Secure] $(_ss_t block.title)" >&2
    _ss_block_rule
    echo "  $(_ss_t block.label.blocked_by)$(_ss_t block.layer.http_api)" >&2
    echo "  $(_ss_t block.label.command)$full" >&2
    echo "  $(_ss_t block.label.target)$target" >&2
    echo "  $(_ss_t block.label.reason)$reason" >&2
    if [ "$lang" = "de" ]; then
        echo "                 Methode: $method. Authentifizierte API-Löschungen können" >&2
        echo "                 Datenbanken, Volumes, Backups oder Projekte endgültig entfernen." >&2
    else
        echo "                 Method: $method. Authenticated API deletes can permanently" >&2
        echo "                 remove databases, volumes, backups, or projects." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    if [ "$lang" = "de" ]; then
        echo "    Erst den Nutzer explizit fragen, Umgebung und Ressourcen-ID prüfen," >&2
        echo "    und wenn möglich Provider-UI, Dry-Run oder nicht-destruktive Preview nutzen." >&2
    else
        echo "    Ask the user for explicit permission first, verify environment and" >&2
        echo "    resource ID, and prefer provider UI, dry-run, or non-destructive preview." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.manual_release)" >&2
    if [ "$lang" = "de" ]; then
        echo "    Nur nach ausdrücklicher Nutzerfreigabe erneut ausführen." >&2
        echo "    Für längere Admin-Sessions: SHELL_SECURE_HTTP_API_PROTECT=false" >&2
        echo "    temporär in ~/.shell-secure/config.conf setzen und danach wieder aktivieren." >&2
    else
        echo "    Re-run only after explicit user approval." >&2
        echo "    For longer admin sessions: temporarily set SHELL_SECURE_HTTP_API_PROTECT=false" >&2
        echo "    in ~/.shell-secure/config.conf, then enable it again afterwards." >&2
    fi
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | http-api | $reason"
    return 1
}

_ss_curl_wrapper() {
    local real_cmd="$1"
    local cmd_name="${_ss_curl_command_name:-$real_cmd}"
    shift

    if ! _ss_http_api_protect_enabled; then
        command "$real_cmd" "$@"
        return $?
    fi

    _ss_curl_collect_context "$@"
    if _ss_curl_should_block; then
        _ss_block_http_api "$cmd_name" "$_ss_curl_effective_method" "$_ss_curl_target" "$_ss_curl_block_reason" "$@"
        return 1
    fi

    command "$real_cmd" "$@"
}

curl() { _ss_curl_wrapper curl "$@"; }
Curl() { _ss_curl_wrapper curl "$@"; }
CURL() { _ss_curl_wrapper curl "$@"; }
curl.exe() { _ss_curl_wrapper curl.exe "$@"; }
Curl.exe() { _ss_curl_wrapper curl.exe "$@"; }
CURL.exe() { _ss_curl_wrapper curl.exe "$@"; }
