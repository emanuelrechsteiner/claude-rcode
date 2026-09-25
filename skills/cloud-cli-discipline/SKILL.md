---
name: cloud-cli-discipline
description: Guidance for inspecting cloud-CLI state before destructive or scope-changing operations (env rm, link --yes, --force) and avoiding team/account auto-pick; covers when --yes is safe, preferring the web UI for per-environment values, and the Vercel team-mismatch pre-deploy check (vercel whoami, teams ls, env ls, switch). Use before running a destructive or scope-changing cloud-CLI command, or when a deploy might target the wrong team or account. Triggers on "vercel", "vercel deploy", "vercel link", "vercel env rm", "vercel switch", "netlify", "firebase deploy", "gcloud", "aws cli", "fly", "railway", "supabase cli", "--yes", "--force", "--dry-run", "dry run", "env rm", "teams ls", "whoami", "wrong team", "wrong account", "web UI", "Web-UI", "per-environment value", "Cloud-CLI", "falsches Team", "falscher Account", "Umgebungsvariable löschen", "pro Umgebung", "deployen auf Vercel".
---

# Cloud-CLI Discipline Rule

> Inspect state before any destructive cloud-CLI operation; beware team/scope auto-selection. On-demand skill — demoted from always-loaded rule per IMP-218 (2026-09-24).

## The Rule

**Before any destructive or scope-changing cloud-CLI command, inspect the current state first** (`<tool> ls`, `<tool> teams ls`, `--dry-run`), and prefer the provider's web UI for per-scope value changes. **Reversible, single-scope, non-destructive commands do not need this gate** — `--yes` is fine for a preview deploy, `whoami`, or an idempotent link to an already-confirmed team. The gate is for ops that delete/overwrite state, change scope, or auto-pick a target.

## Why This Matters

Cloud CLIs hide scope behind terse commands: a delete can span more environments than the one named ("scope-collision"), and an auto-selected team/account can send deploys somewhere invisible ("auto-pick"). Both failures are silent — the command exits 0, and the damage surfaces later.

## How to Apply

- **Inspect before mutate:** run the read/list form first and read the actual scope.
- **Never use `--yes` / `--force`** on **destructive or scope-changing** ops — deletes, overwrites, or any link whose target team/account is not yet confirmed — without first confirming the target (`<tool> teams ls`, `<tool> whoami`).
- **`--yes` is allowed** on clearly **reversible, single-scope, non-destructive** commands: a **preview** deploy, `whoami`, or an **idempotent link to an already-confirmed team**. These do not mutate or collide with existing state, so the inspect-first gate would only add friction.
- **Always confirm the link target** before linking when the team/account is not already known — a wrong auto-pick sends work somewhere invisible. (Once the target is confirmed, re-linking idempotently to it needs no further confirmation.)
- **Prefer the web UI** for per-environment value edits where the CLI lacks scope granularity.
- This complements [[agency-bands]] (irreversible ops need y/n) — but scope-collision and auto-pick are a distinct class: the command is not *obviously* irreversible, so that gate alone won't catch it.

## Anti-Patterns

- ❌ `<provider> env rm KEY production` assuming it only touches production when KEY is multi-env (destructive + scope-collision — inspect first)
- ❌ `<provider> link --yes` to an **unconfirmed** team in a script without a prior `teams ls` (auto-pick risk)
- ❌ Trusting "command exited 0" as proof the right scope was affected
- ✅ `<provider> deploy` (preview) or `<provider> whoami` with `--yes` — reversible, single-scope, non-destructive; no inspect-first needed
- ✅ `<provider> link --yes <team>` when `<team>` was already confirmed earlier in the session — idempotent, single-scope

### Vercel team-mismatch pre-deploy check

Before running `vercel deploy` (including `--prod`), verify the CLI's active scope matches the intended project.

**Why this exists:** A wrong active team causes the deploy to succeed in the *wrong* Vercel account — the command exits 0, but the URL returned belongs to a different team. The correct project shows no new deployment and no error. This is the silent scope-collision pattern described above, applied to the deploy axis rather than the env-var axis.

**Checklist before `vercel deploy`:**

```bash
vercel whoami          # shows the currently authenticated user
vercel teams ls        # lists all teams; the active one is marked
vercel env ls          # confirms env vars are scoped to the intended project
```

If the active team is wrong, switch before deploying:

```bash
vercel switch <team-slug>
vercel deploy
```

**Anti-patterns:**
- ❌ Running `vercel deploy` in a freshly cloned repo without checking which team the CLI resolved (the CLI re-links to the last-used team in the token, which may not be the project owner's team)
- ❌ Treating the returned preview URL as proof the right project was deployed — always cross-check the team in the URL against the expected team slug
- ✅ `vercel whoami && vercel teams ls` takes ~2 seconds and prevents a confusing 10-minute debug loop

## References

- Companion: `agency-bands.md`
- Distilled from multi-project cloud-deploy experience (merge-intake 2026-05-28)

> Evidence and incident history (moved verbatim, IMP-217): `docs/archive/rules-evidence/cloud-cli-discipline.md`
