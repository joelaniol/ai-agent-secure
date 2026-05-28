# Read this file first when changing the PowerShell wrappers.
# Purpose: PowerShell UTF-8 enforcement plus the powershell() wrapper that
#          dispatches between the UTF-8 check and the existing Remove-Item
#          delete check. Covers powershell, PowerShell, *.exe variants, pwsh.
# Scope: relies on protection-core.sh (block helpers, toggle helpers) and
#        protection-tokenize.sh (PS argument tokenizer + Remove-Item helpers).

# ── PowerShell UTF-8 encoding guard ─────────────────────────
# Background: Windows PowerShell 5.1 writes UTF-16 LE BOM by default
# (Out-File, > redirection) or ANSI/codepage-1252 (Set-Content, Add-Content).
# Agents that run "powershell -c \"echo 'foo' > file.txt\"" or "Set-Content file"
# without -Encoding utf8 corrupt source files this way (BOM bytes at the start,
# every ASCII character preceded by 0x00); readers then see apparent machine
# code instead of text. Inline .NET text writes are also blocked unless the
# command line visibly names a UTF-8 encoding.

declare -ag _ss_ps_encoding_values=()

# Collect all "-Encoding <value>" and "-Encoding:<value>" occurrences from
# tokenized PS args in _ss_ps_encoding_values. Values are lower-cased. Match
# only the full flag name "-Encoding" (case-insensitive); the PS prefix
# abbreviation "-Enc" is intentionally NOT recognized so block hints stay clear
# and users use the full name.
_ss_ps_extract_encoding_values() {
    _ss_ps_encoding_values=()
    local i token next_tok n=${#_ss_ps_tokens[@]}
    for ((i = 0; i < n; i++)); do
        token="${_ss_ps_tokens[$i],,}"
        if [[ "$token" =~ ^-encoding: ]]; then
            _ss_ps_encoding_values+=("${token#-encoding:}")
            continue
        fi
        if [ "$token" = "-encoding" ] && [ $((i + 1)) -lt "$n" ]; then
            next_tok="${_ss_ps_tokens[$((i + 1))],,}"
            _ss_ps_encoding_values+=("$next_tok")
        fi
    done
}

# True when the encoding value is safely readable as UTF-8. Accept the UTF-8
# family (with/without BOM) and numeric codepage 65001 (= UTF-8). Everything
# else (ASCII, Unicode/UTF-16, Default, OEM, BigEndianUnicode, UTF7, UTF32,
# byte) is considered unsafe.
_ss_ps_encoding_value_is_utf8() {
    local v="${1,,}"
    v="${v//\"/}"
    v="${v//\'/}"
    case "$v" in
        utf8|utf-8|utf8nobom|utf8bom|65001)
            return 0
            ;;
    esac
    return 1
}

# Heuristic for .NET text writes in PS inline scripts. Static File calls do not
# use PowerShell's "-Encoding" flag, so require a visible UTF-8 encoding object
# or a clearly named UTF-8 variable. WriteAllBytes is intentionally not included
# because it is often used for real binary assets and has no text encoding
# contract.
_ss_ps_token_is_safe_dotnet_utf8_signal() {
    local lower="$1"
    case "$lower" in
        *utf8encoding*|*encoding]::utf8*|*::utf8*)
            return 0
            ;;
        *encoding*utf-8*|*encoding*65001*)
            return 0
            ;;
        *'$utf8nobom'*|*'$utf8bom'*|*'$utf8encoding'*)
            return 0
            ;;
    esac
    return 1
}

_ss_ps_is_command_boundary() {
    case "$1" in
        ";"|"|") return 0 ;;
    esac
    return 1
}

_ss_ps_is_write_cmdlet() {
    case "${1,,}" in
        set-content|add-content|out-file|tee-object|tee) return 0 ;;
    esac
    return 1
}

_ss_ps_write_cmdlet_has_safe_encoding() {
    local start_index="$1"
    local i token next_tok
    local n=${#_ss_ps_tokens[@]}
    for ((i = start_index + 1; i < n; i++)); do
        token="${_ss_ps_tokens[$i],,}"
        _ss_ps_is_command_boundary "$token" && break

        if [[ "$token" =~ ^-encoding: ]]; then
            _ss_ps_encoding_value_is_utf8 "${token#-encoding:}" && return 0
            return 1
        fi

        if [ "$token" = "-encoding" ]; then
            if [ $((i + 1)) -lt "$n" ]; then
                next_tok="${_ss_ps_tokens[$((i + 1))],,}"
                _ss_ps_is_command_boundary "$next_tok" && return 1
                _ss_ps_encoding_value_is_utf8 "$next_tok" && return 0
            fi
            return 1
        fi
    done
    return 1
}

_ss_ps_dotnet_text_write_is_unsafe() {
    local start_index="$1"
    local i token lower
    local n=${#_ss_ps_tokens[@]}
    local has_safe_utf8_encoding=false
    for ((i = 0; i < n; i++)); do
        if [ "$i" -lt "$start_index" ]; then
            continue
        fi
        token="${_ss_ps_tokens[$i]}"
        lower="${token,,}"
        _ss_ps_is_command_boundary "$lower" && break
        _ss_ps_token_is_safe_dotnet_utf8_signal "$lower" && has_safe_utf8_encoding=true
        # Destructive encoding constructors/statics in .NET calls.
        case "$lower" in
            *unicodeencoding*|*asciiencoding*|*utf7encoding*|*utf32encoding*|*bigendianunicode*)
                return 0
                ;;
            *::unicode*|*::ascii*|*::utf7*|*::utf32*|*::default*|*::oem*)
                # [System.Text.Encoding]::Unicode, ::ASCII, ::UTF7, ...
                return 0
                ;;
        esac
    done
    $has_safe_utf8_encoding && return 1
    return 0
}

_ss_ps_token_is_dotnet_text_write() {
    local lower="${1,,}"
    case "$lower" in
        *::writealltext*|*::writealllines*|*::appendalltext*|*::appendalllines*)
            return 0
            ;;
    esac
    return 1
}

_ss_ps_call_uses_unsafe_dotnet_text_write() {
    local i
    local n=${#_ss_ps_tokens[@]}
    for ((i = 0; i < n; i++)); do
        if _ss_ps_token_is_dotnet_text_write "${_ss_ps_tokens[$i]}" &&
            _ss_ps_dotnet_text_write_is_unsafe "$i"; then
            return 0
        fi
    done
    return 1
}

# True when the next token after a ">" is a pure stream-handle target
# (e.g. "&1", "&2") or the $null sink. PowerShell stream redirections like
# "2>&1", "*>&1", "3>&2", "2>$null" merge or discard a stream handle; they
# never write a file, so they must not trigger the UTF-8 encoding guard.
# File redirects always name a non-stream target ("> out.txt", "1> log").
_ss_ps_redirect_is_stream_handle() {
    local next="$1"
    [ "$next" = '$null' ] && return 0
    [[ "$next" =~ ^\&[1-6]$ ]] && return 0
    return 1
}

# True when the tokenized PS command line contains a writing operation that
# would run without UTF-8. Two classes are recognized:
#   1) Write cmdlets without enough "-Encoding utf8" flags.
#   2) ">"/">>" file redirection: unsafe in PS 5.1 because > uses the
#      default encoding and accepts no -Encoding flag. Stream-handle
#      operators ("2>&1", "*>&1", "2>$null") are excluded - they touch no
#      file. The tokenizer splits "2>&1" into "2","|>","&1", so detection
#      runs by looking at the token after ">".
#   3) Inline .NET text writes without a visible safe UTF-8 encoding.
_ss_ps_call_writes_unsafe_encoding() {
    local has_redirect=false
    local i token next_tok
    local n=${#_ss_ps_tokens[@]}
    for ((i = 0; i < n; i++)); do
        token="${_ss_ps_tokens[$i],,}"
        case "$token" in
            set-content|add-content|out-file|tee-object|tee)
                _ss_ps_write_cmdlet_has_safe_encoding "$i" || return 0
                ;;
            ">")
                next_tok=""
                [ $((i + 1)) -lt "$n" ] && next_tok="${_ss_ps_tokens[$((i + 1))],,}"
                if ! _ss_ps_redirect_is_stream_handle "$next_tok"; then
                    has_redirect=true
                fi
                ;;
            ">>")
                # ">>" is always file-append (PS has no ">>&" or ">>$null"
                # idiom in real use), so treat unconditionally as unsafe.
                has_redirect=true
                ;;
        esac
    done

    # Redirection always uses default encoding: unsafe regardless of flags.
    $has_redirect && return 0

    # .NET text writes must visibly name a safe UTF-8 encoding. This catches
    # inline WriteAllText/AppendAllText snippets that would otherwise bypass
    # the cmdlet-specific "-Encoding utf8" requirement.
    if _ss_ps_call_uses_unsafe_dotnet_text_write; then
        return 0
    fi

    return 1
}

_ss_block_ps_encoding() {
    local cmd_name="$1"; shift
    local full="$cmd_name $*"
    local lang
    lang=$(_ss_lang)

    echo "" >&2
    echo "  [Shell-Secure] $(_ss_t block.title)" >&2
    _ss_block_rule
    echo "  $(_ss_t block.label.blocked_by)$(_ss_t block.layer.ps_encoding)" >&2
    echo "  $(_ss_t block.label.command)$full" >&2
    if [ "$lang" = "de" ]; then
        echo "  $(_ss_t block.label.reason)PowerShell schreibt eine Datei ohne explizites UTF-8-Encoding." >&2
        echo "                 Windows PowerShell 5.1 defaultet auf UTF-16 LE BOM (Out-File, >)" >&2
        echo "                 bzw. ANSI/CP-1252 (Set-Content, Add-Content). Quellcode-Dateien" >&2
        echo "                 landen so mit BOM- oder CP1252/ANSI-Bytes im Arbeitsbaum;" >&2
        echo "                 UTF-8-Reader zeigen dann Mojibake oder Ersatzzeichen." >&2
    else
        echo "  $(_ss_t block.label.reason)PowerShell writes a file without explicit UTF-8 encoding." >&2
        echo "                 Windows PowerShell 5.1 defaults to UTF-16 LE BOM (Out-File, >)" >&2
        echo "                 or ANSI/CP-1252 (Set-Content, Add-Content). Source files end up" >&2
        echo "                 with BOM or CP1252/ANSI bytes in the worktree; UTF-8 readers" >&2
        echo "                 then show mojibake or replacement characters." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    if [ "$lang" = "de" ]; then
        echo "    Set-Content -Encoding utf8 -Path file.txt -Value 'content'" >&2
        echo "    'content' | Out-File -Encoding utf8 file.txt" >&2
        echo "    [System.IO.File]::WriteAllText('file.txt', 'content', [System.Text.UTF8Encoding]::new(\$false))" >&2
        echo "    # oder direkt aus Git Bash, das schreibt immer UTF-8:" >&2
        echo "    echo 'content' > file.txt" >&2
    else
        echo "    Set-Content -Encoding utf8 -Path file.txt -Value 'content'" >&2
        echo "    'content' | Out-File -Encoding utf8 file.txt" >&2
        echo "    [System.IO.File]::WriteAllText('file.txt', 'content', [System.Text.UTF8Encoding]::new(\$false))" >&2
        echo "    # or directly from Git Bash, which always writes UTF-8:" >&2
        echo "    echo 'content' > file.txt" >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.tune_threshold)" >&2
    if [ "$lang" = "de" ]; then
        echo "    SHELL_SECURE_PS_ENCODING_PROTECT=false   # falls UTF-16/ANSI bewusst gewollt" >&2
        echo "    -> in ~/.shell-secure/config.conf, Shell neu laden." >&2
    else
        echo "    SHELL_SECURE_PS_ENCODING_PROTECT=false   # if UTF-16/ANSI is genuinely wanted" >&2
        echo "    -> set in ~/.shell-secure/config.conf, then reload the shell." >&2
    fi
    _ss_block_rule
    echo "" >&2
    _ss_log "BLOCKED | $full | ps-encoding | write without explicit UTF-8 encoding"
    return 1
}

# ── powershell wrapper ───────────────────────────────────────

powershell() {
    local full_args="$*"
    local cmd_name="${_ss_powershell_command_name:-powershell}"

    # Two independent layers with separate toggles:
    #   1) Delete protection (Remove-Item -Recurse inside protected areas)
    #   2) UTF-8 protection (Set-Content/Out-File/.NET text writes without UTF-8)
    # Both off -> skip parsing overhead and pass through.
    if ! _ss_delete_protect_enabled && ! _ss_ps_encoding_protect_enabled; then
        command "$cmd_name" "$@"
        return $?
    fi

    _ss_tokenize_powershell_args "$full_args"

    # UTF-8 check first: it applies globally (not bound to protected dirs)
    # because BOM corruption hurts everywhere. The "command powershell ..."
    # bypass remains because "command" never invokes this function.
    if _ss_ps_encoding_protect_enabled && _ss_ps_call_writes_unsafe_encoding; then
        _ss_block_ps_encoding "$cmd_name" "$@"
        return 1
    fi

    if _ss_delete_protect_enabled; then
        local cmd_index
        cmd_index=$(_ss_find_powershell_remove_item_index || true)
        if [ -n "$cmd_index" ] && _ss_powershell_has_recursive_flag "$cmd_index"; then
            local target
            target=$(_ss_extract_powershell_target "$cmd_index" || true)
            target=$(_ss_strip_wrapping_quotes "$target")

            if [ -n "$target" ]; then
                local resolved
                resolved=$(_ss_resolve "$target")
                if _ss_is_protected "$resolved" && ! _ss_is_safe_target "$resolved"; then
                    local reason safer
                    if [ "$(_ss_lang)" = "de" ]; then
                        reason="Rekursives Löschen (PowerShell) in geschütztem Bereich"
                        safer="Erst mit 'Remove-Item -WhatIf' trocken prüfen, oder einzelne Dateien ohne -Recurse löschen; Ordner verschieben mit 'Rename-Item' statt löschen."
                    else
                        reason="Recursive delete (PowerShell) in protected area"
                        safer="Dry-run with 'Remove-Item -WhatIf' first, or remove individual files without -Recurse; move folders with 'Rename-Item' instead of deleting."
                    fi
                    _ss_block "$cmd_name $full_args" "$resolved" "$reason" "$safer"
                    return 1
                fi
            elif _ss_is_protected "$(pwd)"; then
                local reason safer
                if [ "$(_ss_lang)" = "de" ]; then
                    reason="Rekursives Löschen (PowerShell) - Ziel nicht erkannt"
                    safer="LiteralPath explizit angeben statt CWD, oder außerhalb des geschützten Bereichs ausführen."
                else
                    reason="Recursive delete (PowerShell) - target not detected"
                    safer="Pass -LiteralPath explicitly instead of relying on CWD, or run from outside the protected folder."
                fi
                _ss_block "$cmd_name $full_args" "$(pwd)" "$reason" "$safer"
                return 1
            fi
        fi
    fi

    command "$cmd_name" "$@"
}

powershell.exe() { local _ss_powershell_command_name="powershell.exe"; powershell "$@"; }
PowerShell() { local _ss_powershell_command_name="PowerShell"; powershell "$@"; }
Powershell() { local _ss_powershell_command_name="Powershell"; powershell "$@"; }
PowerShell.exe() { local _ss_powershell_command_name="PowerShell.exe"; powershell "$@"; }
Powershell.exe() { local _ss_powershell_command_name="Powershell.exe"; powershell "$@"; }
# PowerShell 7+ goes through the same wrapper so the UTF-8 check also applies
# there. PS7 defaults to UTF-8 (without BOM), but agents that run
# "pwsh -c \"Out-File ... ASCII\"" should still be blocked.
pwsh() { local _ss_powershell_command_name="pwsh"; powershell "$@"; }
pwsh.exe() { local _ss_powershell_command_name="pwsh.exe"; powershell "$@"; }
