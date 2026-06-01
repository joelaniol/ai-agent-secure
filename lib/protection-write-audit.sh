# Read this file first when changing terminal/PTY write audits.
# Purpose: catch CRCRLF bytes produced by risky shell writes such as
#          `cat <<EOF > file` before those bytes are copied to the target.
# Scope: this is a local write audit for cat/tee. It cannot control Bash's
#        own redirection open/truncate step; git add/commit blocking stays in
#        protection-git-corruption.sh.

_ss_write_audit_stdout_target() {
    local target
    target=$(builtin command readlink "/proc/$$/fd/1" 2>/dev/null) || return 1
    [ -n "$target" ] || return 1
    case "$target" in
        /dev/*|pipe:*|socket:*|anon_inode:*|'')
            return 1
            ;;
    esac
    [ -f "$target" ] || return 1
    printf '%s' "$target"
}

_ss_write_audit_force_requested() {
    _ss_git_corruption_force_requested && return 0
    case "${SHELL_SECURE_WRITE_AUDIT_FORCE:-}" in
        1|true|TRUE|yes|YES|allow|ALLOW|force|FORCE)
            return 0
            ;;
    esac
    return 1
}

_ss_write_audit_temp_has_crcrlf() {
    local path="$1"
    local target="${2:-}"
    if [ -n "$target" ]; then
        _ss_git_corruption_path_should_scan "$target" || return 1
    fi
    _ss_git_corruption_stream_has_crcrlf < "$path"
}

_ss_write_audit_tee_targets() {
    local arg past_dashdash=false skip_next=false
    for arg in "$@"; do
        if $past_dashdash; then
            printf '%s\n' "$arg"
            continue
        fi
        if $skip_next; then
            skip_next=false
            continue
        fi
        case "$arg" in
            --)
                past_dashdash=true
                ;;
            --output-error)
                skip_next=true
                ;;
            --output-error=*)
                ;;
            -a|-i|-p|--append|--ignore-interrupts)
                ;;
            -*)
                # Combined short flags such as -ai are options; unknown long
                # options are left to real tee and should not be treated as files.
                ;;
            *)
                printf '%s\n' "$arg"
                ;;
        esac
    done
}

_ss_block_write_corruption() {
    local cmd_name="$1"
    local target="$2"

    echo "" >&2
    echo "  [Shell-Secure] $(_ss_t block.title)" >&2
    _ss_block_rule
    echo "  $(_ss_t block.label.blocked_by)$(_ss_t block.layer.write_corruption)" >&2
    echo "  $(_ss_t block.label.command)$cmd_name" >&2
    [ -n "$target" ] && echo "  $(_ss_t block.label.target)$target" >&2
    echo "  $(_ss_t block.label.reason)Korruption entdeckt / Corruption detected: CRCRLF bytes." >&2
    echo "                 A terminal/PTY write would create doubled carriage returns." >&2
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    echo "    Do not retry through editor, formatter, JSON/PHP rewrite, or UTF-8 parse/write." >&2
    echo "    Generate bytes through a safe script/API or normalize in a byte-only hygiene step." >&2
    echo "    Remove only the extra CR and preserve LF/CRLF policy before git add." >&2
    _ss_block_rule
    echo "  Note:" >&2
    echo "    Bash opens redirection targets before Shell-Secure can inspect stdin." >&2
    echo "    With '>' the target may already have been created or truncated." >&2
    _ss_block_rule
    echo "  Manual release:" >&2
    echo "    SHELL_SECURE_CORRUPTION_FORCE=1 <command>" >&2
    echo "    or SHELL_SECURE_WRITE_AUDIT_FORCE=1 <command>" >&2
    echo "    Only after verifying that the bytes are intentional." >&2
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $cmd_name | write-corruption | ${target:-stdout}: CRCRLF"
    return 1
}

_ss_write_audit_allow_or_block() {
    local cmd_name="$1"
    local target="$2"

    if _ss_write_audit_force_requested; then
        echo "  [Shell-Secure] Write corruption audit forced for: $cmd_name" >&2
        _ss_log "FORCED | $cmd_name | write-corruption | ${target:-stdout}: CRCRLF"
        return 0
    fi

    _ss_block_write_corruption "$cmd_name" "$target"
}

_ss_write_audit_stream_to_stdout() {
    local cmd_name="$1"
    local target="${2:-}"
    shift 2 || true

    if ! _ss_write_audit_protect_enabled; then
        "$@"
        return $?
    fi

    if [ -n "$target" ] && ! _ss_git_corruption_path_should_scan "$target"; then
        "$@"
        return $?
    fi

    local tmp rc
    tmp=$(builtin command mktemp) || {
        "$@"
        return $?
    }

    "$@" > "$tmp"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        builtin command rm -f "$tmp" 2>/dev/null || true
        return "$rc"
    fi

    if _ss_write_audit_temp_has_crcrlf "$tmp" "$target"; then
        if ! _ss_write_audit_allow_or_block "$cmd_name" "$target"; then
            builtin command rm -f "$tmp" 2>/dev/null || true
            return 1
        fi
    fi

    builtin command cat "$tmp"
    rc=$?
    builtin command rm -f "$tmp" 2>/dev/null || true
    return "$rc"
}

cat() {
    if ! _ss_write_audit_protect_enabled || [ -t 1 ]; then
        builtin command cat "$@"
        return $?
    fi

    local target
    target=$(_ss_write_audit_stdout_target 2>/dev/null || true)
    if [ -n "$target" ]; then
        _ss_write_audit_stream_to_stdout "cat $*" "$target" builtin command cat "$@"
        return $?
    fi
    builtin command cat "$@"
}

tee() {
    if ! _ss_write_audit_protect_enabled || [ -t 0 ]; then
        builtin command tee "$@"
        return $?
    fi

    local tmp rc target first_target="" scan_target="" scan_required=false
    first_target=$(_ss_write_audit_stdout_target 2>/dev/null || true)
    if [ -n "$first_target" ] && _ss_git_corruption_path_should_scan "$first_target"; then
        scan_required=true
        scan_target="$first_target"
    fi
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        [ -z "$first_target" ] && first_target="$target"
        if _ss_git_corruption_path_should_scan "$target"; then
            scan_required=true
            [ -z "$scan_target" ] && scan_target="$target"
        fi
    done < <(_ss_write_audit_tee_targets "$@")

    if ! $scan_required; then
        builtin command tee "$@"
        return $?
    fi

    tmp=$(builtin command mktemp) || {
        builtin command tee "$@"
        return $?
    }
    builtin command cat > "$tmp"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        builtin command rm -f "$tmp" 2>/dev/null || true
        return "$rc"
    fi

    if [ -z "$first_target" ]; then
        while IFS= read -r target; do
            [ -n "$target" ] || continue
            first_target="$target"
            break
        done < <(_ss_write_audit_tee_targets "$@")
    fi

    if _ss_write_audit_temp_has_crcrlf "$tmp" "$scan_target"; then
        if ! _ss_write_audit_allow_or_block "tee $*" "${scan_target:-$first_target}"; then
            builtin command rm -f "$tmp" 2>/dev/null || true
            return 1
        fi
    fi

    builtin command tee "$@" < "$tmp"
    rc=$?
    builtin command rm -f "$tmp" 2>/dev/null || true
    return "$rc"
}
