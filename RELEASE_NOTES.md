# AI Agent Secure v1.1.0

## Highlights

- Added Git Leak Protection for `git push`: outgoing commits are checked for risky paths such as `.env`, `.emv`, `.claude/**`, `.codex/**`, `.npmrc`, private keys, credential files, service-account JSON, and production config names before the network push runs.
- Added a 60-second terminal allow prompt for suspicious pushes. No answer, `ignore`, Enter, or timeout blocks fail-closed.
- Added audited agent force mode with `SHELL_SECURE_GIT_LEAK_FORCE=1 git push ...` for reviewed one-shot pushes.
- Added independent Git Leak toggles and timeout controls across GUI, CLI, setup/config paths, and runtime config parsing.
- Added false-positive handling for common templates such as `.env.example`, `.env.local.example`, `.env.sample`, `.env.template`, `.env.dist`, `config.example.php`, and `config.local.example.php`.
- Improved `git push` target parsing for default pushes, explicit refspecs, `--repo`, `--tags`, `--all`, `--mirror`, dry-runs, delete pushes, and `env git push`.
- Hardened destructive authenticated `curl` guidance so blocked HTTP/API calls ask for explicit user permission instead of advertising a one-line bypass.
- Standardized code comments toward English and refreshed German GUI/copy translations.

## Verification

- `tests/run-quality.ps1 -NoColor -BuildGui`
- `test.bat`
- Git Leak selftests for block, force, disabled mode, dry-run, templates, `--repo`, mixed branch/tag pushes, and `env git push`
