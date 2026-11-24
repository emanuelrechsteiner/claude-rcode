<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/api-cost-optimization.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/api-cost-optimization.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Intro line

Derived from a production two-phase email triage pipeline (2026-04).

## Model Era: Claude 5 Family (2026-07)

Examples dated 2024–2026 below are historical evidence for the *patterns*, not current price claims.

## Evidence: Two-Phase Email Triage Pipeline (historical, 2026-04 — Claude 4.x era)

- **Phase A (Haiku 4.5):** 4-way classification (IMPORTANT / ACTION / INFO / IGNORE) on ~200-char thread previews. Fast, cheap, deterministic enough for triage.
- **Phase B (Sonnet 4.6):** Reply-audit on unreplied threads where a human response is likely required. Requires nuance — intent, tone, stakeholder-importance. 90% confidence gate before flagging as urgent-reply.

Result: 2 daily runs at 7:00 + 12:00, within Apps Script 6-min execution limit, cost scales with volume but 80%+ of tokens stay on Haiku tier.

## Cheapest per Successful Outcome (2026-05 Reframe — structural heuristic, still valid)

Added 2026-05-26 after KB synthesis of 109 prompting / cost videos (Anthropic talks + Cole Medin + practitioners).

A "cheap" Haiku call that loops 8 times to hit the right answer is often **more expensive** than ONE Sonnet call that solves it correctly. And the Sonnet call avoids context pollution from N retries.

**Source:** Anthropic "Picking the right model" talk (2026); Cole Medin "REAL cost of LLM (78%+ cost reduction)" — both reframe the cost equation around success-rate, not per-token-rate.

## Cache Discipline — Model-Switch Kills Cache

Added 2026-05-26.

Hot pattern in the creator-szene.

If you toggle 5 times in a 30-call session, you pay full price on 5 calls = ~10x the cost vs staying on one model.

**Source:** Anthropic "Token-savings" talk (2026); Cole Medin "GitHub is the Future of AI Coding" — model-switch cache-flush warning is verbatim across both.

## References

- Two-phase email triage pipeline (Apps Script): reference implementation in your own scripts directory (historical, Claude 4.x era)

the old Claude-4-era "haiku ≈ 1/10 sonnet ≈ 1/50 opus" is historical, not current

## Moved from the rule on 2026-09-29 (IMP-234)

> Moved out verbatim while the rule was condensed to its normative core. Each block names the heading it sat under; the normative content of each block is still stated in the rule.

### Title blockquote

> Model-selection heuristics for Anthropic API calls. Refreshed for the Claude 5.x era 2026-09-27 (IMP-080, IMP-220). Always loaded.

### Model-Selection Decision Matrix — intro

Use when choosing between Haiku 4.5 / Sonnet 5 / Opus 5.5 / Fable 5.1 for a given task.

> **Applied per-spawn via `agents/control-agent.md` §2 (IMP-091).** This matrix is the Model axis of the canonical dispatch spec — the control-agent (or the main-thread planner form) reads it once per atomic task to assign Model alongside Agent, Effort, and dependencies. This file stays the single source for the Model criteria; it is not re-derived in `foundation.md` or `parallel-by-default.md`.

### Cheapest per Successful Outcome — framing

**The 2024 framing** ("pick the cheapest model that does the job" — historical) underweighted **turn count**. The 2026 reframe:

### Cache Discipline — ladder sentence

This applies across the whole Claude 5 ladder: toggling Sonnet 5 ↔ Opus 5.5 ↔ Fable 5.1 mid-session flushes just like the old Opus/Sonnet toggle did.

### ❌ Cache TTL ignorance

Cache expires after 5 minutes of idle. If your session has ~5min gaps (thinking pauses, screen distractions), cache expires mid-conversation. Either keep a steady cadence or accept the miss.

### References

- Anthropic pricing: **verify current per-token rates and tier ratios at docs.claude.com/pricing** — ratios change per model generation; the 2026-09-27 review is `docs/model-era-review-2026-09-27.md`
- IMP-011 in improvement-ledger.json; model-era refresh: IMP-080 (2026-07-03), IMP-220 (2026-09-27)

## Moved 2026-11-10 (context diet)

Source: pre-diet rules/api-cost-optimization.md (2026-11-10 snapshot). The whole old body, verbatim, incl. the price table, legacy era, baseline measurement and anti-pattern tables.

## Model Era: Claude 5.x Family (2026-10)

Tiers, cheapest → most capable: **Haiku 5.5 → Sonnet 5.5 → Opus 5.5 → Fable 5.1**. The full ids on the Anthropic API are `claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5` and `claude-fable-5-1`; the Agent tool's `model` parameter takes only the aliases `haiku`, `sonnet`, `opus` and `fable`, and this file uses the aliases throughout. Price ratio, input and output (per MTok; Anthropic API reference cached 2026-10-06): 1:20:40:100 — Haiku 5.5 $0.10 in / $0.50 out for prompts up to 100K tokens ($0.50 / $2.50 above 100K), Sonnet 5.5 $2 / $10, Opus 5.5 $4 / $20, Fable 5.1 $10 / $50. Window: 1M on all four tiers. Haiku 5.5 runs adaptive thinking that is always on; `MAX_THINKING_TOKENS` cannot bound or disable it. Measurement baseline (dated 2026-10-12, as captured): of the last 1,054 sub-agent dispatches, 575 were `sonnet`, 203 `opus`, 230 had no `model` set, 36 `inherit`, 6 `fable` and 4 `haiku` (0.4 %); a later reader measures the shift against this line.

Legacy era (superseded by the facts above, kept for reference): Haiku 4.5 → Sonnet 5 → Opus 5.5 → Fable 5.1 at 1:2:4:10, Haiku window 200K.

The structural heuristics below (N_turns cost equation, cache discipline, triage-then-depth) are model-era-independent; concrete price ratios, the cache TTL and cache-write premiums are NOT. **Verify current pricing, cache TTL and cache-write premiums at docs.claude.com/pricing before any batch job** — never trust a ratio written down in a prior model era.

## The Haiku-First Default

**Default for every worker sub-agent: Haiku 5.5 (`haiku`).** Classification, extraction, formatting, drafting, code edits, tests and review all start on Haiku, and the task's named check decides whether its output stands. Haiku 5.5 defaults to `medium` effort, so every spawn states its effort explicitly (`agents/control-agent.md` §2). Sonnet, Opus and Fable are assigned to a worker only under the recorded-failure rule in When to Escalate Models.

## Model-Selection Decision Matrix

Use when choosing a tier for a task. It is the Model axis of the canonical per-spawn dispatch spec, `agents/control-agent.md` §2 (IMP-091), and the single source for the Model criteria — not re-derived in `foundation.md` or `parallel-by-default.md`. The Latency row of the earlier matrix is dropped: no Haiku 5.5 latency figure exists in the sources used for this revision.

| Dimension | Haiku 5.5 (`haiku`) | Sonnet 5.5 (`sonnet`) | Opus 5.5 (`opus`) | Fable 5.1 (`fable`) |
|-----------|---------------------|-----------------------|-------------------|---------------------|
| **Role** | Default for every worker sub-agent: classification, extraction, formatting, drafting, code edits, tests, review | Worker only after a recorded Haiku failure on that task class | Coordinator for complex multi-spawn work, cross-file architecture, planning | Team lead for the hardest coordination, `/meta`-style meta-analysis |
| **Input length** | Up to 100K tokens for the cheapest rate; above that the price rises (see Price row) | 2K–50K tokens | 50K+ tokens, multi-doc synthesis | Whole-framework corpora |
| **Semantic complexity** | Classification, extraction, formatting, drafting, code edits, tests, review | Reasoning, drafting, code edits | Multi-step reasoning, architectural decisions, novel synthesis | Hardest synthesis — meta-analysis across many systems, novel cross-domain reasoning |
| **Output type** | Labels, JSON, extraction, prose, code edits, test code | Prose, code, structured plans | Plans spanning many files | Framework-wide meta-reviews, deep multi-source reports |
| **Cost sensitivity** | High-volume and default worker traffic | Interactive worker tasks after escalation | Rare one-offs and planning where cost is dwarfed by value | Team lead only; the top price, so reserved for coordination |
| **Accuracy bar** | Named check must pass on its output (tests, build, reviewer); a failure is escalation evidence | 95%+, on a task class with a recorded Haiku failure | Must-be-right on critical decisions | Must-be-right where Opus has demonstrably fallen short |
| **Price in / out per MTok** | `claude-haiku-5-5`: $0.10 / $0.50 (prompts up to 100K); $0.50 / $2.50 above | `claude-sonnet-5-5`: $2 / $10 | `claude-opus-5-5`: $4 / $20 | `claude-fable-5-1`: $10 / $50 |

## Cheapest per Successful Outcome (2026-05 Reframe — structural heuristic, still valid)

**Total cost = (input tokens + output tokens) × N_turns × price/token** — "pick the cheapest model that does the job" underweights turn count.

| Anti-pattern | Cost reality |
|---|---|
| Sonnet-first for a worker task with no recorded Haiku failure | The 20× tier premium per call, with no evidence that Haiku 5.5 cannot do the task |
| Haiku-first for an agent loop with high N_turns and no named check | N × cheap-token cost AND N × overhead of bad-turn cleanup |
| Opus/Fable for everything | The top-tier premium on every call AND maximum context-window pressure |

**Heuristic:** if `expected_N_turns_at_haiku × haiku_price` exceeds `expected_N_turns_at_sonnet × sonnet_price` (current prices, not from memory), Sonnet wins on cost. For **agent loops**, Haiku 5.5 stays the worker default; a loop that fails its named check on Haiku is the recorded-failure case that permits Sonnet, not a reason to start on Sonnet.

## Cache Discipline — Model-Switch Kills Cache

The prompt cache (5-min TTL, 1h optional; a hit costs 0.1× base input, 0.05× on Opus 5.5, 0.025× on Fable 5.1) is the single biggest cost-saver. The Haiku 5.5 cache-read multiplier is not verified in this file: check the pricing page before quoting one. **But every model switch flushes the entire cache** — the next call is full-price, anywhere on the Claude 5 ladder.

### Anti-patterns

- ❌ **Opus-plan / Sonnet-execute toggling within one conversation** — every toggle = new cache. **Fix:** plan and execute in **separate sessions**, the plan passed as a context file (`@plan.md`); each session keeps a warm cache.
- ❌ **Routinely switching between Sonnet / Haiku mid-conversation for "cost optimization"** — the cache miss wipes out the savings. **Fix:** pick one model per session by session-class (worker = Haiku 5.5; coordinator = Fable 5.1 or Opus 5.5; Sonnet 5.5 only for a named, escalated task) and stick with it.
- ❌ **Cache TTL ignorance** — the cache expires after 5 minutes idle: keep a steady cadence or accept the miss.
- ❌ **Ignoring prompt caching** — enable it for repeated work over stable context (long stable system prompts, retrieved docs): essentially free, a read costs ≤10% of base input.

**KPI: cache hit rate 80–90%** across a session; below that, the session pattern is the issue, not the model selection.

## Anti-Patterns

- ❌ **Top-tier-for-everything (Opus or Fable as the worker default)** — pays a 2× / 5× premium over Sonnet 5.5 and a 40× / 100× premium over Haiku 5.5 on a task the worker default covers. Reserve Opus 5.5 for coordinators on complex multi-spawn work, cross-file architecture and planning; Fable 5.1 for the team lead, for `/meta`-style meta-analysis (framework-wide reasoning) and for the hardest synthesis tasks where Opus has demonstrably fallen short.
- ❌ **Single-model pipelines for triage-then-depth workflows** — one Sonnet call on 500 emails costs 20× a Haiku call. If the first step is a filter, use Haiku; a depth step on Sonnet needs the recorded-failure evidence of When to Escalate Models, not a default.
- ❌ **Over-instrumented retries** — retrying Opus or Fable on every transient failure is expensive: cap retries at 2, exponential backoff. A failure that repeats on Haiku 5.5 is an escalation case: record it, retry once at a higher effort, and only then move up under When to Escalate Models.

## When to Escalate Models

A worker moves up the ladder **Haiku → Sonnet → Opus → Fable** only on recorded evidence. Each step needs all three of these:

1. The same task class ran on Haiku and failed its named check — record the check, the spawn and the failing output.
2. The task was retried once at a higher effort (e.g. `medium` → `high`) and still failed.
3. The failure is recorded where a later reader finds it: the ledger, the task list or the agent log.

Sonnet → Opus and Opus → Fable follow the same rule for workers. Cross-file architecture and planning go to a coordinator tier by role, not to a worker escalation.

**Coordinators are assigned by role, never climbed to:** `/team-lead`, the other command pins and `control-agent` run Fable 5.1 (Opus 5.5 is permitted for coordinators); the planning coordinators `planning-agent` (agent) and the skills `project-planning` and `meta-observer` run Opus 5.5.

One standing exception: `visual-qa-agent` stays on Sonnet, because the owner rule of 2026-10-09 excludes Haiku from browser click-work and the owner's decision on that rule is pending.

## Implementation Checklist

When writing new AI-powered code: identify the task complexity class (filter/classify vs. generate/reason vs. synthesize/architect vs. meta-synthesize); default to Haiku 5.5 for the worker tier of every class; assign coordinator tiers by role (Opus 5.5 or Fable 5.1); move a tier up only on recorded evidence of a failed named check (When to Escalate Models); log model-per-call for cost attribution. Escalation gating, prompt caching and the pricing check apply as stated above.

Ledger: IMP-011; model-era refresh IMP-080, IMP-220, IMP-255.
