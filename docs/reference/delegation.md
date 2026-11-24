<!--
Status: ACTIVE
Last Updated: 2026-11-23
Purpose: Long form of the delegation rules: model tiers and cost, parallel work, access per task, when delegation pays, and what Anthropic measured
-->

# Delegation — Long Form

Long form behind `rules/foundation.md`: model tiers, parallel work, access per task and when delegation pays. It takes over the content of three rules removed on 2026-11-23 (api-cost-optimization, parallel-by-default, agents-as-users); their last texts are in `docs/archive/rules-2026-11-23/`. Not loaded automatically.

## Model tiers

> Model-selection heuristics for Anthropic API calls. Long form; read on demand.

### Model era (Claude 5.x, 2026-10)

Tiers, cheapest → most capable: Haiku 5.5 → Sonnet 5.5 → Opus 5.5 → Fable 5.2 (API ids `claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`, `claude-fable-5-2`; the Agent tool's `model` parameter takes only the aliases `haiku`, `sonnet`, `opus`, `fable`). Price ratio about 1:20:40:80 (input rates per million tokens fetched 2026-11-23: Haiku 5.5 $0.10 up to 100,000 prompt tokens and $0.50 above, Sonnet 5.5 $2, Opus 5.5 $4, Fable 5.2 $8); 1M window on all tiers; Haiku 5.5 runs adaptive thinking that `MAX_THINKING_TOKENS` cannot bound. Verify current pricing, cache TTL and cache-write premiums at docs.claude.com/pricing before any batch job. Facts and history: `docs/model-era-review-2026-10-12.md`.

### Haiku-first default

Every worker sub-agent starts on `haiku`, with its effort stated explicitly (Haiku defaults to `medium`); the task's named check decides whether the output stands. Classification, extraction, formatting, drafting, code edits, tests and review all start there.

### Model-selection matrix

Use when choosing a tier; it is the Model axis of `~/.claude/agents/control-agent.md` §2.

| Tier | Role | Typical input and complexity |
|---|---|---|
| `haiku` | default for every worker: classification, extraction, formatting, drafting, code edits, tests, review | up to 100K tokens at the cheapest rate; the named check decides |
| `sonnet` | worker only after a recorded Haiku failure on that task class | reasoning-heavy drafting or code where Haiku failed its named check |
| `opus` | coordinator for complex multi-spawn work, cross-file architecture, planning | 50K+ tokens, multi-doc synthesis, must-be-right decisions |
| `fable` | team lead for the hardest coordination and `/meta`-style meta-analysis | whole-framework corpora; where Opus has demonstrably fallen short |

### When to escalate a worker

Haiku → Sonnet → Opus → Fable only on recorded evidence, all three: (1) the same task class failed its named check on the lower tier — record check, spawn and failing output; (2) it was retried once at a higher effort and still failed; (3) the failure is recorded where a later reader finds it (ledger or agent log).

### Coordinators by role, never by escalation

`/team-lead` and the other command pins run the `fable` alias (resolves to Fable 5.2, probed 2026-11-10; Opus 5.5 permitted): a command pin sets the model of the main turn, and only the main agent coordinates on that tier. Every agent definition falls back to `haiku`, `control-agent`, `planning-agent` and `visual-qa-agent` included (owner decision 2026-11-11): a spawned agent starts on the worker tier and moves up only under the escalation rule above. `project-planning` and `meta-observer` run Opus 5.5.

### Cost heuristic

Total cost = (input + output tokens) × N_turns × price per token; a cheaper model that needs more turns can cost more. For agent loops Haiku stays the default; a loop that fails its named check is the recorded-failure case above, not a reason to start on Sonnet. Cap retries at 2 with exponential backoff; a failure that repeats on Haiku is an escalation case, not a retry loop.

### Cache discipline

Every model switch flushes the prompt cache (hits cost 0.1× base input or less): plan and execute in separate sessions with the plan passed as a file; one model per session class (worker Haiku, coordinator Fable/Opus); keep a steady cadence (5-minute TTL). Enable prompt caching for repeated work over stable context (long system prompts, retrieved docs). KPI: 80–90 % cache-hit rate; below that the session pattern is the problem, not the model choice.

When writing AI-powered code: default the worker tier to Haiku, assign coordinator tiers by role, and log the model per call for cost attribution.

Ledger: IMP-011, IMP-080, IMP-220, IMP-255.

## Parallel work

> How to run independent units in parallel once the decision rule in `rules/foundation.md` says that helpers pay. Long form; read on demand. Each unit's Agent/Model/Effort comes from `agents/control-agent.md` §2 (IMP-091): assign it before every dispatch.

### The Norm

When a task could be decomposed into 2+ independent units:

1. **Decompose** the task into atomic units.
2. **Analyze independence** — do units share files? Does B need A's output? Is each unit meaningful (>2 min serial)? Shared files, an output→input chain, or tiny units → execute serially.
3. **If 2+ truly independent units exist AND the work is reversible with disjoint, lock-claimed file-sets** → **auto-dispatch** in parallel with a one-line note ("Dispatching N parallel agents on disjoint file-sets X/Y/Z; locks pre-claimed") — do NOT gate on a confirmation prompt.
4. **Reserve the confirmation handshake** (the full proposal + y/n) for parallel work that either contains an **irreversible / ESCALATE-band operation** (anything in `agency-bands.md`'s ESCALATE band — force-push, prod migration, `gh pr merge`, deploys, external sends, destructive deletes) or has **ambiguous scope** (file-sets you cannot prove disjoint, or unclear which files each unit touches).
5. **Execute sequentially** when the units are small, coupled, or depend on context you hold (the decision rule in `rules/foundation.md`).

Why: serial execution of independent work multiplies token cost and wall time, while a confirmation gate on *reversible, disjoint* work adds friction without safety value.

### Decision Matrix — when YES, when NO

Parallel: the same mechanical operation across 3+ files, backend + frontend + tests, 3+ repos/docs read-only, tests for 4 modules, N component migrations, audits of disjoint sub-systems.
Not parallel: a single-file edit, pipelined work (plan → implement → test), tasks under 2 minutes, a cross-file rename that couples files, read-then-decide flows.

### The Proposal Format (for ESCALATE-band or ambiguous-scope work)

For ESCALATE-band or ambiguous-scope parallel work present the proposal (units, agent/model/effort, exclusive file sets, wall-time, safety line) BEFORE executing and wait for y/n; after confirmation the `parallel-dispatch` skill runs claim → dispatch → synthesis. Template: `~/.claude/docs/archive/rules-evidence/parallel-by-default.md`.

### When to skip the proposal (just execute)

1. Reversible work with disjoint, lock-claimed file-sets → auto-dispatch with a one-line note (the common-case default).
2. User already specified parallelism ("do these 3 in parallel") → just do it.
3. Single-domain trivial task → no decomposition exists.
4. Already in `/parallel-dispatch` context → don't recurse.
5. Read-only / investigation tasks with no writes → dispatch in parallel directly, no claims needed.

### Failure modes to watch for

Watch for over-decomposition (sweet spot 3–6 units), hidden dependencies (if the disjoint-file-set check finds one: merge or sequence the units), pipelined work forced parallel, and proposal fatigue.

### Write-mode dispatches: worktree & follow-up discipline (IMP-070/072)

For any WRITE-mode dispatch, follow `~/.claude/skills/parallel-dispatch/SKILL.md` §"Worktree & Follow-up Discipline (IMP-070/072)" (isolation per writer; the lock protocol is for WRITE fan-outs only, read-only swarms need no claims). Actual usage is currently unmeasured (IMP-114) — do not cite a usage rate until the new claim log has accumulated.

Integration (under `~/.claude/`): skills `parallel-dispatch/` (executor) and `check-parallelizable/` (analyzer); `scripts/parallel-claim.sh` (lock registry); hooks `parallel-lock-check.sh` (enforcement), `subagent-lock-release.sh` (auto-release); `agents/control-agent.md` uses the same protocol.

## Access per task

1. **Database:** an LLM-backed app queries through a read-only role; writes need an explicit user-authenticated path.
2. **API keys:** no master keys; one scoped key per tool, never one key bundled or shared across agents; rotate scoped keys aggressively.
3. **Filesystem:** sub-agents get workspace-scoped access, never `~/` or `/`.
4. **Network:** default deny; allowlist domains per task. This governs what an app or a helper may reach; the lead's own research fetching follows the web research paragraph in `rules/agency-bands.md`.
5. **YOLO mode (`--dangerously-skip-permissions`)** MUST have an explicit, narrow allowlist and is by default allowed only in a container or sandbox; `hooks/sandbox-guard.sh` WARNS at SessionStart when YOLO runs outside a known sandbox — it does not block — and every bash invocation MUST be logged while YOLO is on.
6. **Secrets:** never commit `.env` files, keys, tokens or credentials, and scrub secrets from agent outputs; after any `<tool> env pull`, diff the local key set against the remote listing (`<tool> env ls`) — providers silently skip variables marked "Sensitive" (detail: `~/.claude/rules/security.md`, path-scoped).

**Rule of Two:** untrusted input, sensitive data/system, state change or external comms — two or more YES make the operation ESCALATE, also when it looks reversible; defined once in `rules/agency-bands.md`.

## When delegation pays

Decide per task. Work directly when the task is small, sequential, or needs context you already hold: a fresh subagent has to rebuild that context first and does not give a better answer than you would. Use subagents when units are independent and can run in parallel, when the output is long and you only need the conclusion (wide searches, test runs, audits), or when you want a reviewer that has not seen your reasoning.

The main session decides per unit. Everything that changes files, runs code or runs tests is a candidate for a helper when the decision rule above says it pays. The main session keeps the following for itself.

### Work you do yourself

- **Single-file edits** or small mechanical changes (a handful of lines, obvious and bounded)
- **Tasks of about two minutes** end to end
- **Questions, explanations and conversational turns**: no file mutations involved
- **Inside a sub-agent**: do not wrap a sub-agent in a control-agent
- **When the user named a specific agent or skill**: use that one, do not re-route

### Larger builds

When the request is to build, create, develop or implement something that spans several units, work in this order:

1. **Research and planning**: the `research` skill and `planning-agent`, in parallel when both are needed.
2. **Design**, where the work has a user interface: the `ux-design` skill, then `ui-agent`.
3. **Implementation**: `backend-agent` and `ui-agent`, in parallel when their units are independent.
4. **Quality assurance**: `testing-agent` and the `documentation` skill.
5. **Version control**: commits at logical checkpoints (`rules/workflow-git.md`).

Before the next step starts: every helper of the step has reported, the type check, the tests and the build pass (`npx tsc --noEmit`, `npm test` or `pytest`, `npm run build`, or the project's equivalents), and no blocking issue is open. In an R.Code project the Stage playbooks and `/phase-gate` carry this sequence.

### When a helper reports a blocker

Assess it, resolve it yourself or through the fitting agent, then resume the blocked unit.

### Dispatch mechanics

- 2+ independent units: see "Parallel work" above; spawn them in a single message.
- The control-agent is the sole human-facing escalation point (sub-agents never ask the user).
- Every sub-agent brief uses the task brief form (five mandatory fields, two evidenced additions and an optional KNOWLEDGE field): `~/.claude/templates/auftragsbrief.md.template`.
- Knowledge-library notes that fit the unit go into the brief with their paths.
- Per-spawn Agent/Model/Effort per `~/.claude/agents/control-agent.md` §2.
- `Explore` writes no file and runs nothing that changes state, not even a scratch file or a test suite: a measurement that needs output files or a suite run goes to `testing-agent` or `backend-agent` (IMP-283).
- Name the agent on every call (`subagent_type`). `general-purpose` only when no specialist fits and the unit spans several domains.

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

## What Anthropic measured

- "You get parallelism or a fresh pair of eyes out of it, but not a smarter answer." and "a fresh subagent first has to gather context your conversation already had, so it can end up _slower_ than doing the task where you are" (https://code.claude.com/docs/en/best-practices, section "Know what subagents cost", fetched 2026-11-23).
- Defect search, F1 over 10 runs: Opus 5.5 alone at medium 0.827, with Sonnet 5.5 subagents 0.831 at about a third less cost, with Haiku 5.5 subagents 0.677 (https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence, fetched 2026-11-23). Anthropic calls these numbers internal and directional and recommends measuring on your own work.
- Haiku 5.5 pays five times its base price for a request whose prompt, cache reads and writes included, is over 100,000 tokens (https://platform.claude.com/docs/en/about-claude/pricing, fetched 2026-11-23).
- How Anthropic's own team sets up large multi-session work, from a talk by a member of the Claude Code team ("Rethinking Claude Code Best Practices", Lydia Hallie, uploaded 2026-11-12, https://www.youtube.com/watch?v=vlfCjWuv4es, transcript fetched 2026-11-23): one main session orchestrates, "doesn't write the code itself" and runs on "a model that's really good at deciding what to do and judging what comes back, a model like Fable"; the threads that do the work "need a model that's good at actually doing the work like Opus 5.5". The talk describes separate sessions for big tasks, not helpers inside one session, and it names no small model for the working threads.

## What was measured here

- 2026-11-23, one small review task: `code-reviewer-agent` reads a diff of four Python files with eight planted defects, effort high, three fresh runs per model. Haiku 5.5 found all eight in each of the three runs (list-price estimate about 0.02 USD per run, 58 to 87 seconds). Sonnet 5.5 found all eight in each of the three runs (about 0.23 to 0.27 USD per run, 18 to 25 seconds). On this task the worker default holds. The task is small: each defect sits in one function, two of them show only against a neighbouring function, and the grader counts a named defect without penalizing false alarms. It says nothing about reviews that need context across many files, which is where Anthropic's own benchmark above shows the gap. A first variant of the task was invalid and is not counted: the reviewer has no shell and could not see the diff.

