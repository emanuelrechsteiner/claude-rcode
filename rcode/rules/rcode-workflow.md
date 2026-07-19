# R.Code Workflow — Core Rules

> These rules are automatically loaded for every agent session in a R.Code-managed project.
> Import via `@.claude/rules/rcode-workflow.md` in your project's CLAUDE.md.

---

## The R.Code Workflow

R.Code is a strict atomic development workflow designed for large projects (200+ issues, 12+ months) that exceed the context window of any single coding agent. It ensures that **any agent** can pick up the project after days, weeks, or months — understanding history, current state, and next steps — without decreasing quality, adding unplanned features, or dropping planned ones.

### Seven Design Principles

1. **Documents over memory** — Agents forget, files persist. Every decision, pattern, and status lives in version-controlled files.
2. **Append over overwrite** — Agent log is append-only. Phase summaries accumulate. History is never lost.
3. **Verify over trust** — Phase gates check actual state. Scope checks compare code vs manifest. Never assume.
4. **Compress over dump** — Phase summaries compress entire phases into ~500 words. Agents read summaries, not every issue.
5. **Explicit over implicit** — Every issue states what's NOT in scope. Every ADR states WHY. No ambiguity.
6. **Sequential gates over parallel hope** — Phases don't advance until gates pass. Quality is enforced, not hoped for.
7. **Separation of concerns** — Docs commits separate from code commits. One issue per branch. One feature per PR.

---

## Command Reference

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `/rcode-init` | Lay the R.Code rails on a fresh/greenfield project (infrastructure only) | Project inception — before `/brainstorm`, once per project (skip if you start with `/brainstorm`, which self-scaffolds) |
| `/brainstorm` | Transform app idea into complete product foundation | Project inception — once per project |
| `/decompose` | Convert BRAINSTORM.md into GitHub issues + milestones | After brainstorm — once per project |
| `/issue <#>` | Complete development workflow for one issue | Every issue — the daily loop |
| `/review <PR#>` | Comprehensive code review with scope verification | Every PR before merge |
| `/phase-gate <N>` | Verify phase completion before advancing | End of each phase |
| `/status-sync` | Synchronize PROJECT-STATUS.md with GitHub state | Periodically or after merges |
| `/handoff` | Create context handoff for next agent | End of session or agent switch |
| `/lessons` | Extract reusable patterns from completed work | After each phase or major fix |

### Skills (Auto-Triggered)

| Skill | Triggers On | Purpose |
|-------|-------------|---------|
| `rcode-onboard` | "onboard", "get started", "what should I work on" | Cold/warm start for new agents |
| `scope-check` | "scope check", "scope creep", "verify scope" | Detect scope violations |

---

## Living Artifact System

These files are generated during `/brainstorm` and maintained throughout the project:

### Tier 1 — Always Load (Every Session)

| File | Purpose | Updated By |
|------|---------|------------|
| `START_HERE.md` | Onboarding entry point — what is this, tech stack, current status | `/brainstorm`, `/status-sync` |
| `PROJECT-STATUS.md` | Living progress dashboard — phases, issues, blockers | `/status-sync`, `/issue`, `/phase-gate` |

### Tier 2 — Active Work (Load When Working)

| File | Purpose | Updated By |
|------|---------|------------|
| `CONVENTIONS.md` | Code patterns, naming rules, folder structure | `/brainstorm`, `/lessons` |
| `.rcode/agent-log.md` | Append-only session history | `/issue`, `/handoff` |
| Current issue (GitHub) | Acceptance criteria, scope boundary | `/decompose` |

### Tier 3 — On Demand (Load When Needed)

| File | Purpose | Updated By |
|------|---------|------------|
| `ARCHITECTURE.md` | Tech stack, ADRs, system design | `/brainstorm`, `/lessons` |
| `SPECIFICATION.md` | Features, design system, brand guidelines | `/brainstorm` |
| `.rcode/phase-summaries/` | Compressed phase history | `/phase-gate` |

### Tier 4 — Reference Only

| File | Purpose | Updated By |
|------|---------|------------|
| `BRAINSTORM.md` | Master plan with all phases and issues | `/brainstorm`, `/decompose` |
| `RESEARCH_FINDINGS.md` | Technology evaluation and decisions | `/brainstorm` |
| `CLAUDE.md` | Project-level agent instructions | `/brainstorm`, `/lessons` |

---

## Agent Onboarding Protocol

### Cold Start (New Agent, No Prior Knowledge)

A new agent arriving at a R.Code project follows this exact sequence:

1. **Read `START_HERE.md`** — What is this project? Tech stack? Current phase?
2. **Read `PROJECT-STATUS.md`** — Progress table, blockers, next available issue
3. **Read `CONVENTIONS.md`** — Code patterns, naming, folder structure
4. **Read `ARCHITECTURE.md`** — Tech decisions, ADR summaries (skim)
5. **Read latest phase summary** — `.rcode/phase-summaries/phase-N-summary.md`
6. **Read agent log (last 2 entries)** — `.rcode/agent-log.md` (tail)
7. **Pick an issue** — Choose from available issues in PROJECT-STATUS.md

Total onboarding time target: **< 10 minutes**

### Warm Start (Returning Agent)

1. **Read `PROJECT-STATUS.md`** — Any changes since last session?
2. **Read agent log (last entry)** — Pick up where you left off
3. **Check `CONVENTIONS.md`** — Any new entries?

---

## Phase Loop

```
/rcode-onboard   (if new to project)
        |
        v
  /issue <#>          (implement one atomic issue)
        |
        v
  /review <PR#>       (review before merge)
        |
        v
  (merge PR)
        |
        v
  /clear              (MANDATORY between issues)
        |
        v
  [more issues?] --yes--> /issue <next#>
        |
        no
        v
  /phase-gate <N>     (verify phase completion)
        |
        v
  /lessons            (extract patterns)
        |
        v
  [more phases?] --yes--> next phase loop
        |
        no
        v
  FINAL RELEASE
```

### Critical Rules

- **`/clear` between issues is MANDATORY** — Prevents context bleed between issues
- **One issue per branch** — Never combine issues in a single branch
- **Docs commits separate from code commits** — Never mix documentation changes with code changes
- **Never work ahead of phase gates** — Complete current phase before starting next
- **Never change scope without human approval** — See `/scope-check`

---

## Workflow State Directory

```
.rcode/
├── config.json              # Project metadata (name, repo, phases, dates)
├── scope-manifest.json      # Canonical feature list (LOCKED after decompose)
├── agent-log.md             # Append-only session history
├── blocked-issues.md        # Currently blocked issues with reasons
└── phase-summaries/         # Compressed phase completion records
    ├── phase-1-summary.md
    ├── phase-2-summary.md
    └── ...
```
