# Claude Code Framework — Harness Architecture

> Documentation of the harness architecture in this `~/.claude/` setup. Maps to Cole Medin's 7-part AI-layer + Anthropic's Swiss Cheese Defense + a self-improving observation loop. Created 2026-05-26 after KB-synthesis (cluster 08: harness architectures).

## What is a Harness?

A **harness** is the wrapper infrastructure around an LLM that turns raw model capability into reliable agentic work. It includes:

- The agent loop (turn-by-turn control flow)
- Context management (compaction, isolation, snapshots)
- Tool access (built-in + extensions)
- Guard rails (permissions, security, rollback)
- Self-improvement (observation, iteration)

Per Anthropic's Zhang+Murag talk (Dec 2025, `CEvIs9y1uog`), the converging architecture is: **general agent + runtime + MCP servers + library of skills**. This setup is a concrete realization of that pattern.

## The 7-Part AI Layer (Cole Medin Reference Model)

This setup implements all 7 parts. Most setups in the wild have only 3–5.

| Layer | This Setup's Implementation |
|-------|------------------------------|
| **1. Rules** | Always-loaded rules in `~/.claude/rules/` — foundation, code-quality, security, testing-quality, tool-discipline, parallel-by-default, context-engineering, fail-loud, agents-as-users, slop-prevention, agency-bands, release-cli-discipline, mcp-tool-usage, workflow-git, web-research-trust (IMP-088), … (exact counts: `scripts/framework-inventory.sh` — hand-maintained numbers drifted in 3 docs, IMP-083) |
| **2. Skills** | On-demand skills (forked context) — validate-build, research, pattern-document, meta-observer, quality-review, legacy-codebase-audit, rcode-ios, kokonutui-pro, framework-extraction, ux-design, version-control, documentation, … |
| **3. MCP servers** | Multiple — context7-keyed (docs), filesystem, Notion, Supabase, Vercel, optional client-specific brand servers, … WRITE-capable tools gated by `mcp-agency-gate.sh` (IMP-078) |
| **4. Subagents** | 9 active agents (control-agent, planning-agent, backend-agent, testing-agent, ui-agent, code-reviewer-agent, cleanup-agent, documentation-agent [Mode B only], version-control-agent) + general-purpose + Explore + Plan |
| **5. LSP-equivalent** | Built-in tools (Glob, Grep) + Serena MCP for language-aware codebase navigation |
| **6. Hooks** | Lifecycle-bound hooks (counts: `scripts/framework-inventory.sh`) — `guard-unsafe.sh`, `excessive-agency-gate.sh`, `mcp-agency-gate.sh`, `security-audit.sh`, `pretool-auto-read.sh`, `gateguard.sh`, `observation-capture.sh`, `session-end-check.sh`, `config-drift-check.sh`, `web-fetch-safety-gate.sh` (IMP-088), … regression-pinned by `hooks/tests/gate-regression.sh` + `hooks/tests/web-fetch-gate-regression.sh` (IMP-076/088) |
| **7. Tests / Validation** | `validate-build` skill + per-project test discipline (R.Code) + phase-gate quality gates |

## The 5 Harness Properties

1. **Master Loop** — Claude Code's `while tool_calls: run + return` agent loop (Zoneraich "How CC Works")
2. **Context Budget** — window-relative thresholds (soft 50% / hard 75–80% / never the 90% auto-compact margin) per `~/.claude/rules/context-engineering.md`
3. **Verification Contract** — failing→passing tests written DURING planning (Boris Cherny RoboBun pattern) + phase-gate
4. **Disposable Sessions** — `/clear` between issues (workflow-git.md) + subagent isolation per Task
5. **Self-Improving Layer** — observation pipeline (see below)

## Swiss Cheese Defense (Layered Security)

Per the Anthropic Agent SDK Workshop (Thariq Shihipar). This setup has 5+ overlapping defense layers — no single layer is perfect, but combined they catch the majority of failure modes.

| Layer | Implementation | Catches |
|-------|----------------|---------|
| Identity guard | `git-identity-check.sh` (SessionStart) + `git-identity-enforce.sh` (PreToolUse) | Wrong-identity commits (Identity A / Identity B — e.g. work vs. personal git identity) |
| Unsafe command guard | `guard-unsafe.sh` (PreToolUse/Bash) | `rm -rf /`, `sudo`, network exfil |
| Git state guard | `git-state-check.sh` (PreToolUse/Bash) | Operations on dirty/wrong branches |
| File protection | `file-protection.sh` (PreToolUse/Write|Edit) | Sensitive files |
| Security audit | `security-audit.sh` (PreToolUse/Write|Edit) | Secret patterns (`github_pat_*`, `sk-*`, `AIza*`) |
| Excessive agency gate | `excessive-agency-gate.sh` (PreToolUse/Bash) + `mcp-agency-gate.sh` (PreToolUse/`mcp__*`) | `git push --force`, bulk deletes, prod migrations — see `rules/agency-bands.md` |
| Read-before-Edit — Layer 1 (advisory) | `gateguard.sh` (PreToolUse/Write\|Edit) | On first-touch Edit/Write of a file per session: returns a JSON-deny **advisory** ("investigate first") — deliberately downgraded from hard-block to advisory by IMP-045. A second attempt is allowed immediately. The gate feels "inactive" to observers because it never permanently blocks. |
| Read-before-Edit — Layer 2 (hard block) | `pretool-auto-read.sh` (PreToolUse/Write\|Edit) | The actual **exit-2 hard block**: if a file was never Read in this session, this hook denies the Edit/Write entirely. This is the enforcement layer; gateguard is only the advisory reminder. Both run PreToolUse on Write\|Edit — the two-layer split is intentional (IMP-045/IMP-048). |

## Self-Improvement Loop (The Rare Component)

Most harnesses lack this. This setup has it explicitly:

```
Edit/Write ─▶ PostToolUse ─▶ observation-capture.sh ─▶ signals.jsonl
                                                            │
Session End ─▶ Stop ─▶ session-end-check.sh ─▶ session-metrics.jsonl
                                                            │
                                        (threshold crossed) ▼
                                 "Run /meta-observe to extract patterns"
                                                            │
                User invokes /meta-observe ─▶ meta-observer skill (Opus, fork)
                                                            │
                                        ┌───────────────────┴─────────────────────┐
                                        ▼                                         ▼
                          ~/.claude/plans/meta-proposal-*.md          MCP Memory (Pattern entities)
                                        │
                                        ▼ (after review)
                          /pattern-document skill ─▶ ~/.claude/rules/*.md
                          /lessons command ─▶ CLAUDE.md / CONVENTIONS.md updates
```

Compounding effect: every observed friction becomes a rule that prevents future friction. The improvement-ledger (`~/.claude/global-observation/improvement-ledger.json`) tracks IMPs (e.g. IMP-033 = PreToolUse Auto-Read Hook).

## Scheduled Tasks (source-of-truth consolidated 2026-07-03, IMP-087)

All three tasks are LIVE. Authoritative definitions: `~/.claude/scheduled-tasks/<task>/SKILL.md` (read as prompt at fire time — editing the file updates the task). Runtime state: `mcp__scheduled-tasks__list_scheduled_tasks` / `/schedule` skill. The stale `routines/*.yaml` duplicate templates were removed 2026-07-03 (see `routines/README.md`).

| Task | Schedule | Status |
|---|---|---|
| daily-docs | 07:10 daily | ✅ live — Notion sync currently skipped (`NOTION_PARENT_PAGE_ID` unset → "partial" runs) |
| weekly-improve | Sunday 22:06 | ✅ live — data paths fixed 2026-07-03 (IMP-075); mandatory run log `weekly-improve-log.jsonl` |
| nightly-observation | 02:05 daily | ✅ live — rotate-signals archive-then-trim (IMP-049), log `nightly-obs-log.jsonl` |

## How to Extend the Harness

When adding a new capability, decide which layer to use:

| You want to... | Use |
|---|---|
| Document a behavior that should apply every session | Rule (`~/.claude/rules/<name>.md`) |
| Add a reusable workflow / domain knowledge | Skill (`~/.claude/skills/<name>/SKILL.md`) |
| Trigger automation on a lifecycle event | Hook (`~/.claude/hooks/<name>.sh` + register in `settings.json`) |
| Provide a fork()'d execution context | Subagent (`~/.claude/agents/<name>.md`) |
| Connect to external system | MCP server |
| Add a slash command | Command (`~/.claude/commands/<name>.md`) |
| Schedule recurring cloud-side work | Routine (`~/.claude/routines/<name>.yaml`) |

## Counter-Narrative — When NOT to Add to the Harness

Mario Zechner ("Building pi in a World of Slop") warns against unchecked harness accumulation:
- Each addition must pay for itself
- The `archived-replaced-by-skills/` folder is evidence of past pruning
- Periodically audit: which rules / skills / hooks have been invoked in the last 90 days? Prune dead ones.

Cole Medin's compounding-reliability math (`0.95^20 = 36%`) applies to the harness itself:
- More layers = more failure modes
- Add only when measurable benefit is demonstrated

## Naming

This harness is referenced internally as **"the R.Code Harness"** when distinction from vanilla Claude Code matters. Most of the time, just "the harness" / "this setup".

## References

- Cole Medin — "Anthropic Just Dropped a Masterclass on Building Agent Harnesses" — 7-part AI layer
- Cole Medin — "2000+ Hours of Claude Code" — WHISK framework
- Cole Medin — "The Next Evolution of AI Coding Is Harnesses / Archon"
- Anthropic Agent SDK Workshop (Thariq Shihipar) — Swiss Cheese Defense
- Zhang+Murag — "Don't Build Agents, Build Skills Instead" (`CEvIs9y1uog`) — converging general-agent architecture
- Jared Zoneraich — "How Claude Code Works" — master loop, H2A buffer, compaction
- Cluster file: your knowledge base directory (optional) `08-harness-architectures.md`
