<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/testing-quality.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/testing-quality.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Verify at the Sink, Not the Suite (Data-Exfiltration Fixes) (IMP-158)

**Evidence:** 2026-08-03 — the automatic security check found the first fix cosmetic: "the 'exclusion' only removes files from the file count … `graphify extract` is invoked on the unfiltered project root". Four minutes later the triggering work-thread reported "fixed" with 42 green checks. The green suite measured the file counter, not the actual call the external tool received — exactly the confusion this rule forbids.

## Verify Via the Same Code Path, Not a Reimplementation (IMP-158)

**Evidence (same incident as above, the countermeasure that held):** "I deliberately used the same counting code for this as the target resolution itself, no reimplemented logic — a second, separate count that computes differently from the send was exactly the design flaw behind the incident." (said in German)

## Automatic Check Results Belong to Their Trigger (IMP-158)

**Evidence (same incident):** the check that found the fix cosmetic never reached the work-thread that reported "fixed" four minutes later. See `agency-bands.md` "Bulk-Pipeline Manifest Gate (IMP-152)" § "Verify at the sink, not the suite" for the exfiltration-specific half of this same incident.
