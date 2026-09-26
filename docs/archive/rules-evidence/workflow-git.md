<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/workflow-git.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/workflow-git.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Trunk Is Not Always `main`

> Distilled from multi-project experience (merge-intake 2026-05-28): default-`main` assumptions repeatedly caused mis-targeted work.

## Commit Format

  > **Why this was rewritten (IMP-121, 2026-08-01):** the rule previously demanded an issue number
  > unconditionally and was violated **17 times out of 17** across every active repo — not out of
  > sloppiness, but because those repos genuinely use `IMP-###`. A rule that is broken 100% of the
  > time does not enforce discipline, it teaches that rules are decorative. The requirement is
  > unchanged in substance (every code commit must be traceable to a tracked unit of work); only the
  > accepted form now matches how the repos actually work.

## Report-Only Default for Research / Planning / Audit Tasks

Evidence basis: across many sessions the user repeatedly typed "Do NOT commit. Report back." and "Do NOT create branches or commits. Just write the files." What that intent actually protects against is **publishing** work prematurely (pushes, PRs, deploys) — not a throwaway local branch. The earlier blanket ban on `git checkout -b` over-corrected: it suppressed a 100%-reversible operation, forcing analysis work to pile up on the trunk working tree.
