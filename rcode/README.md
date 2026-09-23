<!--
Status: ACTIVE
Last Updated: 2026-09-23
Purpose: What the R.Code workflow is, its three layers, the one-entrance loop, tracker modes, the artifact set, versioning, and how this directory relates to the public claude-rcode export.
-->

# R.Code Workflow

R.Code is the atomic development workflow this framework applies to
individual projects. This file explains it from the framework side — what
lives where, and why. The rules a project actually loads at session start
are `~/.claude/rcode/rules/rcode-workflow.md` (glossary + entrance map +
critical rules), `rcode-scope.md` (scope discipline), and
`rcode-commits.md` (git conventions).

## Three Layers

1. **Global — commands, skills, stage playbooks.** Live in `~/.claude/`
   (`~/.claude/commands/`, `~/.claude/skills/rcode-*`, `~/.claude/rcode/stages/`).
   Never copied into a project, never versioned per project — every
   R.Code project on this machine runs the same command and playbook code.
2. **Rails — copied into each project.** `~/.claude/rcode/rules/*.md` (+
   installed stack rules from `~/.claude/rcode/templates/project-rules/`) are copied into the
   project's `.claude/rules/` at setup and versioned by `~/.claude/rcode/VERSION`
   (see "Versioning" below). `/rcode-upgrade` diffs and updates them,
   per-file, never clobbering a customization without a y/n.
3. **Project artifacts.** Files a project's own agents read and write —
   `PROJECT-STATUS.md`, `BRAINSTORM.md`, `.rcode/*`, optionally
   `CONTEXT.md` (one paragraph below) — generated once by setup and then
   owned by the project, never copied FROM the framework again.

## The One Entrance

`/team-lead "<directive>"` is the documented main entrance for all R.Code
project work; `/plan-team` … `/launch-team` are thin aliases that force a
Stage. The loop: orient (`resume-state.sh` + `status-metrics.sh` +
`.rcode/config.json` + `PROJECT-STATUS.md`) → detect Stage (Plan / Design /
Develop / Test / Launch) → load that Stage's playbook
(`~/.claude/rcode/stages/<stage>.md`) → bind units to `#N`/`P-NNN` → dispatch
→ proportional exit (an agent-log entry always; `/status-sync`,
`/phase-gate`, `/lessons`, or an escalation only when their own trigger
condition holds — never on every exit). Full loop diagram and the
supporting-door command list ("orient", "setup", "periodic", "protocols"):
`~/.claude/rcode/rules/rcode-workflow.md` → "The One Entrance".

## Tracker Modes

This is the single home for the tracker grammar — commands and scripts
point here instead of restating it. A project runs on exactly one tracker,
recorded in `.rcode/config.json` (`"tracker": "github" | "plan"`), asked
once via `AskUserQuestion` (never guessed, never silently inferred) by
whichever command first needs it.

### `github`

Units are GitHub issues (`#N`); labels, milestones, `gh` calls.

### `plan`

Units live in `BRAINSTORM.md` under `### Phase N` headings; no GitHub
required. Three forms are all **read** (never written by the parser —
`/decompose` plan mode is the only writer, and it never renumbers an
existing ID):

- **Checkbox line:** `- [ ] P-NNN — <Title> ...` / `- [x] ...`. Completion
  comes straight from the checkbox: `[x]` → closed, `[ ]` → open.
- **`P-NNN` table row:** a markdown table whose row's first cell matches
  `P-NNN` (e.g. `| P-001 | [Phase 1] <Title> | <Type> | ... |`).
- **Local `#N` table row** (older projects — e.g. Projekt N's 81-unit
  BRAINSTORM.md, which predates the `P-NNN` convention): a markdown table
  whose FIRST header cell is one of `#`, `ID`, `Nr`, `Nr.`, and whose row's
  first cell is an integer or `#`+integer. The unit ID is written `#N`.
  This is a **local plan number**, not a GitHub issue — the project's
  `tracker` field disambiguates it from `github`'s `#N`, never the ID
  shape alone (a `tracker: "plan"` project reading `#N` never means the
  same thing as a `tracker: "github"` project reading `#N`).

**Phase membership** (any plan form): the `[Phase N]` prefix in the title
if present, else the nearest preceding `##`–`####` heading naming
`Phase N` (with or without a `— <Name>` suffix); otherwise `unknown`.

**Completion, table forms:** a column whose header is `Status`/`State`
(case-insensitive) decides it — a value matching
`done|closed|complete|completed|✅|x` → `closed`, any other value →
`open`. A table **without** such a column → every row in it is state
`unknown` — never a fabricated open/closed
(`~/.claude/rules/fail-loud.md`).

**Unknown state is not silently either.** `unknown` units are **excluded
from open/closed counts** wherever this repo reports them (status
dashboards, phase-gate verdicts) — never counted as open, never counted as
closed, never dropped without a trace — and their presence always raises a
finding naming the file/table, so a reader sees "N units of unknown state,
excluded from the count" instead of a total that silently under- or
over-reports progress.

No `P-NNN` or local-`#N` IDs found anywhere in a `plan`-tracker project →
`units: []` plus a finding naming that, never a silently-empty result
(a project can genuinely have 80+ real units on this tracker — an empty
result is a parser gap, not a fact about the project).

Every command that touches units reads all these forms and is
tracker-aware. `~/.claude/scripts/rcode-units.sh` is the one shared parser
both the gather scripts (`status-metrics.sh`, `phase-gate-check.sh`,
`resume-state.sh`) and the commands call — never a second, independently
written counting/matching routine that could drift from it. See
`~/.claude/rcode/rules/rcode-scope.md` for how scope enforcement works per
tracker.

### Commit references (both trackers)

One tracker-agnostic regex, canonical source
`~/.claude/rcode/rules/rcode-commits.md`:

```
(closes|refs) (#[0-9]+|P-[0-9]{3,}(\.\.P-[0-9]{3,})?)((, ?)(#[0-9]+|P-[0-9]{3,}(\.\.P-[0-9]{3,})?))*
```

Real examples: `refs #42`, `closes P-051`, `refs P-051..P-105`,
`refs P-085, P-100`. A unit's own implementation commit references
**exactly one** unit; ranges (`P-051..P-105`) and comma-lists
(`#48, #49, #50`) are reserved for **consolidation commits** (e.g. a
lead's squash-merge closing several units from one wave at once), never
for the unit's own work. Branch-naming forms for both trackers:
`~/.claude/rcode/rules/rcode-commits.md` → "Branch Naming Convention".

## Artifact Set

`.rcode/config.json` (project metadata + tracker) · `scope-manifest.json`
(locked feature list) · `agent-log.md` (append-only, single-writer) ·
`blocked-issues.md` · `phase-summaries/` · `re-entry-brief.md` +
`re-entry-archive/` (backward Stage jumps) · `escalation-queue.md`
(automatic-approval mode). Full tree, field formats, and the two-tier ADR
model: `~/.claude/rcode/rules/rcode-workflow.md` and
`docs/adr/0002-rcode-plan-folgt-praxis.md`.

`CONTEXT.md` (a project's own glossary) is optional and deliberately
lightweight — a project writes it only once a term has been circumlocuted
three times (see `~/.claude/rules/domain-docs-convention.md`); adoption is not
forced, and `/rcode-onboard` reads it only if present.

## Versioning

`~/.claude/rcode/VERSION` (first line, `YYYY-MM-DD`) is the rail version — it
covers `~/.claude/rcode/rules/*.md` and the artifact formats the global
commands parse (config schema, BRAINSTORM unit-line format, template field names),
NOT the global commands/skills/playbooks themselves (those aren't
versioned per project — see "Three Layers" above). Stamped into a
project's `.rcode/config.json` as `framework_version` by `/rcode-init`,
`/rcode-migrate`, `/brainstorm`; compared and bumped by `/rcode-upgrade`,
which diffs rail files three-way and asks one y/n per changed file.

## Relationship to `claude-rcode` (the public export)

This repo (`claude-code-config`, private) is the source of truth. Two
things are true at once here — the **designed pipeline** and the
**current operating mode** — and they currently diverge:

- **Designed pipeline.** The public repo `claude-rcode` is meant to be a
  generated mirror, produced by `~/.claude/scripts/publish.sh` (archive the
  tracked tree → apply `publish-manifest.txt` exclusions → run
  `scrub-check.sh` against the staging tree → rsync into a `claude-rcode`
  checkout for review → a human runs the printed `git push`) — never
  hand-edited. See `docs/PUBLISHING.md` for the full pipeline and the
  PR-governance model for the public repo.
- **Current operating mode.** `publish.sh` has been hard-disabled since
  2026-08-12, by a deliberate maintainer decision (`PUBLISH_DISABLED=1`). Re-activation
  requires a deliberate code edit to the script itself; there is no env-var
  bypass. While it stays disabled, public-surface changes (README numbers,
  quickstart, contributing, issue templates) go through the documented
  **hand-mirroring path** instead: made first in the Bauhof, then mirrored
  by hand into the public repo, and checked for drift with
  `ops/bin/verify-public-mirror.sh`. Full rationale and the three
  considered alternatives: `ops/decisions/2026-08-13-publisher-stilllegung.md`.

Do not edit a `claude-rcode` checkout as if it were independent either
way — under the designed pipeline it would be overwritten by the next
publish; under the current hand-mirroring mode it must match the Bauhof
exactly, verified, not assumed.
