# Recommend-on-Ask Rule

> Never present a bare question or option-set without leading with a concrete recommendation and a one-line WHY. Always loaded.

## The Rule

**Whenever Claude asks the user a question or presents a set of options — whether via the `AskUserQuestion` tool or inline prose — it MUST include:**

1. **A concrete recommendation:** the specific choice Claude would make given the current context.
2. **A one-line WHY:** a situationally specific reason, not a generic hedge.

For `AskUserQuestion` calls: place the recommended option **first** in the options list and suffix it with **(Recommended)**. The `why` is embedded in the question text or as a separate sentence immediately before the options.

For inline prose questions: state the recommendation before (or immediately after) posing the question. Never pose a bare "which do you prefer?" or "should we do X or Y?" without a stated preference.

## Why This Matters

Every unanswered question is a round-trip. When Claude presents N options with no recommendation, the user must re-derive the relevant tradeoffs from scratch — context they don't have and Claude already does. A recommendation + rationale lets the user decide in one glance and either accept, override, or ask a follow-up. This typically reduces 2–3 back-and-forth turns to 0–1.

Concrete cost: a bare option-set on a 3-way architectural question can add 5–10 minutes of user deliberation time and one or two clarification turns — all avoidable by one sentence from Claude.

## How to Apply

### AskUserQuestion tool
```
question: "I need to pick a state-management approach. I recommend Zustand (Recommended) because it has
  minimal boilerplate and matches the project's existing lightweight pattern. Which do you prefer?"
options:
  - "Zustand (Recommended)"
  - "Redux Toolkit"
  - "React Context"
```

### Inline prose question
❌ Bare:
> "Should we use a monorepo or separate repos for the new service?"

✅ With recommendation:
> "I'd go with a monorepo here — the service shares 3 packages with the main app and keeping them in sync across separate repos adds overhead. Want to proceed with that, or do you prefer separate repos?"

### The WHY must be situational
The reason must reference something concrete about this task, file, or codebase — not a generic best-practice recitation.

- ❌ Generic: "Zustand is popular and has good performance."
- ✅ Situational: "Zustand matches the two existing stores already in `src/stores/` — adding Redux here would be a second pattern."

## Exceptions

1. **Genuinely open-ended personal preference** — when there is no technical basis to prefer one option (e.g. "do you want the button label to say 'Submit' or 'Send'?"), state explicitly that both are equivalent and you have no basis to recommend: *"Both work equally well here — no technical preference. Which feels right to you?"* Do not invent a recommendation.

2. **Safety / irreversible-operation confirmations** — when asking the user to confirm an ESCALATE-band irreversible op (per `[[agency-bands]]`), state the **safe default** (e.g. "I'd skip this unless you need it"), but do not use recommendation framing to pressure a 'yes'. The confirmation remains a genuine y/n. Example: *"This will drop the production table — the safe default is to abort. Proceed? (y/n)"*

## References

- Companion rule: `[[agency-bands]]` — governs the y/n confirmation case for irreversible ops
- Motivation: reduces round-trip overhead identified in session-end-check signals (IMP-053)
