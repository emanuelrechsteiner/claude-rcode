<!-- Status: ACTIVE
Last Updated: 2026-10-03
Purpose: decisions, rejected options, numbers, incidents, templates, public claims for the rcode-specialist skill
Source: repo docs/ADRs/plans/research/ledger (last line); cites = file:line, re-checked 2026-10-03
-->
# Docs, decisions, evidence — reference
Legend: ADRn=docs/adr/000n-*.md; RE/x=docs/archive/rules-evidence/x.md; EC/nn=research/ecc-compare/nn-*.md; ER=research/ecc-vs-rcode.md
PB=research/permission-bands-proposal.md; ID=plans/instruction-diet-findings-2026-09-29.md; LG=global-observation/improvement-ledger.json
docs/: MR=model-era-review-2026-09-27, RP=RETENTION-POLICY, WR=WORKING-IN-THIS-REPO (.md); VP=plans/vault-by-design-2026-09-25.md (local)
## 1 Glossary (CONTEXT.md:9-35)
Term|Meaning
---|---
Workshop/live install|workshop = working copy outside ~/.claude (edit, commit); live = ~/.claude (claude-deploy only)
Deploy|claude-deploy config, cockpit or all; fast-forward only; refuses a dirty workshop
Rails|rcode/rules/*.md + stack rules copied per project, versioned by rcode/VERSION; commands/skills/stages are global
Phase/Stage/Step|Phase = milestone 1..N (0 = pre-R.Code); Stage = Plan/Design/Develop/Test/Launch; Step = 0-9 of /issue
Work unit/tracker|#N (tracker github: issues) or P-NNN (tracker plan: BRAINSTORM.md); .rcode/config.json; issue = GitHub only
Check trio|type/build, test, lint; defined in the project CLAUDE.md under "Mandatory Pre-Commit"
R.Code for Claude Code|public name: full in titles/first mention, then "R.Code"; never "Claude R.Code" (legal page, 2026-09-26)
English-only|all framework, Cockpit and site artifacts; German only as input aliases (AGENTENWAHL:), private `*.local.*`
IMP/Ledger|IMP-NNN = numbered improvement tracked in LG; not every rework has one (ADR2)
## 2 Two locations + acceptance (WR)
- pwd first: workshop = edit/test/commit; ~/.claude = live, never by hand: live at once, next deploy aborts (:13-50)
- Self-reference: rules/hooks/skills/settings load at process start, so say "passes direct invocation", never "works" (:54-72)
- /clear is NOT enough (no new process): sign-off = new terminal (:252-257); double CLAUDE.md load: claudeMdExcludes (:27-39)
- Self-check: hooks via stdin JSON (pass AND block case), run-all-tests.sh, jq . settings.json, vault.sh check (:80-160)
- Acceptance form (:231-247): "## Acceptance on the running Claude Code"; Prerequisite: claude-deploy + NEW session;
  numbered `<action> -> expected: <observable result>`; "If step N fails: ..."; `Rollback: cd ~/.claude && git reset --hard <commit>`
- Side-findings: ledger as proposed, never built in-session (:283, IMP-148)
## 3 ADRs (docs/adr/, immutable; change of mind = new ADR)
ADR|Date|Decision|Consequence
---|---|---|---
1 Serena|2026-08-05|Serena writes pass a fail-closed gate reusing native checkers|new tools need gate contract+test; IMP-130
2 R.Code|2026-09-23|One entrance /team-lead; Stages = global playbooks; tracker github or plan|Stage logic once; 5 alias doors stay
3 Vault|2026-09-25|No real name/path/id in versioned bytes: vault, HMAC tokens, 3 gates|ledger shows tokens; vault unbacked; no floor
4 Audit|2026-09-27|Count+skip lone-surrogate lines; ABORT(16) above 1% (corpus and day)|skipped write event is lost, reported; IMP-223
5 Rebrand|2026-10-01|Rebrand scan skips five chronicle files (REBRAND_CARVEOUT)|new old-name mention there unreported; 6th = new ADR
## 4 Decisions (rows are REJECTED unless marked DONE)
Item|Why|Source
---|---|---
Serena adapter (IMP-104)|fail-open checkers; reversed by ADR1|ADR1:13-17
ADR2 alternatives|5 full team procedures (70% dup), merge=union log, GitHub-only tracker, never-commit upgrade|ADR2:46-63
jq -R fromjson?; history rewrite|corrupts 7/8,322 events, hides failures; red CI trains ignoring|ADR4:21-27; ADR5:23-24
Plain hash; vault encryption; hooksPath|reversible; same disk as projects; disables existing hooks|ADR3:50-54,92-96; VP:363-366
Bypass flag; per-tool execute_sql band|kill switch; 1,016 prompts in one session|PB:208,243-255
Floor-block of bare cat; curl ask|9 false blocks; 24 reflex overrides|RE/tool-discipline:22; RE/agency-bands:20
ECC adopt: DONE|IMP-239 path guard, 240 no-verify block, 241 RED/GREEN+review, 242 runner+CI, 243 deploy gate|LG:4945-5075; ER:68-79
ECC adopt: DONE|IMP-244 config audit, 245 14 skills (skill-comply rejected), 246 brief contract; accepted 2026-10-01|LG:5077-5150
ECC not adopted|rules/common (18,377 chars), 111 language rules, ~200 skills, profiles, instinct injection, evolve/promote|ER:26,81
ECC not adopted|AgentShield unattended/--fix, epic-* tracking, plan-orchestrate, dmux, GAN loop, CI matrix|ER:81
## 5 Retention (RP; DRAFT, unapproved, no deletion automation until approved, :9-14)
Class keep -> then (:39-48): transcripts 12 mo -> manual review, delete or encrypted offline; chat-archives 6 mo (decided :129-133)
signals 30 d (auto); metrics/agency/guard logs 12 mo; historical-signals, plans/ indefinite; file-history 90 d; logbook 12 mo
Corpus 2026-08-22 (:25-33): projects 716 MB/102 dirs, chat-archives 818 MB/445 files, global-observation 913 MB, rest <=1 MB
## 6 Model era (MR; sources fetched 2026-09-27, IMP-220)
$/MTok in/out/hit (window 1M, Haiku 200K): Haiku 4.5 1/5/.10; Sonnet 5 2/10/.20; Opus 5.5 4/20/.20; Fable 5.1 10/50/.25; 1:2:4:10 (:36)
Cache (:77-88): 5-min TTL; write 1.25x (5m), 2x (1h); read 0.1x = <=10% of base (Opus 5.5 .05x, Fable .025x); no >200K premium
MAX_THINKING_TOKENS=30000 inert on Sonnet 5/Opus 5.5/Fable 5.1 (adaptive), acts only on Haiku 4.5; real control = effortLevel (:54-61)
Auto-compact 90 = ~90% of ~967K window = ~870K (87% of 1M; derived, :68-71); CLAUDE.md:66 still says 92 -> OPEN (ID:39)
Opus 5.5 < 4.8 ($4/$20 vs $5/$25); 4.7+ tokenizer +30% tokens; Sonnet 5 stays default vs vendor "Opus 5.5" (OPEN, :38-50)
## 7 Rule incidents (RE/x, 20 files; none exist for code-quality, documentation, identity)
agency-bands: unasked gh auth switch (IMP-163), bulk-backend data leak (IMP-152); agents-as-users: YC red-team hacked 7/16 agents
api-cost: 5 toggles/30 calls = ~10x cost; cloud-cli: env rm hits all envs; link --yes wrong team; context-eng: dumb zone (IMP-080)
docs-first: stale cache, "Opus 5 doesn't exist" (IMP-153); domain-docs: correction repeated 2-3x; foundation: wording only (IMP-234)
fail-loud: unescalated repeats x8-20 (IMP-164); mcp-tool-usage: Serena skipped 10 hooks (IMP-130); parallel: retracted metric (IMP-114)
planning-doc: 4.4M chars/229 edits (IMP-036); release-cli: 4 failed deploys ~12 min; security: "Sensitive" vars skipped by env pull
recommend-on-ask: bare options, 2-3 round trips (IMP-053); slop: false "fixed" 13x/7 days (IMP-160); hunter found 39 (IMP-167)
testing-quality: exfil fix "done" on a counter (IMP-158); tool-discipline: 57 cat fails; gate passed 57/60 general-purpose (IMP-213)
web-research: ask[] overrode allows (IMP-088); workflow-git: rule broken 17/17 (IMP-121)
## 8 Templates (24 files in templates/; legacy bootstrap/ x8 + commands/ x5 see 10)
auftragsbrief: Location, Symptom, Cause, Measurement, Acceptance; + Not-part-of-task, verbatim quote, 6-point completion contract
imp-submission: H2 anchors Problem Class, Symptom, Measurement / Evidence, Proposed Change, Risk / Band, Rollback (+Local IMP ID opt.)
command-contract: `<!-- controller-contract:v1 -->` marker or `exempt="<reason>"`, model pin; serena_config: registration + blocks A, B, C
env.local.sh: CLAUDE_BAUHOF_ROOT (mandatory), CLAUDE_LOGBOOK_NOTION_PAGE_ID (daily-docs, weekly-improve), 6 optional; set env wins, none = fail loud
5 `*.local` overlays: skeletons; identity needs name, email, path patterns; automode-environment.json: autoMode.environment, live-only
## 9 Public claims to keep true: claim (anchor) | known tension
"172 improvements implemented" (README:33) | LG has 191 status:implemented lines (Grep 2026-10-03); public ledger ships empty
Counts 21/22/51/12/42/3 rules/commands/skills/agents/hooks/routines (README:164-171) | workshop Glob: 21/22/68/12/44/3 (68 = 67 + host skill rcode-specialist)
"28 suites, 1,100+ assertions" (README:173) | workshop has 38 suites (WR:105); 1,139 cases counted for 33 (ER:25)
"all green before every release" (README:177) | IMP-243 deploy gate + CI exist; publish docs/scripts never run it (Grep)
"no language model in the gate" (README:39) | gateguard note-only, config-protection asks, not all exit 2 (ER:21)
"Twelve agents" (README:44) | 12 in agents/; lock usage unmeasured (RE/parallel-by-default:16)
"0 real values in any tracked file" (site/vault:65) | free-text gap; bypassable hygiene gate (ADR3:133-142)
## 10 Cross-document inconsistencies (more: ID A1-A10 rule vs hook, B1-B14 rule vs rule, C1-C7 stale cites)
Topic|Conflict (anchors)
---|---
Evidence files|20 on disk (18 rules + cloud + release) vs 21 claimed (EC/06:155); headers dated 09-24 x16, 09-27 x2, 09-29 x2; bodies touched 09-29 in 18 of 20 (RE/agency-bands:3 shows only a 09-24 header)
Case counts|gate suite 169 (RE/agency-bands:116) vs 147 (ER:63) vs 73 (was WR:109, fixed); serena gate 35 vs 37 (serena template:121,243)
92 vs 90|CLAUDE.md:66 "92% is a process failure" vs context-engineering:3,19 margin 90 (92 = stock); open (ID:39)
Ack token|rule+CLAUDE.md: data-stripped sha256; excessive-agency-gate.sh:74 same, :112-125 (IMP-119) signs full command, :541 prints it
Legacy skeletons|templates/commands/*: lack the contract block command-contract.template:10 claims; old pins; retired agents (meta.md:4,11)
Naming|"Claude R.Code" remains in CONTRIBUTING.md:3, install.sh:2,3,31,393,413,421,709, install.ps1:1,23,117, MIGRATION.md:5,24 (CHANGELOG.md:115 is history)
Cockpit|README:74 "ten entries (eight hooks, statusLine, subagentStatusLine)" vs CLAUDE.md:16 "7 hook entries + the status line"
Sources read: dossier 13, CONTEXT, WR, ADR1-5, MR, RP, ID, ER, LG, README, templates; Not verified: suite results, case/public counts
