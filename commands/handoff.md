---
description: "Create a context handoff document when switching agents or ending a session. Run before ending work or switching to a different agent."
model: claude-fable-5[1m]
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

### In-Progress Issues

```bash
gh issue list --state open --label "rcode" --json number,title,labels
gh pr list --state open --json number,title,headRefName
```

---

## Step 2: DOCUMENT DECISIONS

Review what was done in this session and document:

### New ADRs
Were any architectural decisions made? List them with ADR numbers.

### New Patterns
Were any new code patterns introduced that should be added to CONVENTIONS.md?

### Modified Conventions
Were any existing conventions updated or discovered to be insufficient?

### Pending Questions
Are there questions that need human input before work can continue?

---

## Step 3: DOCUMENT BLOCKERS

### Technical Blockers
Issues that are blocked by technical problems (failing tests, dependency issues, etc.)

### External Blockers
Issues waiting on external services, API access, human decisions, etc.

### Update `.rcode/blocked-issues.md`
If there are new blockers, add them to the blocked issues file.

---

## Step 4: APPEND TO AGENT LOG

Append a structured entry to `.rcode/agent-log.md`:

```markdown
---

## Session: [Date] — [Agent Identifier]

**Date:** [YYYY-MM-DD HH:MM]
**Duration:** [Approximate session duration]
**Context:** [Brief: what was the goal of this session?]

### Issues Worked On

| Issue | Title | Status | Notes |
|-------|-------|--------|-------|
| #[N] | [Title] | Completed / In Progress / Blocked | [Brief note] |

### Issues Completed This Session
- #[N] — [Title] (PR #[N], merged/pending)

### Issues In Progress
- #[N] — [Title]
  - **Branch:** `[branch-name]`
  - **State:** [Description of where work left off]
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
**Active phase:** Phase [N] — [Name]
**Next recommended action:** [Specific instruction for the next agent]

### Questions for Human
- [Question 1 — needs human input]
```

---

## Step 5: COMMIT

```bash
git add .rcode/agent-log.md .rcode/blocked-issues.md
git commit -m "$(cat <<'EOF'
docs(handoff): session handoff [$(date +%Y-%m-%d)]

Session summary:
- Issues completed: [N]
- Issues in progress: [N]
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
  Completed: [N] issues
  In Progress: [N] issues
  Blocked: [N] issues

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
