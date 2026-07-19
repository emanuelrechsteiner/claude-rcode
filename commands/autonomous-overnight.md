---
description: "Run a scoped autonomous work session that can continue without human supervision, queuing irreversible operations rather than skipping or auto-approving them. Invoke at the start of a pre-vetted night-run or long unattended session."
argument-hint: "<scope description or issue list>"
model: claude-fable-5[1m]
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(npm:*)
  - Bash(npx:*)
  - Bash(tsc:*)
  - Bash(python:*)
  - Bash(pytest:*)
  - Agent
  - Task
  - TaskCreate
  - TaskUpdate
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `agents/control-agent.md` §4.

# /autonomous-overnight

> **SAFETY-CRITICAL COMMAND.** Read this document in full before any action. The
> guardrail described in § Mechanism is load-bearing — it must never be weakened,
> bypassed, or worked around.

Autonomous-overnight mode lets the agent continue a bounded scope of reversible
work while a human is unavailable. **It does NOT add any bypass, ACK token, or
override.** Every security gate (`excessive-agency-gate.sh`, `agency-bands.md`,
`guard-unsafe.sh`) remains active and unmodified at its normal strength
throughout the run.

---

## Pre-flight Checklist

**All seven checks must pass.** If any fails, stop and report — do NOT start the
overnight run.

```
[ ] 1. GIT STATE CLEAN
        git status → 0 untracked + 0 modified files (or everything staged)
        git log --oneline -3  (know the last 3 commits)

[ ] 2. TESTS CURRENTLY GREEN
        Run the full test suite; all tests must pass BEFORE the run starts.
        (npm test / pytest / swift test — whatever the project uses)

[ ] 3. ENVIRONMENT VERIFIED
        All required env vars present and non-empty.
        No expired tokens or missing secrets that would cause mid-run failures.

[ ] 4. NO PENDING ESCALATE ITEMS
        .rcode/escalation-queue.md does not exist, OR every entry in it
        has been resolved and signed off by a human before this run starts.
        A run must never start with an open escalation queue.

[ ] 5. RATE-LIMIT HEADROOM
        Confirm API / GitHub / third-party rate limits have headroom for the
        expected call volume. If uncertain, estimate and document the margin.

[ ] 6. EXPLICIT TASK SCOPE DEFINED
        $ARGUMENTS (or a scope file) names exactly what work is in scope.
        Anything not mentioned is OUT OF SCOPE — do not expand.

[ ] 7. STOP CONDITIONS AGREED
        At minimum: "stop if ≥ N ESCALATE items accumulate" and
        "stop if the test suite goes red and cannot be fixed within the run".
        Document the stop conditions in the overnight report header.
```

If all checks pass, document each as ✅ in the first section of
`.rcode/overnight-report.md` before any other work begins.

---

## Mechanism (INVARIANT — DO NOT MODIFY)

Overnight mode changes exactly **one behavioral rule**: when a
SOFT-ACK–band operation is encountered, it proceeds automatically and the
intent + undo path is logged immediately. Nothing else changes.

| Op band | Normal mode | Overnight mode |
|---------|-------------|----------------|
| AUTO | proceed silently | proceed silently (unchanged) |
| SOFT-ACK | proceed + emit one-line note | proceed + write note to overnight report (auto) |
| **ESCALATE** | **hard block — agent pauses and asks the user** | **hard block — agent appends to escalation queue, then continues OTHER independent work** |

**ESCALATE operations are NEVER auto-approved.** The `excessive-agency-gate.sh`
hook still exits 2 (hard block) on every irreversible op. The agent's response
to that block changes from "pause and ask" to "queue and continue" — but the op
itself never runs without a human ACK token.

**Forbidden responses to an ESCALATE block in overnight mode:**

- Routing around the gate via a different tool, language, subprocess, or eval
- Generating an `CLAUDE_AGENCY_ACK_ONCE` token without a real human having
  approved the operation
- Replacing the blocked op with an approximate substitute that achieves the
  same effect
- Skipping the blocked op silently without recording it in the escalation queue

---

## Escalation Queue

When the gate hard-blocks an ESCALATE-band op, the agent MUST:

1. **Append** a fully self-contained entry to
   `<project>/.rcode/escalation-queue.md` (create file if absent).
2. **Continue** with other independent work from the scope.
3. **Do NOT retry** the blocked op later in the same run.

### Queue entry format

```markdown
---

## ESCALATE: <one-line op description>

**Queued:** YYYY-MM-DD HH:MM (UTC)
**Op:** `<exact command or MCP call that was blocked>`
**Band reason:** <which irreversibility criterion fired — e.g. "gh pr merge = external comms / shared state">
**R/S/T scores:** R=<irreversible|hard-to-reverse|reversible> S=<local|shared-remote|external-or-production> T=<trusted|untrusted>
**Why now:** <why this op is needed — what depends on it>
**If approved:** <what will happen — be precise>
**If deferred:** <what work remains blocked and how to unblock it manually>
**Independent remaining work:** <Yes — N tasks | No — this was the last task>
```

---

## Stop Conditions (mandatory)

Stop the run immediately (do not queue more work) if ANY of the following:

1. **All remaining scope items are ESCALATE-blocked** — there is no independent
   reversible work left to do. Write the final report and halt.
2. **Tests go red AND the failure cannot be fixed within this scope** — do not
   continue accumulating changes on top of a broken baseline.
3. **The escalation queue reaches the agreed stop-N** (defined in pre-flight
   check 7).
4. **An environment error (missing secret, auth failure) would affect all
   remaining work** — halt and report rather than accruing failures.

---

## End-of-Run Report

At the end of the run (or at any stop condition), write
`<project>/.rcode/overnight-report.md`. Overwrite any prior draft; this
file is always the current run's report.

```markdown
# Overnight Run Report

**Started:** YYYY-MM-DD HH:MM (UTC)
**Ended:**   YYYY-MM-DD HH:MM (UTC)
**Scope:** <copied from $ARGUMENTS or scope file>
**Stop reason:** <natural completion | stop-condition N | escalation queue full | test failure>

## Pre-flight Results
[paste the seven ✅/❌ checks]

## Stop Conditions for This Run
- Stop if escalation queue ≥ N items: N = <<agreed value>>
- Stop if tests go red: Yes
- [any additional agreed conditions]

## Completed Work

| Timestamp | Task | Files Changed | Commit |
|-----------|------|---------------|--------|
| HH:MM | <description> | <list> | <sha or "staged"> |

## SOFT-ACK Log

| Timestamp | Op | Undo path |
|-----------|----|-----------|
| HH:MM | <op> | <how to undo> |

## Queued for Human (ESCALATE items)

[If escalation-queue.md is non-empty, paste all entries here as a summary]
[If empty, write: "None — all scope items completed without ESCALATE ops."]

## Failed Items

| Task | Failure reason | Recommendation |
|------|----------------|----------------|
| <task> | <reason> | <what the human should do next> |

## Recommended Human Actions

1. Review escalation queue (if any) and apply ACK tokens to unblock queued ops
2. <any other follow-up>
3. Run /status-sync to verify PROJECT-STATUS.md reflects what was completed
```

---

## Appending to Agent Log

Append a brief entry to `.rcode/agent-log.md` at end-of-run:

```markdown
---

## Session: Autonomous-Overnight — YYYY-MM-DD

**Duration:** ~N hours
**Scope:** <$ARGUMENTS summary>
**Completed:** N tasks
**SOFT-ACK logged:** N ops
**ESCALATE queued:** N ops (see escalation-queue.md)
**Tests at end:** GREEN | RED (details in overnight-report.md)
**Next action for human:** <one sentence>
```

---

## What This Command Does NOT Do

- Does not weaken any gate or guardrail
- Does not auto-approve any irreversible operation
- Does not generate ACK tokens on the agent's own behalf
- Does not expand scope beyond $ARGUMENTS
- Does not push to remote, merge PRs, deploy to production, or send external
  communications without a human ACK (all of these are ESCALATE-band)

If an operation you believe is safe is being ESCALATE-blocked, the correct
response is to queue it and flag it in the overnight report — not to find a
workaround.
