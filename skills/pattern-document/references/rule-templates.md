# Rule Document Templates

Templates for creating pattern/anti-pattern documentation.

## Bug Prevention Rule Template

```markdown
# [Pattern Name]

> [One-line description of what this prevents]

## The Problem

[Describe the bug pattern that was discovered]

### Symptom
[What users/developers see when this bug occurs]

### Root Cause
[Technical explanation of why this happens]

### Example of Buggy Code

\`\`\`typescript
// BAD - This causes [problem]
[code that demonstrates the anti-pattern]
\`\`\`

## The Solution

### Correct Pattern

\`\`\`typescript
// GOOD - This prevents the issue
[code that demonstrates the correct pattern]
\`\`\`

### Why This Works

[Explanation of why the correct pattern avoids the issue]

## Detection

### How to Find This Pattern

\`\`\`bash
# Search for potential violations
grep -rn "[pattern to find violations]" src/
\`\`\`

### Automated Prevention

[ESLint rule, TypeScript setting, or hook that can prevent this]

## Related Patterns

- [Link to related patterns]
- [Other relevant documentation]
```

## Architecture Decision Record (ADR) Template

```markdown
# ADR-[number]: [Decision Title]

**Date**: [YYYY-MM-DD]
**Status**: [Proposed | Accepted | Deprecated | Superseded]

## Context

[What is the issue that we're seeing that motivates this decision?]

## Decision

[What is the change that we're proposing and/or doing?]

## Consequences

### Positive
- [Good outcome 1]
- [Good outcome 2]

### Negative
- [Tradeoff 1]
- [Tradeoff 2]

### Neutral
- [Neither good nor bad, but worth noting]

## Alternatives Considered

### Option A: [Name]
[Description and why rejected]

### Option B: [Name]
[Description and why rejected]

## Implementation Notes

[How to implement this decision]
```

## Best Practice Documentation Template

```markdown
# [Practice Name]

## Purpose

[Why this practice exists and what problem it solves]

## When to Use

- [Situation 1]
- [Situation 2]

## When NOT to Use

- [Exception 1]
- [Exception 2]

## Implementation

### Basic Pattern

\`\`\`typescript
[Code showing the basic implementation]
\`\`\`

### With Options

\`\`\`typescript
[Code showing variations]
\`\`\`

## Common Mistakes

### Mistake 1: [Name]

\`\`\`typescript
// DON'T do this
[bad code]

// DO this instead
[good code]
\`\`\`

### Mistake 2: [Name]

[Description and correction]

## Testing

[How to verify this pattern is correctly implemented]

## References

- [Link 1]
- [Link 2]
```

## Framework-Specific Rule Template

```markdown
# [Framework] [Pattern Name]

> Critical pattern for [Framework] [version] development

## The Issue

[What goes wrong without this pattern]

## Correct Approach

\`\`\`typescript
// [filename]
[code demonstrating correct pattern]
\`\`\`

## Common Violations

### Violation 1

\`\`\`typescript
// WRONG
[code]
\`\`\`

**Why it fails**: [explanation]

### Violation 2

\`\`\`typescript
// WRONG
[code]
\`\`\`

**Why it fails**: [explanation]

## Checklist

Before deploying, verify:

- [ ] [Check 1]
- [ ] [Check 2]
- [ ] [Check 3]

## Debugging

If you see [error message]:

1. [Step 1]
2. [Step 2]
3. [Step 3]

## References

- [Official docs link]
- [GitHub issue link]
```

## Quick Reference Card Template

```markdown
# [Topic] Quick Reference

## Commands

| Command | Description |
|---------|-------------|
| `cmd1` | Does X |
| `cmd2` | Does Y |

## Patterns

| Pattern | Use When |
|---------|----------|
| Pattern A | [situation] |
| Pattern B | [situation] |

## Anti-Patterns

| Don't Do | Do Instead |
|----------|------------|
| Bad thing | Good thing |

## Checklist

- [ ] Item 1
- [ ] Item 2
- [ ] Item 3
```
