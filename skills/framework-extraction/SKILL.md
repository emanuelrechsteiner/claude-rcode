---
name: framework-extraction
description: Framework-in-Project pattern — develop a new framework (rules, commands, skills) INSIDE a host project first, then extract only when the 3-criteria trigger fires (stability + reuse need + pain frequency). Use when building or evolving a framework inside a host project, or deciding whether/how to extract it to a standalone repo. Triggers on "framework extraction", "extract framework", "framework-in-project", "when to extract", "extraction trigger", "extraction checklist", "standalone repo", "framework extrahieren", "framework auslagern", "in eigenes repo auslagern", "wann extrahieren".
---

# Framework-in-Project Extraction Pattern

> When building a new framework (rules, commands, skills), develop it INSIDE a host project first, then extract. Derived from R.Code-iOS development inside a reference iOS project, 2026-04. On-demand skill — demoted from always-loaded rule per IMP-079 (2026-07-03).

## The Pattern

**Framework lives inside host project until it earns extraction.** Host project provides real-world validation; extraction happens only after stability and reuse demand are proven.

```
host-project/
├── src/                           # normal project code
├── .rcode/                   # framework data (project-specific state)
│   ├── scope-manifest.json
│   └── PROJECT-STATUS.md
├── .claude/
│   ├── rules/                     # framework rules under development
│   │   ├── ios-swiftdata.md
│   │   └── ...
│   └── commands/                  # framework commands under development
│       ├── issue.md               # overrides global /issue for iOS specifics
│       └── phase-gate.md
└── .claude-meta/                  # framework meta (optional)
    └── extraction-notes.md        # what will be framework vs. project
```

Once the framework is stable + reused, extract to standalone repo + install mechanism.

## When to Use This Pattern

- Building a framework that NEEDS real-world validation (abstract specs often don't survive contact with reality)
- Framework is one of N, where N is initially 1 and reuse is hypothetical
- The extraction overhead would dominate actual framework work if done too early
- Target domain is rapidly evolving (iOS tooling, new language features) and the framework might change substantially

## When NOT to Use This Pattern

- Framework is a port of existing mature framework (skip in-project; extract from day one)
- Multiple consumers exist on day one (extract up front to avoid divergence)
- Framework crosses organization boundaries (ownership complications)
- Framework contains secrets or org-specific data (can leak through host project)

## The 3-Criteria Extraction Trigger

Extract when **all three** are true:

1. **Stability:** Framework files have changed < 10% in the last 30 days.
2. **Reuse need:** At least one additional project needs the framework AND the copy-paste cost exceeds extraction cost.
3. **Pain frequency:** Host project sees the framework as noise (e.g., contributors repeatedly ask "what is .rcode?" or framework changes pollute project PR reviews).

If one is missing, keep it in-project. Premature extraction creates:
- Versioning overhead before stability
- Install-mechanism work before reuse demand
- Documentation for nobody

## Extraction Checklist

When all 3 triggers fire:

- [ ] Freeze framework API — no breaking changes for 2 weeks before extraction
- [ ] Enumerate **framework** vs. **project-data** files:
  - Framework: rules, commands, skill templates, scaffolding
  - Project-data: PROJECT-STATUS.md, scope-manifest entries, agent-log.md, actual issues
- [ ] Create standalone framework repo with extraction-date README
- [ ] Add install script or doc (what gets copied into new host projects)
- [ ] Update host project to import framework (symlink, git subtree, or copy)
- [ ] Document the host project as "reference implementation" in framework repo
- [ ] Versioning: start at v0.x — first real user moves to v1.0

## Host-Project Hygiene During In-Project Phase

Keep framework work cleanly separable:
- **Directories:** Framework under `.rcode/`, `.claude/rules/`, `.claude/commands/`, `.claude/skills/` — never mix with `src/`.
- **Commits:** Framework changes in separate commits from product work. Commit prefix: `framework:` or `rcode:`.
- **PRs:** If project has PR discipline, separate PRs for framework vs. product. Reviewers skip framework PRs; framework maintainer skips product PRs.
- **Git ignore:** Nothing — framework files are versioned with the project until extraction.

## Anti-Patterns

### ❌ Extract on day one without reuse evidence
Result: v0.1 framework with 1 consumer, most time spent on packaging, nothing validated.

### ❌ Never extract despite obvious reuse demand
Result: copy-paste divergence across N projects, no single source of truth, drift accumulates.

### ❌ Extract before API stability
Result: framework breaks all consumers every week; consumers lose trust and fork.

### ❌ Mix framework + project-data in extraction
Result: consumers import PROJECT-STATUS.md of the host project; meaningless noise.

## Example Reference Case (2026-04)

Host: `[your iOS app]` (iOS Swift app).
Framework: R.Code-iOS (iOS-adapted atomic development workflow).

**Inside-project layout:**
- `.rcode/` — project-specific state (scope-manifest, PROJECT-STATUS)
- `.claude/rules/` — iOS-adapted rules (SwiftData, Swift Testing, i18n gate)
- `.claude/commands/` — `/issue` and `/phase-gate` overrides for iOS
- `.rcode-framework/` — extraction-candidate files (tracked but intended to migrate)

**Extraction criteria being watched:**
1. Stability: 2026-04-17 decision on Raw Xcode + Swift Testing + SwiftLint locked in → countdown start.
2. Reuse need: N = 1 (one host project). No extraction yet.
3. Pain frequency: low — iOS work is the majority of commits, framework noise is in-context.

→ Extraction is NOT triggered. Keep in-project. See IMP-012.
