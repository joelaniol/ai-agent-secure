# Read this file first when changing git corruption detection.
# Purpose: block byte-level corruption before it enters or leaves Git -- both CRCRLF
#          line-ending corruption (0D 0D 0A) and forbidden control bytes
#          (01-08, 0B, 0C, 0E-1F, 7F; TAB/LF/CR stay allowed) -- on add, commit, and
#          (range scan) push. NUL/UTF-16 content is skipped to avoid Windows false
#          positives; NUL/BOM stay the encoding layer's job.
# Scope: no git() wrapper; protection-git.sh owns dispatch and calls this slice
#        after _ss_git_pre_opts has been prepared.

declare -ag _ss_git_corruption_pathspecs=()
declare -ag _ss_git_corruption_commit_pathspecs=()
declare -g _ss_git_corruption_scan_all=false
declare -g _ss_git_corruption_add_tracked_only=false
declare -g _ss_git_corruption_commit_scan_tracked=false
declare -g _ss_git_corruption_commit_include=false
declare -g _ss_git_corruption_full=""
declare -g _ss_git_corruption_context="commit"

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

# Detects byte-level corruption on a stream and prints the kind(s) found, empty if clean:
#   "crcrlf"       doubled carriage return before LF (bytes 0D 0D 0A)
#   "ctrl"         a forbidden control byte: 01-08, 0B, 0C, 0E-1F, 7F
#                  (TAB 09, LF 0A, CR 0D stay allowed -- CRLF is the Windows norm)
#   "crcrlf+ctrl"  both classes present
# Content with a NUL byte (binary, or UTF-16 text which on Windows legitimately carries
# 0x00) is skipped entirely to avoid false positives; NUL/BOM stay the encoding layer's job.
_ss_git_corruption_stream_kind() {
    if command -v perl >/dev/null 2>&1; then
        LC_ALL=C perl -e '
            binmode STDIN;
            my $tail = ""; my $crcrlf = 0; my $ctrl = 0;
            while (read(STDIN, my $buf, 65536)) {
                # NUL => binary or UTF-16; skip the file, emit nothing.
                exit 0 if index($buf, "\0") >= 0;
                my $s = $tail . $buf;
                $crcrlf = 1 if index($s, "\r\r\n") >= 0;
                $ctrl = 1 if $buf =~ /[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]/;
                $tail = substr($s, -2);
            }
            my @k;
            push @k, "crcrlf" if $crcrlf;
            push @k, "ctrl" if $ctrl;
            print join("+", @k) if @k;
        '
        return 0
    fi
    # Fallback for minimal installs without perl: streamed CRCRLF only. Control-byte
    # detection requires perl (a streamed two-pattern byte scan is not safe in pure Bash
    # because variables cannot hold NUL); the full-suite encoding-lint still covers it.
    if LC_ALL=C grep -q $'\r\r'; then
        printf 'crcrlf'
    fi
}

_ss_git_corruption_file_kind() {
    local path="$1"
    [ -f "$path" ] || return 0
    [ -r "$path" ] || return 0
    _ss_git_corruption_path_should_scan "$path" || return 0
    local size max_bytes
    size=$(wc -c < "$path" 2>/dev/null | tr -d '[:space:]') || size=0
    max_bytes=$(_ss_git_corruption_max_bytes)
    if [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt "$max_bytes" ]; then
        return 0
    fi
    _ss_git_corruption_stream_kind < "$path"
}

# Scans the blob at "<ref>:<path>". Empty ref ("") means the index (":path"); "HEAD" means
# the committed tip, etc. Prints the corruption kind, empty if clean / missing / oversized.
_ss_git_corruption_blob_kind() {
    local ref="$1" path="$2"
    _ss_git_corruption_path_should_scan "$path" || return 0
    command git "${_ss_git_pre_opts[@]}" cat-file -e "${ref}:$path" 2>/dev/null || return 0
    local size max_bytes
    size=$(command git "${_ss_git_pre_opts[@]}" cat-file -s "${ref}:$path" 2>/dev/null || echo 0)
    max_bytes=$(_ss_git_corruption_max_bytes)
    if [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt "$max_bytes" ]; then
        return 0
    fi
    command git "${_ss_git_pre_opts[@]}" cat-file -p "${ref}:$path" 2>/dev/null |
        _ss_git_corruption_stream_kind
}

# Batch worktree scan: ONE perl process scans every given path (size via stat, then the
# same byte scan as _ss_git_corruption_stream_kind), replacing the per-file wc+perl spawns
# that dominate cost on Windows/MSYS2. Paths must already be filtered through
# _ss_git_corruption_path_should_scan. Prints "kind\tpath" per corrupt file. Falls back to
# the per-file scanner when perl is unavailable.
_ss_git_corruption_scan_worktree_paths() {
    [ "$#" -gt 0 ] || return 0
    if ! command -v perl >/dev/null 2>&1; then
        local path kind
        for path in "$@"; do
            kind=$(_ss_git_corruption_file_kind "$path")
            [ -n "$kind" ] && printf '%s\t%s\n' "$kind" "$path"
        done
        return 0
    fi
    local max_bytes
    max_bytes=$(_ss_git_corruption_max_bytes)
    printf '%s\0' "$@" | LC_ALL=C SS_CORRUPT_MAX="$max_bytes" perl -0 -e '
        my $max = $ENV{SS_CORRUPT_MAX} + 0;
        while (defined(my $path = <STDIN>)) {
            chomp $path;                        # strips the trailing NUL ($/ is NUL under -0)
            next if $path eq "";
            next unless -f $path && -r $path;
            next if (-s $path) > $max;          # oversize: skip, same as the per-file path
            open(my $fh, "<:raw", $path) or next;
            my $tail = ""; my $crcrlf = 0; my $ctrl = 0; my $nul = 0; my $buf;
            while (read($fh, $buf, 65536)) {
                if (index($buf, "\0") >= 0) { $nul = 1; last; }   # binary/UTF-16: skip file
                my $s = $tail . $buf;
                $crcrlf = 1 if index($s, "\r\r\n") >= 0;
                $ctrl = 1 if $buf =~ /[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]/;
                $tail = substr($s, -2);
            }
            close($fh);
            next if $nul;
            my @k; push @k, "crcrlf" if $crcrlf; push @k, "ctrl" if $ctrl;
            print join("+", @k) . "\t" . $path . "\n" if @k;
        }
    '
}

# Batch blob scan: ONE "git cat-file --batch" + ONE perl scan every requested blob,
# replacing the per-blob cat-file -e/-s/-p + perl spawns. <ref> empty => index (":path"),
# "HEAD" => committed tip. Paths must already be should_scan-filtered. cat-file emits
# exactly one record per input spec (including "<spec> missing"), so the k-th LF-framed
# record pairs with the k-th path. Prints "kind\tpath" per corrupt blob. Falls back to the
# per-blob scanner when perl is missing or for the rare path containing a newline
# (cat-file batch input is newline-delimited and cannot carry such a path).
_ss_git_corruption_scan_blobs() {
    local ref="$1"; shift || true
    [ "$#" -gt 0 ] || return 0

    local -a batch=() fallback=()
    local p
    if command -v perl >/dev/null 2>&1; then
        for p in "$@"; do
            case "$p" in
                *$'\n'*) fallback+=("$p") ;;
                *) batch+=("$p") ;;
            esac
        done
    else
        fallback=("$@")
    fi

    local path kind
    for path in ${fallback[@]+"${fallback[@]}"}; do
        kind=$(_ss_git_corruption_blob_kind "$ref" "$path")
        [ -n "$kind" ] && printf '%s\t%s\n' "$kind" "$path"
    done

    [ "${#batch[@]}" -gt 0 ] || return 0
    local max_bytes
    max_bytes=$(_ss_git_corruption_max_bytes)
    local -a specs=()
    for p in "${batch[@]}"; do specs+=("${ref}:$p"); done
    # Parse the standard LF-framed output (stable across git versions); read each blob's
    # content by its declared size. The ordered paths arrive as @ARGV for index pairing.
    printf '%s\n' "${specs[@]}" \
        | command git "${_ss_git_pre_opts[@]}" cat-file --batch 2>/dev/null \
        | LC_ALL=C SS_CORRUPT_MAX="$max_bytes" perl -e '
            my $max = $ENV{SS_CORRUPT_MAX} + 0;
            my @paths = @ARGV; @ARGV = ();
            binmode STDIN;
            my $idx = 0;
            sub hdr { my $l = ""; my $c; my $n; while (($n = read(STDIN, $c, 1)) > 0) { last if $c eq "\n"; $l .= $c; } return ($n <= 0 && $l eq "") ? undef : $l; }
            sub rdn { my ($want) = @_; my $out = ""; while (length($out) < $want) { my $g = read(STDIN, my $b, $want - length($out)); last if !defined($g) || $g <= 0; $out .= $b; } return $out; }
            while (defined(my $h = hdr())) {
                my $path = $idx < scalar(@paths) ? $paths[$idx] : "";
                $idx++;
                if ($h =~ /^[0-9a-fA-F]+ (\S+) (\d+)$/) {
                    my ($type, $size) = ($1, $2 + 0);
                    my $content = rdn($size);
                    rdn(1);                       # trailing LF after the blob content
                    next if $type ne "blob";
                    next if $size > $max;
                    next if index($content, "\0") >= 0;
                    my $crcrlf = index($content, "\r\r\n") >= 0 ? 1 : 0;
                    my $ctrl = $content =~ /[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]/ ? 1 : 0;
                    my @k; push @k, "crcrlf" if $crcrlf; push @k, "ctrl" if $ctrl;
                    print join("+", @k) . "\t" . $path . "\n" if @k;
                }
                # else: "<spec> missing" / unresolvable => no content follows, emit nothing.
            }
        ' -- "${batch[@]}"
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

# Collects scannable changed/untracked worktree paths (deduped, should_scan-filtered),
# then hands the whole set to one batch scan instead of spawning per file.
_ss_git_corruption_collect_worktree_findings() {
    local tracked_only="${1:-false}"
    shift || true
    local -a pathspecs=("$@")
    local path
    declare -A seen_paths=()
    local -a candidates=()

    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        [ -n "${seen_paths[$path]+x}" ] && continue
        seen_paths[$path]=1
        _ss_git_corruption_path_should_scan "$path" || continue
        candidates+=("$path")
    done < <(command git "${_ss_git_pre_opts[@]}" diff --name-only -z --diff-filter=ACMRTUXB -- "${pathspecs[@]}" 2>/dev/null || true)

    if ! $tracked_only; then
        while IFS= read -r -d '' path; do
            [ -n "$path" ] || continue
            [ -n "${seen_paths[$path]+x}" ] && continue
            seen_paths[$path]=1
            _ss_git_corruption_path_should_scan "$path" || continue
            candidates+=("$path")
        done < <(command git "${_ss_git_pre_opts[@]}" ls-files -z --others --exclude-standard -- "${pathspecs[@]}" 2>/dev/null || true)
    fi

    _ss_git_corruption_scan_worktree_paths ${candidates[@]+"${candidates[@]}"}
}

_ss_git_corruption_collect_staged_findings() {
    local path
    local -a candidates=()
    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        _ss_git_corruption_path_should_scan "$path" || continue
        candidates+=("$path")
    done < <(command git "${_ss_git_pre_opts[@]}" diff --cached --name-only -z --diff-filter=ACMRTUXB 2>/dev/null || true)
    _ss_git_corruption_scan_blobs "" ${candidates[@]+"${candidates[@]}"}
}

# Findings lines are "kind\tpath". Display the path and annotate the kind.
_ss_git_corruption_format_findings() {
    local findings="$1"
    local limit="${2:-10}"
    local count=0 total=0 line path kind out=""

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        total=$((total + 1))
        if [ "$count" -lt "$limit" ]; then
            kind="${line%%$'\t'*}"
            path="${line#*$'\t'}"
            out+="    - $path  [$kind]"$'\n'
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
    local line path out=""

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        path="${line#*$'\t'}"
        if [ -n "$out" ]; then
            out+="; $path"
        else
            out="$path"
        fi
    done <<< "$findings"

    printf '%s' "$out"
}

# Human-readable label of the distinct corruption classes present in the findings.
_ss_git_corruption_kinds_label() {
    local findings="$1"
    local line kind has_crcrlf=false has_ctrl=false
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        kind="${line%%$'\t'*}"
        [[ "$kind" == *crcrlf* ]] && has_crcrlf=true
        [[ "$kind" == *ctrl* ]] && has_ctrl=true
    done <<< "$findings"
    local out=""
    $has_crcrlf && out="CRCRLF line endings (0D 0D 0A)"
    if $has_ctrl; then
        [ -n "$out" ] && out="$out + "
        out="${out}forbidden control bytes (01-08, 0B, 0C, 0E-1F, 7F)"
    fi
    printf '%s' "$out"
}

_ss_block_git_corruption() {
    local full="$1"
    local repo_root="$2"
    local findings="$3"
    local context="${_ss_git_corruption_context:-commit}"
    local kinds
    kinds=$(_ss_git_corruption_kinds_label "$findings")
    [ -n "$kinds" ] || kinds="byte-level corruption"

    # Agent-facing block: kept English-only on purpose so the warning reads the same
    # for every agent (Codex, Claude Code, ...). GUI settings strings stay localized.
    _ss_git_block_header "Git Corruption Protection" "$full" "$repo_root"
    echo "  Reason:         Corruption detected: ${kinds}." >&2
    if [ "$context" = "push" ]; then
        echo "                  Already-committed corruption is in the push range." >&2
    else
        echo "                  Byte-level corruption would enter Git and later create huge" >&2
        echo "                  semantic-free diffs or binary-garbage source files." >&2
    fi
    _ss_block_rule
    echo "  Affected paths:" >&2
    _ss_git_corruption_format_findings "$findings" 10 >&2
    _ss_block_rule
    # URGENT: this is not a routine lint failure. Make the agent stop and escalate.
    echo "  ====================================================================" >&2
    echo "   URGENT WARNING" >&2
    echo "  ====================================================================" >&2
    echo "   Something is very likely seriously wrong with the codebase." >&2
    echo "" >&2
    echo "   AGENT - DO NOW:" >&2
    echo "     1. STOP. Halt ALL further write/edit/commit operations now." >&2
    echo "     2. If a script or tool YOU wrote/ran produced these bytes, ABORT it" >&2
    echo "        immediately - do not run it again until the user has reviewed it." >&2
    echo "     3. STOP any active goal AND scheduled task/loop immediately -" >&2
    echo "        do not continue, do not reschedule or re-arm:" >&2
    echo "          - Codex: set the goal to blocked or complete." >&2
    echo "          - Claude Code: cancel the scheduled task; do not reschedule the loop." >&2
    echo "          - any agent: halt the run and hand control back to the user." >&2
    echo "     4. Inspect the affected files at byte level:" >&2
    echo '          git show ":<path>" | od -An -tx1 | less   (staged)' >&2
    echo '          od -An -tx1 "<path>"                       (worktree)' >&2
    echo "     5. Inform the user IMMEDIATELY - this is NOT a routine lint error." >&2
    _ss_block_rule
    echo "  Better way:" >&2
    echo "    Do not 'repair' via editor reformat, JSON/PHP rewrite, or UTF-8 parse/write." >&2
    echo "    Use a clean worktree/clone and a byte-only hygiene fix:" >&2
    echo "      CRCRLF:        0D 0D 0A -> 0A (LF policy) or 0D 0A (CRLF policy)." >&2
    echo "      control bytes: re-type the affected text; a raw 07/08/0C is usually a" >&2
    echo '                     PowerShell backtick-escape (`a `b `f) decoded into a byte.' >&2
    echo "    Leave every other byte unchanged; do not re-encode the file." >&2
    echo "    Then rerun the guard and 'git diff --check'." >&2
    _ss_block_rule
    echo "  Manual release (only after verifying the bytes are intentional):" >&2
    echo "    SHELL_SECURE_CORRUPTION_FORCE=1 git ..." >&2
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | git-corruption($context:${kinds}) | $(_ss_git_corruption_summary "$findings")"
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

# Pre-push range scan: warns before pushing if already-committed blobs in the outgoing
# range carry corruption. This catches corruption that entered the repo before this guard
# existed (or via a write path that never crossed Bash, e.g. the editor/PowerShell tool).
_ss_git_corruption_guard_push() {
    command git "${_ss_git_pre_opts[@]}" rev-parse --git-dir >/dev/null 2>&1 || return 0
    command git "${_ss_git_pre_opts[@]}" rev-parse --verify HEAD >/dev/null 2>&1 || return 0

    local range upstream
    local empty_tree="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
    upstream=$(command git "${_ss_git_pre_opts[@]}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
    if [ -n "$upstream" ]; then
        range="${upstream}..HEAD"
    elif command git "${_ss_git_pre_opts[@]}" rev-parse --verify HEAD~1 >/dev/null 2>&1; then
        # No upstream (e.g. first push of a branch): best-effort scan of the tip commit.
        range="HEAD~1..HEAD"
    else
        # Single commit, no upstream: scan the whole tip tree against the empty tree.
        range="${empty_tree}..HEAD"
    fi

    local path
    local -a candidates=()
    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        _ss_git_corruption_path_should_scan "$path" || continue
        candidates+=("$path")
    done < <(command git "${_ss_git_pre_opts[@]}" diff --name-only -z --diff-filter=ACMRTUX "$range" -- 2>/dev/null || true)
    local findings
    findings=$(_ss_git_corruption_scan_blobs "HEAD" ${candidates[@]+"${candidates[@]}"})
    [ -n "$findings" ] || return 0

    local full="${_ss_git_corruption_full:-${_ss_git_command_name:-git} push}"
    local repo_root
    repo_root=$(_ss_git_repo_root_label)
    _ss_git_corruption_allow_or_block "$full" "$repo_root" "$findings"
}

_ss_git_corruption_guard_git_command() {
    local sub="$1"
    shift || true
    case "$sub" in
        add)
            _ss_git_corruption_context="add"
            _ss_git_corruption_guard_add "$@"
            ;;
        commit)
            _ss_git_corruption_context="commit"
            _ss_git_corruption_guard_commit "$@"
            ;;
        push)
            _ss_git_corruption_context="push"
            _ss_git_corruption_guard_push "$@"
            ;;
        *)
            return 0
            ;;
    esac
}
