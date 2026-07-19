# Migration Guide

## Coming from the private predecessor (`.torvaldsen/`)

Claude R.Code is a public rebuild of a privately-run predecessor framework that used `.torvaldsen/` as its per-project state directory and `torvaldsen-*` slugs for its atomic-workflow commands (`/torvaldsen-init`, `/torvaldsen-migrate`, …). This is a **clean break, not a compatibility shim**: R.Code detects only `.rcode/`, never `.torvaldsen/`. There is no dual-detection layer.

Why a clean break instead of supporting both: `claude-rcode` is a new public distribution with zero existing users. A permanent `.torvaldsen`-or-`.rcode` shim would bake the old brand string into every functional check forever, for the sake of a migration only the framework's own original operator ever needs to run. A one-time rename is cheaper than permanent dual-support.

### If you have an existing `.torvaldsen/`-managed project

Run this once, per project, from the project root:

```bash
# 1. Rename the state directory
git mv .torvaldsen .rcode

# 2. Rewrite slugs and prose references throughout the project's tracked files
git grep -lI 'torvaldsen' | xargs sed -i '' 's/torvaldsen/rcode/g; s/Torvaldsen/R.Code/g'
# (Linux: drop the '' after -i)

# 3. Review the diff, then commit
git status
git add -A
git commit -m "chore: migrate to Claude R.Code (.torvaldsen -> .rcode)"
```

This covers:

- The `.rcode/` directory itself (rules, hooks-config, `VERSION` file, templates under it)
- Slash-command references (`/torvaldsen-init` → `/rcode-init`, etc.) in your project's own docs
- Prose mentions of "Torvaldsen" / "Torvaldsen Workflow" in `PROJECT-STATUS.md`, `CONVENTIONS.md`, and similar tracked docs

### What this does *not* cover

- **Auto-generated integration scripts.** If your project has a code-generation pipeline (e.g. a design-tool integration) that emits files named after the old slug — such as `torvaldsen-implement-wf_*.js` or `review-torvaldsen-init-wf_*.js` — those live outside the `.rcode/`/framework tree and the sweep above won't catch them. Regenerate them from their source pipeline after the rename so the generator picks up the new naming, and spot-check the output manually; a stale generator can silently keep emitting the old names.
- **Git history.** Old commits and `git blame` output will still show the old name. `git log --grep="R.Code"` won't find pre-migration commits; `git log --grep="Torvaldsen"` still will. This is expected and not rewritten — see `rules/workflow-git.md` on why history rewrites on shared branches are avoided.
- **Your global `~/.claude` installation.** This guide is about *per-project* `.torvaldsen/` state. Upgrading the framework installation itself is a separate step — see the Install section of `README.md` (`overwrite` or `augment` mode).

### Verifying the migration

```bash
git grep -iE 'torvaldsen' -- . ':!MIGRATION.md'
```

Should return zero hits. Then run your project's normal test/build gate to confirm nothing broke from the rename.
