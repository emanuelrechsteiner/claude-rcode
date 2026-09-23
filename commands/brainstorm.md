---
description: "Transform a rough app idea into a complete product foundation: research, specification, design, brand, architecture, and atomic development plan. Use when starting a new project from an idea."
argument-hint: "[app idea with target group and user story]"
model: claude-fable-5-1[1m]
allowed-tools:
  - Task
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash(git:*)
  - Bash(mkdir:*)
  - Bash(cp:*)
  - Bash(ls:*)
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `~/.claude/agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `~/.claude/agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `~/.claude/agents/control-agent.md` §4.

# R.Code Brainstorm — Full Product Development Pipeline

You are executing the R.Code `/brainstorm` command. This transforms a rough app idea into a **complete product foundation** ready for development.

**INPUT:** $ARGUMENTS

---

## Pre-Flight

1. Verify we're in a git repository (or initialize one).

2. **Idempotency guard — detect an existing scaffold BEFORE writing anything.**
   `/brainstorm` is project inception, but it is also the explicit hand-off target of any init/scaffold step that lays the `.rcode/` rails first — so it must NOT assume a clean slate (Design Principle 2: *Append over overwrite — history is never lost*). Inspect `.rcode/config.json`:
   - **Absent** → fresh inception. Proceed normally; you CREATE all state below.
   - **Present** → a prior step already initialized state. Treat this as an **upgrade-in-place**, not a rewrite:
     - **Preserve `created_date`** from the existing config verbatim — never overwrite it with today. (`created_date` is only set when the file is created fresh.) Likewise keep any `migrated_date`.
     - React to the existing `status`:
       - `"initialized"` → an init/scaffold hand-off (the intended on-ramp). Expected — continue and fill in the brainstorm artifacts, then set `status` to `"brainstormed"`.
       - `"brainstormed"` / `"migrated"` / `"decomposed"`, or `scope-manifest.json` `"locked": true` → already past inception. Do **NOT** silently clobber richer state. Print a one-line notice (`".rcode/ already at status <X> — merging brainstorm outputs, preserving existing state"`) and apply skip-if-richer below.
     - **Skip-if-richer:** never overwrite a populated/locked `scope-manifest.json`, a non-empty `blocked-issues.md`, or existing `phase-summaries/` with an empty template — merge or leave as-is, regenerating only what is genuinely missing.

3. Create the `.rcode/` directory structure for any of these that are missing (per the guard above, do not recreate files that already exist):
   ```
   .rcode/
   ├── config.json
   ├── scope-manifest.json
   ├── agent-log.md
   ├── blocked-issues.md
   └── phase-summaries/
   ```
4. Read templates from the R.Code workflow package for structure reference.
5. **Install R.Code rules** into the project's `.claude/rules/` directory:
   ```bash
   mkdir -p .claude/rules
   cp ~/.claude/rcode/rules/rcode-workflow.md .claude/rules/
   cp ~/.claude/rcode/rules/rcode-commits.md .claude/rules/
   cp ~/.claude/rcode/rules/rcode-scope.md .claude/rules/
   ```
6. After architecture decisions in Phase 3, copy applicable **stack-specific rules** from `~/.claude/rcode/templates/project-rules/`:
   - If using Next.js App Router → copy `nextjs-app-router.rule.md`
   - If using Supabase → copy `supabase.rule.md`
   - If using Convex → copy `convex.rule.md`
   - If using Python/FastAPI → copy `python-fastapi.rule.md`
   - If using React with animations → copy `react-performance.rule.md`

---

## Phase 1: RESEARCH (Parallel Agents)

Dispatch the **`research-agent`** via the Task tool (M6 fix, 2026-09-23: `research-agent` is live again at `~/.claude/agents/research-agent.md` since 2026-09-09, IMP-208 — the earlier "archived" note was stale). Prefer it over the `research` skill because it can `Write` the report file directly at the path you name in the brief (per `~/.claude/rules/foundation.md` Agent Selection table); fall back to the **`research`** skill only if the agent isn't available in this environment. Prompt (either way):

```
Conduct comprehensive technology research for the following app idea:

"$ARGUMENTS"

Research these domains (add more as needed based on the app idea):

1. **Core Technology Stack** — Frontend framework, backend/API, database, ORM
2. **Authentication** — Auth patterns, providers, session management
3. **Storage** — File/media storage solutions
4. **Real-Time** — If applicable: WebSocket, SSE, polling approaches
5. **Internationalization** — If applicable: i18n libraries, patterns
6. **Payment** — If applicable: payment processors, subscription management
7. **Email/Notifications** — Transactional email, push notifications
8. **Search** — If applicable: full-text search solutions
9. **Deployment** — Hosting platforms, CI/CD, CDN
10. **Security** — Authentication, authorization, data protection patterns
11. **Monitoring** — Error tracking, analytics, logging

For EACH technology domain:
- Evaluate 2-3 alternatives
- Provide pros/cons comparison
- Recommend one with clear justification
- Include implementation code examples where helpful
- Analyze cost (free tier, scaling costs)
- Note browser/platform compatibility

Target: >95% of technical questions answered.

Output as a comprehensive markdown document following the RESEARCH-FINDINGS template structure with sections for each domain, comparison tables, code examples, cost analysis, and security considerations.
```

**Output:** `RESEARCH_FINDINGS.md` in project root. If using `research-agent`, name that exact path in the brief and let it `Write` the file directly (never `Edit` — the file is new). If using the `research` skill instead, take its returned content and `Write` it yourself.

---

## Phase 2: SPECIFICATION (Sequential — Depends on Research)

After research completes, create the product specification in three sub-phases:

### 2a. Feature Specification

Create detailed specifications directly (or spawn planning-agent):

Using the app idea "$ARGUMENTS" and the research findings in RESEARCH_FINDINGS.md:

1. Expand the rough idea into 3-5 **core features** (each with ID: F001, F002, etc.)
2. For each feature: purpose, user-facing description, technical requirements, data requirements, edge cases, acceptance criteria
3. Write 3-6 **user stories** covering the full user lifecycle
4. Define **success metrics** and KPIs
5. Define **compliance requirements** (GDPR, accessibility, etc.)

### 2b. UX Design

Invoke the **`ux-design`** skill (R-4 stale-ref fix, 2026-07-15: `ux-agent` was archived 2026-05-27, replaced by the `ux-design` skill per `~/.claude/rules/foundation.md` Agent Selection table):

```
Based on the feature specifications for "$ARGUMENTS", create UX design specifications:

1. User journey mapping for each user story
2. Interaction patterns: loading states, error states, empty states
3. Responsive breakpoints and mobile-first strategy
4. Accessibility requirements (WCAG 2.1 AA target)
5. Navigation patterns and information architecture
```

### 2c. Design System & Brand

Spawn a **ui-agent** using the Task tool:

```
Create a design system and brand guidelines for "$ARGUMENTS":

1. Design principles (3-5 guiding principles)
2. Color palette (primary, secondary, semantic colors with hex values)
3. Typography scale (headings, body, code — font families, sizes, weights)
4. Spacing scale (xs through 2xl)
5. Component patterns (buttons, forms, cards, modals, navigation)
6. Brand personality and voice (tone guidelines, writing style)
7. Target audience visual profiles
```

**Output:** Combine all three sub-phases into `SPECIFICATION.md` in project root.

---

## Phase 3: ARCHITECTURE (Sequential — Depends on Research + Spec)

Spawn a **planning-agent** using the Task tool:

```
Create the system architecture for "$ARGUMENTS" based on:
- RESEARCH_FINDINGS.md (technology choices)
- SPECIFICATION.md (feature requirements)

Create:
1. System overview (ASCII architecture diagram)
2. Tech stack table with version numbers
3. ADRs (Architecture Decision Records) for EVERY major technology choice, as **inline** entries `### ADR-NNN — <Title>` within ARCHITECTURE.md (design-time tier — per `~/.claude/rules/domain-docs-convention.md`'s two-tier model: these decisions are not yet implemented, so they stay inline; only a decision that later becomes final/implemented gets additionally filed to `docs/adr/`, which is not brainstorm's job):
   - Each ADR: Context, Decision, Alternatives Considered (with rejection reasons), Consequences, Revisit When
   - Reference specific findings from RESEARCH_FINDINGS.md
   - List every ADR in the ADR **Index** table (`# | Title | Status | Filed ADR` — "Filed ADR" stays `—` until filed)
4. Data flow diagrams (request flow, auth flow, mutation flow)
5. Key architectural patterns (state management, API, auth, error handling)
6. Integration points with external services
7. Deployment architecture
8. Environment variables needed
9. Performance targets
10. Security architecture

Use the ARCHITECTURE template structure.
```

**Output:** Save as `ARCHITECTURE.md` in project root.

---

## Phase 4: PLANNING (Sequential — Depends on Architecture)

Spawn a **planning-agent** using the Task tool:

```
Create the development plan for "$ARGUMENTS" based on:
- SPECIFICATION.md (features to build)
- ARCHITECTURE.md (how to build them)

Decompose into phases and atomic work units (no tracker IDs yet — /decompose assigns those, as GitHub issue numbers or P-NNN plan IDs, once a tracker is chosen):

1. Organize features into development PHASES (foundation → core → enhancement → polish)
2. Break each phase into ATOMIC WORK UNITS (each = 2-4 hours of work max)
3. For each unit:
   - Clear title: "[Phase X] <Description>"
   - Type label: feat/fix/test/docs/infrastructure
   - Area label: auth/api/ui/db/config
   - Whether it's parallel-safe (can be worked on alongside other units)
   - Dependencies: which units block it
4. Map dependencies between units (which blocks which)
5. Identify parallel-safe units per phase
6. Estimate timeline per phase
7. Define milestone markers (git tags: v0.N.0-<phase-name>)

Use the BRAINSTORM template structure.
Each unit should have a clear, atomic scope — never combine "implement X and also Y" into one unit.
```

**Output:** Save as `BRAINSTORM.md` in project root.

---

## Phase 5: PROJECT SETUP (Sequential — Depends on All Above)

Generate the remaining project infrastructure artifacts:

### 5a. CONVENTIONS.md

Based on ARCHITECTURE.md decisions, create code conventions:
- Folder structure rules with correct/incorrect examples
- File naming conventions per category
- Component patterns (if frontend)
- Import ordering rules
- State management patterns
- Error handling patterns
- Testing patterns
- API patterns

Use the CONVENTIONS template.

### 5b. START_HERE.md

Quick onboarding entry:
- One paragraph project description
- Tech stack (condensed)
- Current status line (Phase 0 — setup complete)
- Key documents table
- Environment setup steps
- Contribution flow

Use the START-HERE template.

> If a `START_HERE.md` already exists from an init/scaffold step, refresh the brainstorm-owned sections (status line, key documents, tech stack) but preserve any project-specific notes the prior step added — do not blindly overwrite.

### 5c. CLAUDE.md

Project-level Claude Code instructions:
- Import workflow rules: `@.claude/rules/rcode-workflow.md` etc.
- Quick project overview
- Condensed architecture decisions
- Critical conventions (extracted from CONVENTIONS.md)
- Agent routing rules
- Canonical documentation sources
- Current status line

Use the CLAUDE-PROJECT template.

> **Merge, do not clobber.** If a `CLAUDE.md` already exists (e.g. from an init/scaffold step, or the user's own), MERGE the R.Code sections + rule imports into it — do not overwrite the user's existing content. Preserve their notes. (Same rule as `/rcode-migrate` Phase 4.)

### 5d. README.md

Public-facing project overview:
- Project description and screenshots/mockups (placeholder)
- Tech stack
- Getting started guide
- Project structure
- Contributing link

### 5e. CONTRIBUTING.md

How to contribute using the R.Code workflow. Use the CONTRIBUTING template.

### 5f. CONTEXT.md

Seed the project glossary per `~/.claude/rules/domain-docs-convention.md`: pull **≤10 core product terms** coined during Phase 2 (Specification) and Phase 3 (Architecture) — domain names for the features (F001…), core entities, or architectural concepts that would otherwise be re-explained in prose every time. Each entry: `**Term** — one-sentence meaning`.

- **If `CONTEXT.md` does not exist** (no `/rcode-init` ran first, or its stub was never written) → create it fresh:
  ```markdown
  # Context — [Project Name]

  Project glossary — coin a term at the 3rd circumlocution; code names follow the glossary.

  **[Term 1]** — [one-sentence meaning]
  **[Term 2]** — [one-sentence meaning]
  … (≤10)
  ```
- **If `CONTEXT.md` already exists as the `/rcode-init` 5-line stub** (no real term entries yet) → fill in the term list below the existing reminder line; keep that line.
- **If `CONTEXT.md` already has real term entries** (skip-if-richer, per the Pre-Flight idempotency guard) → do NOT overwrite. Append only genuinely new terms; leave existing entries untouched.

### 5g. .rcode/ State Files

Initialize (or, per the Pre-Flight idempotency guard, **upgrade-in-place**) workflow state.

**`.rcode/config.json`:**
- **Creating fresh** (no prior config) → write the full object below, with `created_date` set to today and `framework_version` read from the **first line** of `~/.claude/rcode/VERSION` (never hardcode a date; if the file is missing, write `null` and say so — never invent a version). `tracker` starts **unset** — brainstorm does not ask for it; `/decompose` asks before it first needs one.
- **Upgrading an existing config** (init/scaffold hand-off or re-run) → **preserve the existing `created_date`** (and any `migrated_date`) verbatim; update only the brainstorm-owned fields (`total_phases`, `total_issues`, `current_phase`, `status`). Never reset `created_date` to today. `framework_version` is NOT brainstorm-owned — preserve the existing value (bumping it is `/rcode-upgrade`'s job); ONLY if the field is absent entirely (pre-versioning scaffold), add it from `~/.claude/rcode/VERSION`. `tracker` is likewise NOT brainstorm-owned — if `/rcode-init`'s interview already set it, preserve that value verbatim; leave unset otherwise. **Any other field already present that isn't listed here** (including a legacy `workflow_version`) **must be preserved verbatim** — edit fields, never replace the object wholesale.

```json
{
  "project_name": "[name]",
  "repository": "[repo URL]",
  "created_date": "[today — ONLY when creating fresh; otherwise PRESERVE the existing value]",
  "framework_version": "[first line of ~/.claude/rcode/VERSION — on fresh create or if absent; otherwise PRESERVE]",
  "tracker": "[github | plan — PRESERVE if already set by /rcode-init; otherwise leave unset]",
  "total_phases": [N],
  "total_issues": [N],
  "current_phase": 0,
  "status": "brainstormed"
}
```

> No `workflow_version` field — it is legacy and no R.Code command writes it any more.

**`.rcode/scope-manifest.json`:**
Initialize from the SCOPE-MANIFEST template, populated with features from SPECIFICATION.md. Set `locked: false` (locked by `/decompose`). **Skip-if-richer:** if a populated or `"locked": true` manifest already exists, do NOT overwrite it — merge in any genuinely new features and leave the rest untouched.

**`.rcode/agent-log.md`** — **APPEND-ONLY (Design Principle 2: history is never lost).**
- **If the file does NOT exist** → create it with the full block below (the `# Agent Log` header + the `## Session: Brainstorm` entry).
- **If the file ALREADY exists** (e.g. an init/scaffold step seeded a `## Session: Init` entry, or a prior run logged one) → **APPEND only the `## Session: Brainstorm` block** (from the `## Session: Brainstorm` line downward). Do NOT emit a second `# Agent Log` header and NEVER rewrite or truncate the existing file — same append pattern as `/decompose` Step 11.

```markdown
# Agent Log — [Project Name]

> Append-only session history. Never delete entries.

---

## Session: Brainstorm

**Date:** [today]
**Agent:** brainstorm-pipeline
**Duration:** [estimated]

**Actions:**
- Generated RESEARCH_FINDINGS.md ([N] technical domains evaluated)
- Generated SPECIFICATION.md ([N] features, [N] user stories, design system, brand)
- Generated ARCHITECTURE.md ([N] ADRs)
- Generated BRAINSTORM.md ([N] phases, [N] issues)
- Generated project infrastructure (CONVENTIONS, START_HERE, CLAUDE.md, README, CONTRIBUTING, CONTEXT.md)
- Initialized .rcode/ workflow state

**Decisions:**
- [Key architectural decisions made — summarize top 3]

**Next Steps:**
- Review all generated documents
- Run `/decompose` to turn the plan into tracked work units and milestones
```

**`.rcode/blocked-issues.md`** — create ONLY if missing (skip-if-richer: never overwrite a populated blocked-issues list):
```markdown
# Blocked Issues

> Issues that cannot proceed. Updated by `/issue` and `/status-sync`.

No blocked issues yet.
```

---

## Phase 6: COMMIT

> **Trunk-commit exception (named on purpose):** this commit lands on the project's trunk (`main`/`master`). `workflow-git.md` forbids direct-to-trunk commits in general — but at inception there is no feature branch or PR to speak of, and the commit is fully local-reversible (`git reset`) before it is ever pushed. This is the same sanctioned **project-bootstrap exception** `/rcode-init` and `/rcode-migrate` rely on for their own baseline commits.

Stage and commit all generated artifacts:

```bash
git add BRAINSTORM.md RESEARCH_FINDINGS.md SPECIFICATION.md ARCHITECTURE.md \
       CONVENTIONS.md START_HERE.md CLAUDE.md README.md CONTRIBUTING.md \
       CONTEXT.md .rcode/
git commit -m "docs(project): initialize R.Code workflow for [project name]

Generated product foundation:
- RESEARCH_FINDINGS.md: [N] technical domains evaluated
- SPECIFICATION.md: [N] features, design system, brand guidelines
- ARCHITECTURE.md: [N] ADRs (inline, design-time), system design
- BRAINSTORM.md: [N] phases, [N] atomic issues
- CONVENTIONS.md: code patterns and naming rules
- Project infrastructure: START_HERE, CLAUDE.md, README, CONTRIBUTING, CONTEXT.md
- Workflow state: .rcode/

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Output Summary

After all phases complete, display:

```
R.Code Brainstorm Complete!

Documents Generated:
  - RESEARCH_FINDINGS.md    [N KB, N domains]
  - SPECIFICATION.md        [N KB, N features, N user stories]
  - ARCHITECTURE.md         [N KB, N ADRs]
  - BRAINSTORM.md           [N KB, N phases, N issues]
  - CONVENTIONS.md          [N KB]
  - START_HERE.md           [Quick onboarding]
  - CLAUDE.md               [Agent instructions]
  - README.md               [Public overview]
  - CONTRIBUTING.md         [Contribution guide]
  - CONTEXT.md              [≤10 seeded terms]
  - .rcode/*           [Workflow state initialized, tracker: <unset — /decompose asks | preserved from /rcode-init>]

Total: [N] documents, [N] issues across [N] phases
Estimated Timeline: [X weeks/months]

Next Step: Review the documents, then run `/decompose` to turn the plan into tracked work units (it will ask which tracker — GitHub issues or plan IDs — if one isn't set yet), then `/team-lead` to start Phase 1.
```
