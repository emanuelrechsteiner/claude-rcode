# global-observation/

Runtime data directory for the framework's self-improvement (observation) pipeline.
Everything under this directory except `improvement-ledger.json` and this `README.md`
is **generated at runtime** and intentionally **not** part of the shipped repo — see
`.gitignore`.

## Why this directory ships almost empty

The observation pipeline is designed to accumulate operational history — session
signals, error patterns, self-critique metadata — over weeks and months of real use.
That history is inherently personal/operational data (file paths, project names,
timestamps tied to one user's work) and has no value as a static template. Shipping
a pre-filled example would either be fabricated (violates `fail-loud.md` — no
scheme-shaped placeholder content) or would leak a real user's operational history.
So this repo ships an **honest, empty** ledger and lets the pipeline populate
everything else on your own machine.

## The pipeline (for reference)

```
Edit/Write ─▶ PostToolUse ─▶ observation-capture.sh ─▶ signals.jsonl
                                                            │
Session End ─▶ Stop ─▶ session-end-check.sh ─▶ session-metrics.jsonl
                                                            │
                                        (threshold crossed) ▼
                                 "Run /meta-observe to extract patterns"
                                                            │
                User invokes /meta-observe ─▶ meta-observer skill (fork)
                                                            │
                                        ┌───────────────────┴─────────────────────┐
                                        ▼                                         ▼
                          ~/.claude/plans/meta-proposal-*.md          MCP Memory (if configured)
                                        │
                                        ▼ (after review)
                          /pattern-document skill ─▶ ~/.claude/rules/*.md
                          /lessons command ─▶ CLAUDE.md / CONVENTIONS.md updates
```

## Files that appear here at runtime (gitignored)

| File | Written by | Purpose |
|------|-----------|---------|
| `signals.jsonl` | `hooks/observation-capture.sh` (PostToolUse) | Per-edit signal capture — the raw feed for pattern extraction |
| `session-metrics.jsonl` | `hooks/session-end-check.sh` (Stop) | Per-session summary metrics |
| `self-critique.jsonl` | `hooks/self-critique-log.sh` (Stop) | Session-end metadata (e.g. edit counts) consumed by `meta-observer` |
| `daily-docs-log.jsonl` | `daily-docs` scheduled task | Mandatory run log (status even on failure) |
| `nightly-obs-log.jsonl` | `nightly-observation` scheduled task | Mandatory run log |
| `weekly-improve-log.jsonl` | `weekly-improve` scheduled task | Mandatory run log |
| `archives/signals-*.jsonl.gz` | Rotation logic | Rotated/compressed historical shards |
| `token-counter.json` | Token-optimization tooling | Local token-usage bookkeeping — not shipped (pure runtime state) |

## `improvement-ledger.json` — the one file that IS shipped

This is the single artifact meant to be version-controlled: a running log of
accepted framework improvements (rule changes, hook fixes, new skills), each
entered manually or via `/pattern-document` / `/lessons` after human review of a
`meta-observer` proposal. It ships with an **empty, valid schema**:

```json
{
  "version": "1.2.0",
  "entries": []
}
```

As you accept improvements from `/meta-observe` proposals, append entries here
(one per accepted change) and commit — this is meant to become your own project's
improvement history, not a copy of anyone else's.

## Related

- `hooks/observation-capture.sh`, `hooks/session-end-check.sh`, `hooks/self-critique-log.sh`
- `skills/meta-observer/SKILL.md`
- `scheduled-tasks/*/SKILL.md` (daily-docs, nightly-observation, weekly-improve)
- `docs/RETENTION-POLICY.md` for retention/rotation guidance
