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

## Moved from the rule on 2026-09-29 (IMP-234)

> Moved out verbatim while the rule was condensed to its normative core (at most one example per rule). The rule keeps the situational-WHY ❌/✅ pair and one phrasing per exception; the other examples are kept here.

### How to Apply — AskUserQuestion tool (verbatim)
```
question: "I need to pick a state-management approach. I recommend Zustand (Recommended) because it has
  minimal boilerplate and matches the project's existing lightweight pattern. Which do you prefer?"
options:
  - "Zustand (Recommended)"
  - "Redux Toolkit"
  - "React Context"
```

### How to Apply — Inline prose question (verbatim)
❌ Bare:
> "Should we use a monorepo or separate repos for the new service?"

✅ With recommendation:
> "I'd go with a monorepo here — the service shares 3 packages with the main app and keeping them in sync across separate repos adds overhead. Want to proceed with that, or do you prefer separate repos?"

### Exceptions — original wording (verbatim)

1. **Genuinely open-ended personal preference** — when there is no technical basis to prefer one option (e.g. "do you want the button label to say 'Submit' or 'Send'?"), state explicitly that both are equivalent and you have no basis to recommend: *"Both work equally well here — no technical preference. Which feels right to you?"* Do not invent a recommendation.

2. **Safety / irreversible-operation confirmations** — when asking the user to confirm an ESCALATE-band irreversible op (per `[[agency-bands]]`), state the **safe default** (e.g. "I'd skip this unless you need it"), but do not use recommendation framing to pressure a 'yes'. The confirmation remains a genuine y/n. Example: *"This will drop the production table — the safe default is to abort. Proceed? (y/n)"*

### References (verbatim)

- Companion rule: `[[agency-bands]]` — governs the y/n confirmation case for irreversible ops
- Motivation: reduces round-trip overhead identified in session-end-check signals (IMP-053)
