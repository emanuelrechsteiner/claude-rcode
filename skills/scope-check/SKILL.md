---
name: scope-check
description: "This skill should be used when the user asks to 'check scope', 'scope check', 'verify scope', 'scope review', or mentions 'scope creep', 'scope shrinkage', 'out of scope', 'scope prüfen', 'scope kontrolle', 'bleiben wir im scope', 'zu viel gemacht', 'haben wir uns verzettelt', 'while we are here', 'mission creep', 'feature creep'. It verifies work matches the original plan by detecting unplanned additions (scope creep) and dropped features (scope shrinkage). Works at per-issue and per-phase granularity."
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

- **Per-Issue Mode:** When called during `/issue` or with a specific issue number
- **Per-Phase Mode:** When called during `/phase-gate` or with a phase number
- **General Mode:** When called without specific context — check the current branch/PR

---

## Per-Issue Mode

### Input
- Issue number (from context or argument)
- Current branch (from `git branch --show-current`)

### Process

#### 1. Read Issue Scope

```bash
gh issue view [issue-number] --json body
```

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
- **Is this file related to the issue's scope?** (YES/NO/UNCLEAR)
- **Is this file mentioned in the issue plan?** (YES/NO)
- **Could this change belong to a different issue?** (YES/NO)

Flag files that are:
- Not mentioned in the issue's technical details
- In directories unrelated to the issue's feature area
- Shared utilities modified without clear justification

#### 4. Check for New Dependencies

```bash
# Check if package.json was modified
git diff main...HEAD -- package.json
```

- Were new npm packages added?
- Were they mentioned in the issue?
- Are they necessary for the acceptance criteria?

#### 5. Check Acceptance Criteria Coverage

For each acceptance criterion:
- Is there code that implements it?
- Is there a test that verifies it?

Flag:
- **Missing criteria** (acceptance criteria without corresponding code)
- **Extra work** (significant code without corresponding criteria)

### Verdict

```markdown
# Scope Check — Issue #[N]

## Files Analyzed: [N]

### In Scope: [N] files
- [file1.ts] — [Related to: acceptance criterion 1]
- [file2.ts] — [Related to: acceptance criterion 2]

### Scope Concern: [N] files
- [file3.ts] — WARNING: Not mentioned in issue plan. Justification needed.
- [shared/util.ts] — WARNING: Shared utility modified. Could affect other issues.

### Out of Scope: [N] files
- [unrelated.ts] — VIOLATION: Not related to this issue.

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
2. Create separate issues for out-of-scope work
3. Address missing acceptance criteria
```

---

## Per-Phase Mode

### Input
- Phase number (from context or argument)

### Process

#### 1. Read Scope Manifest

```
Read .rcode/scope-manifest.json
```

Filter to features assigned to this phase.

#### 2. Check Feature Completion

For each feature in this phase:

```bash
# Get all issues for this feature
# Cross-reference with GitHub state
gh issue list --milestone "Phase [N]" --state all --json number,title,state
```

- Are all feature issues closed?
- Are there open issues that should be closed?
- Are there closed issues that weren't in the original plan?

#### 3. Check for Scope Creep

```bash
# Commits since last phase tag
git log --oneline v0.[N-1].0..HEAD
```

- Do all commits reference planned issues?
- Are there commits for unplanned work?

#### 4. Check for Scope Shrinkage

- Are all planned features accounted for?
- Were any features dropped without a scope change record?

#### 5. Check Scope Changes

Read the `scope_changes` array in scope-manifest.json:
- Are all changes documented?
- Are all changes approved?

### Verdict

```markdown
# Phase Scope Check — Phase [N]

## Features Planned: [N]
## Features Complete: [N]
## Features Missing: [N]

### Feature Status
| Feature | Issues | Closed | Status |
|---------|--------|--------|--------|
| F001 — [Name] | [N] | [N] | Complete / Incomplete / Dropped |

### Scope Creep Detection
- [N] unplanned commits detected
  - [commit hash] — [description] — NO LINKED ISSUE

### Scope Shrinkage Detection
- [N] planned features not delivered
  - F00[N] — [Name] — [N] issues still open

### Scope Changes
- [N] documented and approved
- [N] undocumented (VIOLATION)

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
  - Issues to add: [N]
  - Issues to remove: [N]
  - Phase affected: [N]
  - Timeline impact: [estimate]

This change requires HUMAN APPROVAL.
Do you approve this scope change? (yes/no)
```

### 2. If Approved

1. Update `.rcode/scope-manifest.json`:
   - Add entry to `scope_changes` array
   - Update feature issues lists
   - Update totals

2. Create/close GitHub issues as needed

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

**Manifest:** [Locked / Unlocked]
**Total Features:** [N]
**Features Complete:** [N] ([X]%)
**Scope Changes:** [N] (all approved: [Yes/No])

**Current Branch:** [branch name]
**Current Issue:** #[N] (inferred from branch name)
**Branch Scope:** [CLEAN / NEEDS CHECK]

Run with an issue number for detailed per-issue check.
Run with a phase number for phase-level check.
```
