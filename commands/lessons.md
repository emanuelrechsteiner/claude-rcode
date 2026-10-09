---
description: "Extract reusable patterns and lessons learned from completed work. Run after phase completion or after significant bug fixes."
model: claude-fable-5-1[1m]
allowed-tools:
  - Task
  - Read
  - Write
  - Edit
  - Bash(git:*)
  - Glob
  - Grep
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `~/.claude/agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `~/.claude/agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `~/.claude/agents/control-agent.md` §4.

# R.Code Lessons — Pattern Extraction & Knowledge Capture

You are executing the R.Code `/lessons` command. This extracts reusable patterns and lessons from completed work and updates the project's living documentation.

---

## Step 1: ANALYZE RECENT WORK

**Window (M4):** since the most recent `v0.*`, `scope-lock-*`, or
`rcode-migrate-*` tag (whichever is newest); fall back to the last 2 weeks
only if none of those tags exist yet.

```bash
# Resolve the window start — newest of the three tag families, else 2 weeks ago
WINDOW_TAG=$(git tag --sort=-creatordate | grep -E '^(v0\.|scope-lock-|rcode-migrate-)' | head -1)
if [ -n "${WINDOW_TAG}" ]; then
  WINDOW_REF="${WINDOW_TAG}..HEAD"
  echo "lessons: window = ${WINDOW_TAG}..HEAD" >&2
else
  WINDOW_REF=""
  echo "lessons: no v0.*/scope-lock-*/rcode-migrate-* tag found — window = last 2 weeks" >&2
fi

# Recent commits
if [ -n "${WINDOW_REF}" ]; then
  git log --oneline "${WINDOW_REF}"
else
  git log --oneline --since="2 weeks ago"
fi

# Identify bug fixes (potential anti-patterns) — anchored, conventional-commit
# type prefix only (M4: bare `--grep="fix:"` matched 4 commits where the
# anchored `--grep='^fix'` matches the real 48 — commits are `fix(area): …`,
# and the unanchored substring also false-positives on unrelated text)
if [ -n "${WINDOW_REF}" ]; then
  git log --oneline -E --grep='^fix' "${WINDOW_REF}"
else
  git log --oneline -E --grep='^fix' --since="2 weeks ago"
fi

# Identify refactors (evolved patterns) — same anchoring
if [ -n "${WINDOW_REF}" ]; then
  git log --oneline -E --grep='^refactor' "${WINDOW_REF}"
else
  git log --oneline -E --grep='^refactor' --since="2 weeks ago"
fi

# Most changed files (hotspots)
if [ -n "${WINDOW_REF}" ]; then
  git log --name-only --pretty=format: "${WINDOW_REF}" | sort | uniq -c | sort -rn | head -20
else
  git log --name-only --pretty=format: --since="2 weeks ago" | sort | uniq -c | sort -rn | head -20
fi
```

---

## Step 2: CATEGORIZE FINDINGS

Sort each finding into the appropriate documentation target:

### Category A: Code Conventions (→ CONVENTIONS.md)

Patterns that should become standard practice:
- New naming conventions that emerged
- Component structure patterns that worked well
- Error handling approaches that proved robust
- Testing patterns that caught real bugs
- Import organization that improved readability

### Category B: Architectural Patterns (→ ARCHITECTURE.md)

Patterns that affect system design:
- New ADRs needed for decisions made during implementation
- Existing ADRs that need updating based on real-world experience
- Performance patterns that should be standard
- Security patterns discovered during implementation

### Category C: Anti-Patterns (→ CONVENTIONS.md "Avoid" section)

Things that went wrong and should be prevented:
- Bug patterns that recurred (same type of bug in multiple places)
- Approaches that seemed right but caused problems
- Framework gotchas specific to the project's tech stack

### Category D: Process Improvements (→ Workflow refinement)

Improvements to the development process itself:
- Steps in `/issue` that could be more efficient
- Review criteria that caught real problems
- Review criteria that produced false positives
- Testing strategies that were particularly effective

### Category E: Glossary Terms (→ CONTEXT.md)

Per `~/.claude/rules/domain-docs-convention.md`: any domain phrase that had to
be circumlocuted (written out in full) 3 or more times in the analyzed
commits or in this session's own findings write-up is a coining trigger —
add a one-line `**Term** — meaning` entry to the project's `CONTEXT.md` if
the project has one (A6 — CONTEXT.md is optional; `/rcode-init` writes a
stub, `/brainstorm`/`/rcode-migrate` seed it. If `CONTEXT.md` does not exist,
skip this category — do not create the file here).

---

## Step 3: UPDATE CONVENTIONS.md (+ CONTEXT.md)

For Category A and C findings, update CONVENTIONS.md. For Category E
findings, add the coined term(s) to `CONTEXT.md` if the project has one (A6
— do not create it here if it's missing):

**Tracker note:** the `Discovered:` field below uses whichever unit-ID form
this project's tracker actually produces — `#N` (tracker `github`) or
`P-NNN` (tracker `plan`); resolve the tracker from `.rcode/config.json`
`.tracker` (see `~/.claude/rcode/README.md` §Tracker Modes).

### Adding New Patterns

Add to the "Patterns Discovered During Development" section:

```markdown
### Pattern: [Pattern Name]

**Discovered:** Phase [N], Unit <#N or P-NNN>
**Problem:** [What problem this pattern solves]
**Solution:** [The pattern]
**Example:**

\`\`\`typescript
// [Code example showing the pattern]
\`\`\`
```

### Adding Anti-Patterns

Add to relevant sections with "Avoid" guidance:

```markdown
### Avoid: [Anti-Pattern Name]

**Discovered:** Phase [N], Unit <#N or P-NNN> (fix)
**Problem:** [What went wrong]
**Why It's Wrong:** [Root cause explanation]
**Instead:** [Correct approach]

\`\`\`typescript
// BAD
[wrong code]

// GOOD
[correct code]
\`\`\`
```

---

## Step 4: UPDATE ARCHITECTURE.md

For Category B findings. ADRs follow the two-tier model (A5): design-time
decisions live inline in `ARCHITECTURE.md` as `### ADR-NNN — <Title>`; once a
decision is implemented/final, it is ALSO filed as an immutable
`docs/adr/NNNN-<slug>.md` (using `~/.claude/rcode/templates/ADR.template.md`)
and the inline entry links to it. Look in BOTH places before assuming an ADR
doesn't exist yet.

### New ADRs

If a significant architectural decision was made during implementation that
doesn't have an ADR:

1. Add the inline `### ADR-NNN — <Title>` entry to `ARCHITECTURE.md`
2. If the decision is final (not still under active iteration), also file it
   as `docs/adr/NNNN-<slug>.md` and link the inline entry to it
3. Reference the unit/PR where the decision was made
4. Add (or update) its row in the ADR **Index** table of `ARCHITECTURE.md`
   (`# | Title | Status | Filed ADR`) — the index must list every inline and
   filed ADR

### Pointer memory note (knowledge library, 2026-10-09)

For every ADR filed in this step and every pattern or anti-pattern added in
Step 3, write ONE pointer note into this project's auto-memory folder,
`~/.claude/projects/<encoded cwd>/memory/<kebab-slug>.md` (the encoding replaces
every `/` of the cwd with `-`), plus its one-line entry in that folder's
`MEMORY.md`. Project docs are not mirrored into the cross-project knowledge
library (`docs/OBSIDIAN.md`: Stage 2b is gated), so the memory note is what
makes the decision findable from another project. Format: frontmatter `name`,
`description` (the claim in one line), `metadata: type: project`; body = the
claim first, then `**Why:**`, `**How to apply:**`, and the backtick path of the
ADR or CONVENTIONS section it points to. Never copy the ADR body: one claim,
one path.

### ADR Updates

Existing ADRs are NEVER rewritten retroactively (A5 — immutable once filed):

1. **Filed ADR** (`docs/adr/NNNN-*.md`): write a NEW ADR with
   `Status: superseded-by ADR-NNNN`, referencing the old one; update the old
   file's `Status:` line to point at the new one.
2. **Inline-only ADR** (`### ADR-NNN` in `ARCHITECTURE.md`, not yet filed):
   may still be edited in place — update its consequences/revisit-conditions
   section, note the real-world evidence, add a revision date.

---

## Step 5: UPDATE CLAUDE.md

If significant patterns or conventions were added, update the "Critical Conventions" section of CLAUDE.md to include the most important new patterns. CLAUDE.md should have a condensed version of the most critical conventions — it doesn't need every pattern, just the ones that are most important.

---

## Step 6: SPAWN PATTERN EXTRACTOR (Optional)

For complex patterns that need deep analysis, spawn a **pattern-extractor-agent**:

```
Analyze the following git commits and extract reusable patterns:

[List of relevant commits]

For each pattern found:
1. Identify the root cause or motivation
2. Formalize the pattern with a name, problem, solution, example
3. Classify as: convention, anti-pattern, architectural pattern, or process improvement
4. Suggest where it should be documented (CONVENTIONS.md, ARCHITECTURE.md, etc.)
```

---

## Step 7: COMMIT

```bash
git add CONVENTIONS.md ARCHITECTURE.md CLAUDE.md
# Only if this run actually touched them (A5/A6 — don't stage no-op files):
#   git add docs/adr/NNNN-*.md
#   git add CONTEXT.md

git commit -m "$(cat <<'EOF'
docs(lessons): extract patterns from [Phase N / unit range]

Patterns added to CONVENTIONS.md:
- [Pattern 1 name]
- [Pattern 2 name]

Anti-patterns documented:
- [Anti-pattern 1 name]

ADR updates:
- [ADR-NNN: what changed — inline ARCHITECTURE.md and/or filed docs/adr/]

Glossary terms added to CONTEXT.md:
- [Term name, if any]

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Step 8: APPEND TO AGENT LOG

`/lessons` is one of the single writers of `.rcode/agent-log.md` (A12).

```markdown
## Session: Lessons Extraction

**Date:** [today]
**Agent:** [identifier]
**Scope:** [Phase N / unit range, e.g. #12-#18 or P-012..P-018]
**Window:** [tag..HEAD used in Step 1, or "last 2 weeks — no tag found"]

**Patterns Extracted:**
- [Pattern 1] → CONVENTIONS.md
- [Pattern 2] → CONVENTIONS.md

**Anti-Patterns Documented:**
- [Anti-pattern 1] → CONVENTIONS.md

**ADR Updates:**
- [ADR-NNN] → ARCHITECTURE.md and/or docs/adr/ (A5)

**Glossary Terms Added:**
- [Term] → CONTEXT.md (if the project has one)

**Process Observations:**
- [Any workflow improvement suggestions]
```

---

## Output

```
Lessons Extraction Complete!

Window: [tag..HEAD, or "last 2 weeks — no tag found"]
Analyzed: [N] commits

Patterns Added: [N]
  - [Pattern names]

Anti-Patterns Documented: [N]
  - [Anti-pattern names]

ADR Updates: [N]
  - [ADR references — inline and/or filed]

Glossary Terms Added: [N]
  - [Term names, if any]

Updated Files:
  - CONVENTIONS.md (patterns + anti-patterns)
  - ARCHITECTURE.md (ADR updates)
  - docs/adr/ (newly filed ADRs, if any)
  - CONTEXT.md (glossary terms, if the project has one)
  - CLAUDE.md (critical conventions refresh)

The project's living documentation is now up to date.
Future agents will benefit from these captured learnings.
```
