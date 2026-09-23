---
description: "Resume an interrupted task. Reads PROJECT-STATUS.md, agent-log, and git state to determine where work left off and picks up from the correct /issue Step, or routes to /team-lead. Works for both R.Code and non-R.Code repos."
allowed-tools:
  - Read
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(bash:*)
  - Glob
  - Grep
---

<!-- controller-contract:v1 exempt="read-only git/gh state-detection + router (Read, Bash(git|gh) only — no Write/Edit/Task); it never itself dispatches a subagent, resumption happens via the target command's own contract" -->

# R.Code Continue — Resume Interrupted Work

You are executing the `/continue` command. Your job is to determine exactly where work was interrupted and resume from there — without asking the user to re-explain context.

---

## Detect Repo Type

```bash
ls .rcode/ 2>/dev/null && echo "RCODE" || echo "GENERIC"
```

Branch off to the appropriate path below.

---

## Path A: RCODE REPO

### A1 — Run the gather script

Run the deterministic gather script once — it replaces hand-reading git
state, `.rcode/agent-log.md`, and `PROJECT-STATUS.md` and cross-checking
them by eye (the same failure mode that made an agent hand-count git activity
and get all 12 historical daily-docs entries wrong; fixed 2026-07-18 by
scripting the count instead — see `~/.claude/rules/fail-loud.md`):

```bash
bash ~/.claude/scripts/resume-state.sh "$PWD"
```

**Interpreting the JSON output:**

- **`ok:false` or a non-zero exit code** → the gather could not complete (see
  `errors[]` for why — not a git repo, `git branch`/`git status` failed,
  etc.). Do not fall back to re-deriving the state by hand as a silent
  substitute — report the failure and stop.
- **`ambiguous:true`** → the script found conflicting evidence between
  sources (e.g. agent-log says unit #X, the branch name says #Y; or
  agent-log says Phase M, `PROJECT-STATUS.md` says Phase N). The script
  already picked a tie-break value for `in_progress_unit`/`detected_project_phase`,
  but that pick is **not** the final answer — read `findings[]` for the exact
  conflict, **surface both readings to the user, and ask** which is correct
  rather than silently trusting the tie-break.
- **`findings[]` must be read, not skipped** — it also covers legitimate
  degraded modes (no `.rcode/` directory → generic repo, detached HEAD,
  no PROJECT-STATUS.md, etc.).

### A1.5 — Route check: who wrote the last session?

A1's JSON carries `last_entry_agent` — the value of the newest
`.rcode/agent-log.md` entry's `**Agent:**` line (`string|null`; part of
`resume-state.sh`'s A3 field contract). Route on that value and on the
`**Last step:**` field, never on the mere absence of a field — the absence
of `**Last step:**` alone is NOT distinctive of a `/team-lead` entry, every
non-`/issue` writer omits it too:

- **`last_entry_agent == "team-lead"`** — do NOT try to resume an `/issue`
  Step. `~/.claude/commands/team-lead.md`'s agent-log template (§6) carries
  TWO distinct free-text fields — read both from the newest entry and show
  both, never collapse them into one "Directive" line:

  ```
  Continuing: routing to /team-lead — the last session in
  .rcode/agent-log.md was a /team-lead run, not an interrupted /issue Step.

  Original directive: [verbatim `**Directive:**` field from the last entry]
  Resuming with: [the last entry's `**Next action:**` field — or, if that
    field is literally "none", the "Original directive" above instead]
  ```

  Then execute `~/.claude/commands/team-lead.md`, passing the "Resuming
  with" value above as `$ARGUMENTS` (the "Original directive" line is
  context for the user, not what gets passed — it is used as `$ARGUMENTS`
  only in the "Next action: none" fallback case). Skip A2–A5 below in this
  case.

- **`last_entry_agent == "handoff"`** — do NOT try to resume an `/issue`
  Step or route to `/team-lead`. Read that entry's own "Units In Progress"
  section (per `~/.claude/commands/handoff.md`'s template) directly and
  resume from what it names. Skip A2–A5 below in this case.

- **The newest entry has a `**Last step:**` field** (an `/issue` entry,
  regardless of `last_entry_agent`'s literal value) — this is the one case
  that resumes an `/issue` Step; proceed to A2.

- **Any other producer, or `last_entry_agent` is `null`/unrecognized and
  there is no `**Last step:**` field** — do not guess which of the above
  applies. Report the newest agent-log entry's content (who wrote it, when,
  what it says) and ask the user how to proceed, per
  `~/.claude/rules/recommend-on-ask.md` (lead with a recommendation — e.g.
  "this looks like a `/phase-gate` entry — resume with `/status-sync`?").
  Skip A2–A5 below in this case.

### A2 — Identify the interrupted unit and Step

From the JSON, read directly (no re-derivation needed — A3 field contract):

- **`tracker`** — `github` or `plan`
- **`in_progress_unit`** — the interrupted unit ID (`"#N"` | `"P-NNN"` | `null`)
- **`last_logged_step`** — the `/issue` Step (0–9) parsed from the newest
  `.rcode/agent-log.md` entry's `**Last step:** N` line (int|null) — the
  authority for "which Step do we resume at". Never use `detected_phase` for
  this.
- **`detected_project_phase`** — the project Phase (milestone, int|null).
  `detected_phase` still appears in the JSON as a DEPRECATED alias equal to
  this field (see the script's own header) — it is a project Phase, not an
  `/issue` Step, despite the name.
- **`branch`** — current branch name
- **`dirty_files`** / **`stash_count`** — uncommitted/stashed work
- **`last_commit`** — hash, subject, relative date
- **`open_prs`** — open PRs on the current branch (tracker `github`)

If `in_progress_unit` and `last_logged_step` are both `null` (script could
not detect either — see `findings[]`), fall back to judgment: is there a
unit branch checked out that is not yet merged, and how many commits ahead
of trunk is it?

```bash
git log --oneline main..HEAD || git log --oneline origin/main..HEAD
```

### A3 — Verify current branch matches the interrupted unit

If `stash_count` > 0 and we are on `main`/`development`:
```bash
git stash show -p stash@{0}
```
Pop the stash onto the correct unit branch before resuming.

If we are already on the unit branch matching `in_progress_unit`:
proceed directly.

### A4 — Map to /issue Step

The R.Code `/issue` command runs Steps 0–9 (10 steps total), verified
directly against `~/.claude/commands/issue.md`'s actual `## Step N` headings:

| Step | Name |
|------|------|
| 0 | Readiness Check |
| 1 | Scope Boundary |
| 2 | Branch |
| 3 | Implement + Convention Enforcement |
| 4 | Test + Check Trio |
| 5 | Commit |
| 6 | PR |
| 7 | Verify |
| 8 | Status Sync |
| 9 | Context Hygiene |

Determine the **last completed Step** using A2's `last_logged_step` and
`open_prs` from the gather script as inputs (A3), plus the manual
commit-count check from A2 when both come back `null` — the mapping from
those facts to "which `/issue` Step are we actually resuming at" is
judgment, not gathering, and never uses `detected_phase` (a project Phase,
not a Step):
- `last_logged_step` gives the Step last recorded by `/issue` itself in
  `.rcode/agent-log.md` (`**Last step:** N`)
- `open_prs` (already fetched in A1 — no need to re-run `gh pr list`) tells
  you whether Step 6 (PR) has already happened
- Which files exist (tests present? committed?) and the git log for
  unit-tagged commits remain manual judgment checks — the script does not
  inspect file contents or commit messages beyond what A1/A2 already surface

### A5 — RESUME

State clearly:

```
Resuming Unit <id> — [Title]
Branch: [branch-name]
Last completed Step: Step [N] — [Name]
Resuming at: Step [N+1] — [Name]

Reason: [one-line summary from agent-log]
Remaining work: [list from agent-log "Remaining" field]
```

Then immediately execute the next Step of the `/issue` workflow for that
unit (`~/.claude/commands/issue.md` standalone mode), starting from exactly
where it was interrupted.

**Do not re-execute Steps already completed.**

---

## Path B: GENERIC (non-R.Code) REPO

### B1 — Run the gather script

`~/.claude/scripts/resume-state.sh` is explicitly written to support this path (see its
own header) — a missing `.rcode/` directory or `PROJECT-STATUS.md` is
reported as a `findings[]` entry, not an `errors[]` entry, so run it exactly
as in Path A:

```bash
bash ~/.claude/scripts/resume-state.sh "$PWD"
```

Read `branch`, `dirty_files`, `stash_count`, `last_commit`, and `open_prs`
directly from the JSON — same interpretation rules as A1 (`ok:false` → report
and stop; `findings[]` must be read, not skipped). `in_progress_unit` /
`last_logged_step` / `detected_project_phase` will usually come back `null`
here (no `.rcode/agent-log.md` to cross-check against) — that is the
expected, documented degraded mode, not a script defect.

The script does not carry commit history beyond the single last commit, or
the full branch list — supplement with:

```bash
git log --oneline -15
git log --oneline --all --decorate -20
git diff --stat HEAD
```

### B2 — Identify last activity

From B1's JSON (`dirty_files`, `stash_count`, `last_commit`) plus the
supplementary `git log` above, determine:
- What was the most recent meaningful commit? (skip merge commits and auto-commits)
- Is there a feature branch with uncommitted work?
- Are there uncommitted changes or stashed work?

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
