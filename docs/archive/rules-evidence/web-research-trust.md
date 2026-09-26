<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/web-research-trust.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/web-research-trust.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Web Research Trust Rule (intro line under the title)

> Standing permission to fetch, search, and scrape URLs for research WITHOUT per-URL confirmation. Pause and ask ONLY when the URL/domain crosses a malicious-content risk threshold. The deterministic slice is enforced by `web-fetch-safety-gate.sh`; the nuanced judgment is yours. Always loaded. (IMP-088, 2026-07-09)

## The Rule

This is the user's explicit threshold: *"only ask if there's a <90%[-confidence] risk that the URL contains dangerous content like viruses — otherwise just fetch it."* (said in German)

## How the two layers fit together

| Layer | Catches | Mechanism |
|-------|---------|-----------|
| `web-fetch-safety-gate.sh` (PreToolUse) | The **pattern-matchable** danger subset (raw IP, punycode, shorteners, binary downloads, creds-in-URL, abused TLDs) | Deterministic `permissionDecision:"ask"` — cannot be an LLM, so it only screens strings |
| **This rule (you)** | The **nuanced** subset (reputation, typosquat, warez, context/injection) a script cannot assess | Your own pause-and-ask before calling the fetch tool |

## References

- Origin: IMP-088 — the `ask: [WebFetch, WebSearch]` rule overrode every in-chat `allow` grant (`ask > allow`), so per-domain approvals never stuck.
