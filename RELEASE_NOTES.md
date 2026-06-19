# AI Agent Secure v1.1.7

## Features

- Extended Git Corruption Protection beyond CRCRLF: it now also blocks forbidden **control bytes** (`01-08, 0B, 0C, 0E-1F, 7F`; TAB/LF/CR stay allowed, so normal LF and CRLF files pass) in addition to doubled carriage returns (`0D 0D 0A`), on `git add` and `git commit` (staged, `-a`, `--include`, `--only`/pathspec). Control bytes most often appear when a PowerShell backtick-escape decodes into a raw byte (e.g. `` `b ``/`` `a ``/`` `f `` → `08`/`07`/`0C`).
- Added a **pre-push range scan**: `git push` is now checked over its outgoing commit range, catching corruption that was already committed or that entered through a write path which never crossed Bash (an editor/agent file-write tool, or a directly-spawned `powershell` write). Delete pushes and `--dry-run`/`-n` pushes are excluded.
- Reframed the corruption block as an **urgent stop-and-escalate message for coding agents**: it tells the agent to halt all further write/edit/commit work, abort any script it ran, stop the active goal **and** any scheduled task/loop (Codex and Claude Code named explicitly), inspect the affected bytes (`od -An -tx1`), and inform the user immediately — rather than "repairing" via editor/formatter/UTF-8 rewrite.
- Added a **Windows temp delete whitelist**: recursive deletes under `%WINDIR%\Temp` and `%LOCALAPPDATA%\Temp` are allowed even inside protected trees (agent cleanup), with fail-closed handling of parent and look-alike paths. PowerShell `$env:TEMP` / `$env:TMP` delete targets are expanded before the protected-path check.

## Performance

- Replaced the per-file corruption scan (one `perl` plus `git cat-file` spawn per file) with a single batched `perl` scan for worktree files and a single `git cat-file --batch` + `perl` reader for index/push blobs. On Windows/MSYS2, where process creation dominates, this cuts large-operation overhead dramatically while keeping **byte-identical detection**. Measured on a Windows host: `git add` of 200 text files ~26 s → <1 s; pre-push scan of 500 files ~127 s → ~1.3 s. The per-file scanners remain as a fallback when `perl` is unavailable or a path contains a newline.

## Fixes

- Aligned all surfaces (Localization, README, CLI/setup status labels, config-writer comments, `default.conf`) with the broadened corruption scope (control bytes + add/commit/push) so descriptions no longer claim CRCRLF-only.

## Verification

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-quality.ps1 -NoColor -BuildGui` (full gate + GUI build; embedded-script round-trip OK).
- All 15 isolated protection selftests pass.
- `protection-git-corruption-selftest.sh` extended with control-byte block, TAB-allowed, pre-push range block, and clean-push-through cases; `protection-write-audit-selftest.sh` and `protection-source-layout.ps1` updated for the renamed/added scan functions.
- Performance measured before/after with an isolated multi-file benchmark (50/200/500 text files).
