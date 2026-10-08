<!--
Status: ACTIVE
Last Updated: 2026-10-03
Purpose: Dense anchored reference of the R.Code project workflow as implemented in the repo today.
Source: rcode/**; commands/*.md (R.Code set); skills/{rcode-onboard,scope-check,rcode-ios}; 4 scripts/*.sh; docs/adr/0002 -->
# R.Code workflow — reference
Anchor=@code:line. w,sc,cm=rcode/rules/rcode-{workflow,scope,commits}.md rm=rcode/README.md ver=rcode/VERSION adr=docs/adr/0002-*.md
bt,pl,ds,dv,ts,ln=rcode/stages/{backward-transitions,plan,design,develop,test,launch}.md ios=skills/rcode-ios/SKILL.md
tl,is,dc,pg,ss,co,ho,le,ri,mg,up,rv,so,ao=commands/{team-lead,issue,decompose,phase-gate,status-sync,continue,handoff,lessons,
rcode-init,rcode-migrate,rcode-upgrade,rcode-review,simple-onboard,autonomous-overnight}.md
U,M,G,R=scripts/{rcode-units,status-metrics,phase-gate-check,resume-state}.sh (run `bash ~/.claude/scripts/<name>.sh [dir]`)
## Glossary (binding): Phase=milestone 1..N (0=pre-R.Code baseline): label `phase-N`, tag `v0.N.0-<name>`, `/phase-gate <N>` @w:24
Stage=work mode of the lead (team-lead/main thread): Plan·Design·Develop·Test·Launch; `/team-lead`, aliases `/plan-team`.. @w:25
Step=one of `/issue`'s 10 steps (0-9). Work unit=`#N` (github)|`P-NNN` (plan)|local `#N`; "Issue"=GitHub issue only @w:26
Tracker=`github`|`plan` (config.json `tracker`). Check trio=type/build·test·lint, in `CLAUDE.md` `## Mandatory Pre-Commit` @w:28
Rails=files copied into projects (`rcode/rules/*.md`+stack rules), versioned by `rcode/VERSION`; commands/skills/stages global @w:30
## Entrance: `/team-lead "<directive>"`; `/plan-team`..`/launch-team`=same, Stage forced @w:34
Loop @tl:139: 1 Orient=`R`+`M`, config.json, PROJECT-STATUS "Active Phase", last 2 log entries, re-entry-brief, escalation-queue
 2 Stage 3 Playbook `rcode/stages/<stage>.md` 4 Bind units `#N`/`P-NNN`+branch `work/<date>-<slug>` 5 Dispatch+wave review 6 Exit @tl:161
Stage precedence: alias > open re-entry-brief `to_stage` > inferred @tl:163. Signals @tl:168: no docs/units/re-plan→Plan · UX/flows/design
 system→Design · implement/fix open units→Develop · validate Phase/RC/PR/coverage→Test · release/deploy/incident→Launch
Exit, rows only if condition holds @tl:234: work→log entry `**Agent:** team-lead` · state change→`ss` · ALL Phase units closed→`pg N`
 (never merely on exit) · ESCALATE→one y/n (auto-approval→`escalation-queue.md`) @tl:263
## Stages `rcode/stages/<stage>.md`; each: `--overnight`→`ao`; plan wrong→escalate to management, never silent re-plan @pl:48
1 Plan: planning-agent research-agent research project-planning project-bootstrap scope-check; backward: target only @pl:7
 modes /brainstorm·`dc`·`ri`·`mg`·`so`·/bootstrap·Mid-Life Replanning(no cmd); ends: validated plan/roadmap/units @pl:23
2 Design: ux-design ui-development ui-agent scroll-animation-patterns tailwindcss-v4-styling kokonutui-pro @ds:7
 human-testing visual-qa-agent; modes: core loop(no cmd), idle→log no-change; ends: validated specs; backward: 2→1 only @ds:20
3 Develop: backend-agent ui-agent testing-agent visual-qa-agent cleanup-agent version-control-agent import-fixer parallel-dispatch @dv:7
 modes: per unit `is` Worker|Standalone; ends: implement assigned units, no re-scope @dv:107 (modes @dv:20); backward: 3→2 (design), 3→1 @dv:100
4 Test: quality-review testing-agent code-reviewer-agent visual-qa-agent testing-suite human-testing validate-build fix-review @ts:7
 type-coverage; modes: Milestone/RC Validation (not the `pg` gate)|PR Review=`rv`; ends: go/no-go; backward: 4→3, 4→2, 4→1 @ts:23 (modes); ends @ts:49
5 Launch: version-control-agent worktree-consolidate validate-build dependency-audit documentation backend-agent @ln:7
 nextjs-debug react-perf-check research pattern-document memory-index testing-agent; backward: 5→4, 5→3 (prod incident) @ln:51
 modes: Ship|Run; owns semver, changelog, `gh release` (ESCALATE), never `v0.N.0-*`; ends: ship what Test validated @ln:58; version authority @ln:42; modes @ln:26
## Backward transitions; forward 1→5; class by jump distance, never motive @bt:20
Iteration N→N−1 SOFT-ACK: lead jumps itself, no y/n; logs reason+what target inherits; writes short re-entry brief @bt:25
 Circuit breaker: 3rd consecutive round of one loop (4→3→4→3→4)→NEXT jump is Drawing Board (ask management); `loop_count` @bt:32
Drawing Board N→<N−1 ESCALATE y/n, only if Iteration in N−1 cannot fix; futility proof, 4 elements @bt:41:
 1 finding in Stage N+evidence 2 why N−1 cannot fix (blocking constraint, Stage that set it) 3 target Stage X+mandate 4 invalidation list
Re-entry brief `.rcode/re-entry-brief.md` (every jump): `from_stage` `to_stage` `class: drawing-board|iteration` `loop_count` @bt:69
 `date` `authorized_by: lead|user-y/n`; sections Finding, Futility Proof (drawing-board only), Change Mandate, Invalidation List
Invalidation @bt:97: skipped-Stage artifacts are suspect, not discarded; re-verified by own Stage's checks next forward pass; not `pg`
## `/issue <unit>` Steps 0-9 @is:42. Worker (lead-dispatched, ONE unit): only 0,1,3,4.1-4.3,5; never writes status/BRAINSTORM/log @is:65
|Step|Action|S/W|
|-|-|-|
|0|Readiness: CONVENTIONS/ARCHITECTURE (absent=finding), PROJECT-STATUS, predecessors closed, active Phase, env preflight @is:115|S+W|
|1|Scope boundary: state "I WILL implement:" / "I will NOT implement:" @is:153|S+W|
|2|Branch from trunk: `<type>/issue-<N>-<desc>` or `<type>/p-<NNN>-<desc>` @is:202|S|
|3|Implement per CONVENTIONS/ARCHITECTURE @is:228|S+W|
|4|Tests (RED-first, mandatory for bug fixes); check trio green; 4.4 fresh-context review @is:270|S+W; 4.4 S|
|5|Commit specific files; W: onto the lead's branch, no branch/push/PR @is:315|S+W|
|6-7|PR: push (github+remote, SOFT-ACK), `gh pr create` "[Phase N] <Title> - closes #<N>"; 7 `gh pr checks` @is:352|S|
|8-9|Status sync on unit branch, never trunk: PROJECT-STATUS, BRAINSTORM, START_HERE, log `**Last step:** 8`; 9 `/clear` @is:444|S|
Worker report-back verbatim @is:95: `Unit: <unit-id>` `Files changed: <list>` `Commits: <hash — subject>`
 `Check trio: PASS | FAIL (which check, if FAIL)` `RED evidence: <value defined in Step 4.1>`
 `GREEN evidence: <same test, command + passing summary line>` `Fresh-context review: pending — lead` `Not verified: <what, why> | none`
 `Deviations from the task brief (if any): <what, why>`; RED/GREEN mandatory; unfillable fields reported, never invented
RED evidence @is:282: `<failing test + failure line>` | `not observed — <reason>` (feature units only) | `n/a — docs/config unit`
Review @dv:31: after the report, BEFORE next wave/merge, LEAD spawns fresh `code-reviewer-agent` per unit with
 absolute file paths, commit hash, unit-brief path, `git show <hash>` scratch file; never a summary @dv:36
 logs `**Review:** <agent> — <verdict> — <pointer>`; `fix N issues first`→no merge/build-on; prose-enforced, no hook @dv:40
Env preflight @dv:52 (`is` Step 0 too): before 1st dispatch collect names (`Requires env:`, ARCHITECTURE, `.env.example`);
 only `^[A-Za-z_][A-Za-z0-9_]*$` names pass (others reported, never sanitized); presence by NAME only, never values; list missing once
## Commits·branches·tags: `<type>(<area>): <description> - closes #<N>` (github)|`… - closes P-<NNN>` (plan) @cm:12
 + trailers `Phase: <n>` `Feature: <id>`, body, `Co-Authored-By: Claude` @cm:16
Ref regex (both trackers) verbatim; required on code commits (feat fix refactor test perf), docs/chore may omit @cm:174:
 `(closes|refs) (#[0-9]+|P-[0-9]{3,}(\.\.P-[0-9]{3,})?)((, ?)(#[0-9]+|P-[0-9]{3,}(\.\.P-[0-9]{3,})?))*`
 A unit's own commit refs EXACTLY ONE unit; ranges `refs P-051..P-105`/lists `refs P-085, P-100` only in consolidation commits @cm:180
Branch `<type>/issue-<N>-<kebab>` (github)|`<type>/p-<NNN>-<kebab>` (plan), 3-5 words, one unit each @cm:86
Lead's wave branch `work/<YYYY-MM-DD>-<slug>`: workers commit there; lead owns merge (ESCALATE, one y/n) @cm:118
Tags local, push separate @cm:133: `v0.<phase>.0-<name>` `pg` PASS/WARN (optional) · `scope-lock-<date>` `dc` ·
 `rcode-migrate-<date>` `mg` · `v1.0.0`+ Launch only (ESCALATE) @cm:139
## Tracker grammar @rm:46 (one parser `U`; `M`,`G`,`R` call it @rm:102)
Asked once (AskUserQuestion), never guessed→config.json; scripts never ask: config, else github iff remote+gh auth+issue, else plan (ask-once @rm:50; inference rcode-units.sh:20-25)
github=issues. plan=BRAINSTORM.md units under `### Phase N`; 3 READ forms; only `dc` plan mode writes, never renumbers @rm:58:
 (a) checkbox `- [ ] P-NNN — <Title>`/`- [x]` (b) table row, first cell `P-NNN` @rm:65
 (c) local `#N`: table whose 1st header cell is `#`|`ID`|`Nr`|`Nr.`, row cell int|`#`+int; plan number, not an issue @rm:69
Phase of a unit: `[Phase N]` title prefix, else nearest preceding `##`-`####` heading naming `Phase N`, else `unknown` @rm:78
Done: `[x]`; table column `Status`|`State`: `done|closed|complete|completed|✅|x`→closed, else open; no such column→`unknown` @rm:82
`unknown`: excluded from open/closed counts, always a finding naming file/table; no `P-NNN`/local `#N` at all→`units: []`+finding @rm:89
## `.rcode/` files @w:129: `config.json` · `scope-manifest.json` (locked by `dc`) · `agent-log.md` (append-only, single-writer) ·
 `blocked-issues.md` · `phase-summaries/` (`pg`) · `re-entry-brief.md` (only in a backward jump) · `re-entry-archive/` ·
 `escalation-queue.md` (auto-approval/overnight) · `overnight-report.md` (`ao`) @w:131
config.json: `project_name` `repository` `created_date` `framework_version` `tracker` `total_phases` `total_issues` @ri:161
 `current_phase`: `ri`/`mg` 0, `dc` Step 6→1, `pg` Step 5→N+1 only on PASS/WARN @dc:288
 `status`=initialized(`ri`)|brainstormed(/brainstorm)|migrated(`mg`)|decomposed(`dc` Step 6) @dc:283
 `tracker` asked by `ri` `mg` `dc` `tl` `up` · `framework_version` stamped by `ri` `mg` /brainstorm, bumped by `up` @ver:1
## Gather scripts: stdout ONE JSON; exit 0 `ok:true`, 1 `ok:false` (see `errors[]`), 2 usage error (JSON still emitted) @G:68
All emit {ok,tracker,…,findings,errors}; `ok:false`/non-zero→STOP/BLOCK, never recompute by hand; read `findings[]` @pg:67
 unmeasured (plan table w/o Status col)→`null`+finding, never a fabricated 0; `?`=nullable @U:51
`U` {units[{id,title,phase?,phase_name?,state open|closed|unknown}],source `"gh issue list"`|`"BRAINSTORM.md"`} @U:61
`M` {milestones[{title,total,closed?,percent?}],stale_issues[{number,title,updatedAt}],counts{issues_(total|open|closed|unknown|
 no_milestone|blocked),milestones_total}}; plan: all-unknown→open/closed null @M:77
`G` {verdict,counts{issues_(total|closed|unknown),(tsc|lint)_errors,lint_warnings,tests_(passed|failed)}} <N> @G:124
 BLOCK=hard failure (open units, tsc/lint errors, failing tests, failed build) · WARN=none failed but unverified/skipped/ambiguous
 · PASS=all clean; lead adjudicates @G:162; non-npm→quality null: run `CLAUDE.md` trio; stub→`[not verified]`, never PASS @pg:122
`R` {branch?,dirty_files,stash_count,last_commit?,in_progress_unit?,detected_project_phase?,last_logged_step?,last_entry_agent?,open_prs?,
 ambiguous}; `ambiguous:true`=sources conflict, tie-break provisional→show both, ask @co:50
## Commands: y/n gates · writes · commits (tags: see Tags)
`tl` y/n only: ESCALATE ops, tracker/Stage questions @tl:243 · `is` none; S: branch/commits/PR/`docs(status)`, W: code commit only @is:65
`dc` github: ⛔ y/n (GitHub objects/tag/commit), plan: none; writes BRAINSTORM ids, manifest, status docs, config; 2 commits @dc:54
`pg N` none; BLOCK commits nothing; PASS/WARN: writes phase summary, `current_phase`; `docs(phase-gate)` @pg:220
`ss` none; rewrites PROJECT-STATUS, START_HERE; `docs(status)` @ss:272 · `ho` none; WIP commit/stash, log; `docs(handoff)` @ho:167
`co` read-only; by `last_entry_agent`: team-lead→`tl`, handoff→its "Units In Progress", `**Last step:**`→`is` Step N+1, else ask @co:61
`le` none; CONVENTIONS/ARCHITECTURE/CLAUDE.md/CONTEXT.md; `docs(lessons)` @le:234 · `rv` none; github `gh pr review`, plan: report @rv:35
`ri` ⛔ ONE y/n: git init+commit (+remote if opted); 5 questions; writes `.rcode/`, rules, CLAUDE.md, status docs; `chore(project)` @ri:311
`mg` ⛔ y/n (github: labels/milestone/tag/commit; plan: commit+tag); blocked: no git or `.rcode/` present; `docs(project)` @mg:300
`so` read-only; STRONG|MODERATE→offers `mg` (AskUserQuestion); NOT RECOMMENDED→one-line reason, no offer @so:122
`up` local-only (no gh, no push); y/n per file, then ONE y/n to commit `chore(rcode): upgrade rails to <ver>` @up:259
 bumps `framework_version` only if no OUTDATED-UNMODIFIED/NEW update declined @up:235; classes @up:183: UP-TO-DATE=identical→skip ·
 OUTDATED-UNMODIFIED=differs from current, equals base→propose · CUSTOMIZED=differs from base→never clobber ·
 NEW=core rule absent→propose · PROJECT-OWN=not in global set→untouched · RENAMED=legacy pre-rebrand name→replace+fix import
 zsh traps @up:101: always `"${sha}:rcode/VERSION"` (bare `$sha:r…` eats the `r`); never a variable named `path` (tied to `$PATH`;
 same for cdpath, fpath, manpath)
## `/autonomous-overnight "<scope>"` @ao:29
Pre-flight, all 7 must pass @ao:43: 1 git clean 2 tests green 3 env verified 4 no open `escalation-queue.md` 5 rate/quota headroom,
 numbered per paid-generation-API item (counter+amount) 6 explicit scope 7 stop conditions agreed (≥N ESCALATE; tests red & unfixable)
Only rule change @ao:100: SOFT-ACK proceeds, noted in `.rcode/overnight-report.md`; ESCALATE stays hard-blocked, NEVER approved: append to
 `.rcode/escalation-queue.md` (op, R/S/T, why now, if approved/deferred); continue OTHER work; no retry/workaround/own ACK token @ao:128
Stop @ao:156: all remaining items ESCALATE-blocked · tests red & unfixable · queue reaches stop-N · env error hits all remaining work
## VERSION @ver:1: line 1 `2026-09-23` (current)=rail version; covers `rcode/rules/*.md`+stack rules, artifact formats commands parse
 (config schema, BRAINSTORM unit lines, template fields); NOT commands/skills/stages; stamped `ri` `mg` /brainstorm; bumped `up` @rm:142
## Critical rules @w:105: single-writer: `agent-log.md`+`PROJECT-STATUS.md` only by lead (`tl` exit, `ho`, standalone `is`, setup cmds,
 `pg`, `ss`, `le`, `dc`), never workers; conflicts→skill `resolving-merge-conflicts`, both entries in time order, no `merge=union` @adr:50
 1 unit/branch · 1 unit/commit ref · docs commits separate · no work ahead of phase gates · scope change needs human approval @sc:20
## rcode-ios @ios:23: 10→5 steps: Explore, Test-First, Implement, i18n Gate (strings in `Localizable.xcstrings`; blocks `pg`), Review&Ship
Sources read: Source+legend files in full (scripts: header+contract only; 4 of 18 templates); Not verified: /brainstorm, script bodies
