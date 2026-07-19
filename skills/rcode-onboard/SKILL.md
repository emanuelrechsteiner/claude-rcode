---
name: rcode-onboard
description: "This skill should be used when the user asks to 'onboard', 'get started', 'what should I work on', 'pick up project', 'where are we', 'continue project', or 'what is the current state'. It reads project status, architecture, conventions, and recent agent activity to get a new agent productive in under 10 minutes on a R.Code-managed project."
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash(git log:*)
  - Bash(git status:*)
  - Bash(git branch:*)
  - Bash(git diff:*)
  - Bash(gh:*)
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

Execute these reads **in order**. Total target: ~10 minutes (steps 5 and 7 are quick and skippable when nothing applies).

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

### 4. Read ARCHITECTURE.md — Skim (2 min)

**What you learn:** Tech stack, ADR summaries, data flow, key patterns.

Focus on: Tech stack table, ADR titles and decisions (skip alternatives/consequences unless needed).

```
Read ARCHITECTURE.md
```

### 5. Read Latest Phase Summary (1 min)

**What you learn:** What was built in the previous phase, decisions made, context for current phase.

```
# Find the latest phase summary
ls .rcode/phase-summaries/ | sort -V | tail -1

# Read it
Read .rcode/phase-summaries/[latest].md
```

If no phase summaries exist (Phase 1 not yet complete), skip this step.

### 6. Read Agent Log — Last 2 Entries (1 min)

**What you learn:** What the last agent was working on, decisions made, blockers, recommended next action.

```
Read .rcode/agent-log.md
```

Focus on the last 2 session entries only. Don't read the entire history.

### 7. Gather Pending Structural / Un-ticketed Work (1 min)

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

### 8. Identify Next Issue

From PROJECT-STATUS.md, identify the next available issue:
1. Must be in the **current active phase**
2. Must be **unblocked** (no `blocked` label, predecessors closed)
3. Prefer `parallel-safe` issues if multiple are available
4. If an issue was "in progress" in the last agent log entry, continue it

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

### 3. Check CONVENTIONS.md

Skim for new entries added by `/lessons` since last session.

### 4. Gather Pending Structural / Un-ticketed Work

Assemble from four sources: (a) agent-log.md last entry (the one read in step 2) — scan for refactor / new-file / ADR / deviation notes; (b) `.rcode/scope-manifest.json` → `scope_changes[]`; (c) `.rcode/blocked-issues.md` structural blockers; (d) `git diff --name-status [latest v0.N.0 phase tag]..HEAD` for new files/dirs since the last phase. See Cold Start step 7 for the commands.

### 5. Resume Work

Continue with the next issue or the in-progress issue from the last session.

---

## Onboarding Output

After completing the protocol, output a structured summary:

```markdown
# Onboarding Summary

**Project:** [Name]
**Stack:** [Key technologies]
**Phase:** [N] of [M] — [Name] — [X]% complete

## Current State
- [N] issues completed overall
- [N] issues remaining in current phase
- [N] issues blocked

## Last Agent Activity
- **Date:** [date]
- **Worked on:** #[N] — [Title]
- **State:** [Completed / In Progress / Handed off]
- **Recommended next:** [Action from agent log]

## Pending Structural / Un-ticketed Work
- [what changed] · [where it lives: file/dir] · [has issue/ADR? yes/no] · [needs ticketing?]
- ...

(If none: `None — all recent work is issue-tracked.`)

> Items here likely need an issue or ADR via the scope rule's "It's Too Hard" channel before anything is built on top of them.

## My Recommended Next Action
**Issue #[N]** — [Title]
- Type: [feat/fix/...]
- Phase: [N]
- Parallel-safe: [Yes/No]
- Reason: [Why this issue is the best next step]

Ready to begin. Run `/issue [N]` to start.
```

---

## Context Tier Reference

As you work, load additional documents based on need:

| Tier | Documents | When to Load |
|------|-----------|-------------|
| 1 (Always) | START_HERE.md, PROJECT-STATUS.md | Every session |
| 2 (Active) | CONVENTIONS.md, agent-log.md, current issue | When writing code |
| 3 (On Demand) | ARCHITECTURE.md, SPECIFICATION.md, phase summaries | When making decisions |
| 4 (Reference) | BRAINSTORM.md, RESEARCH_FINDINGS.md | Rarely — for deep context |

Never try to load all documents at once. Use the tier system to manage context window efficiently.
