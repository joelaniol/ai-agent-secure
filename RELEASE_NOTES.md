# AI Agent Secure v1.1.1

## Fixes

- Fixed mojibake in agent-facing shell block warnings by keeping Bash runtime diagnostics English/ASCII regardless of the GUI language.
- Clarified GUI and config language text: `SHELL_SECURE_LANGUAGE` controls GUI text, while shell block diagnostics stay agent-safe.
- Fixed git block rendering under `set -e` so optional repo/branch lines cannot abort the warning before the reason, log entry, or popup is emitted.
- Fixed non-interactive Git Leak checks so missing `/dev/tty` fails closed without noisy `/dev/tty` errors before the normal block message.
- Updated CLI self-test detection for the new English runtime block marker.

## Verification

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-quality.ps1 -NoColor -BuildGui`
- `.\test.bat -NoColor`
- Live safe popup probes for delete, git stash, Git Leak, HTTP/API curl, PowerShell UTF-8, cmd rmdir, and Git Flood
