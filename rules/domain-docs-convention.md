---
paths:
  - "**/CONTEXT.md"
  - "**/docs/adr/**"
  - "**/ADR-*.md"
---

# Domain-Docs Convention Rule (CONTEXT.md + ADRs)

> Two lightweight per-project memory artifacts: a shared-language glossary (`CONTEXT.md`) for domain terms, and atomic Architecture Decision Records (`docs/adr/`). Path-scoped: loads when a matching file is read or edited.

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

## Enforcement

The persist-on-first-correction duty (a NIE/IMMER correction becomes law in the same turn; project invariants land here, user-global preferences in `~/.claude/rules/preferences.local.md`) is stated in `rules/foundation.md` (section "Scope, knowledge and decisions"); this file carries the formats it points to.

## What this is NOT

Not a replacement for [[planning-doc-convention]] (planning docs describe *intended current state* and evolve; ADRs record *point-in-time decisions* and freeze), nor for the [[documentation]] rule's ACTIVE/ARCHIVED split (ADRs are the canonical home of its "WHY / history" category). No backfill obligation for old projects — start at the next decision.

Origin: mattpocock/skills (MIT), IMP-124.
