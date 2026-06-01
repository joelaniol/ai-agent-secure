# AI Agent Secure v1.1.6

## Features

- Added Git Corruption Protection for CRCRLF (`0D 0D 0A`) line-ending corruption before `git add` / `git commit`, including staged, `-a`, `--include`, and `--only`/pathspec commit modes.
- Added binary/font/media/database exclusions and a size-limited streaming scan so random binary payload and huge text-like artifacts do not create noisy false positives.
- Added an opt-in local Write Audit for risky `cat`/`tee` redirections via `SHELL_SECURE_WRITE_AUDIT_PROTECT=true`; the Git boundary remains the default fail-closed protection.

## Fixes

- Fixed GUI blocked-log watching so protocol refresh, config reloads, log bursts, and `FORCED`/`ALLOWED` entries no longer suppress or misclassify block notifications.
- Split Git Flood Protection and Git Corruption Protection into focused runtime slices while keeping installer, setup, CLI, and GUI embedding paths aligned.
- Made the quality gate run isolated Bash selftests in parallel with async output draining and per-test timeouts, reducing local runtime from several minutes to roughly two minutes on this host.

## Verification

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-quality.ps1 -NoColor -BuildGui`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-quality.ps1 -NoColor`
- Targeted selftests: `protection-git-corruption-selftest.sh`, `protection-write-audit-selftest.sh`, `protection-source-layout.ps1`, `gui-source-layout.ps1`.
- Manual GUI notification smokes for `git-corruption`, `git-flood`, and `write-corruption` log entries.
