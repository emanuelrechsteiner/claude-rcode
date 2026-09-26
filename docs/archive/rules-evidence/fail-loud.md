<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/fail-loud.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/fail-loud.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Title blockquote (intro line)

Triangulated from Armin Ronacher + Danilo Campos (PostHog Wizard postmortem) + Mario Zechner (KB cluster 10, 2026-05-26).

## Why This Matters

Agents are statistically prone to writing "defensive" code that hides bugs:
- `except: pass` to "make the test green"
- `value = config.get("X") or "default"` when X is required
- `try { ... } catch { return null }` masking the real failure
- "Just adding a check" that silently skips broken paths

Each silent fallback **compounds reliability degradation** (slop-on-slop pattern from `slop-prevention.md`). At 0.95^20 = 36% reliability already without fallbacks, adding fallbacks accelerates the degradation toward zero.

## Repetition Without Escalation Is Also Silence (IMP-164, 2026-08-24)

Fail-loud is not satisfied by a routine that prints a warning every run if the warning never changes shape when nobody acts on it — the reader habituates, and an unresolved 20-day-old condition becomes visually identical to a fresh one-day condition. This is a distinct failure mode from the ones above: the failure *was* reported, every single time, and it was still effectively silent.

Three documented cases in the same August-2026 window, all traced to this exact pattern:

1. **"Backfill the 7 drifted metric lines"** (said in German) — reported identically in 8 consecutive nightly routine runs, never actioned.
2. **`NOTION_PARENT_PAGE_ID` missing** — reported 10× over 12 days, same wording each time.
3. **The IMP-138 observation-loop staleness counter** — fired for 20 consecutive days (`stale=7` on 2026-08-03 climbing to `stale=26` on 2026-08-22, while `shards=6` sat frozen the whole span) and was overlooked the entire time. This one is the sharpest case: the alarm was **never silent** — it printed every session-end for three weeks — and it was still missed, because each day's printout looked like just another day's printout.

## References

- Armin Ronacher — "The Friction Is Your Judgment"
- Danilo Campos — "LLM codegen fails" (PostHog Wizard postmortem)
- Mario Zechner — "Building pi in a World of Slop"
- Cluster source: see author's knowledge base (private)
