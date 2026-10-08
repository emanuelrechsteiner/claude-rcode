<!--
Status: ACTIVE
Last Updated: 2026-10-08
Purpose: Framework glossary for claude-code-config — terms coined once (rules/domain-docs-convention.md), reused everywhere
-->

# Context — claude-code-config

**Workshop** (formerly "Bauhof") — this repo's working copy outside `~/.claude`, referenced by the `<BAUHOF>` token (real path lives locally in `~/.claude/env.local.sh`). All edits and commits happen here; nothing here is live.

**Live install** (formerly "Haus") — the deployed installation Claude Code actually reads, `~/.claude`. Never edited by hand; receives only `claude-deploy`.

**Deploy** (formerly "Übergabe") — the workshop-to-live-install handoff, `claude-deploy [config|cockpit|all]`. Fast-forward only; refuses if the workshop has uncommitted changes.

**Rails** (translated from the original German "Schienen") — the files copied into each R.Code-managed project and versioned by `rcode/VERSION`: `rcode/rules/*.md` plus installed stack rules. Commands, skills, and stage playbooks are NOT rails — they stay global in `~/.claude`, never copied per project.

**Phase** — a project development milestone, numbered 1..N (0 = pre-R.Code baseline). Used for GitHub milestones, tags `v0.N.0-*`, `/phase-gate <N>`. Never means a team stage or an `/issue` step.

**Stage** — one of the R.Code lead's five work modes: Plan, Design, Develop, Test, Launch (`/team-lead`, `rcode/stages/*.md`). Replaces the earlier "team phase" naming.

**Step** — one of the 10 steps (0–9) of the `/issue` unit protocol. Not a Phase, not a Stage.

**Work unit** — the atomic unit of planned work: `#N` (tracker `github`), or under tracker `plan`, `P-NNN` — or, in older projects, a local `#N` in a `#`/`ID`/`Nr` table (a local plan number, disambiguated from `github`'s `#N` by the `tracker` field, never by ID shape alone; see `rcode/README.md` § Tracker Modes for the full grammar). "Issue" stays reserved for a GitHub issue specifically.

**Tracker** — where work units live: `github` (issues + milestones + labels) or `plan` (checkbox lines in `BRAINSTORM.md`). Field `tracker` in `.rcode/config.json`.

**Check trio** — a project's three pre-commit checks (type/build · test · lint), defined once in that project's own `CLAUDE.md` → `## Mandatory Pre-Commit`.

**R.Code for Claude Code** — the product name of this framework in every public and marketing surface (README, website, design system, release titles, social preview): the full name in titles, hero, social preview and the first mention per page or section; "R.Code" alone in running text after that. Never "Claude R.Code" — Anthropic's Claude Code legal page forbids "Claude"/"Claude Code" as part of a third-party product name (code.claude.com/docs/en/legal-and-compliance, read 2026-09-26). Owner decision 2026-09-26 ("Go with R.Code for Claude Code" — said in German at the time), superseding "Claude R.Code" from earlier the same day. Tagline: "Build smarter. Build better." Repo and path names (`claude-rcode`, `.rcode/`, `rcode/`) stay as they are.

**R.Code framework vs. R.Code workflow** — inside this repo, "R.Code" usually means the project workflow (`.rcode/`); the whole framework is "R.Code for Claude Code" (see above). Say "R.Code workflow" when the project methodology specifically is meant.

**IMP / Ledger** — a numbered, ledger-tracked improvement (`IMP-NNN`, `global-observation/improvement-ledger.json`). Not every rework carries one — see `docs/adr/0002-rcode-plan-follows-practice.md` for a decision recorded without an IMP number.

**English-only** — every framework, Cockpit and website artifact (code, comments, messages, tests, docs, ADRs, images) is written in English; German appears only as accepted input aliases (e.g. `AGENTENWAHL:`) and in the owner's private `*.local.*` files.

**Obsidian vault** — any folder opened in Obsidian; the app writes its per-folder state into `.obsidian/` there. Always say "Obsidian vault": the bare word `vault` in this repo is the PII pseudonym store (`/vault/`, `docs/adr/0003-vault-and-gate.md`). See `docs/OBSIDIAN.md`, `docs/adr/0006-obsidian-read-window.md`.

**Knowledge folder** — the machine-local directory that `CLAUDE_KNOWLEDGE_DIR` points to, outside `~/.claude`, the workshop and any synced folder, holding `mirror/` (owned by the script, overwritten on each run) and `notes/` (the owner's, never touched); opened in Obsidian as its own Obsidian vault. Written `<KNOWLEDGE>` in docs.

**Knowledge mirror** — the read-only copy of the distilled knowledge layer (logbook, per-project memory, meta-proposals, tracked rules, a rendered ledger index) that `scripts/knowledge-mirror.sh` writes into `<KNOWLEDGE>/mirror/`; a snapshot that is stale until the script runs again.

**Rule link** — the token form `[[name]]`: a bare basename, with no path and no extension, pointing to `rules/<name>.md` (or `skills/<name>/`); a pointer for readers that nothing in the framework resolves or checks, which Obsidian makes clickable. See `docs/OBSIDIAN.md` § Link convention.

**Library lookup** — `scripts/knowledge-lookup.sh`: the agent's on-demand search over the knowledge mirror by keywords or `--stack` (keywords derived from the project's dependency files). It serves the third knowledge layer — true across projects, needed only sometimes — which is searched when needed and never loaded into every session (the always-loaded layer is `rules/`, the per-project layer is `CONTEXT.md`/ADRs/project memory). See `docs/OBSIDIAN.md` § Stage 3.
