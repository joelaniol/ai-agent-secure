# AI Agent Secure v1.1.2

## Fixes

- Clarified the PowerShell UTF-8 protection docs to cover CP1252/ANSI single-byte corruption, not only UTF-16 BOM output.
- Documented the boundary between live Shell-Secure runtime interception and release-time source-encoding validation.
- Updated the README guidance around PowerShell encoding failures so PHP/web source corruption is easier to recognize and prevent.

## Verification

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\source-encoding-selftest.ps1 -NoColor`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-quality.ps1 -NoColor -BuildGui`
