# API Cost Optimization Rules

> Model-selection heuristics for Anthropic API calls. Refreshed for the Claude 5.x era 2026-09-27 (IMP-080, IMP-220). Always loaded.

## Model Era: Claude 5.x Family (2026-09)

Current tiers, cheapest → most capable: **Haiku 4.5 → Sonnet 5 → Opus 5.5 → Fable 5.1** (`claude-fable-5-1`, the tier above Opus). Price ratio (2026-09-27, input and output): 1:2:4:10. Window: Haiku 200K, others 1M. The structural heuristics below (N_turns cost equation, cache discipline, triage-then-depth) are model-era-independent; concrete price ratios are NOT. **Verify current pricing at docs.claude.com/pricing before any batch job** — never trust a ratio written down in a prior model era.

## The Dual-Model Default

**Default pattern for any two-step AI pipeline:** Haiku first for classification or filtering, Sonnet for nuanced generation or judgment.

## Model-Selection Decision Matrix

Use when choosing between Haiku 4.5 / Sonnet 5 / Opus 5.5 / Fable 5.1 for a given task.

> **Applied per-spawn via `agents/control-agent.md` §2 (IMP-091).** This matrix is the Model axis of the canonical dispatch spec — the control-agent (or the main-thread planner form) reads it once per atomic task to assign Model alongside Agent, Effort, and dependencies. This file stays the single source for the Model criteria; it is not re-derived in `foundation.md` or `parallel-by-default.md`.

| Dimension | Favors Haiku 4.5 | Favors Sonnet 5 | Favors Opus 5.5 | Favors Fable 5.1 |
|-----------|------------------|-----------------|-----------------|------------------|
| **Input length** | < 2K tokens | 2K–50K tokens | 50K+ tokens, multi-doc synthesis | Whole-framework corpora |
| **Semantic complexity** | Classification, extraction, formatting | Reasoning, drafting, code edits | Multi-step reasoning, architectural decisions, novel synthesis | Hardest synthesis — meta-analysis across many systems, novel cross-domain reasoning |
| **Output type** | Labels, JSON, regex-like extraction | Prose, code, structured plans | Plans spanning many files | Framework-wide meta-reviews, deep multi-source reports |
| **Cost sensitivity** | High-volume batch (email triage, log scan) | Interactive sessions | Rare one-offs where cost is dwarfed by value | Rarest tier — only where no lower tier has succeeded |
| **Latency requirement** | < 2s user-facing | 2–30s acceptable | Batch / async | Batch / async |
| **Accuracy bar** | 85% acceptable (human-in-the-loop possible) | 95%+ | Must-be-right on critical decisions | Must-be-right where Opus has demonstrably fallen short |

## Cheapest per Successful Outcome (2026-05 Reframe — structural heuristic, still valid)

> The equation is model-era-independent; plug in current per-token rates from docs.claude.com/pricing.

**The 2024 framing** ("pick the cheapest model that does the job" — historical) underweighted **turn count**. The 2026 reframe:

**Total cost = (input tokens + output tokens) × N_turns × price/token**

| Anti-pattern | Cost reality |
|---|---|
| Haiku-first for an agent loop with high N_turns | Pays N × cheap-token cost AND N × overhead of bad-turn cleanup |
| Sonnet-first for simple classification | Pays the tier-premium per call, but only 1 call |
| Opus/Fable for everything | Pays the top-tier premium on every call AND maximum context-window pressure |

**Heuristic:** Estimate `expected_N_turns_at_haiku × haiku_price` vs `expected_N_turns_at_sonnet × sonnet_price` (current prices from docs.claude.com/pricing, not from memory). If the Haiku product exceeds the Sonnet product, Sonnet wins on cost.

For **agent loops**, default to Sonnet unless you have evidence Haiku reliably one-shots the task.

## Cache Discipline — Model-Switch Kills Cache

> The flush mechanics are model-era-independent; the TTL and cache-write premiums are not — verify current values at docs.claude.com/pricing before relying on them in batch jobs.

Anthropic's prompt cache (5-min TTL, 1h optional; a hit costs 0.1× base input, 0.05× on Opus 5.5, 0.025× on Fable 5.1) is the single biggest cost-saver. **But every model switch flushes the entire cache** — the next call is full-price. This applies across the whole Claude 5 ladder: toggling Sonnet 5 ↔ Opus 5.5 ↔ Fable 5.1 mid-session flushes just like the old Opus/Sonnet toggle did.

### Anti-patterns

#### ❌ Opus-plan / Sonnet-execute toggling within one conversation
Hot pattern in the creator-szene. Every toggle = new cache. If you toggle 5 times in a 30-call session, you pay full price on 5 calls = ~10x the cost vs staying on one model.

**Fix:** Run plan + execute in **separate sessions**. Use the plan output as a context file (`@plan.md`) in the execute session. Each session keeps a warm cache.

#### ❌ Routinely switching between Sonnet / Haiku mid-conversation for "cost optimization"
Same flush. The savings from one cheap call are wiped out by the cache miss.

**Fix:** Pick a model per session based on session-class (interactive coding = Sonnet; high-volume batch = Haiku) and stick with it.

#### ❌ Cache TTL ignorance
Cache expires after 5 minutes of idle. If your session has ~5min gaps (thinking pauses, screen distractions), cache expires mid-conversation. Either keep a steady cadence or accept the miss.

### KPI to Track
**Cache hit rate target: 80–90%** across a session. If you can't hit that, your session pattern is the issue, not your model selection.

### Per-session checklist
- [ ] Decided which model serves this session
- [ ] No planned mid-session model switches
- [ ] Long stable system prompt (cached)
- [ ] Steady cadence (avoid 5-min idle gaps)

## Anti-Patterns

### ❌ Top-tier-for-everything (Opus or Fable as default)
Using Opus 5.5 — or worse, Fable 5.1 — as default pays a 2× / 5× premium over Sonnet 5 for work Sonnet handles equally well (verify at docs.claude.com/pricing). Reserve Opus for:
- Architectural planning across many files
- Novel synthesis where Sonnet has been observed to miss nuance on the specific domain

Reserve Fable 5.1 for:
- `/meta` style meta-analysis (framework-wide reasoning)
- The hardest synthesis tasks where Opus has demonstrably fallen short

### ❌ Single-model pipelines for triage-then-depth workflows
A single Sonnet call on 500 emails costs a full tier-multiple more than Haiku-filter → Sonnet-on-10% of those. If the first step is a filter, use Haiku.

### ❌ Ignoring prompt caching
For repeated work over stable context (long system prompts, retrieved docs), use Anthropic prompt caching. It is essentially free to enable; a read costs ≤10% of base input.

### ❌ Over-instrumented retries
Retrying Opus on every transient failure is expensive. Cap retries at 2, exponential backoff, fall back to smaller model on persistent failure.

## When to Escalate Models

The escalation ladder is **Haiku → Sonnet → Opus → Fable**. Allowed escalation triggers:
- Haiku → Sonnet: Haiku output scored below confidence threshold (e.g., 80%)
- Sonnet → Opus: Task involves cross-file architectural decisions, framework redesign, or complex multi-step reasoning
- Opus → Fable: Meta-analysis / hardest-synthesis class — framework-wide reviews, cross-system reasoning over very large corpora, or explicit evidence of Opus shortfall on the specific task
- Never: Escalating based on vague intuition — escalate only on measurable confidence gap or declared complexity class.

## Implementation Checklist

When writing new AI-powered code:
- [ ] Identify the task complexity class (filter/classify vs. generate/reason vs. synthesize/architect vs. meta-synthesize)
- [ ] Default to Haiku for the class's lowest tier
- [ ] Gate escalation to Sonnet on measurable confidence signal
- [ ] Reserve Opus for tasks that have explicit evidence of Sonnet shortfall; Fable only for evidence of Opus shortfall
- [ ] Verify current per-token pricing at docs.claude.com/pricing before launching any batch job
- [ ] Enable prompt caching for repeated-context workflows
- [ ] Log model-per-call for cost attribution

## References

- Anthropic pricing: **verify current per-token rates and tier ratios at docs.claude.com/pricing** — ratios change per model generation; the 2026-09-27 review is `docs/model-era-review-2026-09-27.md`
- IMP-011 in improvement-ledger.json; model-era refresh: IMP-080 (2026-07-03), IMP-220 (2026-09-27)

> Evidence and incident history (moved verbatim, IMP-217): `docs/archive/rules-evidence/api-cost-optimization.md`
