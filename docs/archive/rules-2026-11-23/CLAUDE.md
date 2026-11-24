# Claude Code — Development Framework

> ## ⚠️ READ THIS FIRST — this repo exists in TWO places
>
> **Before you change anything, run `pwd` to find out where you are.**
>
> | `pwd` ends in … | You are in the … | What applies |
> |---|---|---|
> | `…/claude-code-config` | **WORKSHOP** (`<WORKSHOP>`; real path in `~/.claude/env.local.sh`) | Development, review, commits. Nothing here is live. |
> | `~/.claude` | **LIVE INSTALL** | What Claude Code actually reads; receives only finished deploys. **Do NOT edit by hand** — only `claude-deploy` writes here. **Exception:** git-ignored `rules/*.local.md` overlays are machine-local by design and edited here in place. |
>
> 1. **Changes go in the workshop only.** An edit to `~/.claude/...` goes live immediately and is lost at the next deploy.
> 2. **You cannot verify your own work in your own session:** a change takes effect only in a **new** session after `claude-deploy`. Never claim "it works" — write down what the user needs to verify.
> 3. **Verify what you CAN before reporting done:** hook scripts directly (JSON on stdin), `jq . settings.json`, the suites under `hooks/tests/`.
>
> Deploy: `claude-deploy [config|cockpit|all]` — clean workshop only, fast-forward only, next session. Never secrets in `settings.json` (public file). Runtime keys, remotes, Cockpit: `docs/FRAMEWORK-REFERENCE.md` §Two locations.

## System Architecture

**Counts are GENERATED, never hand-maintained:** `scripts/framework-inventory.sh` — run it instead of quoting numbers. Rules differ by location: the workshop tracks the rules, the live install adds the git-ignored `*.local.md` overlays — state both, from the inventory. Six rules are path-scoped (`paths:` frontmatter, listed in `docs/FRAMEWORK-REFERENCE.md` §Auto-Loaded Rules) and load only when a matching file is read or edited; the others are always loaded. Inventory/history: `docs/FRAMEWORK-REFERENCE.md`; architecture: `HARNESS.md`.

### Auto-Loaded Rules (always in context)

Every tracked `rules/*.md` plus the live install's `*.local.md` overlays; topic map: `docs/FRAMEWORK-REFERENCE.md` §Auto-Loaded Rules. Evidence moved out of each rule: `docs/archive/rules-evidence/<rule>.md`.

### Agents (Task tool)

Roster with models: `docs/FRAMEWORK-REFERENCE.md` §Agents; each agent's use-when is its `agents/*.md` description; the Need → Agent map is in `rules/foundation.md`. pattern-extractor-agent: /lessons Step 6; ad-hoc → `pattern-document` skill.

**Retire an agent by moving it OUT of `agents/`; a subfolder does nothing.**

### Skills

Demoted, on-demand: legacy-codebase-audit, rcode-ios, framework-extraction, kokonutui-pro, release-cli-discipline, cloud-cli-discipline. Forked (haiku): pattern-document, documentation, scroll-animation-patterns. Background: react-perf-check, tailwindcss-v4-styling, import-fixer, fix-review, orchestration.

### Hooks (registered in `settings.json`)

`settings.json` is the only complete registration truth (the non-`.sh` graphify hook-guard is invisible to `framework-inventory.sh`). Gates a session will meet: guard-unsafe, excessive-agency-gate, mcp-agency-gate.

#### Bypass tokens (three scopes)

- `CLAUDE_GUARD_OVERRIDE` — one-shot, logged.
- `CLAUDE_AGENCY_ACK_ONCE=<sha256>` — op-bound, single-use; bash gate (`rules/agency-bands.md`).
- `CLAUDE_CONFIG_PROTECT_OFF` — recoverable override for protected config.

Full table: `docs/FRAMEWORK-REFERENCE.md` §Hooks.

### Observation Pipeline

Signals feed the weekly-improve routine, which reads them itself and writes proposals back (`meta-observer` is the manual, owner-invoked form of the same analysis). **Trust boundary:** `ledger-append-proposed.sh` writes only `status:"proposed"`; a human is the gate.

### Scheduled Tasks

`scheduled-tasks/<task>/SKILL.md` is the prompt read at fire time; every run must leave a run-log line (IMP-075). Details: `docs/FRAMEWORK-REFERENCE.md` §Scheduled Tasks.

### R.Code

Projects with `.rcode/` use R.Code. **`/team-lead "<directive>"` is THE entrance**; it picks the **Stage** (Plan, Design, Develop, Test, Launch; never "Phase"). Tracker: `.rcode/config.json` (`github` or `plan`). Check command availability with `ls ~/.claude/commands/ | grep -i team`. Backward Stage-jump: futility proof required. Commands and y/n gates: `docs/FRAMEWORK-REFERENCE.md` §R.Code.

### Output Style — Hausbau (opt-in)

`output-styles/hausbau.md`: opt-in only (`/output-style Hausbau`). `keep-coding-instructions: true` is load-bearing. Details: `docs/FRAMEWORK-REFERENCE.md` §Output Style.

### Token Optimization

Auto-compact margin 90 % (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`); reaching it is a process failure per `rules/context-engineering.md`; `MAX_THINKING_TOKENS` is inert for Haiku 5.5. Details: `docs/FRAMEWORK-REFERENCE.md` §Moved from CLAUDE.md.

### Behavioral Directives

1. **Development recognition:** build/create/develop → 5-phase workflow.
2. **Delegate by default:** orchestrate, don't implement (opt-out `CLAUDE_PARALLEL_AUTO_SUGGEST=0`).
3. **Multi-domain work:** 3+ agents → `control-agent` first.
4. **Commit discipline:** every 60 min (`workflow-git.md`).
5. **Error recovery:** blocker → assess → resolution agent → resume.
6. **Context hygiene:** `/clear` between unrelated tasks.
7. **Routine awareness:** daily-docs writes a Notion scaffold.

<!-- Section 'External collaboration' removed from this archived copy on 2026-11-23: a private note that must not be published; it lives in the project memory. -->
## Graphify — Knowledge-Graph Tool (external, installed 2026-07-31, IMP-109)

**Durable note: the `## graphify` section below is TOOL-OWNED and gets overwritten — put nothing that matters into it.** Global (`~/.local/bin/graphify`), nudge-only (strict toggle `GRAPHIFY_HOOK_STRICT`, off), inert until `graphify-out/graph.json` exists, fails open; remove with `graphify uninstall`. `graphify claude install` has **no global mode**: it writes `./CLAUDE.md` + `./.claude/settings.json` in the cwd only, so re-running it in a project installs a **second, project-scoped** copy.

## graphify

A knowledge graph may exist at `graphify-out/` (god nodes, community structure, cross-file relationships) — **only in projects where `graphify .` has actually been run.** Check for `graphify-out/graph.json` before assuming one is present; do not hunt for it otherwise.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
