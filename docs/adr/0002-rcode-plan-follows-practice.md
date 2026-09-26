# 0002 — R.Code rework "plan follows practice": one entry point, Stages as playbooks, two tracker modes

- Status: accepted
- Date: 2026-09-23
- Translated: 2026-09-26 (English; decision unchanged)

## Context

The R.Code workflow was designed as a plan on 2026-07-26 (5 team commands
each mapped to one project Phase 1–5, `/team-lead` as a "phase-agnostic
fallback", GitHub issues as the pervasive baseline assumption, a 5-step exit
contract that ran at the end of every command). Measured against 471 main
transcripts plus the 5 real running R.Code projects (proj-797f37,
proj-671b6b, proj-47cf29, proj-4cfd39, proj-292e7a; measured 2026-09-23),
practice drifted away from the plan early and significantly:

- `/team-lead` used 67× (16 projects); `/plan-team` … `/launch-team`
  combined **0×**. The five team commands existed only on paper as
  "primary entry points" — every actual session ran through `/team-lead`,
  documented as the "fallback".
- `/issue`, `/decompose`, `/phase-gate`, `/lessons`, `/continue`,
  `/rcode-review`, `/rcode-upgrade`, `/scope-check`, `/autonomous-overnight`
  each **0×**. `re-entry-brief.md` in 0/5 projects, `phase-summaries/` empty
  in 3/5, `escalation-queue.md` in 2/5, `scope_changes[]` in 2/5 (used only
  where it was used: proj-671b6b 4×, proj-47cf29 7×). `agent-log.md`, by
  contrast, alive in 5/5 projects — that is the artifact that actually
  carries the weight.
- proj-47cf29 has **no** git remote at all (0/28 commits reference
  anything); proj-292e7a uses its own plan IDs, `refs P-NNN`, instead of
  GitHub issues (IMP-150). GitHub was nonetheless a hard requirement in
  commands/templates.
- Under `/team-lead`, 16 subagents committed across 4 waves onto ONE shared
  branch (`overnight/2026-09-21-foundation`, proj-292e7a) — `/issue` as the
  "binding protocol" for workers was never invoked in the sense documented
  there (one branch per unit, one PR per unit).
- 24 further concrete defects were verified with file:line evidence
  (M1–M24, full list + citations: `CHANGELOG.md` entry 2026-09-23, and the
  build plan this rework grew out of).

The trigger was the verbatim user directive: "Quite clearly, the plan
follows the practice. I want YOU to remove all the deficiencies and
optimize the framework before I bring my own input."

**Alternatives considered, rejected:**

1. **Keep all five full team procedures, just fix bugs.** Rejected: that
   would have cemented the 70%-identical 5× duplication (the IMP-083 drift
   class) instead of fixing the cause — the procedure living 5× instead of
   1×.
2. **`.gitattributes merge=union` for `.rcode/agent-log.md`** (originally
   planned as the M21 fix). Rejected after adversarial critique: line-based
   merges can interleave multi-line log entries, and a corrupted merged log
   is harder to spot than a conflict. Replaced with a single-writer rule
   (A12): `.rcode/agent-log.md` and `PROJECT-STATUS.md` are written only by
   the lead/main thread, never by a dispatched worker.
3. **Keep GitHub issues as the only supported tracker form.** Rejected: 2
   of 5 real projects cannot satisfy that (no remote; own plan IDs) — a
   "mandatory" feature that 40% of the actual user base cannot satisfy is
   not mandatory, it is a blind spot.
4. **`/rcode-upgrade` still never commits** (the original invariant).
   Rejected: uncommitted stamps rotted in 3 of 5 projects — the invariant
   protected against nothing, it only produced silent data loss. Replaced
   with A9: one commit after exactly one explicit y/n.

## Decision

The workflow is rebuilt so the architecture follows the measured practice,
not the other way around:

1. **One entry point.** `/team-lead "<directive>"` is the documented main
   entry point for every piece of R.Code project work. `/plan-team` …
   `/launch-team` stay installed, but only as thin aliases (`/team-lead`
   with a forced Stage) — doors, not their own procedures, because users
   type their names as the keywords they remember.
2. **Stages instead of team phases, as global playbooks.** Five work modes
   (Plan/Design/Develop/Test/Launch) replace the overloaded term "Phase"
   (which now exclusively means a project milestone). Their procedure
   content lives once, in
   `~/.claude/rcode/stages/{plan,design,develop,test,launch}.md`, no longer
   duplicated 5× across the team commands.
3. **Two tracker modes.** `github` (issues/milestones/labels) and `plan`
   (`P-NNN` checkbox lines in `BRAINSTORM.md`, no GitHub needed) — commands
   read `.rcode/config.json` → `tracker` instead of assuming GitHub.
4. **Proportional exit instead of a five-step exit contract.** The
   previous exit contract ran in full at the end of every command,
   regardless of whether anything had actually happened — among other
   things, `/develop-team`'s exit would have called `/phase-gate` with no
   defined N and blocked every non-final session (M11). Now: each of the 6
   possible exit steps fires only under its own condition (work happened,
   a unit's status changed, all units of the phase are closed, …).
5. **Backward-transitions rule demoted.** The backward-jump protocol
   (`rules/phase-backward-transitions.md`) claimed "not globally loaded",
   but sat in `rules/` and therefore was — ~1.2K tokens in every session of
   every project, even though only R.Code Stage work ever needs it. Moved
   to `~/.claude/rcode/stages/backward-transitions.md`, referenced by the
   Stage playbooks instead of always loaded.
6. Additionally, in detail: two worker modes for `/issue` (A1 — standalone
   vs. dispatched worker, the latter without its own branch/PR), an
   env-key preflight before the first dispatch of a unit chain (A11,
   IMP-169), two-stage ADRs (inline in `ARCHITECTURE.md` at the design
   decision, filed to `docs/adr/` once finalized — A5), and the watchdog
   side-finding M22/A8.

## Consequences

**Gets easier:** the Stage procedure lives once instead of 5× — a change
hits all five aliases at once, no more drift possible. Projects without
GitHub (measured: 2 of 5) can use R.Code fully. Every session of every
project saves the ~1.2K tokens of the backward-jump protocol that is no
longer always loaded. `/rcode-upgrade` stamps no longer rot uncommitted. A
worker dispatched into a shared wave now has a documented protocol that
matches actual practice (one branch per wave, not one branch per unit)
instead of ignoring it.

**Gets harder:** five alias commands remain as doors (not deleted), even
though practice shows almost nobody calls them directly — a deliberate,
permanent small redundancy cost, because users know and type their names
as keywords. The old `phase-N` naming (labels, milestones, tags) is kept
for compatibility reasons, even though "Phase" now exclusively means a
milestone and may no longer be used for team tiers — two closely related
terms remain side by side, with the glossary as the only disambiguation
aid.

**Open questions, not decided here (A15):**

- `/autonomous-overnight` still has **0** invocations, while the one real
  overnight run happened via `/team-lead` plus the agency-bands escalation
  queue. Whether `/autonomous-overnight` has standalone value over that
  combination is undecided — a follow-up task, not part of this rework.
- `CONTEXT.md` adoption sits at ~0% across the real projects, even though
  the rule has been globally loaded since 2026-08-03 (A6 scales the
  ambition down accordingly: only a stub at init, seeding at
  brainstorm/migrate — no retroactive backfill).
- The `/rcode-upgrade` commit invariant was deliberately changed (A9, from
  "never commit" to "commit after one y/n") — this ADR is the authoritative
  record of that behavior change.
- The retention period for handoff snapshots
  (`.rcode/handoff-<date>-<session>.md`, A14) is open, not built in this
  rework.

**Revisit when:** the `plan` tracker-mode practice yields signal across
more than 2 projects; `/autonomous-overnight` usage (should it ever rise
above 0) can be re-evaluated against the `/team-lead` queueing alternative;
`CONTEXT.md` adoption is measured again.
