# Slop Prevention Rule

> Ban extending unverified AI code. Always loaded.

## The Rule

**An agent must not extend, refactor, or build on top of AI-generated code that has not been verified.** Verification = compiles + tests pass + key logic human-reviewed.

## "Slop-on-Slop" Math

Compounding agent reliability: `P(end-state correct) = P(step correct)^N`

**Adding silent slop to the chain** (unverified scaffolds, ignored type errors, untested code) drops `P(step)` to ~0.7–0.8, making `P(end)` approach zero exponentially:

| P(step) | 20 steps → P(end) |
|---|---|
| 0.95 | 36% — already shaky |
| 0.85 | 4% — broken |
| 0.75 | 0.3% — useless |

## The Three Triggers

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

### Trigger 3 — Visible claim without rendered proof
**Forbidden:** Declaring a VISIBLE state (UI, game graphics, layout, render output) "fixed" or "done" on the basis of a declaration/data-structure check. A completion claim about anything the user will *look at* is only valid with proof against the rendered result — a screenshot of the running program / the rendered page — never a check of the source declaration or data structure that merely feeds the render.

**Self-referential tests are forbidden:** a test that reads the same source the fix wrote (e.g. asserting on the atlas/config entry that was just edited, instead of on what the renderer actually produces) can only agree with itself — it proves nothing about the visible outcome.

**Check against the SOURCE, never against your own paraphrase.** The comparison target is the primary artifact — the file on disk, the PDF, the screenshot the *user* sent, the running program — not your summary of it, not the plan's restatement of it, not what a sub-agent reported it says. A paraphrase was already filtered through the same expectation that produced the bug; comparing against it can only confirm the expectation.

**Describe what you see, then judge.** At every checkpoint, first write down what is *actually visible* in the artifact (which elements, which colors, which positions, which values), and only then state whether it matches the claim. Naming the observation before the verdict is the working defense against confirmation bias. A verdict with no description behind it is not an inspection; it is a guess wearing an inspection's clothes.

Workflow:
1. Before claiming "fixed"/"done" on a visible state, run or render the artifact.
2. Capture a screenshot (or equivalent direct observation) of the actual output.
3. **Describe** the relevant part of that output in words — per checkpoint, one line of what is there.
4. Compare the description against the claim, and the claim against the **source** — not against the declaration that was edited, and not against any paraphrase of the requirement.
5. If no rendering step exists yet, build one before making the completion claim, not after the fact.
6. **Report verdict-first.** The first line of every completion report, visual or not, is `Done: yes` or `Done: no — missing: <list>`, scoped per visible surface (`verified` / `not checked`). An unchecked surface the user can see is never covered by a completion-flavored sentence.

A discipline agreed only in chat is not enforced — it lives here, in this rule.

**Four error types** (IMP-160), each with its own countermeasure — fixing one leaves the others live: circular check, checking against your own paraphrase, confirmation bias (countered above and by the patterns below), and a sub-agent overruling an explicit user instruction (`agents/control-agent.md` §3/§4).

## How to Apply

### Pattern: Fresh-Agent Review Before Extension
Before extending unverified AI scaffolds, spawn a fresh-context `code-reviewer-agent`:
- Reviews the AI scaffold cold (no prior context contamination)
- Identifies issues, half-implementations, silent fallbacks
- Returns "verified safe to extend" or "fix these N issues first"

### Pattern: "Copy, don't interpret" (Abschreiben, nicht deuten)

**Sub-agents get pointed at the SOURCE, never at the orchestrator's paraphrase of it.** A delegation brief hands over the file path, the quoted requirement, the user's screenshot — not a summary. The orchestrator's summary was written by the same context that is about to be wrong; passing it down turns one agent's misreading into every sub-agent's premise, and no amount of downstream diligence can recover the dropped detail.

Concretely, in every brief:
- Name the artifact by absolute path (and section/symbol), so the sub-agent reads it itself.
- Quote any explicit user instruction **verbatim** rather than restating it (see `agents/control-agent.md` §3 — the sub-agent may not overrule it, only escalate).
- Where you must summarize for context, mark it as your summary and still point at the source.

### Pattern: Adversarial counter-check (an agent that HUNTS for deviations)

After an implementation wave that claims conformance to a spec, source, or design, spawn a **separate** agent whose stated job is to **find deviations**, not to confirm the work. The brief matters: "verify this matches" invites agreement; "find every place this does NOT match, list them" invites the opposite.

Run it as a second phase with a typed result schema (a list of deviations with locations), so an empty result is a real finding rather than the absence of a report.

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

### ❌ "Hardening" a check that was never looking at the right thing
Making a circular check stricter makes it stricter at agreeing with itself. Before tightening a check, ask what artifact it reads — if that artifact is the same one the fix wrote, no amount of hardening turns it into evidence.

### ❌ Handing a sub-agent your summary of the user's instruction
See *"Copy, don't interpret"* above. The paraphrase is where the requirement quietly loses the detail that mattered.

## References

- Trigger 3: IMP-143, `plans/meta-proposal-2026-08-23-chat-analyse.md`; companion paragraph in `testing-quality.md` ("Rendered-Proof for Visual Claims")

> Evidence and incident history (moved verbatim, IMP-217): `docs/archive/rules-evidence/slop-prevention.md`
