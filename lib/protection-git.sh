# Read this file first when changing git destructive guards or the flood limiter.
# Purpose: all git wrappers - destructive guards, network-call flood limiter,
#          and dispatch into protection-git-leak.sh for push leak checks.
# Scope: relies on protection-core.sh helpers and protection-git-leak.sh for
#        push leak detection.

# ── git stash wrapper ───────────────────────────────────────
# Background: agents often run "git stash" without a clean stash lifecycle and
# bury uncommitted work from parallel sessions. A chained
# "git stash push ; git stash pop" is even more dangerous: when push is blocked,
# pop can still apply an old stash over current work. Therefore only inspection
# commands (list/show/help) and "create" are allowed directly. Mutating or
# unknown stash subcommands require the explicit "command git stash ..." bypass
# or a prior WIP commit.

# Pre-command options are passed through this global array so the dirty check
# for "git -C /path stash" runs in the correct repo (not the CWD). It is filled
# only during a git() invocation; otherwise empty.
declare -ag _ss_git_pre_opts=()

_ss_stash_would_capture() {
    local porcelain
    # Not in a repo -> nothing to stash -> do not block. Pre-opts
    # ("${_ss_git_pre_opts[@]}") ensure -C/--git-dir take effect. On git-internal
    # errors (no HEAD, lock, etc.) return "do not block" conservatively; git
    # stash would fail by itself in those cases.
    command git "${_ss_git_pre_opts[@]}" rev-parse --git-dir >/dev/null 2>&1 || return 1
    porcelain=$(command git "${_ss_git_pre_opts[@]}" status --porcelain 2>/dev/null) || return 1
    [ -z "$porcelain" ] && return 1

    local has_tracked=false has_untracked=false line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "${line:0:2}" in
            "??") has_untracked=true ;;
            *)    has_tracked=true ;;
        esac
    done <<< "$porcelain"

    $has_tracked && return 0

    # Pure untracked files are actually stashed only with -u/-a. It is enough to
    # inspect stash args (after the "stash" token); they arrive here as "$@".
    if $has_untracked; then
        local a
        for a in "$@"; do
            case "$a" in
                -u|-a|--include-untracked|--all) return 0 ;;
            esac
        done
    fi
    return 1
}

_ss_git_repo_available() { command git "${_ss_git_pre_opts[@]}" rev-parse --git-dir >/dev/null 2>&1; }

_ss_git_repo_root_label() {
    local repo_root
    repo_root=$(command git "${_ss_git_pre_opts[@]}" rev-parse --show-toplevel 2>/dev/null)
    [ -z "$repo_root" ] && repo_root="$(_ss_t no_repo)"
    printf '%s' "$repo_root"
}
_ss_git_block_header() {
    local layer="$1" full="$2" repo_root="${3:-}" branch="${4:-}"
    echo "" >&2
    echo "  [Shell-Secure] $(_ss_t block.title)" >&2
    _ss_block_rule
    echo "  $(_ss_t block.label.blocked_by)$layer" >&2
    echo "  $(_ss_t block.label.command)$full" >&2
    [ -z "$repo_root" ] || echo "  $(_ss_t block.label.repo)$repo_root" >&2
    [ -z "$branch" ] || echo "  $(_ss_t block.label.branch)$branch" >&2
}

_ss_git_manual_release() {
    local lang="$1" de_line="$2" en_line="$3"
    # Agents tend to copy remediation text from block output. Do not print the
    # exact "command git ..." escape hatch in Git diagnostics.
    echo "  $(_ss_t block.section.manual_release)" >&2
    if [ "$lang" = "de" ]; then
        echo "    $de_line" >&2
        echo "    Die technische Bypass-Schreibweise steht absichtlich nicht in dieser Meldung." >&2
    else
        echo "    $en_line" >&2
        echo "    The technical bypass form is intentionally omitted from this message." >&2
    fi
}

_ss_block_stash() {
    local full="${_ss_git_command_name:-git} $*"
    local repo_root
    repo_root=$(_ss_git_repo_root_label)
    local lang
    lang=$(_ss_lang)

    _ss_git_block_header "$(_ss_t block.layer.git)" "$full" "$repo_root"
    if [ "$lang" = "de" ]; then
        echo "  $(_ss_t block.label.reason)git stash mit uncommitteten Änderungen im Worktree." >&2
        echo "                 Stashes werden häufig nicht zurück-gepoppt, und" >&2
        echo "                 parallele Sessions verlieren so ihre Arbeit irreversibel." >&2
    else
        echo "  $(_ss_t block.label.reason)git stash with uncommitted changes in the worktree." >&2
        echo "                 Stashes are often never popped back, and parallel" >&2
        echo "                 sessions can silently lose their work irreversibly." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    if [ "$lang" = "de" ]; then
        echo "    git add -A && git commit -m \"WIP: <kurze beschreibung>\"" >&2
        echo "    - Arbeit ist sauber im Reflog, kein Datenverlust möglich." >&2
        echo "    - Später bei Bedarf: 'git reset --soft HEAD~1' zum Aufheben." >&2
    else
        echo "    git add -A && git commit -m \"WIP: <short description>\"" >&2
        echo "    - The work lives safely in the reflog; no data loss." >&2
        echo "    - Later if needed: 'git reset --soft HEAD~1' to unmake it." >&2
    fi
    _ss_block_rule
    _ss_git_manual_release "$lang" \
        "Nur außerhalb von Agent-Läufen und nach sauberem WIP-Commit bewusst ausführen." \
        "Only run outside of agent runs and after a clean WIP commit."
    _ss_block_rule
    echo "" >&2
    # Four-field format analogous to _ss_block so the GUI can parse consistently:
    # BLOCKED | <cmd> | <target> | <reason>
    _ss_log "BLOCKED | $full | $repo_root | $([ "$lang" = "de" ] && printf '%s' "git stash auf dirty worktree" || printf '%s' "git stash on dirty worktree")"
    return 1
}

# ── git reset --hard wrapper ────────────────────────────────
# Background: "git reset --hard" discards tracked worktree changes WITHOUT a
# Reflog entry for the worktree state. Resetting a dirty worktree can lose
# uncommitted work permanently. Untracked files remain, so only tracked lines
# from "git status --porcelain" count as destructive. A clean worktree is not
# blocked because committed history stays reconstructable through Reflog for
# about 90 days.

# True when the given reset arguments contain "--hard". The "--" separator marks
# the start of pathspecs in git; everything after it is no longer a flag and is
# not checked further.
_ss_reset_args_have_hard() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --)     return 1 ;;
            --hard) return 0 ;;
        esac
    done
    return 1
}

_ss_reset_hard_would_destroy() {
    local porcelain
    command git "${_ss_git_pre_opts[@]}" rev-parse --git-dir >/dev/null 2>&1 || return 1
    porcelain=$(command git "${_ss_git_pre_opts[@]}" status --porcelain 2>/dev/null) || return 1
    [ -z "$porcelain" ] && return 1
    # Untracked lines ("??") are not touched by --hard, so do not block. Any
    # other porcelain line means a tracked modification or staged change that
    # would be lost without Reflog safety.
    local line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "${line:0:2}" in
            "??") continue ;;
            *)    return 0 ;;
        esac
    done <<< "$porcelain"
    return 1
}

_ss_block_reset_hard() {
    local full="${_ss_git_command_name:-git} $*"
    local repo_root
    repo_root=$(_ss_git_repo_root_label)
    local lang
    lang=$(_ss_lang)

    _ss_git_block_header "$(_ss_t block.layer.git)" "$full" "$repo_root"
    if [ "$lang" = "de" ]; then
        echo "  $(_ss_t block.label.reason)git reset --hard mit uncommitteten Änderungen im Worktree." >&2
        echo "                 Tracked Modifikationen wären ohne Reflog-Eintrag verloren," >&2
        echo "                 weil --hard den Worktree-Zustand nicht im Reflog sichert." >&2
    else
        echo "  $(_ss_t block.label.reason)git reset --hard with uncommitted changes in the worktree." >&2
        echo "                 Tracked modifications would be lost without a Reflog entry," >&2
        echo "                 because --hard does not snapshot the worktree state." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    if [ "$lang" = "de" ]; then
        echo "    git add -A && git commit -m \"WIP: <kurze beschreibung>\"" >&2
        echo "    - Arbeit ist sauber im Reflog, kein Datenverlust möglich." >&2
        echo "    - Danach 'git reset --hard <commit>' aus sauberem Stand." >&2
    else
        echo "    git add -A && git commit -m \"WIP: <short description>\"" >&2
        echo "    - The work lives safely in the reflog; no data loss." >&2
        echo "    - Then run 'git reset --hard <commit>' from a clean state." >&2
    fi
    _ss_block_rule
    _ss_git_manual_release "$lang" \
        "Nur außerhalb von Agent-Läufen und nach bewusster Prüfung ausführen." \
        "Only run outside of agent runs and after deliberate review."
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | $repo_root | $([ "$lang" = "de" ] && printf '%s' "git reset --hard auf dirty worktree" || printf '%s' "git reset --hard on dirty worktree")"
    return 1
}

# ── git clean wrapper ───────────────────────────────────────
# Background: "git clean -f" permanently deletes untracked files. Untracked
# means "not in history and not in Reflog"; accidental deletion is recoverable
# only from backups. Block only when delete mode is actually active (-f set, no
# -n/--dry-run, and no -i/--interactive) AND "git clean -n" would actually list
# entries. This keeps harmless no-ops and dry-runs free of block noise.

# True when the given clean arguments force an actual delete run. Combined short
# flags ("-fd", "-fdx", "-nf") are evaluated character by character;
# --interactive prompts the user and is therefore considered "safe" here, not
# silently destructive.
_ss_clean_args_destructive() {
    local arg
    local force=false safe=false
    for arg in "$@"; do
        case "$arg" in
            --) break ;;
            --force) force=true ;;
            --dry-run|--interactive) safe=true ;;
            --*) ;;
            -*)
                local rest="${arg#-}" i ch
                for ((i = 0; i < ${#rest}; i++)); do
                    ch="${rest:i:1}"
                    case "$ch" in
                        f) force=true ;;
                        n|i) safe=true ;;
                    esac
                done
                ;;
        esac
    done
    $force && ! $safe && return 0
    return 1
}

_ss_clean_would_destroy() {
    command git "${_ss_git_pre_opts[@]}" rev-parse --git-dir >/dev/null 2>&1 || return 1
    # "git clean -n" with the original flags (-d/-x/-X/-e ...) shows exactly
    # what the real command would delete. Empty output -> nothing to delete ->
    # no block. Redirect stderr to /dev/null so invalid flag combinations are
    # still reported by the real execution as before.
    local out
    out=$(command git "${_ss_git_pre_opts[@]}" clean -n "$@" 2>/dev/null) || return 1
    [ -n "$out" ]
}

_ss_block_clean() {
    local full="${_ss_git_command_name:-git} $*"
    local repo_root
    repo_root=$(_ss_git_repo_root_label)
    local lang
    lang=$(_ss_lang)

    _ss_git_block_header "$(_ss_t block.layer.git)" "$full" "$repo_root"
    if [ "$lang" = "de" ]; then
        echo "  $(_ss_t block.label.reason)git clean würde untracked Dateien dauerhaft löschen." >&2
        echo "                 Untracked Dateien sind weder in der Historie noch im" >&2
        echo "                 Reflog - Wiederherstellung wäre nur über Backups möglich." >&2
    else
        echo "  $(_ss_t block.label.reason)git clean would permanently delete untracked files." >&2
        echo "                 Untracked files are not in history nor in the reflog -" >&2
        echo "                 recovery is only possible from backups." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    if [ "$lang" = "de" ]; then
        echo "    git clean -nfd            # zeigt nur, was gelöscht würde" >&2
        echo "    git status --ignored      # listet untracked und ignored Dateien" >&2
        echo "    Anschließend gezielt einzelne Dateien committen oder per 'rm' entfernen." >&2
    else
        echo "    git clean -nfd            # only show what would be removed" >&2
        echo "    git status --ignored      # list untracked and ignored files" >&2
        echo "    Then commit individual files deliberately, or remove them via 'rm'." >&2
    fi
    _ss_block_rule
    _ss_git_manual_release "$lang" \
        "Nur außerhalb von Agent-Läufen und nach Prüfung mit -nfd ausführen." \
        "Only run outside of agent runs and after reviewing with -nfd."
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | $repo_root | $([ "$lang" = "de" ] && printf '%s' "git clean (force, kein dry-run)" || printf '%s' "git clean (force, no dry-run)")"
    return 1
}

# ── git checkout / switch / restore wrappers ────────────────
# Background: all three subcommands can overwrite worktree content with older
# versions from index/HEAD/tree. The most common silent-overwrite vectors are
# "git checkout -f", "git checkout -- <path>", "git switch --discard-changes",
# and "git restore <path>" (default mode). Block conservatively: tracked
# worktree modification + destructive form -> block. A branch switch without
# -f/--force/--discard-changes lets git abort safely by itself, so do not block.

# Shared helper: true when the worktree has tracked modifications
# (untracked-only "??" lines do not count). This is exactly the condition where
# checkout/switch/restore would silently overwrite.
_ss_worktree_has_tracked_changes() {
    local porcelain
    command git "${_ss_git_pre_opts[@]}" rev-parse --git-dir >/dev/null 2>&1 || return 1
    porcelain=$(command git "${_ss_git_pre_opts[@]}" status --porcelain 2>/dev/null) || return 1
    [ -z "$porcelain" ] && return 1
    local line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "${line:0:2}" in
            "??") continue ;;
            *)    return 0 ;;
        esac
    done <<< "$porcelain"
    return 1
}

# True when checkout args have an unambiguously destructive form: -f/--force,
# "--" pathspec separator, or "." as a positional arg. Pure branch switches
# (git checkout main, -b new, -B existing, --orphan) do not trigger; git refuses
# anyway if dirty modifications collide. Deliberate gap: "git checkout file.txt"
# without "--" is not recognized because branch-vs-pathspec resolution needs
# repo state. Use "git restore" for reliable coverage; it is detected.
_ss_checkout_args_destructive() {
    local arg past_dashdash=false
    for arg in "$@"; do
        if $past_dashdash; then
            return 0
        fi
        case "$arg" in
            --)            past_dashdash=true ;;
            -f|--force)    return 0 ;;
            .)             return 0 ;;
        esac
    done
    return 1
}

# True when switch args have a destructive form: -f/--force/--discard-changes.
# "--merge" lets git preserve conflicts, so it is not silently destructive and
# does not trigger.
_ss_switch_args_destructive() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --)                                 return 1 ;;
            -f|--force|--discard-changes)       return 0 ;;
        esac
    done
    return 1
}

# True when restore modifies the worktree. Default mode is worktree; only
# "--staged" without "--worktree"/"-W" leaves the worktree untouched (pure index
# operation). At least one positional pathspec must be present, otherwise
# restore would fail by itself.
_ss_restore_args_touch_worktree() {
    local arg
    local explicit_staged=false explicit_worktree=false has_pathspec=false past_dashdash=false
    for arg in "$@"; do
        if $past_dashdash; then
            has_pathspec=true
            continue
        fi
        case "$arg" in
            --)                  past_dashdash=true ;;
            -S|--staged)         explicit_staged=true ;;
            -W|--worktree)       explicit_worktree=true ;;
            --source=*) ;;
            --*) ;;
            -*) ;;
            *)                   has_pathspec=true ;;
        esac
    done
    $has_pathspec || return 1
    if $explicit_staged && ! $explicit_worktree; then
        return 1
    fi
    return 0
}

# Generic block for worktree-overwriting subcommands. A shared diagnostic keeps
# the message consistent and avoids three parallel copy-paste versions. The
# subcommand name is passed as the first arg so diagnostics and log entries are
# named correctly.
_ss_block_worktree_overwrite() {
    local subcommand="$1"; shift
    local full="${_ss_git_command_name:-git} $*"
    local repo_root
    repo_root=$(_ss_git_repo_root_label)
    local lang
    lang=$(_ss_lang)

    _ss_git_block_header "$(_ss_t block.layer.git)" "$full" "$repo_root"
    if [ "$lang" = "de" ]; then
        echo "  $(_ss_t block.label.reason)git $subcommand würde tracked Worktree-Änderungen überschreiben." >&2
        echo "                 Diese Änderungen sind nicht im Reflog gesichert - eine" >&2
        echo "                 Wiederherstellung wäre ohne Backup nicht möglich." >&2
    else
        echo "  $(_ss_t block.label.reason)git $subcommand would overwrite tracked worktree changes." >&2
        echo "                 These changes are not stored in the reflog - recovery" >&2
        echo "                 would not be possible without a backup." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    if [ "$lang" = "de" ]; then
        echo "    git status                            # zeigt aktuelle Modifikationen" >&2
        echo "    git add -A && git commit -m \"WIP\"     # sichert die Arbeit im Reflog" >&2
        echo "    Danach $subcommand bewusst aus sauberem Stand ausführen." >&2
    else
        echo "    git status                            # show current modifications" >&2
        echo "    git add -A && git commit -m \"WIP\"     # save the work in the reflog" >&2
        echo "    Then run $subcommand deliberately from a clean state." >&2
    fi
    _ss_block_rule
    _ss_git_manual_release "$lang" \
        "Nur außerhalb von Agent-Läufen und nach 'git status' bewusst ausführen." \
        "Only run outside of agent runs and after reviewing 'git status'."
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | $repo_root | $([ "$lang" = "de" ] && printf '%s' "git $subcommand auf dirty worktree" || printf '%s' "git $subcommand on dirty worktree")"
    return 1
}

# ── git flood wrapper ───────────────────────────────────────
# Background: when an agent spins out it can issue dozens of push/pull/fetch
# calls within seconds. Without a credential helper, each one triggers an auth
# prompt; with a helper, it can create accidental push/pull loops. Limit network
# git calls with token-bucket-like logic: at most N calls in a W-second window,
# persisted through a small state file.

# True when the subcommand usually touches the network and therefore triggers
# the auth pipeline. Only these are counted; "git status" often runs 20x/min in
# agent loops and would otherwise false-positive constantly. "remote update"
# does not count because "git remote -v" needs no network and here we only see
# the subcommand token before "remote ..." arguments.
_ss_git_subcommand_is_network() {
    case "$1" in
        push|pull|fetch|clone|ls-remote)
            return 0
            ;;
    esac
    return 1
}

# Read the rate log file, discard entries outside the window, and decide whether
# there is room for another call. On allow, append and persist the current call;
# on block, leave the counter unchanged (otherwise the next legitimate call
# could be blocked incorrectly as soon as the newly fired entry falls out of the
# window). Return code 0 = allow, 1 = block.
_ss_git_flood_record_and_check() {
    local subcommand="$1"
    local rate_log="$SHELL_SECURE_DIR/git-rate.log"
    local threshold="${SHELL_SECURE_GIT_FLOOD_THRESHOLD:-4}"
    local window="${SHELL_SECURE_GIT_FLOOD_WINDOW:-60}"

    # Sanity: non-numeric / zero / negative values -> hard defaults.
    [[ "$threshold" =~ ^[0-9]+$ ]] || threshold=4
    [[ "$window"    =~ ^[0-9]+$ ]] || window=60
    [ "$threshold" -lt 1 ] && threshold=4
    [ "$window"    -lt 1 ] && window=60

    local now start
    now=$(date +%s)
    start=$((now - window))

    mkdir -p "$SHELL_SECURE_DIR" 2>/dev/null || true

    local kept=""
    local count=0
    if [ -f "$rate_log" ]; then
        local ts rest
        while IFS=' ' read -r ts rest; do
            [[ "$ts" =~ ^[0-9]+$ ]] || continue
            if [ "$ts" -ge "$start" ]; then
                kept+="$ts $rest"$'\n'
                count=$((count + 1))
            fi
        done < "$rate_log"
    fi

    if [ "$count" -ge "$threshold" ]; then
        # Do NOT increment the counter: a blocked call must not become the
        # source of later blocks.
        printf '%s' "$kept" > "$rate_log" 2>/dev/null || true
        return 1
    fi

    kept+="$now $subcommand"$'\n'
    printf '%s' "$kept" > "$rate_log" 2>/dev/null || true
    return 0
}

_ss_block_git_flood() {
    local subcommand="$1"; shift
    local full="${_ss_git_command_name:-git} $*"
    local threshold="${SHELL_SECURE_GIT_FLOOD_THRESHOLD:-4}"
    local window="${SHELL_SECURE_GIT_FLOOD_WINDOW:-60}"
    local lang
    lang=$(_ss_lang)

    _ss_git_block_header "$(_ss_t block.layer.git_flood)" "$full"
    if [ "$lang" = "de" ]; then
        echo "  $(_ss_t block.label.reason)Mehr als $threshold Netzwerk-git-Aufrufe in den letzten ${window}s." >&2
        echo "                 Ein durchdrehender Agent kann sonst Auth-Prompts spammen oder" >&2
        echo "                 versehentliche Push/Pull-Loops triggern." >&2
    else
        echo "  $(_ss_t block.label.reason)More than $threshold network git calls in the last ${window}s." >&2
        echo "                 A runaway agent would otherwise spam the auth prompt or" >&2
        echo "                 trigger unintended push/pull loops." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    if [ "$lang" = "de" ]; then
        echo "    git config --global credential.helper manager   # einmaliges Login statt Spam" >&2
        echo "    Pause einlegen und prüfen, was die Aufrufe verursacht." >&2
    else
        echo "    git config --global credential.helper manager   # one-time login instead of spam" >&2
        echo "    Pause and review what is firing the calls." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.tune_threshold)" >&2
    if [ "$lang" = "de" ]; then
        echo "    SHELL_SECURE_GIT_FLOOD_THRESHOLD=N    (max Calls)" >&2
        echo "    SHELL_SECURE_GIT_FLOOD_WINDOW=Sek     (Fensterlänge)" >&2
        echo "    SHELL_SECURE_GIT_FLOOD_PROTECT=false  (komplett aus)" >&2
        echo "    -> in ~/.shell-secure/config.conf setzen, Shell neu laden." >&2
    else
        echo "    SHELL_SECURE_GIT_FLOOD_THRESHOLD=N    (max calls)" >&2
        echo "    SHELL_SECURE_GIT_FLOOD_WINDOW=secs    (window length)" >&2
        echo "    SHELL_SECURE_GIT_FLOOD_PROTECT=false  (disable entirely)" >&2
        echo "    -> set in ~/.shell-secure/config.conf, then reload the shell." >&2
    fi
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | git-flood | $subcommand: >${threshold} in ${window}s"
    return 1
}

# ── git branch -D wrapper ───────────────────────────────────
# Background: "git branch -D <name>" deletes a branch even when its commits are
# not merged into HEAD. Those commits then live only in Reflog (~90 days by
# default). This silent-orphan path is the risky case. Lowercase "-d" rejects
# unmerged branches by itself and is therefore safe. Block only force delete,
# and only when the branch is actually unmerged into HEAD.

declare -ag _ss_branch_force_delete_targets=()

# Set _ss_branch_force_delete_targets to positional branch names when force
# delete mode is recognized. Recognizes:
#   -D                  (short form, including combos like -Dq or -qD)
#   --delete --force    (long-form combination)
# Return 0 when force mode is recognized, otherwise 1.
_ss_branch_args_extract_force_delete() {
    _ss_branch_force_delete_targets=()
    local arg has_capital_D=false has_long_delete=false has_long_force=false past_dashdash=false
    local -a positionals=()
    for arg in "$@"; do
        if $past_dashdash; then
            positionals+=("$arg")
            continue
        fi
        case "$arg" in
            --)        past_dashdash=true ;;
            --delete)  has_long_delete=true ;;
            --force)   has_long_force=true ;;
            --*) ;;
            -*)
                [[ "$arg" == *D* ]] && has_capital_D=true
                ;;
            *)
                positionals+=("$arg")
                ;;
        esac
    done
    if $has_capital_D || ($has_long_delete && $has_long_force); then
        _ss_branch_force_delete_targets=("${positionals[@]}")
        return 0
    fi
    return 1
}

# True when the given branch exists in the current repo AND is not merged into
# HEAD. Non-existent branches: let git's own error win -> do not block. Repo not
# reachable: conservatively do not block; "git branch -D" would fail by itself.
_ss_branch_target_is_unmerged() {
    local target="$1"
    [ -z "$target" ] && return 1
    command git "${_ss_git_pre_opts[@]}" rev-parse --verify --quiet "refs/heads/$target" >/dev/null 2>&1 || return 1
    local merged
    merged=$(command git "${_ss_git_pre_opts[@]}" branch --merged HEAD 2>/dev/null) || return 1
    # Entries have format "  branch" or "* branch"; an exact line check prevents
    # "feature-x" from prefix-matching "feature-x-y". Dots in branch names are
    # escaped literally.
    local target_re="${target//./\\.}"
    if grep -qE "^[* ]+${target_re}$" <<<"$merged"; then
        return 1
    fi
    return 0
}

_ss_block_branch_force_delete() {
    local target="$1"; shift
    local full="${_ss_git_command_name:-git} $*"
    local repo_root
    repo_root=$(_ss_git_repo_root_label)
    local lang
    lang=$(_ss_lang)

    _ss_git_block_header "$(_ss_t block.layer.git)" "$full" "$repo_root" "$target"
    if [ "$lang" = "de" ]; then
        echo "  $(_ss_t block.label.reason)git branch -D würde nicht gemergte Commits aus '$target' verlieren." >&2
        echo "                 Die Commits leben danach nur noch im Reflog (~90 Tage Default)." >&2
    else
        echo "  $(_ss_t block.label.reason)git branch -D would orphan unmerged commits from '$target'." >&2
        echo "                 The commits would then live only in the reflog (~90 days default)." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    if [ "$lang" = "de" ]; then
        echo "    git log --oneline ${target} --not HEAD     # zeigt was verloren ginge" >&2
        echo "    git branch -d ${target}                    # nur wenn merged -> safe" >&2
        echo "    Falls bewusst entfernen: erst log prüfen, dann -D explizit ausführen." >&2
    else
        echo "    git log --oneline ${target} --not HEAD     # show what would be lost" >&2
        echo "    git branch -d ${target}                    # only if merged -> safe" >&2
        echo "    To delete deliberately: review the log first, then run -D explicitly." >&2
    fi
    _ss_block_rule
    _ss_git_manual_release "$lang" \
        "Nur außerhalb von Agent-Läufen und nach git log Prüfung verwenden." \
        "Only run outside of agent runs and after reviewing the git log."
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | $repo_root | $([ "$lang" = "de" ] && printf '%s' "git branch -D nicht gemerged: $target" || printf '%s' "git branch -D unmerged: $target")"
    return 1
}

_ss_block_stash_mutation() {
    local full="${_ss_git_command_name:-git} $*"
    local repo_root
    repo_root=$(_ss_git_repo_root_label)
    local lang
    lang=$(_ss_lang)

    _ss_git_block_header "$(_ss_t block.layer.git)" "$full" "$repo_root"
    if [ "$lang" = "de" ]; then
        echo "  $(_ss_t block.label.reason)Mutierendes git-stash-Kommando ohne expliziten Bypass." >&2
        echo "                 Stash-Einträge können alte Session-Zustände über" >&2
        echo "                 aktuelle Arbeit legen oder gespeicherte Arbeit entfernen." >&2
    else
        echo "  $(_ss_t block.label.reason)Mutating git-stash command without explicit bypass." >&2
        echo "                 Stash entries can lay old session state over current work" >&2
        echo "                 or remove saved work." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    if [ "$lang" = "de" ]; then
        echo "    git stash list" >&2
        echo "    git stash show --stat stash@{n}" >&2
        echo "    Erst aktuellen Stand committen, dann Stash gezielt prüfen/anwenden." >&2
    else
        echo "    git stash list" >&2
        echo "    git stash show --stat stash@{n}" >&2
        echo "    Commit the current state first, then review/apply the stash deliberately." >&2
    fi
    _ss_block_rule
    _ss_git_manual_release "$lang" \
        "Nur in sauberem Worktree und mit explizitem stash@{n} verwenden." \
        "Only use in a clean worktree and with an explicit stash@{n}."
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | $repo_root | $([ "$lang" = "de" ] && printf '%s' "mutierendes git stash" || printf '%s' "mutating git stash")"
    return 1
}

# Git pre-command options (docs: "git --help" -> OPTIONS).
# Options with a SEPARATE argument (consume "$1" and "$2"):
#   -C <path>, -c <name=value>, --exec-path <path>, --namespace <ref>,
#   --super-prefix <path>, --config-env <env=name>, --work-tree <path>,
#   --git-dir <path>
# Options in = form OR as switches are standalone tokens.
# Any other non-flag argument is the subcommand.
git() {
    # Three independent protection layers with separate toggles:
    #   1) Destructive subcommands (stash/reset/clean/checkout/...) -> GIT_PROTECT
    #   2) Flood/spam of network calls (push/pull/...)              -> GIT_FLOOD_PROTECT
    #   3) Potential secret/agent-file pushes                       -> GIT_LEAK_PROTECT
    # When all are off, pass through without parsing overhead.
    if ! _ss_git_protect_enabled && ! _ss_git_flood_protect_enabled && ! _ss_git_leak_protect_enabled; then
        command git "$@"
        return $?
    fi

    local -a pre_opts=() stash_args=()
    local sub="" skip_next=false seen_sub=false tok
    for tok in "$@"; do
        if $seen_sub; then
            stash_args+=("$tok")
            continue
        fi
        if $skip_next; then
            pre_opts+=("$tok")
            skip_next=false
            continue
        fi
        case "$tok" in
            -C|-c|--exec-path|--namespace|--super-prefix|--config-env|--work-tree|--git-dir)
                pre_opts+=("$tok")
                skip_next=true
                ;;
            -*)
                pre_opts+=("$tok")
                ;;
            *)
                sub="$tok"
                seen_sub=true
                ;;
        esac
    done

    # Flood check runs BEFORE destructive subcommand guards. It is independent
    # from the GIT_PROTECT toggle: a user who disables the destructive layer can
    # keep flood protection active separately (for agent setups where
    # rebase/reset should intentionally stay free).
    if _ss_git_flood_protect_enabled && _ss_git_subcommand_is_network "$sub"; then
        if ! _ss_git_flood_record_and_check "$sub"; then
            _ss_block_git_flood "$sub" "$@"
            return 1
        fi
    fi

    # Push leak detection is independent from the destructive Git layer. A user
    # may disable stash/reset guards while keeping push leak warnings active.
    if _ss_git_leak_protect_enabled && [ "$sub" = "push" ]; then
        _ss_git_pre_opts=("${pre_opts[@]}")
        if ! _ss_git_leak_guard_push "$@"; then
            _ss_git_pre_opts=()
            return 1
        fi
        _ss_git_pre_opts=()
    fi

    # From here on, only destructive subcommand guards remain. If the toggle is
    # off, skip them completely and pass through.
    if ! _ss_git_protect_enabled; then
        command git "$@"
        return $?
    fi

    # "stash_args" is the argument vector after the subcommand token. Use it
    # first for the reset branch, then fall through into existing stash handling.
    if [ "$sub" = "reset" ]; then
        if _ss_reset_args_have_hard "${stash_args[@]}"; then
            _ss_git_pre_opts=("${pre_opts[@]}")
            if _ss_reset_hard_would_destroy; then
                _ss_block_reset_hard "$@"
                _ss_git_pre_opts=()
                return 1
            fi
            _ss_git_pre_opts=()
        fi
        command git "$@"
        return $?
    fi

    if [ "$sub" = "clean" ]; then
        if _ss_clean_args_destructive "${stash_args[@]}"; then
            _ss_git_pre_opts=("${pre_opts[@]}")
            if _ss_clean_would_destroy "${stash_args[@]}"; then
                _ss_block_clean "$@"
                _ss_git_pre_opts=()
                return 1
            fi
            _ss_git_pre_opts=()
        fi
        command git "$@"
        return $?
    fi

    if [ "$sub" = "checkout" ]; then
        if _ss_checkout_args_destructive "${stash_args[@]}"; then
            _ss_git_pre_opts=("${pre_opts[@]}")
            if _ss_worktree_has_tracked_changes; then
                _ss_block_worktree_overwrite "checkout" "$@"
                _ss_git_pre_opts=()
                return 1
            fi
            _ss_git_pre_opts=()
        fi
        command git "$@"
        return $?
    fi

    if [ "$sub" = "switch" ]; then
        if _ss_switch_args_destructive "${stash_args[@]}"; then
            _ss_git_pre_opts=("${pre_opts[@]}")
            if _ss_worktree_has_tracked_changes; then
                _ss_block_worktree_overwrite "switch" "$@"
                _ss_git_pre_opts=()
                return 1
            fi
            _ss_git_pre_opts=()
        fi
        command git "$@"
        return $?
    fi

    if [ "$sub" = "restore" ]; then
        if _ss_restore_args_touch_worktree "${stash_args[@]}"; then
            _ss_git_pre_opts=("${pre_opts[@]}")
            if _ss_worktree_has_tracked_changes; then
                _ss_block_worktree_overwrite "restore" "$@"
                _ss_git_pre_opts=()
                return 1
            fi
            _ss_git_pre_opts=()
        fi
        command git "$@"
        return $?
    fi

    if [ "$sub" = "branch" ]; then
        if _ss_branch_args_extract_force_delete "${stash_args[@]}"; then
            _ss_git_pre_opts=("${pre_opts[@]}")
            local _ss_branch_target
            for _ss_branch_target in "${_ss_branch_force_delete_targets[@]}"; do
                if _ss_branch_target_is_unmerged "$_ss_branch_target"; then
                    _ss_block_branch_force_delete "$_ss_branch_target" "$@"
                    _ss_git_pre_opts=()
                    return 1
                fi
            done
            _ss_git_pre_opts=()
        fi
        command git "$@"
        return $?
    fi

    if [ "$sub" != "stash" ]; then
        command git "$@"
        return $?
    fi

    # Stash subcommand = first non-flag after "stash".
    local stash_sub=""
    local stash_help=false
    for tok in "${stash_args[@]}"; do
        case "$tok" in
            -h|--help) stash_help=true ;;
        esac
        case "$tok" in
            -*) continue ;;
            *)  stash_sub="$tok"; break ;;
        esac
    done

    if $stash_help; then
        command git "$@"
        return $?
    fi

    # Check writing subcommands (bare, push, save) against the worktree.
    # Restore/ref commands (pop/apply/branch/drop/clear/store and unknown ones)
    # are blocked directly; users can intentionally bypass with "command git ...".
    local stash_guard="mutation"
    case "$stash_sub" in
        ""|push|save)      stash_guard="capture"  ;;
        list|show|create)  stash_guard="allow"    ;;
        *)                 stash_guard="mutation" ;;
    esac

    if [ "$stash_guard" = "capture" ]; then
        _ss_git_pre_opts=("${pre_opts[@]}")
        if _ss_stash_would_capture "${stash_args[@]}"; then
            _ss_block_stash "$@"
            _ss_git_pre_opts=()
            return 1
        fi
        _ss_git_pre_opts=()
    fi

    if [ "$stash_guard" = "mutation" ]; then
        _ss_git_pre_opts=("${pre_opts[@]}")
        if _ss_git_repo_available; then
            _ss_block_stash_mutation "$@"
            _ss_git_pre_opts=()
            return 1
        fi
        _ss_git_pre_opts=()
    fi

    command git "$@"
}

Git() { local _ss_git_command_name="Git"; git "$@"; }
git.exe() { local _ss_git_command_name="git.exe"; git "$@"; }
Git.exe() { local _ss_git_command_name="Git.exe"; git "$@"; }
