# Slop Prevention Rule

> Ban extending unverified AI code. Always loaded.

## The Rule

**An agent must not extend, refactor, or build on top of AI-generated code that has not been verified.** Verification = compiles + tests pass + key logic human-reviewed.

## "Slop-on-Slop" Math

Compounding agent reliability: `P(end-state correct) = P(step correct)^N`; silent slop (unverified scaffolds, ignored type errors, untested code) drops `P(step)` to ~0.7–0.8, and `P(end)` approaches zero exponentially.

## The Three Triggers

### Trigger 1 — Type errors / lint errors present
**The gate is on the error TREND, not the error COUNT.** What is forbidden is **adding new functionality** to a file that still has unresolved compile/type errors: that is building on slop.

- ✅ **Allowed / encouraged:** edits that hold a file's unresolved compile/type-error count flat or drive it down (fixing the type error, narrowing a type, removing the broken call). The fix-the-error edit is never blocked.
- ❌ **Forbidden:** edits that *add* features, branches, or call sites to such a file while its error count stays the same or rises — building on slop. "I'll fix the type error later" is no excuse: fixing *now* is always allowed, deferral-plus-extension is banned.

The operational test is **"does this edit decrease (or hold) the file's error count?"** — not "is the error count zero?"; an error count that does **not** decrease across an edit whose stated purpose was unrelated to those errors is the violation. Run the type-check first (`npx tsc --noEmit` / `mypy` / `swift build`); while errors exist, the next edits must be aimed at *reducing* them — do not bolt new functionality onto the still-broken file; proceed once the file type-checks clean (or your edit has measurably reduced the error set).

### Trigger 2 — Recently AI-generated code being extended
**Forbidden:** extending a function/file/module that was AI-generated in the last 24h **without verification first.** Check `git log -p <file>` for recent AI-generated commits (`Co-Authored-By: Claude`); if found, read the code, run the tests, manually verify behavior — only then extend.

### Trigger 3 — Visible claim without rendered proof
**Forbidden:** declaring a VISIBLE state (UI, game graphics, layout, render output) "fixed" or "done" on the basis of a declaration/data-structure check. A completion claim about anything the user will *look at* is only valid with proof against the rendered result — a screenshot of the running program / the rendered page — never a check of the source declaration or data structure that merely feeds the render.

**Self-referential tests are forbidden:** a test that reads the same source the fix wrote (e.g. asserting on the just-edited atlas/config entry instead of on what the renderer produces) can only agree with itself — it proves nothing about the visible outcome.

**Check against the SOURCE, never against your own paraphrase.** The comparison target is the primary artifact — the file on disk, the PDF, the screenshot the *user* sent, the running program — not your summary of it, not the plan's restatement of it, not what a sub-agent reported it says; a paraphrase was already filtered through the expectation that produced the bug.

**Describe what you see, then judge.** At every checkpoint, first write down what is *actually visible* in the artifact (which elements, colors, positions, values), and only then state whether it matches the claim — naming the observation before the verdict is the defense against confirmation bias; a verdict with no description behind it is a guess, not an inspection.

Workflow:
1. Before claiming "fixed"/"done" on a visible state, run or render the artifact.
2. Capture a screenshot (or equivalent direct observation) of the actual output.
3. **Describe** the relevant part in words — per checkpoint, one line of what is there.
4. Compare the description against the claim, and the claim against the **source** — not against the edited declaration, not against any paraphrase of the requirement.
5. If no rendering step exists yet, build one before making the completion claim.
6. **Report verdict-first.** The first line of every completion report, visual or not, is `Done: yes` or `Done: no — missing: <list>`, scoped per visible surface (`verified` / `not checked`). An unchecked surface the user can see is never covered by a completion-flavored sentence.

**Four error types** (IMP-160), each with its own countermeasure — fixing one leaves the others live: circular check, checking against your own paraphrase, confirmation bias (countered above and by the patterns below), and a sub-agent overruling an explicit user instruction (`agents/control-agent.md` §3/§4). A discipline agreed only in chat is not enforced; it lives in this rule.

## How to Apply

### Pattern: Fresh-Agent Review Before Extension
Before extending unverified AI scaffolds, spawn a fresh-context `code-reviewer-agent`: it reviews the scaffold cold, identifies issues, half-implementations, and silent fallbacks, and returns "verified safe to extend" or "fix these N issues first".

### Pattern: "Copy, don't interpret" (Abschreiben, nicht deuten)

**Sub-agents get pointed at the SOURCE, never at the orchestrator's paraphrase of it:** the brief hands over the file path, the quoted requirement, the user's screenshot — not a summary, which comes from the same context that is about to be wrong and, passed down, turns one misreading into every sub-agent's premise. In every brief:
- Name the artifact by absolute path (and section/symbol), so the sub-agent reads it itself.
- Quote any explicit user instruction **verbatim** (`agents/control-agent.md` §3 — the sub-agent may not overrule it, only escalate).
- Where you must summarize for context, mark it as your summary and still point at the source.

### Pattern: Adversarial counter-check (an agent that HUNTS for deviations)

After an implementation wave that claims conformance to a spec, source, or design, spawn a **separate** agent whose stated job is to **find deviations**, not to confirm the work: "find every place this does NOT match, list them" (not "verify this matches", which invites agreement). Run it as a second phase with a typed result schema (a list of deviations with locations), so an empty result is a real finding rather than the absence of a report.

## Enforcement

A PreToolUse hook blocks `Edit` only when it would **add functionality** to a file with unresolved type-errors (error count not decreasing); edits that reduce the error set pass. Also: the `code-reviewer-agent` invocation pattern in control-agent workflows; the R.Code phase-gate runs type-check + test before unlocking the next phase.

## Anti-Patterns

- ❌ **Cline's "Level 4: full autonomy"** — measurably worse outcomes than Level 2 ("plan + review per step") on real codebases. Default to Level 2.
- ❌ **Skipping verification because "the test passes"** — passing tests on slop only prove the slop passes the tests. Manual review of NEW logic is mandatory.
- ❌ **Asking Claude to "make the tests pass" without reviewing what it changed** — it may delete the test, weaken the assertion, or comment out the failing case. Always diff.
- ❌ **"Hardening" a check that was never looking at the right thing** — a stricter circular check only agrees with itself more strictly. Before tightening a check, ask what artifact it reads; if the fix wrote that artifact, no hardening turns it into evidence.

References: Trigger 3 — IMP-143, `plans/meta-proposal-2026-08-23-chat-analyse.md`; companion paragraph in `testing-quality.md` ("Rendered-Proof for Visual Claims").
