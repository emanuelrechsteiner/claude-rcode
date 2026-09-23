# Domain-Docs Convention Rule (CONTEXT.md + ADRs)

> Two lightweight per-project memory artifacts: a shared-language glossary (`CONTEXT.md`) that compresses domain jargon into short, consistently used terms, and atomic Architecture Decision Records (`docs/adr/`). Adapted from mattpocock/skills (MIT, © 2026 Matt Pocock) 2026-08-03, IMP-124. Always loaded.

## Why

Agents dropped into a project without a shared language use 20 words where 1 would do — in prose, in thinking tokens, and in identifier names. And decisions recorded only inside bulk reports (`plans/*-triage-*.md`) are unfindable six weeks later when someone asks "why is X built this way?". Both artifacts fix a retrieval problem: the glossary makes *terms* stable, the ADRs make *reasons* findable.

## CONTEXT.md — the shared language

- **Location:** project root, `CONTEXT.md`. One file per project.
- **Content:** a glossary — each entry is `**Term** — one-sentence meaning`, optionally with a pointer to the module that implements it. Nothing else; it is not a README and not a planning doc.
- **When to coin a term:** the third time the same multi-word circumlocution appears in conversation, commits, or docs, coin a term for it and add the entry. ("The problem when a lesson inside a section is given a spot in the file system" → "the **materialization cascade**".)
- **Binding effect:** once a term exists, use it — in conversation, in identifiers, in file names, in commit messages. New code that paraphrases around an existing glossary term is a naming violation, same class as inconsistent casing.
- **Maintenance:** edits, not rewrites (same discipline as [[planning-doc-convention]]). Remove entries whose concept left the codebase.

## ADRs — atomic decision records

- **Location:** `docs/adr/NNNN-kebab-slug.md`, zero-padded sequential numbering (`0001-…`).
- **Scope:** exactly ONE decision per file. Bulk analyses and multi-finding reports stay in `plans/` — an ADR is the distilled, citable outcome, not the investigation.
- **Format** (four sections, all required):
  ```markdown
  # NNNN — <decision title>
  - Status: accepted | superseded-by NNNN
  - Date: YYYY-MM-DD

  ## Context      <!-- the forces: what made a decision necessary -->
  ## Decision     <!-- what was decided, one paragraph -->
  ## Consequences <!-- what becomes easier, what becomes harder, known trade-offs -->
  ```
- **Immutability:** an accepted ADR is never edited in substance. Changed your mind? Write a new ADR and mark the old one `superseded-by`. The history of reversals is itself the value.
- **When to write one:** any decision someone might later ask "why?" about — architecture choices, rejected alternatives after a `grilling` session or `prototype` verdict, deliberate rule exceptions.
- **R.Code exception:** project-level ADRs written from R.Code's own template may use the `ADR-` prefix (`ADR-NNNN-slug.md`) and a two-tier model — an inline `### ADR-NNN` entry in `ARCHITECTURE.md` at design time, filed to `docs/adr/` only once implemented/final — both remain valid alongside the bare-`NNNN` immutable form above (adopted 2026-09-23, `docs/adr/0002-rcode-plan-folgt-praxis.md`).

## Enforcement — Korrektur wird sofort Gesetz

**On the FIRST "NIE X" / "IMMER X" (or "NEVER X" / "ALWAYS X") correction from the user, write the CONTEXT.md invariant — or a mini-ADR, and where checkable a test case — IN THE SAME TURN.** This is the default action, not an offer and not a question back to the user ("should I persist this?" is itself the violation). A correction that only lives in the chat transcript has not been enforced; it has to land in an artifact the next session actually reads.

**The SECOND occurrence of the identical correction is a process failure, not a reminder.** It means the first correction was heard but not persisted — treat it as a signal (per the observation pipeline), not just as "say it again, more firmly."

**How to apply:**
1. Recognize the pattern: a categorical, non-negotiable statement of a project rule ("NIE X", "IMMER X", "NEVER X", "ALWAYS X" or their unambiguous equivalents).
2. In the same turn: add/amend the CONTEXT.md entry if it names a term or invariant, or write a mini-ADR if it records a decision — using the formats defined above.
3. If the correction is mechanically checkable, add a test case that would have caught the violation before it recurs.
4. Proceed with the original task afterward — persisting the correction is a side-effect of the same turn, not a separate task requiring confirmation.

**Evidence:** "immer klickbar ausgeben" repeated **twice in the same morning across two sessions** (2026-08-03); Projekt D "KEIN ZUSATZ-FEATURE" repeated **3× within 90 minutes** (2026-08-07) — the out-of-scope work built in between had to be discarded; "jeder Screen Zurück/Weiter" repeated (Projekt B, 2026-07-13 → 2026-07-18); Projekt C's chat-agreed "Bauordnung" from 2026-08-09 did not prevent the identical regression on 2026-08-12 — the companion case for `slop-prevention.md` Trigger 3, and the reason this section exists as a standing rule rather than a chat agreement.

## What this is NOT

- Not a replacement for [[planning-doc-convention]] — planning docs describe *intended current state* and evolve; ADRs record *point-in-time decisions* and freeze.
- Not a replacement for the `documentation` rule's ACTIVE/ARCHIVED split — ADRs are the canonical home of the "WHY / history" category that rule defines.
- Not retroactive homework: no backfill obligation for old projects. Start at the next decision.

## References

- Companions: [[planning-doc-convention]], [[documentation]], `skills/grilling` (closes into these artifacts), `skills/prototype` (verdicts land here)
- Origin: adapted from [mattpocock/skills](https://github.com/mattpocock/skills) `domain-modeling` conventions + `.agents/adr/` practice (MIT); adopted as IMP-124 (2026-08-03)
