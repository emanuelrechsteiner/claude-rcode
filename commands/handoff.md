---
description: "Create a context handoff document when switching agents or ending a session. Run before ending work or switching to a different agent."
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash(git:*)
  - Bash(gh:*)
  - Glob
  - Grep
---

<!-- controller-contract:v1 exempt="read-only/mechanical, no agent dispatch" -->

# R.Code Handoff — Agent Context Transfer

You are executing the R.Code `/handoff` command. This captures the current session's state so the next agent can continue seamlessly.

---

## Step 1: CAPTURE STATE

### Uncommitted Changes

```bash
git status
git diff --stat
```

**If there are uncommitted changes:**
- If the work is complete enough to commit: commit with proper format
- If the work is in-progress: `git stash save "WIP: issue-[N] — [description]"`
- Document the state clearly in the handoff

### Active Branches

```bash
git branch --list
git log --oneline -5  # Recent commits on current branch
```

### In-Progress Units

Tracker-aware (`.rcode/config.json` `.tracker`; if unset, resolve it the way
`~/.claude/scripts/rcode-units.sh` does, A3):

```bash
# tracker: github
gh issue list --state open --label "rcode" --json number,title,labels
gh pr list --state open --json number,title,headRefName

# tracker: plan — read open (unticked) units directly from BRAINSTORM.md
# (A2 grammar); no gh calls.
```

---

## Step 2: DOCUMENT DECISIONS

Review what was done in this session and document:

### New ADRs
Were any architectural decisions made? List them with ADR numbers — check
both the inline `### ADR-NNN` entries in `ARCHITECTURE.md` and filed
`docs/adr/NNNN-*.md` (two-tier model, A5). Filing is `/lessons`'s job; a
handoff only records that a decision was made and where.

### New Patterns
Were any new code patterns introduced that should be added to CONVENTIONS.md?

### Modified Conventions
Were any existing conventions updated or discovered to be insufficient?

### Pending Questions
Are there questions that need human input before work can continue?

---

## Step 3: DOCUMENT BLOCKERS

### Technical Blockers
Units that are blocked by technical problems (failing tests, dependency issues, etc.)

### External Blockers
Units waiting on external services, API access, human decisions, etc.

### Update `.rcode/blocked-issues.md`
If there are new blockers, add them to the blocked issues file.

---

## Step 4: APPEND TO AGENT LOG

`/handoff` is one of the single writers of `.rcode/agent-log.md` (A12 —
dispatched workers never write it; rare cross-worktree conflicts are
resolved with the `resolving-merge-conflicts` skill, keeping both entries in
timestamp order).

Append a structured entry to `.rcode/agent-log.md`:

```markdown
---

## Session: [Date] — [Agent Identifier]

**Date:** [YYYY-MM-DD HH:MM]
**Duration:** [Approximate session duration]
**Context:** [Brief: what was the goal of this session?]

### Units Worked On

| Unit | Title | Status | Notes |
|------|-------|--------|-------|
| #[N] / P-[NNN] | [Title] | Completed / In Progress / Blocked | [Brief note] |

### Units Completed This Session
- <unit-id> — [Title] (PR #[N], merged/pending — tracker github only)

### Units In Progress
- <unit-id> — [Title]
  - **Branch:** `[branch-name]`
  - **State:** [Description of where work left off, incl. which /issue Step if known]
  - **Remaining:** [What still needs to be done]
  - **Stashed Work:** [Yes/No — if yes, describe]

### Decisions Made
- [Decision 1 — what was decided and why]
- [Decision 2]

### Blockers Identified
- [Blocker 1 — what's blocked, what's needed to unblock]

### New Patterns / Learnings
- [Pattern 1 — should be added to CONVENTIONS.md via /lessons]

### State Summary for Next Agent

**Current branch:** `[branch-name]`
**Uncommitted work:** [Yes/No — if yes, describe or note stash]
**Active Phase:** Phase [N] — [Name]
**Next recommended action:** [Auftragsbrief — see the mandatory form below]

### Questions for Human
- [Question 1 — needs human input]
```

### The "Next recommended action" is an Auftragsbrief (mandatory form, IMP-161)

A handoff is an opening turn for the next agent, so it is written in the same
form as a delegation brief: **`~/.claude/templates/auftragsbrief.md.template`** — five
mandatory fields (Ort/path · Symptom · Ursache soweit bekannt · Messwert/Beleg ·
Akzeptanzkriterium) plus "gemessen, nicht vermutet — BITTE SELBST NACHPRÜFEN"
and an explicit "was ausdrücklich NICHT Auftrag ist". Read the template; the
fields are not restated here.

**If one of the five is unknown at handoff time, write "unbekannt" — never a
guess dressed as a fact.** A complete opening turn carried 6 sessions through
79–266 agent steps without a single correction; one opened with half-finished
numbers and cost 24 correction turns. A handoff is exactly the moment where an
invented number becomes unattributable.

Carry any **explicit user instruction verbatim** into the handoff (quoted, not
paraphrased) — the next agent inherits the instruction, not your reading of it.

---

## Step 5: COMMIT

```bash
git add .rcode/agent-log.md .rcode/blocked-issues.md
git commit -m "$(cat <<'EOF'
docs(handoff): session handoff [$(date +%Y-%m-%d)]

Session summary:
- Units completed: [N]
- Units in progress: [N]
- Blockers: [N]
- Next action: [brief description]

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Output

```
Handoff Complete!

Session Summary:
  Completed: [N] units
  In Progress: [N] units
  Blocked: [N] units

State:
  Branch: [branch-name]
  Uncommitted: [Yes/No]
  Stashed: [Yes/No]

For the next agent:
  1. Read START_HERE.md and PROJECT-STATUS.md
  2. Read .rcode/agent-log.md (last entry)
  3. [Specific next action]

The agent log has been updated. The next agent can pick up
from where you left off by reading the last log entry.
```
