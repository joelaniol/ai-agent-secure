# AI Agent Secure v1.1.10

## Security

- **Closed an `env` protection bypass.** The `env()` wrapper exists specifically to catch `env [VAR=val ...] <tool> ...` spellings that try to route around the protected wrappers, but it only covered `git` and `curl`. `rm`, `cmd`/`cmd.exe` and `powershell`/`pwsh` fell through to the real binaries, so `env rm -rf <protected-path>` deleted a protected directory from a loaded Bash session **without a block and without a log entry** (and `env powershell ... Remove-Item -Recurse` bypassed the PowerShell wrapper the same way). Unlike the documented `command rm ...` escape hatch, this was an unintended gap in the very layer meant to catch such routing. The wrapper now also routes `rm`, `cmd`/`cmd.exe` and `powershell`/`powershell.exe`/`pwsh`/`pwsh.exe` through their guards; matching is done against the already-lower-cased command so every spelling variant (`RM`, `Powershell.exe`, ...) is covered while the original spelling is preserved for block diagnostics.

## Fixes

- **Whitelist entries can now be removed.** `SHELL_SECURE_SAFE_TARGETS` was add-only in both entry points, yet a stray safe-target entry lifts protection for that basename (a direct protection bypass) and could previously only be corrected by hand-editing the config. Added the CLI command `unwhitelist <name>` (case-insensitive) and a `[d] remove name` action in the setup TUI, mirroring the protected-directory remove flow.
- **Setup uninstall no longer aborts in a half-state.** The setup uninstaller called `powershell -c` without `|| true`/`-NoProfile`; under `set -euo pipefail` a failing `powershell` (not on PATH, broken profile) aborted the whole uninstall before `~/.shell-secure/` was removed. Aligned with the robust CLI form.
- **Portable log path preserved on CLI config rewrites.** The CLI config parser initialized the `SHELL_SECURE_LOG` default as an already-expanded absolute path instead of the portable `$HOME` placeholder; a rewrite of a config missing that line would bake in an absolute path. Aligned with the setup parser so the placeholder round-trips.
- **Atomic, leak-free config writes.** Both `cfg_write` implementations used `mktemp` → `cp` → `rm`; a failed `cp` under `set -e` left the temp file (containing every protected path) behind in `TMPDIR` and could leave a half-written config. They now use a cleanup `trap` plus an atomic `mv`.
- **GUI build no longer emits a UTF-8 BOM** for the generated `EmbeddedScripts.cs` (Windows PowerShell `Set-Content -Encoding UTF8` adds one); switched to a BOM-free `WriteAllText`.
- **Installer uninstall hardening.** The `.bashrc` marker-block removal now keeps a terminating newline, and the `~/.shell-secure/` removal checks for a reparse point first and deletes only the link (never the target contents) if the directory was replaced by a symlink/junction — fitting for a tool whose purpose is guarding against unintended recursive deletes.

## Verification

- New `tests/protection-env-selftest.sh` (registered in the gate): `env rm -rf` and `env FOO=bar rm -rf` on a protected tree block, uppercase `env RM` blocks, `env rm <single loose file>` stays allowed, and `env powershell ... Remove-Item -Recurse` is routed through the wrapper. `tests/cli-config-selftest.sh` extended with an `unwhitelist` round-trip.
- `run-quality.ps1 -BuildGui` full gate green (`Quality test OK.`, `Embedded-Script-Checks: OK`); GUI rebuilt with embedded-script round-trip OK.

---

# AI Agent Secure v1.1.9

## Features

- Added **Empty / Zeroed File Protection** — a new independent layer (toggle `SHELL_SECURE_EMPTY_FILE_PROTECT`, own GUI toggle row, default on) that blocks **0-byte** and **all-NUL** files (every byte `0x00`, size > 0) from entering Git on `git add`, `git commit`, and the pre-push range scan. This is exactly the truncation/crash-corruption class the byte scanner deliberately skips (it ignores NUL/empty to avoid UTF-16 false positives), so a source/config file silently zeroed by a crash or a buggy tool — the PHPMailer-style "0-byte committed for weeks" incident — is now caught before it ships.
- **Union detection policy:** a tracked file whose committed blob had real content but is now empty/NUL is flagged as **truncation** regardless of extension; a **new** empty/NUL file is flagged only when it has a content-mandatory extension (`.php/.js/.ts/.json/.css/.html/.sql/.py/...`). A file that was already empty before stays unflagged (no regression noise).
- **Agent-facing block** in the same urgent stop-and-escalate spirit: it tells the agent the emptiness is suspect, to verify intent (`git show HEAD:<path> | wc -c`, `od -An -tx1`), and — if it is corruption — to halt the goal and any scheduled task/loop, restore the file (`git checkout HEAD -- <path>`), and inform the user.
- **Path allowlist (not SHA):** empty files are not content-distinguishable (every 0-byte file shares one hash), so the exemption is path-based. Built-in legit-empties are always allowed (`.gitkeep`, `.keep`, `__init__.py`, `py.typed`, `.nojekyll`, `gc.properties`, `temp/`, `logs/`); extend with `~/.shell-secure/empty-file-allowlist` (one path/glob per line) or a reviewed one-shot `SHELL_SECURE_EMPTY_FILE_FORCE=1`.

## Notes

- Lives in its own slice `lib/protection-git-empty.sh`; the GUI embeds it like the other guards. Localization was split (German strings moved to `Localization.De.cs` as a `partial class Loc`) to stay within the 500-line GUI source limit.

## Verification

- New `tests/protection-git-empty-selftest.sh` (in the gate): 0-byte + all-NUL block, legit empties/non-mandatory extensions allowed, truncation on add and `commit -a`, pre-existing empty not re-flagged, pre-push range block, sidecar-glob allow, force + audit, toggle-off pass-through.
- `run-quality.ps1 -BuildGui` full gate green; GUI rebuilt with embedded-script round-trip OK. Isolated end-to-end battery against the built EXE's embedded scripts also green.

---

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
