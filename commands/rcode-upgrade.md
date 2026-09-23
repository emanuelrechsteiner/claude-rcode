---
description: "Upgrade a R.Code-managed project's deployed rails to the current global framework version. Compares .rcode/config.json framework_version against ~/.claude/rcode/VERSION, migrates the config (adds a missing tracker field, never touching historical fields), three-way-diffs the installed rules (incl. legacy torvaldsen-*.md renames), verifies the CLAUDE.md rule imports, and proposes each change behind a per-file y/n — never clobbering project-customized rules. Local-only: no GitHub mutations, no pushes; commits only after one explicit y/n."
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

<!-- controller-contract:v1 exempt="mechanical three-way rule diff + config/import migration + cp/Edit/git-rm procedure (Steps 1-7), local-only (no GitHub mutations, never pushes), per-file y/n gates plus one final commit y/n — no subagent dispatch" -->

# R.Code Upgrade — Bring Deployed Rails to the Current Global Version

You are executing the `/rcode-upgrade` command. Your job is to compare this project's deployed R.Code rails (`.claude/rules/` + `framework_version`) against the current global framework version and apply per-file updates — with the user approving every file, and project-customized rules never being clobbered.

Hard constraints (read before doing anything):

- **LOCAL-ONLY.** No GitHub mutations of any kind (`gh` is deliberately absent from allowed-tools). No pushes, ever. Commits happen ONLY after an explicit y/n at the very end (Step 7, A9) — declined, the updated files stay in the working tree for the user to review and commit by hand.
- **IDEMPOTENT.** Re-running at the current version with no rule drift, a set `tracker`, and correct CLAUDE.md imports is a clean no-op (report + STOP, zero writes).
- **FAIL-LOUD.** Never silently default. A missing VERSION file, an unreadable config, or an unresolvable base version is reported explicitly — then you either STOP or take the explicitly-announced conservative path. Never guess a version, never guess a tracker, never assume a file is unmodified.

---

## Step 1: PRECONDITIONS + VERSION COMPARISON (read-only)

```bash
jq -r '.framework_version // "MISSING"' .rcode/config.json
```

Then `Read` `~/.claude/rcode/VERSION` — the **first line** is the current global version.

Abort conditions (report clearly, then **STOP** — no writes, not even Step 2):

- **No `.rcode/config.json`** → not a R.Code-managed project. Point at `/rcode-init` (greenfield), `/rcode-migrate` (existing codebase), or `/simple-onboard` (assessment).
- **`~/.claude/rcode/VERSION` missing** → the global install predates versioning or is broken. Say exactly that and stop — never invent a version.

Compare the two versions:

| Project `framework_version` | Meaning | Path |
|---|---|---|
| equal to global | Possibly current — but files can drift without a version change, so STILL run the Step 4 diff as a repair check; Step 2's config/import migration always runs too. Nothing found anywhere (no rule diff, no tracker migration needed, imports already correct) → report "already at [version], nothing to do" and **STOP** (idempotent no-op). Otherwise the run is "partial" even though the rules themselves were current. | Steps 2–4 (5–7 only if something was found to apply) |
| older than global | Normal upgrade. | Steps 2–7 |
| `MISSING` | Legacy pre-versioning scaffold. Proceed in **conservative mode** (Step 3 fallback) and stamp `framework_version` at the end. | Steps 2–7 |
| newer than global | This machine's global config is stale (project was upgraded elsewhere). **STOP** and tell the user to update the global config first (`git pull` in `~/.claude`). Upgrading "down" would be a downgrade. | — |

---

## Step 2: CONFIG MIGRATION (tracker field + historical-field preservation — A7, A10)

This step is independent of the rule-diff mechanics below and always runs once Step 1 has decided NOT to abort, regardless of which version-comparison branch was taken.

**Tracker field (A10 — ask, never guess):**

```bash
jq -r '.tracker // "MISSING"' .rcode/config.json
```

- **Already set** → nothing to do here, continue to Step 3.
- **`MISSING`** → determine a recommendation, then ask ONCE via `AskUserQuestion` (never silently default — a wrong silent guess here makes every later tracker-aware command misbehave):
  ```bash
  git remote -v | head -1
  ```
  Recommend `github` when a remote is present, `plan` when it is not.
  **Documented simplification of A10:** the full tracker-recommendation rule
  ("remote exists AND `gh auth status` succeeds AND ≥1 GitHub issue exists")
  needs `gh`, which this command deliberately does not carry in
  `allowed-tools` (LOCAL-ONLY).
  Say so in the question itself, e.g. "Recommended: github — a remote is
  configured (this command does not check `gh` auth/issue state; say no if
  this project doesn't actually track work as GitHub issues)." Commands that
  already have `gh` access (`/decompose`, `/rcode-init`, `/rcode-migrate`)
  apply the full A10 heuristic — this command's version is an honest,
  narrower substitute, not a claim to have checked GitHub state.
  Persist the answer via `Edit` — **add** the `tracker` field to
  `.rcode/config.json`, touch nothing else in the object.

**Historical fields (A7 — never rewrite the object, only edit named fields):**

Every write this command makes to `.rcode/config.json` — here and in Step 7 —
edits ONLY the field it names (`tracker` here, `framework_version` in Step
7). `workflow_version` and any other field this command does not name (e.g.
a project-specific `renamed_torvaldsen_to_rcode` marker) are left
byte-for-byte as found. If `workflow_version` is present, report it once in
the Step 7 summary as "legacy field, present but unused — left untouched" —
never remove it, never bump it.

---

## Step 3: RESOLVE THE BASE (the OLD global rule set)

The customization test needs **three** copies of every rule: the project's copy, the **current** global copy, and the **base** — the global copy at the version the project was stamped with. `~/.claude` is a git repo; recover the base from its history.

**zsh trap (M3) — read before touching this step.** `"$sha:rcode/VERSION"` <!-- lint:allow -->
(no braces) is silently misparsed by zsh 5.9: `:r` is a valid zsh parameter
modifier ("remove the suffix after the last dot"), so zsh consumes the `r`
of `rcode` as the modifier letter and the command actually runs against
`e7eb35bcode/VERSION` instead — reproduced live 2026-09-23 (`echo
"$sha:rcode/VERSION"` → `e7eb35bcode/VERSION` for `sha=e7eb35b`). <!-- lint:allow -->
**Always brace the variable before a literal `:`**
(`"${sha}:rcode/VERSION"`), everywhere in this command, not only here.

**Second trap found while proving this fix (not in the original defect
report): never name a loop variable `path`.** In zsh the lowercase array
`path` is TIED to `$PATH` — assigning a scalar to `path` silently rewrites
the shell's command search path, and every subsequent command in the same
shell (`git`, `sed`, …) then fails with `command not found`, with nothing
in the error pointing at the real cause. Reproduced live 2026-09-23: a
first draft of the loop below named its per-commit variable `path` and
every `git`/`sed` call inside the loop broke; renaming it to `rel_path`
fixed it with no other change. Never reuse `path`, `cdpath`, `fpath`,
`manpath` (or their uppercase forms) as an ordinary script variable in
anything this command runs under zsh.

Base resolution, historical-path aware (paths below are inside the `~/.claude` git history; pre-2026-08-06 `rcode/VERSION` was <!-- lint:allow -->
`torvaldsen/VERSION` — `git log --follow` tracks the rename across that
history, but you still need `--name-only` to know WHICH path name to
`git show` at each historical commit, since the path itself changed):

```bash
proj_ver=$(jq -r '.framework_version // empty' .rcode/config.json)
base_sha=""
base_relpath=""
while IFS= read -r line; do
  case "${line}" in
    commit:*)
      sha="${line#commit:}"
      ;;
    "")
      ;;
    *)
      rel_path="${line}"
      v=$(git -C ~/.claude show "${sha}:${rel_path}" | sed -n 1p)
      if [ "${v}" = "${proj_ver}" ]; then
        base_sha="${sha}"
        base_relpath="${rel_path}"
        break
      fi
      ;;
  esac
done < <(git -C ~/.claude log --follow --name-only --format="commit:%H" -- rcode/VERSION)
# base copy of a rule — derive the rails dir from the VERSION path found at that commit
# (rcode/VERSION → rcode/rules/rcode-<x>.md; pre-2026-08-06 torvaldsen/VERSION → torvaldsen/rules/torvaldsen-<x>.md):
base_rules_dir="${base_relpath%/VERSION}/rules"
# git -C ~/.claude show "${base_sha}:${base_rules_dir}/<rule file name as it was at that commit>"
```

No `cd`, no swallowed errors: `git -C ~/.claude ...` is used throughout
instead of a `cd` chain, and the loop body carries no `2>/dev/null` — a
real failure (`jq`/`git` missing, corrupt config, an unreadable object)
surfaces on stderr instead of being silently read as "no base found."

**Proof this resolves (read-only, run 2026-09-23 against this machine's
`~/.claude`):** for `proj_ver=2026-07-03` the loop above found
`base_sha=259e948a33aef46f68c6cf4b63b935edeae8d40b`,
`base_relpath=rcode/VERSION` — a commit was found, confirming the snippet
works under zsh once both traps (braces, and the `path` variable name) are
avoided.

- **Base resolved** → three-way mode; full classification in Step 4.
- **Base NOT resolved** (`framework_version` MISSING, or no commit in `~/.claude` carries that VERSION) → **conservative two-way mode.** Announce it explicitly ("cannot recover the base version [X] — treating every differing rule as potentially customized"), and classify EVERY project rule that differs from the current global copy as CUSTOMIZED. Never assume "unmodified" without the base to prove it.

---

## Step 4: DIFF & CLASSIFY

The comparison scope — the global rcode rule set as deployed to projects:

- **Core rules:** every file in `~/.claude/rcode/rules/` (enumerate with `ls`, don't hardcode — currently `rcode-workflow.md`, `rcode-commits.md`, `rcode-scope.md`).
- **Stack rules:** files in `~/.claude/rcode/templates/project-rules/` that the project has ALREADY installed in `.claude/rules/`. Never push new stack rules — the stack choice belongs to the project.
- **Legacy names:** any `.claude/rules/torvaldsen-*.md` file present in the project (pre-2026-08-06 naming — see the M3 historical-path note in Step 3).
- **Project CLAUDE.md imports:** the `@.claude/rules/<file>.md` line for every CURRENT core rule file (from the `ls` above).

For each core/stack rule file run `diff -u` (project vs current global; and project vs base where resolved) and classify:

| Project vs CURRENT global | Project vs BASE | Class | Action |
|---|---|---|---|
| identical | — | **UP-TO-DATE** | Skip silently. |
| differs | identical to base | **OUTDATED-UNMODIFIED** | Safe to update — propose (Step 5). |
| differs | differs from base too | **CUSTOMIZED** | Protected — never clobber (Step 5). |
| absent in project (new core rule in global set) | — | **NEW** | Propose install (Step 5). |
| present in project, not in the global set | — | **PROJECT-OWN** | Leave untouched — not ours. |
| present under its pre-2026-08-06 `torvaldsen-<X>.md` name AND `rcode-<X>.md` exists in the current global set | — | **RENAMED** | Propose replace + CLAUDE.md import fix (Step 5). If a found `torvaldsen-<X>.md` has NO `rcode-<X>.md` counterpart in the current global set, that is an anomaly — report it, do not guess a mapping. |

**Project CLAUDE.md imports (read-only check, findings feed Step 5):**
`Grep` the project's `CLAUDE.md` for `@.claude/rules/` lines. For every
CURRENT core rule basename: present-and-correct → fine, no finding;
present but pointing at the OLD `torvaldsen-<X>.md` name → paired with that
file's RENAMED entry above (fixed together in Step 5); missing entirely (no
import line for that rule at all, and the rule file itself is NOT a
RENAMED case) → a standalone finding, "import missing for `rcode-<X>.md`" —
Step 5 proposes adding it on its own.

Present the classification as a one-table summary before any prompting, so the user sees the whole upgrade at a glance.

---

## Step 5: PROPOSE PER FILE (y/n each — never batch-clobber)

**OUTDATED-UNMODIFIED and NEW files** — for each, show the unified diff (for NEW: "new file, [N] lines, purpose: [one-liner from its header]") and ask a per-file y/n. Lead with the recommendation (per `recommend-on-ask.md`): "Recommended: apply — your copy is unmodified from version [base], this only picks up upstream changes."

**CUSTOMIZED files** — NEVER overwrite by default. Show BOTH diffs: project-vs-base (= the project's deliberate customization) and base-vs-current (= what upstream changed). Then ask, with keep as the recommended first option:

1. **Keep project version (Recommended)** — preserves the customization; the file is recorded as a deliberate delta.
2. Overwrite with the current global version — explicitly discards the customization (only on an explicit user choice, never inferred).
3. Skip and flag for manual merge — logged in Step 7 for the user to reconcile by hand.

**RENAMED files** — one y/n per legacy file: "Recommended: replace — install `rcode-<X>.md` (current global content) at `.claude/rules/rcode-<X>.md`, remove `.claude/rules/torvaldsen-<X>.md`, and fix the CLAUDE.md import line from `@.claude/rules/torvaldsen-<X>.md` to `@.claude/rules/rcode-<X>.md`." Declining leaves the legacy file, its content, and its import line untouched — never partially apply (no rename without the matching import fix, and vice versa).

**CLAUDE.md import fixes with no RENAMED file** (the rule file is already `rcode-<X>.md` but its import line is simply missing) — a separate one y/n per missing line: "Recommended: add — the rule file is installed but not imported, so the project's CLAUDE.md never loads it." Insert the line next to the project's other `@.claude/rules/rcode-*.md` import lines; if none exist yet, add a short new block and say exactly where it was placed. Never touch any other line of CLAUDE.md — user content outside these exact import lines is off-limits.

---

## Step 6: APPLY (only what was approved)

**Rule files (OUTDATED-UNMODIFIED / NEW / CUSTOMIZED-overwrite):** `cp` each approved file from its global source into `.claude/rules/`. Then re-run `diff` on every applied file and verify it is now **identical** to the current global copy — surface any mismatch immediately (fail-loud), do not paper over it.

**RENAMED files (approved):** `cp` the current global `rcode-<X>.md` into `.claude/rules/rcode-<X>.md`; then `git rm .claude/rules/torvaldsen-<X>.md` (stages the removal in the project's index — nothing is committed yet, see Step 7); then `Edit` the CLAUDE.md import line as described in Step 5. Verify the new file is identical to the global copy the same way as above.

**CLAUDE.md-only import fixes (approved):** `Edit` the single line; verify with `Grep` that the new line is present and no other line changed.

No writes beyond the approved set.

---

## Step 7: STAMP + LOG + REPORT

**Version bump rule:** set `framework_version` to the current global version ONLY if no OUTDATED-UNMODIFIED or NEW file was declined. A declined upstream update leaves the version un-bumped, so a re-run honestly re-proposes it. Kept CUSTOMIZED files do NOT block the bump — they are deliberate project deltas, recorded below. Also stamp the field when it was MISSING (legacy scaffold).

Update `.rcode/config.json` via `Edit` — change `framework_version` only (the `tracker` field, if it was added, was already written in Step 2); preserve every other field verbatim, especially `created_date` / `migrated_date` / `workflow_version` (A7).

Append to `.rcode/agent-log.md` — **APPEND-ONLY**, never rewrite or truncate existing entries:

```markdown
## Session: Upgrade

**Date:** [today]
**Agent:** rcode-upgrade

**Actions:**
- Upgraded R.Code rails: framework_version [old → new | unchanged — updates declined | stamped (was missing)]
- Tracker field: [added "github"/"plan" after asking | already set | n/a]
- Updated: [files | none]
- Newly installed: [files | none]
- Renamed (legacy torvaldsen-*.md → rcode-*.md): [files | none]
- CLAUDE.md imports fixed: [lines/files | none]
- Kept (customized, protected): [files | none]
- Declined: [files | none]
- Flagged for manual merge: [files | none]
```

**Commit offer (A9 — no silent commit).** If Steps 2–6 touched at least one file, ask ONE y/n:

> Commit these rail updates now? (recommended: yes — uncommitted stamps rotted in 3 of 5 projects measured 2026-09-23)
> [If the current branch is a trunk branch (`main`/`master`/`development`), add: "this lands directly on `<branch>`."]

- **yes** → `git add` exactly the touched files (rule files applied/renamed/removed, `.rcode/config.json`, `.rcode/agent-log.md`, CLAUDE.md if fixed — never `git add -A`/`-u`), then one commit: `git commit -m "chore(rcode): upgrade rails to <new version>"`. Never push.
- **no** → print the exact `git add <files> && git commit -m "chore(rcode): upgrade rails to <new version>"` line for the user to run by hand.

If nothing was touched (clean idempotent no-op), skip the commit offer entirely — there is nothing to commit.

End with the summary:

```
R.Code Upgrade — [complete | partial | nothing to do]

framework_version: [old] → [new]   (global: ~/.claude/rcode/VERSION)
tracker: [added <value> | already set <value>]
Updated: [N]   New: [N]   Renamed: [N]   Customized-kept: [N]   Declined: [N]   Manual-merge: [N]   CLAUDE.md imports fixed: [N]

[Committed as <sha> | Nothing was committed — run: <git add ... && git commit ...>]
```
