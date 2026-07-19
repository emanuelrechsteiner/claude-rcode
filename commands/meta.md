---
description: Meta-layer improvement system verification and self-enhancement activation
argument-hint: [--verify | --enhance | --analyze | --report] [--opus-mode]
model: claude-fable-5[1m]
allowed-tools:
  - Task
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash(jq:*)
  - Bash(git:*)
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `agents/control-agent.md` §4.

# Meta-Layer Self-Improvement System

Analyze and enhance the improvement system itself using advanced reasoning capabilities. This is the meta-layer that improves how the system improves.

## User Request

$ARGUMENTS

## Instructions

### 1. System Architecture Analysis
- Examine the current improvement system design and architecture
- Analyze agent coordination patterns and effectiveness
- Review workflow automation and integration points
- Assess the observation ledger system performance

### 2. Meta-Level Pattern Recognition
- Identify patterns in how improvements are discovered and implemented
- Analyze the effectiveness of different improvement strategies
- Review cross-project learning and knowledge transfer
- Evaluate the system's ability to adapt and evolve

### 3. Self-Enhancement Opportunities
- Identify ways to improve the improvement process itself
- Suggest enhancements to agent coordination mechanisms
- Recommend optimizations to the observation and learning system
- Propose new meta-strategies for system evolution

### 4. Quality Assurance Review
- Verify that improvements actually improve outcomes
- Check for unintended consequences of system changes
- Validate that the meta-system maintains coherence
- Ensure improvement processes remain comprehensible and maintainable

## `--verify` Mode — OPERATIONAL procedure (IMP-075, 2026-07-03)

When invoked with `--verify`, do NOT produce strategic prose. Execute this measurement loop:

1. **Select:** `jq` over `~/.claude/global-observation/improvement-ledger.json` → all entries with `status: implemented`.
2. **Measure** each entry that has a `verification` block (`{kpi, baseline, target, measured, measuredAt}`): compute the KPI's CURRENT value from the real data sources and compare against `target`:
   - Gate behavior → run `bash ~/.claude/hooks/tests/gate-regression.sh`; FP/block rates → `~/.claude/global-observation/excessive-agency.log` (+ `guard-overrides.log`)
   - Tool-discipline / read-before-edit → `error` events in `signals.jsonl` + `archives/signals-*.jsonl.gz` (first-class since IMP-075); pre-2026-07 baselines via `chat-archives/` grep or `historical-signals.db`
   - Session/observation health → `session-metrics.jsonl`, `nightly-obs-log.jsonl`, `daily-metrics.jsonl`
3. **Write back:** update `measured` + `measuredAt` in the ledger entry (jq/python surgery, single commit). An IMP whose measured value regressed below target gets flagged in the report AND a defect note in its entry.
4. **Unmeasurable entries** (no `verification` block — most pre-2026-07 IMPs): list them with a PROPOSED kpi+baseline each, so coverage grows every run. Never invent a measured value.
5. **Report:** table `IMP | KPI | baseline → measured | target | verdict (effective / regressed / unmeasurable)` + updated `outcomeMeasurementCoverage` in the ledger metrics block.
6. **Command-contract lint (IMP-089 closed-loop wiring, 2026-07-15):** as the deterministic KPI measurement for IMP-089 itself, run `bash ~/.claude/scripts/command-contract-lint.sh` over `~/.claude/commands/` and record its exit code + per-command failure lines verbatim as the `measured` value in IMP-089's `verification` block — do not paraphrase or round to "looks fine."

**Mandate:** every NEW ledger entry with `status: implemented` MUST carry a `verification` block at creation time (see meta-observer SKILL Step 6). No block → the implementation batch is incomplete.

### 5. Strategic Planning
- Develop roadmap for system evolution
- Prioritize meta-improvements by impact and feasibility
- Plan integration of new capabilities
- Establish metrics for meta-system effectiveness

### 6. Implementation Recommendations
- Provide specific, actionable meta-improvements
- Design implementation strategies that maintain system stability
- Create monitoring and validation frameworks
- Establish feedback loops for continuous meta-optimization

## Success Criteria
- Generate insights that improve the improvement system itself
- Maintain system coherence while enabling evolution
- Provide clear implementation roadmap for enhancements
- Establish robust feedback mechanisms for ongoing optimization