<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Belege, Vorfälle und Messungen, die am 2026-09-24 (IMP-217) wörtlich aus rules/context-engineering.md ausgelagert wurden — die Regel selbst bleibt dort; hier steht das „Warum" in voller Länge.
-->
# Belege zu `rules/context-engineering.md`

> Ausgelagert 2026-09-24 (IMP-217). Jeder Block steht unter der Überschrift, unter der er in der Regel stand, und ist unverändert übernommen.

## Intro (blockquote under the H1 title)

> Reconciled empirical thresholds for managing Claude Code's context window. Derived from KB synthesis of 140 videos on context engineering (2026-05-26); converted to window-relative percentages 2026-07-03 (IMP-080) — windows now range from 200K up to 1M (`[1m]` model suffix), so absolute token constants mislead. Always loaded.

## Why Window-Relative (IMP-080)

The original thresholds (100K soft / 250K hard) were tuned for the Opus-4.x-era **200K** window. Sessions now run on models with windows up to **1M** (`[1m]` suffix, e.g. `claude-fable-5-1[1m]`). Absolute constants mislead in both directions: on a 1M window, 100K is only 10% fill (a premature `/clear` throws away healthy headroom); on a 200K window, treating 250K as "safe" is already past auto-compact. **All thresholds below are % of the active window.** The historical 200K numbers are kept as the worked example.

## References

> Source numbers below are absolute tokens from the 200K-window era (Opus 4.x); read them as the %-of-window thresholds above.

- Matt Pocock — "Full Walkthrough: Workflow for AI Coding" — smart-zone <100K threshold (= ~50% of 200K)
- Cole Medin — "2000+ Hours of Claude Code" / WHISK framework — 250K hallucination cliff (cited on larger-window models)
- Dex Horthy — "No Vibes Allowed: Solving Hard Problems in Complex Codebases" — 40% dumb-zone empirical
- Jared Zoneraich — "How Claude Code Works" — 92% auto-compact mechanism, H2A buffer (local override: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90`)
- Cluster source: see author's knowledge base (private)
