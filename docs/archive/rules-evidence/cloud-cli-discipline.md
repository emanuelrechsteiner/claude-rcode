<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/cloud-cli-discipline.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/cloud-cli-discipline.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Why This Matters

Cloud CLIs hide scope behind terse commands. Two recurring failure modes:

1. **Scope-collision on delete.** A command like `<provider> env rm NAME <env>` can remove the entire variable across *all* environments when the variable spans multiple environments in a single row — not just the one environment named. The CLI often lacks the per-scope granularity the web UI exposes.
2. **Team/account auto-pick.** A command like `<provider> link --yes` auto-selects a team/account non-interactively. The wrong target means deploys land somewhere invisible, and you debug a "missing" deploy that actually succeeded elsewhere.

Both are silent: the command "succeeds," the damage surfaces later.
