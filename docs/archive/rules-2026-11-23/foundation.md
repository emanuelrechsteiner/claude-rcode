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

- 2+ independent units: per `rules/parallel-by-default.md`, spawned in a single message.
- The control-agent is the sole human-facing escalation point (sub-agents never ask the user).
- Every sub-agent brief uses the task brief form (six mandatory fields + the two evidenced additions): `~/.claude/templates/auftragsbrief.md.template`.
- Before every dispatch the Lead runs the knowledge round (`knowledge-agent`, 2–4 keyword sets, verdict in the brief's KNOWLEDGE field — `hooks/knowledge-brief-check.sh` denies a dispatch without it, IMP-268).
- Per-spawn Agent/Model/Effort per `~/.claude/agents/control-agent.md` §2.

### Goal tracking (IMP-289)

Every task prompt gets a goal on Cockpit card 4 (`hooks/goal-prompt.sh` writes the seed and prints the session's commands). Turn it into a plan of atomic issues with minute estimates (`bash ~/.claude/scripts/goal.sh plan`), mark `start` and `done` per issue, and record every detour, added or dropped piece of work with `add`, `drop` or `deviate` BEFORE doing it. The time to goal is computed from the estimates and the measured pace; `hooks/goal-stop.sh` raises unreported deviations when the turn ends, and they are named to the user in the report.

### Agent Selection (Task tool — heavy implementation)

| Need | Agent |
|---|---|
| Architecture, task breakdown | planning-agent |
| Backend: APIs, DB, auth | backend-agent |
| Tests, coverage | testing-agent |
| Code review (read-only) | code-reviewer-agent |
| User flows, wireframes | `ux-design` skill (ux-agent archived) |
| Visual specs, components | ui-agent |
| Rendered-output check in a real browser (read-only) | visual-qa-agent (IMP-196) |
| Research that must land as a report file | research-agent (new files only, never Edit — IMP-197) |
| Dead code, cleanup | cleanup-agent |
| Scope watch: the work against the goal plan (read-only) | goal-agent (IMP-289) |

Forked skills (isolated context): `research` (tech, APIs, docs), `documentation`, `version-control` (git, commits, PRs), `validate-build`, `pattern-document` (patterns from fixes), `nextjs-debug`.

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

Read only what the current task needs; `/clear` between unrelated tasks; project-level rules (`.claude/rules/`) for project-specific patterns. Before implementing in an area you have not worked in this session, run `bash ~/.claude/scripts/knowledge-lookup.sh --stack` (or `--alt` with 2–4 keyword sets: your own words, the German/English translation, the technical terms), judge by the `»` lines and open only the top note's section. `hooks/knowledge-gate.sh` checks this on the first Write/Edit of every agent and subagent (IMP-267); `hooks/knowledge-inject.sh` injects top hits for a prompt or a subagent brief as a floor — your own sets are what works.

## Corrections become law (IMP-124)

On the FIRST categorical correction from the user ("NIE X", "IMMER X", "NEVER X", "ALWAYS X" or an unambiguous equivalent), persist it IN THE SAME TURN — the default action, not an offer and not a question back ("should I persist this?" is itself the violation). A correction that lives only in the chat transcript is not enforced; it has to land in an artifact the next session actually reads.

1. **Classify scope.** About this codebase (a file, term, vendor, invariant) → the project's `CONTEXT.md`, an ADR or project memory (formats: `~/.claude/rules/domain-docs-convention.md`). About how the user works with the agent → user-global: one line in `~/.claude/rules/preferences.local.md` (git-ignored), never project memory. Before writing a project memory, grep `~/.claude/projects/*/memory/` for the same stance; a hit elsewhere means user-global — consolidate, leaving a one-line pointer in the project copy.
2. If mechanically checkable, add a test case that would have caught the violation.
3. Then proceed with the original task — persisting is a side-effect of the same turn, not a separate task requiring confirmation.

A SECOND identical correction is a process failure, not a reminder: the first was heard but not persisted — treat it as a signal for the observation pipeline, not as "say it again, more firmly".

Decisions someone might later ask "why?" about get an ADR (`docs/adr/NNNN-slug.md`); a multi-word circumlocution used a third time becomes a `CONTEXT.md` term, and once a term exists it is binding in conversation, identifiers, file names and commit messages.

## Error Recovery

If an agent reports a blocker: assess the issue, spawn the appropriate agent to resolve it, then resume the blocked work.
