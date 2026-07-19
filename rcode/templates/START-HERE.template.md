# Start Here — [Project Name]

> Onboarding entry point for new agents and contributors.
> Read this FIRST. Time to orient: ~2 minutes.

---

## What Is This?

[One paragraph: What is this project? What does it do? Who is it for?]

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | [Technology + version] |
| Backend | [Technology + version] |
| Database | [Technology + version] |
| Auth | [Technology] |
| Hosting | [Platform] |
| Testing | [Framework] |

---

## Current Status

**Phase [N] of [M]** — [Phase Name] — **[X]% complete**

> For detailed progress, see `PROJECT-STATUS.md`

---

## Key Documents

| Document | Purpose | When to Read |
|----------|---------|--------------|
| `START_HERE.md` | You are here | Always first |
| `PROJECT-STATUS.md` | Progress dashboard, next issue | Every session start |
| `CONVENTIONS.md` | Code patterns, naming, structure | Before writing code |
| `ARCHITECTURE.md` | Tech decisions, ADRs, system design | When making tech choices |
| `SPECIFICATION.md` | Features, design system, brand | When implementing UI |
| `BRAINSTORM.md` | Master plan, all phases and issues | Reference only |
| `RESEARCH_FINDINGS.md` | Technology evaluation | Reference only |
| `CLAUDE.md` | Agent-specific instructions | Auto-loaded |

---

## Environment Setup

```bash
# 1. Clone the repository
git clone [REPO_URL]
cd [PROJECT_NAME]

# 2. Install dependencies
[INSTALL_COMMAND]

# 3. Set up environment variables
cp .env.example .env.local
# Fill in required values (see ARCHITECTURE.md § Environment Variables)

# 4. Start development server
[DEV_COMMAND]

# 5. Run tests
[TEST_COMMAND]
```

---

## Contribution Flow

```
1. /rcode-onboard     ← Orient yourself (you're doing this now)
2. Pick an issue            ← From PROJECT-STATUS.md "Next Available"
3. /issue <#>              ← Full development workflow
4. /review <PR#>           ← Code review before merge
5. /clear                  ← Clean context between issues
6. Repeat from step 2
```

---

## Quick Reference

- **Commit format:** `<type>(<area>): <description> - closes #<N>`
- **Branch format:** `<type>/issue-<N>-<description>`
- **Before commit:** `npx tsc --noEmit && npm test && npm run build`
- **Scope rules:** See `.claude/rules/rcode-scope.md`
- **Phase gate:** Run `/phase-gate <N>` when all phase issues are closed

---

## Need Help?

| I need to... | Do this |
|--------------|---------|
| Understand the architecture | Read `ARCHITECTURE.md` |
| Know the code conventions | Read `CONVENTIONS.md` |
| See the full plan | Read `BRAINSTORM.md` |
| Check feature requirements | Read `SPECIFICATION.md` |
| See what happened before | Read `.rcode/phase-summaries/` |
| See what the last agent did | Read `.rcode/agent-log.md` (last entry) |
