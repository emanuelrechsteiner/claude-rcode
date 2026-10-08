# Identity Config Check Rules

> Prevents commits under the wrong git identity when you operate under multiple identities (work vs. personal, client A vs. client B, etc.). Always loaded.

Git does not warn when `user.name`/`user.email` mismatch the project context, and retroactive commit-author rewrites are painful (history-invasive, break signatures, require force-push).

- **Guard:** `~/.claude/hooks/git-identity-check.sh` runs at `SessionStart` (registered under `hooks.SessionStart` in `~/.claude/settings.json`) and warns — **non-blocking**, it does not prevent work — when the cwd suggests one identity but `git config user.name/email` is set to another. It reads the mappings from `~/.claude/rules/identity.local.md` (gitignored) if present; without multiple identities, omit that file and the hook no-ops.
- **Setup:** copy `templates/identity.local.md.template` (it defines the format) to `rules/identity.local.md`, describe your identities and the path patterns that should match each, restart Claude Code.
- **Before each commit in an ambiguous context** (no identity rule matches) — the hook cannot catch novel contexts — verify:
  ```bash
  git config user.name
  git config user.email
  ```
- **Mismatch already landed, before pushing** (local-only):
  ```bash
  git -c user.name="Correct Name" -c user.email="correct@email" commit --amend --no-edit
  ```
  **After push** (don't force-push shared branches without coordination): accept the mismatch on shared branches, document the incident, adjust local git config and move on — retroactive rewriting of shared history is almost never worth the cost.
