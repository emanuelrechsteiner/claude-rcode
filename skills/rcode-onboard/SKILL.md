---
name: rcode-onboard
description: "This skill should be used when the user asks to 'onboard', 'get started', 'what should I work on', 'pick up project', 'where are we', 'continue project', 'what is the current state', 'wo stehen wir', or 'was ist der stand'. It reads project status, architecture, conventions, and recent agent activity to get a new agent productive in under 10 minutes on a R.Code-managed project."
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash(git log:*)
  - Bash(git status:*)
  - Bash(git branch:*)
  - Bash(git diff:*)
  - Bash(gh:*)
  - Bash(bash:*)
---

# R.Code Onboard — Agent Orientation Skill

This skill gets a new or returning agent oriented on a R.Code-managed project.

---

## Detection

Before running this protocol, verify this is a R.Code project:
- Check for `.rcode/` directory
- Check for `START_HERE.md` in project root
- Check for `PROJECT-STATUS.md` in project root

If none of these exist, inform the user this is not a R.Code-managed project and suggest running `/brainstorm` to initialize one.

---

## Cold Start Protocol (New Agent — No Prior Knowledge)

Execute these reads **in order**. Total target: ~10 minutes (steps 4, 6 and 8 are quick and skippable when nothing applies).

### 1. Read START_HERE.md (2 min)

**What you learn:** Project name, purpose, tech stack, current phase, key documents, setup steps.

```
Read START_HERE.md
```

### 2. Read PROJECT-STATUS.md (2 min)

**What you learn:** Progress by phase, available issues, blocked issues, recent activity.

```
Read PROJECT-STATUS.md
```

### 3. Read CONVENTIONS.md (2 min)

**What you learn:** Code patterns, naming rules, folder structure, testing patterns.

```
Read CONVENTIONS.md
```

### 4. Read CONTEXT.md — If Present (Tier 2)

**What you learn:** the project's shared-language glossary (domain terms coined at the 3rd circumlocution — see `~/.claude/rules/domain-docs-convention.md`). Once read, your own prose and any code names you introduce follow these terms.

```
Read CONTEXT.md
```

Not every project has one yet — if `CONTEXT.md` doesn't exist, skip this step.

### 5. Read ARCHITECTURE.md — Skim (2 min)

**What you learn:** Tech stack, ADR summaries, data flow, key patterns.

Focus on: Tech stack table, ADR titles and decisions (skip alternatives/consequences unless needed). ADRs live in two places — check both: `### ADR-NNN — <Title>` entries inline in this file (design-time decisions), and, once a decision is implemented/final, an immutable filed record at `docs/adr/NNNN-<slug>.md` (the inline entry then links to it).

```
Read ARCHITECTURE.md
```

### 6. Read Latest Phase Summary — If Any (1 min)

**What you learn:** What was built in the previous phase, decisions made, context for current phase.

```
# Find the latest phase summary
ls .rcode/phase-summaries/ | sort -V | tail -1

# Read it
Read .rcode/phase-summaries/[latest].md
```

If no phase summaries exist yet (early in Phase 1, or a project that hasn't run `/phase-gate`), skip this step.

### 7. Read Agent Log — Last 2 Entries (1 min)

**What you learn:** What the last agent was working on, decisions made, blockers, recommended next action.

```
Read .rcode/agent-log.md
```

Focus on the last 2 session entries only. Don't read the entire history.

### 8. Check Escalation Queue & Re-Entry Brief

**What you learn:** whether prior work left open ESCALATE-band operations awaiting a human y/n, or a backward Stage jump mid-flight.

```
# Both are the exception, not the rule — absence is the normal case
Read .rcode/escalation-queue.md
Read .rcode/re-entry-brief.md
```

If `.rcode/escalation-queue.md` exists, its open entries need a human decision before new work proceeds (see `~/.claude/rules/agency-bands.md`) — surface them first in the Onboarding Output below. If `.rcode/re-entry-brief.md` exists, a backward Stage jump (see `~/.claude/rcode/stages/backward-transitions.md`) is in progress — surface its `from_stage`/`to_stage` and change mandate. Neither file existing is healthy and normal — skip silently.

### 9. Gather Pending Structural / Un-ticketed Work (1 min)

**What you learn:** Architectural/structural changes (refactors, new folders, file extractions, ADR-worthy deviations) that have no GitHub issue and would otherwise evaporate from the summary.

Assemble from four sources:
1. **agent-log.md** — in the last 2 entries, scan for refactor / new-file / ADR / deviation notes.
2. **`.rcode/scope-manifest.json`** — read `scope_changes[]` entries.
3. **`.rcode/blocked-issues.md`** — note structural blockers.
4. **git diff vs last phase tag** — detect new files/dirs since the last phase:

```
# Latest v0.N.0 phase tag
git describe --tags --match "v0.*.0" --abbrev=0

# New/changed files since that tag
git diff --name-status [tag]..HEAD
```

### 10. Determine Tracker & Identify Next Work Unit

**What you learn:** which tracker this project uses, and the best next work unit to recommend.

Read `.rcode/config.json` → `tracker` (`github` or `plan`). Then get unit counts and Phase-completion state — this works for either tracker:

```
bash ~/.claude/scripts/status-metrics.sh "$PWD"
```

For a `plan`-tracker project, or to read an individual unit's body directly, read `BRAINSTORM.md` yourself: units appear either as checkbox lines under `### Phase N — <Name>` headings (`- [ ] P-012 — <Title> \`<type>\` \`<area>\``, `- [x]` = done) or as table rows whose first cell is the unit ID (`| P-001 | [Phase 1] <Title> | <Type> | <Area> | … |`) — different projects use one form or the other; read whichever is there.

From that, identify the next available work unit:
1. Must be in the **current active Phase** (project milestone — `.rcode/config.json` → `current_phase`)
2. Must be **unblocked** (no `blocked` label / `blocked-by:` marker, predecessors closed)
3. Prefer `parallel-safe` units if multiple are available
4. If a unit was "in progress" in the last agent log entry, continue it

---

## Warm Start Protocol (Returning Agent)

For agents returning to a project they've worked on before:

### 1. Read PROJECT-STATUS.md

Check for changes since last session.

### 2. Read Agent Log — Last Entry

Pick up where you left off. Check for:
- Was there a handoff?
- Are there stashed changes?
- What was the recommended next action?

### 3. Check CONVENTIONS.md and CONTEXT.md

Skim CONVENTIONS.md for new entries added by `/lessons` since last session. If `CONTEXT.md` exists, skim it too — new terms may have been coined since your last session.

### 4. Check Escalation Queue & Re-Entry Brief

Same check as Cold Start step 8 — read `.rcode/escalation-queue.md` and `.rcode/re-entry-brief.md` if present; both being absent is the normal, healthy case.

### 5. Gather Pending Structural / Un-ticketed Work

Assemble from four sources: (a) agent-log.md last entry (the one read in step 2) — scan for refactor / new-file / ADR / deviation notes; (b) `.rcode/scope-manifest.json` → `scope_changes[]`; (c) `.rcode/blocked-issues.md` structural blockers; (d) `git diff --name-status [latest v0.N.0 phase tag]..HEAD` for new files/dirs since the last phase. See Cold Start step 9 for the commands.

### 6. Resume Work

Read `.rcode/config.json` → `tracker`, then continue with the next work unit or the in-progress unit from the last session (see Cold Start step 10 for how to find it).

---

## Onboarding Output

After completing the protocol, output a structured summary:

```markdown
# Onboarding Summary

**Project:** [Name]
**Stack:** [Key technologies]
**Tracker:** [github / plan]
**Phase:** [N] of [M] — [Name] — [X]% complete

## Open Escalations / Re-Entry
[Include this section ONLY when `.rcode/escalation-queue.md` or `.rcode/re-entry-brief.md` exist — omit entirely otherwise]
- Escalation queue: [N] open entries — [one line each: op, why-now]
- Re-entry brief: Stage [from] → [to] ([iteration / drawing-board]) — [change mandate, one line]

## Current State
- [N] work units completed overall
- [N] work units remaining in current phase
- [N] work units blocked

## Last Agent Activity
- **Date:** [date]
- **Worked on:** [#N or P-NNN] — [Title]
- **State:** [Completed / In Progress / Handed off]
- **Recommended next:** [Action from agent log]

## Pending Structural / Un-ticketed Work
- [what changed] · [where it lives: file/dir] · [has unit/ADR? yes/no] · [needs ticketing?]
- ...

(If none: `None — all recent work is unit-tracked.`)

> Items here likely need a work unit or ADR via the scope rule's "It's Too Hard" channel before anything is built on top of them.

## My Recommended Next Action
`/team-lead "<concrete directive>"`
- Binds: [the work unit IDs the directive would bind, e.g. `#42, #43` or `P-012, P-013`]
- Stage: [Plan/Design/Develop/Test/Launch — the Stage `/team-lead` would infer for this directive]
- Reason: [Why these units, why now]

Ready to begin — run the directive above. `/team-lead` re-derives state itself and dispatches through the matching Stage playbook; a single unit can still be worked directly via `/issue <unit-id>` (see `~/.claude/commands/issue.md`, standalone mode) when that's genuinely all that's needed.
```

---

## Context Tier Reference

As you work, load additional documents based on need:

| Tier | Documents | When to Load |
|------|-----------|-------------|
| 1 (Always) | START_HERE.md, PROJECT-STATUS.md | Every session |
| 2 (Active) | CONVENTIONS.md, CONTEXT.md, agent-log.md, current work unit | When writing code |
| 3 (On Demand) | ARCHITECTURE.md, SPECIFICATION.md, phase summaries | When making decisions |
| 4 (Reference) | BRAINSTORM.md, RESEARCH_FINDINGS.md | Rarely — for deep context |

Never try to load all documents at once. Use the tier system to manage context window efficiently.
