# Read this file first when changing git-push leak detection.
# Purpose: inspect commits about to be pushed for high-risk secret and agent
#          workspace paths, then require an explicit one-shot allow decision.
# Scope: no git() wrapper; protection-git.sh owns dispatch and calls this slice
#        only for push commands after _ss_git_pre_opts has been prepared.

declare -ag _ss_git_leak_push_args=()

_ss_git_leak_force_requested() {
    case "${SHELL_SECURE_GIT_LEAK_FORCE:-}" in
        1|true|TRUE|yes|YES|allow|ALLOW|force|FORCE)
            return 0
            ;;
    esac
    return 1
}

_ss_git_leak_timeout_seconds() {
    local timeout="${SHELL_SECURE_GIT_LEAK_TIMEOUT:-60}"
    [[ "$timeout" =~ ^[0-9]+$ ]] || timeout=60
    [ "$timeout" -lt 1 ] && timeout=60
    printf '%s' "$timeout"
}

_ss_git_leak_extract_push_args() {
    _ss_git_leak_push_args=()
    local skip_next=false seen_sub=false tok

    for tok in "$@"; do
        if $seen_sub; then
            _ss_git_leak_push_args+=("$tok")
            continue
        fi
        if $skip_next; then
            skip_next=false
            continue
        fi
        case "$tok" in
            -C|-c|--exec-path|--namespace|--super-prefix|--config-env|--work-tree|--git-dir)
                skip_next=true
                ;;
            -*)
                ;;
            push)
                seen_sub=true
                ;;
            *)
                return 1
                ;;
        esac
    done

    $seen_sub
}

_ss_git_leak_push_is_dry_run() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run)
                return 0
                ;;
            -[!-]*)
                [[ "${arg#-}" == *n* ]] && return 0
                ;;
        esac
    done
    return 1
}

_ss_git_leak_ref_commits() {
    local ref="$1"
    [ -n "$ref" ] || return 0
    command git "${_ss_git_pre_opts[@]}" rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1 || return 0

    if command git "${_ss_git_pre_opts[@]}" for-each-ref --format='%(refname)' refs/remotes 2>/dev/null | grep -q .; then
        command git "${_ss_git_pre_opts[@]}" rev-list "$ref" --not --remotes 2>/dev/null || true
    else
        command git "${_ss_git_pre_opts[@]}" rev-list "$ref" 2>/dev/null || true
    fi
}

_ss_git_leak_push_candidate_commits() {
    local -a positionals=() refs=()
    local arg skip_next=false skip_next_is_repo=false remote_via_option=false
    local delete_mode=false push_all=false push_mirror=false push_tags=false tag_next=false

    for arg in "$@"; do
        if $skip_next; then
            if $skip_next_is_repo; then
                remote_via_option=true
                skip_next_is_repo=false
            fi
            skip_next=false
            continue
        fi
        case "$arg" in
            --repo)
                skip_next=true
                skip_next_is_repo=true
                ;;
            --receive-pack|--exec|--push-option|-o)
                skip_next=true
                ;;
            --repo=*)
                remote_via_option=true
                ;;
            --receive-pack=*|--exec=*|--push-option=*|-o?*)
                ;;
            --all)
                push_all=true
                ;;
            --mirror)
                push_mirror=true
                ;;
            --tags)
                push_tags=true
                ;;
            --delete)
                delete_mode=true
                ;;
            -d)
                delete_mode=true
                ;;
            --)
                ;;
            --*)
                ;;
            -[!-]*)
                [[ "${arg#-}" == *d* ]] && delete_mode=true
                ;;
            *)
                positionals+=("$arg")
                ;;
        esac
    done

    # Branch delete pushes do not transfer commits and should not warn about
    # path leaks. Mixed delete/create pushes are uncommon; git itself keeps the
    # destructive branch-delete semantics, while this layer avoids a false leak.
    $delete_mode && return 0

    if $push_all || $push_mirror; then
        if command git "${_ss_git_pre_opts[@]}" for-each-ref --format='%(refname)' refs/remotes 2>/dev/null | grep -q .; then
            command git "${_ss_git_pre_opts[@]}" rev-list --all --not --remotes 2>/dev/null || true
        else
            command git "${_ss_git_pre_opts[@]}" rev-list --all 2>/dev/null || true
        fi
        return 0
    fi

    local spec_start=1
    $remote_via_option && spec_start=0

    if $push_tags && ((${#positionals[@]} <= spec_start)); then
        refs=()
    elif ((${#positionals[@]} <= spec_start)); then
        refs=("HEAD")
    else
        local spec local_ref
        for spec in "${positionals[@]:$spec_start}"; do
            if $tag_next; then
                refs+=("$spec")
                tag_next=false
                continue
            fi
            if [ "$spec" = "tag" ]; then
                tag_next=true
                continue
            fi
            spec="${spec#+}"
            local_ref="${spec%%:*}"
            [ -z "$local_ref" ] && continue
            refs+=("$local_ref")
        done
    fi

    local ref
    {
        if $push_tags; then
            if command git "${_ss_git_pre_opts[@]}" for-each-ref --format='%(refname)' refs/remotes 2>/dev/null | grep -q .; then
                command git "${_ss_git_pre_opts[@]}" rev-list --tags --not --remotes 2>/dev/null || true
            else
                command git "${_ss_git_pre_opts[@]}" rev-list --tags 2>/dev/null || true
            fi
        fi
        for ref in "${refs[@]}"; do
            _ss_git_leak_ref_commits "$ref"
        done
    } | awk 'NF && !seen[$0]++'
}

_ss_git_leak_commit_paths() {
    local commit="$1"
    command git "${_ss_git_pre_opts[@]}" diff-tree --no-commit-id --name-only -r --root "$commit" 2>/dev/null || true
}

_ss_git_leak_path_reason() {
    local raw="$1"
    local path="${raw//\\//}"
    local lower="${path,,}"
    local base="${lower##*/}"

    case "$lower" in
        .claude|.claude/*|*/.claude|*/.claude/*)
            printf '%s' "agent-workspace"
            return 0
            ;;
        .codex|.codex/*|*/.codex|*/.codex/*)
            printf '%s' "agent-workspace"
            return 0
            ;;
        .aws/credentials|*/.aws/credentials)
            printf '%s' "cloud-credentials"
            return 0
            ;;
        .kube/config|*/.kube/config)
            printf '%s' "cluster-credentials"
            return 0
            ;;
        .docker/config.json|*/.docker/config.json)
            printf '%s' "registry-auth"
            return 0
            ;;
    esac

    case "$base" in
        .env.example|.env.sample|.env.template|.env.dist|.env.defaults|.env.example.*|.env.sample.*|.env.template.*|.env.*.example|.env.*.sample|.env.*.template|.env.*.dist)
            return 1
            ;;
        .emv.example|.emv.sample|.emv.template|.emv.dist|.emv.*.example|.emv.*.sample|.emv.*.template|.emv.*.dist)
            return 1
            ;;
        config.example.php|config.sample.php|config.template.php|config.dist.php|config.default.php|config.defaults.php|config.*.example.php|config.*.sample.php|config.*.template.php|config.*.dist.php|config.*.default.php)
            return 1
            ;;
    esac

    case "$base" in
        .env|.env.*|.emv|.emv.*)
            printf '%s' "env-file"
            return 0
            ;;
        .npmrc|.pypirc|.netrc)
            printf '%s' "auth-config"
            return 0
            ;;
        agent.md|agend.md)
            printf '%s' "agent-instruction"
            return 0
            ;;
        config.php|config.*.php|config..php|wp-config.php|configuration.php)
            printf '%s' "app-config"
            return 0
            ;;
        secret|secrets|secrets.*|secret.*|credentials|credentials.*|credential|credential.*)
            printf '%s' "secret-file"
            return 0
            ;;
        service-account*.json|firebase-adminsdk*.json|google-credentials*.json)
            printf '%s' "service-account"
            return 0
            ;;
        id_rsa|id_dsa|id_ecdsa|id_ed25519)
            printf '%s' "private-key"
            return 0
            ;;
        *.pem|*.key|*.p12|*.pfx|*.kdbx)
            case "$base" in
                *.pub) return 1 ;;
            esac
            printf '%s' "key-store"
            return 0
            ;;
    esac

    return 1
}

_ss_git_leak_reason_text() {
    local code="$1"
    if [ "$(_ss_lang)" = "de" ]; then
        case "$code" in
            agent-workspace)     printf '%s' "Agent-Arbeitsdaten" ;;
            cloud-credentials)   printf '%s' "Cloud-Credentials-Datei" ;;
            cluster-credentials) printf '%s' "Cluster-Credentials-Datei" ;;
            registry-auth)       printf '%s' "Registry-Auth-Datei" ;;
            env-file)            printf '%s' "Umgebungsdatei" ;;
            auth-config)         printf '%s' "Auth-Konfigurationsdatei" ;;
            agent-instruction)   printf '%s' "Agent-Instruktionsdatei" ;;
            app-config)          printf '%s' "Anwendungs-Konfigurationsdatei" ;;
            secret-file)         printf '%s' "Credential- oder Secret-Datei" ;;
            service-account)     printf '%s' "Service-Account-Credentials" ;;
            private-key)         printf '%s' "Private Key" ;;
            key-store)           printf '%s' "Private Key oder Credential Store" ;;
            *)                   printf '%s' "$code" ;;
        esac
        return 0
    fi

    case "$code" in
        agent-workspace)     printf '%s' "agent workspace data" ;;
        cloud-credentials)   printf '%s' "cloud credentials file" ;;
        cluster-credentials) printf '%s' "cluster credentials file" ;;
        registry-auth)       printf '%s' "container registry auth file" ;;
        env-file)            printf '%s' "environment file" ;;
        auth-config)         printf '%s' "auth config file" ;;
        agent-instruction)   printf '%s' "agent instruction file" ;;
        app-config)          printf '%s' "application config file" ;;
        secret-file)         printf '%s' "credential or secret file" ;;
        service-account)     printf '%s' "service account credentials" ;;
        private-key)         printf '%s' "private key" ;;
        key-store)           printf '%s' "private key or credential store" ;;
        *)                   printf '%s' "$code" ;;
    esac
}

_ss_git_leak_collect_findings() {
    local -a commits=()
    local commit path reason key
    declare -A seen_paths=()

    mapfile -t commits < <(_ss_git_leak_push_candidate_commits "$@")
    ((${#commits[@]} > 0)) || return 0

    for commit in "${commits[@]}"; do
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            key="${path,,}"
            [ -n "${seen_paths[$key]+x}" ] && continue
            if reason=$(_ss_git_leak_path_reason "$path"); then
                seen_paths[$key]=1
                printf '%s\t%s\n' "$path" "$reason"
            fi
        done < <(_ss_git_leak_commit_paths "$commit")
    done
}

_ss_git_leak_format_findings() {
    local findings="$1"
    local limit="${2:-10}"
    local count=0 total=0 path reason out="" lang
    lang=$(_ss_lang)

    while IFS=$'\t' read -r path reason; do
        [ -n "$path" ] || continue
        total=$((total + 1))
        if [ "$count" -lt "$limit" ]; then
            out+="    - $path ($(_ss_git_leak_reason_text "$reason"))"$'\n'
            count=$((count + 1))
        fi
    done <<< "$findings"

    if [ "$total" -gt "$limit" ]; then
        if [ "$lang" = "de" ]; then
            out+="    - ... und $((total - limit)) weitere"$'\n'
        else
            out+="    - ... and $((total - limit)) more"$'\n'
        fi
    fi

    printf '%s' "$out"
}

_ss_git_leak_summary() {
    local findings="$1"
    local path reason item out=""

    while IFS=$'\t' read -r path reason; do
        [ -n "$path" ] || continue
        item="$path ($(_ss_git_leak_reason_text "$reason"))"
        if [ -n "$out" ]; then
            out+="; $item"
        else
            out="$item"
        fi
    done <<< "$findings"

    printf '%s' "$out"
}

_ss_git_leak_prompt_allow() {
    local full="$1"
    local repo_root="$2"
    local findings="$3"
    local timeout
    timeout=$(_ss_git_leak_timeout_seconds)

    local lang answer tty_fd
    # Git Bash may expose /dev/tty even when the current process has no
    # controlling terminal. Open it once and reuse that fd so non-interactive
    # agents fail closed without noisy redirection errors.
    if ! { exec {tty_fd}<>/dev/tty; } 2>/dev/null; then
        return 1
    fi

    lang=$(_ss_lang)
    {
        echo ""
        if [ "$lang" = "de" ]; then
            echo "  [Shell-Secure] Möglicher Git-Leak vor Push"
            _ss_block_rule
            echo "  Befehl:         $full"
            [ -n "$repo_root" ] && echo "  Repo:           $repo_root"
            echo "  Verdächtige Pfade in den zu pushenden Commits:"
            _ss_git_leak_format_findings "$findings" 10
            _ss_block_rule
            echo "  Tippe innerhalb von ${timeout}s 'allow' zum einmaligen Erlauben."
            echo "  'ignore', Enter oder Timeout blockiert den Push."
            echo -n "  Entscheidung [allow/ignore]: "
        else
            echo "  [Shell-Secure] Possible Git leak before push"
            _ss_block_rule
            echo "  Command:        $full"
            [ -n "$repo_root" ] && echo "  Repo:           $repo_root"
            echo "  Suspicious paths in commits about to be pushed:"
            _ss_git_leak_format_findings "$findings" 10
            _ss_block_rule
            echo "  Type 'allow' within ${timeout}s to allow this push once."
            echo "  'ignore', Enter, or timeout blocks the push."
            echo -n "  Decision [allow/ignore]: "
        fi
    } >&"$tty_fd" 2>&1

    if ! IFS= read -r -t "$timeout" answer <&"$tty_fd"; then
        echo "" >&"$tty_fd"
        exec {tty_fd}>&-
        return 1
    fi
    exec {tty_fd}>&-
    case "${answer,,}" in
        allow|a|yes|y)
            return 0
            ;;
    esac
    return 1
}

_ss_block_git_leak() {
    local full="$1"
    local repo_root="$2"
    local findings="$3"
    local lang
    lang=$(_ss_lang)

    _ss_git_block_header "$(_ss_t block.layer.git_leak)" "$full" "$repo_root"
    if [ "$lang" = "de" ]; then
        echo "  $(_ss_t block.label.reason)Push enthält potenzielle Leak-Dateien." >&2
        echo "                 Der Push wurde blockiert, weil Commits sensible Pfade" >&2
        echo "                 oder Agent-Arbeitsdateien veröffentlichen könnten." >&2
        _ss_block_rule
        echo "  Verdächtige Pfade:" >&2
        _ss_git_leak_format_findings "$findings" 10 >&2
        _ss_block_rule
        echo "  $(_ss_t block.section.better_way)" >&2
        echo "    git rm --cached <pfad>      # nur aus Git entfernen, lokal behalten" >&2
        echo "    .gitignore ergänzen und Secret rotieren, falls es echt war." >&2
        _ss_block_rule
        echo "  Agent-Force (nur nach Prüfung):" >&2
        echo "    SHELL_SECURE_GIT_LEAK_FORCE=1 git push ..." >&2
    else
        echo "  $(_ss_t block.label.reason)Push contains potential leak files." >&2
        echo "                 The push was blocked because commits may publish" >&2
        echo "                 sensitive paths or agent workspace files." >&2
        _ss_block_rule
        echo "  Suspicious paths:" >&2
        _ss_git_leak_format_findings "$findings" 10 >&2
        _ss_block_rule
        echo "  $(_ss_t block.section.better_way)" >&2
        echo "    git rm --cached <path>      # remove from Git, keep local file" >&2
        echo "    Update .gitignore and rotate the secret if it was real." >&2
        _ss_block_rule
        echo "  Agent force (only after review):" >&2
        echo "    SHELL_SECURE_GIT_LEAK_FORCE=1 git push ..." >&2
    fi
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | git-leak | $(_ss_git_leak_summary "$findings")"
    return 1
}

_ss_git_leak_guard_push() {
    _ss_git_leak_extract_push_args "$@" || return 0
    _ss_git_leak_push_is_dry_run "${_ss_git_leak_push_args[@]}" && return 0
    command git "${_ss_git_pre_opts[@]}" rev-parse --git-dir >/dev/null 2>&1 || return 0

    local findings
    findings=$(_ss_git_leak_collect_findings "${_ss_git_leak_push_args[@]}")
    [ -n "$findings" ] || return 0

    local full="${_ss_git_command_name:-git} $*"
    local repo_root
    repo_root=$(_ss_git_repo_root_label)

    if _ss_git_leak_force_requested; then
        if [ "$(_ss_lang)" = "de" ]; then
            echo "  [Shell-Secure] Git-Leak-Schutz per SHELL_SECURE_GIT_LEAK_FORCE=1 übergangen: $full" >&2
        else
            echo "  [Shell-Secure] Git leak protection forced via SHELL_SECURE_GIT_LEAK_FORCE=1: $full" >&2
        fi
        _ss_log "FORCED | $full | git-leak | $(_ss_git_leak_summary "$findings")"
        return 0
    fi

    if _ss_git_leak_prompt_allow "$full" "$repo_root" "$findings"; then
        _ss_log "ALLOWED | $full | git-leak | $(_ss_git_leak_summary "$findings")"
        return 0
    fi

    _ss_block_git_leak "$full" "$repo_root" "$findings"
}
