# Read this file first when changing the PowerShell wrappers.
# Purpose: PowerShell UTF-8 enforcement plus the powershell() wrapper that
#          dispatches between the UTF-8 check and the existing Remove-Item
#          delete check. Covers powershell, PowerShell, *.exe variants, pwsh.
# Scope: relies on protection-core.sh (block helpers, toggle helpers) and
#        protection-tokenize.sh (PS argument tokenizer + Remove-Item helpers).

# ── PowerShell UTF-8 encoding guard ─────────────────────────
# Hintergrund: Windows PowerShell 5.1 schreibt per Default UTF-16 LE BOM
# (Out-File, > Redirection) bzw. ANSI/Codepage-1252 (Set-Content, Add-Content).
# Agents, die "powershell -c \"echo 'foo' > file.txt\"" oder "Set-Content file"
# ohne -Encoding utf8 absetzen, korrumpieren so Quellcode-Dateien (BOM-Bytes
# am Anfang, jedes ASCII-Zeichen mit 0x00 vorgesetzt) - lesetools sehen
# scheinbar Maschinencode statt Text.

declare -ag _ss_ps_encoding_values=()

# Sammelt alle "-Encoding <wert>"- und "-Encoding:<wert>"-Vorkommen aus den
# tokenisierten PS-Args in _ss_ps_encoding_values. Werte werden lower-cased.
# Wir matchen nur den vollen Flag-Namen "-Encoding" (case-insensitive); die
# PS-Praefix-Verkuerzung "-Enc" wird bewusst NICHT erkannt, damit
# Block-Hinweise klar lesbar bleiben - User soll den vollen Namen nutzen.
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

# True wenn der Encoding-Wert sicher als UTF-8 lesbar ist. Akzeptiert wird
# die UTF-8-Familie (mit/ohne BOM) und der numerische Codepage 65001 (= UTF-8).
# Alles andere (ASCII, Unicode/UTF-16, Default, OEM, BigEndianUnicode, UTF7,
# UTF32, byte) gilt als unsafe.
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

# Heuristik fuer .NET-Write-Methoden in PS-Inline-Skripten:
# [System.IO.File]::WriteAllText / WriteAllLines / WriteAllBytes /
# AppendAllText / AppendAllLines schreiben in .NET Framework per Default
# UTF-8 MIT BOM. Das ist weniger katastrophal als UTF-16-BOM, aber noch
# immer Quelltext-korrumpierend fuer BOM-empfindliche Tools. Wir blocken
# deshalb nur, wenn explizit eine destruktive Encoding-Klasse mitgegeben
# wurde (UnicodeEncoding, ASCIIEncoding, UTF7Encoding, UTF32Encoding,
# BigEndianUnicode, Default). 2-Arg-Form (ohne Encoding) bleibt erlaubt,
# weil der .NET-Default UTF-8 (mit BOM) ist - das deckt der Block-Hint
# verbal mit ab.
_ss_ps_call_uses_destructive_dotnet_write() {
    local i token lower
    local n=${#_ss_ps_tokens[@]}
    local has_dotnet_write=false
    local has_destructive_encoding=false
    for ((i = 0; i < n; i++)); do
        token="${_ss_ps_tokens[$i]}"
        lower="${token,,}"
        # .NET Method Detection: [System.IO.File]::WriteAllText etc.
        # PS-Tokenizer behandelt das als ein Token. Substring-Match reicht.
        case "$lower" in
            *writealltext*|*writealllines*|*writeallbytes*|*appendalltext*|*appendalllines*)
                has_dotnet_write=true
                ;;
        esac
        # Destruktive Encoding-Konstruktoren / Statics in .NET-Aufrufen.
        case "$lower" in
            *unicodeencoding*|*asciiencoding*|*utf7encoding*|*utf32encoding*|*bigendianunicode*)
                has_destructive_encoding=true
                ;;
            *::unicode*|*::ascii*|*::utf7*|*::utf32*|*::default*|*::oem*)
                # [System.Text.Encoding]::Unicode, ::ASCII, ::UTF7, ...
                has_destructive_encoding=true
                ;;
        esac
    done
    $has_dotnet_write && $has_destructive_encoding && return 0
    return 1
}

# True wenn die tokenisierte PS-Befehlszeile eine schreibende Operation
# enthaelt, die ohne UTF-8 ausgefuehrt wuerde. Zwei Klassen werden erkannt:
#   1) Schreib-Cmdlets ohne ausreichend "-Encoding utf8"-Flags.
#   2) ">"/">>"-Redirection - immer unsafe in PS 5.1, da > die Default-
#      Encoding nutzt und kein -Encoding-Flag annimmt.
_ss_ps_call_writes_unsafe_encoding() {
    local has_redirect=false
    local write_count=0
    local i token
    local n=${#_ss_ps_tokens[@]}
    for ((i = 0; i < n; i++)); do
        token="${_ss_ps_tokens[$i],,}"
        case "$token" in
            set-content|add-content|out-file|tee-object|tee)
                write_count=$((write_count + 1))
                ;;
            ">"|">>")
                has_redirect=true
                ;;
        esac
    done

    # Redirection nutzt immer Default-Encoding -> unsafe, egal welche Flags da sind.
    $has_redirect && return 0

    # .NET-Write mit explizit destruktiver Encoding-Klasse (UnicodeEncoding,
    # ASCIIEncoding, etc.) -> blocken. Ohne explizite Encoding-Klasse laeuft
    # die 2-Arg-Form weiter, weil der .NET-Default UTF-8 (mit BOM) ist.
    if _ss_ps_call_uses_destructive_dotnet_write; then
        return 0
    fi

    [ "$write_count" -eq 0 ] && return 1

    _ss_ps_extract_encoding_values

    # Mindestens so viele -Encoding-Werte wie Schreib-Cmdlets noetig, damit
    # jedes Cmdlet sein eigenes Flag haben koennte. Bei Mismatch konservativ
    # blocken statt zu raten welches Cmdlet welches Flag bekommt.
    [ ${#_ss_ps_encoding_values[@]} -lt "$write_count" ] && return 0

    local v
    for v in "${_ss_ps_encoding_values[@]}"; do
        _ss_ps_encoding_value_is_utf8 "$v" || return 0
    done

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
        echo "  $(_ss_t block.label.reason)PowerShell schreibt eine Datei ohne -Encoding utf8." >&2
        echo "                 Windows PowerShell 5.1 defaultet auf UTF-16 LE BOM (Out-File, >)" >&2
        echo "                 bzw. ANSI/CP-1252 (Set-Content, Add-Content). Quellcode-Dateien" >&2
        echo "                 werden so mit BOM-Bytes verseucht und sehen wie Maschinencode aus," >&2
        echo "                 sobald sie ein anderes Tool als UTF-8 oeffnet." >&2
    else
        echo "  $(_ss_t block.label.reason)PowerShell writes a file without -Encoding utf8." >&2
        echo "                 Windows PowerShell 5.1 defaults to UTF-16 LE BOM (Out-File, >)" >&2
        echo "                 or ANSI/CP-1252 (Set-Content, Add-Content). Source files end up" >&2
        echo "                 polluted with BOM bytes and look like binary garbage to anything" >&2
        echo "                 that opens them as UTF-8." >&2
    fi
    _ss_block_rule
    echo "  $(_ss_t block.section.better_way)" >&2
    if [ "$lang" = "de" ]; then
        echo "    Set-Content -Encoding utf8 -Path file.txt -Value 'content'" >&2
        echo "    'content' | Out-File -Encoding utf8 file.txt" >&2
        echo "    # oder direkt aus Git Bash, das schreibt immer UTF-8:" >&2
        echo "    echo 'content' > file.txt" >&2
    else
        echo "    Set-Content -Encoding utf8 -Path file.txt -Value 'content'" >&2
        echo "    'content' | Out-File -Encoding utf8 file.txt" >&2
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
    _ss_log "BLOCKED | $full | ps-encoding | write without -Encoding utf8"
    return 1
}

# ── powershell wrapper ───────────────────────────────────────

powershell() {
    local full_args="$*"
    local cmd_name="${_ss_powershell_command_name:-powershell}"

    # Zwei unabhaengige Layer mit eigenen Toggles:
    #   1) Delete-Schutz   (Remove-Item -Recurse in geschuetztem Bereich)
    #   2) UTF-8-Schutz    (Set-Content/Out-File/> ohne -Encoding utf8)
    # Beide aus -> Parsing-Aufwand sparen und durchreichen.
    if ! _ss_delete_protect_enabled && ! _ss_ps_encoding_protect_enabled; then
        command "$cmd_name" "$@"
        return $?
    fi

    _ss_tokenize_powershell_args "$full_args"

    # UTF-8-Check zuerst: greift global (nicht protected-dirs-gebunden), weil
    # BOM-Korruption ueberall schmerzt. Bypass via "command powershell ..."
    # bleibt erhalten, weil "command" diese Funktion gar nicht erst aufruft.
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
                        reason="Rekursives Loeschen (PowerShell) in geschuetztem Bereich"
                        safer="Erst mit 'Remove-Item -WhatIf' trocken pruefen, oder einzelne Dateien ohne -Recurse loeschen; Ordner verschieben mit 'Rename-Item' statt loeschen."
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
                    reason="Rekursives Loeschen (PowerShell) - Ziel nicht erkannt"
                    safer="LiteralPath explizit angeben statt CWD, oder ausserhalb des geschuetzten Bereichs ausfuehren."
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
# PowerShell 7+ wird ueber denselben Wrapper geschickt, damit der UTF-8-Check
# auch dort greift. PS7 defaultet zwar selbst auf UTF-8 (ohne BOM), aber
# Agents, die "pwsh -c \"Out-File ... ASCII\"" absetzen, sollen weiter blocken.
pwsh() { local _ss_powershell_command_name="pwsh"; powershell "$@"; }
pwsh.exe() { local _ss_powershell_command_name="pwsh.exe"; powershell "$@"; }
