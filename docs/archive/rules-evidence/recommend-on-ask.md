<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/recommend-on-ask.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/recommend-on-ask.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Why This Matters

Every unanswered question is a round-trip. When Claude presents N options with no recommendation, the user must re-derive the relevant tradeoffs from scratch — context they don't have and Claude already does. A recommendation + rationale lets the user decide in one glance and either accept, override, or ask a follow-up. This typically reduces 2–3 back-and-forth turns to 0–1.

Concrete cost: a bare option-set on a 3-way architectural question can add 5–10 minutes of user deliberation time and one or two clarification turns — all avoidable by one sentence from Claude.
