# Foundation Rules

> Universal project structure, guidelines, and context management. Always loaded.

## Agent Orchestration Model

**Delegate by default, execute directly only when delegation adds no value.** The main thread acts as the control-agent — it plans, delegates, and synthesizes, not implements — and routes every task involving file mutations, code execution, test runs, or any implementation work to specialized sub-agents, unless it falls into the skip-list below.

### Skip-list — do NOT delegate for:
- **Single-file edits** or small mechanical changes (< ~5 lines, obvious and bounded)
- **Tasks estimated < 2 min** wall-time end-to-end
- **Pure Q&A, explanation, or conversational turns** — no file mutations involved
- **Already inside a sub-agent** — never wrap a sub-agent in a control-agent recursively
- **User named a specific agent or skill** — honor their choice, do not re-route

### Dispatch mechanics

- 2+ independent units: per `rules/parallel-by-default.md`, spawned in a single message (e.g. research + planning, or backend + frontend once APIs are defined).
- The control-agent (`~/.claude/agents/control-agent.md`) is the **sole human-facing escalation point** for all delegated work; sub-agents never ask the user directly.
- Every sub-agent brief uses the task brief form (five mandatory fields + the two evidenced additions) from `templates/auftragsbrief.md.template` (IMP-161).
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

## Development Phases

When asked to "build", "create", "develop", or "implement":

1. **Research & Planning** — Spawn research skill + planning-agent in parallel
2. **Design** — `ux-design` skill → ui-agent (sequential)
3. **Implementation** — backend-agent / ui-agent (parallel if independent)
4. **Quality Assurance** — testing-agent + documentation skill
5. **Version Control** — Commit every 60 minutes during active development

## Quality Gates

Before moving to the next phase: all agents reported completion · `npx tsc --noEmit` passes (TypeScript projects) · `npm test` / `pytest` passes · `npm run build` succeeds (or equivalent) · no blocking issues.

## Context Management

Never try to load all project documents at once — read only what the current task needs. Use `/clear` between unrelated tasks to prevent context contamination. Prefer project-level rules (`.claude/rules/`) for project-specific patterns.

Before implementing in an area you have not worked in during this session, run `bash ~/.claude/scripts/knowledge-lookup.sh --stack` (or `--alt` with 2–4 keyword sets in one call: your own words, the German/English translation, the technical terms), judge by the `»` lines, open only the top note's section — it searches the cross-project library (`docs/OBSIDIAN.md`, Stage 2) so earlier lessons are found on demand instead of loaded into every session.

## Error Recovery

If an agent reports a blocker: assess the issue, spawn the appropriate agent to resolve it, then resume the blocked work.
