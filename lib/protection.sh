#!/bin/bash
# ============================================================
#  Shell-Secure Protection Layer (entry / loader)
#  Sourced by .bashrc to intercept dangerous shell operations.
#  Purpose: thin entry that pulls in the layered slices.
#  Scope: each slice owns one responsibility. Read order:
#         protection-core.sh        - shared variables, config loader, helpers
#         protection-i18n.sh        - language detection + shared label texts
#         protection-tokenize.sh    - PowerShell argument tokenizer
#         protection-delete.sh      - rm and cmd /c rmdir wrappers
#         protection-ps.sh          - PowerShell UTF-8 enforcement + wrapper
#         protection-http.sh        - curl authenticated destructive API guard
#         protection-git-leak.sh    - git push leak detector
#         protection-git.sh         - git destructive guards + flood limiter
#         protection-env.sh         - env wrapper that catches "env git ..."
#  Build/install paths concatenate these slices into one file at install
#  time; tests source this entry directly so the slice files must live
#  alongside it (lib/ in dev, ~/.shell-secure/ once installed - the
#  installer copies all slices next to this entry).
# ============================================================

_ss_loader_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_ss_loader_dir/protection-core.sh"
source "$_ss_loader_dir/protection-i18n.sh"
source "$_ss_loader_dir/protection-tokenize.sh"
source "$_ss_loader_dir/protection-delete.sh"
source "$_ss_loader_dir/protection-ps.sh"
source "$_ss_loader_dir/protection-http.sh"
source "$_ss_loader_dir/protection-git-leak.sh"
source "$_ss_loader_dir/protection-git.sh"
source "$_ss_loader_dir/protection-env.sh"
unset _ss_loader_dir

export SHELL_SECURE_ACTIVE=true
