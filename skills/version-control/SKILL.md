---
name: version-control
description: Git operations and release management specialist. Handles branching strategies, conventional commits, PR management, release coordination, and clean Git history. Use when managing git operations, creating commits, handling branches, preparing releases, or managing PRs. Triggers on "git", "commit", "branch", "merge", "release", "PR", "pull request", "version", "tag", "push", "committe das", "commit machen", "branch erstellen", "branch anlegen", "PR öffnen", "pull request erstellen", "merge in main", "release vorbereiten", "tag setzen", "push auf origin", "rebase", "git state".
context: fork
model: haiku
allowed-tools: Bash(git:*), Bash(gh:*), Read, Grep
---

# Version Control Skill - Git Operations & Release Management

## Memory-First Protocol (MANDATORY)

Before starting any task:
1. Query Memory MCP for project and release context: `mcp__memory__search_nodes`
2. Load related version history entities using `mcp__memory__open_nodes`

During task execution:
- Create release entities: `mcp__memory__create_entities` with type "Release"
- Add version notes as observations: `mcp__memory__add_observations`
- Link releases to features and changes: `mcp__memory__create_relations`

## Core Competencies

### 1. Git Operations Management
- **Branch Strategy**: Feature branches, integration, and release management
- **Commit Management**: Conventional commits, meaningful messages, clean history
- **Merge Coordination**: Conflict resolution, integration testing, rollback
- **Release Management**: Version tagging, release notes, deployment coordination

### 2. Code Quality Gates
- **Pre-commit Validation**: Ensure tests pass, linting compliance, TypeScript checks
- **Integration Testing**: Validate feature branches before merging
- **Rollback Procedures**: Quick recovery from problematic commits
- **History Maintenance**: Clean, readable commit history with proper attribution

## Branch Structure
```
main                        # Production-ready code
├── feature/[name]          # Feature implementation
├── fix/[issue]             # Bug fixes
├── hotfix/*                # Emergency fixes
└── release/[version]       # Release preparation
```

## Commit Convention
```
type(scope): description

feat(venues): add venue creation form with validation
fix(artists): resolve tour relationship loading issue
docs(readme): update setup instructions for new pages
test(venues): add comprehensive venue CRUD tests
refactor(stores): optimize venue store performance
chore(deps): update dependencies to latest versions
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting, missing semicolons, etc.
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `test`: Adding missing tests
- `chore`: Maintenance tasks

## Commit Workflow

### Creating Commits
```bash
# Stage changes
git add .

# Create commit with conventional message
git commit -m "$(cat <<'EOF'
feat(component): add new feature

- Detailed description of changes
- List specific modifications
- Note breaking changes if any

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Feature Branch Workflow
```bash
# Create feature branch
git checkout -b feature/venue-page
git push -u origin feature/venue-page

# Regular development commits
git add .
git commit -m "feat(venues): implement venue list component"
git push origin feature/venue-page

# Merge back to main (after approval)
git checkout main
git pull origin main
git merge feature/venue-page
git push origin main
git tag -a v1.1.0 -m "Add venue management page"
```

## Pre-commit Quality Gates

### Automated Checks
```bash
#!/bin/sh
echo "Running pre-commit checks..."

# TypeScript compilation
npm run build || exit 1

# Linting
npm run lint || exit 1

# Tests
npm run test:run || exit 1

echo "All pre-commit checks passed"
```

### Manual Verification Checklist
- [ ] All new components have TypeScript interfaces
- [ ] Unit tests written for new functionality
- [ ] Storybook stories created for UI components
- [ ] Documentation updated appropriately
- [ ] No breaking changes introduced
- [ ] Performance impact assessed

## Merge Strategy

### Integration Process
1. **Development Complete**: All tasks finished and validated
2. **Self-Testing**: Feature branch thoroughly tested
3. **Documentation Updated**: All relevant docs reflect changes
4. **Pre-merge Review**: Final approval
5. **Integration Testing**: Test with main branch
6. **Merge Execution**: Clean merge with proper message
7. **Post-merge Validation**: Verify no regressions

### Merge Commit Template
```
Merge branch 'feature/venue-page' into main

* Complete venue management page implementation
* Add VenueList, VenueForm, VenueCard components
* Implement venueManagementStore with CRUD operations
* Add comprehensive test coverage (95%+)
* Update documentation and Storybook stories

Closes #123
Co-authored-by: Claude <noreply@anthropic.com>
```

## Release Management

### Version Numbering
- **Major (X.0.0)**: Breaking changes, major features
- **Minor (1.X.0)**: New features, backward compatible
- **Patch (1.1.X)**: Bug fixes, minor improvements

### Release Notes Template
```markdown
# Release v1.1.0 - [Feature Name]

## New Features
- Feature description with details

## Technical Improvements
- Backend/infrastructure changes

## Documentation
- Documentation updates

## Testing
- Test coverage and validation

## Security
- Security-related changes
```

## Pull Request Workflow

### Creating PRs
```bash
# Check status
git status
git diff

# Push branch
git push -u origin feature/name

# Create PR
gh pr create --title "feat: add feature" --body "$(cat <<'EOF'
## Summary
- Key changes

## Test plan
- [ ] Testing checklist

Generated with Claude Code
EOF
)"
```

## Conflict Resolution

### Strategy
1. **Prevention**: Regular rebasing with main branch
2. **Detection**: Automated conflict detection in CI/CD
3. **Resolution**: Collaborative resolution with affected parties
4. **Validation**: Full testing after conflict resolution
5. **Documentation**: Record resolution strategies

## Success Criteria

- All commits follow conventional commit format
- Feature branches integrate cleanly with main
- No regressions introduced during merges
- Release process is smooth and well-documented
- Git history remains clean and readable
- Rollback procedures work when needed
