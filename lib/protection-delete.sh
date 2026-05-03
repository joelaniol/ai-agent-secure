# Read this file first when changing rm / cmd recursive-delete protection.
# Purpose: rm and cmd /c "rmdir /s" wrappers that block recursive deletes
#          inside SHELL_SECURE_PROTECTED_DIRS. The PowerShell delete check
#          lives in protection-ps.sh because it shares its wrapper with the
#          UTF-8 enforcement layer.
# Scope: relies on protection-core.sh helpers (_ss_resolve, _ss_is_protected,
#        _ss_is_safe_target, _ss_block, _ss_delete_protect_enabled) and on
#        _ss_strip_wrapping_quotes from protection-core.sh.

# ── rm wrapper ───────────────────────────────────────────────

rm() {
    local arg
    local end_of_options=false
    local -a targets=()

    if ! _ss_delete_protect_enabled; then
        command rm "$@"
        return $?
    fi

    if _ss_has_recursive_flag "$@"; then
        for arg in "$@"; do
            if ! $end_of_options; then
                case "$arg" in
                    --)
                        end_of_options=true
                        continue
                        ;;
                    -*)
                        continue
                        ;;
                esac
            fi
            targets+=("$arg")
        done

        if [ ${#targets[@]} -gt 0 ]; then
            for arg in "${targets[@]}"; do
                local resolved
                resolved=$(_ss_resolve "$arg")
                if _ss_is_protected "$resolved" && ! _ss_is_safe_target "$resolved"; then
                    local reason safer
                    if [ "$(_ss_lang)" = "de" ]; then
                        reason="Rekursives Löschen in geschütztem Bereich"
                        safer="Gezielt einzelne Dateien ohne -rf löschen, oder Ordner erst umbenennen: mv \"$resolved\" \"$resolved.old\" - dann später manuell prüfen und entfernen."
                    else
                        reason="Recursive delete in protected area"
                        safer="Delete individual files without -rf, or rename the folder first: mv \"$resolved\" \"$resolved.old\" - then review and remove manually later."
                    fi
                    _ss_block "rm $*" "$resolved" "$reason" "$safer"
                    return 1
                fi
            done
        fi
    fi

    command rm "$@"
}

# ── cmd wrapper (catches: cmd /c "rmdir /s /q path") ────────

cmd() {
    local full_args="$*"
    local full_lower="${full_args,,}"

    if ! _ss_delete_protect_enabled; then
        command cmd "$@"
        return $?
    fi

    if [[ "$full_lower" =~ (rmdir|rd)[[:space:]] ]] && [[ "$full_lower" =~ /s([[:space:]]|$|\") ]]; then
        local target
        target=$(echo "$full_args" | \
            sed -E 's/.*\b[Rr]([Mm][Dd][Ii][Rr]|[Dd])\b//' | \
            sed -E 's|/[sS]||g; s|/[qQ]||g' | \
            sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        target=$(_ss_strip_wrapping_quotes "$target")

        if [ -n "$target" ]; then
            local resolved
            resolved=$(_ss_resolve "$target")
            if _ss_is_protected "$resolved" && ! _ss_is_safe_target "$resolved"; then
                local reason safer
                if [ "$(_ss_lang)" = "de" ]; then
                    reason="rmdir /s in geschütztem Bereich"
                    safer="Aus Git Bash mit 'rm <datei>' gezielt entfernen (ohne -rf), oder den Ordner verschieben: mv \"$resolved\" \"$resolved.old\"."
                else
                    reason="rmdir /s in protected area"
                    safer="Delete individual files from Git Bash with 'rm <file>' (without -rf), or move the folder: mv \"$resolved\" \"$resolved.old\"."
                fi
                _ss_block "cmd $full_args" "$resolved" "$reason" "$safer"
                return 1
            fi
        elif _ss_is_protected "$(pwd)"; then
            local reason safer
            if [ "$(_ss_lang)" = "de" ]; then
                reason="rmdir /s - Ziel nicht erkannt, CWD ist geschützt"
                safer="Zielpfad explizit angeben (kein CWD-Löschen), oder vorher in ein ungeschütztes Verzeichnis wechseln."
            else
                reason="rmdir /s - target not detected, CWD is protected"
                safer="Pass the target path explicitly (do not delete CWD), or change to an unprotected area first."
            fi
            _ss_block "cmd $full_args" "$(pwd)" "$reason" "$safer"
            return 1
        fi
    fi

    command cmd "$@"
}

cmd.exe() { cmd "$@"; }
