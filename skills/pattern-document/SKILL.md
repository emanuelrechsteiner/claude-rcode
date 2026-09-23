---
name: pattern-document
description: Learning extraction skill. Analyzes recent fixes, extracts reusable patterns or anti-patterns, and creates rule documents in ~/.claude/rules/. Use after discovering bugs or implementing solutions that could help prevent future issues. Triggers on "document pattern", "extract learning", "create rule", "prevent this bug", "pattern document", "save this pattern", "was haben wir daraus gelernt", "muster dokumentieren", "regel erstellen", "daraus eine regel machen", "dieses problem nie wieder", "speicher das als pattern", "lerne daraus", "das sollten wir uns merken", "bug pattern".
context: fork
model: sonnet
allowed-tools: Read, Write, Glob, Grep, Bash(git log *), Bash(git diff *)
---

# Pattern Document Skill - Learning Extraction

## Purpose

Extract learnings from bug fixes, successful implementations, or discovered anti-patterns and create persistent documentation that prevents future occurrences.

## When to Use This Skill

1. **After fixing a tricky bug** - Capture the root cause and solution
2. **After discovering an anti-pattern** - Document what NOT to do
3. **After implementing a complex feature** - Capture the pattern for reuse
4. **After a time-consuming debugging session** - Save the diagnostic approach
5. **After learning framework-specific behavior** - Document gotchas

## Pattern Extraction Process

### Step 1: Identify the Learning

Answer these questions:
- What was the symptom/problem?
- What was the root cause?
- What was the solution?
- Why wasn't this obvious initially?
- Could this happen again in different code?

### Step 2: Categorize the Pattern

**Pattern Types:**

| Type | Description | Example |
|------|-------------|---------|
| Anti-Pattern | What NOT to do | Using state and refs for same property |
| Solution Pattern | How to solve a problem | RAF loop for scroll synchronization |
| Diagnostic Pattern | How to debug an issue | Checking middleware matcher for 405 errors |
| Framework Gotcha | Unexpected framework behavior | Next.js middleware intercepting API routes |
| Architecture Pattern | Structural approach | Zustand store organization |

### Step 3: Create Rule Document

**File Location:** `~/.claude/rules/[descriptive-name].md`

**Naming Convention:**
- Use kebab-case
- Be descriptive but concise
- Include framework name if specific (e.g., `nextjs-api-routes.md`)

### Rule Document Template

```markdown
# [Pattern Name]

> [One-line summary of the learning]

## The Problem

[Describe the symptom or issue that this pattern addresses]

**Common Symptoms:**
- [Symptom 1]
- [Symptom 2]

## Root Cause

[Explain why this happens - the underlying mechanism]

## The Solution

[Describe the correct approach]

### Example - Before (BAD)

```[language]
// BAD - explain why this is problematic
[code example]
```

### Example - After (GOOD)

```[language]
// GOOD - explain why this works
[code example]
```

## Detection

How to identify if this issue is present:

```bash
# Commands or patterns to detect the issue
[detection commands]
```

## Prevention

- [ ] [Checklist item to prevent this issue]
- [ ] [Another preventive measure]

## Related Resources

- [Link to documentation]
- [Link to related patterns]

## Metadata

- **Discovered:** [Date]
- **Project:** [Project name if relevant]
- **Root Cause Category:** [TypeScript | React | Next.js | State Management | CSS | etc.]
```

## Example Patterns Created

### Example 1: React State/Ref Conflict

```markdown
# React State and Ref Conflicts

> Never use React state AND ref DOM updates for the same CSS property

## The Problem

UI element position doesn't update in real-time during animations.

## Root Cause

React's reconciliation overwrites ref-based DOM updates whenever state changes trigger a re-render.

## The Solution

Let refs have exclusive control over frequently-updated properties.
```

### Example 2: Next.js Middleware API Routes

```markdown
# Next.js Middleware and API Routes

> Always exclude /api/* from i18n/auth middleware matchers

## The Problem

API routes return 405 Method Not Allowed or redirect unexpectedly.

## Root Cause

Middleware intercepts ALL routes unless explicitly excluded. Redirects break POST requests.

## The Solution

Add explicit exclusion in middleware config:
matcher: ['/((?!api|_next|static|.*\\..*).*']
```

## Quick Pattern Documentation

For simpler learnings, use this shorter format:

```markdown
# [Pattern Name]

**Problem:** [Brief description]
**Cause:** [One-line root cause]
**Solution:** [One-line solution]

**Example:**
```[language]
// BAD
[bad code]

// GOOD
[good code]
```
```

## Integration with Other Skills

1. After `/fix-review` reveals a pattern, use `/pattern-document` to capture it
2. Patterns inform what hooks should check (future `/validate-build` enhancements)
3. Patterns can become test cases (inform `testing-agent`)

## Checklist Before Creating a Rule

- [ ] Is this pattern general enough to apply elsewhere?
- [ ] Is the root cause clearly understood?
- [ ] Is the solution proven to work?
- [ ] Would this save significant debugging time if known earlier?
- [ ] Is there existing documentation for this? (Don't duplicate)

## Storing the Pattern

Save the rule document to:

```bash
~/.claude/rules/[pattern-name].md
```

The pattern will be automatically loaded in future sessions when relevant context is detected.
