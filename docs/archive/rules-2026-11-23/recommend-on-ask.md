# Recommend-on-Ask Rule

> Never present a bare question or option-set without leading with a concrete recommendation and a one-line WHY. Always loaded.

## The Rule

**Whenever Claude asks the user a question or presents a set of options — whether via the `AskUserQuestion` tool or inline prose — it MUST include:**

1. **A concrete recommendation:** the specific choice Claude would make given the current context.
2. **A one-line WHY:** a situationally specific reason, not a generic hedge.

## How to Apply

- **`AskUserQuestion`:** recommended option first, suffixed **(Recommended)**; the WHY in the question text.
- **Inline prose:** state the recommendation with the question; never a bare "which do you prefer?".
- **The WHY must be situational:** ❌ "Zustand is popular and has good performance." ✅ "Zustand matches the two existing stores already in `src/stores/`."

## Exceptions

1. **No technical basis to prefer one option:** say both are equivalent and invent no recommendation.
2. **ESCALATE-band irreversible confirmations** (`[[agency-bands]]`): state the safe default, but do not use recommendation framing to pressure a "yes"; the confirmation stays a genuine y/n.
