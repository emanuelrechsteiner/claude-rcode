# 0008 — Owner-authored curation keys live in source notes; everything generated lives in the mirror only

- Status: accepted
- Date: 2026-10-09

## Context

The knowledge-library optimisation plan of 2026-10-09 needs per-note freshness
and supersession signals. ADR 0007 settled where generated structure goes (the
mirror's copies, never the sources) but said nothing about keys that a human
must set and that cannot be derived. Measured on 2026-10-09: 0 of 150 source
memory notes carry a `status:` key, so the vocabulary is free; 0 carry a date in
frontmatter, yet the date is derivable from the note. Two options for the
owner-set keys were weighed: a sidecar file under the knowledge folder, or the
source note itself. Claude Code loads the source note in its own project, so a
sidecar would fix the mirror and leave native memory stale.

## Decision

The owner-authored curation keys `status` (`active|superseded|archived`),
`superseded_by`, `valid_from` and `backfilled` live in source notes and nowhere
else; no script writes them except the owner-gated backfill applier, which
stamps `backfilled`. Everything derived stays generated into mirror copies only:
`dated`, `dated_from`, `origin_session`, the `## Mentions` section, the graph
TSV export and all link rewrites. This extends ADR 0007 and replaces nothing in
it. Superseded notes are kept, never deleted. The contract is in
`docs/OBSIDIAN.md` § Stage 2 "Contract v3".

## Consequences

- Native memory and the mirror agree on supersession, because the key is in the
  note both read.
- Source memory notes are untracked, so no git backstop exists: a dated backup
  must precede any source edit, and Claude Code may later rewrite a note and drop
  the keys (unverified); the lint flags a note that loses `status`.
- Generated keys cannot collide with authored ones by construction: authored
  names are fixed here, generated names stay out of that set.
- Nothing generated is ever written into a source, so ADR 0007's boundary holds
  and the lookup, the lint and the graph export all read one consistent copy.
- Cost: the owner must set the keys, at first for the few notes known to
  contradict each other.
