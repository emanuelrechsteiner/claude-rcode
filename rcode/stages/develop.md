# Develop Playbook

Stage 3 — Develop. Implement work units as vertical slices, including
unit-local tests. Loaded by `~/.claude/commands/team-lead.md` (directly, or
via the `/develop-team` alias) once R.Code Mode has selected this Stage.

## Asset cluster

| Asset | Kind | Use for |
|---|---|---|
| `backend-agent` | agent (sonnet) | APIs, database, server logic, auth |
| `ui-agent` | agent (sonnet) | Components, visual design, implementation |
| `testing-agent` | agent (sonnet) | Unit-local unit/integration tests |
| `visual-qa-agent` | agent (sonnet, read-only) | Rendered check of implemented UI against the design spec before a unit is reported done |
| `cleanup-agent` | agent (haiku) | Dead code, debug-artifact removal |
| `version-control-agent` | agent (sonnet) | Commits, branches, PRs when a unit runs standalone |
| `import-fixer` | skill | Import-path repair after refactors |
| `parallel-dispatch` | skill | True parallel fan-out across disjoint units (worktree discipline IMP-070/072) |

## Core loop

For each in-scope unit, TRIGGER — never copy — the existing protocol: read
`~/.claude/commands/issue.md` and follow its **Worker mode** section when
this unit is one wave among several this turn dispatches (the common case
under `/team-lead`/`/develop-team`), or its **Standalone mode** when the
unit is worked end-to-end by this turn alone (branch, commit, PR, status
sync, agent-log all included). Units with disjoint file-sets may run in
parallel via the `parallel-dispatch` skill, following the Write-mode
Worktree & Follow-up Discipline (`~/.claude/rules/parallel-by-default.md`).

**Per-unit fresh-context review.** Workers cannot spawn subagents, so
after a worker's report-back and BEFORE the next wave or any merge, the
LEAD spawns, per unit, a fresh `code-reviewer-agent` (no prior context). It
gets (a) the changed files as absolute paths, (b) the commit hash for
context, (c) the unit's brief path, never a summary
(`~/.claude/rules/slop-prevention.md` "Copy, don't interpret"). The reviewer
has only Read/Grep/Glob and cannot run `git diff`; to show it the diff, the
lead writes `git show <hash>` to a scratch file and passes that path. The
lead records `**Review:** <agent> — <verdict> — <pointer>` in the agent-log
and sets the unit's `Fresh-context review:` field. Verdict `fix N issues
first`: the lead sends the unit back to a worker (or amends/reverts) and
neither merges nor builds on it; the user may overrule via the lead as
arbiter. This gate is prose-enforced; no hook checks it. Bug-fix units need
RED-first; allowed `RED evidence` values are defined once in
`~/.claude/commands/issue.md` Step 4.1.

A unit that renders something visible (a page, a component, a game state)
is not reported done on a green test suite alone — route the rendered
result through `visual-qa-agent` or the `human-testing` skill before
closing it, per `~/.claude/rules/slop-prevention.md` Trigger 3.

## Env-key preflight

**⛔ Per-unit dispatch gate** — a unit whose required key is known missing is not dispatched this wave (see below).

Before the first dispatch of a unit chain, collect the environment keys the
chain actually needs, from:

- each unit body's `Requires env:` line,
- `ARCHITECTURE.md`'s Environment Variables table,
- `.env.example` key names.

**Validate every collected name before it touches a shell string or
pattern.** A `Requires env:` line can come from a tracker-`github` issue
body — text any collaborator with issue-write access can edit, i.e.
untrusted input per `~/.claude/rules/security.md` and
`~/.claude/rules/agents-as-users.md`. Keep a name only if it matches
`^[A-Za-z_][A-Za-z0-9_]*$`; skip any name that doesn't and report it once as
an invalid/suspicious env-key name — never sanitize it and use a partial
form. Only validated names may reach the presence checks below.

Check presence **by name only** — never read or print a value:

- process environment: `bash -c '[ -n "${KEY+x}" ] && echo present || echo missing'`
- `.env` / `.env.local`: search for the key name with the `Grep` tool
  (pattern `^(export[[:space:]]+)?KEY=`) against each file that exists,
  rather than shelling out to `grep`.

List missing keys **once**, with a recommendation, before any dependent unit
is dispatched — never silently, and never mid-wave (evidence: IMP-169,
proj-af832e 2026-08-09 — missing env keys/secrets blocked 7 of 12 units
transitively because no preflight existed). `~/.claude/commands/issue.md`
runs this same section for its own unit at its own Step 0 — in BOTH
Standalone mode and Worker mode — by reference, never as a second copy of
this text.

**Lead-level gate:** if a unit's required key is already known missing at
this preflight, do NOT bind or dispatch that unit this wave —
`~/.claude/commands/issue.md` Step 0 already hard-STOPs a worker on the
identical missing-key condition, so dispatching it anyway only defers the
same stop to a worker who immediately bounces it back. Surface the
recommendation and either wait for the key, or bind a different, unblocked
unit for this wave instead.

## Stage nuance (backward transitions)

Full protocol in `~/.claude/rcode/stages/backward-transitions.md` — read it,
don't re-derive it here.

Develop's standard iteration is **3→2** — an implementation blocker that
traces back to the design, not the code (e.g. a component contract design
didn't anticipate). Its drawing-board case is **3→1** — the feature
demonstrably solves the wrong problem, which no design or implementation of
it can fix (an application of the general Stage N→Stage<N−1 rule; the
protocol's own worked example of this pattern is 4→1).

## Authority boundary

This Stage's authority ends at implementing the units the roadmap and
design assigned it — not re-scoping units, not deciding release timing, not
milestone-wide validation. If it becomes clear mid-work that the *plan
itself* is wrong (bad unit scope, missing dependency), that's an escalation
to management, never a silent re-plan.

## --overnight

When the invoking command carries `--overnight`, follow
`~/.claude/commands/autonomous-overnight.md` unchanged (its `Mechanism
(INVARIANT — DO NOT MODIFY)` section governs ESCALATE-band queueing) — not
restated here.
