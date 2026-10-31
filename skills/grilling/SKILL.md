---
name: grilling
description: "Interview the user relentlessly about a plan, decision, or idea until every branch of the decision tree is resolved — one question at a time, each led with a concrete recommendation. Use before large or ambiguous undertakings, when requirements feel underspecified, or on 'grill me', 'stress-test my plan', 'löcher mich', 'hinterfrag meinen plan', 'denk das mit mir durch', 'frag mich aus'."
context: main
---

# Grilling

Interview the user relentlessly about every aspect of the plan, decision, or idea until you reach a **shared understanding**. Walk down each branch of the decision tree, resolving dependencies between decisions one by one. The most common failure mode in software work is misalignment — this session closes the gap BEFORE any work begins.

## Rules

1. **One question at a time.** Ask, wait for the answer, then continue. Multiple questions at once are bewildering and produce shallow answers. (This deliberately overrides the batch-questions default — depth beats throughput here.)
2. **Lead every question with a recommendation** plus a one-line situational WHY, per `rules/recommend-on-ask.md`. The user reacts to a concrete proposal faster than to an open question.
3. **Facts vs. decisions.** If a *fact* can be found in the environment — the code (read the files, search for the symbol), the repo docs (`CONTEXT.md`, ADRs, README, planning docs), git history, or tool output — look it up before asking, and name the source you read. Only what the environment cannot settle goes to the user. *Decisions* belong to the user — put each one to them and wait for the answer.
4. **Ungrillable questions go to `prototype`.** A question that talking cannot settle — it has to be seen or run first, such as how a screen should look or how a state machine behaves at its edges — is not asked again in words. Stop grilling on it, hand it to the `prototype` skill, and resume with the user's one-line answer once they have seen the result.
5. **Do not act** on the plan until the user confirms the shared understanding is reached.
6. **Close with a decision record.** When the tree is resolved, output a compact summary of every decision taken (and rejected alternatives where meaningful). Feed it into the planning doc (`rules/planning-doc-convention.md`) and, where terms or architectural choices were coined, into `CONTEXT.md` / an ADR (`rules/domain-docs-convention.md`).

## When NOT to use

- The task is small and unambiguous — grilling overhead exceeds its value.
- The user already provided a complete spec — go straight to work.
- Mid-implementation detail questions — ask those inline, one-off.

---
*Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) `grilling` (MIT License, © 2026 Matt Pocock); integrated with this framework's recommend-on-ask, planning-doc, and domain-docs conventions (IMP-124).*
