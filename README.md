# AI Agent Secure

<!-- ai-agent-secure-version:start -->
**Current version:** `1.0.4` | Build `20260503.114302` | Built `2026-05-03 11:43:02 UTC`

See [VERSION](VERSION) for the build manifest.
<!-- ai-agent-secure-version:end -->

Shell and Git protection for AI coding agents on Windows (Git Bash / MSYS2) — covers recursive directory deletion, dangerous git operations, runaway git rate-limiting, and PowerShell UTF-8 enforcement.

## Screenshots

<p align="center">
  <img src="screenshots/ai-agent-secure-dashboard.png" alt="AI Agent Secure dashboard" width="900">
</p>

<p align="center">
  <img src="screenshots/ai-agent-secure-protected-areas.png" alt="Protected areas" width="30%">
  <img src="screenshots/ai-agent-secure-settings-git-details.png" alt="Git protection details" width="30%">
  <img src="screenshots/ai-agent-secure-about.png" alt="About page with version and build information" width="30%">
</p>

A `rm -rf` in the wrong directory wipes out years of work. A `git stash` on the wrong worktree silently buries uncommitted changes nobody pops back. A `git reset --hard` on dirty files leaves no Reflog trail. A `powershell Set-Content` without `-Encoding utf8` corrupts source files with UTF-16 BOM. A wedged agent fires `git fetch` four times a second and floods the credential prompt. AI Agent Secure intercepts all of these **before** they do damage.

### Why this exists

AI coding agents (Codex, Claude Code, etc.) routinely execute shell commands on your machine — including recursive deletes and stash operations. A [documented incident on Windows](https://community.openai.com/t/potential-destructive-command-mis-parsing-on-windows-agent-cleanup-via-cmd-c-may-delete-workspace-content-instead-of-target-folder/1376026/2) showed how `cmd /c rmdir` mis-parsing caused an agent to wipe an entire workspace instead of a temporary folder. The `git stash` problem is subtler: agents stash changes, switch branches, and forget to pop — work then sits invisibly in the stash list until the next session overwrites it. AI Agent Secure was built to prevent both classes of accident.

---

## What gets intercepted?

AI Agent Secure runs the **Shell-Secure protection core** with three independent layers, each with its own toggle: `SHELL_SECURE_DELETE_PROTECT`, `SHELL_SECURE_GIT_PROTECT` (plus `SHELL_SECURE_GIT_FLOOD_PROTECT` as a sub-layer), and `SHELL_SECURE_PS_ENCODING_PROTECT`.

### 1. Delete protection

Recursive deletes targeting a configured protected area are blocked across all three attack vectors that work in Git Bash:

| Command | Example | Status |
|---|---|---|
| `rm` | `rm -rf /d/Projects` | Blocked |
| `cmd` / `cmd.exe` | `cmd /c "rmdir /s /q D:\Projects"` | Blocked |
| `powershell` | `powershell Remove-Item D:\Projects -Recurse` | Blocked |

Non-recursive delete commands (`rm file.txt`, `rmdir empty-folder`) and deletes outside protected areas are not affected. Build artefacts on the whitelist (`node_modules`, `dist`, `.cache`, …) stay deletable inside protected trees.

### 2. Git protection

The git layer wraps the operations that most often cause silent uncommitted-work loss in agent-driven workflows.

**`git stash`** — three classes of stash subcommands:

| Subcommand | Behavior |
|---|---|
| `git stash list` / `show` / `create` / `--help` | Always allowed (read-only / no auto-apply) |
| `git stash` / `push` / `save` | Blocked **only** when the worktree is dirty (would actually capture work) |
| `git stash pop` / `apply` / `branch` / `drop` / `clear` / `store` / unknown | Blocked unconditionally inside a repo (mutations on existing stash entries) |

**`git reset --hard`** — blocked **only** when the worktree has uncommitted tracked modifications (the silent-loss case). Untracked-only state, clean worktrees, and non-`--hard` resets (`--soft`, `--mixed`, default, pathspec form) all pass through.

**`git clean -f`** — blocked **only** when force-mode is active (`-f` set, no `-n`/`--dry-run`/`-i`) **and** `git clean -n` reports that something would actually be removed. Dry-runs (`-nfd`, `--dry-run`), interactive mode (`-i`), and clean trees with nothing to remove all pass through. Combined short flags like `-fd`, `-fdx`, `-fdxe pattern` are recognised.

**`git checkout` / `git switch` / `git restore` (worktree-overwriting forms)** — blocked when the targeted repo has tracked uncommitted modifications **and** the command would overwrite the worktree:

| Form | Behavior |
|---|---|
| `git checkout -f` / `--force` | Blocked when worktree is dirty |
| `git checkout -- <pathspec>` (or `git checkout .`) | Blocked when worktree is dirty |
| `git checkout main` / `-b feature` / `-B existing` / `--orphan …` | Always passes (Git refuses on conflict, branch-create is non-destructive) |
| `git switch -f` / `--force` / `--discard-changes` | Blocked when worktree is dirty |
| `git switch main` / `-c new` / `--merge` | Always passes |
| `git restore <pathspec>` (default mode touches worktree) | Blocked when worktree is dirty |
| `git restore --staged --worktree <pathspec>` | Blocked when worktree is dirty |
| `git restore --staged <pathspec>` (index only) | Always passes |

**Known gap:** `git checkout file.txt` without the `--` separator is not detected, because branch-vs-pathspec resolution depends on repo state. Use `git restore file.txt` for unambiguous restore — that path **is** caught.

**`git branch -D <name>`** — blocked **only** when the named branch is unmerged into HEAD (i.e., when `git branch -d` would refuse). Force-delete on an already-merged branch produces the same result as `-d` and passes through. Long form `git branch --delete --force <name>` and combined short flags like `-Dq` are recognised.

**Git Flood Protection** — separate layer that rate-limits *network* git calls (`push`, `pull`, `fetch`, `clone`, `ls-remote`) to catch agents that spin out and hammer the auth pipeline or push/pull loop. Lives behind its own toggle `SHELL_SECURE_GIT_FLOOD_PROTECT` and stays active even when `SHELL_SECURE_GIT_PROTECT=false` (so you can keep flood protection while opting out of the destructive guards). Defaults: max **4 calls per 60 seconds**, configurable via `SHELL_SECURE_GIT_FLOOD_THRESHOLD` and `SHELL_SECURE_GIT_FLOOD_WINDOW`. Non-network subcommands (`status`, `log`, `diff`, `branch -a`, …) are never counted. State lives in `~/.shell-secure/git-rate.log` and entries older than the window are pruned automatically; blocked calls do **not** count toward the bucket so the limiter recovers cleanly.

### 3. PowerShell UTF-8 enforcement

A separate layer (toggle `SHELL_SECURE_PS_ENCODING_PROTECT`, default **on**) catches a different agent failure mode: writing files via PowerShell without `-Encoding utf8`. Windows PowerShell 5.1 defaults to UTF-16 LE BOM (`Out-File`, `>`, `>>`) or ANSI/CP-1252 (`Set-Content`, `Add-Content`), so a careless `powershell -c "Set-Content config.json '{...}'"` corrupts source files with BOM bytes — and the file then looks like binary garbage to anything that expects UTF-8.

Blocked forms:

| Pattern | Behavior |
|---|---|
| `Set-Content`, `Add-Content`, `Out-File`, `Tee-Object` (or `tee`) without `-Encoding utf8` | Blocked |
| `>` and `>>` redirection (PS 5.1 default-encodes, ignores `-Encoding`) | Blocked |
| Same cmdlets with `-Encoding utf8` / `utf-8` / `utf8NoBOM` / `utf8BOM` | Allowed |
| Multiple write cmdlets in one script: encoding count must match write count, all UTF-8 | Allowed only when both conditions hold |
| Read-only cmdlets (`Get-Content`, `cat`, `type`, …) | Always allowed |
| Non-write pipelines (`Get-Process | Select-Object`) | Always allowed |

Coverage: `powershell`, `powershell.exe`, `PowerShell`, `Powershell`, `PowerShell.exe`, `Powershell.exe`, plus PowerShell 7's `pwsh` and `pwsh.exe`. Bypass via `command powershell ...` if you really need ANSI/UTF-16 output for a Windows-native consumer.

Known gap: `[System.IO.File]::WriteAllText("...")` and other inline .NET method calls aren't reliably detectable from a string and are **not** intercepted. Use the cmdlet form (`Set-Content -Encoding utf8 ...`) for guaranteed coverage.

Pre-command options like `git -C /repo stash` and `git --git-dir=… reset --hard` are honoured — the dirty check runs against the targeted repo, not the current directory. Spellings `Git`, `git.exe`, `Git.exe`, and `env … git …` are also covered.

Other git operations (`commit`, `rebase`, …) are **not** intercepted today. The git layer focuses on the asymmetric-risk subcommands where uncommitted work disappears without a Reflog entry to recover from.

## How does it work?

The Shell-Secure core defines shell wrapper functions for `rm`, `cmd`, `cmd.exe`, `powershell`, `powershell.exe`, `git`, `Git`, `git.exe`, `Git.exe`, and `env`. These are loaded at the start of every Bash session via `.bashrc`, and additionally for non-interactive shells via `BASH_ENV`.

### Delete check flow

```
Command intercepted
    │
    ▼
Is the target inside a protected area?
    │
    ├── No  → Command executes normally
    │
    ▼
Is the folder name on the whitelist? (e.g. node_modules, dist)
    │
    ├── Yes → Command executes normally
    │
    ▼
BLOCKED ✗  (logged to file)
```

### Git stash check flow

```
git [pre-opts] stash [args]
    │
    ▼
Stash subcommand classification
    │
    ├── list / show / create / --help → executes normally
    │
    ├── push / save / (no sub)
    │       │
    │       ▼
    │   Is the worktree dirty in the targeted repo?
    │       │
    │       ├── No  → executes normally
    │       └── Yes → BLOCKED ✗ (capture would bury work)
    │
    └── pop / apply / drop / clear / branch / store / unknown
            │
            ▼
        Inside a repo? → BLOCKED ✗ (mutation on stash refs)
```

### Git reset --hard check flow

```
git [pre-opts] reset [args]
    │
    ▼
Do the args contain "--hard" (before "--")?
    │
    ├── No  → executes normally (--soft / --mixed / pathspec)
    │
    ▼
Has the targeted repo tracked modifications in the worktree?
    │
    ├── No  → executes normally (clean tree, untracked-only)
    └── Yes → BLOCKED ✗ (--hard would discard tracked work without a Reflog entry)
```

### Git clean check flow

```
git [pre-opts] clean [args]
    │
    ▼
Force mode? (-f / --force present, AND no -n / --dry-run / -i)
    │
    ├── No  → executes normally (dry-run, interactive, missing -f)
    │
    ▼
Would "git clean -n <args>" actually list any path?
    │
    ├── No  → executes normally (nothing to remove)
    └── Yes → BLOCKED ✗ (untracked deletion has no Reflog recovery)
```

### Path normalization

Paths are normalized before comparison:
- Backslashes → forward slashes (`D:\Projects` → `D:/Projects`)
- Drive letters → MSYS2 format (`D:` → `/d`)
- Case-insensitive matching
- Relative paths and `..` are resolved

## Features

- **Protected areas** — Configure folders, projects, or whole drives
- **Whitelist** — Build artifacts like `node_modules`, `dist`, `.cache` etc. can still be deleted
- **Per-category toggles** — `SHELL_SECURE_DELETE_PROTECT` and `SHELL_SECURE_GIT_PROTECT` can be flipped independently of the master switch
- **Git stash guard** — Blocks captures on dirty worktrees and any mutation on existing stash entries; honours `git -C /path` and `--git-dir`
- **Git reset --hard guard** — Blocks `git reset --hard` only when uncommitted tracked changes would be lost; clean trees and `--soft` / `--mixed` resets pass through
- **Git clean guard** — Blocks `git clean -f` only when something would actually be removed; dry-runs (`-nfd`), interactive (`-i`), and no-op runs pass through
- **Git checkout / switch / restore guard** — Blocks the worktree-overwriting forms (`-f`, `--`, `.`, `--discard-changes`, `restore` default mode) only when tracked changes would be lost; pure branch switches and `restore --staged` always pass through
- **Git branch -D guard** — Blocks `git branch -D <name>` only when the branch is unmerged into HEAD; force-delete on a merged branch passes through, lowercase `-d` is left to git's own safety check
- **Git flood protection** — Rate-limits network git calls (`push`/`pull`/`fetch`/`clone`/`ls-remote`) to catch runaway agents; default 4 per 60 s, separately toggleable via `SHELL_SECURE_GIT_FLOOD_PROTECT`
- **PowerShell UTF-8 enforcement** — Blocks `Set-Content` / `Out-File` / `>` writes that would emit UTF-16 LE BOM or ANSI; covers `powershell`, `pwsh`, and case variants; toggleable via `SHELL_SECURE_PS_ENCODING_PROTECT`
- **Logging** — Every blocked command is logged with a timestamp
- **On/Off** — Disable protection at any time without uninstalling
- **Non-interactive shells** — Also active in scripts and subshells via `BASH_ENV`
- **Bypass** — Intentional deletion is always possible with `command rm -rf ...`; intentional stash is `command git stash ...`

## Installation

### Prerequisites

- Windows 10/11 with .NET Framework 4.8 or newer
- [Git for Windows](https://gitforwindows.org/) (Git Bash)

### GUI (recommended)

Download the Windows ZIP from the [latest release](https://github.com/joelaniol/ai-agent-secure/releases), extract it, and run `shell-secure-gui.exe`. There is no separate app installer. The executable name and CLI stay `shell-secure` for compatibility; the visible product name is AI Agent Secure. Handles setup, configuration, and monitoring in one window with a system tray icon. Uses classic .NET Framework/WPF (4.8-compatible), which is serviced with Windows.

### Alternative: Interactive setup TUI

```bash
bash setup.sh
```

Opens a terminal menu with options for installation, configuration, and status.

### Alternative: CLI

```bash
bash shell-secure.sh install
```

### After installation

Open a new shell or reload in your current session:

```bash
source ~/.bashrc
```

## Configuration

After installation, the config lives at `~/.shell-secure/config.conf`:

```bash
# Master switch — turning this off disables both layers below.
SHELL_SECURE_ENABLED=true

# Per-category toggles — only effective while ENABLED=true.
# Delete protection: rm -rf, cmd /c rmdir /s, powershell Remove-Item -Recurse
SHELL_SECURE_DELETE_PROTECT=true
# Git protection: git stash capture/restore/ref-mutation without explicit bypass
SHELL_SECURE_GIT_PROTECT=true
# Git flood protection: rate-limit network git calls (push/pull/fetch/clone/ls-remote)
SHELL_SECURE_GIT_FLOOD_PROTECT=true
SHELL_SECURE_GIT_FLOOD_THRESHOLD=4    # max calls
SHELL_SECURE_GIT_FLOOD_WINDOW=60      # seconds
# PowerShell UTF-8 enforcement: block writes that would emit UTF-16 BOM / ANSI
SHELL_SECURE_PS_ENCODING_PROTECT=true

# Protected areas
SHELL_SECURE_PROTECTED_DIRS=(
    "D:/Projects"
)

# Folder names that CAN still be recursively deleted
SHELL_SECURE_SAFE_TARGETS=(
    "node_modules"
    "dist"
    "build"
    ".cache"
    "__pycache__"
    # ...
)
```

### Managing Protected Areas

```bash
# Add a protected area
shell-secure add "E:/Work"

# Remove a protected area
shell-secure remove "E:/Work"

# Add a whitelist entry
shell-secure whitelist add ".output"

# Show status
shell-secure status
```

Or via the TUI menu: `bash setup.sh`

## Usage

### Delete protection in action

```
$ rm -rf /d/Projects/my-repo

  [Shell-Secure] BLOCKED
  ------------------------------------
  Command:  rm -rf /d/Projects/my-repo
  Target:   /d/projects/my-repo
  Reason:   Recursive delete in protected area
  ------------------------------------
  Bypass:   command rm -rf ...
            command cmd /c "..."
  ------------------------------------
```

### Git protection in action

```
$ git stash

  [Shell-Secure] BLOCKED
  ------------------------------------
  Reason:  git stash with uncommitted changes in the worktree.
           Stashes often never get popped back, and parallel
           sessions can lose their work irreversibly.
  ------------------------------------
  Better:  git add -A && git commit -m "WIP: <short description>"
           — Reflog keeps it; recover later with `git reset --soft HEAD~1`.
  ------------------------------------
```

```
$ git reset --hard HEAD

  [Shell-Secure] BLOCKED
  ------------------------------------
  Reason:  git reset --hard with uncommitted changes in the worktree.
           Tracked modifications would be lost without a Reflog entry,
           because --hard does not snapshot the worktree state.
  ------------------------------------
  Better:  git add -A && git commit -m "WIP: <short description>"
           — Then run `git reset --hard <commit>` from a clean state.
  ------------------------------------
```

```
$ git fetch    # 5th time within 60 s

  [Shell-Secure] BLOCKED
  ------------------------------------
  Layer:   Shell-Secure (Git-Flood-Schutz)
  Reason:  More than 4 network git calls in the last 60 s.
           A runaway agent would otherwise spam the auth prompt or
           trigger an unintended push/pull loop.
  ------------------------------------
  Better:  git config --global credential.helper manager   # once-only login
           Pause and check what is firing the calls.
  ------------------------------------
  Tune:    SHELL_SECURE_GIT_FLOOD_THRESHOLD / _WINDOW / _PROTECT
  ------------------------------------
```

```
$ powershell -c "Set-Content config.json '{...}'"

  [Shell-Secure] BLOCKED
  ------------------------------------
  Layer:   Shell-Secure (PowerShell-UTF-8-Schutz)
  Reason:  PowerShell write without -Encoding utf8.
           Windows PowerShell 5.1 defaults to UTF-16 LE BOM (Out-File, >)
           or ANSI/CP-1252 (Set-Content, Add-Content). Source files end
           up with BOM bytes and look like binary garbage to anything
           that opens them as UTF-8.
  ------------------------------------
  Better:  Set-Content -Encoding utf8 -Path file.txt -Value 'content'
           'content' | Out-File -Encoding utf8 file.txt
           # or just: echo 'content' > file.txt   (Git Bash, always UTF-8)
  ------------------------------------
  Toggle:  SHELL_SECURE_PS_ENCODING_PROTECT=false to disable entirely
  ------------------------------------
```

### Allowed operations

```bash
# Whitelisted targets pass through
rm -rf /d/Projects/my-repo/node_modules  # OK

# Non-recursive is fine
rm /d/Projects/file.txt                  # OK

# Intentional delete bypass
command rm -rf /d/Projects/old-folder    # OK (skips wrapper)

# Read-only stash inspection always works
git stash list                           # OK
git stash show --stat stash@{0}          # OK

# Stash on a clean worktree is allowed (nothing to capture)
git stash                                # OK if `git status` is clean

# Soft reset and mixed reset are never blocked
git reset --soft HEAD~1                  # OK
git reset HEAD path/to/file              # OK (unstage)

# Hard reset on a clean tree is allowed (nothing to destroy)
git reset --hard HEAD                    # OK if `git status` is clean

# Clean dry-runs and interactive mode always pass through
git clean -nfd                           # OK (dry-run)
git clean -i                             # OK (interactive prompts)

# Clean is allowed when there is nothing to remove
git clean -fd                            # OK if no untracked files exist

# Branch switches are not affected; Git refuses on conflict itself
git checkout feature                     # OK
git switch -c new-feature                # OK
git checkout -B feature                  # OK (branch create/reset)

# Index-only restores are always safe
git restore --staged path/to/file        # OK (no worktree change)

# Force-delete is only blocked when the branch is unmerged
git branch -D unmerged-branch            # BLOCKED if commits would orphan
git branch -D fully-merged-branch        # OK (same outcome as -d)
git branch -d any-branch                 # OK (git's own safety still applies)

# Local/inspection git is never rate-limited
git status                               # OK (not counted)
git log --oneline                        # OK (not counted)
git diff                                 # OK (not counted)
git branch -a                            # OK (not counted)

# PowerShell writes need explicit UTF-8 encoding
powershell -c "Set-Content -Encoding utf8 file.txt 'content'"   # OK
powershell -c "Get-Content file.txt"                            # OK (read-only)
powershell -c "Get-Process | Tee-Object -Encoding utf8 log.txt" # OK
```

### Run self-test

```bash
shell-secure test
```

Creates a temporary directory and verifies that blocking and whitelisting work correctly.

## CLI reference

```
shell-secure <command>

  install                    Install shell-secure
  uninstall                  Uninstall and clean up
  update                     Update the protection script
  enable                     Enable protection (master switch)
  disable                    Disable protection (master switch)
  status                     Show installation status
  test                       Run self-test
  add <path>                 Add a protected area
  remove <path>              Remove a protected area
  whitelist                  Manage whitelist (add/remove/list)
  log                        Show blocked commands

  flood show                 Show git-flood threshold/window
  flood enable | disable     Toggle git-flood protection
  flood threshold <n>        Set max network git calls per window
  flood window <s>           Set window length in seconds

  ps-utf8 show               Show PS UTF-8 enforcement status
  ps-utf8 enable | disable   Toggle PS UTF-8 enforcement
```

## Uninstall

```bash
# CLI
shell-secure uninstall

# Or via TUI
bash setup.sh  # → menu: Uninstall
```

Removes all files from `~/.shell-secure/`, cleans up `.bashrc`, and backs up the block log.

## Building from source

Only needed if you want to compile the GUI yourself. End users don't need this.

- **.NET Framework 4.8+ compiler** (`csc.exe`) — compiles the GUI
- **PowerShell** — runs the build script

The build updates `VERSION` and the README version block, so GitHub shows the current build after the change is committed and pushed.

```powershell
.\build-gui.ps1
```

### Packaging a release ZIP

Release ZIPs are generated into `dist/` and are meant for GitHub Releases, not for committing to the source tree.

```powershell
.\package-release.ps1
```

The package contains the GUI executable, `VERSION`, `README.md`, `LICENSE`, `CONTRIBUTING.md`, release metadata, and SHA256 checksums.

## License

This project is licensed under the **AI Agent Secure Source-Available License v1.0** — see [LICENSE](LICENSE) for details.

You may use, inspect, modify, and contribute to the project under the license terms. Commercial sale or paid redistribution of AI Agent Secure, including modified versions, requires prior written permission from Joel Aniol.

Contributions are welcome under the contribution terms in [CONTRIBUTING.md](CONTRIBUTING.md).

Because commercial sale is restricted, this is not an OSI-approved open source license.

### Third-party components

| Component | Purpose | License |
|---|---|---|
| [Git for Windows](https://gitforwindows.org/) | Provides Git Bash (required for shell protection) | [GPL v2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html) |
| [.NET Framework 4.8+](https://learn.microsoft.com/en-us/dotnet/framework/install/on-windows-and-server) | GUI runtime/build target (WPF) — serviced with supported Windows versions | [Microsoft terms](https://dotnet.microsoft.com/platform/free) |

AI Agent Secure does not bundle or redistribute any of these components.

## Disclaimer

This software comes with **absolutely no warranty**. While AI Agent Secure is designed to prevent accidental recursive deletion and agent-driven workflow loss, it cannot guarantee protection in every scenario. Use at your own risk. Always maintain proper backups of important data.
