<!--
Status: ACTIVE
Last Updated: 2026-10-03
Purpose: single backlog of defects, inconsistencies and open questions (2026-10-03 study) with verification status
Source: 13 study dossiers, plans/instruction-diet-findings-2026-09-29.md, research/ecc-vs-rcode.md s5; repo re-checks 2026-10-03 -->
# Open defects and questions — reference (2026-10-03)
Status: VL=verified-by-lead 2026-10-03 (row 21: script replica, not the live hook); IN=inferred; UN=unverified.
DV=dossier-verified; re-read in repo 10-03: rows 4,5,8,10,11,15,20,22,25,29,31,33,37,48,51.
Tracked: IMP-nnn; 235:A1=item A1 of IMP-235 (file IDF); listed=IDs in finding; -=untracked. Size S/M/L=effort.
Paths: h/=hooks/ s/=scripts/ ledger=global-observation/improvement-ledger.json IDF=plans/instruction-diet-findings-2026-09-29.md
T70=publish-transforms.d/70-neutralize-private-layer-prose.sh
Closed since study, no rows: ecc s5 #1,#2,#6,#7,#8 = IMP-239,240,241,242+243,244. Open: #3 row 8, #4 U4, #5 row 13.
#|file:line|finding|status|tracked|size
---|---|---|---|---|---
**publish/vault**|||||
1|T70:95-97|silent no-op: marker regex (2 German words) matches 0 in publish.sh, rcode/README.md since 09-26 English pass|VL|-|M
2|T70:212|PUBLISH_DISABLED=0->1 normalization sits inside the skipped branch: a committed =0 is not forced back to 1|VL|-|S
3|s/publish.sh:34-45; rcode/README.md:167-168|overlay prose that T70 should replace remains in both files|VL|-|S
4|s/scrub-check.sh:326,330|vault.sh stderr dropped and exit ignored in PII pass: a crash reads clean; due before next publish|DV|-|S
5|publish-manifest.txt:19,20,28|audit-reports/, work/, ops/ unanchored: rsync drops same-named nested dirs, as vault/ did|DV|-|S
6|ops/decisions/2026-08-13-*.md:100|history scrub never run (v1.0.1 shipped private-repo URL x3, 8761f9a); decision still open|DV|-|L
7|docs/adr/0003-*.md:126-142|accepted residuals: paraphrase gap, unencrypted vault, fail-open gate, cherry-pick skips hooks|DV|ADR 0003|L
**hooks-gates**|||||
8|rules/tool-discipline.md:10|rule: first touch JSON-denies; h/gateguard.sh:2 is a non-blocking note since IMP-044/045|DV|235:A1|S
9|rules/slop-prevention.md:63|names a PreToolUse type-error edit gate; none exists, only the Stop hook (broken, row 21)|DV|235:A2|M
10|rules/fail-loud.md:35|security-audit.sh has no except:pass check or ALLOWED marker; *.pem/*.key unblocked (security.md:14)|DV|235:A3|M
11|rules/agents-as-users.md:27|rule: SessionStart blocks YOLO; h/sandbox-guard.sh:34 only warns|DV|235:A4|S
12|rules/agency-bands.md:93|rule: sha of data-stripped command; h/excessive-agency-gate.sh:112-125 (hash at :124-125) hashes it with quoted data|DV|235:A5|S
13|h/excessive-agency-gate.sh:540|ACK sha is printed to the model; nothing mechanical ties it to a human y/n|DV|-|L
14|h/excessive-agency-gate.sh:354|basename AUTO-PASS is dead code; h/guard-unsafe.sh:203 already blocks absolute non-temp rm -rf|DV|235:A6|S
15|rules/agency-bands.md:114|rule: unparseable execute_sql asks; h/mcp-agency-gate.sh:46-67 asks only on an empty query|DV|235:A7|S
16|h/excessive-agency-gate.sh:75|bash gate emits no SOFT-ACK (trunk commit, push, lint edit); no vercel --prod or PR-create arm|DV|-|M
17|h/dispatch-specialist-check.sh:240|identical retry passes and counts as granted: "3rd grant always asks" is bypassable|DV|IMP-213|S
18|IDF:24-26|A8 planning-doc warn 80% vs 50%; A9 git-identity-enforce no-op placeholders; A10 security-findings-check|DV|235:A8-A10|S
19|h/guard-unsafe.sh:22|silent fail-open on missing jq/script; also mcp-agency-gate:22, file-protection:9, parallel-lock-check:31|DV|-|M
20|h/tests/|no suite: mcp-agency-gate, gateguard, config-protection, git-identity-enforce, sandbox-guard|DV|-|M
**hooks-lifecycle**|||||
21|h/stop-batched-checks.sh:168|GROUPS is bash-special: replica loop ran on [20] (gid); tsc/eslint/ruff per project never run, exit 0|VL|-|S
22|h/routine-liveness-check.sh:120|only status "error" alarms; routine SKILLs write ok/partial/fail, so fail is silent|DV|-|M
23|h/session-end-check.sh:164|repeat counter counts Stops (turns), not days: 3rd/5th escalation can fire in one session|IN|IMP-164,192|S
24|settings.json:5|controller-first stays note-only (log only, invisible); IMP-089/090 count as implemented|DV|IMP-089,090|L
25|h/tests/|no suite: stop-batched-checks, self-critique-log, session-handoff-write, git-remote-check, post-edit-validate|DV|-|M
**scripts/deploy/tests**|||||
26|s/audit-config.sh:62|lists theme as invalid while settings.json:500 sets it and deploy-to-live.sh:102 lists it as a runtime key|VL|-|S
27|repo grep|claude-deploy is defined in no file of the repo (grep over scripts/templates/docs: only references)|VL|-|M
28|s/audit-config.sh:111|audit flags TaskCreate/TaskUpdate invalid in agents/*.md; lint (:279) accepts Task|TaskCreate|TaskUpdate in commands/: overlapping vocabulary, unclear which is valid; lint :130 reads live agents, ignores --root|DV|-|S
29|s/parallel-claim.sh:171|stolen-expired lock record lacks session_id: bind later treats it as legacy and binds first-come|DV|-|S
30|s/deploy-to-live.sh:367|failed ff-only pull aborts (set -e) after checkout -- .: volatile plugin files not restored|IN|-|M
**R.Code workflow**|||||
31|rcode/stages/develop.md:43|RED/GREEN and fresh-context review are prose-enforced (no hook); first real wave is the test|DV|IMP-241|M
32|rcode/VERSION:1,13|5 shipped projects keep stamp 2026-07-03, read "behind" until /rcode-upgrade; restamp unconfirmed|DV|IMP-214,215|M
33|templates/command-contract.template:7,76|claims templates/commands carry the marker (0 matches) and pin fable-5 (real: fable-5-1)|DV|-|S
**ledger**|||||
34|ledger:3492|IMP-208 is proposed though FRAMEWORK-REFERENCE.md and CHANGELOG describe it done 2026-09-09|VL|IMP-208|S
35|ledger:865|metrics block says 0 open defects (implementedWithOpenDefect []) while IMP-094 is regressed|VL|IMP-094|S
36|ledger:1704|IMP-094 regressed: gate AUTO/SOFT-ACK activity never reaches signals.jsonl; no measured value|DV|IMP-094|M
37|ledger:868|coverage 122/190: 68 implemented lack a measured value; regressed/in-progress and many categories undeclared|DV|IMP-113|M
38|ledger:3553|IMP-211 weekly-improve blocked: meta-observer has model-invocation off; agent fix denied by classifier|DV|IMP-211|M
39|ledger (ids)|37 proposed open: 042,043,135,136,155,165-168,170-182,184,185,187,208(row 34),210,211,228,230-233,235-238|DV|listed|L
40|ledger (ids)|implemented, residual open in own notes: 050,063b,067,082,084,088,104,107,109,114,122|DV|listed|M
41|ledger (ids)|implemented, residual open in own notes: 130,131,134,158,161-164,169,193,209,212-215,242,244|DV|listed|M
41a|ledger (meta)|metadata quirks (grep-verified 10-03, detail in ledger.md): 239-246 implementedAt 15:50Z postdates counted metrics 15:40Z; v1.5.0 cites absent 073/074; 41 undeclared category values vs 7 declared; 098 lacks implementedAt|DV|-|S
**skills/agents**|||||
42|skills/fix-review/SKILL.md:5|allowed-tools omit commands the body runs (grep/find/rm); 6 skills incl. scope-check, meta-observer|DV|-|M
43|skills/*/SKILL.md:8-11|Memory-First step mandatory in 10 skills, none lists mcp__memory__*; do allowed-tools gate MCP? unknown|DV|-|M
44|skills/pattern-document/SKILL.md:48|create-* and pattern-document skills write into live ~/.claude, against the deploy rule|DV|-|M
45|agents/version-control-agent.md:33|bans local branch/commit in report-only (rules allow); version-control skill pushes main|DV|-|M
46|agents/documentation-agent.md:38,53,100|pre-fix procedure kept: ~/repos scan (:38), LOGBOOK_DIR (:53), hand-typed log line (:100); the Notion id lives in daily-docs/SKILL.md, not here|DV|-|M
**docs**|||||
47|IDF:32-33|trunk commit and PR creation: SOFT-ACK in agency-bands, forbidden/ESCALATE in workflow-git|DV|235:B1,B2|S
48|CLAUDE.md:66|'92% = failure' vs local 90% margin (context-engineering.md:21); MAX_THINKING_TOKENS acts on Haiku only|DV|235:B8|S
49|IDF:34-45|rule conflicts B3-B7, B9-B14: PR target, network posture, tool-discipline wording, bypass table, BRAINSTORM|DV|235:B3-B14|M
50|IDF:51-57|C1-C7: comments cite text that never existed or moved, e.g. autonomy-arbiter.md (excessive-agency-gate.sh:16)|DV|235:C1-C7|S
51|README.md:33,173,177|says 172 improvements (ledger: 190), 28 suites (38 exist), all green before release (publish.sh runs none)|DV|-|S
52|research/ecc-vs-rcode.md:26,85|always-loaded size: 148,930 (:85), 150,244 and 146.4k only in ledger IMP-236; 106,835 = derived 96,811+10,024 (:26) leaves ~42k unexplained|DV|IMP-236|M
## Questions only the owner can answer
#|question|anchor
---|---|---
Q1|Where is the claude-deploy wrapper defined (row 27)?|s/install-routine-timers.sh
Q2|Origin of the pre-rebrand name (no commit states it)?|rcode/VERSION:5
Q3|Were tags v1.1.0..v1.6.1 pushed? Per release: one-run reopen or hand-mirror?|s/publish.sh:372; 693ab73
Q4|Why did v1.6.1 need a retry, v1.2.0 a reopen with empty message?|50c3ebe..db37276; 04b4c36
Q5|Sibling repos (public mirror, cockpit, pre-rebrand clone, feat/phase-team-restructure, external registry): roles?|aac95b2; e5f00fb
Q6|Do other branches hold the 09-28 and 09-30 work (main-line export shows none)?|git log 09-28..09-30
Q7|Open checks: CI green after c81410c? launchd 09-10 run ok? row 32 restamp? GitGuardian alarm marked?|c81410c; 3cad614
## Unverified claims that need a live test
#|claim|anchor|test
---|---|---|---
U1|Hooks of one event run in parallel (docs); "runs FIRST" comments void; JSON merge unknown|h/gateguard.sh:18|2 sleeping hooks, conflicting JSON
U2|[INVISIBLE]: exit-0 hook output on Pre/PostToolUse never reaches the model|settings.json:228,295|hook prints a canary
U3|rm -Rf/-fr, command rm, /bin/rm, xargs, bash -c evade the rm floor and gate|h/guard-unsafe.sh:203; gate:323|gate-regression harness
U4|MultiEdit still exposed? Its group has only governing-path and vault gates; security-audit skips edits[]|settings.json:237|list tools; try it
U5|ask[] prefix match misses "git push -f" and trailing --force|settings.json:41|both forms in a sandbox repo
U6|Cockpit SessionStart group resume/clear/compact/fork fires after /clear|settings.json:88|run /clear; check session file
U7|Comma list in one Bash() allowed-tools pattern matches each entry|skills/import-fixer/SKILL.md:5|invoke skill; run listed command
U8|<<<word and $((1 << n)) open a fake heredoc: later lines escape classification|h/excessive-agency-gate.sh:89|feed such a command to the gate
Sources read: 13 study dossiers, instruction-diet-findings 2026-09-29, ecc-vs-rcode s5; Not verified: live hook runs, CI, tags, launchd
