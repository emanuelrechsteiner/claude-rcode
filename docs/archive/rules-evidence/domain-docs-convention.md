<!--
Status: ARCHIVED
Last Updated: 2026-11-10
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/domain-docs-convention.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/domain-docs-convention.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Enforcement — a correction becomes law immediately

**Evidence:** "always output it as clickable" (said in German) repeated **twice in the same morning across two sessions** (2026-08-03); proj-48ac51 "NO ADD-ON FEATURE" (said in German) repeated **3× within 90 minutes** (2026-08-07) — the out-of-scope work built in between had to be discarded; "every screen back/forward" (said in German) repeated (proj-1df43a, 2026-07-13 → 2026-07-18); proj-902a42's chat-agreed "construction code" (said in German) from 2026-08-09 did not prevent the identical regression on 2026-08-12 — the companion case for `slop-prevention.md` Trigger 3, and the reason this section exists as a standing rule rather than a chat agreement.

## Moved 2026-09-27 (budget offset for IMP-222)

> Moved out verbatim to offset the instruction-budget cost of the IMP-222 amendment ("How to apply" step 1a). Non-normative: rationale and a worked example.

### Why (former section of the rule, verbatim)

Agents dropped into a project without a shared language use 20 words where 1 would do — in prose, in thinking tokens, and in identifier names. And decisions recorded only inside bulk reports (`plans/*-triage-*.md`) are unfindable six weeks later when someone asks "why is X built this way?". Both artifacts fix a retrieval problem: the glossary makes *terms* stable, the ADRs make *reasons* findable.

### CONTEXT.md — "When to coin a term" worked example (verbatim)

("The problem when a lesson inside a section is given a spot in the file system" → "the **materialization cascade**".)

## Moved from the rule on 2026-09-29 (IMP-234)

> Moved out verbatim while the rule was condensed to its normative core. The normative content of each block is still stated in the rule; the dates, the project-scope summary sentence and the full References list are kept here.

### ADRs — R.Code exception (verbatim)

- **R.Code exception:** project-level ADRs written from R.Code's own template may use the `ADR-` prefix (`ADR-NNNN-slug.md`) and a two-tier model — an inline `### ADR-NNN` entry in `ARCHITECTURE.md` at design time, filed to `docs/adr/` only once implemented/final — both remain valid alongside the bare-`NNNN` immutable form above (adopted 2026-09-23, `docs/adr/0002-rcode-plan-follows-practice.md`).

### Enforcement — first paragraph (verbatim)

**On the FIRST "NIE X" / "IMMER X" (or "NEVER X" / "ALWAYS X") correction from the user, persist it IN THE SAME TURN** — project scope: CONTEXT.md invariant or mini-ADR, plus a test case where checkable; user-global scope: one overlay line (step 1a). This is the default action, not an offer and not a question back to the user ("should I persist this?" is itself the violation). A correction that only lives in the chat transcript has not been enforced; it has to land in an artifact the next session actually reads.

### Enforcement — step 1a setup line (verbatim)

   Setup: copy `templates/preferences.local.md.template` to `~/.claude/rules/preferences.local.md`. Carve-out from CLAUDE.md rule 1: git-ignored `*.local.md` overlays in `~/.claude/rules/` are machine-local by design and edited in place; everything tracked is edited in the workshop.

### References (verbatim)

- Companions: [[planning-doc-convention]], [[documentation]], `skills/grilling` (closes into these artifacts), `skills/prototype` (verdicts land here)
- Origin: adapted from [mattpocock/skills](https://github.com/mattpocock/skills) `domain-modeling` conventions + `.agents/adr/` practice (MIT); adopted as IMP-124 (2026-08-03)

## Moved 2026-11-10 (context diet)

> Passages moved verbatim out of rules/domain-docs-convention.md on 2026-11-10 (context diet) — the rule keeps the normative text; this file carries rationale, hook internals, history and examples.
> The pointer now lives in rules/domain-docs-convention.md §Enforcement; the normative text is in rules/foundation.md §Corrections become law (2026-11-10).

### Enforcement — a correction becomes law immediately

**On the FIRST "NIE X" / "IMMER X" (or "NEVER X" / "ALWAYS X") correction from the user, persist it IN THE SAME TURN** — the default action, not an offer and not a question back ("should I persist this?" is itself the violation). A correction that only lives in the chat transcript is not enforced; it has to land in an artifact the next session actually reads. **The SECOND occurrence of the identical correction is a process failure, not a reminder**: the first was heard but not persisted — treat it as a signal (per the observation pipeline), not as "say it again, more firmly."

1. Recognize a categorical, non-negotiable rule statement ("NIE X", "IMMER X", "NEVER X", "ALWAYS X" or their unambiguous equivalents).
1a. **Classify scope before persisting.** About *this codebase* (a file, term, vendor, invariant of this project) → CONTEXT.md / ADR / project memory. About *how the user works with the agent* (who tests, which model tier, branch naming, report format) → **user-global**: one line in `~/.claude/rules/preferences.local.md` (git-ignored, auto-loaded everywhere; copied from `templates/preferences.local.md.template`; edited in place per the `*.local.md` exception in `CLAUDE.md`), never project memory. Before writing a project memory, grep `~/.claude/projects/*/memory/` for the same stance; a hit elsewhere means user-global — consolidate, leaving a one-line pointer in the project copy.
2. Project scope, same turn: add/amend the CONTEXT.md entry for a term or invariant, or write a mini-ADR for a decision (formats above).
3. If mechanically checkable, add a test case that would have caught the violation before it recurs.
4. Then proceed with the original task — persisting is a side-effect of the same turn, not a separate task requiring confirmation.
