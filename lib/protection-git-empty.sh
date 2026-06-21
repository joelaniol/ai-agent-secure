# Read this file first when changing the empty / zeroed-file guard.
# Purpose: block files with NO real content -- 0-byte OR entirely-NUL (size>0, every byte
#          0x00) -- from entering Git on add/commit/push. This is the crash/truncation
#          corruption class the byte-scanner deliberately SKIPS (it ignores NUL/empty to
#          avoid UTF-16 false positives), so it is its own slice with its own toggle.
# Scope: no git() wrapper; protection-git.sh dispatches here after _ss_git_pre_opts is set.
#        Reuses protection-git-corruption.sh pathspec extraction (that slice loads first).
#
# Decision (union policy):
#   - A path on the legit-empty allowlist is never flagged.
#   - TRUNCATION: a path whose prior committed blob had real content but is now empty/NUL
#     is flagged regardless of extension (a file that HAD content losing it is corruption).
#   - NEW void file: a path absent from HEAD that is empty/NUL is flagged only when it has a
#     mandatory-content extension (a brand-new empty marker of another type may be intended).
#   - A path that was already empty/NUL before stays unflagged (no regression introduced).

declare -Ag _ss_git_empty_allow_globs=()

_ss_git_empty_force_requested() {
    case "${SHELL_SECURE_EMPTY_FILE_FORCE:-}" in
        1|true|TRUE|yes|YES|allow|ALLOW|force|FORCE) return 0 ;;
    esac
    return 1
}

# Extensions whose files are broken/meaningless when empty. Gates only the NEW-file rule;
# truncation is flagged for any extension.
_ss_git_empty_mandatory_ext() {
    case "${1,,}" in
        *.php|*.js|*.mjs|*.cjs|*.jsx|*.ts|*.tsx|*.css|*.scss|*.sass|*.less|\
        *.json|*.json5|*.html|*.htm|*.xml|*.yaml|*.yml|*.toml|*.ini|*.sql|\
        *.py|*.rb|*.go|*.rs|*.java|*.kt|*.c|*.h|*.cc|*.cpp|*.hpp|*.cs|*.swift|\
        *.sh|*.bash|*.zsh|*.ps1|*.psm1|*.pl|*.lua|*.vue|*.svelte)
            return 0 ;;
        # Note: .md/.markdown/.txt are intentionally NOT here -- a new empty Markdown/text
        # file is legitimate (CHANGELOG/NOTES stubs). Truncating a tracked one still blocks
        # via the prior=content path (any extension).
    esac
    return 1
}

_ss_git_empty_allowlist_file() {
    printf '%s' "${SHELL_SECURE_EMPTY_FILE_ALLOWLIST:-$SHELL_SECURE_DIR/empty-file-allowlist}"
}

# (Re)load user glob patterns from the sidecar; built-ins are matched separately. Read each
# block (only on a detected finding), so mid-session edits take effect like config re-reads.
_ss_git_empty_load_allowlist() {
    _ss_git_empty_allow_globs=()
    local file line
    file=$(_ss_git_empty_allowlist_file)
    [ -r "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -n "$line" ] || continue
        _ss_git_empty_allow_globs["$line"]=1
    done < "$file"
}

# True when a repo-relative path is a known-legit empty file (never flagged). Built-in
# defaults cover the common intentional-empties; the sidecar adds project-specific globs.
_ss_git_empty_path_allowlisted() {
    local path="$1" base="${1##*/}" glob
    case "$base" in
        .gitkeep|.keep|.nojekyll|__init__.py|__main__.py|conftest.py|py.typed|gc.properties) return 0 ;;
    esac
    case "$path" in
        temp/*|*/temp/*|logs/*|*/logs/*|*.log|.playwright-mcp/*|docs/.vitepress/dist/*) return 0 ;;
    esac
    _ss_git_empty_load_allowlist
    for glob in "${!_ss_git_empty_allow_globs[@]}"; do
        [[ "$path" == $glob ]] && return 0
        [[ "$base" == $glob ]] && return 0
    done
    return 1
}

# Classify a worktree file: "empty" | "nul" | "content" | "" (missing). The all-NUL test
# is NOT size-capped: a large tracked file crash-zeroed to all-NUL is exactly the truncation
# class this guard targets. The `head -c1` makes it early-exit on the first non-NUL byte
# (tr gets SIGPIPE), so it stays cheap even on large content files.
_ss_git_empty_worktree_state() {
    local path="$1"
    [ -e "$path" ] || { printf ''; return; }
    [ -f "$path" ] && [ -r "$path" ] || { printf 'content'; return; }
    local size; size=$(wc -c < "$path" 2>/dev/null | tr -d '[:space:]') || size=0
    [ "$size" = "0" ] && { printf 'empty'; return; }
    local nonnul; nonnul=$(LC_ALL=C tr -d '\000' < "$path" 2>/dev/null | head -c1 | wc -c | tr -d '[:space:]')
    [ "$nonnul" = "0" ] && printf 'nul' || printf 'content'
}

# Classify a blob at "<ref>:<path>": "empty" | "nul" | "content" | "absent". The all-NUL
# test is not size-capped (see _ss_git_empty_worktree_state); `head -c1` early-exits the
# cat-file stream on the first non-NUL byte.
_ss_git_empty_blob_state() {
    local ref="$1" path="$2"
    command git "${_ss_git_pre_opts[@]}" cat-file -e "${ref}:$path" 2>/dev/null || { printf 'absent'; return; }
    local size; size=$(command git "${_ss_git_pre_opts[@]}" cat-file -s "${ref}:$path" 2>/dev/null || echo 0)
    [ "$size" = "0" ] && { printf 'empty'; return; }
    local nonnul
    nonnul=$(command git "${_ss_git_pre_opts[@]}" cat-file -p "${ref}:$path" 2>/dev/null | LC_ALL=C tr -d '\000' | head -c1 | wc -c | tr -d '[:space:]')
    [ "$nonnul" = "0" ] && printf 'nul' || printf 'content'
}

# Union decision. Prints the finding kind ("empty"/"nul") to flag, else "".
_ss_git_empty_decide() {
    local path="$1" cur="$2" prior="$3"
    case "$cur" in empty|nul) ;; *) printf ''; return ;; esac
    # TRUNCATION first, BEFORE the allowlist: a tracked file that HELD real content and is
    # now void is corruption regardless of path/extension. Checking the allowlist first would
    # let a scratch-dir glob (temp/, logs/, *.log) silently exempt a zeroed real source file.
    [ "$prior" = "content" ] && { printf '%s' "$cur"; return; }
    # NEW void file (absent from HEAD): the path allowlist and the mandatory-extension gate
    # apply here -- this is where intentional empties (.gitkeep, scratch dirs, ...) live.
    _ss_git_empty_path_allowlisted "$path" && { printf ''; return; }
    if [ "$prior" = "absent" ]; then
        _ss_git_empty_mandatory_ext "$path" && { printf '%s' "$cur"; return; }
    fi
    printf ''
}

# ── candidate collectors (mirror the corruption slice's enumeration) ──

_ss_git_empty_collect_add() {
    local tracked_only="$1"; shift
    local -a pathspecs=("$@")
    local path state prior kind
    declare -A seen=()
    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        [ -n "${seen[$path]+x}" ] && continue; seen[$path]=1
        state=$(_ss_git_empty_worktree_state "$path")
        prior=$(_ss_git_empty_blob_state "HEAD" "$path")
        kind=$(_ss_git_empty_decide "$path" "$state" "$prior")
        [ -n "$kind" ] && printf '%s\t%s\n' "$kind" "$path"
    done < <(command git "${_ss_git_pre_opts[@]}" diff --name-only -z --diff-filter=ACMRTUXB -- "${pathspecs[@]}" 2>/dev/null || true)
    $tracked_only && return 0
    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        [ -n "${seen[$path]+x}" ] && continue; seen[$path]=1
        state=$(_ss_git_empty_worktree_state "$path")
        prior=$(_ss_git_empty_blob_state "HEAD" "$path")
        kind=$(_ss_git_empty_decide "$path" "$state" "$prior")
        [ -n "$kind" ] && printf '%s\t%s\n' "$kind" "$path"
    done < <(command git "${_ss_git_pre_opts[@]}" ls-files -z --others --exclude-standard -- "${pathspecs[@]}" 2>/dev/null || true)
}

_ss_git_empty_collect_staged() {
    local path state prior kind
    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        state=$(_ss_git_empty_blob_state "" "$path")
        prior=$(_ss_git_empty_blob_state "HEAD" "$path")
        kind=$(_ss_git_empty_decide "$path" "$state" "$prior")
        [ -n "$kind" ] && printf '%s\t%s\n' "$kind" "$path"
    done < <(command git "${_ss_git_pre_opts[@]}" diff --cached --name-only -z --diff-filter=ACMRT 2>/dev/null || true)
}

_ss_git_empty_collect_worktree_tracked() {
    local path state prior kind
    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        state=$(_ss_git_empty_worktree_state "$path")
        prior=$(_ss_git_empty_blob_state "HEAD" "$path")
        kind=$(_ss_git_empty_decide "$path" "$state" "$prior")
        [ -n "$kind" ] && printf '%s\t%s\n' "$kind" "$path"
    done < <(command git "${_ss_git_pre_opts[@]}" diff --name-only -z --diff-filter=ACMRT 2>/dev/null || true)
}

# ── block diagnostic (agent-facing, English; same urgent stop-and-escalate framing as the
#    byte-corruption block, but for empty/zeroed content) ──

_ss_git_empty_kinds_label() {
    local findings="$1" line kind has_empty=false has_nul=false
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        kind="${line%%$'\t'*}"
        [ "$kind" = "empty" ] && has_empty=true
        [ "$kind" = "nul" ] && has_nul=true
    done <<< "$findings"
    local out=""
    $has_empty && out="0-byte (empty) files"
    if $has_nul; then [ -n "$out" ] && out="$out + "; out="${out}all-NUL files (every byte 0x00)"; fi
    printf '%s' "$out"
}

_ss_git_empty_summary() {
    local findings="$1" line path out=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        path="${line#*$'\t'}"
        [ -n "$out" ] && out+="; $path" || out="$path"
    done <<< "$findings"
    printf '%s' "$out"
}

_ss_block_git_empty() {
    local full="$1" repo_root="$2" findings="$3" context="${4:-commit}"
    local kinds; kinds=$(_ss_git_empty_kinds_label "$findings"); [ -n "$kinds" ] || kinds="empty/zeroed files"

    _ss_git_block_header "Empty/Zeroed File Protection" "$full" "$repo_root"
    echo "  Reason:         Content-free file(s) would enter Git: ${kinds}." >&2
    echo "                  A source/config file that is 0 bytes or all-NUL is almost always" >&2
    echo "                  truncation/crash corruption (a class the byte scanner skips)." >&2
    echo "                  Committed empty code silently breaks builds/imports for everyone." >&2
    _ss_block_rule
    echo "  Affected paths:" >&2
    local line path kind shown=0 total=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        total=$((total + 1))
        if [ "$shown" -lt 10 ]; then
            kind="${line%%$'\t'*}"; path="${line#*$'\t'}"
            echo "    - $path  [$kind]" >&2
            shown=$((shown + 1))
        fi
    done <<< "$findings"
    [ "$total" -gt 10 ] && echo "    - ... and $((total - 10)) more" >&2
    _ss_block_rule
    echo "  ====================================================================" >&2
    echo "   AGENT - VERIFY, DO NOT WAVE THROUGH" >&2
    echo "  ====================================================================" >&2
    echo "   An empty/zeroed file is SUSPECT. Before doing anything else:" >&2
    echo "     1. STOP. Do not commit/add this as-is and do not 'fix' it blindly." >&2
    echo "     2. Confirm the emptiness is INTENDED. Inspect:" >&2
    echo '          git show "HEAD:<path>" | wc -c     # did it have content before?' >&2
    echo '          od -An -tx1 "<path>" | head         # all 00 = crash-zeroed' >&2
    echo "     3. If a script/tool YOU ran emptied it, ABORT that tool; do not rerun it." >&2
    echo "     4. If this is corruption: STOP the active goal AND any scheduled task/loop" >&2
    echo "        (do not reschedule/re-arm), restore the file, and inform the user NOW." >&2
    echo "        Restore a truncated file from its last good version:" >&2
    echo '          git checkout HEAD -- "<path>"            (or <good-commit>~1)' >&2
    _ss_block_rule
    echo "  Manual release - requires EXPLICIT USER CONFIRMATION (do not self-bypass):" >&2
    echo "  (a) If this empty file is legitimately intended, add its path to the allowlist:" >&2
    echo "          ~/.shell-secure/empty-file-allowlist   (one path/glob per line)" >&2
    echo "      (built-in legit-empties like .gitkeep, __init__.py, py.typed are already allowed)" >&2
    echo "  (b) One-shot bypass for this single command:" >&2
    echo "          SHELL_SECURE_EMPTY_FILE_FORCE=1 git ..." >&2
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | empty-file($context:${kinds}) | $(_ss_git_empty_summary "$findings")"
    return 1
}

_ss_git_empty_allow_or_block() {
    local full="$1" repo_root="$2" findings="$3" context="$4"
    [ -n "$findings" ] || return 0
    if _ss_git_empty_force_requested; then
        echo "  [Shell-Secure] Empty/zeroed-file protection forced via SHELL_SECURE_EMPTY_FILE_FORCE=1: $full" >&2
        _ss_log "FORCED | $full | empty-file | $(_ss_git_empty_summary "$findings")"
        return 0
    fi
    _ss_block_git_empty "$full" "$repo_root" "$findings" "$context"
}

# ── guards (reuse the corruption slice's pathspec extraction) ──

_ss_git_empty_guard_add() {
    command git "${_ss_git_pre_opts[@]}" rev-parse --git-dir >/dev/null 2>&1 || return 0
    _ss_git_corruption_extract_add_pathspecs "$@"
    local -a pathspecs=()
    $_ss_git_corruption_scan_all || pathspecs=("${_ss_git_corruption_pathspecs[@]}")
    local findings
    findings=$(_ss_git_empty_collect_add "$_ss_git_corruption_add_tracked_only" "${pathspecs[@]}")
    [ -n "$findings" ] || return 0
    _ss_git_empty_allow_or_block "${_ss_git_corruption_full:-${_ss_git_command_name:-git} $*}" "$(_ss_git_repo_root_label)" "$findings" "add"
}

_ss_git_empty_guard_commit() {
    command git "${_ss_git_pre_opts[@]}" rev-parse --git-dir >/dev/null 2>&1 || return 0
    _ss_git_corruption_extract_commit_pathspecs "$@"
    local findings="" has_pathspec=false
    $_ss_git_corruption_commit_scan_tracked || [ "${#_ss_git_corruption_commit_pathspecs[@]}" -gt 0 ] && has_pathspec=true

    if ! $has_pathspec || $_ss_git_corruption_commit_include; then
        findings=$(_ss_git_empty_collect_staged)
    fi
    if $has_pathspec; then
        local -a pathspecs=()
        $_ss_git_corruption_commit_scan_tracked || pathspecs=("${_ss_git_corruption_commit_pathspecs[@]}")
        local pf; pf=$(_ss_git_empty_collect_add true "${pathspecs[@]}")
        [ -n "$pf" ] && findings="${findings}${findings:+$'\n'}${pf}"
    elif _ss_git_corruption_commit_stages_worktree "$@"; then
        local wf; wf=$(_ss_git_empty_collect_worktree_tracked)
        [ -n "$wf" ] && findings="${findings}${findings:+$'\n'}${wf}"
    fi
    [ -n "$findings" ] || return 0
    _ss_git_empty_allow_or_block "${_ss_git_corruption_full:-${_ss_git_command_name:-git} $*}" "$(_ss_git_repo_root_label)" "$findings" "commit"
}

_ss_git_empty_guard_push() {
    command git "${_ss_git_pre_opts[@]}" rev-parse --git-dir >/dev/null 2>&1 || return 0
    command git "${_ss_git_pre_opts[@]}" rev-parse --verify HEAD >/dev/null 2>&1 || return 0
    local empty_tree="4b825dc642cb6eb9a060e54bf8d69288fbee4904" base upstream
    upstream=$(command git "${_ss_git_pre_opts[@]}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
    if [ -n "$upstream" ]; then base="$upstream"
    elif command git "${_ss_git_pre_opts[@]}" rev-parse --verify HEAD~1 >/dev/null 2>&1; then base="HEAD~1"
    else base="$empty_tree"; fi
    local path state prior kind findings=""
    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        state=$(_ss_git_empty_blob_state "HEAD" "$path")
        prior=$(_ss_git_empty_blob_state "$base" "$path")
        kind=$(_ss_git_empty_decide "$path" "$state" "$prior")
        [ -n "$kind" ] && findings="${findings}${findings:+$'\n'}${kind}"$'\t'"${path}"
    done < <(command git "${_ss_git_pre_opts[@]}" diff --name-only -z --diff-filter=ACMRT "${base}..HEAD" -- 2>/dev/null || true)
    [ -n "$findings" ] || return 0
    _ss_git_empty_allow_or_block "${_ss_git_corruption_full:-${_ss_git_command_name:-git} push}" "$(_ss_git_repo_root_label)" "$findings" "push"
}

_ss_git_empty_guard_git_command() {
    local sub="$1"; shift || true
    case "$sub" in
        add)    _ss_git_empty_guard_add "$@" ;;
        commit) _ss_git_empty_guard_commit "$@" ;;
        push)   _ss_git_empty_guard_push "$@" ;;
        *)      return 0 ;;
    esac
}
