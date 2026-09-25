<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Belege, Vorfälle und Messungen, die am 2026-09-24 (IMP-217) wörtlich aus rules/web-research-trust.md ausgelagert wurden — die Regel selbst bleibt dort; hier steht das „Warum" in voller Länge.
-->
# Belege zu `rules/web-research-trust.md`

> Ausgelagert 2026-09-24 (IMP-217). Jeder Block steht unter der Überschrift, unter der er in der Regel stand, und ist unverändert übernommen.

## Web Research Trust Rule (Einleitungszeile unter dem Titel)

> Standing permission to fetch, search, and scrape URLs for research WITHOUT per-URL confirmation. Pause and ask ONLY when the URL/domain crosses a malicious-content risk threshold. The deterministic slice is enforced by `web-fetch-safety-gate.sh`; the nuanced judgment is yours. Always loaded. (IMP-088, 2026-07-09)

## The Rule

This is the user's explicit threshold: *"nur fragen, wenn ein Risiko von <90%[-Sicherheit] besteht, dass die URL gefährliche Inhalte wie Viren enthält — sonst einfach abrufen."*

## How the two layers fit together

| Layer | Catches | Mechanism |
|-------|---------|-----------|
| `web-fetch-safety-gate.sh` (PreToolUse) | The **pattern-matchable** danger subset (raw IP, punycode, shorteners, binary downloads, creds-in-URL, abused TLDs) | Deterministic `permissionDecision:"ask"` — cannot be an LLM, so it only screens strings |
| **This rule (you)** | The **nuanced** subset (reputation, typosquat, warez, context/injection) a script cannot assess | Your own pause-and-ask before calling the fetch tool |

## References

- Origin: IMP-088 — the `ask: [WebFetch, WebSearch]` rule overrode every in-chat `allow` grant (`ask > allow`), so per-domain approvals never stuck.
