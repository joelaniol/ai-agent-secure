# Read this file first when changing the git network flood limiter.
# Purpose: rate-limit runaway network git calls before they spam auth prompts
#          or trigger accidental push/pull loops.
# Scope: no git() wrapper; protection-git.sh owns dispatch and calls this slice.

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
