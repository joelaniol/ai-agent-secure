# Read this file first when changing git corruption detection.
# Purpose: block CRCRLF line-ending corruption before files enter Git via add
#          or commit.
# Scope: no git() wrapper; protection-git.sh owns dispatch and calls this slice
#        after _ss_git_pre_opts has been prepared.

declare -ag _ss_git_corruption_pathspecs=()
declare -ag _ss_git_corruption_commit_pathspecs=()
declare -g _ss_git_corruption_scan_all=false
declare -g _ss_git_corruption_add_tracked_only=false
declare -g _ss_git_corruption_commit_scan_tracked=false
declare -g _ss_git_corruption_commit_include=false
declare -g _ss_git_corruption_full=""

_ss_git_corruption_max_bytes() {
    local value="${SHELL_SECURE_CORRUPTION_MAX_BYTES:-20971520}"
    [[ "$value" =~ ^[0-9]+$ ]] || value=20971520
    printf '%s' "$value"
}

_ss_git_corruption_force_requested() {
    case "${SHELL_SECURE_CORRUPTION_FORCE:-}" in
        1|true|TRUE|yes|YES|allow|ALLOW|force|FORCE)
            return 0
            ;;
    esac
    return 1
}

_ss_git_corruption_path_is_binary_asset() {
    local path="${1,,}"
    case "$path" in
        *.7z|*.a|*.ai|*.arrow|*.avi|*.avif|*.bin|*.bmp|*.br|*.bz2|*.class|*.cur|*.dat|*.db|*.dbf|*.dfont|*.dll|*.dmg|*.doc|*.docx|*.eot|*.eps|*.exe|*.flac|*.fon|*.gif|*.gpkg|*.gz|*.h5|*.hdf5|*.heic|*.heif|*.ico|*.idx|*.iso|*.jar|*.jpeg|*.jpg|*.lib|*.lockb|*.lz|*.lz4|*.lzma|*.m4a|*.m4v|*.mbtiles|*.mdb|*.mkv|*.mmdb|*.mov|*.mp3|*.mp4|*.msi|*.npy|*.npz|*.o|*.obj|*.ogg|*.onnx|*.orc|*.otf|*.pack|*.parquet|*.pbf|*.pdf|*.png|*.ppt|*.pptx|*.psd|*.pyc|*.rar|*.rdb|*.shp|*.shx|*.so|*.sqlite|*.sqlite3|*.tar|*.tgz|*.tif|*.tiff|*.ttc|*.ttf|*.wasm|*.wav|*.webm|*.webp|*.woff|*.woff2|*.xls|*.xlsm|*.xlsx|*.xz|*.zip|*.zst)
            return 0
            ;;
    esac
    return 1
}

_ss_git_corruption_path_is_special_target() {
    case "${1:-}" in
        -|/dev/*|/proc/*|/sys/*|/run/*|pipe:*|socket:*|anon_inode:*)
            return 0
            ;;
    esac
    return 1
}

_ss_git_corruption_path_should_scan() {
    local path="${1:-}"
    [ -n "$path" ] || return 0
    _ss_git_corruption_path_is_special_target "$path" && return 1
    _ss_git_corruption_path_is_binary_asset "$path" && return 1
    return 0
}

_ss_git_corruption_stream_has_crcrlf() {
    if command -v perl >/dev/null 2>&1; then
        LC_ALL=C perl -e 'binmode STDIN; my $tail = ""; while (read(STDIN, my $buf, 65536)) { my $s = $tail . $buf; exit 1 if index($s, "\0") >= 0; exit 0 if index($s, "\r\r\n") >= 0; $tail = substr($s, -2); } exit 1'
        return $?
    fi
    # Fallback keeps the guard active on minimal Bash installs. It may also
    # match rare raw CRCR bytes not followed by LF, but that is still a strong
    # corruption signal for source text.
    LC_ALL=C grep -q $'\r\r'
}

_ss_git_corruption_file_has_crcrlf() {
    local path="$1"
    [ -f "$path" ] || return 1
    [ -r "$path" ] || return 1
    _ss_git_corruption_path_should_scan "$path" || return 1
    local size max_bytes
    size=$(wc -c < "$path" 2>/dev/null | tr -d '[:space:]') || size=0
    max_bytes=$(_ss_git_corruption_max_bytes)
    if [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt "$max_bytes" ]; then
        return 1
    fi
    _ss_git_corruption_stream_has_crcrlf < "$path"
}

_ss_git_corruption_index_path_has_crcrlf() {
    local path="$1"
    _ss_git_corruption_path_should_scan "$path" || return 1
    command git "${_ss_git_pre_opts[@]}" cat-file -e ":$path" 2>/dev/null || return 1
    local size max_bytes
    size=$(command git "${_ss_git_pre_opts[@]}" cat-file -s ":$path" 2>/dev/null || echo 0)
    max_bytes=$(_ss_git_corruption_max_bytes)
    if [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt "$max_bytes" ]; then
        return 1
    fi
    command git "${_ss_git_pre_opts[@]}" cat-file -p ":$path" 2>/dev/null |
        _ss_git_corruption_stream_has_crcrlf
}

_ss_git_corruption_read_pathspec_file() {
    local file="$1"
    local nul="${2:-false}"
    local target_array="$3"
    local spec

    [ -n "$file" ] && [ "$file" != "-" ] && [ -r "$file" ] || return 1
    if $nul; then
        while IFS= read -r -d '' spec; do
            [ -n "$spec" ] || continue
            case "$target_array" in
                add) _ss_git_corruption_pathspecs+=("$spec") ;;
                commit) _ss_git_corruption_commit_pathspecs+=("$spec") ;;
            esac
        done < "$file"
    else
        while IFS= read -r spec || [ -n "$spec" ]; do
            [ -n "$spec" ] || continue
            case "$target_array" in
                add) _ss_git_corruption_pathspecs+=("$spec") ;;
                commit) _ss_git_corruption_commit_pathspecs+=("$spec") ;;
            esac
        done < "$file"
    fi
    return 0
}

_ss_git_corruption_extract_add_pathspecs() {
    _ss_git_corruption_pathspecs=()
    _ss_git_corruption_scan_all=false
    _ss_git_corruption_add_tracked_only=false
    local arg pathspec_file="" past_dashdash=false skip_next=false skip_kind="" pathspec_file_nul=false

    for arg in "$@"; do
        if $past_dashdash; then
            _ss_git_corruption_pathspecs+=("$arg")
            continue
        fi
        if $skip_next; then
            [ "$skip_kind" = "pathspec" ] && pathspec_file="$arg"
            skip_next=false
            skip_kind=""
            continue
        fi
        case "$arg" in
            --)
                past_dashdash=true
                ;;
            --pathspec-from-file)
                skip_next=true
                skip_kind="pathspec"
                ;;
            --pathspec-file-nul)
                pathspec_file_nul=true
                ;;
            --chmod)
                skip_next=true
                skip_kind="other"
                ;;
            --pathspec-from-file=*)
                pathspec_file="${arg#--pathspec-from-file=}"
                ;;
            --chmod=*)
                ;;
            -u|--update|--renormalize)
                _ss_git_corruption_add_tracked_only=true
                ;;
            -*)
                [[ "${arg#-}" == *u* ]] && _ss_git_corruption_add_tracked_only=true
                ;;
            *)
                _ss_git_corruption_pathspecs+=("$arg")
                ;;
        esac
    done

    if [ -n "$pathspec_file" ]; then
        _ss_git_corruption_pathspecs=()
        if ! _ss_git_corruption_read_pathspec_file "$pathspec_file" "$pathspec_file_nul" "add"; then
            _ss_git_corruption_scan_all=true
        fi
    fi
}

_ss_git_corruption_commit_stages_worktree() {
    local arg past_dashdash=false
    for arg in "$@"; do
        $past_dashdash && continue
        case "$arg" in
            --)
                past_dashdash=true
                ;;
            -a|--all)
                return 0
                ;;
            -[!-]*)
                [[ "${arg#-}" == *a* ]] && return 0
                ;;
        esac
    done
    return 1
}

_ss_git_corruption_extract_commit_pathspecs() {
    _ss_git_corruption_commit_pathspecs=()
    _ss_git_corruption_commit_scan_tracked=false
    _ss_git_corruption_commit_include=false
    local arg short pathspec_file="" past_dashdash=false skip_next=false skip_kind="" pathspec_file_nul=false

    for arg in "$@"; do
        if $past_dashdash; then
            _ss_git_corruption_commit_pathspecs+=("$arg")
            continue
        fi
        if $skip_next; then
            [ "$skip_kind" = "pathspec" ] && pathspec_file="$arg"
            skip_next=false
            skip_kind=""
            continue
        fi
        case "$arg" in
            --)
                past_dashdash=true
                ;;
            --pathspec-from-file)
                skip_next=true
                skip_kind="pathspec"
                ;;
            --pathspec-file-nul)
                pathspec_file_nul=true
                ;;
            --pathspec-from-file=*)
                pathspec_file="${arg#--pathspec-from-file=}"
                ;;
            --include)
                _ss_git_corruption_commit_include=true
                ;;
            --message|--file|--reuse-message|--reedit-message|--author|--date|--cleanup|--fixup|--squash|--gpg-sign)
                skip_next=true
                skip_kind="other"
                ;;
            --message=*|--file=*|--reuse-message=*|--reedit-message=*|--author=*|--date=*|--cleanup=*|--fixup=*|--squash=*|--gpg-sign=*)
                ;;
            --all|--only|--amend|--no-edit|--allow-empty|--allow-empty-message|--no-verify|--signoff|--verbose|--quiet)
                ;;
            --*)
                ;;
            -m?*|-F?*|-C?*|-c?*|-S?*)
                ;;
            -[!-]*)
                short="${arg#-}"
                if [[ "$short" == *[mFCcS] ]]; then
                    skip_next=true
                    skip_kind="other"
                fi
                ;;
            *)
                _ss_git_corruption_commit_pathspecs+=("$arg")
                ;;
        esac
    done

    if [ -n "$pathspec_file" ]; then
        _ss_git_corruption_commit_pathspecs=()
        if ! _ss_git_corruption_read_pathspec_file "$pathspec_file" "$pathspec_file_nul" "commit"; then
            _ss_git_corruption_commit_scan_tracked=true
        fi
    fi
}

_ss_git_corruption_collect_worktree_findings() {
    local tracked_only="${1:-false}"
    shift || true
    local -a pathspecs=("$@")
    local path
    declare -A seen_paths=()

    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        [ -n "${seen_paths[$path]+x}" ] && continue
        seen_paths[$path]=1
        if _ss_git_corruption_file_has_crcrlf "$path"; then
            printf '%s\n' "$path"
        fi
    done < <(command git "${_ss_git_pre_opts[@]}" diff --name-only -z --diff-filter=ACMRTUXB -- "${pathspecs[@]}" 2>/dev/null || true)

    $tracked_only && return 0

    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        [ -n "${seen_paths[$path]+x}" ] && continue
        seen_paths[$path]=1
        if _ss_git_corruption_file_has_crcrlf "$path"; then
            printf '%s\n' "$path"
        fi
    done < <(command git "${_ss_git_pre_opts[@]}" ls-files -z --others --exclude-standard -- "${pathspecs[@]}" 2>/dev/null || true)
}

_ss_git_corruption_collect_staged_findings() {
    local path
    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        if _ss_git_corruption_index_path_has_crcrlf "$path"; then
            printf '%s\n' "$path"
        fi
    done < <(command git "${_ss_git_pre_opts[@]}" diff --cached --name-only -z --diff-filter=ACMRTUXB 2>/dev/null || true)
}

_ss_git_corruption_format_findings() {
    local findings="$1"
    local limit="${2:-10}"
    local count=0 total=0 path out=""

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        total=$((total + 1))
        if [ "$count" -lt "$limit" ]; then
            out+="    - $path"$'\n'
            count=$((count + 1))
        fi
    done <<< "$findings"

    if [ "$total" -gt "$limit" ]; then
        out+="    - ... and $((total - limit)) more"$'\n'
    fi

    printf '%s' "$out"
}

_ss_git_corruption_summary() {
    local findings="$1"
    local path out=""

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -n "$out" ]; then
            out+="; $path"
        else
            out="$path"
        fi
    done <<< "$findings"

    printf '%s' "$out"
}

_ss_block_git_corruption() {
    local full="$1"
    local repo_root="$2"
    local findings="$3"

    _ss_git_block_header "$(_ss_t block.layer.git_corruption)" "$full" "$repo_root"
    echo "  $(_ss_t block.label.reason)Korruption entdeckt / Corruption detected: CRCRLF line endings." >&2
    echo "                 A doubled carriage return before LF would enter Git and" >&2
    echo "                 later create huge semantic-free whitespace diffs." >&2
    _ss_block_rule
    echo "  Affected paths:" >&2
    _ss_git_corruption_format_findings "$findings" 10 >&2
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    echo "    Do not repair this via editor, formatter, JSON/PHP rewrite, or UTF-8 parse/write." >&2
    echo "    Use a clean worktree/clone and a byte-only hygiene commit." >&2
    echo "    Remove only the extra CR and keep the file/repo line-ending policy:" >&2
    echo "      LF policy:   0D 0D 0A  ->  0A" >&2
    echo "      CRLF policy: 0D 0D 0A  ->  0D 0A" >&2
    echo "    Leave every other byte unchanged; do not re-encode file contents." >&2
    echo "    Then rerun the corruption guard." >&2
    echo "    Also run git diff --check and format-specific smokes (for example JSON parse)." >&2
    _ss_block_rule
    echo "  Manual release:" >&2
    echo "    SHELL_SECURE_CORRUPTION_FORCE=1 git ..." >&2
    echo "    Only after verifying the byte-level line endings intentionally." >&2
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | git-corruption | $(_ss_git_corruption_summary "$findings")"
    return 1
}

_ss_git_corruption_allow_or_block() {
    local full="$1"
    local repo_root="$2"
    local findings="$3"
    [ -n "$findings" ] || return 0

    if _ss_git_corruption_force_requested; then
        echo "  [Shell-Secure] Git corruption protection forced via SHELL_SECURE_CORRUPTION_FORCE=1: $full" >&2
        _ss_log "FORCED | $full | git-corruption | $(_ss_git_corruption_summary "$findings")"
        return 0
    fi

    _ss_block_git_corruption "$full" "$repo_root" "$findings"
}

_ss_git_corruption_guard_add() {
    _ss_git_corruption_extract_add_pathspecs "$@"
    command git "${_ss_git_pre_opts[@]}" rev-parse --git-dir >/dev/null 2>&1 || return 0

    local -a pathspecs=()
    if ! $_ss_git_corruption_scan_all; then
        pathspecs=("${_ss_git_corruption_pathspecs[@]}")
    fi

    local findings
    findings=$(_ss_git_corruption_collect_worktree_findings "$_ss_git_corruption_add_tracked_only" "${pathspecs[@]}")
    [ -n "$findings" ] || return 0

    local full="${_ss_git_corruption_full:-${_ss_git_command_name:-git} $*}"
    local repo_root
    repo_root=$(_ss_git_repo_root_label)
    _ss_git_corruption_allow_or_block "$full" "$repo_root" "$findings"
}

_ss_git_corruption_guard_commit() {
    command git "${_ss_git_pre_opts[@]}" rev-parse --git-dir >/dev/null 2>&1 || return 0

    _ss_git_corruption_extract_commit_pathspecs "$@"

    local findings="" pathspec_findings worktree_findings
    local has_pathspec=false
    $_ss_git_corruption_commit_scan_tracked || [ "${#_ss_git_corruption_commit_pathspecs[@]}" -gt 0 ] && has_pathspec=true

    # Git's pathspec/--only commit mode ignores unrelated staged changes. Avoid
    # blocking a safe pathspec commit because another staged file is corrupt.
    if ! $has_pathspec || $_ss_git_corruption_commit_include; then
        findings=$(_ss_git_corruption_collect_staged_findings)
    fi

    if $has_pathspec; then
        local -a pathspecs=()
        if ! $_ss_git_corruption_commit_scan_tracked; then
            pathspecs=("${_ss_git_corruption_commit_pathspecs[@]}")
        fi
        pathspec_findings=$(_ss_git_corruption_collect_worktree_findings true "${pathspecs[@]}")
        if [ -n "$pathspec_findings" ]; then
            findings="${findings}${findings:+$'\n'}${pathspec_findings}"
        fi
    elif _ss_git_corruption_commit_stages_worktree "$@"; then
        worktree_findings=$(_ss_git_corruption_collect_worktree_findings true)
        if [ -n "$worktree_findings" ]; then
            findings="${findings}${findings:+$'\n'}${worktree_findings}"
        fi
    fi

    [ -n "$findings" ] || return 0

    local full="${_ss_git_corruption_full:-${_ss_git_command_name:-git} $*}"
    local repo_root
    repo_root=$(_ss_git_repo_root_label)
    _ss_git_corruption_allow_or_block "$full" "$repo_root" "$findings"
}

_ss_git_corruption_guard_git_command() {
    local sub="$1"
    shift || true
    case "$sub" in
        add)
            _ss_git_corruption_guard_add "$@"
            ;;
        commit)
            _ss_git_corruption_guard_commit "$@"
            ;;
        *)
            return 0
            ;;
    esac
}
