<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/slop-prevention.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/slop-prevention.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Slop Prevention Rule (original intro line under the title)

> Ban extending unverified AI code. Triangulated from Replit ByBench + Cline 4-levels + Matt Pocock + Mario Zechner (KB cluster 09 + 18, 2026-05-26). Always loaded.

## "Slop-on-Slop" Math

This is the "slop-on-slop" failure mode demonstrated in Replit ByBench.

## Trigger 3 — Visible claim without rendered proof

_Original version of the "Describe what you see, then judge." paragraph (shortened in the rule by removing the quote and the date):_

**Describe what you see, then judge.** At every checkpoint, first write down what is *actually visible* in the artifact (which elements, which colors, which positions, which values), and only then state whether it matches the claim. Naming the observation before the verdict is the working defense against confirmation bias — the failure mode is literally *"I saw what I expected to see"* (self-diagnosis, 2026-08-09, said in German). A verdict with no description behind it is not an inspection; it is a guess wearing an inspection's clothes.

**Evidence:** proj-902a42, 2026-08-09 — "You 'fixed' them ... when playing they're EXACTLY the same ... NOTHING AT ALL" (said in German) — the same false "fixed" claim recurred **≥9 times across 5 sessions** (the atlas/asset declaration was checked, never the render). **The 09→12.08 lesson:** a testing discipline that was merely *agreed on in chat* on 2026-08-09 did not survive to 2026-08-12 — the identical failure recurred three days later. A discipline that lives only in chat history is not enforced; it has to live here, as a rule the agent re-reads every session, not as a one-time chat agreement.

_Original version of the intro and the four-error-type table (shortened in the rule to drop the counts and transcript quotes):_

**The four error types** behind the wider count — **13 "fixed without visual inspection" incidents across 7 days** (IMP-160), of which the ≥9 above are the visible-claim subset. All four were self-diagnosed in the same transcript; each has its own countermeasure, and fixing only the first leaves the other three live:

| # | Error type | Countermeasure |
|---|---|---|
| 1 | **Circular check** — *"The test derives its expectation from the same declaration it's meant to check ... I even 'hardened' this check yesterday — harder in the mechanism, still blind to the picture"* (said in German) | Trigger 3 above: prove against the render, not the declaration |
| 2 | **Checking against one's own paraphrase** instead of the source | "Check against the SOURCE" above + the *"Copy, don't interpret"* pattern below |
| 3 | **Confirmation bias when looking** — *"I saw what I expected to see"* (said in German) | "Describe what you see, then judge" above + the adversarial counter-check below |
| 4 | **Sub-agent replaces an explicit user instruction with its own judgement**, and the orchestrator waves it through — *"That's my failure"* (said in German) | `agents/control-agent.md` §3 (verbatim instruction travels with the brief; deviation escalates, never decides) + §4 synthesis check |

## Pattern: Adversarial counter-check (an agent that HUNTS for deviations)

**Counter-evidence that this works:** proj-1df43a, 2026-07-13 — a dedicated deviation-hunting agent found **39 real deviations** that the implementing strand could not see itself. It is the only pattern in the August corpus demonstrated to surface errors the executing thread was structurally blind to.

## References

_Original lines; the rule now carries only the IMP IDs and file paths:_

- Replit ByBench benchmark — "slop-on-slop" failure mode
- Cline talk — 4 levels of agent autonomy; Level 4 worse outcomes
- Matt Pocock — "Full Walkthrough" — vertical slices + verification
- Mario Zechner — "Building pi in a World of Slop"
- Cluster source: see author's knowledge base (private)
- Trigger 3: proj-902a42 chat-transcript evidence (2026-08-09 → 2026-08-12, ≥9 recurrences) — IMP-143, `plans/meta-proposal-2026-08-23-chat-analyse.md`; companion paragraph in `testing-quality.md` ("Rendered-Proof for Visual Claims")
- Trigger 3 extension (source-not-paraphrase, describe-before-judging, four-error table) + the two patterns above: IMP-160/IMP-167 — `plans/meta-proposal-2026-08-24-august-vollanalyse.md` §2 (13 incidents / 7 days, four self-diagnosed error types) and §3.4 (proj-1df43a 2026-07-13, 39 deviations found by a deviation-hunting agent)
