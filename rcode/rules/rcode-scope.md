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
- Each feature maps to specific work units (`#N` in tracker `github`, `P-NNN` in tracker `plan` — the manifest's `issues` array holds unit IDs in whichever form the project's tracker uses; the field name stays `issues` for compatibility, see `.rcode/config.json`)
- The manifest is **locked** after decompose (`"locked": true`)
- A `scope-lock-<date>` git tag marks the lock point
- **No agent can modify the locked manifest without human approval**

### Layer 2: Implementation Time (`/issue`)

When a work unit is picked up — either standalone (`/issue <unit>` invoked directly) or as a worker dispatched by `/team-lead` (see `~/.claude/commands/issue.md` for the two modes):

- Agent reads the unit's **Scope Boundary** section
- Agent explicitly states: "I WILL implement: [list]" and "I will NOT implement: [list]"
- Agent verifies the unit belongs to the **current active phase**
- Agent confirms no predecessor units are still open
- Any temptation to add "while I'm here" changes is **rejected**

### Layer 3: Review Time (`/rcode-review`)

When a change is reviewed before merge — a GitHub PR (tracker `github`, via `gh pr ...`) or a branch diff against trunk (tracker `plan` / no remote, via `git diff <trunk>...<branch>` + the unit's body from BRAINSTORM.md):

- Reviewer reads the linked unit's scope boundary
- `git diff` is analyzed against the scope — every changed file must relate to the unit
- **Scope creep flags**: New files not mentioned in the unit, new dependencies not planned, changes to files owned by other units
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

The shape above is tracker-agnostic — `issues` (and `issues_added`/`issues_removed` below) hold `10, 11, …` in tracker `github` or `"P-010", "P-011", …` in tracker `plan`. The example uses bare numbers because that is the common case; the field names never change between trackers.

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

### Step 3: Create Work Units

- Tracker `github`: create new issues for added scope; close removed issues with `wontfix` label and explanation; update milestone assignments
- Tracker `plan`: append new `P-NNN` lines for added scope under the right `### Phase N` heading in BRAINSTORM.md; mark removed units with a strike-through and the reason inline (never delete the line)

### Step 4: Update Status

- Update PROJECT-STATUS.md with new totals
- Update BRAINSTORM.md with the new units
- Update START_HERE.md current status

### Step 5: Commit with Justification

```bash
git commit -m "docs(scope): approved scope change SC001 - add push notifications

Justification: User research showed 78% of target users expect
push notifications for event reminders.

Approved by: human
Units added: #48, #49, #50
Units removed: none"
```

(tracker `plan`: `Units added: P-048, P-049, P-050`)

---

## Scope Verification Checklists

### Per-Unit Scope Check (Before Creating a PR / Handing Back to the Lead)

- [ ] All acceptance criteria from the unit are implemented
- [ ] No files outside the unit's scope were modified (except shared utilities with justification)
- [ ] No new dependencies were added that weren't mentioned in the unit
- [ ] No new features were added that aren't in the acceptance criteria
- [ ] The implementation matches the architectural approach from the unit's "Architectural Context"
- [ ] Test coverage addresses all scenarios in the acceptance criteria

### Per-Phase Scope Check (Before Phase Gate)

- [ ] All units assigned to this Phase are closed
- [ ] All features planned for this Phase are complete (check scope-manifest.json)
- [ ] No features from future Phases were implemented early
- [ ] No planned features were silently dropped
- [ ] All scope changes are documented in scope-manifest.json with approvals

### Per-Project Scope Check (Before Final Release)

- [ ] All features in scope-manifest.json have status "complete"
- [ ] All scope changes are documented and approved
- [ ] No orphaned units (units not linked to any feature)
- [ ] Total delivered matches total planned (adjusted for approved changes)

---

## Common Scope Violations

### "While I'm Here" Anti-Pattern

```
VIOLATION: Agent fixing unit #42 (login bug) also refactors the
navigation component because "it was nearby and looked messy."

CORRECT: Agent creates a new unit for the navigation refactor,
references it in the PR description, and focuses only on #42.
```

### "It Would Be Nice" Anti-Pattern

```
VIOLATION: Agent implementing unit #30 (user profile page) also
adds a "dark mode toggle" because "users would appreciate it."

CORRECT: Agent implements exactly what #30 specifies. If dark mode
is desired, it goes through the scope change protocol.
```

### "It's Too Hard" Anti-Pattern

```
VIOLATION: Agent working on unit #55 (real-time notifications)
implements polling instead of WebSockets because "it's simpler"
without documenting the deviation.

CORRECT: Agent documents the architectural deviation, creates an
ADR, and gets human approval for the changed approach. The unit's
acceptance criteria are updated to reflect the new approach.
```

### "It's Obviously Wrong" Anti-Pattern

```
VIOLATION: Agent discovers a typo in the SPECIFICATION.md and
fixes it while working on an unrelated unit.

CORRECT: Agent creates a new unit for the documentation fix.
Even typo fixes should be tracked for accountability.
Exception: Obvious typos in code comments within the file you're
already modifying are acceptable.
```

---

## Scope Discipline Mantras

1. **"If it's not in the unit, it's not in the branch."**
2. **"New ideas are new units."**
3. **"The manifest is the truth. The code must match the manifest."**
4. **"No agent is smarter than the plan. The plan was approved by the human."**
5. **"Scope changes require human approval. Always. No exceptions."**
