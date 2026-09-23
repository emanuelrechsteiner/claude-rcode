# R.Code Workflow — Core Rules

> Auto-loaded for every agent session in a R.Code-managed project.
> Import via `@.claude/rules/rcode-workflow.md` in your project's CLAUDE.md.

## What R.Code Is

A strict atomic development workflow for large projects (200+ work units,
12+ months) that exceed any single agent's context window. Any agent picks
up the project after days, weeks, or months — history, current state, and
next steps live in files, never in memory.

**Principles:** documents over memory · append over overwrite (agent-log,
phase summaries) · verify over trust (gates check actual state, never
assumed) · compress over dump (phase summaries, not every unit) · explicit
over implicit (every unit states what's NOT in scope; every ADR states WHY)
· sequential gates over parallel hope · docs commits separate from code
commits.

## Glossary (binding — use exactly these words)

| Term | Meaning |
|---|---|
| **Phase** | A project milestone, numbered 1..N (0 = pre-R.Code baseline). Labels `phase-N`, tags `v0.N.0-<name>`, `.rcode/phase-summaries/`, `/phase-gate <N>`. |
| **Stage** | One of five work modes the lead runs in: Plan, Design, Develop, Test, Launch. `/team-lead`, `~/.claude/rcode/stages/*.md`, aliases `/plan-team`…`/launch-team`. |
| **Step** | One of the 10 steps (0–9) of the `/issue` unit protocol. |
| **Work unit** | The atomic unit of planned work: `#N` (tracker `github`) or, under tracker `plan`, `P-NNN` — or, in older projects, a local `#N` in a `#`/`ID`/`Nr` table (grammar: see the Tracker row below). "Issue" means a GitHub issue specifically. |
| **Tracker** | Where units live: `github` or `plan`. Field `tracker` in `.rcode/config.json`. Full grammar for both trackers (checkbox/table forms, completion, unknown-state handling, commit-ref regex): `~/.claude/rcode/README.md` § Tracker Modes. |
| **Check trio** | The project's three pre-commit checks (type/build · test · lint), defined ONCE in the project's `CLAUDE.md` → `## Mandatory Pre-Commit`. |
| **Rails** (DE: Schienen) | The files copied into each project and versioned by `~/.claude/rcode/VERSION`: `~/.claude/rcode/rules/*.md` (+ installed stack rules). Commands, skills, stage playbooks are global (live in `~/.claude`), NOT copied, NOT versioned per project. |

## The One Entrance

`/team-lead "<directive>"` is THE main entrance for all R.Code project
work. `/plan-team` … `/launch-team` are thin aliases = `/team-lead` with
the Stage forced.

Supporting doors (all still valid, none deprecated):
- **Orient:** `/rcode-onboard` (skill) · **End session:** `/handoff`
- **Setup** (once): `/rcode-init` · `/brainstorm` · `/rcode-migrate`
- **Planning:** `/decompose` (units from BRAINSTORM.md)
- **Periodic:** `/status-sync` · `/phase-gate <N>` · `/lessons` · `/rcode-upgrade`
- **Protocols:** `/issue` (the unit protocol — standalone or dispatched as
  a worker; see `~/.claude/commands/issue.md`) · `/rcode-review` (PR/diff review)
- **Other:** `/continue` (resume) · `/autonomous-overnight` · `/simple-onboard`

```
/rcode-onboard   (orient, if new to the project)
        │
        ▼
/team-lead "<directive>"  ◄────────────────────────────┐
   1. Orient    — resume-state + status-metrics +       │
                  .rcode/config.json, re-entry-brief,    │
                  escalation-queue                       │
   2. Stage     — Plan | Design | Develop | Test | Launch│
   3. Playbook  — ~/.claude/rcode/stages/<stage>.md      │
   4. Bind      — map units to #N / P-NNN                │
   5. Dispatch  — workers receive ~/.claude/commands/     │
                  issue.md (Worker mode) by reference     │
   6. Exit      — proportional (agent-log always; status- │
                  sync / phase-gate / lessons / escalation│
                  only when their condition holds) — see  │
                  ~/.claude/commands/team-lead.md          │
        │                                                 │
   [more work this session?] ──yes───────────────────────┘
        │ no
        ▼
/handoff   (session end)
```

## Living Artifact System

Generated during setup (`/rcode-init` / `/brainstorm` / `/rcode-migrate`),
maintained throughout the project.

### Tier 1 — Always Load (Every Session)
| File | Purpose |
|---|---|
| `START_HERE.md` | Onboarding entry point — what is this, tech stack, current status |
| `PROJECT-STATUS.md` | Living progress dashboard — phases, units, blockers |

### Tier 2 — Active Work (Load When Working)
| File | Purpose |
|---|---|
| `CONVENTIONS.md` | Code patterns, naming rules, folder structure |
| `.rcode/agent-log.md` | Append-only session history — single-writer, see Critical Rules |
| `CONTEXT.md` (optional) | Project glossary — coin a term at the 3rd circumlocution |
| Current work unit (`#N` / `P-NNN`) | Acceptance criteria, scope boundary |

### Tier 3 — On Demand (Load When Needed)
| File | Purpose |
|---|---|
| `ARCHITECTURE.md` | Tech stack, inline ADRs (`### ADR-NNN`), system design |
| `docs/adr/NNNN-*.md` | Filed ADRs — implemented/final decisions, immutable |
| `SPECIFICATION.md` | Features, design system, brand guidelines |
| `.rcode/phase-summaries/` | Compressed phase completion records |

### Tier 4 — Reference Only
`BRAINSTORM.md` (master plan) · `RESEARCH_FINDINGS.md` (tech evaluation) · `CLAUDE.md` (project-level agent instructions, incl. the check trio)

**ADRs are two-tier.** Design-time decisions live inline in `ARCHITECTURE.md` as `### ADR-NNN — <Title>`. Once a decision is
implemented/final, it is additionally filed as an immutable `docs/adr/NNNN-slug.md` and the inline entry links to it. Never rewrite a
filed ADR retroactively — write a new one and mark the old `superseded-by`.

## Critical Rules

- **Single-writer rule.** `.rcode/agent-log.md` and `PROJECT-STATUS.md` are
  written only by the lead/main thread — `/team-lead`'s exit, `/handoff`,
  standalone `/issue`, setup commands. Dispatched workers never write
  them. Rare conflicts between long-lived worktrees are resolved with the
  `resolving-merge-conflicts` skill, keeping both entries in timestamp
  order — not with a line-based merge strategy (interleaves multi-line
  entries).
- **One work unit per branch** — never combine units in a single branch.
- **One unit per commit reference.** A unit's own implementation commit
  references exactly one unit (`closes #N` / `refs P-NNN`). Ranges/lists
  (`refs P-051..P-105`) are reserved for consolidation commits — e.g. a
  lead's squash-merge closing several units at once — never for the
  unit's own work. See `rcode-commits.md` for the full regex.
- **Docs commits separate from code commits** — never mix them; see
  `rcode-commits.md`.
- **Never work ahead of phase gates** — complete the current Phase before
  starting the next.
- **Never change scope without human approval** — see `rcode-scope.md`.
- **Fresh context per unit.** A dispatched worker gets a clean context
  automatically; running `/issue` standalone (not dispatched), `/clear`
  before the next unrelated unit.

## Workflow State Directory

```
.rcode/
├── config.json                        # project metadata, tracker, phase
├── scope-manifest.json                # locked after /decompose (or by
│                                       # construction in /rcode-migrate)
├── agent-log.md                       # append-only, single-writer
├── blocked-issues.md                  # blocked units + reasons
├── phase-summaries/                   # written by /phase-gate (on demand)
├── re-entry-brief.md                  # only while a backward stage jump
│                                       # is active
├── re-entry-archive/                  # consumed re-entry briefs, never
│                                       # deleted
├── escalation-queue.md                # only when ESCALATE ops were queued
│                                       # (automatic-approval mode / overnight)
├── handoff-<UTC-date>-<session8>.md   # per-machine, transient, git-ignored
└── overnight-report.md                # written by /autonomous-overnight
```
