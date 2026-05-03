# Read this file first when changing git destructive guards or the flood limiter.
# Purpose: all git wrappers - stash / reset --hard / clean / checkout / switch /
#          restore / branch -D destructive guards plus the network-call flood
#          limiter. The git() function dispatches between layers based on
#          GIT_PROTECT and GIT_FLOOD_PROTECT toggles.
# Scope: relies on protection-core.sh helpers (block rendering, toggle helpers).

# ── git stash wrapper ───────────────────────────────────────
# Hintergrund: Agents rufen "git stash" oft ohne sauberen Stash-Lifecycle auf
# und begraben dadurch uncommittete Arbeit aus parallelen Sessions. Noch
# gefaehrlicher ist ein verkettetes "git stash push ; git stash pop": wenn push
# blockiert wird, kann pop sonst einen alten Stash ueber aktuelle Arbeit legen.
# Deshalb bleiben nur Inspektionsbefehle (list/show/help) und "create" direkt
# erlaubt. Mutierende oder unbekannte Stash-Subkommandos brauchen den expliziten
# Bypass "command git stash ..." oder vorher einen WIP-Commit.

# Pre-Command-Optionen werden ueber diese globale Array-Variable
# durchgereicht, damit der Dirty-Check fuer "git -C /pfad stash" im
# korrekten Repo laeuft (und nicht im CWD). Nur waehrend eines git()-
# Aufrufs befuellt; sonst leer.
declare -ag _ss_git_pre_opts=()

_ss_stash_would_capture() {
    local porcelain
    # Nicht in einem Repo -> nichts zu stashen -> nicht blocken.
    # Pre-Opts ("${_ss_git_pre_opts[@]}") stellen sicher, dass -C/--git-dir
    # wirken. Bei git-internen Fehlern (kein HEAD, Lock, etc.) kehren wir
    # konservativ mit "nicht blocken" zurueck - git stash wuerde in diesen
    # Faellen ohnehin selbst fehlschlagen.
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

    # Reine Untracked-Dateien werden nur mit -u/-a tatsaechlich gestasht.
    # Es reicht, die Stash-Args (nach dem "stash"-Token) zu untersuchen;
    # die kommen hier als "$@" herein.
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
    [ -n "$repo_root" ] && echo "  $(_ss_t block.label.repo)$repo_root" >&2
    [ -n "$branch" ] && echo "  $(_ss_t block.label.branch)$branch" >&2
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
        echo "  $(_ss_t block.label.reason)git stash mit uncommitteten Aenderungen im Worktree." >&2
        echo "                 Stashes werden haeufig nicht zurueck-gepoppt, und" >&2
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
        echo "    - Arbeit ist sauber im Reflog, kein Datenverlust moeglich." >&2
        echo "    - Spaeter bei Bedarf: 'git reset --soft HEAD~1' zum Aufheben." >&2
    else
        echo "    git add -A && git commit -m \"WIP: <short description>\"" >&2
        echo "    - The work lives safely in the reflog; no data loss." >&2
        echo "    - Later if needed: 'git reset --soft HEAD~1' to unmake it." >&2
    fi
    _ss_block_rule
    _ss_git_manual_release "$lang" \
        "Nur ausserhalb von Agent-Laeufen und nach sauberem WIP-Commit bewusst ausfuehren." \
        "Only run outside of agent runs and after a clean WIP commit."
    _ss_block_rule
    echo "" >&2
    # 4-Feld-Format analog _ss_block, damit die GUI einheitlich parsen kann:
    # BLOCKED | <cmd> | <target> | <reason>
    _ss_log "BLOCKED | $full | $repo_root | $([ "$lang" = "de" ] && printf '%s' "git stash auf dirty worktree" || printf '%s' "git stash on dirty worktree")"
    return 1
}

# ── git reset --hard wrapper ────────────────────────────────
# Hintergrund: "git reset --hard" verwirft tracked Worktree-Aenderungen
# OHNE Reflog-Eintrag fuer den Worktree-Zustand. Wer bei dirty Worktree
# resetet, kann uncommittete Arbeit nicht zurueckholen. Untracked-Dateien
# bleiben erhalten -> nur tracked-Zeilen aus "git status --porcelain"
# gelten als zerstoerend. Clean Worktree wird nicht blockiert, da
# committete Historie ueber Reflog 90 Tage rekonstruierbar bleibt.

# True wenn die uebergebenen reset-Argumente "--hard" enthalten.
# Der "--"-Separator markiert in git den Beginn der Pathspec; alles
# danach ist kein Flag mehr und wird daher nicht weiter geprueft.
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
    # Untracked-Zeilen ("??") wuerden von --hard nicht angefasst, also nicht
    # blocken. Jede andere Porcelain-Zeile bedeutet tracked Modifikation oder
    # staged Aenderung, die ohne Reflog-Sicherheit verloren ginge.
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
        echo "  $(_ss_t block.label.reason)git reset --hard mit uncommitteten Aenderungen im Worktree." >&2
        echo "                 Tracked Modifikationen waeren ohne Reflog-Eintrag verloren," >&2
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
        echo "    - Arbeit ist sauber im Reflog, kein Datenverlust moeglich." >&2
        echo "    - Danach 'git reset --hard <commit>' aus sauberem Stand." >&2
    else
        echo "    git add -A && git commit -m \"WIP: <short description>\"" >&2
        echo "    - The work lives safely in the reflog; no data loss." >&2
        echo "    - Then run 'git reset --hard <commit>' from a clean state." >&2
    fi
    _ss_block_rule
    _ss_git_manual_release "$lang" \
        "Nur ausserhalb von Agent-Laeufen und nach bewusster Pruefung ausfuehren." \
        "Only run outside of agent runs and after deliberate review."
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | $repo_root | $([ "$lang" = "de" ] && printf '%s' "git reset --hard auf dirty worktree" || printf '%s' "git reset --hard on dirty worktree")"
    return 1
}

# ── git clean wrapper ───────────────────────────────────────
# Hintergrund: "git clean -f" loescht untracked Dateien dauerhaft. Untracked
# bedeutet "nicht in der Historie und nicht im Reflog" - eine versehentliche
# Loeschung ist nur ueber Backups rekonstruierbar. Wir blocken nur, wenn
# tatsaechlich Loesch-Modus aktiv ist (-f gesetzt, kein -n/--dry-run und kein
# -i/--interactive) UND ein "git clean -n" tatsaechlich Eintraege auflisten
# wuerde. Dadurch bleiben harmlose No-ops und Dry-Runs ohne Block-Noise.

# True wenn die uebergebenen clean-Argumente einen tatsaechlichen
# Loeschdurchlauf erzwingen. Kombinierte Kurz-Flags ("-fd", "-fdx", "-nf")
# werden Zeichen-fuer-Zeichen ausgewertet; --interactive prompts the user
# und gilt deshalb hier als "safe", nicht als silent-destruktiv.
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
    # "git clean -n" mit den Original-Flags (-d/-x/-X/-e ...) zeigt exakt das,
    # was die Echtversion loeschen wuerde. Leere Ausgabe -> nichts zu loeschen
    # -> kein Block. Wir leiten stderr nach /dev/null, damit ungueltige Flag-
    # Kombinationen sich wie gehabt von der echten Ausfuehrung melden lassen.
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
        echo "  $(_ss_t block.label.reason)git clean wuerde untracked Dateien dauerhaft loeschen." >&2
        echo "                 Untracked Dateien sind weder in der Historie noch im" >&2
        echo "                 Reflog - Wiederherstellung waere nur ueber Backups moeglich." >&2
    else
        echo "  $(_ss_t block.label.reason)git clean would permanently delete untracked files." >&2
        echo "                 Untracked files are not in history nor in the reflog -" >&2
        echo "                 recovery is only possible from backups." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    if [ "$lang" = "de" ]; then
        echo "    git clean -nfd            # zeigt nur, was geloescht wuerde" >&2
        echo "    git status --ignored      # listet untracked und ignored Dateien" >&2
        echo "    Anschliessend gezielt einzelne Dateien committen oder per 'rm' entfernen." >&2
    else
        echo "    git clean -nfd            # only show what would be removed" >&2
        echo "    git status --ignored      # list untracked and ignored files" >&2
        echo "    Then commit individual files deliberately, or remove them via 'rm'." >&2
    fi
    _ss_block_rule
    _ss_git_manual_release "$lang" \
        "Nur ausserhalb von Agent-Laeufen und nach Pruefung mit -nfd ausfuehren." \
        "Only run outside of agent runs and after reviewing with -nfd."
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | $repo_root | $([ "$lang" = "de" ] && printf '%s' "git clean (force, kein dry-run)" || printf '%s' "git clean (force, no dry-run)")"
    return 1
}

# ── git checkout / switch / restore wrappers ────────────────
# Hintergrund: alle drei Subkommandos koennen Worktree-Inhalte mit alten
# Versionen aus Index/HEAD/Tree ueberschreiben. Die haeufigsten silent-
# overwrite-Vektoren sind "git checkout -f", "git checkout -- <path>",
# "git switch --discard-changes" und "git restore <path>" (default-Mode).
# Wir blocken konservativ: tracked Modifikation im Worktree + destruktive
# Form -> Block. Branch-Switch ohne -f/--force/--discard-changes laesst
# Git selbst sicher abbrechen, also nicht blocken.

# Shared helper: True wenn der Worktree tracked Modifikationen hat
# (Untracked-only "??"-Zeilen zaehlen nicht). Genau die Bedingung,
# unter der checkout/switch/restore silent ueberschreiben wuerden.
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

# True wenn checkout-Args eine eindeutig destruktive Form haben:
# -f / --force, "--" Pathspec-Separator, oder "." als positionales Arg.
# Reine Branch-Switches (git checkout main, -b new, -B existing, --orphan)
# triggern nicht; Git refuses ohnehin, falls dirty Modifikationen kollidieren.
# Bewusste Luecke: "git checkout file.txt" ohne "--" wird nicht erkannt,
# weil die Branch-vs-Pathspec-Aufloesung Repo-Zustand braucht. Wer
# zuverlaessigen Schutz will, nutzt "git restore" (wird erfasst).
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

# True wenn switch-Args eine destruktive Form haben:
# -f / --force / --discard-changes. "--merge" laesst Git Konflikte halten,
# ist also nicht silent-destruktiv und triggert nicht.
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

# True wenn restore den Worktree modifiziert. Default-Mode ist Worktree;
# nur "--staged" ohne "--worktree"/"-W" laesst den Worktree unangetastet
# (reine Index-Operation). Mindestens ein positionaler Pathspec muss
# vorhanden sein, sonst wuerde restore ohnehin fehlschlagen.
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

# Generischer Block fuer worktree-ueberschreibende Subkommandos. Eine
# gemeinsame Diagnose haelt die Botschaft konsistent und vermeidet drei
# parallele copy-paste-Versionen. Subkommando-Name wird als erstes Arg
# uebergeben, damit Diagnose und Log-Eintrag korrekt benannt sind.
_ss_block_worktree_overwrite() {
    local subcommand="$1"; shift
    local full="${_ss_git_command_name:-git} $*"
    local repo_root
    repo_root=$(_ss_git_repo_root_label)
    local lang
    lang=$(_ss_lang)

    _ss_git_block_header "$(_ss_t block.layer.git)" "$full" "$repo_root"
    if [ "$lang" = "de" ]; then
        echo "  $(_ss_t block.label.reason)git $subcommand wuerde tracked Worktree-Aenderungen ueberschreiben." >&2
        echo "                 Diese Aenderungen sind nicht im Reflog gesichert - eine" >&2
        echo "                 Wiederherstellung waere ohne Backup nicht moeglich." >&2
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
        echo "    Danach $subcommand bewusst aus sauberem Stand ausfuehren." >&2
    else
        echo "    git status                            # show current modifications" >&2
        echo "    git add -A && git commit -m \"WIP\"     # save the work in the reflog" >&2
        echo "    Then run $subcommand deliberately from a clean state." >&2
    fi
    _ss_block_rule
    _ss_git_manual_release "$lang" \
        "Nur ausserhalb von Agent-Laeufen und nach 'git status' bewusst ausfuehren." \
        "Only run outside of agent runs and after reviewing 'git status'."
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | $repo_root | $([ "$lang" = "de" ] && printf '%s' "git $subcommand auf dirty worktree" || printf '%s' "git $subcommand on dirty worktree")"
    return 1
}

# ── git flood wrapper ───────────────────────────────────────
# Hintergrund: Wenn ein Agent durchdreht, kann er innerhalb weniger Sekunden
# dutzende push/pull/fetch-Aufrufe absetzen. Ohne Credential-Helper triggert
# jeder davon eine Auth-Abfrage (User wird mit Passwort-Prompts ueberflutet),
# mit Helper kann er versehentliche Push/Pull-Loops erzeugen. Wir limitieren
# Netzwerk-git-Calls per Token-Bucket-aehnlicher Logik: maximal N Calls in
# einem Fenster von W Sekunden, persistent ueber eine kleine State-Datei.

# True wenn das Subkommando typischerweise das Netzwerk anfasst und damit
# auch die Auth-Pipeline triggert. Nur diese werden gezaehlt; "git status"
# laeuft im Agent-Loop oft 20x/min und wuerde sonst dauerhaft false-positive.
# "remote update" zaehlt nicht, weil "git remote -v" kein Netz braucht und
# wir hier den Subkommando-Token vor "remote ..."-Argumenten sehen.
_ss_git_subcommand_is_network() {
    case "$1" in
        push|pull|fetch|clone|ls-remote)
            return 0
            ;;
    esac
    return 1
}

# Liest die Rate-Log-Datei, verwirft Eintraege ausserhalb des Fensters,
# und entscheidet ob noch Platz fuer einen weiteren Call ist. Bei
# Erlaubnis wird der aktuelle Call angehaengt und persistiert; bei
# Block bleibt der Counter unveraendert (sonst wuerde der naechste
# legitime Call faelschlich rauspoppen, sobald der jetzt-gefeuerte
# Eintrag aus dem Fenster faellt). Returncode 0 = allow, 1 = block.
_ss_git_flood_record_and_check() {
    local subcommand="$1"
    local rate_log="$SHELL_SECURE_DIR/git-rate.log"
    local threshold="${SHELL_SECURE_GIT_FLOOD_THRESHOLD:-4}"
    local window="${SHELL_SECURE_GIT_FLOOD_WINDOW:-60}"

    # Sanity: nicht-numerische / 0 / negative Werte -> harte Defaults.
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
        # Counter NICHT inkrementieren: der blockierte Call darf nicht
        # spaeter zur Quelle weiterer Blocks werden.
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
        echo "    Pause einlegen und pruefen, was die Aufrufe verursacht." >&2
    else
        echo "    git config --global credential.helper manager   # one-time login instead of spam" >&2
        echo "    Pause and review what is firing the calls." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.tune_threshold)" >&2
    if [ "$lang" = "de" ]; then
        echo "    SHELL_SECURE_GIT_FLOOD_THRESHOLD=N    (max Calls)" >&2
        echo "    SHELL_SECURE_GIT_FLOOD_WINDOW=Sek     (Fensterlaenge)" >&2
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
# Hintergrund: "git branch -D <name>" loescht einen Branch auch dann, wenn
# seine Commits nicht in HEAD eingegangen sind. Die Commits leben dann nur
# noch im Reflog (~90 Tage Default). Genau dieser silent-orphan-Pfad ist
# riskant. "-d" (lowercase) lehnt unmerged Branches selbst ab und ist
# damit safe. Wir blocken nur den Force-Delete-Fall, und auch nur wenn
# der Branch tatsaechlich unmerged in HEAD ist.

declare -ag _ss_branch_force_delete_targets=()

# Setzt _ss_branch_force_delete_targets auf die positionalen Branch-Namen
# wenn ein Force-Delete-Modus erkannt wurde. Erkennt:
#   -D                  (Kurzform, auch in Kombi wie -Dq oder -qD)
#   --delete --force    (Langform-Kombination)
# Gibt 0 zurueck wenn Force-Modus erkannt, sonst 1.
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

# True wenn der angegebene Branch im aktuellen Repo existiert UND nicht
# in HEAD eingegangen ist. Nicht-existente Branches: Git eigene Fehler-
# meldung gewinnt -> nicht blocken. Repo nicht erreichbar: konservativ
# nicht blocken; "git branch -D" wuerde dort ohnehin selbst scheitern.
_ss_branch_target_is_unmerged() {
    local target="$1"
    [ -z "$target" ] && return 1
    command git "${_ss_git_pre_opts[@]}" rev-parse --verify --quiet "refs/heads/$target" >/dev/null 2>&1 || return 1
    local merged
    merged=$(command git "${_ss_git_pre_opts[@]}" branch --merged HEAD 2>/dev/null) || return 1
    # Eintraege haben das Format "  branch" oder "* branch"; eine exakte
    # Zeilen-Pruefung verhindert, dass "feature-x" ein Praefix-Match auf
    # "feature-x-y" produziert. Punkt im Branch-Namen wird literal escaped.
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
        echo "  $(_ss_t block.label.reason)git branch -D wuerde nicht gemergte Commits aus '$target' verlieren." >&2
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
        echo "    Falls bewusst entfernen: erst log pruefen, dann -D explizit ausfuehren." >&2
    else
        echo "    git log --oneline ${target} --not HEAD     # show what would be lost" >&2
        echo "    git branch -d ${target}                    # only if merged -> safe" >&2
        echo "    To delete deliberately: review the log first, then run -D explicitly." >&2
    fi
    _ss_block_rule
    _ss_git_manual_release "$lang" \
        "Nur ausserhalb von Agent-Laeufen und nach git log Pruefung verwenden." \
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
        echo "                 Stash-Eintraege koennen alte Session-Zustaende ueber" >&2
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
        echo "    Erst aktuellen Stand committen, dann Stash gezielt pruefen/anwenden." >&2
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

# Pre-Command-Optionen von Git (Doku: "git --help" -> OPTIONS).
# Optionen mit SEPARATEM Argument (verbrauchen "$1" und "$2"):
#   -C <path>, -c <name=value>, --exec-path <path>, --namespace <ref>,
#   --super-prefix <path>, --config-env <env=name>, --work-tree <path>,
#   --git-dir <path>
# Optionen in =-Form ODER als Schalter sind selbststaendige Tokens.
# Jede andere Nicht-Flag-Argument = Subkommando.
git() {
    # Zwei unabhaengige Schutz-Layer mit eigenen Toggles:
    #   1) Destruktive Subkommandos (stash/reset/clean/checkout/...) -> GIT_PROTECT
    #   2) Flood/Spam von Netzwerk-Calls (push/pull/...)              -> GIT_FLOOD_PROTECT
    # Wenn beide aus sind, fallen wir ohne Parsing-Overhead durch.
    if ! _ss_git_protect_enabled && ! _ss_git_flood_protect_enabled; then
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

    # Flood-Check laeuft VOR den destruktiven Subkommando-Guards. Er ist
    # unabhaengig vom GIT_PROTECT-Toggle: ein Nutzer, der die destruktive
    # Schutzschicht abdreht, kann den Flood-Schutz separat aktiv lassen
    # (z. B. Agent-Setups, in denen rebase/reset bewusst frei sein sollen).
    if _ss_git_flood_protect_enabled && _ss_git_subcommand_is_network "$sub"; then
        if ! _ss_git_flood_record_and_check "$sub"; then
            _ss_block_git_flood "$sub" "$@"
            return 1
        fi
    fi

    # Ab hier nur noch destruktive Subkommando-Guards. Wenn der Toggle
    # aus ist, ueberspringen wir sie komplett und reichen den Call durch.
    if ! _ss_git_protect_enabled; then
        command git "$@"
        return $?
    fi

    # "stash_args" ist der Argumentvektor nach dem Subkommando-Token.
    # Wir nutzen ihn zuerst fuer den reset-Zweig, danach faellt der Code
    # in die bestehende stash-Behandlung.
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

    # Stash-Subkommando = erstes Nicht-Flag nach "stash".
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

    # Schreibende Subkommandos (bare, push, save) gegen Worktree pruefen.
    # Restore-/Ref-Kommandos (pop/apply/branch/drop/clear/store und unbekannte)
    # blocken wir direkt: der Nutzer kann mit "command git ..." bewusst umgehen.
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
