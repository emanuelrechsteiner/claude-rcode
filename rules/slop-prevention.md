# Slop Prevention Rule

> Ban extending unverified AI code. Triangulated from Replit ByBench + Cline 4-levels + Matt Pocock + Mario Zechner (KB cluster 09 + 18, 2026-05-26). Always loaded.

## The Rule

**An agent must not extend, refactor, or build on top of AI-generated code that has not been verified.** Verification = compiles + tests pass + key logic human-reviewed.

## "Slop-on-Slop" Math

Compounding agent reliability: `P(end-state correct) = P(step correct)^N`

If `P(step correct) = 0.95` and you have 20 steps: `P(end) = 36%`.

**Adding silent slop to the chain** (unverified scaffolds, ignored type errors, untested code) drops `P(step)` to ~0.7–0.8, making `P(end)` approach zero exponentially:

| P(step) | 20 steps → P(end) |
|---|---|
| 0.95 | 36% — already shaky |
| 0.85 | 4% — broken |
| 0.75 | 0.3% — useless |

This is the "slop-on-slop" failure mode demonstrated in Replit ByBench.

## The Two Triggers

### Trigger 1 — Type errors / lint errors present
**The gate is on the error TREND, not the error COUNT.** Edits whose purpose is to *reduce* the unresolved-error set are explicitly **encouraged** — fixing a type error is the very thing that clears the file. What is forbidden is **adding new functionality** to a file that still has unresolved compile/type errors: that is building on slop.

- ✅ **Allowed / encouraged:** edits that hold the error count flat or drive it down (fixing the type error, narrowing a type, removing the broken call). The fix-the-error edit is never blocked.
- ❌ **Forbidden:** edits that *add* features, branches, or call sites to a file while its error count stays the same or rises — i.e. extending unverified-because-uncompiling code.

The operational test is **"does this edit decrease (or hold) the file's error count?"** — not "is the error count zero?". An error count that does **not** decrease across an edit whose stated purpose was unrelated to those errors is the violation.

Workflow:
1. Run type-check first: `npx tsc --noEmit` / `mypy` / `swift build`
2. If errors exist → the next edits must be aimed at *reducing* them. Do not bolt new functionality onto the still-broken file.
3. Once the file type-checks clean (or your edit has measurably reduced the error set), proceed.

### Trigger 2 — Recently AI-generated code being extended
**Forbidden:** Extending a function/file/module that was AI-generated in the last 24h **without verification first.**

Workflow:
1. Check `git log -p <file>` for recent AI-generated commits (`Co-Authored-By: Claude`)
2. If recent AI commit found: read the code, run tests, manually verify behavior
3. Only after verification: extend

## How to Apply

### Pattern: Fresh-Agent Review Before Extension
Before extending unverified AI scaffolds, spawn a fresh-context `code-reviewer-agent`:
- Reviews the AI scaffold cold (no prior context contamination)
- Identifies issues, half-implementations, silent fallbacks
- Returns "verified safe to extend" or "fix these N issues first"

### Pattern: Type-Check Gate
Gate on the error *trend* across an edit, not on a nonzero count — otherwise the gate blocks the very edit that fixes the error. Capture a baseline error count, and only refuse an edit when the count fails to decrease for an edit that did not claim to be a fix:
```bash
# In .rcode/phase-gate.sh or via PreToolUse hook
# Baseline error count is recorded BEFORE the edit; compared AFTER.
before=$(npx tsc --noEmit 2>&1 | grep -c 'error TS')
# ... edit happens ...
after=$(npx tsc --noEmit 2>&1 | grep -c 'error TS')
if [ "$after" -gt "$before" ]; then
  echo "Error count rose ($before → $after) — edit added slop on top of broken code"
  exit 1
fi
# Holding flat or decreasing is fine — fixing edits and refactors-toward-green pass.
```

## Enforcement

- PreToolUse hook — block `Edit` only when it would **add functionality** to a file with unresolved type-errors (error count not decreasing). Edits that reduce the error set pass.
- `code-reviewer-agent` invocation pattern in control-agent workflows
- Phase-gate command runs type-check + test before unlocking next phase (already in R.Code)

## Anti-Patterns

### ❌ "I'll fix the type error later" — then add a feature on top
Deferring the fix while extending the broken file is the violation. Later never comes; the slop compounds. Fixing the error *now* is always allowed — it is the deferral-plus-extension that is banned.

### ❌ Cline's "Level 4: full autonomy"
Cline talk demonstrates 4 levels of agent autonomy. Level 4 ("full autonomy") has measurably worse outcomes than Level 2 ("plan + review per step") on real codebases. Default to Level 2.

### ❌ Skipping verification because "the test passes"
Passing tests on slop only proves the slop passes the tests. Not that the code is right. Manual review of NEW logic is mandatory.

### ❌ Asking Claude to "make the tests pass" without reviewing what it changed
The agent may delete the test, weaken the assertion, or comment out the failing case. Always diff.

## References

- Replit ByBench benchmark — "slop-on-slop" failure mode
- Cline talk — 4 levels of agent autonomy; Level 4 worse outcomes
- Matt Pocock — "Full Walkthrough" — vertical slices + verification
- Mario Zechner — "Building pi in a World of Slop"
- Cluster source: see author's knowledge base (private)
