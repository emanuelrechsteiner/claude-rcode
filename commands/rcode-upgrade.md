---
description: "Upgrade a R.Code-managed project's deployed rails to the current global framework version. Compares .rcode/config.json framework_version against ~/.claude/rcode/VERSION, three-way-diffs the installed rules, proposes each update behind a per-file y/n, and never clobbers project-customized rules. Local-only: no GitHub mutations, no commits."
model: claude-fable-5[1m]
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Bash(git:*)
  - Bash(jq:*)
  - Bash(diff:*)
  - Bash(ls:*)
  - Bash(cp:*)
  - Bash(sed:*)
---

<!-- controller-contract:v1 exempt="mechanical three-way rule diff + cp/Edit procedure (Steps 1-6), local-only, per-file y/n gates — no subagent dispatch" -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `agents/control-agent.md` §4.

# R.Code Upgrade — Bring Deployed Rails to the Current Global Version

You are executing the `/rcode-upgrade` command. Your job is to compare this project's deployed R.Code rails (`.claude/rules/` + `framework_version`) against the current global framework version and apply per-file updates — with the user approving every file, and project-customized rules never being clobbered.

Hard constraints (read before doing anything):

- **LOCAL-ONLY.** No GitHub mutations of any kind (`gh` is deliberately absent from allowed-tools). No commits, no pushes — leave the updated files in the working tree for the user to review and commit.
- **IDEMPOTENT.** Re-running at the current version with no rule drift is a clean no-op (report + STOP, zero writes).
- **FAIL-LOUD.** Never silently default. A missing VERSION file, an unreadable config, or an unresolvable base version is reported explicitly — then you either STOP or take the explicitly-announced conservative path. Never guess a version, never assume a file is unmodified.

---

## Step 1: PRECONDITIONS + VERSION COMPARISON (read-only)

```bash
jq -r '.framework_version // "MISSING"' .rcode/config.json
```

Then `Read` `~/.claude/rcode/VERSION` — the **first line** is the current global version.

Abort conditions (report clearly, then **STOP** — no writes):

- **No `.rcode/config.json`** → not a R.Code-managed project. Point at `/rcode-init` (greenfield), `/rcode-migrate` (existing codebase), or `/simple-onboard` (assessment).
- **`~/.claude/rcode/VERSION` missing** → the global install predates versioning or is broken. Say exactly that and stop — never invent a version.

Compare the two versions:

| Project `framework_version` | Meaning | Path |
|---|---|---|
| equal to global | Possibly current — but files can drift without a version change, so STILL run the Step-3 diff as a repair check. No diffs → report "already at [version], nothing to do" and **STOP** (idempotent no-op). | Steps 2–3 |
| older than global | Normal upgrade. | Steps 2–6 |
| `MISSING` | Legacy pre-versioning scaffold. Proceed in **conservative mode** (Step 2 fallback) and stamp `framework_version` at the end. | Steps 2–6 |
| newer than global | This machine's global config is stale (project was upgraded elsewhere). **STOP** and tell the user to update the global config first (`git pull` in `~/.claude`). Upgrading "down" would be a downgrade. | — |

---

## Step 2: RESOLVE THE BASE (the OLD global rule set)

The customization test needs **three** copies of every rule: the project's copy, the **current** global copy, and the **base** — the global copy at the version the project was stamped with. `~/.claude` is a git repo; recover the base from its history:

```bash
proj_ver=$(jq -r '.framework_version // empty' .rcode/config.json)
base_commit=$(cd ~/.claude && git log --format=%H -- rcode/VERSION | while read -r sha; do
  v=$(git show "$sha:rcode/VERSION" 2>/dev/null | sed -n 1p)
  [ "$v" = "$proj_ver" ] && { echo "$sha"; break; }
done)
# base copy of a rule:  (cd ~/.claude && git show "$base_commit:rcode/rules/<file>")
```

- **Base resolved** → three-way mode; full classification in Step 3.
- **Base NOT resolved** (`framework_version` MISSING, or no commit in `~/.claude` carries that VERSION) → **conservative two-way mode.** Announce it explicitly ("cannot recover the base version [X] — treating every differing rule as potentially customized"), and classify EVERY project rule that differs from the current global copy as CUSTOMIZED. Never assume "unmodified" without the base to prove it.

---

## Step 3: DIFF & CLASSIFY

The comparison scope — the global rcode rule set as deployed to projects:

- **Core rules:** every file in `~/.claude/rcode/rules/` (currently `rcode-workflow.md`, `rcode-commits.md`, `rcode-scope.md` — enumerate with `ls`, don't hardcode).
- **Stack rules:** files in `~/.claude/rcode/templates/project-rules/` that the project has ALREADY installed in `.claude/rules/`. Never push new stack rules — the stack choice belongs to the project.

For each file run `diff -u` (project vs current global; and project vs base where resolved) and classify:

| Project vs CURRENT global | Project vs BASE | Class | Action |
|---|---|---|---|
| identical | — | **UP-TO-DATE** | Skip silently. |
| differs | identical to base | **OUTDATED-UNMODIFIED** | Safe to update — propose (Step 4). |
| differs | differs from base too | **CUSTOMIZED** | Protected — never clobber (Step 4). |
| absent in project (new core rule in global set) | — | **NEW** | Propose install (Step 4). |
| present in project, not in the global set | — | **PROJECT-OWN** | Leave untouched — not ours. |

Present the classification as a one-table summary before any prompting, so the user sees the whole upgrade at a glance.

---

## Step 4: PROPOSE PER FILE (y/n each — never batch-clobber)

**OUTDATED-UNMODIFIED and NEW files** — for each, show the unified diff (for NEW: "new file, [N] lines, purpose: [one-liner from its header]") and ask a per-file y/n. Lead with the recommendation (per `recommend-on-ask.md`): "Recommended: apply — your copy is unmodified from version [base], this only picks up upstream changes."

**CUSTOMIZED files** — NEVER overwrite by default. Show BOTH diffs: project-vs-base (= the project's deliberate customization) and base-vs-current (= what upstream changed). Then ask, with keep as the recommended first option:

1. **Keep project version (Recommended)** — preserves the customization; the file is recorded as a deliberate delta.
2. Overwrite with the current global version — explicitly discards the customization (only on an explicit user choice, never inferred).
3. Skip and flag for manual merge — logged in Step 6 for the user to reconcile by hand.

---

## Step 5: APPLY (only what was approved)

`cp` each approved file from its global source into `.claude/rules/`. Then re-run `diff` on every applied file and verify it is now **identical** to the current global copy — surface any mismatch immediately (fail-loud), do not paper over it. No writes beyond the approved set.

---

## Step 6: STAMP + LOG + REPORT

**Version bump rule:** set `framework_version` to the current global version ONLY if no OUTDATED-UNMODIFIED or NEW file was declined. A declined upstream update leaves the version un-bumped, so a re-run honestly re-proposes it. Kept CUSTOMIZED files do NOT block the bump — they are deliberate project deltas, recorded below. Also stamp the field when it was MISSING (legacy scaffold).

Update `.rcode/config.json` via `Edit` — change `framework_version` only; preserve every other field verbatim (especially `created_date` / `migrated_date`).

Append to `.rcode/agent-log.md` — **APPEND-ONLY**, never rewrite or truncate existing entries:

```markdown
## Session: Upgrade

**Date:** [today]
**Agent:** rcode-upgrade

**Actions:**
- Upgraded R.Code rails: framework_version [old → new | unchanged — updates declined | stamped (was missing)]
- Updated: [files | none]
- Newly installed: [files | none]
- Kept (customized, protected): [files | none]
- Declined: [files | none]
- Flagged for manual merge: [files | none]
```

End with the summary:

```
R.Code Upgrade — [complete | partial | nothing to do]

framework_version: [old] → [new]   (global: ~/.claude/rcode/VERSION)
Updated: [N]   New: [N]   Customized-kept: [N]   Declined: [N]   Manual-merge: [N]

Nothing was committed — review with `git diff`, then commit the rail updates yourself.
```
