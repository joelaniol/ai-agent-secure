# AI Agent Secure v1.1.8

## Features

- Added a **content-hash allowlist** for Git Corruption Protection. Files whose byte content is verified intentional — e.g. a vendored minified library such as `xterm.js` that legitimately embeds control bytes — can be exempted by adding their **SHA256 content digest** (one 64-hex digest per line, `#` for comments) to `~/.shell-secure/corruption-allowlist`. The allowlist applies to `git add`, `git commit`, and the pre-push range scan, and is read only when corruption is actually detected (no cost on clean operations).
- The exemption is **by exact content, not by path or name**: changing a single byte yields a new hash that is no longer covered, so the guard **re-arms automatically**. Unlike a filename whitelist, a previously-vetted file can never silently absorb new corruption. Each accepted entry is audit-logged as `ALLOWLISTED | git-corruption | <path> | sha256=<hash>`, alongside the existing `FORCED` entries.
- **EOL/filter-aware matching:** `git add` hashes the worktree file while `commit`/`push` hash the stored git blob. Under `core.autocrlf` or a `.gitattributes` text filter those byte streams differ, so a blob finding also honors the operator's worktree digest (`sha256sum <path>`) — but only when `git hash-object --path` proves the worktree file is the exact source of the scanned blob (identical OID). A committed blob that diverges from the clean worktree is never exempted, so no false negative is introduced. The block message documents the blob-digest commands for the rare case the worktree has moved on.
- The corruption block message now documents **both** manual-release paths — the one-shot `SHELL_SECURE_CORRUPTION_FORCE=1` and the persistent allowlist — and states that an agent must **stop and obtain explicit user confirmation** before using either; it must not write the allowlist or set the force variable on its own initiative. Enforcement is honor-system plus audit log (the same trust level as the existing force bypass): a shell-write-capable agent technically can still self-bypass, but the allowlist is more granular (per-content, permanently logged) than a blanket force.
- The GUI corruption-protection detail panel now lists the allowlist alongside the one-shot force as a reviewed manual-release path (EN + DE).

## Notes

- The allowlist is **fail-closed**: when `sha256sum` is unavailable, a listed hash can never be confirmed, so the finding still blocks.
- The allowlist lives in a sidecar file rather than `config.conf`, so existing config parsers/writers (core/setup/CLI) and the GUI config round-trip are untouched. The location can be overridden for tests via `SHELL_SECURE_CORRUPTION_ALLOWLIST`.

## Verification

- `protection-git-corruption-selftest.sh` extended: a control-byte file blocks by default, is allowed once its content SHA256 is listed, **re-blocks after a one-byte change**, an unrelated corrupt file still blocks while the list is non-empty, a comment-only list exempts nothing, and distinct scenarios cover the commit staged-blob path, the pre-push (HEAD blob) path, the `core.autocrlf` worktree/blob divergence, and the OID-divergence safety case (a divergent committed corrupt blob is not masked by an allowlisted clean worktree).
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-quality.ps1 -BuildGui` full gate green; GUI rebuilt with embedded-script round-trip OK.
- Isolated end-to-end test against the **built v1.1.8 EXE's embedded scripts** (extracted and sourced in a throwaway HOME): delete/git-destructive/corruption guards all block correctly, and the SHA allowlist allows, re-arms, and audits on add **and** push — 17/17.

---

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
