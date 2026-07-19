---
description: "Extract reusable patterns and lessons learned from completed work. Run after phase completion or after significant bug fixes."
model: claude-fable-5[1m]
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
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `agents/control-agent.md` §4.

# R.Code Lessons — Pattern Extraction & Knowledge Capture

You are executing the R.Code `/lessons` command. This extracts reusable patterns and lessons from completed work and updates the project's living documentation.

---

## Step 1: ANALYZE RECENT WORK

Review the recent git history to identify patterns and learnings:

```bash
# Recent commits (since last phase tag or last 2 weeks)
git log --oneline --since="2 weeks ago"

# Identify bug fixes (potential anti-patterns)
git log --oneline --grep="fix:" --since="2 weeks ago"

# Identify refactors (evolved patterns)
git log --oneline --grep="refactor:" --since="2 weeks ago"

# Most changed files (hotspots)
git log --name-only --pretty=format: --since="2 weeks ago" | sort | uniq -c | sort -rn | head -20
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

---

## Step 3: UPDATE CONVENTIONS.md

For Category A and C findings, update CONVENTIONS.md:

### Adding New Patterns

Add to the "Patterns Discovered During Development" section:

```markdown
### Pattern: [Pattern Name]

**Discovered:** Phase [N], Issue #[N]
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

**Discovered:** Phase [N], Issue #[N] (fix)
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

For Category B findings:

### New ADRs

If a significant architectural decision was made during implementation that doesn't have an ADR:

1. Create the ADR using the ADR template
2. Add it to the ADR index in ARCHITECTURE.md
3. Reference the issue/PR where the decision was made

### ADR Updates

If an existing ADR's consequences or revisit conditions changed based on real experience:

1. Update the ADR's consequences section
2. Note the real-world evidence that informed the update
3. Add a revision note with date

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
git commit -m "$(cat <<'EOF'
docs(lessons): extract patterns from [Phase N / Issue range]

Patterns added to CONVENTIONS.md:
- [Pattern 1 name]
- [Pattern 2 name]

Anti-patterns documented:
- [Anti-pattern 1 name]

ADR updates:
- [ADR-NNN: what changed]

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Step 8: APPEND TO AGENT LOG

```markdown
## Session: Lessons Extraction

**Date:** [today]
**Agent:** [identifier]
**Scope:** [Phase N / Issue #N-#N]

**Patterns Extracted:**
- [Pattern 1] → CONVENTIONS.md
- [Pattern 2] → CONVENTIONS.md

**Anti-Patterns Documented:**
- [Anti-pattern 1] → CONVENTIONS.md

**ADR Updates:**
- [ADR-NNN] → ARCHITECTURE.md

**Process Observations:**
- [Any workflow improvement suggestions]
```

---

## Output

```
Lessons Extraction Complete!

Analyzed: [N] commits from [date range]

Patterns Added: [N]
  - [Pattern names]

Anti-Patterns Documented: [N]
  - [Anti-pattern names]

ADR Updates: [N]
  - [ADR references]

Updated Files:
  - CONVENTIONS.md (patterns + anti-patterns)
  - ARCHITECTURE.md (ADR updates)
  - CLAUDE.md (critical conventions refresh)

The project's living documentation is now up to date.
Future agents will benefit from these captured learnings.
```
