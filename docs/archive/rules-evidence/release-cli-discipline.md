<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/release-cli-discipline.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/release-cli-discipline.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## 1. Local-First Deploy

Observed: 4 failed cloud deploys cost ~12 minutes; a single local `<tool> build` + direct import of the compiled function (e.g. `import('.vercel/output/functions/.../index.js')` or the platform equivalent) would have caught all four bugs in <5 seconds.
