# 0007 — Justification edges are generated into the knowledge mirror, never written into sources

- Status: accepted
- Date: 2026-10-08

## Context

The owner looked at the Obsidian graph of the workshop and saw 280 nodes with
about 85 edges. The goal, translated from the owner's German: a more readable,
structured knowledge base that agents get through faster, in which information
is bound into a knowledge system and recognised. The owner's reading of the
graph, accepted: a node without an edge to its ground is information in form
even when it is knowledge in substance, so the justification relation must
become an edge.

Measured on 2026-10-08, the grounds exist but are not edges:

- The framework's cross-references are backtick paths (115 files) or name
  coincidence: 18 of 21 rules have an evidence twin under
  `docs/archive/rules-evidence/` with the same basename.
- The ledger is a list without links.
- Only the memory notes are graph-shaped: 96 of 150 link, 107 of 139 links
  resolve, 95 carry Why/How, and 134 carry an origin session id.

Writing wikilinks into the sources is the obvious fix and the wrong one: the
sources use backtick references for the agent and for the instruction budget.
The knowledge mirror (ADR 0006) is a copy, where structure may be added freely.

## Decision

Justification edges are generated into the knowledge mirror's copies and are
never written into the framework's source files. `scripts/knowledge-mirror.sh`
gives each copy typed frontmatter (`kind`, `origin` — amended 2026-10-09 from
`type`/`source`, because 23 memory notes own a `type` key and a generated key
must never collide with an authored one), rewrites backtick repo
paths to mirrored targets into path-qualified wikilinks, adds an `## Evidence`
section to a rule copy whose evidence twin exists, and writes one note per
ledger id. The enrichment happens before hashing, so drift detection is
unaffected by design. The contract is in `docs/OBSIDIAN.md` § Stage 2, the colour reading in
§ Graph legend. ADR 0006 is unchanged: `~/.claude` is still never opened as an
Obsidian vault.

## Consequences

- The graph is only as current as the last mirror run. `--check-links` prints
  a `LINKS total= resolved= ambiguous= dangling=` line and lists dangling
  tokens; that report is the fail-loud signal for decay.
- `kind` and `origin` are generated, never authored. Sources stay
  backtick-based, so nothing the agent reads changes.
- Obsidian's edges are untyped. Colour groups by path stand in for edge types,
  and the measurement behind a ledger note (`measured: true` or `false`) is a
  frontmatter field, not an edge Obsidian can draw.
- The mirror script gains rewriting, ledger-note and link-check logic to
  maintain.
- This ADR records the decision only. The contract is specified and the code is
  under construction on 2026-10-08; nothing is verified, and the status lives
  in `docs/OBSIDIAN.md`.
- Ledger: IMP-250 (proposed).
