---
name: scope-check
description: "This skill should be used when the user asks to 'check scope', 'scope check', 'verify scope', 'scope review', or mentions 'scope creep', 'scope shrinkage', 'out of scope', 'scope prüfen', 'scope kontrolle', 'bleiben wir im scope', 'zu viel gemacht', 'haben wir uns verzettelt', 'while we are here', 'mission creep', 'feature creep'. It verifies work matches the original plan by detecting unplanned additions (scope creep) and dropped features (scope shrinkage). Works at per-unit and per-phase granularity, tracker-aware (github issues or plan P-NNN units)."
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash(git diff:*)
  - Bash(git log:*)
  - Bash(gh:*)
---

# R.Code Scope Check — Scope Guardian Skill

This skill verifies that work stays within the planned scope. It operates in two modes:

---

## Mode Detection

Determine the mode based on context:

- **Per-Unit Mode:** When called during `/issue`, during `~/.claude/commands/rcode-review.md`'s scope-verification step, or with a specific work unit ID (`#N` github, `P-NNN` plan)
- **Per-Phase Mode:** When called during `/phase-gate` or with a Phase number. **Phase** here is the glossary term — a project milestone (1..N) — never `/issue`'s Steps 0–9 or a `/team-lead` Stage.
- **General Mode:** When called without specific context — check the current branch/PR

Tracker (`github` or `plan`) comes from `.rcode/config.json` → `tracker`. If unset, infer it: `github` iff a git remote exists AND `gh auth status` succeeds AND at least one GitHub issue exists, else `plan` — and say so in the output ("tracker not set in .rcode/config.json — inferred `<x>`").

---

## Per-Unit Mode

### Input
- Work unit ID (from context or argument) — `#N` (github) or `P-NNN` (plan)
- Current branch (from `git branch --show-current`; matches `<type>/issue-<N>-<desc>` for github units or `<type>/p-<NNN>-<desc>` for plan units, case-insensitive)

### Process

#### 1. Read Unit Scope

`github` tracker:
```bash
gh issue view [issue-number] --json body
```

`plan` tracker — read the unit's line + indented body from `BRAINSTORM.md`. Two forms occur, read whichever is there:
- checkbox: `- [ ] P-012 — <Title> \`<type>\` \`<area>\`` with indented body lines below it (Description / Acceptance / Scope boundary / Requires env)
- table row whose first cell is the ID: `| P-001 | [Phase 1] <Title> | <Type> | <Area> | … |` — scope/acceptance info lives in that row's own columns, or in prose immediately around the table if the table doesn't carry it

Extract:
- **IN SCOPE** section — what should be changed
- **OUT OF SCOPE** section — what should NOT be changed
- **Acceptance Criteria** — what must be delivered

#### 2. Analyze Changes

```bash
# All files changed on this branch vs main
git diff main...HEAD --stat
git diff main...HEAD --name-only
```

#### 3. Verify Each Changed File

For every file in the diff:
- **Is this file related to the unit's scope?** (YES/NO/UNCLEAR)
- **Is this file mentioned in the unit's plan?** (YES/NO)
- **Could this change belong to a different unit?** (YES/NO)

Flag files that are:
- Not mentioned in the unit's technical details
- In directories unrelated to the unit's feature area
- Shared utilities modified without clear justification (if the justification points at an architectural decision, check both ADR locations — see Per-Phase Mode step 5, "Check Scope Changes & ADR Coverage" — before flagging as unjustified)

#### 4. Check for New Dependencies

```bash
# Check if the project's dependency manifest was modified — project-specific
# (package.json, requirements.txt, Package.swift, go.mod, ...)
git diff main...HEAD -- <dependency-manifest>
```

- Were new dependencies added?
- Were they mentioned in the unit's plan?
- Are they necessary for the acceptance criteria?

#### 5. Check Acceptance Criteria Coverage

For each acceptance criterion:
- Is there code that implements it?
- Is there a test that verifies it (the project's check trio — CLAUDE.md → Mandatory Pre-Commit — is what actually enforces this at commit time)?

Flag:
- **Missing criteria** (acceptance criteria without corresponding code)
- **Extra work** (significant code without corresponding criteria)

### Verdict

```markdown
# Scope Check — Unit [#N or P-NNN]

## Files Analyzed: [N]

### In Scope: [N] files
- [file1.ts] — [Related to: acceptance criterion 1]
- [file2.ts] — [Related to: acceptance criterion 2]

### Scope Concern: [N] files
- [file3.ts] — WARNING: Not mentioned in unit plan. Justification needed.
- [shared/util.ts] — WARNING: Shared utility modified. Could affect other units.

### Out of Scope: [N] files
- [unrelated.ts] — VIOLATION: Not related to this unit.

### Acceptance Criteria Coverage
- [x] Criterion 1 — Covered in [file.ts]
- [x] Criterion 2 — Covered in [file.ts]
- [ ] Criterion 3 — NOT COVERED (scope shrinkage!)

### New Dependencies
- [package-name] — [Justified / Not in plan]

## Verdict: CLEAN / WARNING / VIOLATION

### If VIOLATION:
Recommended action:
1. Remove out-of-scope changes from this branch
2. Create separate work units for out-of-scope work (github issue or plan `P-NNN`, per this project's tracker)
3. Address missing acceptance criteria
```

---

## Per-Phase Mode

**Phase** here is always the glossary meaning — a project milestone (1..N) — never `/issue`'s Steps 0–9 or a `/team-lead` Stage.

### Input
- Phase number (from context or argument)

### Process

#### 1. Read Scope Manifest

```
Read .rcode/scope-manifest.json
```

Filter to features assigned to this phase.

#### 2. Check Feature Completion

For each feature in this phase, get the unit states:

`github` tracker:
```bash
gh issue list --milestone "Phase [N]" --state all --json number,title,state
```

`plan` tracker — read `BRAINSTORM.md`. Units for this Phase are either checkbox lines under a `### Phase N — <Name>` heading, or table rows whose title cell/text carries a `[Phase N]` prefix (else the nearest preceding heading containing `Phase N`). Completion: checkbox `[x]` → closed; table row with a `Status`/`State` column (case-insensitive) whose value matches `done|closed|complete|completed|✅|x` → closed, any other value → open; a table WITHOUT such a column → completion **unknown** for those units — report `closed: unknown` and a finding ("completion not recorded for N units — add a Status column or checkboxes"), never a fabricated 0 or 100%.

- Are all feature units closed?
- Are there open units that should be closed?
- Are there closed units that weren't in the original plan?

#### 3. Check for Scope Creep

```bash
# Commits since last phase tag
git log --oneline v0.[N-1].0..HEAD
```

- Do all commits reference planned units? Accept both trackers, incl. ranges and comma lists: `(closes|refs) (#[0-9]+|P-[0-9]{3,}(\.\.P-[0-9]{3,})?)((, ?)(#[0-9]+|P-[0-9]{3,}(\.\.P-[0-9]{3,})?))*` (e.g. `refs P-051..P-105`, `refs P-085, P-100`).
- Are there commits for unplanned work?

#### 4. Check for Scope Shrinkage

- Are all planned features accounted for?
- Were any features dropped without a scope change record?

#### 5. Check Scope Changes & ADR Coverage

Read the `scope_changes` array in scope-manifest.json:
- Are all changes documented?
- Are all changes approved?

For any scope change or architectural deviation flagged above, check for an ADR in **both** places before flagging it as undocumented: an inline `### ADR-NNN — <Title>` entry in `ARCHITECTURE.md` (design-time), or an immutable filed record at `docs/adr/NNNN-<slug>.md` (implemented/final — the inline entry then links to it). Only flag VIOLATION if the decision appears in neither.

### Verdict

```markdown
# Phase Scope Check — Phase [N] (tracker: github | plan)

## Features Planned: [N]
## Features Complete: [N]
## Features Missing: [N]

### Feature Status
| Feature | Units | Closed | Status |
|---------|-------|--------|--------|
| F001 — [Name] | [N] | [N or "unknown"] | Complete / Incomplete / Dropped / Unknown |

### Scope Creep Detection
- [N] unplanned commits detected
  - [commit hash] — [description] — NO LINKED UNIT

### Scope Shrinkage Detection
- [N] planned features not delivered
  - F00[N] — [Name] — [N] units still open

### Scope Changes & ADR Coverage
- [N] documented and approved
- [N] undocumented (VIOLATION) — checked both ADR locations before flagging

## Verdict: CLEAN / WARNING / VIOLATION
```

---

## Scope Change Protocol

If a scope change is needed (detected or requested):

### 1. Document the Change

Present to the user:

```
SCOPE CHANGE REQUEST

Type: Addition / Removal / Modification
Feature: [Feature ID and name]
Justification: [Why this change is needed]

Impact:
  - Units to add: [N]
  - Units to remove: [N]
  - Phase affected: [N]
  - Timeline impact: [estimate]

This change requires HUMAN APPROVAL.
Do you approve this scope change? (yes/no)
```

### 2. If Approved

1. Update `.rcode/scope-manifest.json`:
   - Add entry to `scope_changes` array
   - Update feature unit lists
   - Update totals

2. Create/close work units as needed — GitHub issues (`github` tracker) or `BRAINSTORM.md` checkbox lines (`plan` tracker)

3. Update PROJECT-STATUS.md

4. Commit:
   ```bash
   git commit -m "docs(scope): approved scope change SC[NNN] — [brief description]"
   ```

### 3. If Rejected

Document the rejection:
```
Scope change REJECTED. Original scope maintained.
The current plan remains the authoritative source.
```

---

## Quick Scope Health Report

When called without specific context, provide a general health report:

```markdown
# Scope Health Report

**Tracker:** [github / plan]
**Manifest:** [Locked / Unlocked]
**Total Features:** [N]
**Features Complete:** [N] ([X]%)
**Scope Changes:** [N] (all approved: [Yes/No])

**Current Branch:** [branch name]
**Current Work Unit:** [#N or P-NNN] (inferred from the branch name — `.../issue-<N>-...` or `.../p-<NNN>-...`, case-insensitive)
**Branch Scope:** [CLEAN / NEEDS CHECK]

Run with a work unit ID for detailed per-unit check.
Run with a phase number for phase-level check.
```
