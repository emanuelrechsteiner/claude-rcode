<!--
Status: ARCHIVED
Last Updated: 2026-11-10
Purpose: Passages moved verbatim out of rules/identity.md on 2026-11-10 (context diet) — the rule keeps the normative text; this file carries rationale, hook internals, history and examples.
-->
# Evidence for `rules/identity.md`

> Moved 2026-11-10 (context diet). The rule keeps the guard, the verification steps and the local amend; the rationale and the long after-push text live here.

## Moved 2026-11-10 (context diet)

### Rationale (original opening paragraph)

Git does not warn when `user.name`/`user.email` mismatch the project context, and retroactive commit-author rewrites are painful (history-invasive, break signatures, require force-push).

### Guard (original bullet)

- **Guard:** `~/.claude/hooks/git-identity-check.sh` runs at `SessionStart` (registered under `hooks.SessionStart` in `~/.claude/settings.json`) and warns — **non-blocking**, it does not prevent work — when the cwd suggests one identity but `git config user.name/email` is set to another. It reads the mappings from `~/.claude/rules/identity.local.md` (gitignored) if present; without multiple identities, omit that file and the hook no-ops.

### Setup (original bullet)

- **Setup:** copy `templates/identity.local.md.template` (it defines the format) to `rules/identity.local.md`, describe your identities and the path patterns that should match each, restart Claude Code.

### After push (original text)

  **After push** (don't force-push shared branches without coordination): accept the mismatch on shared branches, document the incident, adjust local git config and move on — retroactive rewriting of shared history is almost never worth the cost.
