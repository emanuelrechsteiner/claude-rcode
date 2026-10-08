<!--
Status: ARCHIVED
Last Updated: 2026-09-29
Purpose: Passages moved verbatim out of rules/foundation.md on 2026-09-29 (IMP-234) — the rule itself stays there; this file carries the wording it had before the condensing round.
-->
# Evidence for `rules/foundation.md`

> Moved out 2026-09-29 (IMP-234). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Moved from the rule on 2026-09-29 (IMP-234)

> Condensing round IMP-234 (instruction files under 150k chars). The passages below were shortened, merged, or re-formatted in `rules/foundation.md`; each is carried over verbatim from the rule as it stood before that round, under the heading it had there. The normative content stays in the rule; what lives only here is repeated wording, history tags (dates of agent archival/creation), and the detail of the per-spawn assignment that `agents/control-agent.md` §2 owns.

### Agent Orchestration Model

**Delegate by default, execute directly only when delegation adds no value.** The main thread acts as the control-agent and routes implementation work to specialized sub-agents. Direct execution by the main thread is the exception, not the norm.

### When to Delegate (default)

Delegate to a sub-agent whenever the task involves file mutations, code execution, test runs, or any implementation work — unless it falls into the skip-list below.

For everything else, the main thread's role is to plan, delegate, and synthesize — not to implement.

### Dispatch mechanics

For 2+ independent units: see `rules/parallel-by-default.md`. That rule defines the confirmation-handshake and auto-dispatch rules — they are not duplicated here. The control-agent (`~/.claude/agents/control-agent.md`) is the **sole human-facing escalation point** for all delegated work; sub-agents never ask the user directly.

Every brief handed to a sub-agent is written in the task brief form — five mandatory fields plus the two evidenced additions, defined once in `templates/auftragsbrief.md.template` (IMP-161).

**Model + Effort assignment per spawn is defined ONCE, in `agents/control-agent.md` §2** (the canonical dispatch spec, IMP-091) — not restated here. §2 assigns Agent, Model (against the matrix in `rules/api-cost-optimization.md`), Effort, and dependencies for every atomic task, whether the control-agent runs as a real sub-agent or the main thread performs the planner role in its place.

### Agent Selection (Task tool — heavy implementation)

| Need | Agent |
|------|-------|
| User flows, wireframes | `ux-design` skill (ux-agent archived 2026-05-27) |
| Rendered-output check in a real browser (screenshot, describe, then judge — read-only) | visual-qa-agent (NEW 2026-09-09, IMP-196) |

### Parallel Execution

When tasks have no dependencies, spawn multiple agents in a single message per `rules/parallel-by-default.md`. Examples:
- Research + Planning (Phase 1 of any project)
- Backend + Frontend (when APIs are defined)

### Development Phases

2. **Design** — `ux-design` skill → ui-agent (sequential; ux-agent archived 2026-05-27)

### Quality Gates

Before moving to next phase:
- All agents reported completion
- `npx tsc --noEmit` passes (TypeScript projects)
- `npm test` / `pytest` passes
- `npm run build` succeeds (or equivalent)
- No blocking issues

### Context Management

- Never try to load all project documents at once
- Read only what's needed for the current task
- Use `/clear` between unrelated tasks to prevent context contamination
- Prefer project-level rules (`.claude/rules/`) for project-specific patterns

### Error Recovery

If an agent reports a blocker:
1. Assess the issue
2. Spawn appropriate agent to resolve
3. Resume blocked work after resolution
