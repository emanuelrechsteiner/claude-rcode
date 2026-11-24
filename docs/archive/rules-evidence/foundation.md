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

## Moved 2026-11-10 (context diet)

Source: pre-diet rules/foundation.md (2026-11-10 snapshot). Verbatim blocks, original headings kept.

### Dispatch mechanics

- 2+ independent units: per `rules/parallel-by-default.md`, spawned in a single message (e.g. research + planning, or backend + frontend once APIs are defined).
- The control-agent (`~/.claude/agents/control-agent.md`) is the **sole human-facing escalation point** for all delegated work; sub-agents never ask the user directly.
- Every sub-agent brief uses the task brief form (six mandatory fields + the two evidenced additions) from `templates/auftragsbrief.md.template` (IMP-161).
- Before every dispatch the Lead runs the knowledge round (`knowledge-agent`, 2–4 keyword sets, verdict in the brief's KNOWLEDGE field; `hooks/knowledge-brief-check.sh` denies a dispatch without it — IMP-268); the protocol lives in `agents/control-agent.md` §2.
- Per-spawn Agent/Model/Effort: `agents/control-agent.md` §2 (IMP-091), also when the main thread plays the planner — not restated here.

### Agent Selection (Task tool — heavy implementation)

| Need | Agent |
|---|---|
| Architecture, task breakdown | planning-agent |
| Backend: APIs, DB, auth | backend-agent |
| Tests, coverage | testing-agent |
| Code review (read-only) | code-reviewer-agent |
| User flows, wireframes | `ux-design` skill (ux-agent archived) |
| Visual specs, components | ui-agent |
| Rendered-output check in a real browser (screenshot, describe, then judge — read-only) | visual-qa-agent (IMP-196) |
| Research that must land as a report file | research-agent (writes NEW files only, never Edit — IMP-197) |
| Dead code, cleanup | cleanup-agent |

### Forked Skills (isolated context — lightweight specialists)

| Need | Skill |
|---|---|
| Research tech, APIs, docs | research |
| Documentation | documentation |
| Git, commits, PRs | version-control |
| Quick build validation | validate-build |
| Extract patterns from fixes | pattern-document |
| Framework debugging | nextjs-debug |

## Context Management

Never try to load all project documents at once — read only what the current task needs. Use `/clear` between unrelated tasks to prevent context contamination. Prefer project-level rules (`.claude/rules/`) for project-specific patterns.

Before implementing in an area you have not worked in during this session, run `bash ~/.claude/scripts/knowledge-lookup.sh --stack` (or `--alt` with 2–4 keyword sets in one call: your own words, the German/English translation, the technical terms), judge by the `»` lines, open only the top note's section — it searches the cross-project library (`docs/OBSIDIAN.md`, Stage 2) so earlier lessons are found on demand instead of loaded into every session. Since 2026-10-31 `~/.claude/hooks/knowledge-gate.sh` checks this on the first Write or Edit of every agent and subagent (IMP-267), and `~/.claude/hooks/knowledge-inject.sh` injects the top hits for a prompt or a subagent brief; the injection is the floor, the agent's own 2–4 keyword sets are what works.

### Second pass

Text removed from `rules/foundation.md` by the second pass (2026-11-10, fix-up items B1–B6), verbatim:

```text
B1 removed: - Parallel dispatch per `rules/parallel-by-default.md`.
B2 removed: - Every brief uses the task brief form (`templates/auftragsbrief.md.template`).
B3 removed: - Per-spawn Agent/Model/Effort per `agents/control-agent.md` §2.
B4 removed: ### Forked Skills (isolated context — lightweight specialists)
B4 removed: Forked skills (isolated context): `research`, `documentation`, `version-control`, `validate-build`, `pattern-document`, `nextjs-debug`.
B5 removed: on the first Write/Edit of every agent (IMP-267)
B5 removed: injects top hits as a floor
B6 removed (section, heading and paragraph):

## Corrections become law (IMP-124)

On the FIRST categorical correction from the user ("NIE X", "IMMER X", "NEVER X", "ALWAYS X" or an unambiguous equivalent), persist it in the SAME turn — not as an offer and not as a question back. A project invariant (a file, term, vendor, invariant of this codebase) goes to the project's `CONTEXT.md`, an ADR or project memory (`rules/domain-docs-convention.md` has the formats); a preference about how the user works with the agent goes to `~/.claude/rules/preferences.local.md` (user-global, git-ignored). Before writing a project memory, grep `~/.claude/projects/*/memory/` for the same stance — a hit elsewhere means user-global. If mechanically checkable, add a test. A SECOND identical correction is a process failure, not a reminder.
```
