# Project Status — [Project Name]

> Living progress dashboard. Updated by `/status-sync`, `/issue`, and `/phase-gate`.
> This is a Tier 1 document — always read when starting a session.

---

## Current Status

**Active Phase:** Phase [N] — [Phase Name]
**Overall Progress:** [X]% complete ([completed]/[total] units)
**Last Updated:** [ISO timestamp]
**Last Updated By:** [Agent identifier or "human"]

---

## Progress by Phase

<!-- Counts are work units (see .rcode/config.json → "tracker": "github" | "plan"). -->

| Phase | Name | Total Units | Done | In Progress | Blocked | Available | % |
|-------|------|-------------|------|-------------|---------|-----------|---|
| 1 | [Name] | [N] | [N] | [N] | [N] | [N] | [X]% |
| 2 | [Name] | [N] | [N] | [N] | [N] | [N] | [X]% |
| 3 | [Name] | [N] | [N] | [N] | [N] | [N] | [X]% |
| **Total** | | **[N]** | **[N]** | **[N]** | **[N]** | **[N]** | **[X]%** |

---

## Current Sprint

### Next Available Units

<!-- Units that are unblocked and ready to work on -->

| Unit | Title | Type | Area | Labels |
|------|-------|------|------|--------|
| [#N or P-NNN] | [Title] | [feat/fix/...] | [area] | `parallel-safe` |
| [#N or P-NNN] | [Title] | [feat/fix/...] | [area] | |

### Currently In Progress

| Unit | Title | Branch | Agent | Started |
|------|-------|--------|-------|---------|
| [#N or P-NNN] | [Title] | `feat/issue-N-...` (tracker github) or `feat/p-NNN-...` (tracker plan) | [Agent] | [Date] |

### Blocked Units

| Unit | Title | Blocked By | Reason |
|------|-------|------------|--------|
| [#N or P-NNN] | [Title] | [#N or P-NNN] | [Why it's blocked] |

---

## Recent Activity

| Date | Agent | Action | Unit | Details |
|------|-------|--------|------|---------|
| [Date] | [Agent] | Completed | [#N or P-NNN] | [Brief description] |
| [Date] | [Agent] | Started | [#N or P-NNN] | [Brief description] |
| [Date] | [Agent] | Phase Gate | Phase [N] | [Pass/Fail] |
| [Date] | [Agent] | Handoff | — | [Session summary] |

---

## Blockers & Risks

### Active Blockers

| # | Unit | Description | Owner | Since | Impact |
|---|------|-------------|-------|-------|--------|
| B1 | [#N or P-NNN] | [Description] | [Who can resolve] | [Date] | [HIGH/MED/LOW] |

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
| P1 | [Phase N — Name] | [Why this matters now] | [next release window / after Phase N gate / deferred] | [#N or P-NNN or blocking dependency] |
| P2 | [Phase N — Name] | [Why this matters] | [next release window / after Phase N gate / deferred] | [#N or P-NNN or —] |
| P3 | [Phase N — Name] | [Why this matters] | [next release window / after Phase N gate / deferred] | [#N or P-NNN or —] |

**Recommended Next Strategic Move:** [one-liner: what to prioritize next and WHY — the next strategic lever, not just the next unit.]

---

## Quality Metrics

<!-- Populated from this project's check trio (CLAUDE.md → Mandatory Pre-Commit). Use
     "[not configured]" for any row the stack doesn't produce — never a fabricated 0
     (fail-loud.md: a missing measurement is not the same as a clean one). -->

| Metric | Current | Target |
|--------|---------|--------|
| Type/Build Errors | [N or "not configured"] | 0 |
| Lint Warnings | [N or "not configured"] | 0 |
| Test Coverage | [N% or "not configured"] | [Target]% |
| Build Status | [Pass/Fail or "not configured"] | Pass |
