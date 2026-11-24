# Identity Config Check Rules

> Prevents commits under the wrong git identity when you operate under multiple identities (work vs. personal, client A vs. client B, etc.). Always loaded.

- `hooks/git-identity-check.sh` warns at SessionStart (non-blocking) when the cwd matches an identity in `~/.claude/rules/identity.local.md` but `git config user.email` is set to another; without that file it no-ops. Setup: copy `templates/identity.local.md.template` to `rules/identity.local.md`, describe your identities and their path patterns, restart Claude Code.
- **Before each commit in an ambiguous context** (no identity rule matches) — the hook cannot catch novel contexts — verify:
  ```bash
  git config user.name
  git config user.email
  ```
- **Mismatch already landed, before pushing** (local-only):
  ```bash
  git -c user.name="Correct Name" -c user.email="correct@email" commit --amend --no-edit
  ```
  **After push:** accept the mismatch on shared branches, document it and fix the local git config — rewriting shared history is almost never worth the cost, and never without coordination.
