# Read this file first when adding/changing localizable strings.
# Purpose: language selection (`_ss_lang`) and key-based string lookup
#          (`_ss_t`) for short shared block labels and TUI/CLI snippets.
#          Long block message bodies dispatch on `_ss_lang()` directly
#          inside their renderer (per-renderer EN/DE bodies); this slice
#          only owns the small reused labels.
# Scope: extending coverage means adding key+text to both _SS_TEXTS_EN
#        and _SS_TEXTS_DE. Missing keys fall back to English; missing
#        in English fall back to the literal key (loud failure for typos).

# Returns "en" (default) or "de" based on the parsed config value.
# Anything other than "de" maps to "en" so future regions can default
# safely to English.
_ss_lang() {
    case "${SHELL_SECURE_LANGUAGE:-en}" in
        de|DE) printf '%s' "de" ;;
        *)     printf '%s' "en" ;;
    esac
}

# Shared short labels used across multiple block renderers, TUI status
# screens, and CLI help. Long multi-line block bodies live with their
# block renderer (per-renderer EN/DE pair) because they need template
# values for cmd/repo/branch interpolation.
# Labels are padded to a fixed width of 16 characters (including the
# trailing colon + spaces) so the value column aligns consistently.
# This matches the column at which the original German block messages
# put their values, so existing log greps and visual scan-line layouts
# stay intact.
declare -gA _SS_TEXTS_EN=(
    [no_repo]="(no repo)"
    [block.title]="BLOCKED"
    [block.label.blocked_by]="Blocked by:     "
    [block.label.command]="Command:        "
    [block.label.target]="Target:         "
    [block.label.repo]="Repo:           "
    [block.label.branch]="Branch:         "
    [block.label.reason]="Reason:         "
    [block.section.better_way]="Better way:"
    [block.section.bypass]="Bypass (only when intended):"
    [block.section.manual_release]="Manual release:"
    [block.section.tune_threshold]="Adjust threshold:"
    [block.layer.delete]="Shell-Secure (Delete Protection)"
    [block.layer.git]="Shell-Secure (Git Protection)"
    [block.layer.git_flood]="Shell-Secure (Git Flood Protection)"
    [block.layer.git_leak]="Shell-Secure (Git Leak Protection)"
    [block.layer.http_api]="Shell-Secure (HTTP API Protection)"
    [block.layer.ps_encoding]="Shell-Secure (PowerShell UTF-8 Protection)"
)

declare -gA _SS_TEXTS_DE=(
    [no_repo]="(kein Repo)"
    [block.title]="BLOCKIERT"
    [block.label.blocked_by]="Blockiert von:  "
    [block.label.command]="Befehl:         "
    [block.label.target]="Ziel:           "
    [block.label.repo]="Repo:           "
    [block.label.branch]="Branch:         "
    [block.label.reason]="Grund:          "
    [block.section.better_way]="Besserer Weg:"
    [block.section.bypass]="Bypass (nur wenn wirklich beabsichtigt):"
    [block.section.manual_release]="Manuelle Freigabe:"
    [block.section.tune_threshold]="Schwellwert anpassen:"
    [block.layer.delete]="Shell-Secure (Delete-Schutz)"
    [block.layer.git]="Shell-Secure (Git-Schutz)"
    [block.layer.git_flood]="Shell-Secure (Git-Flood-Schutz)"
    [block.layer.git_leak]="Shell-Secure (Git-Leak-Schutz)"
    [block.layer.http_api]="Shell-Secure (HTTP-API-Schutz)"
    [block.layer.ps_encoding]="Shell-Secure (PowerShell-UTF-8-Schutz)"
)

# Returns the localized string for $1. Falls back to English if the
# active language has no entry, then to the key literal so missing
# entries are loud rather than silent.
_ss_t() {
    local key="$1"
    if [ "$(_ss_lang)" = "de" ]; then
        if [ -n "${_SS_TEXTS_DE[$key]+x}" ]; then
            printf '%s' "${_SS_TEXTS_DE[$key]}"
            return 0
        fi
    fi
    if [ -n "${_SS_TEXTS_EN[$key]+x}" ]; then
        printf '%s' "${_SS_TEXTS_EN[$key]}"
        return 0
    fi
    printf '%s' "$key"
    return 1
}
