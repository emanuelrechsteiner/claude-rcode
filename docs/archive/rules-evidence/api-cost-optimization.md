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
