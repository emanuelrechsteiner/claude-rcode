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
> 1. **Changes go in the workshop only.** An edit to `~/.claude/...` goes live immediately, mid-session, and is lost at the next deploy (fast-forward conflict).
> 2. **You cannot verify your own work in your own session:** rules, hooks, and skills load at session start, so a change takes effect only in a **new** session after `claude-deploy`. Never claim "it works" — write down what the user needs to verify.
> 3. **Always verify what you CAN before reporting done:** call hook scripts and shell tools directly (pipe JSON via stdin, check exit code and output), `jq . settings.json` for syntax, the regression suites under `hooks/tests/`.
>
> Deploy: `claude-deploy [config|cockpit|all]` — clean workshop only, fast-forward only, effective from the next session. The live install and the Cockpit copy `~/.claude/cockpit` (7 hook entries + the status line point there) stay local and complete — no symlink onto the SSD. Environment values go in the shell (`~/.zshrc`); values that must arrive even without a shell profile go in `settings.json`'s `env` block — **never secrets**, the file is public. The deploy pulls runtime keys (`model`, `effortLevel`, `modelSettings`; IMP-127/194) back into the workshop; runtime data, remotes: `docs/FRAMEWORK-REFERENCE.md` §Two locations; conventions + acceptance protocol: `docs/WORKING-IN-THIS-REPO.md`.

## System Architecture

**Counts are GENERATED, never hand-maintained:** `scripts/framework-inventory.sh`. **Rules is the one count that differs by location — state both, never one:** workshop 21 tracked, live install 24 after `claude-deploy` (+3 git-ignored `*.local.md`). Inventory/history (incl. key files and archived agents): `docs/FRAMEWORK-REFERENCE.md`; architecture: `HARNESS.md`; changes: `global-observation/improvement-ledger.json`.

### Auto-Loaded Rules (always in context)

Every tracked `rules/*.md` plus the live install's `*.local.md` overlays; topic map: `docs/FRAMEWORK-REFERENCE.md` §Auto-Loaded Rules. Evidence moved out of each rule: `docs/archive/rules-evidence/<rule>.md`.

### Agents (Task tool)

Roster with models: `docs/FRAMEWORK-REFERENCE.md` §Agents; each agent's use-when is its `agents/*.md` description; the Need → Agent map is in `rules/foundation.md`. pattern-extractor-agent: /lessons Step 6; ad-hoc → `pattern-document` skill.

**Retire an agent by moving it OUT of `agents/`; a subfolder does nothing.**

### Skills

Demoted rules live as on-demand skills — load them on their topic: legacy-codebase-audit, rcode-ios, framework-extraction, kokonutui-pro (IMP-079); release-cli-discipline, cloud-cli-discipline (IMP-218). Forked, sonnet: pattern-document, documentation, scroll-animation-patterns, quality-review. Background, auto-trigger only: react-perf-check, tailwindcss-v4-styling, import-fixer, fix-review, orchestration. Full list with modes: `docs/FRAMEWORK-REFERENCE.md` §Forked Skills.

### Hooks (registered in `settings.json`)

`settings.json` is the only complete registration truth (the non-`.sh` graphify hook-guard is invisible to `framework-inventory.sh`). Gates a session will meet: guard-unsafe, excessive-agency-gate, mcp-agency-gate, web-fetch-safety-gate, security-audit, vault-write-gate, file-protection, config-protection, pretool-auto-read, gateguard, serena-write-gate, dispatch-specialist-check, git-identity-enforce, git-state-check. Full table + suites: `docs/FRAMEWORK-REFERENCE.md` §Hooks.

#### Bypass tokens (three distinct scopes — do not confuse)

| Token | Scopes | Semantics |
|-------|--------|-----------|
| `CLAUDE_GUARD_OVERRIDE` | `guard-unsafe.sh` | One-shot, inline-from-command-string, logged. Approves a single guarded command. |
| `CLAUDE_AGENCY_ACK_ONCE=<sha256>` | `excessive-agency-gate.sh` (the bash gate) | Op-bound, single-use, inline-visible, logged (`authorizer=user`); contract: [[agency-bands]]. Replaces the old `CLAUDE_GATEGUARD_OFF` for the bash gate — that flag scopes only `gateguard.sh`; a persistent disable would live in `settings.json` `env`, not an inline `export`. |
| `CLAUDE_CONFIG_PROTECT_OFF` | `config-protection.sh` | Recoverable override for protected-config edits. |

### Observation Pipeline

Signals feed `/meta-observe` proposals; weekly-improve writes back. **Trust boundary — do not widen it:** `ledger-append-proposed.sh` writes only `status:"proposed"` — never promotes to `implemented`, never applies a change; observation data must not write framework governance, a human is the gate.

### Scheduled Tasks

`scheduled-tasks/<task>/SKILL.md` is read as prompt at fire time (editing it updates the task, no re-registration); runtime state: `mcp__scheduled-tasks__list_scheduled_tasks` / `/schedule`; every run must leave a run-log line (IMP-075) — else it is indistinguishable from one that never fired. Schedules, runner: `docs/FRAMEWORK-REFERENCE.md` §Scheduled Tasks.

### R.Code

Projects with a `.rcode/` directory use the R.Code workflow. **`/team-lead "<directive>"` is THE entrance** (also the generic controller outside R.Code); it picks the **Stage** (Plan, Design, Develop, Test, Launch — never "Phase", a milestone); `/plan-team` … `/launch-team` force their Stage. Tracker in `.rcode/config.json`: `github` (issues) or `plan` (`P-NNN` in `BRAINSTORM.md`), set by /decompose, /rcode-init, /rcode-migrate. Rails install per project. 22 commands (verify with `framework-inventory.sh`); /rcode-onboard is a skill. Before asserting availability on any machine, check `ls ~/.claude/commands/ | grep -i team`, not a doc. A backward Stage-jump requires a documented futility proof (`rcode/stages/backward-transitions.md`). Commands: /rcode-init, /brainstorm, /simple-onboard, /rcode-migrate, /decompose, /issue \<unit\>, /rcode-review (the only review command — `/review` never existed), /status-sync, /phase-gate \<N\>, /lessons, /rcode-upgrade, /continue, /handoff, /autonomous-overnight. Each command's y/n gates: `docs/FRAMEWORK-REFERENCE.md` §R.Code.

### Output Style — Hausbau (personal preference, opt-in)

`output-styles/hausbau.md` — house-building metaphor for readers who are not deeply technical — is the owner's runtime preference, not a framework default (publish transform 40 strips `outputStyle` on release; opt in with `/output-style Hausbau`). `keep-coding-instructions: true` is load-bearing: `false`, the default, strips the built-in engineering instructions. Main thread only, read at session start; a project-level `outputStyle` overrides it. Facts stay concrete; the metaphor never softens a defect; where construction has no honest counterpart, say so and explain directly.

### Token Optimization

`MAX_THINKING_TOKENS=30000`; auto-compact at 90% (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`) — but per `context-engineering.md`, reaching 92% is treated as a process failure, not normal flow.

### Behavioral Directives

1. **Development recognition:** build/create/develop → 5-phase workflow (`rules/foundation.md`).
2. **Delegate by default** — you orchestrate, agents execute (specialized agents for heavy implementation, forked skills for diagnostics/utilities); skip-list: `rules/foundation.md`; 2+ independent units: `parallel-by-default.md`; opt-out `CLAUDE_PARALLEL_AUTO_SUGGEST=0`.
3. **Multi-domain work:** 3+ agents → `control-agent` first, the Autonomy Arbiter — sub-agents never ask the user directly ([[agency-bands]]); recommended, not mandatory: brief intent before action (what + why + expected output), concrete results after (files changed, decisions, blockers).
4. **Commit discipline:** every 60 min; report-only default per `workflow-git.md`.
5. **Error recovery:** blocker → assess → spawn resolution agent → resume.
6. **Context hygiene:** `/clear` between unrelated tasks.
7. **Routine awareness:** daily-docs writes a Notion scaffold, filled during the day.

## External collaboration — Moin Latif / karst (since 2026-10-06)

- **Finding, verified 2026-10-06 against `commands/team-lead.md`:** `/team-lead` checks unit independence at task level only ("disjoint files, no output→input chain"). There is no code-level check (callers, imports) before dispatch. **Two agents on disjoint file sets can still break each other through callers.** An impact check before dispatch would close that gap.
- **Who:** Moin Latif builds **karst** (github.com/Moin105/karst): local MCP server, tree-sitter call graph, tool `find_impact` (blast radius of a change), Python, Apache-2.0, six languages; as of 2026-10-06 early (0 stars, 53 commits).
- **His proposal:** a deterministic **pre-Edit gate** — blast radius CRITICAL or graph coverage short → human y/n, like the force-push gate — plus one impact check before `/team-lead` dispatch. He offered to wire a prototype against our hooks. The maintainer accepted the collaboration (LinkedIn thread, 2026-10-06).
- **Design line for the prototype:** fail closed — if karst is slow or fails, the gate blocks and asks. Keep the gate a plain script (no model in the loop), consistent with [[agency-bands]].
- **Status:** waiting for his prototype (thread or GitHub issue). If it arrives as a PR on `claude-rcode`: `pr-guard` blocks the merge by design; review it there, then `scripts/backport-pr.sh <PR>` here (CONTRIBUTING.md, checked 2026-10-06, public copy is current).
- **Knowledge base for the LinkedIn side (read-only from here):** `/Volumes/<VOLUME>/COWORK/CPI_APP_R.Code/promo/linkedin-monitor/ledger/` (`<VOLUME>` = the volume in `CLAUDE_BAUHOF_ROOT`, `~/.claude/env.local.sh`) — `ledger.db` (SQLite), `ledger.py` (`python3 ledger.py query "SELECT …"`), `README.md` (schema, IDs, relevance scale), `exports/ledger.md` (readable view). Private, never published. Thread record: P-016, C-016, C-024, C-027.
- Nothing implemented yet; no hook, rule or changelog entry until the prototype lands and is reviewed. Private context: this file is not in `publish-manifest.txt`.

## Graphify — Knowledge-Graph Tool (external, installed 2026-07-31, IMP-109)

**Durable note: the `## graphify` section below is TOOL-OWNED and gets overwritten — put nothing that matters into it.** Global (`~/.local/bin/graphify`), nudge-only (strict toggle `GRAPHIFY_HOOK_STRICT`, off), inert until `graphify-out/graph.json` exists, fails open; remove with `graphify uninstall`. `graphify claude install` has **no global mode**: it writes `./CLAUDE.md` + `./.claude/settings.json` in the cwd only, so re-running it in a project installs a **second, project-scoped** copy.

## graphify

A knowledge graph may exist at `graphify-out/` (god nodes, community structure, cross-file relationships) — **only in projects where `graphify .` has actually been run.** Check for `graphify-out/graph.json` before assuming one is present; do not hunt for it otherwise.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
