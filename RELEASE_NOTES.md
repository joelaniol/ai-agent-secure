# AI Agent Secure v1.1.3

## Fixes

- Updated the GUI PowerShell UTF-8 details to name CP1252/ANSI corruption alongside UTF-16 BOM corruption.
- Clarified the runtime PowerShell block message so blocked writes mention BOM and CP1252/ANSI byte corruption, including mojibake/replacement-character symptoms.
- Kept the PowerShell UTF-8 runtime guard behavior unchanged: unsafe writes still block, explicit UTF-8 writes still pass.

## Verification

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-quality.ps1 -NoColor -BuildGui`
- Isolated runtime repro: `Set-Content` without `-Encoding utf8` blocked, target file not written, and `Set-Content -Encoding utf8` allowed.
- Isolated edge repros: `Set-Content`, `Add-Content`, `Out-File -Encoding ASCII`, `>` redirection, multi-write mismatch, and .NET ASCII writes blocked; CP1252 PHP and UTF-8 BOM files rejected by source-encoding QA.
