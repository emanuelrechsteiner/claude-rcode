<!--
Status: ACTIVE
Last Updated: 2026-10-03
Purpose: Ledger mechanics, themes, OPEN backlog, contradictions, R.Code entries (per-entry lines: ledger-index.md)
Source: global-observation/improvement-ledger.json v1.5.0 (2026-10-01), scripts/ledger-append-proposed.sh header -->
# Improvement ledger: mechanics, themes, open work
## Mechanics
- 231 ids = 001..246 minus 15 absent (014-018, 026-032, 073, 074, 142; v1.5.0 cites 073/074). Entries live in ~33 named top-level collections (proposals append to `weeklyImproveProposals`); 001-007, 037 also keyed in `activeImprovements`; last occurrence per id wins.
- Entry: id, status, riskLevel (low..critical), category, proposedAt, implementedAt (null if open), source, sourceProposal (dedup `<proposal>#<finding>`), evidence, notes, filesModified, verification{kpi,baseline,target,measured,measuredAt}.
- Statuses declared: proposed, approved, in_progress, implemented, tested, rolled_back, deprecated; UNDECLARED but used: `regressed` (094 only), `in-progress` (metrics key, 0). Categories declared (7): orchestration, compliance, integrity, efficiency, safety, automation, context; 41 undeclared values in use.
- Verification rule (IMP-075, 2026-07-03): `implemented` needs a non-empty `measured`; coverage 122/190 (2026-10-01). IMP-113 (2026-08-01): 67 measured-less = 54 legacy (pre-07-03) + 13 violations; no mass backfill (invented values = the defect).
- Trust boundary: ledger-append-proposed.sh (IMP-112, 2026-08-01) writes only `proposed` (dedup on sourceProposal), never promotes or applies; vault-gated (219); a human sets implemented. IMP-188 (2026-09-27): recomputes header counters + `metrics` after every write; `--recompute-only [--dry-run]` after hand edits, `--check` exits 1 on drift (not hooked); counters had drifted 3x (097, 2026-08-24, 2026-09-27).
- Continuity (IMP-074): read the ledger before new work; an improvement is implemented ONLY once its entry exists - record immediately. Next version 1.6.0.
- Versions: v1.0.0 2025-08-31; v1.1.0 IMP-001..007; v1.2.0 2026-04-20 009..013; v1.3.0 2026-04-20 019..025 (retrofitted by 074); v1.4.0 2026-06-09 040/041/044/045/046; v1.5.0 2026-07-03 backfill 047..069 + computed counters.
- Counts (metrics 2026-10-01): implemented 190, proposed 37, deprecated 3 (064, 183, 186), regressed 1 (094), in-progress 0 = 231. Part 1 (001-129, 115 ids): 111/2/1/1; part 2 (130-246, 116 ids): 79 impl, 35 prop, 2 depr.
## Themes
1. Gates/security (040-041, 076, 102-108, 119, 130-132, 157, 163, 193, 209): command-position classifier, op-bound ACK, MCP ask layer; gate suite 28 (076) -> 90 (106) -> 142 (157) -> 169 (209).
2. Observation loop + alarm economy (009, 075, 110-113, 135-141, 164, 188, 210): data silently dead repeatedly (zcat read 7/7 shards as 0; routines dead 20 days from 2026-08-02; alarm repeated 255x); 164: escalate repeats.
3. Read-before-edit/tool discipline (021, 033-035, 093, 096, 157): 89 "not read" errors, 246 Bash reads; 034 block softened to advisory (157).
4. Orchestration (055, 070, 114, 139, 159, 199, 212-213): lock registry (3,212/3,212 releases freed 0 locks, 114); general-purpose 43.5% of dispatches (139) -> rationale gate (159, 213); null model 29.5% -> 5.2% (212).
5. Context/cost (217-218, 234-238): always-loaded text 280.6k -> 165.3k (217) -> 148.9k (218) -> 181.8k -> 147.2k chars (234).
6. Deploy + routines (084, 127, 147, 189-192, 198, 216, 242-243): runner passed SKILL.md after -p (39 failed runs, 189); watchdog 1,515/1,515 false abnormal (216); deploy gate = clean main + suites (243).
7. Identity/privacy (020, 067, 152, 158, 219): incident 2026-08-03 -> bulk-run manifest gate; repo pseudonymized, 326 findings -> 0 over 390 files (219).
8. Chat-analysis rules (143-168): rendered proof (143), same-turn persistence (144), escalation queue (145), brief template (161); Class B 165-187 mostly unbuilt.
9. R.Code/controller-first: see the R.Code section below.
## OPEN backlog (37 proposed)
| id | what is open | dependency / owner decision |
|---|---|---|
| 042, 043 | product-repo refactors (route monoliths, chatStore), since 2026-06-08 | product repos, not config |
| 135 | routines: launchd + live ok-run; manual ok-run 2026-09-09 exists (189) | owner closes status |
| 136 | real defect = repo-global trailing intent attribution; partial fix 16/16 stays | name mechanism first |
| 155, 181 | MCP connector diet (293.6k tokens, 29.4%) + context diet | owner disables connectors |
| 165-168, 170-180, 184, 185, 187 | 18 Class-B findings (2026-08-24), unbuilt; 176 needs 161 | human triage |
| 182 | probable duplicate of 149 | owner: deprecate? |
| 208 | move agents/archived-replaced-by-skills/ out of agents/ (2 name collisions); update CLAUDE.md, HARNESS.md | risk high |
| 210 | staleness alarm repeated 255x (DAYS_STALE=17) | investigate |
| 211 | weekly-improve blocked by meta-observer disable-model-invocation | owner chose split 2026-09-27; agent edit denied (Self-Modification); needs interactive session |
| 228, 230, 232 | logbook-count ABORT design; rotate-signals 7 follow-ups; watchdog 3 residuals | human design |
| 231 | 3 inert deny rules warn each headless start | owner y/n + gate regression |
| 233 | default model, MAX_THINKING_TOKENS=30000, 90 vs 92% | owner decision |
| 235-237 | 31 rule disagreements; budget guard (margin 2.8k); demote 3 rules (~6.4k chars) | owner y/n; 237 shifts load timing |
| 238 | condense rcode/rules (24,988 chars) | VERSION bump + /rcode-upgrade per project |
Implemented with open defect (metrics list is []): 084 restore drill PENDING; 089/090 note-only; 104 Serena unpinned; 107 tag mismatch; 109 graphify unproven; 122 remote creation; 130/131 rename proof; 134 scrub-check; 158 no deterministic check; 161 phase-team link; 162b repeat-path hint; 163 kubectl; 164 routine side; 169/212/213 effect unmeasured; 193/209 `--location=user` stays AUTO; 214 rails unchecked; 215 deploy + per-project upgrade; 242 CI not run; 244 6 WARN untriaged.
## Contradictions / status errors
- 094 regressed, yet metrics show implementedWithOpenDefect [] and successRate 100.0 (kept deliberately, 2026-08-24 note).
- 208 proposed (implementedAt null), but 197 (2026-09-09) cites it as done; FRAMEWORK-REFERENCE says done (per brief, unverified). 135 proposed though 189 shows a manual ok-run (2026-09-09).
- 136 dated 08-22 in entry, 08-23 in paper; fix missed the real defect (downgraded 08-24). 139: 43.5% (100/230) vs 45.9% (186/405), first figure 31% wrong. 162: 66 errors/37 sessions, but 200 finds 43 of 50 from the security-review pipeline (200 baseline said 44); 162 stays implemented.
- 098 note "honestly in-progress", status implemented, no implementedAt. 090/091/092/093/095/096/097/099/100 implemented with no `measured` (IMP-113 audit lists also 070-072; 075 predates them by 12 days).
- 041 claimed op-bound tokens; 119 found a signature collision, 108 env-prefixed ops never consumed a token. 087 logged a settings.local.json env as fix; 128 proved the file unread.
- 212/213 notes say unverified though measured exists; 217 target <150k missed (165.3k) yet implemented (218: 148.9k); 239-246 implementedAt 2026-10-01T15:50:00Z postdates metrics.computedAt 15:40:05Z that counts them.
- Stale text: 055/057 notes; 065 dates v1.4.0 06-20 vs 06-09; 013 proposed in v1.2.0 history.
## R.Code entries
- 085 (2026-07-03): rcode/VERSION + framework_version stamp + upgrade command (3-way diff, per-file y/n). Commands carried the pre-rebrand name until 2026-08-06.
- 089-092 (07-15): contract lint 16/16 (089), mutation gate (090), one Controller spec (091), Fable pin on 16 commands (092). 089/090 note-only; 090/091 no `measured`; pin misses the free-text main loop.
- 099 (07-15) schema minLength after 2/2 placeholder give-ups; 100 (07-15) verify-the-verifier (A/B checkout divergence, not hallucination); 101 (07-16) /team-lead, lint 17/17: a hook cannot force a controller step.
- 107 (07-26) public docs, scrub 246 files, tag mismatch open; 116 (08-01) compliance log, 8,550 lines all mode=note; 120 (08-01) 5 phase-team commands installed, yet 0 calls in 471 transcripts (215).
- 150 (08-23): 88 issues decomposed, /issue 0x vs /team-lead 20x -> issue discipline folded into team-lead. 161 (08-24) + 246 (10-01): 5-field brief template + completion contract; phase-team commands lack the link. 169 (09-23): env-key preflight (7 of 12 issues blocked), effect unmeasured.
- 214 (09-21): rcode/VERSION 07-03 -> 08-06, 5 projects wrongly "equal". 215 (09-23): ADR 0002, one entrance /team-lead (67x vs 0), 24 defects, lint 22/22, project rails not upgraded. 238 (open): condense rails. 241 (10-01): RED/GREEN + lead-spawned review per unit, prose-enforced.
Sources read: dossiers 05/06, ledger meta block, writer-script header; id/status/date of all 231 grep-checked in the real ledger, ~30 entries read in full; Not verified: 122/190 and --check not recomputed (no shell), FRAMEWORK-REFERENCE, 041/087/195/212/213/217 details (dossier-only).
