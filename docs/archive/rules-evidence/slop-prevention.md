<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Belege, Vorfälle und Messungen, die am 2026-09-24 (IMP-217) wörtlich aus rules/slop-prevention.md ausgelagert wurden — die Regel selbst bleibt dort; hier steht das „Warum" in voller Länge.
-->
# Belege zu `rules/slop-prevention.md`

> Ausgelagert 2026-09-24 (IMP-217). Jeder Block steht unter der Überschrift, unter der er in der Regel stand, und ist unverändert übernommen.

## Slop Prevention Rule (Einleitungszeile unter dem Titel, Original)

> Ban extending unverified AI code. Triangulated from Replit ByBench + Cline 4-levels + Matt Pocock + Mario Zechner (KB cluster 09 + 18, 2026-05-26). Always loaded.

## "Slop-on-Slop" Math

This is the "slop-on-slop" failure mode demonstrated in Replit ByBench.

## Trigger 3 — Visible claim without rendered proof

_Originalfassung des Absatzes „Describe what you see, then judge." (in der Regel gekürzt um das Zitat und das Datum):_

**Describe what you see, then judge.** At every checkpoint, first write down what is *actually visible* in the artifact (which elements, which colors, which positions, which values), and only then state whether it matches the claim. Naming the observation before the verdict is the working defense against confirmation bias — the failure mode is literally *"Ich sah, was ich zu sehen erwartete"* (self-diagnosis, 2026-08-09). A verdict with no description behind it is not an inspection; it is a guess wearing an inspection's clothes.

**Evidence:** Projekt C, 2026-08-09 — "Du hast sie 'gefixt' … beim Spielen sind sie EXAKT gleich … GAR NICHTS" — the same false "fixed" claim recurred **≥9 times across 5 sessions** (the atlas/asset declaration was checked, never the render). **The 09→12.08 lesson:** a testing discipline that was merely *agreed on in chat* on 2026-08-09 did not survive to 2026-08-12 — the identical failure recurred three days later. A discipline that lives only in chat history is not enforced; it has to live here, as a rule the agent re-reads every session, not as a one-time chat agreement.

_Originalfassung der Einleitung und Tabelle der vier Fehlertypen (in der Regel ohne Zählungen und Transkript-Zitate):_

**The four error types** behind the wider count — **13 "fixed without visual inspection" incidents across 7 days** (IMP-160), of which the ≥9 above are the visible-claim subset. All four were self-diagnosed in the same transcript; each has its own countermeasure, and fixing only the first leaves the other three live:

| # | Error type | Countermeasure |
|---|---|---|
| 1 | **Circular check** — *"Der Test leitet seine Erwartung aus derselben Deklaration ab, die er prüfen soll … Ich habe diese Prüfung gestern sogar 'gehärtet' — härter im Mechanismus, unverändert blind fürs Bild"* | Trigger 3 above: prove against the render, not the declaration |
| 2 | **Checking against one's own paraphrase** instead of the source | "Check against the SOURCE" above + the *Abschreiben, nicht deuten* pattern below |
| 3 | **Confirmation bias when looking** — *"Ich sah, was ich zu sehen erwartete"* | "Describe what you see, then judge" above + the adversarial counter-check below |
| 4 | **Sub-agent replaces an explicit user instruction with its own judgement**, and the orchestrator waves it through — *"Das ist mein Versäumnis"* | `agents/control-agent.md` §3 (verbatim instruction travels with the brief; deviation escalates, never decides) + §4 synthesis check |

## Pattern: Adversarial counter-check (an agent that HUNTS for deviations)

**Counter-evidence that this works:** Projekt B, 2026-07-13 — a dedicated deviation-hunting agent found **39 real deviations** that the implementing strand could not see itself. It is the only pattern in the August corpus demonstrated to surface errors the executing thread was structurally blind to.

## References

_Originalzeilen; in der Regel stehen nur noch die IMP-IDs und Dateipfade:_

- Replit ByBench benchmark — "slop-on-slop" failure mode
- Cline talk — 4 levels of agent autonomy; Level 4 worse outcomes
- Matt Pocock — "Full Walkthrough" — vertical slices + verification
- Mario Zechner — "Building pi in a World of Slop"
- Cluster source: see author's knowledge base (private)
- Trigger 3: Projekt C chat-transcript evidence (2026-08-09 → 2026-08-12, ≥9 recurrences) — IMP-143, `plans/meta-proposal-2026-08-23-chat-analyse.md`; companion paragraph in `testing-quality.md` ("Rendered-Proof for Visual Claims")
- Trigger 3 extension (source-not-paraphrase, describe-before-judging, four-error table) + the two patterns above: IMP-160/IMP-167 — `plans/meta-proposal-2026-08-24-august-vollanalyse.md` §2 (13 incidents / 7 days, four self-diagnosed error types) and §3.4 (Projekt B 2026-07-13, 39 deviations found by a deviation-hunting agent)
