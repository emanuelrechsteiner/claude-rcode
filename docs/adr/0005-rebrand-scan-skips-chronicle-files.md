# 0005 — The rebrand scan skips five chronicle files

- Status: accepted
- Date: 2026-10-01

## Context

`scripts/scrub-check.sh` §6 reports every leftover mention of the project's
pre-rebrand name. The repo carries 47 reviewed, accepted mentions, all of them
history: 20 in `CHANGELOG.md`, 23 in `global-observation/improvement-ledger.json`
(old entries), and 4 in a design spec, a hand-over file and a decision note.
Since 2026-09-25 the `--staged` mode (commit hook) ignores such debt, but the
full-tree mode (CI, publish staging scan) reports all of it, so the `scrub-check`
workflow has been red on every push. The first real run of the new `tests`
workflow on 2026-10-01 made that visible. The line-bound
`scripts/scrub-allowlist.txt` cannot help: §6 never consults it, and its entries
would go stale whenever a line moves (every new `CHANGELOG.md` entry shifts 20).

## Decision

The five files are added to `REBRAND_CARVEOUT` in `scripts/scrub-check.sh`, next
to `MIGRATION.md` and `commands/rcode-upgrade.md` (same carve-out class, owner
decision 2026-10-01). Rewriting history, or leaving a permanently red check that
trains everyone to ignore it, were rejected.

## Consequences

- `scrub-check` is green in CI again; a red result means something new.
- Accepted cost: a new mention of the old name inside one of these five files is
  no longer reported, in full-tree mode or under `--staged`. Every other file is
  still scanned. `scripts/tests/scrub-check-regression.sh` pins both halves.
- Adding a sixth chronicle file is an owner decision and a new ADR.
