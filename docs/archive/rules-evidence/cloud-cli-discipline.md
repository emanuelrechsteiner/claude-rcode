<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Belege, Vorfälle und Messungen, die am 2026-09-24 (IMP-217) wörtlich aus rules/cloud-cli-discipline.md ausgelagert wurden — die Regel selbst bleibt dort; hier steht das „Warum" in voller Länge.
-->
# Belege zu `rules/cloud-cli-discipline.md`

> Ausgelagert 2026-09-24 (IMP-217). Jeder Block steht unter der Überschrift, unter der er in der Regel stand, und ist unverändert übernommen.

## Why This Matters

Cloud CLIs hide scope behind terse commands. Two recurring failure modes:

1. **Scope-collision on delete.** A command like `<provider> env rm NAME <env>` can remove the entire variable across *all* environments when the variable spans multiple environments in a single row — not just the one environment named. The CLI often lacks the per-scope granularity the web UI exposes.
2. **Team/account auto-pick.** A command like `<provider> link --yes` auto-selects a team/account non-interactively. The wrong target means deploys land somewhere invisible, and you debug a "missing" deploy that actually succeeded elsewhere.

Both are silent: the command "succeeds," the damage surfaces later.
