# API Cost Optimization Rules

> Model-selection heuristics for Anthropic API calls. Always loaded.

## Model Era: Claude 5.x Family (2026-09)

Tiers, cheapest → most capable: **Haiku 4.5 → Sonnet 5 → Opus 5.5 → Fable 5.1** (`claude-fable-5-1`, the tier above Opus). Price ratio (2026-09-27, input and output): 1:2:4:10. Window: Haiku 200K, others 1M. The structural heuristics below (N_turns cost equation, cache discipline, triage-then-depth) are model-era-independent; concrete price ratios, the cache TTL and cache-write premiums are NOT. **Verify current pricing, cache TTL and cache-write premiums at docs.claude.com/pricing before any batch job** — never trust a ratio written down in a prior model era.

## The Dual-Model Default

**Default for any two-step AI pipeline:** Haiku first for classification or filtering, Sonnet for nuanced generation or judgment.

## Model-Selection Decision Matrix

Use when choosing a tier for a task. It is the Model axis of the canonical per-spawn dispatch spec, `agents/control-agent.md` §2 (IMP-091), and the single source for the Model criteria — not re-derived in `foundation.md` or `parallel-by-default.md`.

| Dimension | Favors Haiku 4.5 | Favors Sonnet 5 | Favors Opus 5.5 | Favors Fable 5.1 |
|-----------|------------------|-----------------|-----------------|------------------|
| **Input length** | < 2K tokens | 2K–50K tokens | 50K+ tokens, multi-doc synthesis | Whole-framework corpora |
| **Semantic complexity** | Classification, extraction, formatting | Reasoning, drafting, code edits | Multi-step reasoning, architectural decisions, novel synthesis | Hardest synthesis — meta-analysis across many systems, novel cross-domain reasoning |
| **Output type** | Labels, JSON, regex-like extraction | Prose, code, structured plans | Plans spanning many files | Framework-wide meta-reviews, deep multi-source reports |
| **Cost sensitivity** | High-volume batch (email triage, log scan) | Interactive sessions | Rare one-offs where cost is dwarfed by value | Rarest tier — only where no lower tier has succeeded |
| **Latency requirement** | < 2s user-facing | 2–30s acceptable | Batch / async | Batch / async |
| **Accuracy bar** | 85% acceptable (human-in-the-loop possible) | 95%+ | Must-be-right on critical decisions | Must-be-right where Opus has demonstrably fallen short |

## Cheapest per Successful Outcome (2026-05 Reframe — structural heuristic, still valid)

**Total cost = (input tokens + output tokens) × N_turns × price/token** — "pick the cheapest model that does the job" underweights turn count.

| Anti-pattern | Cost reality |
|---|---|
| Haiku-first for an agent loop with high N_turns | N × cheap-token cost AND N × overhead of bad-turn cleanup |
| Sonnet-first for simple classification | The tier-premium per call, but only 1 call |
| Opus/Fable for everything | The top-tier premium on every call AND maximum context-window pressure |

**Heuristic:** if `expected_N_turns_at_haiku × haiku_price` exceeds `expected_N_turns_at_sonnet × sonnet_price` (current prices, not from memory), Sonnet wins on cost. For **agent loops**, default to Sonnet unless you have evidence Haiku reliably one-shots the task.

## Cache Discipline — Model-Switch Kills Cache

The prompt cache (5-min TTL, 1h optional; a hit costs 0.1× base input, 0.05× on Opus 5.5, 0.025× on Fable 5.1) is the single biggest cost-saver. **But every model switch flushes the entire cache** — the next call is full-price, anywhere on the Claude 5 ladder.

### Anti-patterns

- ❌ **Opus-plan / Sonnet-execute toggling within one conversation** — every toggle = new cache. **Fix:** plan and execute in **separate sessions**, the plan passed as a context file (`@plan.md`); each session keeps a warm cache.
- ❌ **Routinely switching between Sonnet / Haiku mid-conversation for "cost optimization"** — the cache miss wipes out the savings. **Fix:** pick one model per session by session-class (interactive coding = Sonnet; high-volume batch = Haiku) and stick with it.
- ❌ **Cache TTL ignorance** — the cache expires after 5 minutes idle: keep a steady cadence or accept the miss.
- ❌ **Ignoring prompt caching** — enable it for repeated work over stable context (long stable system prompts, retrieved docs): essentially free, a read costs ≤10% of base input.

**KPI: cache hit rate 80–90%** across a session; below that, the session pattern is the issue, not the model selection.

## Anti-Patterns

- ❌ **Top-tier-for-everything (Opus or Fable as default)** — pays a 2× / 5× premium over Sonnet 5 for work Sonnet handles equally well. Reserve Opus 5.5 for architectural planning across many files and novel synthesis where Sonnet has been observed to miss nuance on the specific domain; Fable 5.1 for `/meta`-style meta-analysis (framework-wide reasoning) and the hardest synthesis tasks where Opus has demonstrably fallen short.
- ❌ **Single-model pipelines for triage-then-depth workflows** — one Sonnet call on 500 emails costs a full tier-multiple more than Haiku-filter → Sonnet-on-10%. If the first step is a filter, use Haiku.
- ❌ **Over-instrumented retries** — retrying Opus on every transient failure is expensive: cap retries at 2, exponential backoff, fall back to a smaller model on persistent failure.

## When to Escalate Models

Ladder **Haiku → Sonnet → Opus → Fable**. Escalate only on a measurable confidence gap or a declared complexity class — never on vague intuition:
- Haiku → Sonnet: Haiku output scored below the confidence threshold (e.g., 80%)
- Sonnet → Opus: cross-file architectural decisions, framework redesign, or complex multi-step reasoning
- Opus → Fable: meta-analysis / hardest-synthesis class — framework-wide reviews, cross-system reasoning over very large corpora, or explicit evidence of Opus shortfall on the specific task

## Implementation Checklist

When writing new AI-powered code: identify the task complexity class (filter/classify vs. generate/reason vs. synthesize/architect vs. meta-synthesize); default to Haiku for the class's lowest tier; reserve Opus for tasks with explicit evidence of Sonnet shortfall, Fable only for evidence of Opus shortfall; log model-per-call for cost attribution. Escalation gating, prompt caching and the pricing check apply as stated above.

Ledger: IMP-011; model-era refresh IMP-080, IMP-220.
