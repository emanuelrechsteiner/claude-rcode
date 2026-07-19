---
name: quality-review
description: "Milestone-level multi-specialist code review. Dispatches 6 parallel specialist agents (architecture, security, performance, testing, maintainability, docs) on a targeted file set and synthesizes findings by severity. Use when a feature/milestone feels complete and you want a thorough multi-angle quality pass before commit/PR. Triggers on 'quality review', 'review my work', 'deep review', 'milestone review', 'qualitäts review', 'gründlich prüfen'."
disable-model-invocation: true
---

# Quality Review (Layer 3 — Milestone Review)

This skill dispatches **6 parallel specialist sub-agents** for a deep multi-angle review at milestone time. Adapted from claudekit's `/code-review` 6-agent pattern.

## When to use

- A feature or work-unit feels complete and you want a thorough pre-commit/pre-PR check
- After a refactor sprint, before merging
- When the work spans multiple concerns (security + perf + a11y + etc.) — single-agent review misses cross-cutting issues

**NOT for:**
- Per-edit feedback (the Stop-batch hook handles that)
- Tiny fixes (overkill)
- Read-only exploration (use `code-reviewer-agent` directly instead)

## Default target

If no arguments: review the **files changed in the last commit** (or all uncommitted changes if any).
If `$ARGUMENTS` provided: treat as a space-separated list of file paths or globs.

## Execution protocol

Dispatch all 6 specialists in a **single message with 6 parallel Agent tool calls**. Use `subagent_type: code-reviewer-agent` (read-only) for all 6 with a specialized prompt per agent. Each agent returns a structured report under 300 words.

### The 6 specialists

| Agent role | Prompt focus |
|-----------|--------------|
| **architecture** | Module boundaries, dependency direction, separation of concerns, layering, public/internal API hygiene |
| **security** | Auth, secrets handling, input validation, XSS/SQLi/SSRF, RLS/permissions, untrusted-data flows |
| **performance** | Render thrash, N+1 queries, unnecessary memoization, blocking I/O, bundle weight, async boundaries |
| **testing** | Coverage of branches/edges, mocking discipline, regression test for bugs, missing async/error paths |
| **maintainability** | Naming, complexity, dead code, file/function size, comment quality (WHY not WHAT), duplication |
| **docs** | README freshness, JSDoc/docstring presence for public APIs, decision rationale in commit body |

## Concrete invocation template

When invoked, do this in ONE message:

```
Read changed files: <list>

Then send 6 Agent calls in parallel, each with subagent_type=code-reviewer-agent.
Prompt template per agent:
  "Review these files specifically for {ROLE_FOCUS}.
   Files: <list>
   Return: top 3-5 findings prioritized 🔴 CRITICAL / 🟡 WARN / 🟢 OK.
   Each finding = 1-2 sentences + file:line reference.
   Under 300 words total."
```

## Synthesis

After all 6 reports arrive:
1. Collect findings by severity (🔴 / 🟡 / 🟢)
2. Deduplicate (e.g. if architecture + maintainability both flag the same monolith)
3. Output one consolidated table sorted CRITICAL → WARN, by role
4. End with: **"Top 3 actions"** — the 3 highest-impact fixes the user should do before commit
5. Estimated remediation effort (XS/S/M/L) per top action

## Cost model

- 6 parallel `code-reviewer-agent` calls (Sonnet) on a small file set
- Wall time: ~30s (parallel, not serial)
- Token cost: ~$0.20 per full review at current Sonnet pricing
- Use threshold: only invoke when the work-unit is meaningful (10+ lines changed across 2+ files)

## Output format example

```
## Quality Review — <timestamp>

### 🔴 CRITICAL (must fix before commit)
| File:line | Role | Finding |
|-----------|------|---------|
| src/api/auth.ts:42 | security | JWT secret read from process.env without validation — could be undefined |
| src/db/users.ts:78 | performance | N+1 query in loop — batches needed |

### 🟡 WARN (should fix soon)
| File:line | Role | Finding |
|-----------|------|---------|
| ... | ... | ... |

### Top 3 actions
1. **[S]** Validate JWT secret presence at startup (src/api/auth.ts:40-45)
2. **[M]** Replace N+1 with batched query (src/db/users.ts:75-90)
3. **[S]** Add JSDoc for the new public `getUser()` API

### 🟢 OK signals
- No new secrets leaked
- Tests cover the new code paths
- No file exceeds 400 lines
```

## Why this complements Layer 1 (gateguard) + Layer 2 (stop-batched-checks)

- **Layer 1** (gateguard) prevents iteration waste by forcing investigation BEFORE edit
- **Layer 2** (stop-batched-checks) catches mechanical issues (types, lint, line-count) at session-end
- **Layer 3** (this skill) catches **structural and judgment issues** that no linter sees — architecture drift, security gaps, missing tests, unclear naming

Together: each layer catches a different class of problem. Don't substitute one for another.
