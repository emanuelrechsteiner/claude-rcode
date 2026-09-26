<!--
Status: ACTIVE
Last Updated: 2026-09-23
Purpose: Framework glossary for claude-code-config — terms coined once (rules/domain-docs-convention.md), reused everywhere
-->

# Context — claude-code-config

**Bauhof** — this repo's working copy outside `~/.claude`, token `<BAUHOF>` (real path lives locally in `~/.claude/env.local.sh`). All edits and commits happen here; nothing here is live.

**Haus** — the deployed installation Claude Code actually reads, `~/.claude`. Never edited by hand; receives only `claude-deploy`.

**Übergabe** — the Bauhof→Haus handoff, `claude-deploy [config|cockpit|all]`. Fast-forward only; refuses if the Bauhof has uncommitted changes.

**Rails** (DE: Schienen) — the files copied into each R.Code-managed project and versioned by `rcode/VERSION`: `rcode/rules/*.md` plus installed stack rules. Commands, skills, and stage playbooks are NOT rails — they stay global in `~/.claude`, never copied per project.

**Phase** — a project development milestone, numbered 1..N (0 = pre-R.Code baseline). Used for GitHub milestones, tags `v0.N.0-*`, `/phase-gate <N>`. Never means a team stage or an `/issue` step.

**Stage** — one of the R.Code lead's five work modes: Plan, Design, Develop, Test, Launch (`/team-lead`, `rcode/stages/*.md`). Replaces the earlier "team phase" naming.

**Step** — one of the 10 steps (0–9) of the `/issue` unit protocol. Not a Phase, not a Stage.

**Work unit** — the atomic unit of planned work: `#N` (tracker `github`), or under tracker `plan`, `P-NNN` — or, in older projects, a local `#N` in a `#`/`ID`/`Nr` table (a local plan number, disambiguated from `github`'s `#N` by the `tracker` field, never by ID shape alone; see `rcode/README.md` § Tracker Modes for the full grammar). "Issue" stays reserved for a GitHub issue specifically.

**Tracker** — where work units live: `github` (issues + milestones + labels) or `plan` (checkbox lines in `BRAINSTORM.md`). Field `tracker` in `.rcode/config.json`.

**Check trio** — a project's three pre-commit checks (type/build · test · lint), defined once in that project's own `CLAUDE.md` → `## Mandatory Pre-Commit`.

**R.Code framework vs. R.Code workflow** — the public repo `claude-rcode` brands this whole configuration "R.Code"; inside this repo, "R.Code" usually means the project workflow (`.rcode/`). Say "R.Code workflow" when the project methodology specifically is meant.

**IMP / Ledger** — a numbered, ledger-tracked improvement (`IMP-NNN`, `global-observation/improvement-ledger.json`). Not every rework carries one — see `docs/adr/0002-rcode-plan-folgt-praxis.md` for a decision recorded without an IMP number.
