# Read this file first when adding/changing runtime block strings.
# Purpose: agent-safe language selection (`_ss_lang`) and key-based string
#          lookup (`_ss_t`) for short shared block labels.
# Scope: shell runtime diagnostics stay English/ASCII. The GUI keeps its
#        own EN/DE localization in Localization.cs.

# Runtime block diagnostics are consumed by agents and Windows terminal
# bridges that may decode UTF-8 as ANSI/CP1252. Keep shell protection output
# English/ASCII regardless of GUI language; GUI localization is handled in C#.
_ss_lang() {
    printf '%s' "en"
}

# Shared short labels used across multiple block renderers. Long multi-line
# block bodies live with their block renderer because they need template values
# for cmd/repo/branch interpolation.
# Labels are padded to a fixed width of 16 characters (including the
# trailing colon + spaces) so the value column aligns consistently.
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

# Returns the runtime string for $1. Missing entries fall back to the key
# literal so missing entries are loud rather than silent.
_ss_t() {
    local key="$1"
    if [ -n "${_SS_TEXTS_EN[$key]+x}" ]; then
        printf '%s' "${_SS_TEXTS_EN[$key]}"
        return 0
    fi
    printf '%s' "$key"
    return 1
}
