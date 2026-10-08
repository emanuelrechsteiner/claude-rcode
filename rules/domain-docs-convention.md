# Domain-Docs Convention Rule (CONTEXT.md + ADRs)

> Two lightweight per-project memory artifacts: a shared-language glossary (`CONTEXT.md`) for domain terms, and atomic Architecture Decision Records (`docs/adr/`). Always loaded.

## CONTEXT.md — the shared language

- One `CONTEXT.md` at the project root: a glossary, each entry `**Term** — one-sentence meaning`, optionally pointing to the module that implements it. Nothing else — not a README, not a planning doc.
- **Coin a term** the third time the same multi-word circumlocution appears in conversation, commits, or docs, and add the entry.
- **Binding:** once a term exists, use it in conversation, identifiers, file names, commit messages. New code that paraphrases around an existing glossary term is a naming violation, same class as inconsistent casing.
- **Maintenance:** edits, not rewrites (as in [[planning-doc-convention]]); remove entries whose concept left the codebase.

## ADRs — atomic decision records

- `docs/adr/NNNN-kebab-slug.md`, zero-padded sequential numbering (`0001-…`); exactly ONE decision per file. Bulk analyses and multi-finding reports stay in `plans/` — an ADR is the distilled, citable outcome, not the investigation.
- **Format** (four sections, all required):
  ```markdown
  # NNNN — <decision title>
  - Status: accepted | superseded-by NNNN
  - Date: YYYY-MM-DD

  ## Context      <!-- the forces: what made a decision necessary -->
  ## Decision     <!-- what was decided, one paragraph -->
  ## Consequences <!-- what becomes easier, what becomes harder, known trade-offs -->
  ```
- **Immutable:** an accepted ADR is never edited in substance — a changed mind is a new ADR, the old one marked `superseded-by`; the history of reversals is itself the value.
- **Write one** for any decision someone might later ask "why?" about — architecture choices, rejected alternatives after a `grilling` session or `prototype` verdict, deliberate rule exceptions.
- **R.Code exception:** project-level ADRs from R.Code's own template may use the `ADR-` prefix (`ADR-NNNN-slug.md`) and a two-tier model — inline `### ADR-NNN` in `ARCHITECTURE.md` at design time, filed to `docs/adr/` only once implemented/final — both valid alongside the bare-`NNNN` immutable form (`docs/adr/0002-rcode-plan-follows-practice.md`).

## Enforcement — a correction becomes law immediately

**On the FIRST "NIE X" / "IMMER X" (or "NEVER X" / "ALWAYS X") correction from the user, persist it IN THE SAME TURN** — the default action, not an offer and not a question back ("should I persist this?" is itself the violation). A correction that only lives in the chat transcript is not enforced; it has to land in an artifact the next session actually reads. **The SECOND occurrence of the identical correction is a process failure, not a reminder**: the first was heard but not persisted — treat it as a signal (per the observation pipeline), not as "say it again, more firmly."

1. Recognize a categorical, non-negotiable rule statement ("NIE X", "IMMER X", "NEVER X", "ALWAYS X" or their unambiguous equivalents).
1a. **Classify scope before persisting.** About *this codebase* (a file, term, vendor, invariant of this project) → CONTEXT.md / ADR / project memory. About *how the user works with the agent* (who tests, which model tier, branch naming, report format) → **user-global**: one line in `~/.claude/rules/preferences.local.md` (git-ignored, auto-loaded everywhere; copied from `templates/preferences.local.md.template`; edited in place per the `*.local.md` exception in `CLAUDE.md`), never project memory. Before writing a project memory, grep `~/.claude/projects/*/memory/` for the same stance; a hit elsewhere means user-global — consolidate, leaving a one-line pointer in the project copy.
2. Project scope, same turn: add/amend the CONTEXT.md entry for a term or invariant, or write a mini-ADR for a decision (formats above).
3. If mechanically checkable, add a test case that would have caught the violation before it recurs.
4. Then proceed with the original task — persisting is a side-effect of the same turn, not a separate task requiring confirmation.

## What this is NOT

Not a replacement for [[planning-doc-convention]] (planning docs describe *intended current state* and evolve; ADRs record *point-in-time decisions* and freeze), nor for the [[documentation]] rule's ACTIVE/ARCHIVED split (ADRs are the canonical home of its "WHY / history" category). No backfill obligation for old projects — start at the next decision.

Origin: mattpocock/skills (MIT), IMP-124.
