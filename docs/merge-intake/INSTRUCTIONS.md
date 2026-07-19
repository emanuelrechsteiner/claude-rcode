# External Config Merge — Intake Instructions

> **For the Claude Code agent running on a machine with a *different* `~/.claude/` config.**
> You were pointed at this file after the user cloned `claude-rcode` somewhere on that machine. Read this entire file before doing anything.

## Your role (read twice)

You are **not** merging anything. You are a **collector and reporter**.

- **`baseline`** = the `claude-rcode` repo you were cloned from (the curated, public framework, currently v1.0.0).
- **`local`** = this machine's live `~/.claude/` config — accumulated over time, possibly diverged, possibly containing private project data and secrets.

Your job: produce a structured **intake branch** that a maintainer on the baseline machine reviews and triages. You do **not** decide what is "better," you do **not** overwrite baseline files, you do **not** merge into `main`. You surface differences and summarize accumulated experience. That's it.

Why so narrow: you don't have the context of the refactor decisions that produced v1.0.0. A confident merge from you would silently undo deliberate choices. Collection + reporting is safe; merging is not.

---

## HARD SAFETY GATES — violating any of these is a failure

1. **This repo is PUBLIC.** Treat everything you stage for push as world-readable forever.
2. **NEVER push secrets.** Run the secret scan (Step 2) before every push. Any hit → STOP, exclude the file, note it in the report.
3. **NEVER raw-copy private data.** Do not copy anything under `local`'s `projects/`, `global-observation/*.jsonl`, `*.local.*`, `.credentials.json`, `history.jsonl`, `sessions/`, `tasks/`, `shell-snapshots/`, or caches into the pushed branch. Memory/experience gets **summarized in prose** in the report, never pasted raw.
4. **NEVER overwrite baseline files.** Work only inside `docs/merge-intake/<label>/`. The point of the diff is lost if you edit the baseline.
5. **NEVER push to `main`.** Push only to a branch named `merge-intake/<label>` (see Step 6).
6. If anything is ambiguous, **write it in the report as an open question** rather than guessing.

Motivation for gate #2: in the session that produced v1.0.0, a live Firecrawl API key (`fc-…`) was found committed in `settings.local.json` and had to be scrubbed from history. Assume `local` has a similar landmine until the scan proves otherwise.

---

## Step 0 — Orient

Establish the two paths and confirm they're distinct.

```bash
# baseline = the clone you're reading this from
BASELINE="$(git rev-parse --show-toplevel)"
echo "baseline: $BASELINE"

# local = the machine's live config
LOCAL="$HOME/.claude"
echo "local:    $LOCAL"

# Sanity: they must NOT be the same directory
[ "$BASELINE" = "$LOCAL" ] && { echo "ABORT: you cloned over the live config. Re-clone into a scratch dir."; exit 1; }

# Is local even a git repo? (changes how you read its history)
( cd "$LOCAL" && git rev-parse --is-inside-work-tree 2>/dev/null && echo "local is git-tracked" ) || echo "local is NOT git-tracked"

# A label for this intake (machine + date)
LABEL="$(hostname -s | tr '[:upper:]' '[:lower:]')-$(date +%Y-%m-%d)"
echo "label: $LABEL"
```

Record `BASELINE`, `LOCAL`, and `LABEL` — you'll reuse them.

---

## Step 1 — Framework file diff

Compare only the framework directories (the portable, shareable parts). Skip state/data dirs entirely.

```bash
for d in rules skills hooks agents commands templates routines system; do
  echo "===== $d ====="
  diff -rq "$BASELINE/$d" "$LOCAL/$d" 2>/dev/null
done
```

`diff -rq` output tells you three buckets:
- **"Only in $LOCAL/…"** → local-only files (candidates to port).
- **"Files … differ"** → present in both but diverged (3-way reconciliation needed).
- **"Only in $BASELINE/…"** → baseline-only (already covered, ignore).

Keep this raw output — it goes into the report.

---

## Step 2 — Secret + personal scan (MANDATORY before copying anything)

For every **local-only** or **differing** file you're considering, scan it. Any hit means that file does **not** get copied into the intake — instead you note it in the report as "contains sensitive content — manual review needed."

```bash
# Secret patterns (superset of baseline's security-audit.sh)
SECRET_RE='fc-[a-zA-Z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[0-9A-Za-z-]{10,}'

# Personal-data patterns (tune to the user's identities/projects as you discover them)
PERSONAL_RE='/Users/[a-z]+/|/Volumes/|@[a-z]+\.(com|de|dev)|[A-Z][a-z]+ [A-Z][a-z]+ <[^>]+@'

# Example scan of a candidate file:
grep -nE "$SECRET_RE" <file> && echo "SECRET HIT — exclude" || echo "secret-clean"
grep -nE "$PERSONAL_RE" <file> && echo "personal refs — scrub or note" || echo "personal-clean"
```

Rule: **secret hit → never copy, flag loudly.** Personal-ref hit → either scrub the refs (replace paths/names with placeholders) before copying, or leave the file out and describe it in the report.

---

## Step 3 — Build the intake quarantine

```bash
INTAKE="$BASELINE/docs/merge-intake/$LABEL"
mkdir -p "$INTAKE/framework-candidates"
```

Copy **only** framework files that (a) are local-only or meaningfully newer, AND (b) passed the secret scan, into `framework-candidates/`, preserving their relative path (e.g. `framework-candidates/rules/my-rule.md`). Scrub personal refs as you copy.

Do **NOT** copy: anything under `projects/`, `global-observation/`, `*.local.*`, secrets, caches, `history.jsonl`, `sessions/`, `tasks/`, `shell-snapshots/`, `node_modules/`, `__pycache__/`.

---

## Step 4 — Harvest experience (summarize, never paste raw)

This is the highest-value part and the most privacy-sensitive. The accumulated "experience" lives in:
- `local`'s `~/.claude/projects/*/memory/*.md` (per-project memories)
- `local`'s `~/.claude/global-observation/improvement-ledger.json` (IMP entries)
- Personal additions inside `local`'s `CLAUDE.md` / `MEMORY_FIRST.md`

Read them. In the report, **summarize in your own words** what exists locally that appears **absent from the baseline**: lessons learned, recurring bug patterns, workflow rules, IMP proposals, tool-discipline findings. Reference them by theme and value — **do not paste** raw memory content (it names private projects and clients).

For each item, suggest a target shape: "would become a new rule", "would become an IMP-ledger entry", "is a personal preference → `.local.*` overlay", or "looks obsolete".

To compare against the baseline's own ledger, read `$BASELINE/global-observation/improvement-ledger.json` (it's anonymized and committed).

---

## Step 5 — Write the report

Write `$INTAKE/REPORT.md` using exactly this structure:

```markdown
# Merge Intake Report — <label>

## Summary
- Local config git-tracked: yes/no
- Framework files: <N> local-only, <M> differing, <K> baseline-only
- Framework candidates copied (secret-clean): <count>
- Files excluded for secrets: <count>  ← list them
- Experience items worth porting: <count>

## A. Framework — local-only files (copied to framework-candidates/)
| Path | Purpose (1 line) | Secret scan | Recommendation |
|------|------------------|-------------|----------------|
| rules/x.md | … | clean | port upstream / personal → .local / obsolete |

## B. Framework — files that differ in both
| Path | Nature of difference | Which looks newer/better | Notes |
|------|----------------------|--------------------------|-------|

## C. Experience harvest (summarized, NOT pasted)
For each: theme · what the lesson/pattern is · why it has value · suggested target shape.
- …

## D. Excluded for secrets / sensitive content (NOT copied)
| Path | What was detected | What a maintainer should do |
|------|-------------------|------------------------------|

## E. Open questions for the maintainer
- …
```

---

## Step 6 — Commit & push the intake branch

```bash
cd "$BASELINE"
git checkout -b "merge-intake/$LABEL"

# Final secret scan on the STAGED diff (belt and suspenders)
git add "docs/merge-intake/$LABEL"
git diff --cached | grep -nE "$SECRET_RE" && { echo "ABORT: secret in staged diff"; exit 1; }

git commit -m "merge-intake: external config from <label>

Collected (not merged) framework candidates + experience summary from a
diverged ~/.claude/ config. For maintainer triage against baseline.
No secrets, no raw memory, no baseline files modified."

git push -u origin "merge-intake/$LABEL"
```

Then report back to the user with: the branch name, the counts from the summary, and anything in section D/E that needs a human decision.

---

## What you must NOT do (final checklist)

- ❌ Merge into `main` or any baseline branch
- ❌ Modify or delete any baseline file outside `docs/merge-intake/<label>/`
- ❌ Push secrets, `.local.*`, `projects/`, `global-observation/*.jsonl`, or raw memory
- ❌ Decide "this is better and should win" — that's the maintainer's call
- ❌ `git push --force` anything
- ✅ Collect, scan, summarize, push an intake branch, report back

---

## After you push (what happens next, FYI)

The maintainer on the baseline machine reviews `merge-intake/<label>`, triages each candidate into: (a) cherry-pick upstream as a real commit, (b) hand back as a `.local.*` overlay, or (c) discard. Once triaged, the intake branch is deleted. You don't need to do any of that — your job ends at "pushed + reported."
