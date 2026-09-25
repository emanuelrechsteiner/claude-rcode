<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Belege, Vorfälle und Messungen, die am 2026-09-24 (IMP-217) wörtlich aus rules/testing-quality.md ausgelagert wurden — die Regel selbst bleibt dort; hier steht das „Warum" in voller Länge.
-->
# Belege zu `rules/testing-quality.md`

> Ausgelagert 2026-09-24 (IMP-217). Jeder Block steht unter der Überschrift, unter der er in der Regel stand, und ist unverändert übernommen.

## Verify at the Sink, Not the Suite (Data-Exfiltration Fixes) (IMP-158)

**Evidence:** 2026-08-03 — the automatic security check found the first fix cosmetic: "the 'exclusion' only removes files from the file count … `graphify extract` is invoked on the unfiltered project root". Four minutes later the triggering work-thread reported "fixed" with 42 green checks. The green suite measured the file counter, not the actual call the external tool received — exactly the confusion this rule forbids.

## Verify Via the Same Code Path, Not a Reimplementation (IMP-158)

**Evidence (same incident as above, the countermeasure that held):** "Ich habe dafür bewusst denselben Zähl-Code verwendet wie die Zielauflösung selbst, keine Nachbau-Logik — eine zweite, eigene Zählung, die anders rechnet als der Versand, war genau der Konstruktionsfehler hinter dem Vorfall."

## Automatic Check Results Belong to Their Trigger (IMP-158)

**Evidence (same incident):** the check that found the fix cosmetic never reached the work-thread that reported "fixed" four minutes later. See `agency-bands.md` "Bulk-Pipeline Manifest Gate (IMP-152)" § "Verify at the sink, not the suite" for the exfiltration-specific half of this same incident.
