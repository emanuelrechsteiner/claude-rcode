---
description: "Synchronize PROJECT-STATUS.md with actual GitHub state. Run periodically or after merging PRs."
model: claude-fable-5[1m]
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash(gh:*)
  - Bash(git:*)
  - Glob
---

<!-- controller-contract:v1 exempt="read-only/mechanical, no agent dispatch" -->

# R.Code Status Sync — Progress Dashboard Update

You are executing the R.Code `/status-sync` command. This synchronizes the project's living documents with the actual state on GitHub.

---

## Step 1: FETCH CURRENT STATE

Gather the real state from GitHub:

```bash
# All issues with full metadata
gh issue list --state all --json number,title,state,labels,milestone --limit 500

# All PRs
gh pr list --state all --json number,title,state,mergedAt,headRefName --limit 500

# Milestone progress
gh api repos/{owner}/{repo}/milestones --jq '.[] | {title, open_issues, closed_issues}'
```

---

## Step 2: CALCULATE METRICS

For each phase (milestone):
- **Total issues** — Count all issues in the milestone
- **Completed** — Count closed issues
- **In Progress** — Count issues with open PRs
- **Blocked** — Count issues with `blocked` label
- **Available** — Total minus (completed + in progress + blocked)
- **Percentage** — (Completed / Total) * 100

Overall:
- **Total progress** — Sum of all completed / Sum of all total
- **Current active phase** — First phase with < 100% completion

---

## Step 3: UPDATE PROJECT-STATUS.md

Rewrite `PROJECT-STATUS.md` with fresh data:

1. **Update header:**
   - Active Phase number and name
   - Overall Progress percentage
   - Last Updated timestamp (now)
   - Last Updated By: "status-sync"

2. **Rewrite Progress Table:**
   | Phase | Name | Total | Done | In Progress | Blocked | Available | % |
   With actual calculated numbers.

3. **Update "Next Available Issues":**
   - Issues that are open, unblocked, in the current phase, with no open PR
   - Prioritize `parallel-safe` labeled issues first

4. **Update "Currently In Progress":**
   - Issues with open PRs — include branch name and author

5. **Update "Blocked Issues":**
   - Issues with `blocked` label — include blocking reason from `.rcode/blocked-issues.md`

6. **Update "Scope Health":**
   - Read `.rcode/scope-manifest.json` for feature completion status

7. **Regenerate "Roadmap / Strategic Prioritization":**

   This section lives right after "Scope Health". REGENERATE it from the **live GitHub milestone state** — consistent with this command's "GitHub is truth, the doc is regenerated" model. Do not hand-preserve stale rows; recompute from the metrics gathered in Steps 1–2. Use this exact section format:

   ```markdown
   ## Roadmap / Strategic Prioritization

   **Strategic Posture:** [Ship / Consolidate] — [one line: is now a good moment to ship/release or to consolidate? Derived from current phase completion %, open blockers, and test/quality status.]

   | Priority | Phase / Milestone | Strategic Rationale | Suggested Timing | Must-Precede |
   |----------|-------------------|---------------------|------------------|--------------|
   | P1 | [Phase N — Name] | [Why this matters now] | [next release window / after Phase N gate / deferred] | [#N or blocking dependency] |
   | P2 | [Phase N — Name] | [Why this matters] | [next release window / after Phase N gate / deferred] | [#N or —] |
   | P3 | [Phase N — Name] | [Why this matters] | [next release window / after Phase N gate / deferred] | [#N or —] |

   **Recommended Next Strategic Move:** [one-liner: what to prioritize next and WHY — the next strategic lever, not just the next issue.]
   ```

   Regenerate each part from the live data:

   - **Recompute Strategic Posture** from the synced metrics:
     - High overall completion % + zero active blockers + green quality (0 TS errors, 0 lint warnings, build Pass, coverage ≥ target) → posture = `Ship` ("a milestone is releasable now").
     - Low/mid completion %, OR any active blocker, OR red quality → posture = `Consolidate` ("stabilize before releasing").
     - The one-liner must cite the actual numbers driving the call (e.g. "Phase 2 at 80%, 1 blocker open, build failing → consolidate").
   - **Re-rank priorities (P1/P2/P3)** from live milestone state:
     - The current active phase (first milestone < 100%) and any phase gating others rank highest (P1).
     - Milestones with the most blocked downstream work, or unblocking-heavy dependency milestones, rank above isolated nice-to-haves.
     - **Must-Precede** = blocking dependencies still open (issues with `blocked` / `blocking` labels and predecessor milestones not yet 100%).
   - **Refresh Suggested Timing** against live progress:
     - A milestone at/near 100% with green quality → `next release window`.
     - A sequenced downstream phase → `after Phase N gate`.
     - Low-priority / out-of-current-focus → `deferred`.
   - **Recommended Next Strategic Move** = the highest-leverage lever given the live state (e.g. "close the 1 open blocker on Phase 2 to make it releasable", "cut a release of Phase 1 now while Phase 2 is mid-flight"), with the WHY — not just the next issue number.

---

## Step 4: UPDATE START_HERE.md

Update the status line:
```markdown
**Phase [N] of [M]** — [Phase Name] — **[X]% complete**
```

---

## Step 5: DETECT ANOMALIES

Check for issues that need attention:

### Orphaned Issues
Issues not in any milestone or not linked to any feature in scope-manifest.json.

### Stale Issues
Issues in progress for more than 2 weeks without activity:
```bash
gh issue list --state open --json number,title,updatedAt | jq '.[] | select(.updatedAt < "[2-weeks-ago]")'
```

### Scope Drift
Compare total issues in GitHub vs total in scope-manifest.json. If they differ, flag it.

### Missing Labels
Issues without required labels (phase, type, area).

Report any anomalies found.

---

## Step 6: COMMIT

```bash
git add PROJECT-STATUS.md START_HERE.md
git commit -m "$(cat <<'EOF'
docs(status): sync project status [$(date +%Y-%m-%d)]

Progress: [X]% complete ([N]/[M] issues)
Active Phase: [N] — [Phase Name]
Anomalies: [none / list]

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Output

```
Status Sync Complete!

Overall: [X]% complete ([N]/[M] issues)
Active Phase: Phase [N] — [Phase Name] ([X]%)

Phase Progress:
  Phase 1: [X]% ([N]/[M])
  Phase 2: [X]% ([N]/[M])
  ...

Available Now: [N] issues ready to work on
Blocked: [N] issues

Anomalies: [none / list of detected issues]
```
