<!--
Status: ACTIVE
Last Updated: 2026-11-23
Purpose: Long form of the slop-prevention rule: the three triggers, verification principles and anti-patterns
-->

Long form of `rules/slop-prevention.md`. Not loaded automatically.

# Slop Prevention Rule

> Ban extending unverified AI code. Long form; read on demand.

## The Rule

**An agent must not extend, refactor, or build on top of AI-generated code that has not been verified.** Verification = compiles + tests pass + key logic human-reviewed.

## "Slop-on-Slop" Math

`P(end-state correct) = P(step correct)^N` — unverified scaffolds and ignored errors drop `P(step)` to about 0.7–0.8, and `P(end)` collapses exponentially.

## The Three Triggers

### Trigger 1 — Type errors / lint errors present
**The gate is on the error TREND, not the error COUNT.** What is forbidden is **adding new functionality** to a file that still has unresolved compile/type errors: that is building on slop.

- ✅ **Allowed / encouraged:** edits that hold the error count flat or drive it down (fixing the type error, narrowing a type, removing the broken call).
- ❌ **Forbidden:** edits that *add* features, branches or call sites while the error count stays the same or rises; "I'll fix the type error later" is no excuse.

The operational test is **"does this edit decrease (or hold) the file's error count?"** — not "is the error count zero?"; an error count that does **not** decrease across an edit whose stated purpose was unrelated to those errors is the violation. Run the type-check first (`npx tsc --noEmit` / `mypy` / `swift build`); while errors exist, the next edits must aim at reducing them.

### Trigger 2 — Recently AI-generated code being extended
**Forbidden:** extending a function/file/module that was AI-generated in the last 24h **without verification first.** Check `git log -p <file>` for recent AI-generated commits (`Co-Authored-By: Claude`); if found, read the code, run the tests, manually verify behavior — only then extend.

### Trigger 3 — Visible claim without rendered proof
**Forbidden:** declaring a VISIBLE state (UI, game graphics, layout, render output) "fixed" or "done" on the basis of a declaration/data-structure check. A completion claim about anything the user will *look at* is only valid with proof against the rendered result — a screenshot of the running program / the rendered page — never a check of the source declaration or data structure that merely feeds the render. A green test suite does not cover this gate.

**Self-referential tests are forbidden:** a test that reads the same source the fix wrote (e.g. asserting on the just-edited atlas/config entry instead of on what the renderer produces) can only agree with itself — it proves nothing about the visible outcome.

**Check against the SOURCE, never against your own paraphrase:** the comparison target is the primary artifact — the file on disk, the PDF, the screenshot the *user* sent, the running program — not your summary of it, not the plan's restatement, not what a sub-agent reported it says.

**Describe what you see, then judge.** At every checkpoint, first write down what is *actually visible* in the artifact (which elements, colors, positions, values), and only then state whether it matches the claim.

Workflow:
1. Before claiming "fixed"/"done" on a visible state, run or render the artifact.
2. Capture a screenshot (or equivalent direct observation) of the actual output.
3. **Describe** the relevant part in words — per checkpoint, one line of what is there.
4. Compare the description against the claim, and the claim against the **source** — not against the edited declaration, not against any paraphrase of the requirement.
5. If no rendering step exists yet, build one before making the completion claim.
6. **Report verdict-first.** The first line of every completion report, visual or not, is `Done: yes` or `Done: no — missing: <list>`, scoped per visible surface (`verified` / `not checked`). An unchecked surface the user can see is never covered by a completion-flavored sentence.

## How to Apply

### Pattern: Fresh-Agent Review Before Extension
Before extending a larger unverified AI scaffold, spawn a fresh-context `code-reviewer-agent` (a small one you verify yourself: read it and run its tests): it reviews the scaffold cold, names issues, half-implementations and silent fallbacks, and returns "verified safe to extend" or "fix these N issues first".

### Pattern: "Copy, don't interpret" (Abschreiben, nicht deuten)
**Sub-agents get pointed at the SOURCE, never at the orchestrator's paraphrase of it.** In every brief:
- Name the artifact by absolute path (and section/symbol), so the sub-agent reads it itself.
- Quote any explicit user instruction **verbatim** (`agents/control-agent.md` §3 — the sub-agent may not overrule it, only escalate).
- Where you must summarize for context, mark it as your summary and still point at the source.

### Pattern: Adversarial counter-check
After an implementation wave that claims conformance to a spec, source or design, spawn a **separate** agent whose stated job is to **find deviations**, not to confirm the work: brief it "find every place this does NOT match, list them" — never "verify this matches", which invites agreement. Run it as a second phase with a typed result schema (a list of deviations with locations), so an empty result is a real finding.

## Verification principles (IMP-158)

**Verify at the sink, not the suite:** a fix to a filter, exclusion or manifest gate that stops data reaching an external backend is proven only at the real sender/output — which files or records the external tool really receives: a capture of the real invocation parameters, or a dry run printing the real target list. A green suite that checks a flag or counter is not that proof. This holds for any data-sink fix, not only bulk-pipeline runs. **Verify via the same code path:** when verification counts or resolves what production also counts or resolves, call the same resolution code — a second, independently written counter drifts and passes while the real path stays broken; a bespoke recount is itself a defect class, not a safety margin. **Automatic check results belong to their trigger:** if your action caused a check to run (security review, lint pass, async verification), retrieve its result before claiming fixed or done — triggering it is not enough. This is a duty on the work thread, whether a Claude-Code-bundled feature (e.g. `/security-review`) or a repo hook produced the check: a finding logged where nobody reads it is functionally silent.

## Enforcement

No PreToolUse type-error gate exists. `hooks/stop-batched-checks.sh` runs type-check and lint per project at Stop, and the R.Code phase-gate runs type-check + tests before unlocking the next phase; the fresh-agent review above is the pre-extension check.

**Anti-patterns:** passing tests on unverified code prove only that the slop passes the tests — manual review of NEW logic is mandatory; after "make the tests pass", always diff (deleted tests, weakened assertions, commented-out cases); before tightening a check, ask what artifact it reads — if the fix wrote that artifact, no hardening turns it into evidence.

Ledger: IMP-143, IMP-158, IMP-160.
