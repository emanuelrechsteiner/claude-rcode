# R.Code Workflow — Scope Discipline Rules

> These rules enforce strict scope management across the entire project lifecycle.
> Import via `@.claude/rules/rcode-scope.md` in your project's CLAUDE.md.

---

## The Scope Problem

In long-running projects with multiple agents, scope drift is the #1 quality killer:

- **Scope creep**: Agents add "helpful" features not in the original plan
- **Scope shrinkage**: Agents skip planned features because they seem hard or unnecessary
- **Scope mutation**: Requirements subtly change without documentation

R.Code enforces scope discipline through **three layers of verification**.

---

## Three Layers of Scope Enforcement

### Layer 1: Definition Time (`/decompose`)

When the scope manifest is created and locked:

- Every feature from SPECIFICATION.md gets an entry in `scope-manifest.json`
- Each feature maps to specific GitHub issues
- The manifest is **locked** after decompose (`"locked": true`)
- A `scope-lock-<date>` git tag marks the lock point
- **No agent can modify the locked manifest without human approval**

### Layer 2: Implementation Time (`/issue`)

When an agent starts working on an issue:

- Agent reads the issue's **Scope Boundary** section
- Agent explicitly states: "I WILL implement: [list]" and "I will NOT implement: [list]"
- Agent verifies the issue belongs to the **current active phase**
- Agent confirms no predecessor issues are still open
- Any temptation to add "while I'm here" changes is **rejected**

### Layer 3: Review Time (`/review`)

When a PR is reviewed before merge:

- Reviewer reads the linked issue's scope boundary
- `git diff` is analyzed against the scope — every changed file must relate to the issue
- **Scope creep flags**: New files not mentioned in issue, new dependencies not planned, changes to files owned by other issues
- **Scope shrinkage flags**: Acceptance criteria not addressed in code, missing test coverage for required scenarios
- Verdict: CLEAN / WARNING / VIOLATION

---

## Scope Manifest Format

The canonical scope tracker lives at `.rcode/scope-manifest.json`:

```json
{
  "project_name": "Project Name",
  "created_date": "2026-03-01",
  "version": "1.0.0",
  "locked": true,
  "locked_date": "2026-03-01",
  "total_issues": 47,
  "total_features": 5,
  "features": [
    {
      "id": "F001",
      "name": "User Authentication",
      "description": "JWT-based auth with email/password and OAuth",
      "phase": 2,
      "issues": [10, 11, 12, 13, 14],
      "status": "in_progress",
      "scope_boundary": "Authentication and session management ONLY. Does NOT include user profile, preferences, or admin roles."
    }
  ],
  "scope_changes": []
}
```

---

## Scope Change Protocol

When scope must change (new requirements, technical discovery, pivot):

### Step 1: Human Approval Required

**No agent can unilaterally change scope.** The agent must:

1. Document the proposed change with justification
2. Present to the human for approval
3. Wait for explicit "approved" response

### Step 2: Record in Manifest

After human approval:

```json
{
  "scope_changes": [
    {
      "id": "SC001",
      "date": "2026-03-15",
      "type": "addition",
      "feature": "F006-push-notifications",
      "justification": "User research showed 78% of target users expect push notifications for event reminders",
      "approved_by": "human",
      "issues_added": [48, 49, 50],
      "issues_removed": []
    }
  ]
}
```

### Step 3: Create GitHub Issues

- Create new issues for added scope
- Close removed issues with `wontfix` label and explanation
- Update milestone assignments

### Step 4: Update Status

- Update PROJECT-STATUS.md with new totals
- Update BRAINSTORM.md with new issues
- Update START_HERE.md current status

### Step 5: Commit with Justification

```bash
git commit -m "docs(scope): approved scope change SC001 - add push notifications

Justification: User research showed 78% of target users expect
push notifications for event reminders.

Approved by: human
Issues added: #48, #49, #50
Issues removed: none"
```

---

## Scope Verification Checklists

### Per-Issue Scope Check (Before Creating PR)

- [ ] All acceptance criteria from the issue are implemented
- [ ] No files outside the issue's scope were modified (except shared utilities with justification)
- [ ] No new dependencies were added that weren't mentioned in the issue
- [ ] No new features were added that aren't in the acceptance criteria
- [ ] The implementation matches the architectural approach from the issue's "Architectural Context"
- [ ] Test coverage addresses all scenarios in the acceptance criteria

### Per-Phase Scope Check (Before Phase Gate)

- [ ] All issues assigned to this phase are closed
- [ ] All features planned for this phase are complete (check scope-manifest.json)
- [ ] No features from future phases were implemented early
- [ ] No planned features were silently dropped
- [ ] All scope changes are documented in scope-manifest.json with approvals

### Per-Project Scope Check (Before Final Release)

- [ ] All features in scope-manifest.json have status "complete"
- [ ] All scope changes are documented and approved
- [ ] No orphaned issues (issues not linked to any feature)
- [ ] Total delivered matches total planned (adjusted for approved changes)

---

## Common Scope Violations

### "While I'm Here" Anti-Pattern

```
VIOLATION: Agent fixing issue #42 (login bug) also refactors the
navigation component because "it was nearby and looked messy."

CORRECT: Agent creates a new issue for the navigation refactor,
references it in the PR description, and focuses only on #42.
```

### "It Would Be Nice" Anti-Pattern

```
VIOLATION: Agent implementing issue #30 (user profile page) also
adds a "dark mode toggle" because "users would appreciate it."

CORRECT: Agent implements exactly what #30 specifies. If dark mode
is desired, it goes through the scope change protocol.
```

### "It's Too Hard" Anti-Pattern

```
VIOLATION: Agent working on issue #55 (real-time notifications)
implements polling instead of WebSockets because "it's simpler"
without documenting the deviation.

CORRECT: Agent documents the architectural deviation, creates an
ADR, and gets human approval for the changed approach. The issue's
acceptance criteria are updated to reflect the new approach.
```

### "It's Obviously Wrong" Anti-Pattern

```
VIOLATION: Agent discovers a typo in the SPECIFICATION.md and
fixes it while working on an unrelated issue.

CORRECT: Agent creates a new issue for the documentation fix.
Even typo fixes should be tracked for accountability.
Exception: Obvious typos in code comments within the file you're
already modifying are acceptable.
```

---

## Scope Discipline Mantras

1. **"If it's not in the issue, it's not in the branch."**
2. **"New ideas are new issues."**
3. **"The manifest is the truth. The code must match the manifest."**
4. **"No agent is smarter than the plan. The plan was approved by the human."**
5. **"Scope changes require human approval. Always. No exceptions."**
