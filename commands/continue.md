---
description: "Resume an interrupted task. Reads PROJECT-STATUS.md, agent-log, and git state to determine where work left off and picks up from the correct /issue phase. Works for both R.Code and non-R.Code repos."
model: claude-fable-5[1m]
allowed-tools:
  - Read
  - Bash(git:*)
  - Bash(gh:*)
  - Glob
  - Grep
---

<!-- controller-contract:v1 exempt="read-only git/gh state-detection + router (Read, Bash(git|gh) only — no Write/Edit/Task); it never itself dispatches a subagent, resumption happens via the target command's own contract" -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `agents/control-agent.md` §4.

# R.Code Continue — Resume Interrupted Work

You are executing the `/continue` command. Your job is to determine exactly where work was interrupted and resume from there — without asking the user to re-explain context.

---

## Step 1: DETECT REPO TYPE

```bash
ls .rcode/ 2>/dev/null && echo "RCODE" || echo "GENERIC"
```

Branch off to the appropriate path below.

---

## Path A: RCODE REPO

### A1 — Read state files (parallel)

Read all three in parallel — they contain the ground truth:

1. **PROJECT-STATUS.md** — active phase, issue availability, blockers
2. **.rcode/agent-log.md** — last entry = last known in-progress state
3. **Git state:**

```bash
git status
git log --oneline -10
git branch --show-current
git stash list
```

### A2 — Identify the interrupted issue and phase

From the agent-log last entry, extract:

- **Issue number** (`In Progress` section)
- **Active phase** (e.g. "Phase 3 — Implement")
- **State description** (what was left to do)
- **Branch name**
- **Stashed work** (yes/no)

If the agent-log last entry shows no In Progress issues, check git: is there a feature branch checked out that is not yet merged?

```bash
git log --oneline main..HEAD 2>/dev/null || git log --oneline origin/main..HEAD 2>/dev/null
gh pr list --state open --json number,title,headRefName 2>/dev/null
```

### A3 — Verify current branch matches the interrupted issue

If we are on `main`/`development` but stashed work exists:
```bash
git stash show -p stash@{0}
```
Pop the stash onto the correct feature branch before resuming.

If we are already on the feature branch: proceed directly.

### A4 — Map to /issue phase

The R.Code `/issue` command has 9 phases:

| Phase | Name |
|-------|------|
| 0 | Onboard Check |
| 1 | Analyze + Scope Boundary |
| 2 | Design (UX) |
| 3 | Implement |
| 4 | Tests |
| 5 | Documentation |
| 6 | Review |
| 7 | PR |
| 8 | Close |

Determine the **last completed phase** by examining:
- Agent-log "Active phase" field
- Which files exist (tests present? PR open?)
- Git log for phase-tagged commits

```bash
gh pr list --state open --head "$(git branch --show-current)" --json number,title 2>/dev/null
```

### A5 — RESUME

State clearly:

```
Resuming Issue #[N] — [Title]
Branch: [branch-name]
Last completed phase: Phase [N] — [Name]
Resuming at: Phase [N+1] — [Name]

Reason: [one-line summary from agent-log]
Remaining work: [list from agent-log "Remaining" field]
```

Then immediately execute the next phase of the `/issue` workflow for that issue, starting from exactly where it was interrupted.

**Do not re-execute phases already completed.**

---

## Path B: GENERIC (non-R.Code) REPO

### B1 — Capture git state

```bash
git status
git log --oneline -15
git branch --show-current
git stash list
git diff --stat HEAD
```

### B2 — Identify last activity

From git log, determine:
- What was the most recent meaningful commit? (skip merge commits and auto-commits)
- Is there a feature branch with uncommitted work?
- Are there uncommitted changes or stashed work?

```bash
# Check for recent branch activity
git log --oneline --all --decorate -20
```

### B3 — Synthesize current state

Produce a concise state summary:

```
Current branch: [branch]
Last commit: [hash] — [message] ([time ago])
Uncommitted changes: [yes/no — list files if yes]
Stashed work: [yes/no]

Inferred task: [what was being worked on, based on branch name + recent commits + uncommitted files]
```

### B4 — Resume the obvious next step

Based on the inferred task:
- If there are uncommitted changes: review them and determine if they are ready to commit or need more work
- If on a feature branch with commits ahead of main: check whether a PR exists or needs to be created
- If all changes are committed and pushed: check for open PRs, review status, or identify next issue

State your next action explicitly before executing it.

---

## Output (both paths)

End with a one-line status that confirms what you are about to do:

```
Continuing: [brief description of next action]
```

Then proceed without further prompting.
