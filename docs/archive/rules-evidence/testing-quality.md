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

## Moved from the rule on 2026-09-29 (IMP-234)

> Moved out verbatim while the rule was condensed to its normative core. The rendered-proof rule is owned by `rules/slop-prevention.md` (Trigger 3); `testing-quality.md` keeps a one-line pointer. The scope note's time-bound repo observation is kept here; its duty statement stays in the rule.

### Rendered-Proof for Visual Claims (verbatim)

A "fixed"/"done" claim about a VISIBLE state (UI, game graphics, layout, render output) is a validation gate like any other — see `slop-prevention.md` Trigger 3 for the full rule (rendered proof required — screenshot of the running program / rendered page; self-referential tests forbidden). Don't fold a visual claim into the type-check/test-suite gates above: a green test suite proves the code compiles and the assertions pass, not that the thing actually looks right when rendered.

### Automatic Check Results Belong to Their Trigger (IMP-158) — scope note (verbatim)

**Scope note:** at the time of writing, no `/security-review` command or skill is defined in this repo (`commands/`, `skills/`) — the string `security-review` appears only in `skills/audit-config/SKILL.md` as a name to avoid colliding with, i.e. it is treated there as a **Claude-Code-bundled** feature, not a repo-owned one. This rule is therefore written as a duty on the **work thread**, not as a hook this repo can register: whoever's action caused an automatic check to run must read its outcome before reporting completion, regardless of whether a bundled feature or a repo hook produced the check.
