# ~/.claude/routines/ — SUPERSEDED (2026-07-03, IMP-087)

> The YAML templates that lived here (daily-docs, weekly-improve, nightly-observation)
> were removed on 2026-07-03. They had become a stale SECOND source of truth: e.g.
> `nightly-observation.yaml` still said `status: disabled` while the live task had been
> running nightly since 2026-06-21 — exactly the two-sources-drift the Fable-5 metareview
> flagged (documentation-as-cache always goes stale).

## Where the live definitions are

**Authoritative source:** `~/.claude/scheduled-tasks/<task>/SKILL.md` — one directory per
task; the scheduler reads the SKILL.md as the prompt at fire time, so editing that file
updates the task with no re-registration.

**Runtime state** (schedule, enabled, lastRunAt): the scheduled-tasks MCP —
`mcp__scheduled-tasks__list_scheduled_tasks` / `update_scheduled_task` — or the
`/schedule` skill.

**Run evidence:** `~/.claude/global-observation/daily-docs-log.jsonl`,
`nightly-obs-log.jsonl`, `weekly-improve-log.jsonl` (mandatory since IMP-075).

| Task | Schedule (UTC-naive local) | Live since |
|------|---------------------------|------------|
| daily-docs | 07:10 daily | 2026-05 |
| nightly-observation | 02:05 daily | re-enabled 2026-06-21 (IMP-049) |
| weekly-improve | Sunday 22:06 | scheduled since 2026-06; data paths fixed 2026-07-03 (IMP-075) |

Counts: `~/.claude/scripts/framework-inventory.sh` (source: `scheduled-tasks/*/SKILL.md`).
