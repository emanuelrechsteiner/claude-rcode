---
description: "Synchronize PROJECT-STATUS.md with actual project state (GitHub issues or plan units). Run periodically or after merging PRs / closing plan units."
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(bash:*)
  - Glob
---

<!-- controller-contract:v1 exempt="read-only/mechanical, no agent dispatch" -->

# R.Code Status Sync — Progress Dashboard Update

You are executing the R.Code `/status-sync` command. This synchronizes the project's living documents with the actual state of its work units (GitHub issues, tracker `github`, or `BRAINSTORM.md` units, tracker `plan`).

---

## Step 1: FETCH CURRENT STATE

**Tracker-aware (M14).** Resolve the tracker from `.rcode/config.json`
`.tracker`; if unset, resolve it the way `~/.claude/scripts/rcode-units.sh`
does (A3) and note the inference in Step 5's anomaly report.

**tracker `github`** — gather the real state from GitHub:

```bash
# All issues with full metadata
gh issue list --state all --json number,title,state,labels,milestone --limit 500

# All PRs
gh pr list --state all --json number,title,state,mergedAt,headRefName --limit 500

# Milestone progress
gh api repos/{owner}/{repo}/milestones --jq '.[] | {title, open_issues, closed_issues}'
```

**tracker `plan`** — no `gh` calls. State comes entirely from Step 2's
gather script, which reads `BRAINSTORM.md` directly (A2 grammar).

---

## Step 2: CALCULATE METRICS

Run the deterministic gather script — this replaces hand-computing the
closed/total percentage and stale-issue detection by eyeballing `gh issue
list` output (the same failure mode that made an agent hand-count git
activity and get all 12 historical daily-docs entries wrong; fixed
2026-07-18 by scripting the count instead — see `~/.claude/rules/fail-loud.md`):

```bash
bash ~/.claude/scripts/status-metrics.sh "$PWD"
```

**Interpreting the JSON output:**

- **`ok:false` or a non-zero exit code** → the gather could not complete
  (see `errors[]` — `gh` not authenticated, not a git repo, etc.). Do not
  fall back to recomputing the percentages by hand as a silent substitute —
  report the failure and stop.
- **`milestones[]`** gives the exact **Title**, **Total**, **Completed**, and
  **Percentage** for each phase/milestone — use these verbatim in the
  Progress Table in Step 3, do not re-derive them by hand. `title` (K-B) has
  a DIFFERENT shape per tracker — never re-derive or reformat it, and never
  assume one tracker's shape applies to the other:
  - **tracker `plan`:** `"Phase N — <Name>"` (em dash) when the
    `BRAINSTORM.md` `### Phase N — <Name>` heading carries a name, else the
    bare `"Phase N"`.
  - **tracker `github`:** the raw GitHub milestone title exactly as
    `/decompose` created it — currently colon-separated, e.g.
    `"Phase 2: Core Systems"` (see `~/.claude/commands/decompose.md` Step
    2.2's `create_milestone` calls). Do NOT expect the em-dash form here.
- **`counts{}`** gives the repo-wide **Total progress** figures
  (`issues_total`, `issues_open`, `issues_closed`, `issues_blocked`,
  `issues_no_milestone`, `milestones_total`). **Unmeasured-completion
  caveat (tracker `plan`):** `issues_open`/`issues_closed` are computed by
  exact state match against each unit's recorded state and can come back
  `0`/`0` even when completion was never recorded for those units — the
  same "no `Status`/`State` column" condition the `milestones[]` caveat
  below already nulls out at the per-phase level. Before reporting a
  repo-wide completion % from these two fields, cross-check `milestones[]`:
  if one or more phases show `closed: null` (or, on a gather script that
  emits it, a non-zero `counts.issues_unknown` / a `null`
  `issues_open`/`issues_closed`), completion for those units is
  **unmeasured, not zero** — do not report a percentage derived from them;
  report "completion unmeasured for N units" instead (see Step 3's
  Strategic Posture handling below). Never treat a bare `0` here as "zero
  done."
- **Known scope limit (tracker `github`):** a milestone with **zero** issues
  is invisible to `milestones[]` (the script's single `gh issue list` call
  only returns milestones that have ≥1 issue attached). If a phase milestone
  exists but has no issues yet, it will not appear here — note that
  explicitly rather than silently reporting it as 0%/absent.
- **tracker `plan`:** `milestones[]` groups units by the nearest preceding
  `### Phase N` heading in `BRAINSTORM.md` (A2/A3). `closed`/`percent` come
  back `null` when a table-form unit list has no `Status`/`State` column —
  report that as "completion unknown for N units", never a fabricated 0%.
- **`findings[]` must be read, not skipped** — it flags issues with no
  milestone, blocked issues, and the 500-item fetch-limit truncation
  warning.

**Still requires lead judgment (not part of the script's contract):**
- **In Progress** (issues with an open PR) and **Available** (Total −
  Completed − In Progress − Blocked) per milestone — `milestones[]` only
  carries Total/Completed/Percent, not a per-milestone PR/blocked breakdown.
  Derive these by cross-referencing Step 1's `gh pr list` output (PR → issue
  linkage) and per-issue labels against each milestone's issue set.
- **Current active phase** — the first entry in `milestones[]` with
  `percent` < 100.

---

## Step 3: UPDATE PROJECT-STATUS.md

Rewrite `PROJECT-STATUS.md` with fresh data:

1. **Update header:**
   - Active Phase number and name
   - Overall Progress percentage — or "unmeasured (N units have no recorded
     completion state)" per Step 2's `counts{}` caveat above; never a
     fabricated 0%
   - Last Updated timestamp (now)
   - Last Updated By: "status-sync"

2. **Rewrite Progress Table:**
   | Phase | Total | Done | In Progress | Blocked | Available | % |
   The **Phase** column is `milestones[].title` used verbatim (K-B — per
   tracker: `plan` → `"Phase N — <Name>"` em-dash form, or bare `"Phase N"`;
   `github` → the raw milestone title as created by `/decompose`, currently
   colon-separated `"Phase N: <Name>"`; there is no separate Name field to
   fill for either). Fill the rest with actual calculated numbers — for
   tracker `plan`, leave **%** as "unmeasured" rather than 0 when
   `milestones[].closed` is `null` for that phase (see Step 2's caveat).

3. **Update "Next Available Units":**
   - Units that are open, unblocked, in the current phase, with no open PR
     (tracker `github`) / with no `blocked-by:` reference to a still-open
     unit (tracker `plan`, which has no PR concept)
   - Prioritize `parallel-safe` units first

4. **Update "Currently In Progress":**
   - Units with open PRs — include branch name and author (tracker `github`
     only; tracker `plan` has no PR concept — leave empty, or cross-reference
     `.rcode/agent-log.md`'s "Units In Progress" entries if present)

5. **Update "Blocked Units":**
   - Units with the `blocked` label (tracker `github`) or a `blocked-by:P-NNN`
     marker in the unit line (tracker `plan`) — include blocking reason from
     `.rcode/blocked-issues.md`

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

   - **Recompute Strategic Posture** from the synced metrics — but only from
     data this command actually gathers. Step 2's `status-metrics.sh` produces
     overall completion %, `counts.issues_blocked`, and `stale_issues[]` —
     **nothing about TS errors, lint warnings, test/build status, or test
     coverage.** This command's `allowed-tools` carries no `Bash(npm:*)` /
     `Bash(npx:*)`, so it has no sanctioned way to gather that either. The
     sibling script `~/.claude/scripts/phase-gate-check.sh <phase-number>` DOES gather
     `tsc_errors`/`lint_errors`/`tests_passed`/`tests_failed`/build status —
     that is a `/phase-gate` run, not this command; do not fabricate a
     quality verdict here, and do not silently drop the quality half of the
     rule either.
     - **If overall completion is unmeasured** — per the `counts{}` caveat
       in Step 2 (`milestones[]` shows `closed: null` for one or more
       phases, or a `counts.issues_unknown`/null `issues_open`/
       `issues_closed` signals the same) — do NOT compute a percentage or
       call `Ship`/`Consolidate` from it. State plainly: "completion
       unmeasured for N units — Strategic Posture cannot be derived from
       progress alone" and fall back to whatever blocker/quality signal IS
       available (or say the posture itself is unmeasurable this run).
       Never report a `Consolidate` verdict that was actually computed from
       a fabricated `0%`.
     - High overall completion % + zero active blockers → posture = `Ship`
       ("a milestone is releasable now"), **caveated**: "pending a green
       `/phase-gate` — status-sync does not verify TS/lint/build/coverage."
     - Low/mid completion %, OR any active blocker → posture = `Consolidate`
       ("stabilize before releasing").
     - If a recent `/phase-gate` result for the active phase is known (e.g.
       from `.rcode/phase-summaries/` or this session's own history) and
       it was BLOCK, that overrides a `Ship` call above — say so explicitly.
     - **Coverage has no automated source anywhere in this repo's scripts** —
       neither this command nor `phase-gate-check.sh` computes it. State it as
       permanently unavailable rather than implying it was checked.
     - The one-liner must cite the actual numbers driving the call (e.g.
       "Phase 2 at 80%, 1 blocker open — Ship pending a `/phase-gate` quality
       check (not run by status-sync)") — never state "green quality" unless
       a `/phase-gate` result actually confirmed it.
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

Check for issues that need attention. **Stale-issue detection reuses Step
2's gather** — no second script call needed.

### Stale Issues
**tracker `github`:** Step 2's `bash ~/.claude/scripts/status-metrics.sh
"$PWD"` output already carries `stale_issues[]` — every OPEN issue whose
`updatedAt` is older than `CLAUDE_STALE_DAYS` (default 14, matching "more
than 2 weeks" here). Do not recompute this by hand with a `jq` one-liner —
report each entry (`number`, `title`, `updatedAt`) from `stale_issues[]`
verbatim.

**tracker `plan`:** `BRAINSTORM.md` units carry no `updatedAt` — stale
detection is unavailable (A3); `stale_issues[]` is empty with a `findings[]`
entry saying so. Do not invent a staleness signal from file mtime.

### Orphaned Issues (tracker `github` only)
GitHub issues not in any milestone or not linked to any feature in
scope-manifest.json. `counts.issues_no_milestone` from Step 2 gives the
starting count; identify the specific issues via Step 1's `gh issue list`
output. Tracker `plan`: not applicable — every plan unit is grouped under a
Phase heading by construction (A2).

### Scope Drift
Compare total units (`counts.issues_total` from Step 2 — field name kept for
compatibility, counts units in either tracker) vs total in
scope-manifest.json. If they differ, flag it.

### Missing Labels (tracker `github` only)
GitHub issues without required labels (phase, type, area). Tracker `plan`
has no label mechanism — the nearest equivalent (a unit line missing its
`` `<type>` ``/`` `<area>` `` tags) is not gathered by `status-metrics.sh`
and is out of scope for this check.

Report any anomalies found.

---

## Step 6: COMMIT

```bash
git add PROJECT-STATUS.md START_HERE.md
git commit -m "$(cat <<'EOF'
docs(status): sync project status [$(date +%Y-%m-%d)]

Progress: [X]% complete ([N]/[M] units) | unmeasured (N units)
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

Overall: [X]% complete ([N]/[M] units) | unmeasured (N units have no
  recorded completion state — see Step 2's counts{} caveat)
Active Phase: Phase [N] — [Phase Name] ([X]% | unmeasured)

Phase Progress:
  Phase 1: [X]% ([N]/[M]) | unmeasured ([N] units)
  Phase 2: [X]% ([N]/[M]) | unmeasured ([N] units)
  ...

Available Now: [N] units ready to work on
Blocked: [N] units

Anomalies: [none / list of detected anomalies]
```
