# Project Status — [Project Name]

> Living progress dashboard. Updated by `/status-sync`, `/issue`, and `/phase-gate`.
> This is a Tier 1 document — always read when starting a session.

---

## Current Status

**Active Phase:** Phase [N] — [Phase Name]
**Overall Progress:** [X]% complete ([completed]/[total] issues)
**Last Updated:** [ISO timestamp]
**Last Updated By:** [Agent identifier or "human"]

---

## Progress by Phase

| Phase | Name | Total | Done | In Progress | Blocked | Available | % |
|-------|------|-------|------|-------------|---------|-----------|---|
| 1 | [Name] | [N] | [N] | [N] | [N] | [N] | [X]% |
| 2 | [Name] | [N] | [N] | [N] | [N] | [N] | [X]% |
| 3 | [Name] | [N] | [N] | [N] | [N] | [N] | [X]% |
| **Total** | | **[N]** | **[N]** | **[N]** | **[N]** | **[N]** | **[X]%** |

---

## Current Sprint

### Next Available Issues

<!-- Issues that are unblocked and ready to work on -->

| Issue | Title | Type | Area | Labels |
|-------|-------|------|------|--------|
| #[N] | [Title] | [feat/fix/...] | [area] | `parallel-safe` |
| #[N] | [Title] | [feat/fix/...] | [area] | |

### Currently In Progress

| Issue | Title | Branch | Agent | Started |
|-------|-------|--------|-------|---------|
| #[N] | [Title] | `feat/issue-N-...` | [Agent] | [Date] |

### Blocked Issues

| Issue | Title | Blocked By | Reason |
|-------|-------|------------|--------|
| #[N] | [Title] | #[N] | [Why it's blocked] |

---

## Recent Activity

| Date | Agent | Action | Issue | Details |
|------|-------|--------|-------|---------|
| [Date] | [Agent] | Completed | #[N] | [Brief description] |
| [Date] | [Agent] | Started | #[N] | [Brief description] |
| [Date] | [Agent] | Phase Gate | Phase [N] | [Pass/Fail] |
| [Date] | [Agent] | Handoff | — | [Session summary] |

---

## Blockers & Risks

### Active Blockers

| # | Issue | Description | Owner | Since | Impact |
|---|-------|-------------|-------|-------|--------|
| B1 | #[N] | [Description] | [Who can resolve] | [Date] | [HIGH/MED/LOW] |

### Upcoming Risks

| # | Risk | Phase | Mitigation | Status |
|---|------|-------|------------|--------|
| R1 | [Risk] | [Phase N] | [Plan] | Monitoring |

---

## Scope Health

**Scope Manifest Status:** [Locked / Unlocked]
**Total Features:** [N]
**Features Complete:** [N]
**Scope Changes:** [N] (see `.rcode/scope-manifest.json`)

---

## Roadmap / Strategic Prioritization

**Strategic Posture:** [Ship / Consolidate] — [one line: is now a good moment to ship/release or to consolidate? Derived from current phase completion %, open blockers, and test/quality status.]

| Priority | Phase / Milestone | Strategic Rationale | Suggested Timing | Must-Precede |
|----------|-------------------|---------------------|------------------|--------------|
| P1 | [Phase N — Name] | [Why this matters now] | [next release window / after Phase N gate / deferred] | [#N or blocking dependency] |
| P2 | [Phase N — Name] | [Why this matters] | [next release window / after Phase N gate / deferred] | [#N or —] |
| P3 | [Phase N — Name] | [Why this matters] | [next release window / after Phase N gate / deferred] | [#N or —] |

**Recommended Next Strategic Move:** [one-liner: what to prioritize next and WHY — the next strategic lever, not just the next issue.]

---

## Quality Metrics

| Metric | Current | Target |
|--------|---------|--------|
| TypeScript Errors | [N] | 0 |
| ESLint Warnings | [N] | 0 |
| Test Coverage | [N]% | [Target]% |
| Build Status | [Pass/Fail] | Pass |
