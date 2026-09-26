# Claude Code — Development Framework

> ## ⚠️ ZUERST LESEN — dieses Repo existiert an ZWEI Orten
>
> **Bevor du irgendetwas änderst, stelle mit `pwd` fest, wo du bist.**
>
> | `pwd` endet auf … | Du bist im … | Was hier gilt |
> |---|---|---|
> | `…/claude-code-config` | **BAUHOF** (Arbeitskopie) | Hier wird entwickelt und committet. Nichts wirkt live. **Das ist der richtige Ort für Änderungen.** |
> | `~/.claude` | **HAUS** (Installation) | Was Claude Code tatsächlich liest. **Hier NICHT von Hand ändern** — nur `claude-deploy` schreibt hierher. |
>
> **Die drei Regeln für Agenten:**
> 1. **Änderungen ausschließlich im Bauhof.** Editierst du `~/.claude/...` direkt, geht die Änderung bei der nächsten Übergabe verloren (Fast-Forward-Konflikt) — und sie wird sofort scharf, mitten in der laufenden Sitzung.
> 2. **Du kannst deine Arbeit NICHT in deiner eigenen Sitzung verifizieren.** Regeln, Hooks und Skills liest Claude Code beim **Sitzungsstart**. Was du änderst, wirkt erst in einer **neuen** Sitzung nach `claude-deploy`. Behaupte niemals „funktioniert" — schreibe, was der Nutzer prüfen muss.
> 3. **Was du trotzdem selbst prüfen kannst:** Hook-Skripte und Shell-Werkzeuge direkt aufrufen (JSON per stdin hineinschieben, Exit-Code und Ausgabe prüfen), `jq . settings.json` zur Syntaxprüfung, vorhandene Regressionssuiten unter `hooks/tests/` laufen lassen. Tu das immer, bevor du fertig meldest.
>
> Vollständige Baustellenordnung inkl. Abnahmeprotokoll: **`docs/WORKING-IN-THIS-REPO.md`**.
> Übergabe ins Haus: `claude-deploy [config|cockpit|all]`.

> You orchestrate, agents execute. Use specialized agents for heavy implementation and forked skills for diagnostics/utilities.

## System Architecture

Rules, commands, skills, agents, hooks, scheduled tasks. **Counts are GENERATED, never hand-maintained:** `scripts/framework-inventory.sh`. **Rules is the one count that differs by location — state both, never one:** Bauhof 21 tracked, Haus 24 after `claude-deploy` (+3 git-ignored `*.local.md`). Inventory/history: `docs/FRAMEWORK-REFERENCE.md`; architecture: `HARNESS.md`; changes: `global-observation/improvement-ledger.json`.

### Zwei Orte: Bauhof und bewohntes Haus

`<BAUHOF>` = Arbeitskopie dieses Repos außerhalb von `~/.claude` (realer Pfad lokal in `~/.claude/env.local.sh`).

| Ort | Rolle | Pfad |
|---|---|---|
| **Bauhof** (Arbeitskopie) | Hier wird entwickelt, geprüft, committet. Nichts wirkt live. | `<BAUHOF>` |
| **Haus** (Installation) | Was Claude Code tatsächlich liest. Empfängt nur fertige Übergaben. | `~/.claude` |

Remotes: Bauhof `origin` + `live` (Haus); Haus `origin` + `workshop` (Bauhof). `claude-deploy [config|cockpit|all]`: nur mit sauberem Bauhof, nur Fast-Forward, wirkt ab nächster Sitzung; zieht Laufzeitschlüssel (`model`, `effortLevel`, `modelSettings`; IMP-127/194) in den Bauhof zurück. Laufzeitdaten nur im Haus. Umgebungswerte in die Shell (`~/.zshrc`); Werte, die auch ohne Shell-Profil ankommen müssen, in den `env`-Block von `settings.json` — **niemals Geheimnisse**, diese Datei ist öffentlich. Das Haus bleibt vollständig (kein Symlink auf die SSD), ebenso die Cockpit-Kopie `~/.claude/cockpit` (7 Hook-Einträge + Statuszeile zeigen dorthin) — sie muss lokal und vollständig sein. Mehr: `docs/WORKING-IN-THIS-REPO.md`, `docs/FRAMEWORK-REFERENCE.md`.

### Auto-Loaded Rules (always in context)

| Rule | Governs |
|---|---|
| foundation, parallel-by-default, recommend-on-ask | Orchestration, dispatch, questions |
| agency-bands, agents-as-users, security, fail-loud | Safety, authz, secrets |
| code-quality, testing-quality, slop-prevention | Code and test quality |
| workflow-git, identity | Git, identity |
| tool-discipline, mcp-tool-usage, context-engineering, api-cost-optimization | Tools, MCP, context, models |
| documentation, planning-doc-convention, domain-docs-convention, docs-first-integration, web-research-trust | Docs, plans, ADRs, research |

Demoted to on-demand skills: legacy-codebase-audit, rcode-ios, framework-extraction, kokonutui-pro (IMP-079); release-cli-discipline, cloud-cli-discipline (IMP-218). phase-backward-transitions → `rcode/stages/backward-transitions.md`. Evidence moved out of the rules: `docs/archive/rules-evidence/`.

### Agents (Task tool)

| Agent | Model | Use |
|---|---|---|
| control-agent | fable | Orchestrator, arbiter |
| planning-agent | opus | Architecture |
| backend-agent | sonnet | APIs, DB, auth |
| testing-agent | sonnet | Tests |
| code-reviewer-agent | sonnet | Read-only review |
| cleanup-agent | haiku | Dead code |
| ui-agent | sonnet | UI components |
| visual-qa-agent | sonnet | Browser QA |
| research-agent | haiku | Research; may `Write` a NEW report file, never Edit |
| documentation-agent | sonnet | Daily-Docs only; ad-hoc docs → `documentation` skill |
| version-control-agent | sonnet | Git, report-only |
| pattern-extractor-agent | sonnet | /lessons Step 6; ad-hoc → `pattern-document` skill |

Archived: ux-agent (→ ux-design), improvement-agent (→ observation pipeline). **Retire an agent by moving it OUT of `agents/`; a subfolder does nothing.**

### Skills

| Skill | Mode | Use |
|---|---|---|
| validate-build, research, version-control, nextjs-debug, worktree-consolidate, memory-index | forked, haiku | Utilities |
| pattern-document, documentation, scroll-animation-patterns, quality-review | forked, sonnet | Docs, patterns, review |
| meta-observer; prototype | forked (opus); forked | IMP proposals; spikes |
| scope-check, rcode-onboard, grilling, resolving-merge-conflicts | main | Scope, onboard, grill, merge |
| create-hook, create-rule, create-skill, create-subagent, migrate-to-skills | creation | Author framework assets |
| legacy-codebase-audit, rcode-ios, framework-extraction, kokonutui-pro, release-cli-discipline, cloud-cli-discipline | on-demand | Demoted rules — load on their topic |
| react-perf-check, tailwindcss-v4-styling, import-fixer, fix-review, orchestration | background | Auto-trigger only |

### Hooks (registered in `settings.json`)

`settings.json` is the only complete registration truth (the non-`.sh` graphify hook-guard is invisible to `framework-inventory.sh`). Gates a session will meet: guard-unsafe, excessive-agency-gate, mcp-agency-gate, web-fetch-safety-gate, security-audit, vault-write-gate, file-protection, config-protection, pretool-auto-read, gateguard, serena-write-gate, dispatch-specialist-check, git-identity-enforce, git-state-check. Full table + suites: `docs/FRAMEWORK-REFERENCE.md` §Hooks.

#### Bypass tokens (three distinct scopes — do not confuse)

| Token | Scopes | Semantics |
|-------|--------|-----------|
| `CLAUDE_GUARD_OVERRIDE` | `guard-unsafe.sh` | One-shot, inline-from-command-string, logged. Approves a single guarded command. |
| `CLAUDE_AGENCY_ACK_ONCE=<sha256>` | `excessive-agency-gate.sh` (the bash gate) | Op-bound + single-use + inline-visible + logged (`authorizer=user`). The sha is computed over the normalized (data-stripped, whitespace-collapsed) op signature; a mismatch logs `ack-mismatch` and still blocks; a replay re-blocks. **Replaces the old `CLAUDE_GATEGUARD_OFF` for the bash gate.** |
| `CLAUDE_CONFIG_PROTECT_OFF` | `config-protection.sh` | Recoverable override for protected-config edits. |

`CLAUDE_GATEGUARD_OFF` scopes only `gateguard.sh`, not the bash gate; a persistent disable would live in `settings.json` `env`, not a bare inline `export`.

### Observation Pipeline

Signals feed `/meta-observe` proposals; weekly-improve writes back:

> **Trust boundary — do not widen it:** `ledger-append-proposed.sh` writes `status:"proposed"` and
> nothing else. It never promotes to `implemented` and never applies a change. Observation data must
> not write framework governance; a human is the gate. Idempotent via a `sourceProposal` dedup key.

Key files: observation-capture.sh, session-end-check.sh, meta-observer, compute-daily-metrics.sh, improvement-ledger.json.

### Scheduled Tasks

`scheduled-tasks/<task>/SKILL.md` is read as prompt at fire time (editing it updates the task, no re-registration); runtime state: `mcp__scheduled-tasks__list_scheduled_tasks` / `/schedule`. Run by launchd (`scripts/routine-run.sh`, installer `scripts/install-routine-timers.sh`), watched by routine-liveness-check.sh. A run without a log line is indistinguishable from one that never fired.

| Task | Schedule | Run log (mandatory since IMP-075) |
|---|---|---|
| daily-docs | 07:10 daily | daily-docs-log.jsonl |
| nightly-observation | 02:05 daily | nightly-obs-log.jsonl |
| weekly-improve | Sunday 22:06 | weekly-improve-log.jsonl |

### R.Code

For projects with a `.rcode/` directory, use the R.Code workflow. **`/team-lead "<directive>"` is THE entrance** (and the generic controller outside R.Code): picks the **Stage** — Plan, Design, Develop, Test, Launch; never "Phase" (= milestone) — loads its `rcode/stages/` playbook, dispatches. `/plan-team` … `/launch-team` are thin aliases that force their Stage.

Tracker in `.rcode/config.json`: `github` (issues) or `plan` (`P-NNN` in `BRAINSTORM.md`). /decompose, /rcode-init, /rcode-migrate set it; the rest read it.

| Kind | Commands |
|---|---|
| Setup | /rcode-init (greenfield; `git init`/commit/remote behind one y/n even in autonomous mode), /brainstorm, /simple-onboard (any repo; offers /rcode-migrate), /rcode-migrate (GitHub/commit mutations behind y/n) |
| Units | /decompose, /issue \<unit\>, /rcode-review (the only review command — `/review` never existed) |
| Periodic | /status-sync, /phase-gate \<N\>, /lessons, /rcode-upgrade (per-file y/n, never clobbers customized rules) |
| Session | /continue, /handoff, /autonomous-overnight (unattended; queues ESCALATE ops, never auto-approves) |

Rails install per project. 22 commands (verify with `framework-inventory.sh`); /rcode-onboard is a skill. Before asserting availability on any machine, check `ls ~/.claude/commands/ | grep -i team`, not a doc. A backward Stage-jump requires a documented futility proof (`rcode/stages/backward-transitions.md`).

### Output Style — Hausbau (personal preference, opt-in)

`output-styles/hausbau.md`, house-building metaphor, for readers who are not deeply technical. This is the owner's own runtime preference (own `settings.json`, same category as `model`/`effortLevel`) — not a framework default; publish transform 40 strips `outputStyle` on release, so the public framework answers in plain developer language and anyone can opt in with `/output-style Hausbau`. `keep-coding-instructions: true` is load-bearing; `false` (default) strips the built-in engineering instructions. Main thread only, read at session start; a project-level `outputStyle` would override it. Facts stay concrete, the metaphor never softens a defect; where construction has no honest counterpart, say so and explain directly.

### Token Optimization

`MAX_THINKING_TOKENS=30000`; auto-compact at 90% (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`) — but per `context-engineering.md`, reaching 92% is treated as a process failure, not normal flow.

### Behavioral Directives

1. **Automatic development recognition**: build/create/develop → 5-phase workflow (`rules/foundation.md`).
2. **Delegate-by-default posture**: the main thread acts as control-agent (plan, delegate, synthesize) and delegates implementation to specialists; skip-list in `rules/foundation.md`, 2+ independent units per `parallel-by-default.md`; opt-out `CLAUDE_PARALLEL_AUTO_SUGGEST=0`.
3. **Use control-agent for multi-domain work**: 3+ agents → `control-agent` first, the Autonomy Arbiter: sub-agents never ask the user directly, they report ESCALATE-band ops up and it consolidates one verbatim y/n per logical operation. Coordination (recommended, not mandatory): brief intent before action (what + why + expected output), concrete results after (files changed, decisions, blockers).
4. **Commit discipline**: every 60 min; report-only default per `workflow-git.md`.
5. **Error recovery**: If an agent reports a blocker → assess → spawn resolution agent → resume.
6. **Context hygiene**: `/clear` between unrelated tasks.
7. **Routine awareness**: daily-docs writes a Notion scaffold, filled during the day.

## Graphify — Knowledge-Graph Tool (external, installed 2026-07-31, IMP-109)

**Durable framework note. The `## graphify` section below is TOOL-OWNED and gets overwritten — put nothing here that matters into it.**

Global (`~/.local/bin/graphify`), nudge-only (strict toggle `GRAPHIFY_HOOK_STRICT`, not enabled), inert until `graphify-out/graph.json` exists, fails open; removal: `graphify uninstall`. `graphify claude install` has **no global mode** — it writes `./CLAUDE.md` + `./.claude/settings.json` in the *cwd only*; re-running it in a project installs a **second, project-scoped** copy. See `docs/FRAMEWORK-REFERENCE.md`.

## graphify

A knowledge graph may exist at `graphify-out/` (god nodes, community structure, cross-file relationships) — **only in projects where `graphify .` has actually been run.** Check for `graphify-out/graph.json` before assuming one is present; do not hunt for it otherwise.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
