---
description: "Main entry point for R.Code and framework work: decomposes a directive, dispatches specialist agents as team lead and, in R.Code projects, detects the Stage (Plan, Design, Develop, Test, Launch). Use for any directive; /plan-team through /launch-team force a Stage."
argument-hint: <the task or directive to hand to the team>
model: fable
allowed-tools:
  - Task
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash(git:*)
  - Bash(bash:*)
  - Bash(gh auth status:*)
  - Bash(gh issue list:*)
  - Bash(gh repo view:*)
  - AskUserQuestion
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `~/.claude/agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `~/.claude/agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `~/.claude/agents/control-agent.md` §4.

> **Since 2026-09-23 (R.Code rework "Plan folgt Praxis", ADR 0002):**
> `/team-lead` is THE main entrance for all R.Code project work, and stays
> the generic controller outside R.Code projects. This supersedes the
> 2026-07-26 framing ("phase-agnostic fallback — prefer the five team
> commands for phase work"), which practice never followed: 471 transcripts
> measured `/team-lead` at 67 invocations across 16 projects against 0 for
> every one of `/plan-team`…`/launch-team` (§0 of the rework spec).
> `/plan-team`…`/launch-team` remain valid as thin aliases — `/team-lead`
> with the Stage forced — for when the directive already names its Stage;
> see "R.Code Mode" below.

# Team Lead — The Main Controller-First Entry Point

The `model:` frontmatter pins THIS turn to the `fable` alias (the current Fable model) regardless of the session
model, and it makes the current turn genuinely act as team lead: this prompt
is a management directive, not a task to execute directly. When `.rcode/`
exists in the project root, this turn additionally runs **R.Code Mode**
(below) to bind the directive to a Stage and its playbook before decomposing.

> NOTE: the pin covers only the command turn. If you reply mid-flow (e.g. to
> a y/n), the next turn falls back to the session model — for multi-turn
> delegation sessions, additionally set the chat model to Fable5.

## User's Directive

$ARGUMENTS

## Instructions

### 1. Read as a management directive
Treat `$ARGUMENTS` as instructions from a manager to a team lead. Your job this turn is to plan the work, hand out what is worth handing out, and check what comes back. Apply the decision rule in `~/.claude/rules/foundation.md`: units that are independent, produce long output or need an unbiased review go to helpers; a unit that is small, sequential or needs the context you hold you do yourself, and you say so in one line. Under `/team-lead`, size decides first: a unit that spans several files or domains goes to a helper with a brief, also when it is sequential. A personal preference file may set a stricter default for the lead; where it does, it decides.

Do not spawn `control-agent` as a subagent for this: this turn is the lead, and a spawned controller would only add a layer between you and the workers.

### 2. Decompose
Break the directive into atomic units of work. For each unit, determine:
- Which specialized agent fits (see `~/.claude/agents/control-agent.md` §2 for the
  Agent/Model/Effort assignment table and `~/.claude/docs/reference/delegation.md` (Agent Selection)
  for the agent-selection matrix)
- Whether it's independent of the other units (disjoint files, no
  output→input chain) — see `~/.claude/docs/reference/delegation.md` (Parallel work)

**Goal plan (IMP-289).** The units become the goal plan: one
`bash ~/.claude/scripts/goal.sh --session <id> plan` call (the session id is in
this turn's `[Goal tracking]` line) with the goal in one sentence, milestones in
workflow order (research, plan, develop, test, deploy; a stage left out carries
its reason) and one atomic issue per unit with honest minutes, the files it may
touch (`paths`) and `"fixed": true` for machine time such as a suite run. The
plan is what Cockpit card 4 shows and what the time to goal is computed from;
work that is not in the plan is a deviation.

### 3. Dispatch
- 2+ independent, reversible units with disjoint files → dispatch in
  parallel in a single message, per `~/.claude/docs/reference/delegation.md` (Parallel work).
- Anything containing an ESCALATE-band op, or with unprovable disjointness →
  present the proposal format from `~/.claude/docs/reference/delegation.md` (Parallel work) and wait
  for a real y/n.
- Single-domain work that is more than a small unit → dispatch the one fitting
  specialist. A small unit, or one that needs the context you hold, you do
  yourself (§1).
- **Knowledge for the brief (IMP-267, IMP-268).** Library hits for the prompt and for each helper are injected automatically. When a unit touches an area with history, run one lookup yourself (`bash ~/.claude/scripts/knowledge-lookup.sh --max 6` with two to four keyword sets: your own words, the German or English translation, the technical terms) and put fitting notes with their paths into the brief's KNOWLEDGE field. `knowledge-agent` remains available when a large wave needs many lookups at once.
- **Goal tracking per wave (IMP-289).** The goal plan is the task list of the wave. `bash ~/.claude/scripts/goal.sh --session <id> start <issue>`
  when a unit is dispatched, `done <issue>` when its check has passed in the
  wave review (§4). Work that was not planned gets `add` (or `add --detour`),
  planned work that will not happen gets `drop --why`, any other change of
  course gets `deviate` — BEFORE it is done, not after. Two reasons this is
  mandatory, not optional bookkeeping: **Cockpit's card 4 shows the goal, the
  issues, the measured pace, the time to goal and every deviation live**, and
  the time to goal is only as true as the start and done marks. Units you do yourself (§1) need no issue.
- **Every Agent call carries an explicit `model` parameter.** A worker spawn
  passes `haiku` (Haiku 5.5, the worker default in `~/.claude/docs/reference/delegation.md` (Model tiers));
  `sonnet` only on a recorded Haiku failure under that reference's three-part rule.
  This turn is pinned to Fable by the `model:` frontmatter above. A spawn
  without the parameter resolves in this order: the `model:` of the target's
  definition file, then `CLAUDE_CODE_SUBAGENT_MODEL` (`haiku` in this setup's
  `settings.json`), then the CALLER's model, which here is Fable, the
  coordinator tier. `general-purpose`, `Plan` and plugin agents have no
  definition file of their own and depend on that variable. The built-in
  `Explore` agent is the exception: on a subscription it runs on the model
  behind the `opus` alias unless the call passes `model`.
  See `~/.claude/agents/control-agent.md` §2 for the full
  four-step resolution order and the 2026-09-21 measurement behind this
  (IMP-212). Assigning the model in prose does not set it.

### 4. Synthesize + Re-Plan
After EVERY delegation wave — not only at the end — run the 2nd-order
checkpoint from `~/.claude/agents/control-agent.md` §4: digest-review outputs against
the §2 definition-of-done, re-evaluate the remaining plan and each spawn's
Model×Effort sizing, and decide explicitly (continue / re-decompose /
escalate) BEFORE dispatching the next wave. Then consolidate all outputs
into one coherent result for the user; its first line is `Done: yes` or
`Done: no — missing: <list>`, scoped per visible surface (`verified` /
`not checked`), per `~/.claude/docs/reference/slop-prevention.md` Trigger 3 step 6.
Surface any ESCALATE-band operations
subagents flagged up to you (per `~/.claude/rules/agency-bands.md` — you are the
human-facing escalation point for this delegation).

**Goal check (IMP-289).** Every issue of the wave is `done`, or is explicitly
left open or dropped with a stated reason. At every milestone and before the
completion report, spawn `goal-agent` (model haiku, effort medium) with the
session id and the repository root: it lists scope creep, silent drops and
unreported detours against the plan. Record each finding with `goal.sh deviate`
(or `add` / `drop`), name it in the synthesis for the user, then run
`goal.sh ack`. The completion report carries the progress, pace and time-to-goal
line of `goal.sh status` and every deviation; `hooks/goal-stop.sh` raises what
was left unreported when the turn ends.

## R.Code Mode

Applies when `.rcode/` exists in the project root. This runs BEFORE §1–4
above scope the directive: it turns a project-shaped directive into a bound
Stage + playbook, which §2's Decompose and §3's Dispatch then work inside
of. (Outside a `.rcode/` project, §1–4 run exactly as before — nothing here
changes generic, non-R.Code behavior.)

### 1. Orient (deterministic)

Run `bash ~/.claude/scripts/resume-state.sh "$PWD"` and
`bash ~/.claude/scripts/status-metrics.sh "$PWD"`. Read `.rcode/config.json`
(`tracker`), `PROJECT-STATUS.md`, the last 2 `agent-log.md` entries,
`CONTEXT.md` if present, `.rcode/re-entry-brief.md` if present, and
`.rcode/escalation-queue.md` if present — its open entries are surfaced
first, before anything else this turn.

For the active project Phase, read `PROJECT-STATUS.md`'s "Active Phase"
line FIRST — it is the one Phase field every command keeps live. Read
`.rcode/config.json`'s `current_phase` only as a fallback, when
`PROJECT-STATUS.md` is absent or states no Active Phase: that field is a
scaffold-time stub until `/decompose` Step 6 gives it its first real value
(`1`, once Phase 1's units exist), and apart from `/phase-gate` advancing it
on PASS/WARN nothing else updates it, so it can go stale between phase
gates.

If `.rcode/config.json` has no `tracker` field, ask once via
`AskUserQuestion` before proceeding (per `~/.claude/rules/foundation.md`, Asking and acting):
recommend `github` when a remote exists AND `gh auth status` succeeds AND at
least one GitHub issue exists, else recommend `plan`. Persist the answer to
`.rcode/config.json` and continue — never guess silently.

### 2. Stage detection

Alias-forced Stage wins (a `/plan-team`…`/launch-team` invocation always
sets its own Stage). Otherwise, an open `.rcode/re-entry-brief.md`'s
`to_stage` wins. Otherwise, infer from the directive + the state gathered in
step 1:

| Signal | Stage |
|---|---|
| no product docs / no units yet / re-planning, new scope | Plan |
| UX, flows, design system, component specs | Design |
| implement/fix units, open units in current Phase | Develop |
| validate a Phase/RC, review PR(s), coverage strategy | Test |
| release, deploy, production incident | Launch |

State the chosen Stage and a one-line why. Genuine ambiguity → one question
to management with a recommendation, per `~/.claude/rules/foundation.md` (Asking and acting)
— never a silent guess.

### 3. Load playbook

Read `~/.claude/rcode/stages/<stage>.md` (`plan.md`, `design.md`,
`develop.md`, `test.md`, or `launch.md`) and follow it — its asset cluster,
operating modes, core loop, Stage nuance (backward transitions), and
authority boundary govern the rest of this turn. TRIGGER, never copy: read
the file, don't paraphrase it into this prompt.

### 4. Unit binding (IMP-150, tracker-agnostic)

Map every unit of work to an open work unit — `#N` (tracker `github`) or
`P-NNN` (tracker `plan`). A unit without one is dispatched only with an
explicit declaration: "no unit — creation needed" or "deliberately
unit-free, because …" — silent unit-free dispatch is a scope violation.

Workers that implement a unit receive `~/.claude/commands/issue.md`'s
**Worker mode** section (not its Standalone mode) as their binding
protocol — by reference, never paraphrased — plus the unit ID, the tracker,
and the branch name THIS Lead has chosen for the working session (one
branch per directive/wave, `work/<YYYY-MM-DD>-<slug>` unless the user named
one — see the Single-Writer Rule below; workers never create branches
themselves).

Before creating that wave branch, this Lead resolves the trunk exactly the
way `~/.claude/commands/issue.md` Step 2 does — never assume `main`:

```bash
trunk="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's#^origin/##')"
trunk="${trunk:-main}"   # no remote/origin HEAD (e.g. tracker plan, local-only repo) → confirm the trunk name with the user once if it is not main
git checkout "${trunk}"
if git remote get-url origin >/dev/null; then git pull --ff-only origin "${trunk}"; fi
git checkout -b "work/$(date +%Y-%m-%d)-<slug>"
```

> Evidence (proj-292e7a, 2026-09-21): 16 sub-agents across 4 waves
> committed to one shared branch (`overnight/2026-09-21-foundation`);
> `/issue` was never invoked in its Standalone form. Worker mode formalizes
> exactly that shape instead of treating it as a deviation.

### 5. Dispatch + wave review

Unchanged mechanics from §2–4 above: control-agent §2/§3/§4 for
Agent/Model/Effort assignment, `~/.claude/docs/reference/delegation.md` (Parallel work) for
independence + auto-dispatch vs. proposal, the task brief form
(`~/.claude/templates/auftragsbrief.md.template`) for every brief, the
verbatim-instruction clause, and the explicit `model` parameter rule above
on every spawn.

### 6. Proportional exit

Replaces a fixed 5-step Exit Contract that used to run every command on
every exit regardless of whether it applied. Apply only the rows whose
condition actually holds this turn:

| Condition | Action |
|---|---|
| any work was done | append one `## Session: …` entry to `.rcode/agent-log.md` in the template below (append-only; run the full `~/.claude/commands/handoff.md` procedure when the session ends or the user asks) |
| unit states changed | run the `~/.claude/commands/status-sync.md` procedure |
| a unit became newly blocked (predecessor, env key, or other) | record it in `PROJECT-STATUS.md`'s "Blocked Units" / "Active Blockers" tables and, if the blocker is expected to persist across sessions, `.rcode/blocked-issues.md` |
| ALL units of the active Phase N are closed | run the `~/.claude/commands/phase-gate.md` procedure for `N`; after PASS/WARN, offer `~/.claude/commands/lessons.md` |
| a major fix / recurring bug was resolved | offer `~/.claude/commands/lessons.md` |
| a unit implemented a design-time inline `ADR-NNN` not yet filed | file it as `docs/adr/NNNN-<slug>.md`, linking the inline `ADR-NNN` entry to it (two-tier model, A5) |
| a long-lived branch/worktree is about to be merged into trunk | first reconcile `.rcode/agent-log.md` and `PROJECT-STATUS.md` with the `resolving-merge-conflicts` skill, keeping both entries in timestamp order (Single-writer rule, A12 below) — fold that reconciliation into the one consolidated merge y/n, don't run it as a separate unannounced step |
| ESCALATE-band ops were flagged | ONE verbatim y/n per `~/.claude/rules/agency-bands.md` (in automatic-approval mode → `.rcode/escalation-queue.md`) |
| a re-entry brief was consumed | archive it to `.rcode/re-entry-archive/` — never delete |

**Agent-log entry template** — the only shape this Lead writes (see the
Single-Writer Rule below). `~/.claude/commands/continue.md`'s A1.5 route
check depends on the literal `**Agent:** team-lead` line to recognize a
`/team-lead` session on resume:

```
## Session: <YYYY-MM-DD HH:MM> — team-lead
**Agent:** team-lead
**Stage:** <Plan|Design|Develop|Test|Launch>
**Directive:** "<verbatim directive>"
**Branch:** <work branch>
**Units:** <IDs with state>
**Review:** <agent> — <verdict> — <pointer>   (per unit; Develop Stage)
**Decisions:** …
**Next action:** <task brief one-liner or 'none'>
```

**Never run `/phase-gate` merely because a command exits** — only when
every unit of the active project Phase is actually closed (Phase = project
milestone, not Stage — see the glossary in `~/.claude/rcode/rules/rcode-workflow.md`).

### Single-writer rule (A12)

`.rcode/agent-log.md` and `PROJECT-STATUS.md` are written ONLY by this Lead
(or the main thread acting as Lead) — never by a dispatched worker, even one
running in Worker mode. A line-based `merge=union` strategy was considered
and rejected: it can interleave multi-line entries from concurrent writers.
Rare conflicts between long-lived worktrees are resolved with the
`resolving-merge-conflicts` skill, keeping both entries in timestamp order.
Same rule stated in `~/.claude/rcode/rules/rcode-workflow.md`.

## Why This Command Exists

A hook cannot start a model turn or force a controller to run first. This command makes the current turn act as the team lead, on the model pinned in its frontmatter. The earlier prompt-time reminder hooks were retired on 2026-11-23; their guidance is in `~/.claude/rules/foundation.md`.
