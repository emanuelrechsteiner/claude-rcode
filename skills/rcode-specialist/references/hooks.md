<!--
Status: ACTIVE
Last Updated: 2026-10-03
Purpose: Dense hook reference for rcode-specialist: registration, mechanisms, bypass tokens, invariants, mismatches, limits.
Source: workshop settings.json, hooks/*.sh, hooks/lib/*, rules/agency-bands.md, 2 internal dossiers; anchors re-read 2026-10-03. -->
# Hooks — reference
Legend: S:n=settings.json line (group hook k = first+4(k-1)); h/=hooks/; GO/=~/.claude/global-observation/; AB:=rules/agency-bands.md
x=exit2 block k=ask d=deny c=ctx JSON n=NOTE o=info; O/C=fail open/closed; +=see §2; T:x=h/tests/x-regression.sh; tokens drop CLAUDE_
## 1 Registration (no timeout key in S:48-430; all hooks of one event run in PARALLEL, S order = list order only) (docs summary, re-verify)
|event matcher (S line)|first S|hooks code:effect+fail|model sees (docs summary, re-verify)|
|---|---|---|---|
|SessionStart startup (51), other sources (88)|55|echo SX GC SG GR RL SF CE: oO; (88) CE only|stdout visible; echo prints literal $(date)|
|PreToolUse Bash (99)|103|GU:xO GP:xO+ GB:xO+ GS:xO GE:oO EA:xO WF:kO CM:nO RA:nO|x: stderr to model; k: user prompt; n [INVISIBLE]|
|PreToolUse WebFetch\|WebSearch (140); mcp__.* (166)|144; 170|WF:kO; MA:kO WF:kO|k: user prompt; MA NOTE [INVISIBLE]|
|PreToolUse Task\|Agent (149)|153|DC:oO DS:kO CE|k: user prompt; DS NOTE [INVISIBLE]|
|PreToolUse mcp__serena__.* \| mcp__plugin_serena_serena__.* (179)|183|SW:dC (also x, k)|deny reason to model|
|PreToolUse Write\|Edit (188)|192|PL:dO GG:cO AR:xO CP:kO FP:xO GP:xO+ SA:xO+ VW:xO CM:nO echo,echo|x/c to model; echo, n [INVISIBLE]|
|PreToolUse MultiEdit (237)|241|GP VW only (PL GG AR CP FP SA CM never run); docs list no MultiEdit tool|docs summary, re-verify|
|PostToolUse Edit\|Write (279)|283|AF:oO PV:xO OC:oO echo CE|PV stderr to model; echo [INVISIBLE]|
|PostToolUse serena (270); Read (322); TaskCreate/Update (304,313)|274; 326|SP:xO; TR:oO; Task*: CE only|SP stderr to model|
|Stop (331)|336|SE:oO SB:cO SC:oO HW:oO CD(scripts/) CE BA:oO|SB c to model (continues turn); plain stdout [INVISIBLE?] see §6|
|SubagentStop (365)|370|LR:oO WD:oO CF:oO echo CE|stdout [INVISIBLE?] see §6; WD stderr [INVISIBLE]|
|UserPromptSubmit (412); PostToolUseFailure Bash (391); Notification (402)|417/397/407|PA CG BA:cO; PF NT:oO|c to model; PF [INVISIBLE]|
|PreToolUse Bash\|Grep (249); Read\|Glob (258)|254; 263|graphify hook-guard (external binary ~/.local/bin/graphify; not read)|not checked|
## 2 Hooks (h/<name>.sh; bypass: see §3; gpc,gbc,ncs=h/lib/governing-path-classify.py,git-bypass-classify.py,normalize-command.sh)
|code name: decision (anchors)|log/suite (a=both, a/b, -=none)|
|---|---|
|GU guard-unsafe: rm -rf abs/~ :203, mkfs/dd :248-253, curl -o :392, nc :497 block; curl/wget POST :320 NOTE|guard-overrides/gate|
|EA excessive-agency-gate: ESCALATE list :176-407 (AB:83-89), else AUTO :419; SOFT-ACK never emitted :75|excessive-agency/gate|
|MA mcp-agency-gate: ask: suffix list :33, SQL write/empty :49, 'prod' deploy :72; read SQL explicit allow :59|excessive-agency/-|
|WF web-fetch-safety-gate: ask: URL flags :71-170 (IP, punycode, TLD, shortener, .exe, userinfo); curl-pipe-shell :206|web-fetch-gate|
|SA security-audit: secret regexes on new_string/content :64-107; missing lib blocks :43; edits[] unread :13|security-audit|
|VW vault-write-gate: content -> vault.sh :222 (marked repos :158); rc2 blocks :234; infra error opens :251|vault-gate/vault-write-gate|
|FP file-protection: blocks .env/.env.* (not .env.example) :21, .aws/credentials :27, .ssh/id_* :33, .gnupg/ :39, /secrets/ :45; CP config-protection: asks on linter cfg :77|-/serena-gate|
|AR pretool-auto-read: unread file (/tmp/claude-reads-<sid>, exact path :32) blocks :80; GG gateguard: ctx note :97|signals/read-tracking|
|SW serena-write-gate: Serena write -> Edit payload :205 -> PL FP SA VW CP :216; unknown tool deny :176|serena-gate-log.jsonl/serena-gate|
|GP governing-path-guard: live-install governed write (gpc:56-63; Bash :159-205); parsefail+raw hit closed gpc:227|governing-path-guard|
|GB git-bypass-guard: --no-verify, commit -n, hooksPath, HUSKY=0 incl. bash -c/eval/pipe-to-shell (gbc:122-134; env/config/git checks gbc:44-96); degraded asks :64|git-bypass-guard|
|GS git-state-check: only cmd starting git :19; lock >300s deleted :43; conflicts/markers block commit/push/rebase :69|-/git-state-check|
|DS dispatch-specialist-check: general-purpose needs AGENTENWAHL naming agent :157; 3rd grant asks :227; retry ok :240|dispatch-specialist|
|PL parallel-lock-check: denies edit if locked by other agent; bind :56; no script=open :31; LR subagent-lock-release :27|-/parallel-lock|
|CM controller-first-mutation-gate: no control-agent run: note only :209 (S:5), enforce x2 :273; exempt paths :156|controller-first|
|CG controller-first-prompt-gate: flag :56, ctx :73; CF -subagent-flag: sets controller-ran for control-agent :29|controller-first|
|PA parallel-analyze-prompt: ctx :80, skip tokens :38; RA read-tool-preference-advisory: one NOTE/session :67-82|read-tool-advisory|
|DC dispatch-capture: row per dispatch :53; WD subagent-watchdog: status :136-141 (marker regex :121); BA background-agent-check :104|dispatch-capture.jsonl, subagent-stops.jsonl/background-watchdog (WD BA), controller-first (DC)|
|OC observation-capture: signals :94, queue :112, tracker :127; TR posttool-track-read :16|signals/observation-intent|
|SP serena-post-tool: feeds AF/OC/PV :67-76; AF auto-format: silent :61; PV post-edit-validate: EOF digit :33 exit 2|-/serena-gate|
|SB stop-batched-checks: line limit :94, lint, tsc/eslint/ruff :168 (GROUPS bug §6), ctx :225, 60 s limit :40|refactor-queue.jsonl/-|
|SE session-end-check: archive :17, reminders :53-429 (alarm helper :164-181); SC self-critique-log :50; HW session-handoff-write :134|session-metrics.jsonl/session-end-staleness|
|SX session-start-context :10-127; GC git-identity-check, SG sandbox-guard :27, GR git-remote-check: warn|-/session-start-path-canon|
|RL routine-liveness-check :147; SF security-findings-check :51|-/routine-liveness, security-findings|
|PF postbash-failure-recovery :60; NT notification-tts :22; GE git-identity-enforce: no-op placeholder :37; LL line-limit-check: dead|PF /tmp/postbash-hook.log, NT notifications.jsonl/-|
## 3 Bypass tokens (env=hook process env: launch env/S:2-7, inline VAR=1 prefix does NOT reach hooks; cmd=grepped from command text)
|token (drop CLAUDE_)|scope|read from|notes|
|---|---|---|---|
|GUARD_OVERRIDE=1|GU, one Bash call: all chained segments pass (exit 0 :72)|cmd, must START the command string :41|logged :66; export form only warns :78; reflex use logged UNNECESSARY :63 (:58-65)|
|AGENCY_ACK_ONCE=<sha256>|EA|cmd, anywhere :487|sig=sha256(cmd minus token, data kept) :107-125; single-use /tmp file :482|
|GIT_BYPASS_ACK=<sha256>|GB|cmd :98|sig minus own token gbc:148; consumed GO/.git-bypass-consumed-<sid> :97; mismatch/replay x2|
|GOVERNING_WRITE_ACK=<sha256>|GP|env or raw input :79-80|Bash sig=cmd minus token :68; files: path+sha256(content) :70-73; consumed :82|
|CONTROLLER_ACK_ONCE=<sha256>|CM, enforce only (S:5 = note)|Bash cmd :234; Write/Edit env :238|sig data-stripped :116; single-use :240|
|CONFIG_PROTECT_OFF; VAULT_GATE_OFF; WEBFETCH_GATE_OFF|CP; VW; WF|env (CP:26; VW:50; WF:58)|VW logs bypass :199; CP, WF silent|
|PARALLEL_LOCK_OFF, DISPATCH_CHECK_OFF, GATEGUARD_OFF, READ_ADVISORY_OFF|PL DS GG RA|env :15,:116,:38,:53|DS logs allow-optout|
|GATE_TESTMODE=1; WEBFETCH_GATE_TESTMODE=1|EA GB CM exit 0 + own *-test.log; GP exit 0 + decision=testmode-exempt in its normal log; WF prints ASK|env (EA:60; GP:75; GB:82; CM:62; WF:247)|test-only|
|STOP_BATCH_OFF/FORCE=1; AUTO_HANDOFF=0; PARALLEL_AUTO_SUGGEST=0|SB HW PA (CG ignores)|env :24,37 :24 :17|PA :70 export: unreachable|
|NOREMOTE_CHECK_OFF=1; SESSION_NUDGE=0|GR; SX|env GR:24; SX:103|silent opt-outs|
## 4 Invariants when editing
|invariant (anchors)|
|---|
|Exit 2 + stderr blocks; JSON only with exit 0 (SW:38). Fail modes intended: SW :13, SA lib-missing :36, gpc:227 closed; VW DS MA WF open|
|strip_data has 3 identical copies: EA:87-102, ncs:58-73, CM:99-114; ncs falls back to the RAW command, never empty (:79-83)|
|Ack sig hashes the command WITH quoted data (EA:124, IMP-119), strips only its own token (:107), checks consumed before accept (:494)|
|GU: override only at command start (:41), self-check must not recurse (:58-65); curl -o: every target classified, blank = critical (:430-432; rationale :424-428)|
|WF loopback = flag, not early return (:124-158); jq-built log (:259). MA: empty SQL asks, read SQL needs explicit allow JSON (:50-67)|
|SW: unknown suffix denies (:176); hard blockers before CP ask (:211); no bypass var (:34); inspectors get synthesized Edit payload (:205)|
|Read tracker /tmp/claude-reads-<sid>.txt, exact path per line: AR:16,26 TR:15 GG:63 OC:128 SP:44; GG safe only while AR blocks|
|DS: retry marker logs every attempt, grant counter only grants (:192-219); roster from agents/*.md (:141). PL owner via bind (:56)|
|Keep identical: WD:121 = BA:128 (marker regex); CG:39-42 = PA:27-30. GP file sig has content hash (:70). Hooks need +x (SW:218)|
## 5 Rule vs hook mismatches
|rule file:line|hook file:line|mismatch|
|---|---|---|
|AB:78; AB:36-40|EA:75,449; GU:136; MA:76|EA never emits SOFT-ACK (only GU curl/wget/curl -X/scripted HTTP :320-329,464,486-489, MA preview); trunk commit/push, lint-edit unemitted|
|AB:93 (sig data-stripped, per PPID)|EA:124-125; :481|sig hashes quoted data (IMP-119); session_id first, PPID last|
|AB:70,44,88|GU:203|GU hard-blocks abs/home rm -rf outside temp; GUARD_OVERRIDE lifts GU only, EA still ESCALATEs (needs AGENCY_ACK_ONCE too, GUARD token first); EA ack path also reached by -fr/-r -f and env-prefixed rm (chain-probe-imp108.sh:136)|
|AB:88 (basename AUTO-PASS)|EA:354-360, 401-407|absolute /x/node_modules ESCALATEs at :401 first; :354 set wider than AB; :404 redundant|
|AB:42 (force push)|S:41; GU:510; GS:103|adjacent-text match: -f, trailing --force, --force-with-lease unmatched (inferred); GU only warns|
|AB:45,116 (PROD, PR)|EA:199; MA:33,72|no vercel --prod arm; MA 'prod' substring mis-matches; PR/issue creation only behavioral|
|AB:128-131; agents-as-users.md:27; CLAUDE.md:40|SG:12,27; §3|YOLO_SANDBOX only silences a warning; YOLO only warns; 17 more tokens|
|tool-discipline.md:10,46|GG:5-35,81-107; DS:240-244|GG = non-blocking ctx note, not JSON deny; identical retry passes past 3rd-grant ask|
|fail-loud.md:35-58; security.md:14|SA:54-107; FP:21-48|no except:pass/empty-catch/ALLOWED detection; no filename block for *.pem/*.key on write; SA:55 blocks PEM private-key content only|
|AB:3|EA:16,537 (path; label-only :508); MA:4,39; skills/worktree-consolidate/SKILL.md:15,188|stale pointers to absent rules/autonomy-arbiter.md|
|mcp-tool-usage.md:36-37, :43-44; foundation.md|SX:111, :107-108; CG:65; CM:7-8|SX says Serena read-only (vs :36-37) and offers activate_project (vs :43-44); CG/CM cite missing Controller-First section/plan|
## 6 Known limits
|limit|
|---|
|(inferred) unseen: /bin/rm, command/env/xargs rm, bash -c '...' (GU:203, EA:150); rm -Rf matched by neither gate (GU:203, EA:323)|
|(inferred) sha printed on block (EA:541, GB:122, GP:98): not user-bound; 2 SHA tokens in one cmd unsatisfiable (EA:107, gbc:148, GP:68)|
|(docs summary, re-verify) hooks run in parallel: "runs first" comments (EA:6-8,23-26; GG:18-22), chain-probe-imp108.sh:57 assume order|
|GROUPS SB:168-170: bash special var (gids), loop iterates gid, tsc/eslint/ruff never run (lead-verified in replica, not on the live hook)|
|(inferred) native deny/ask match prefixes: git push origin main --force, -f skip S:41; sudo/dd/mkfs/nc denied S:21-30|
|(inferred) strip regex EA:89, ncs:60, CM:101 also matches <<<, $((1 << n)): later lines dropped; CM sig data-stripped :116|
|Stop/SubagentStop plain stdout: dossier says visible, docs summary only SessionStart/UserPromptSubmit: SE SC BA echo may be [INVISIBLE]|
|Coverage: MultiEdit skips SA FP CP AR PL (S:237-247); SA reads new_string/content only (:13); GP misses rm/ln/dd/rsync/MCP (gpc:9-13)|
## 7 No regression suite: MA GG GE GC SG GR PA SB SC HW AF PV PF NT LL(dead); FP, CP only indirectly (serena-gate-regression.sh:143,161)
## 8 Observation pipeline
|producer|file (GO/)|consumer|
|---|---|---|
|OC; AR error rows :70; GE|signals.jsonl|SE counts, HW gate :72, SC :24, /meta-observe|
|SE per Stop :119, copy :17-43; SC :50|session-metrics, self-critique (.jsonl), chat-archives/|meta-observer, weekly-improve|
|DC :53; WD :147|dispatch-capture.jsonl; subagent-stops.jsonl|scripts/compute-daily-metrics.sh :194 and BA; BA only|
|nightly routine|archives/signals-*.gz, daily-metrics, nightly-obs-log (.jsonl)|SE, RL: only status error counted, SKILLs write fail|
|meta-observer SKILL.md:194|.last-run-ts|SE staleness >= 7 d :195|
|/meta-observe; ledger-append-proposed.sh|plans/meta-proposal-*.md; improvement-ledger.json (proposed only)|SE :395-427; human promotes|
|SE repeat >= 5 :221|ledger entry once per month (marker :233)|human|
|CM RA PA SB NT LL|log: controller-first, read-tool-advisory, refactor-needed; jsonl: parallel-prompts, refactor-queue, notifications|none|
Sources read: settings.json, hooks/**, agency-bands, dossiers; Not verified: CE cockpit-event, CD config-drift-check, graphify, test bodies
