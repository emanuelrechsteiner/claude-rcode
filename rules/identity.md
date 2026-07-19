# Identity Config Check Rules

> Prevents commits under the wrong git identity when you operate under multiple identities (work vs. personal, client A vs. client B, etc.). Personal identity mappings live in `rules/identity.local.md` (gitignored). Always loaded.

## The Problem

If you contribute under multiple git identities (different name/email per client, project, or context), git does not warn when `user.name` and `user.email` mismatch the project context. Retroactive commit-author rewrites are painful (history-invasive, breaks signatures, requires force-push).

## The Guard

`~/.claude/hooks/git-identity-check.sh` runs at `SessionStart` and warns when the current working directory suggests one identity but `git config user.name/email` is set to another.

The hook is **non-blocking** — warns, does not prevent work.

The hook reads identity mappings from `~/.claude/rules/identity.local.md` if present. If you don't have multiple identities, simply omit the `.local.md` file — the hook will no-op.

## Setup

1. Copy `templates/identity.local.md.template` to `rules/identity.local.md`
2. Edit it to describe your identities and the path patterns that should match each
3. Restart Claude Code

See `templates/identity.local.md.template` for the format.

## Behavior Before Each Commit

If in ambiguous context (no identity rule matches):

```bash
git config user.name
git config user.email
```

Verify before committing. The hook cannot catch novel contexts.

## If a Mismatch Commit Already Landed

**Before pushing** (local-only):

```bash
git -c user.name="Correct Name" -c user.email="correct@email" commit --amend --no-edit
```

**After push** (don't force-push shared branches without coordination):

- Accept the mismatch on shared branches
- Document the incident
- Adjust local git config and move on
- Retroactive rewriting of shared history is almost never worth the cost

## Implementation References

- Hook: `~/.claude/hooks/git-identity-check.sh`
- Registered in: `~/.claude/settings.json` under `hooks.SessionStart`
- Personal mappings: `~/.claude/rules/identity.local.md` (gitignored)
