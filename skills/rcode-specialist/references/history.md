<!--
Status: ACTIVE
Last Updated: 2026-10-03
Purpose: Dense anchored history of the framework 2026-01-22..2026-10-01 for the rcode-specialist skill.
Source: 407-commit export (>100 hashes grep-checked), 4 dossiers, CHANGELOG.md 2026-09-23 entry, ADR 0002, public/CHANGELOG.md. -->
# Framework history — reference
Hashes 7-char; fields split by "|"; why: "q"=quote (translated), (p)=paraphrase; IMP-n=ledger id; live install=~/.claude.
## 1 Eras: date|key hashes|built|why
- 2026-01-22..23|070f8e7 da3e960 756be7e|infra: hooks, skills, agents, manual|"60% reduction in preventable errors" (claimed)
- 2026-05-25..28|7857731 8446118 e8b14ed 99ca234|hook audit, Quality Trinity, locks, public refactor|3 hooks "silently-broken" (q)
- 2026-06-08..21|e66dfca 5e36c79 1d1d687 3e366f2|migrate/init, arbiter classifier, IMP-047..069|(p) beta feedback; gate rewritten
- 2026-07-03..16|246d6a8 73af3ab 8be723c 242eb25|measurement loop, rules diet, web gate, /team-lead|(p) weekly-improve ran blind
- 2026-07-17..08-05|fa8a444 81fb8e8 e5f00fb cdcd5e7|Serena gate, team commands, gather scripts|"outside the hook chain" (q, Serena)
- 2026-08-06..15|c6a742a 0eed451 01ac031 f912316|rebrand, publish pipeline, v1.0.0, publisher stop OPT-014|(p) rebrand reason unstated
- 2026-08-22..09-21|8d77498 70c4687 c165871 330c65b|transcript IMPs, gate fixes, watchdogs, model fix|(p) IMPs derive from transcripts
- 2026-09-23|ea28a4b daf8de4 5ace915|R.Code rework IMP-215; publish hardening|"the plan follows the practice" (q, directive)
- 2026-09-24..25|bfdc56b 41dba01 b6f4316 06e1fb1|instruction diet IMP-217/218; vault+gates IMP-219|(p) real names never in versioned files
- 2026-09-26..27|3cad614 3529ad5 053b374 c429b42|vault merge (PR #6), brand, English-only, v1.3.0-v1.6.1|(p) trademark-safe name
- 2026-09-29..10-01|980cc52 14e2fbf 7d61a10 c81410c 9ab4812|rules -24% IMP-234, guards IMP-239/240, CI (7d61a10), rebrand-scan fix (c81410c), ECC skills (9ab4812)|(p) leaner always-loaded rules
## 2 R.Code lineage (post-rebrand command names; pre-rebrand name: see MIGRATION.md)
- 4406002 2026-05-25: review.md renamed to pre-rebrand-name review ("Resolves shadowing of bundled /review"); name already in use
- 0cd3b7f 2026-05-27: origin, in a 148-file "preservation snapshot" (recovery point); no rationale; adds brainstorm decompose issue
- 0cd3b7f (cont.): phase-gate status-sync handoff lessons commands, scope-check + onboard skills, 12 templates, 3 rules
- 0e6e95f 2026-05-28: hooks starter hooks-config.json (commit-before-stop, /handoff nudge); installed by nobody (M5)
- e66dfca 2026-06-08: /rcode-migrate (492 lines, forward-only, y/n gate) + /simple-onboard (read-only); 641fcda registers (10->12 cmds)
- 1d1d687 2026-06-14: /rcode-init greenfield (418 lines; features:[] manifest); 4-dimension adversarial review, 7 findings
- 3e366f2 2026-06-21: /continue (IMP-068) + /autonomous-overnight (IMP-069) inside the IMP-047..069 batch commit
- 73af3ab 2026-07-03: rcode/VERSION stamp + /rcode-upgrade (143 lines); b0d6ea0 9aa642f 07-15: command-contract markers + lint
- 242eb25 2026-07-16: /team-lead (95 lines), manual entry since "a synchronous shell hook cannot create an LLM turn" (q)
- 81fb8e8 2026-08-01: plan/design/develop/test/launch-team (148-170 lines each, installed locally; the byte-identical dev-repo-branch source @87cecd5 is stated in e5f00fb, not here)
- e5f00fb 2026-08-01: phase-gate-check.sh, resume-state.sh, status-metrics.sh, backward-transitions rule, incident-response skill
- c6a742a 2026-08-06: rebrand step 1, 28 pure renames; 259e948 step 2, text sweep over 69 files; reason not stated
- 6b99228 2026-08-23: IMP-150 issue mapping before dispatch mandatory; worker follows /issue ("88 issues decomposed, 0x /issue", q)
- 330c65b 2026-09-21: IMP-212 model id fable-5-1 in 22 commands + explicit model param; e7eb35b IMP-214 VERSION -> 2026-08-06
- ea28a4b daf8de4 4356eec 2026-09-23: IMP-215: rcode-units.sh (github/plan), 5 stage playbooks, team commands -> aliases, ADR 0002
- befbd52 2026-09-26: per-wave task list mandatory in /team-lead + control-agent (696 sessions: 6 TaskCreated vs 63 dispatching)
- 0a257a5 2026-10-01: IMP-241 Develop RED/GREEN + lead-spawned fresh-context review (prose-enforced); 628fda8 IMP-246 completion contract
## 3 IMP-215 rework 2026-09-23 (ADR 0002 + CHANGELOG): defects M1-M24 -> fix
Evidence: 471 transcripts, 5 projects: /team-lead 67x, stage commands 0x; 39 acceptance fixes; A0-A15: 16 adjustments, see ADR 0002.
M1 gather scripts repo-relative `bash scripts/X.sh` -> `~/.claude/scripts/`; M2 nonexistent `/review` referenced -> `/rcode-review`
M3 zsh `$sha:path` modifier trap in /rcode-upgrade -> `${sha}`; M4 /lessons grep `fix:` 4 hits vs `^fix` 48 -> anchored
M5 orphan rcode/hooks/hooks-config.json -> archived; M6 nonexistent frontend-agent, stale "research-agent archived" -> roster
M7 Node/TS checks hard-coded in 5 commands -> project check trio; M8 /decompose no y/n gate, not idempotent -> gate + checks
M9 /issue step 8 committed on trunk -> unit branch; M10 /rcode-upgrade never committed, stamps rotted in 3/5 -> commit after 1 y/n
M11 "Phase" meant 3 things -> glossary Phase/Stage/Step/Work-unit/Tracker; M12 5 team commands ~70% duplicate -> aliases + playbooks
M13 two ADR standards, no CONTEXT.md -> two-tier ADRs + template; M14 GitHub mandatory (2/5 projects lack it) -> trackers github/plan
M15 2 version counters (workflow_version never moved) -> legacy + VERSION scope; M16 always-loaded backward rule -> rcode/stages/
M17 mechanical commands pinned to top model -> pin removed; M18 ~190 repo-relative refs in commands -> `~/.claude/<path>`
M19 /continue exempt marker + full preamble -> marker only; M20 lint blind spots (deny-terms only in commands/) -> C6-C9, wider scope
M21 agent-log.md worktree divergence -> single-writer, not merge=union; M22 side find: watchdog 1,494/1,494 stops abnormal -> 3 states
M23 /rcode-onboard advised `/issue N` -> `/team-lead`; M24 missing env keys blocked 7/12 units (proj-af832e, IMP-169) -> env preflight
## 4 Releases: version|date|content|published via (open/close = 1-line publish.sh toggle commits)|push/tag evidence; n/s=not shown
v1.0.0|2026-08-06|R.Code release; history regenerated (f9e70b2)|pipeline 0eed451 (run n/s)|01ac031 "release done" (q); push/tag n/s
v1.0.1|undated|deferred-to in 99ca234 (05-27), be7e270 (07-26), cited as shipped in 8761f9a (09-23); superseded by v1.1.0 restart|n/s|n/s
v1.1.0|2026-09-23|IMP-215 rework, hardened publish path; history restarted as 1 commit|b638db7/de2457b|local clone ec13aa6, msg "nothing pushed" (German)
v1.1.1|2026-09-24|cockpit showcase README; deploy dependency-sync fix (68b2257)|0e6da1c/1386c8f|local clone 629804e, msg "nothing pushed" (German)
v1.2.0|2026-09-25|v1.1.1 + instruction diet IMP-217/218|ecd6977/d0ab7b4 (blocked), 04b4c36/693ab73|c4f84bc local; push/tags left to user (q)
v1.3.0|2026-09-26|vault + gates IMP-219; public changelog (ed31b3d)|e4b68ef/8e90df5|n/s
v1.4.0|2026-09-26|name R.Code for Claude Code, website, demos, brand assets|0552d18/1e8414c|n/s
v1.4.1|2026-09-26|cockpit images + set-up path; subagentStatusLine stripped on publish|2e42627/0df8294|n/s
v1.5.0|2026-09-26|plain developer language default, per-wave task list, cockpit wave card|f4f5ee5/5ae2142|n/s
v1.6.0|2026-09-26|English throughout, self-improvement as headline feature|3157a64/b7f3c0d|n/s
v1.6.1|2026-09-27|maintenance fixes, model-era refresh|50c3ebe/7deb218, retry 9dbc47c/db37276|n/s; retry reason n/s
## 5 Reversals / defects found-then-fixed: wrong|found by|fix
- 3 hooks inert since creation (settings.json arg substitution unsupported); PostToolUse blind to failures|hook audit|7857731, 4f6dc6a
- API key pushed via settings.local.json|incident 2026-05-27|ba19b9b (pattern), a313057 (mandatory scan)
- rm -rf regex inverted: ALLOWED sensitive dotpaths|gate rewrite|5e36c79
- "every parallel dispatch approved explicitly" -> auto-dispatch for disjoint reversible work|policy|ce88989 -> 05ea135
- Serena outside hook chain; read-only fix reversed by write gate; plugin double-run since ~07-17|audit|fa8a444, cdcd5e7, a8745ef
- routines yaml "disabled" while task ran nightly; weekly-improve pointed at missing files|audit|3412226, 246d6a8
- public artifact F1-F5: blocked templates, silent installer skip, ps1 glob, dead link, wrong counts|audit|6479229 7f6e702 c11ca0e b511c63
- read-lock on CRITICAL floor: 9 false alarms in 8 sessions; writes to ~ passed|transcripts|70c4687
- 39 routine runs failed unnoticed after IMP-135 "fix" (prompt '---' read as option; dry-run blind)|09-09 improvement run|c165871
- subagents inherited caller model; gp-gate passed 57 of 60 on rationale presence, not content|measured 09-21|330c65b, 2ee9704
- VERSION stamp stuck at 2026-07-03 -> false "already current"|measured on 5 projects|e7eb35b
- publish gate ran scrub-check from defused staging copy; unanchored vault/ dropped scripts/vault/|counter-review; late|5ace915, fc5044c
## 6 Maintainer principles (one evidence hash each)
- Fail loud, state limits ("not verified" stated in commit bodies, German original): 46152cb
- Measure, then change; mandatory verification{kpi,baseline,target,measured}: 246d6a8
- Gate by reversibility, not mode (AUTO/SOFT-ACK/ESCALATE): 05ea135
- Human is the gate: ledger writer emits only status "proposed": 5754587
- Proof at the sink; a green suite alone is no proof: 05be557
- Two locations: edit in the workshop, live install gets deploys only: c1c02b4
- Plan follows practice: transcript evidence before design: daf8de4
- Hooks only nudge or deny later calls, never create turns: 242eb25
- Independent adversarial review before accepting big changes: 980cc52
- Real names only in a local vault, framework carries tokens: b6f4316
## 7 Not determinable from the repo
- No commits 2026-01-23..05-25 (author identity differs after); origin of the pre-rebrand name and the rebrand reason: stated nowhere.
- Sibling repos (public mirror, Cockpit, dev-repo branch @87cecd5, older clone): relation unclear; versions "1.0.0-1.0.2" (be7e270, 07-26)
  and "v1.2.0 (0505b29)" (e5f00fb, 08-01) predate the v1.0.0 restart of 2026-08-06; numbering not reconcilable from commits.
- Why v1.6.1 needed a retry (50c3ebe/7deb218 vs 9dbc47c/db37276); why 04b4c36 has no message; contents of ops/decisions notes, IMP-235..238.
- Whether any tag/push/release exists: v1.1.0/v1.1.1 msgs say "nothing pushed" (German); be7e270: old v1.0.0 tag hit an orphan, v1.0.1/1.0.2 untagged.
- 909ecbe (2026-08-22): a private project path was committed into settings.json and later made live-only by 0c954b4.
Sources read: dossiers 01-04, CHANGELOG.md L78-110, ADR 0002, public/CHANGELOG.md; Not verified: dossier numbers, M/A plan doc, tags
