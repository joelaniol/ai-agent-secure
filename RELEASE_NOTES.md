# AI Agent Secure v1.1.5

## Fixes

- Stopped the PowerShell UTF-8 guard from misreading stream-handle operators as file redirects, so `2>&1`, `*>&1`, `2>$null`, `3>&2` and similar handle merges now pass through while true file writes (`> file.txt`, `2> errors.log`) remain blocked.
- Collapsed multi-line PowerShell commands into a single log entry so the GUI protocol view, CLI report, and toast classifier no longer split one blocked operation into many phantom rows; the original line breaks are preserved as visible `↵` separators.
- Hardened the GUI log reader to fold legacy multi-line log records back into one logical entry by detecting the `[YYYY-MM-DD HH:MM:SS]` timestamp prefix, so existing `blocked.log` files render correctly without a manual clear.
- Fixed the build script to read embedded Bash slices and `config/default.conf` as UTF-8 instead of the Windows default CP1252, restoring correct Umlauts in the installed `protection.sh` (German block banners no longer ship as double-encoded Mojibake).
- Strengthened the embedded-script round-trip check with a byte-level identity comparison between source slices on disk and the bytes the installer writes, so future CP1252-vs-UTF-8 regressions fail the build immediately instead of silently shipping garbage to users.

## Verification

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-quality.ps1 -NoColor -BuildGui`
- Isolated runtime repros after fresh GUI install: `2>&1` pipeline allowed (`Get-Process | Select-Object -First 1 2>&1` runs through), `> file.txt` still blocked, `Set-Content` without `-Encoding utf8` still blocked, `rm -rf` in a protected directory still blocked, `Remove-Item -Recurse -Force` on the repo `.git` still blocked.
- Multi-line PowerShell command produces exactly one log line containing `↵` separators (verified with `Write-Host 'a';\nSet-Content file.txt 'x';\nWrite-Host 'b'`); legacy multi-line entries fold back into one entry in the GUI log view.
- Installed `protection.sh` byte-checked: 51 Umlauts preserved (was 0 before due to CP1252 read), 3× `↵` U+21B5 preserved, 0× `â†µ` Mojibake remaining.
- New PS encoding self-test cases (`tests/protection-ps-encoding-selftest.sh`, cases 46–52): stream-merge variants pass, real file writes still blocked, log-writer roundtrip emits exactly one entry per blocked operation.
