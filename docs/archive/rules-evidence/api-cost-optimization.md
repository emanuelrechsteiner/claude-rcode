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
