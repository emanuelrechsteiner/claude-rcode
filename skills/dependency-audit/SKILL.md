---
name: dependency-audit
description: Audit npm dependencies for security vulnerabilities, outdated packages, and unused dependencies. Provides actionable upgrade recommendations. Use to maintain healthy dependencies. Triggers on "dependency audit", "npm audit", "outdated packages", "security vulnerabilities", "dependency check", "update dependencies", "dependencies prüfen", "abhängigkeiten aktualisieren", "veraltete pakete", "sicherheitslücken prüfen", "npm pakete checken", "ungenutzte abhängigkeiten".
allowed-tools: Read, Glob, Grep, Bash(npm *, npx depcheck *, npx npm-check *)
---

# Dependency Audit Skill - Security & Health Check

## Purpose

Audit project dependencies for security vulnerabilities, outdated packages, and unused dependencies. Provide clear, prioritized recommendations.

## When to Use

- Before deploying to production
- On a regular schedule (weekly/monthly)
- When adding new dependencies
- After security advisories
- During codebase audits

## Audit Sequence

### 1. Security Vulnerabilities

```bash
# Run npm audit
npm audit

# JSON output for parsing
npm audit --json

# Fix automatically where possible
npm audit fix

# Force fix (may have breaking changes - review first!)
npm audit fix --force --dry-run
```

**Severity Levels:**
| Level | Action |
|-------|--------|
| Critical | Fix immediately |
| High | Fix within 24 hours |
| Moderate | Fix within 1 week |
| Low | Fix in next maintenance window |

### 2. Outdated Packages

```bash
# Check for outdated packages
npm outdated

# With detail
npm outdated --long
```

**Update Priority:**
| Type | Priority |
|------|----------|
| Security patches | Immediate |
| Bug fixes | High |
| Minor versions | Medium |
| Major versions | Plan & test |

### 3. Unused Dependencies

```bash
# Install depcheck if needed
npm install -g depcheck

# Run unused dependency check
npx depcheck

# JSON output
npx depcheck --json
```

**Categories:**
- `dependencies` - Runtime unused
- `devDependencies` - Dev tools unused
- `Missing` - Used but not in package.json

### 4. Duplicate Dependencies

```bash
# Check for duplicates
npm ls --all | grep "deduped\|UNMET"

# Or use dedicated tool
npx npm-dedupe
```

## Quick Audit Commands

```bash
# One-liner health check
echo "=== Security ===" && npm audit --audit-level=moderate 2>&1 | head -20 && \
echo "=== Outdated ===" && npm outdated 2>&1 | head -10 && \
echo "=== Unused ===" && npx depcheck 2>&1 | head -10
```

## Audit Report Template

```markdown
# Dependency Audit Report

**Project**: [project-name]
**Date**: [timestamp]
**Node**: [version]
**npm**: [version]

## Summary

| Category | Count | Action Required |
|----------|-------|-----------------|
| Critical vulnerabilities | 0 | - |
| High vulnerabilities | 2 | Immediate |
| Outdated (major) | 5 | Plan upgrade |
| Outdated (minor) | 12 | Standard update |
| Unused dependencies | 3 | Remove |
| Missing types | 2 | Install @types |

## Security Vulnerabilities

### Critical/High Priority

| Package | Severity | Issue | Fix |
|---------|----------|-------|-----|
| lodash | High | Prototype pollution | Update to 4.17.21 |
| axios | Moderate | SSRF | Update to 1.6.0 |

### Recommended Fix Commands

```bash
npm install lodash@4.17.21
npm install axios@1.6.0
```

## Outdated Packages

### Major Version Updates (Breaking Changes Likely)

| Package | Current | Latest | Breaking Changes |
|---------|---------|--------|------------------|
| next | 13.5.0 | 14.0.0 | [Migration guide link] |
| react | 17.0.2 | 18.2.0 | [Migration guide link] |

### Minor/Patch Updates (Safe)

| Package | Current | Latest |
|---------|---------|--------|
| typescript | 5.0.0 | 5.3.0 |
| eslint | 8.50.0 | 8.55.0 |

## Unused Dependencies

### Safe to Remove

| Package | Last Used | Size |
|---------|-----------|------|
| moment | Never | 290KB |
| lodash | Type-only | 72KB |

### Recommended Command

```bash
npm uninstall moment lodash
```

## Missing Type Definitions

| Package | @types Package |
|---------|---------------|
| some-lib | @types/some-lib |

## Recommendations

### Immediate Actions
1. Fix critical/high vulnerabilities
2. Remove unused dependencies
3. Install missing @types

### Scheduled Actions
1. Plan major version upgrades
2. Update minor versions
3. Review duplicate dependencies

### Preventive Measures
1. Enable `npm audit` in CI/CD
2. Use Renovate/Dependabot for updates
3. Lock versions in package-lock.json
```

## Upgrade Strategies

### Safe Update (Patch/Minor)

```bash
# Update all safe updates
npm update

# Or specific package
npm install package@latest
```

### Major Version Update

1. Read changelog and migration guide
2. Create upgrade branch
3. Update package
4. Run tests
5. Fix breaking changes
6. Review and merge

```bash
# Create upgrade branch
git checkout -b upgrade/next-14

# Update with exact version
npm install next@14.0.0

# Run tests
npm test

# Build check
npm run build
```

### Bulk Updates

```bash
# Using npm-check-updates
npx npm-check-updates

# Interactive mode
npx npm-check-updates -i

# Update package.json (doesn't install)
npx npm-check-updates -u
```

## Common Issues & Fixes

### Peer Dependency Conflicts

```bash
# See what's conflicting
npm ls --all | grep PEER

# Install with legacy peer deps (use carefully)
npm install --legacy-peer-deps
```

### Lock File Sync

```bash
# Regenerate lock file
rm package-lock.json
npm install
```

### Deduplicate

```bash
npm dedupe
```

## CI/CD Integration

Add to your CI pipeline:

```yaml
# .github/workflows/deps.yml
- name: Security Audit
  run: npm audit --audit-level=moderate

- name: Check Outdated
  run: |
    npm outdated || true  # Don't fail, just report
```

## Quick Commands

```bash
# Security quick check
npm audit --audit-level=high

# Outdated count
npm outdated 2>/dev/null | wc -l

# Unused deps list
npx depcheck 2>/dev/null | grep "Unused dependencies" -A 20

# Fix all safe issues
npm audit fix && npm update
```

## Integration

Use with:
- `/validate-build` - Ensure deps are valid
- `version-control-agent` - Before releases
- CI/CD pipelines - Automated checks
