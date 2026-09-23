---
description: "Verify phase completion with quality gates before unlocking the next phase. Run when all issues in a phase are closed."
argument-hint: "<phase-number>"
model: claude-fable-5-1[1m]
allowed-tools:
  - Task
  - Read
  - Write
  - Edit
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(npm:*)
  - Bash(npx:*)
  - Bash(pnpm:*)
  - Bash(yarn:*)
  - Bash(bun:*)
  - Bash(mypy:*)
  - Bash(pytest:*)
  - Bash(ruff:*)
  - Bash(black:*)
  - Bash(cargo:*)
  - Bash(go:*)
  - Bash(swift:*)
  - Bash(xcodebuild:*)
  - Bash(make:*)
  - Bash(bash:*)
  - Glob
  - Grep
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `~/.claude/agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `~/.claude/agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `~/.claude/agents/control-agent.md` §4.

# R.Code Phase Gate — Phase Completion Verification

You are executing the R.Code `/phase-gate` command for **Phase $ARGUMENTS**.

This is a **5-step verification**. All steps must pass for the phase gate to open.

---

## Step 1: UNIT VERIFICATION

**Check:** Are all phase units closed?

Tracker-aware (github issues or plan units, per `.rcode/config.json`
`.tracker` — see `~/.claude/rcode/README.md` §Tracker Modes).
The gather script's `counts.issues_total`/`issues_closed` field names are
kept for compatibility (A3) and count work units in either tracker.

Run the deterministic gather script **once** — its JSON answers both Step 1
(unit verification) and Step 2 (quality verification) below. This replaces
hand-running `gh issue list` / `npx tsc` / `npx eslint` / `npm test` / `npm run
build` and eyeballing their output — the same failure mode that made an
agent hand-count git activity and get all 12 historical daily-docs entries
wrong (fixed 2026-07-18 by scripting the count instead; see
`~/.claude/rules/fail-loud.md`). Model-eyeballed counting of `gh`/`tsc` output is that
exact bug class with higher stakes here — a hallucinated "0 errors" unlocks a
phase.

```bash
bash ~/.claude/scripts/phase-gate-check.sh $ARGUMENTS "$PWD"
```

**Interpreting the JSON output (applies to both Step 1 and Step 2):**

- **`ok:false` or a non-zero exit code → BLOCK, never a pass.** This means
  the gather itself could not be completed (see `errors[]` for why — `gh` not
  authenticated, no milestone match, a runner crash, etc.). Do not fall back
  to re-deriving the facts by hand as a silent substitute — report the
  failure and stop.
- **`verdict` is the deterministic floor**, computed from hard facts only
  (open issues, `tsc_errors`/`lint_errors` > 0, failing tests, a failed
  build):
  - `BLOCK` — an objective failure exists. The gate cannot open.
  - `WARN` — no hard failure, but something could not be fully verified (a
    skipped check, a missing tool, or an ambiguous/missing milestone match).
  - `PASS` — every check ran and came back clean, nothing skipped.
  The lead still adjudicates WARN-vs-PASS **on top of** these facts — the
  script's `verdict` is a floor, not the final call. A `WARN` may still
  resolve to a documented PASS-with-caveats (recorded in Step 4's phase
  summary) or may warrant escalating to BLOCK if the lead judges the caveat
  unacceptable. The script never makes that judgment call for you.
- **`findings[]` must be read, not skipped** — even on a clean `PASS` with an
  empty array, confirm it actually is empty; a `WARN`/`BLOCK` almost always
  carries a specific, actionable finding (skipped check, truncated fetch,
  ambiguous milestone match, etc.).

**The script does not check PR-merge status** (`counts{}` has no PR data) —
that remains a manual spot-check, **tracker `github` only** (tracker `plan`
has no PRs to check — go straight to the `counts{}` verification below):

```bash
gh pr list --state all --json number,title,state,mergedAt --search "milestone:\"Phase $ARGUMENTS\""
```

**Verify (from `counts{}`):**
- [ ] `issues_total` == `issues_closed` — all units in the Phase/milestone
      are closed (github: GitHub issues; plan: units grouped under
      `### Phase $ARGUMENTS` in `BRAINSTORM.md`, per
      `~/.claude/rcode/README.md` §Tracker Modes — a plan
      table with no `Status`/`State` column reports completion as
      **unknown**, not a fabricated 0, per A2/A3)
- [ ] All PRs linked to these units are **merged** (not just closed) — tracker `github` only, from the manual `gh pr list` spot-check above
- [ ] No orphaned PRs (PRs without linked issues) — tracker `github` only
- [ ] No open PRs that should have been merged — tracker `github` only
- [ ] `errors[]` is empty

**Result:** [issues_closed]/[issues_total] units closed, [N]/[N] PRs merged

---

## Step 2: QUALITY VERIFICATION

**Check:** Does the codebase build, pass tests, and have no type/lint errors?

Uses the same JSON gathered by Step 1's `phase-gate-check.sh` call above — no
second script invocation is needed.

**Non-npm / no-manifest fallback — MANDATORY, not optional.**
`phase-gate-check.sh` only ever RUNS the check trio for an npm/TS project (a
`package.json` at the project root or one level down). For every other
stack, `counts.tsc_errors`/`lint_errors`/`tests_passed`/`tests_failed` come
back `null`, and `findings[]` at best *names* the detected manifest
(`pyproject.toml`/`Cargo.toml`/`go.mod`/`Package.swift`) and says the check
trio "must be run by the lead" from the project's `CLAUDE.md` → "##
Mandatory Pre-Commit" section — the script never runs it for you. If
`counts{}`'s quality fields are `null`, or `findings[]` contains that
message:

1. `Read` the calling project's `CLAUDE.md` and locate its
   "## Mandatory Pre-Commit" section.
2. **If it lists real, executable commands** (not unfilled template text
   like `[type-check command]` / `TODO` / an empty section): run **exactly
   those commands**, in order, and record each command's exit code. Treat
   any non-zero exit as a hard quality failure for this Step — same
   consequence as a nonzero `tsc_errors`/`lint_errors`/`tests_failed` from
   the script.
3. **If that section is a stub/placeholder or missing entirely:** quality
   is **`[not verified]`** for this phase. Do NOT run guessed commands
   (`npx tsc`, `npm test`, …) as a substitute, and do NOT treat the absence
   of a reported error as a pass. Note the stub explicitly in Step 4's
   phase summary.

This determines what the Gate Results templates below are allowed to say —
see the precondition note on the PASS template: `verdict:PASS`/"Quality:
All checks passing" is never printed when quality was `[not verified]`.

**Verify (from `counts{}`, npm/TS projects only — see the mandatory
fallback above for every other stack):**
- [ ] `tsc_errors` == 0
- [ ] `lint_errors` == 0
- [ ] `tests_failed` == 0 (and `tests_passed` > 0, unless `findings[]`
      explains why the test check was skipped — e.g. no test script, no
      jest/vitest JSON reporter)
- [ ] `findings[]` reviewed for any skipped check (missing tool/config,
      no `package.json`/`node_modules`, no JSON test reporter, etc.)

**Result:** tsc [tsc_errors] errors, lint [lint_errors] errors, tests
[tests_passed] passed / [tests_failed] failed, build [PASS/FAIL — see
`findings[]`] — OR, when the non-npm fallback applied: `CLAUDE.md`
Mandatory Pre-Commit — [N] commands run, [N] passed / [N] failed — OR
`[not verified] — CLAUDE.md "Mandatory Pre-Commit" is a stub/placeholder`.

---

## Step 3: SCOPE VERIFICATION

**Check:** Were all planned features delivered? No extras? No missing?

1. **Read `.rcode/scope-manifest.json`**
2. **For each feature assigned to Phase $ARGUMENTS:**
   - Are all feature issues closed?
   - Is the feature functionally complete?
   - Were any acceptance criteria skipped?

3. **Check for unplanned additions:**
   - Compare `git log --oneline v0.[N-1].0..HEAD` against planned units (if
     the previous phase's tag doesn't exist because tagging was skipped
     there — Step 5's tag is optional — compare against the previous phase
     summary's recorded commit/date instead)
   - Are there commits that don't reference a planned unit? Commit reference
     accepts both forms and ranges/lists (A2): `closes #N` / `closes P-NNN`

4. **Check for scope changes:**
   - Are all scope changes in `scope_changes` array documented and approved?

**Verify:**
- [ ] All planned features for this phase are complete
- [ ] No unplanned features were added
- [ ] All scope changes are documented and approved
- [ ] Feature status updated to "complete" in scope manifest

**Result:** [N]/[N] features complete, [N] scope changes (all approved)

---

## Step 4: CREATE PHASE SUMMARY

Generate `.rcode/phase-summaries/phase-$ARGUMENTS-summary.md` using the PHASE-SUMMARY template:

1. **Overview:** Phase number, name, completion date, duration, unit count, git tag
2. **What Was Built:** Feature-level description (what the user can now do)
3. **Units Completed:** Table of all units with highlights
4. **Key Decisions:** New ADRs or significant choices — check both
   ARCHITECTURE.md inline `### ADR-NNN` entries and filed
   `docs/adr/NNNN-*.md` (two-tier model, A5)
5. **Patterns Established:** New conventions or approaches
6. **Known Technical Debt:** Work deferred to future phases
7. **Context for Next Phase:** State of codebase, assumptions, watch-outs, recommended next steps

**This is the most critical output** — future agents will read this summary instead of reviewing every individual issue from this phase.

---

> **Version authority (2026-07-26):** phase-gate creates INTERNAL milestone tags only (`v0.N.0-<phase-name>`). User-facing semver releases (`vMAJOR.MINOR.PATCH`, changelog, `gh release`) are owned exclusively by `/launch-team` — never create them here. See `~/.claude/plans/team-phase-restructure-2026-07-26.md` §5. **This tag is optional but recommended** (traceability; Step 3's next-phase scope-drift diff uses it when present) — if skipped, say so explicitly in the phase summary and in the Gate Results output below.

## Step 5: COMMIT (PASS/WARN only, tag optional, recommended)

**Only reached on PASS or WARN.** On BLOCK, stop at the Gate Results output
below — nothing is complete yet, there is nothing to commit.

```bash
# Update scope manifest — mark phase features as complete
# (edit .rcode/scope-manifest.json)

# Update PROJECT-STATUS.md — mark phase as 100% complete
# Update START_HERE.md — increment current phase

# Update .rcode/config.json — set current_phase to the NEXT phase (K-E):
# `Edit` only the `current_phase` field to $ARGUMENTS + 1 — preserve every
# other field verbatim, including historical/legacy ones (A7). This is the
# only writer that ever advances current_phase past its scaffold-time value.

# Commit
git add .rcode/phase-summaries/phase-$ARGUMENTS-summary.md \
       .rcode/scope-manifest.json \
       .rcode/config.json \
       PROJECT-STATUS.md \
       START_HERE.md

git commit -m "$(cat <<'EOF'
docs(phase-gate): phase $ARGUMENTS complete — [Phase Name]

Phase $ARGUMENTS Summary:
- [N] units completed
- [N] features delivered: [list]
- [N] new ADRs
- [N] patterns established
- Known tech debt: [brief list or "none"]

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

# Create version tag — OPTIONAL but recommended (see note above); if you
# skip it, say so explicitly in the phase summary and Gate Results output.
# Quality line MUST match what Step 2 actually established — never hardcode
# "All checks passing" here; use one of:
#   Quality: All checks passing
#   Quality: All checks passing (via CLAUDE.md Mandatory Pre-Commit)
#   Quality: not verified — <reason>          # WARN-only, see Step 2
git tag -a "v0.$ARGUMENTS.0-[phase-name-kebab]" -m "Phase $ARGUMENTS: [Phase Name] complete

Features: [list]
Units: [N] completed
Quality: [All checks passing | All checks passing (via CLAUDE.md Mandatory Pre-Commit) | not verified — <reason>]"
```

---

## Gate Results

### PASS — Phase Complete

**Precondition — do not skip:** quality must have been ACTUALLY verified
per Step 2 — either the script's own npm/TS trio, or (non-npm projects) the
`CLAUDE.md` "Mandatory Pre-Commit" fallback trio with every command
actually run and its exit code recorded. If quality came back
`[not verified]` (stub/placeholder Mandatory Pre-Commit section, or any
other reason the trio could not actually run), the gate is **never PASS**
— use the WARN template below instead, with its "Quality: not verified"
line. "Quality: All checks passing" below may be printed ONLY when the
checks genuinely ran and passed.

```
Phase Gate $ARGUMENTS: PASS

Phase $ARGUMENTS — [Phase Name] is COMPLETE.

Summary:
  Units: [N]/[N] closed
  Quality: All checks passing [— via CLAUDE.md Mandatory Pre-Commit, if
    Step 2's non-npm fallback ran instead of the script's own trio]
  Scope: All features delivered
  Tag: v0.$ARGUMENTS.0-[phase-name]

Phase Summary: .rcode/phase-summaries/phase-$ARGUMENTS-summary.md

Next Phase: Phase [N+1] — [Phase Name]
  [N] units planned
  [N] parallel-safe units available

Recommended: Run /lessons to extract patterns before starting next phase.
```

### BLOCK — Phase Incomplete

```
Phase Gate $ARGUMENTS: BLOCK

Phase $ARGUMENTS cannot be completed. Blockers found:

Units:
  - [ ] #[N] — [Title] (still open)
  - [ ] P-[NNN] — [Title] (still open)
  - [ ] #[N] — [Title] (PR not merged — tracker `github` only)

Quality:
  - TypeScript: [N] errors / Tests: [N] failing   (npm gather)
  - OR (non-npm fallback) CLAUDE.md Mandatory Pre-Commit: [command] failed (exit [N])

Scope:
  - Feature [F00N] is incomplete: [details]

Action Required:
  1. [Specific action to resolve each blocker]
  2. Re-run /phase-gate $ARGUMENTS after resolving
```

### WARN — Phase Complete with Caveats

```
Phase Gate $ARGUMENTS: WARN (Proceed with Caution)

Phase $ARGUMENTS is technically complete but has caveats:

Warnings:
  - [Quality: not verified — CLAUDE.md "Mandatory Pre-Commit" section is a
     stub/placeholder (or missing); no check trio could be run for this
     phase — include this exact line, unedited, whenever Step 2's
     non-npm fallback could not actually run the trio; never omit it and
     never let a WARN with unverified quality read as if quality passed]
  - [Technical debt item deferred]
  - [Test coverage below target: X% vs Y% target — MANUALLY SUPPLIED ONLY:
     phase-gate-check.sh gathers no coverage data, and no automated coverage
     source exists anywhere in this repo's scripts; include this line only
     if a human ran a coverage tool and is supplying the numbers directly]

These items are documented in the phase summary.
Phase [N+1] may proceed but should address warnings early.
```

---

## Append to Agent Log

`/phase-gate` runs as the lead (or under lead dispatch) and is one of the
single writers of `.rcode/agent-log.md` (A12 — dispatched workers never
write it).

```markdown
## Session: Phase Gate $ARGUMENTS

**Date:** [today]
**Agent:** [identifier]
**Result:** [PASS / BLOCK / WARN]

**Phase Summary:**
- Units completed: [N]
- Features delivered: [list]
- Quality: [status]
- Tag: v0.$ARGUMENTS.0-[phase-name]

**Next Steps:**
- [Run /lessons]
- [Begin Phase N+1]
```
