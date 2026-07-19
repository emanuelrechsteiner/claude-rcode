# Foundation Rules

> Universal project structure, guidelines, and context management. Always loaded.

## Agent Orchestration Model

**Delegate by default, execute directly only when delegation adds no value.** The main thread acts as the control-agent and routes implementation work to specialized sub-agents. Direct execution by the main thread is the exception, not the norm.

### When to Delegate (default)

Delegate to a sub-agent whenever the task involves file mutations, code execution, test runs, or any implementation work — unless it falls into the skip-list below.

### Skip-list — do NOT delegate for:
- **Single-file edits** or small mechanical changes (< ~5 lines, obvious and bounded)
- **Tasks estimated < 2 min** wall-time end-to-end
- **Pure Q&A, explanation, or conversational turns** — no file mutations involved
- **Already inside a sub-agent** — never wrap a sub-agent in a control-agent recursively
- **User named a specific agent or skill** — honor their choice, do not re-route

For everything else, the main thread's role is to plan, delegate, and synthesize — not to implement.

### Dispatch mechanics

For 2+ independent units: see `rules/parallel-by-default.md`. That rule defines the confirmation-handshake and auto-dispatch rules — they are not duplicated here. The control-agent (`~/.claude/agents/control-agent.md`) is the **sole human-facing escalation point** for all delegated work; sub-agents never ask the user directly.

**Model + Effort assignment per spawn is defined ONCE, in `agents/control-agent.md` §2** (the canonical dispatch spec, IMP-091) — not restated here. §2 assigns Agent, Model (against the matrix in `rules/api-cost-optimization.md`), Effort, and dependencies for every atomic task, whether the control-agent runs as a real sub-agent or the main thread performs the planner role in its place.

### Agent Selection (Task tool — heavy implementation)

| Need | Agent |
|------|-------|
| Architecture, task breakdown | planning-agent |
| Backend: APIs, DB, auth | backend-agent |
| Tests, coverage | testing-agent |
| Code review (read-only) | code-reviewer-agent |
| User flows, wireframes | `ux-design` skill (ux-agent archived 2026-05-27) |
| Visual specs, components | ui-agent |
| Dead code, cleanup | cleanup-agent |

### Forked Skills (isolated context — lightweight specialists)

| Need | Skill |
|------|-------|
| Research tech, APIs, docs | research |
| Documentation | documentation |
| Git, commits, PRs | version-control |
| Quick build validation | validate-build |
| Extract patterns from fixes | pattern-document |
| Framework debugging | nextjs-debug |

### Parallel Execution

When tasks have no dependencies, spawn multiple agents in a single message per `rules/parallel-by-default.md`. Examples:
- Research + Planning (Phase 1 of any project)
- Backend + Frontend (when APIs are defined)

## Development Phases

When asked to "build", "create", "develop", or "implement":

1. **Research & Planning** — Spawn research skill + planning-agent in parallel
2. **Design** — `ux-design` skill → ui-agent (sequential; ux-agent archived 2026-05-27)
3. **Implementation** — backend-agent / ui-agent (parallel if independent)
4. **Quality Assurance** — testing-agent + documentation skill
5. **Version Control** — Commit every 60 minutes during active development

## Quality Gates

Before moving to next phase:
- All agents reported completion
- `npx tsc --noEmit` passes (TypeScript projects)
- `npm test` / `pytest` passes
- `npm run build` succeeds (or equivalent)
- No blocking issues

## Context Management

- Never try to load all project documents at once
- Read only what's needed for the current task
- Use `/clear` between unrelated tasks to prevent context contamination
- Prefer project-level rules (`.claude/rules/`) for project-specific patterns

## Error Recovery

If an agent reports a blocker:
1. Assess the issue
2. Spawn appropriate agent to resolve
3. Resume blocked work after resolution
