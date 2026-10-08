<!--
Status: ACTIVE
Last Updated: 2026-10-03
Purpose: One line per IMP entry (231); grep an id instead of reading the 442 KB ledger
Source: global-observation/improvement-ledger.json v1.5.0 (id/status/date grep-verified 2026-10-03; wording from dossiers) -->
# Improvement ledger index (IMP-001..246)
Legend: ID | status | date | what | mechanism. impl=implemented prop=proposed depr=deprecated regr=regressed (undeclared); date = implementedAt, else proposedAt; half = partly delivered; no meas. = no verification.measured (flagged on some entries only; full post-075 set in ledger.md); implAt = implementedAt. eag=excessive-agency-gate.sh gu=guard-unsafe.sh ses=session-end-check.sh obs=observation-capture.sh par=parallel-dispatch skill. Totals: impl 190, prop 37, depr 3, regr 1.
Absent ids (not in file): 014-018, 026-032, 073, 074 (v1.5.0 text cites them), 142.
IMP-001 | impl | 2025-08-31 | Control Agent auto-activation | agent
IMP-002 | impl | 2025-08-31 | Compliance validator agent | archived
IMP-003 | impl | 2025-08-31 | Data-structure preservation | doc
IMP-004 | impl | 2025-08-31 | Context checkpoints | doc
IMP-005 | impl | 2025-08-31 | Agent auto-routing | doc
IMP-006 | impl | 2025-08-31 | Testing-agent auto-trigger | agent
IMP-007 | impl | 2025-08-31 | Improvement ledger + semver | ledger
IMP-008 | impl | 2026-02-22 | iOS workflow v2 (8->5 phases) | agents, skill
IMP-009 | impl | 2026-04-20 | Observation pipeline reboot | obs, skill
IMP-010 | impl | 2026-04-20 | Legacy-codebase audit pattern | skill (079)
IMP-011 | impl | 2026-04-20 | Haiku+Sonnet cost rule | rule
IMP-012 | impl | 2026-04-20 | Framework-extraction pattern | skill (079)
IMP-013 | impl | 2026-04-20 | Cross-project memory query | skill
IMP-019 | impl | 2026-04-20 | Report-only default | rule
IMP-020 | impl | 2026-04-20 | Git identity auto-correct | hook
IMP-021 | impl | 2026-04-20 | Tool-discipline rule | rule
IMP-022 | impl | 2026-04-20 | German triggers, 7 skills | SKILL.md
IMP-023 | impl | 2026-04-20 | gu curl tuning | gu
IMP-024 | impl | 2026-04-20 | Web tools on ask list | superseded 088
IMP-025 | impl | 2026-04-20 | SessionStart cwd ritual | hook
IMP-033 | impl | 2026-05-24 | Read-before-Edit hook | hook
IMP-034 | impl | 2026-05-24 | gu blocks Bash cat/head/tail | gu; eased 157
IMP-035 | impl | 2026-05-25 | Post-Bash-failure prompt | hook
IMP-036 | impl | 2026-05-25 | Planning-doc live-spec rule | rule, ses
IMP-037 | impl | 2026-05-25 | i18n bilingual-sync | skill
IMP-038 | impl | 2026-05-25 | NAVIGATE-mode skill | skill
IMP-039 | impl | 2026-05-24 | Drop compaction prompts | extract.py
IMP-040 | impl | 2026-06-09 | Bash-gate FP + rm -rf fix | eag
IMP-041 | impl | 2026-06-09 | Op-bound ACK token | eag; defect 119
IMP-042 | prop | 2026-06-08 | Split route files >400 LOC | product repos
IMP-043 | prop | 2026-06-08 | Shared chatStore | product repos
IMP-044 | impl | 2026-06-09 | Autonomy Arbiter | merged 079
IMP-045 | impl | 2026-06-09 | Security/autonomy rebalance | rules, hooks
IMP-046 | impl | 2026-06-09 | session-metrics writer fix | ses
IMP-047 | impl | 2026-06-20 | gu curl /dev/null fix | gu
IMP-048 | impl | 2026-06-20 | Read-before-edit doc | HARNESS.md
IMP-049 | impl | 2026-06-21 | Rotation archive-then-trim | rotate-signals
IMP-050 | impl | 2026-06-21 | 250-LOC limit + queue | stop hook
IMP-051 | impl | 2026-06-21 | GUARD_OVERRIDE at cmd head | gu
IMP-052 | impl | 2026-06-20 | Intent classifier bleed fix | obs
IMP-053 | impl | 2026-06-20 | recommend-on-ask rule | rule
IMP-054 | impl | 2026-06-21 | Lifecycle bands, MCP merge | workflow-git
IMP-055 | impl | 2026-06-21 | Delegate-by-default | foundation
IMP-056 | impl | 2026-06-20 | StructuredOutput abort at 3 | par
IMP-057 | impl | 2026-06-21 | Stop-hook handoff writer | hook
IMP-058 | impl | 2026-06-20 | eag testmode log | eag
IMP-059 | impl | 2026-06-20 | classify_rm /tmp first | eag
IMP-060 | impl | 2026-06-20 | Context7 param-name doc | rule
IMP-061 | impl | 2026-06-20 | Subagent read-only grep | par
IMP-062 | impl | 2026-06-20 | PROJECT_ROOT contract | par
IMP-063 | impl | 2026-06-21 | rm-rf allowlist; 063b open | eag
IMP-064 | depr | 2026-06-20 | Daily archive guard | merged 049
IMP-065 | impl | 2026-06-20 | Stale memory cleanup | ledger
IMP-066 | impl | 2026-06-21 | worktree-consolidate | skill
IMP-067 | impl | 2026-07-03 | identity.local mappings | rule
IMP-068 | impl | 2026-06-21 | /continue | cmd
IMP-069 | impl | 2026-06-21 | Autonomous-overnight | cmd
IMP-070 | impl | 2026-07-03 | Follow-ups inherit worktree | par
IMP-071 | impl | 2026-07-03 | Handoff commit-loop defect | fixed 081
IMP-072 | impl | 2026-07-03 | Worktree discipline | par
IMP-075 | impl | 2026-07-03 | Outcome verification loop | meta-observer
IMP-076 | impl | 2026-07-03 | Gate regression suite 28/28 | tests
IMP-077 | impl | 2026-07-03 | Policy coherence, 4 spots | hook texts
IMP-078 | impl | 2026-07-03 | MCP agency gate | hook
IMP-079 | impl | 2026-07-03 | Rules diet (~9K tokens) | rules
IMP-080 | impl | 2026-07-03 | Model-era refresh | rules
IMP-081 | impl | 2026-07-03 | Handoff loop fix; eag 100ms | hook
IMP-082 | impl | 2026-07-03 | Write-only data closed | queue 136->78
IMP-083 | impl | 2026-07-03 | Generated inventory | script
IMP-084 | impl | 2026-07-03 | Drift guard; drill PENDING | hook
IMP-085 | impl | 2026-07-03 | R.Code VERSION + upgrade | rcode/VERSION
IMP-086 | impl | 2026-07-03 | Meta-loop trust boundary | meta-observer
IMP-087 | impl | 2026-07-03 | Scheduled-task source merge | README
IMP-088 | impl | 2026-07-09 | Web research trust gate | hook, rule
IMP-089 | impl | 2026-07-15 | Contract lint, note-only | lint script
IMP-090 | impl | 2026-07-15 | Mutation gate, note-only | hook; no meas.
IMP-091 | impl | 2026-07-15 | Role unification | no meas.
IMP-092 | impl | 2026-07-15 | Fable pin, 16 cmds | frontmatter
IMP-093 | impl | 2026-07-15 | auto-read new-file fix | hook; no meas.
IMP-094 | regr | 2026-07-15 | Gate activity -> signals | eag; 0 records
IMP-095 | impl | 2026-07-15 | 12h marathon warning | ses; no meas.
IMP-096 | impl | 2026-07-15 | Repeat-block diagnostic | hook; no meas.
IMP-097 | impl | 2026-07-15 | Ledger totalEntries 73/74 | jq
IMP-098 | impl | 2026-07-15 | A<->B checkout sync | git; no implAt
IMP-099 | impl | 2026-07-15 | Schema minLength | schemas
IMP-100 | impl | 2026-07-15 | Verify-the-verifier | briefings
IMP-101 | impl | 2026-07-16 | /team-lead command | cmd
IMP-102 | impl | 2026-07-16 | eag macOS temp roots | eag
IMP-103 | impl | 2026-07-16 | gu temp carve-out | gu
IMP-104 | impl | 2026-07-17 | Serena writes off | MCP cfg
IMP-105 | impl | 2026-07-17 | Serena ignores worktrees | MCP cfg
IMP-106 | impl | 2026-08-22 | gu command-position check | gu lib
IMP-107 | impl | 2026-07-26 | Public docs for /team-lead | public repo
IMP-108 | impl | 2026-07-26 | eag env-prefix bypass | eag
IMP-109 | impl | 2026-07-31 | graphify global install | settings
IMP-110 | impl | 2026-08-01 | weekly-improve zcat fix | SKILL.md
IMP-111 | impl | 2026-08-01 | daily-metrics provenance | script
IMP-112 | impl | 2026-08-01 | Write-back bridge | ledger-append
IMP-113 | impl | 2026-08-01 | Ledger integrity, sampling | eag
IMP-114 | impl | 2026-08-01 | Lock-registry ID spaces | parallel-claim
IMP-115 | impl | 2026-08-01 | dispatch-capture meter | hook
IMP-116 | impl | 2026-08-01 | Controller-first log | hook
IMP-117 | impl | 2026-08-01 | web-fetch-gate log fix | hook
IMP-118 | impl | 2026-08-01 | gu logs needless override | gu
IMP-119 | impl | 2026-08-01 | ACK signature collision | eag
IMP-120 | impl | 2026-08-01 | 5 phase-team cmds installed | cmds
IMP-121 | impl | 2026-08-01 | IMP-### commit refs | workflow-git
IMP-122 | impl | 2026-08-01 | git-remote-check hook | hook
IMP-123 | impl | 2026-08-02 | rebase --abort unblocked | hook
IMP-124 | impl | 2026-08-03 | 3 skills + domain-docs rule | skills
IMP-125 | impl | 2026-08-03 | Fowler smell baseline | reviewer
IMP-126 | impl | 2026-08-03 | disable-model-invocation x2 | skills
IMP-127 | impl | 2026-08-04 | Deploy pulls runtime keys | deploy
IMP-128 | impl | 2026-08-04 | settings.local dead letter | docs
IMP-129 | impl | 2026-08-04 | controller-first suite fix | tests
IMP-130 | impl | 2026-08-05 | Serena write gate | hook
IMP-131 | impl | 2026-08-05 | Serena gate: missing file | hook
IMP-132 | impl | 2026-08-06 | execute_sql by statement | mcp gate
IMP-133 | impl | 2026-08-15 | Serena double install off | cfg
IMP-134 | impl | 2026-08-15 | pr-guard in mirror only | workflow
IMP-135 | prop | 2026-08-22 | 3 routines dead 20 days | launchd pkg
IMP-136 | prop | 2026-08-22 | Intent classifier 65% FP | obs
IMP-137 | impl | 2026-08-22 | MCP memory persistent path | cfg
IMP-138 | impl | 2026-08-22 | Staleness alarm decoupled | ses
IMP-139 | impl | 2026-08-24 | general-purpose share 43.5% | done by 159
IMP-140 | impl | 2026-08-22 | Lock log release sampling | hook
IMP-141 | impl | 2026-08-22 | Obs dir 913 MB rotation | script
IMP-143 | impl | 2026-08-23 | Rendered-proof duty | rule
IMP-144 | impl | 2026-08-23 | NIE/IMMER persisted same turn | rule
IMP-145 | impl | 2026-08-23 | Escalation queue (auto mode) | rule
IMP-146 | impl | 2026-08-23 | curl upload SOFT-ACK | gu
IMP-147 | impl | 2026-08-23 | Deploy pending-verification | deploy
IMP-148 | impl | 2026-08-23 | Side findings -> ledger | doc
IMP-149 | impl | 2026-08-23 | Target-path announce | tool rule 7
IMP-150 | impl | 2026-08-23 | /issue into team-lead | cmds
IMP-151 | impl | 2026-08-23 | Serena guard in audit | audit-config
IMP-152 | impl | 2026-08-23 | Bulk external run ESCALATE | rule
IMP-153 | impl | 2026-08-23 | Dated negative claims | rule
IMP-154 | impl | 2026-08-23 | Quota before fan-out | cmd
IMP-155 | prop | 2026-08-23 | MCP connector diet | plan doc
IMP-156 | impl | 2026-08-23 | IMPs from transcripts only | skills
IMP-157 | impl | 2026-08-24 | gu curl hole; cat block off | gu, hook
IMP-158 | impl | 2026-08-24 | Sink proof; half | rules
IMP-159 | impl | 2026-08-24 | general-purpose rationale | hook
IMP-160 | impl | 2026-08-24 | Acceptance at artifact | rules
IMP-161 | impl | 2026-08-24 | Task-brief template | template
IMP-162 | impl | 2026-08-24 | Path canon, Rule 8; half | hook, rule
IMP-163 | impl | 2026-08-24 | Global-state ESCALATE | eag
IMP-164 | impl | 2026-08-24 | Repeat counter escalation | ses
IMP-165 | prop | 2026-08-24 | Model-switch hygiene | rule
IMP-166 | prop | 2026-08-24 | Pilot before fan-out | rule
IMP-167 | prop | 2026-08-24 | Copy-not-interpret check | agent
IMP-168 | prop | 2026-08-24 | BEFUND diagnosis format | skill
IMP-169 | impl | 2026-09-23 | Env-key preflight | rcode stages
IMP-170 | prop | 2026-08-24 | Background runs, no timeouts | rule
IMP-171 | prop | 2026-08-24 | Dev-server port management | doc
IMP-172 | prop | 2026-08-24 | Narrow security-review trigger | -
IMP-173 | prop | 2026-08-24 | In-session plan-doc warning | rule
IMP-174 | prop | 2026-08-24 | Worktree merge proposal | skill
IMP-175 | prop | 2026-08-24 | Sharpen a private trigger | overlay
IMP-176 | prop | 2026-08-24 | Plausibility of brief numbers | template
IMP-177 | prop | 2026-08-24 | Tool-call hygiene measure | rule
IMP-178 | prop | 2026-08-24 | Numbered Qs + recommendation | rule
IMP-179 | prop | 2026-08-24 | Cost claims need before/after | rule
IMP-180 | prop | 2026-08-24 | /human-testing loaded once | cause unknown
IMP-181 | prop | 2026-08-24 | Context diet; merge 155 | rule
IMP-182 | prop | 2026-08-24 | Repo-name ambiguity; dup 149? | rule
IMP-183 | depr | 2026-08-24 | Dated negatives; dup of 153 | -
IMP-184 | prop | 2026-08-24 | Machine format + readable view | doc
IMP-185 | prop | 2026-08-24 | ADR duty, landscape choices | rule
IMP-186 | depr | 2026-08-24 | Escalation channel; dup 145 | -
IMP-187 | prop | 2026-08-24 | Handoff verification at start | hook
IMP-188 | impl | 2026-09-27 | Ledger counters recomputed | ledger-append
IMP-189 | impl | 2026-09-09 | Routine runner stdin fix | routine-run
IMP-190 | impl | 2026-09-09 | routine-run --dry-run | routine-run
IMP-191 | impl | 2026-09-09 | SessionStart reads routine log | hook
IMP-192 | impl | 2026-09-09 | Alarm cause line, N=5 | ses
IMP-193 | impl | 2026-09-09 | npm --location=global bypass | eag
IMP-194 | impl | 2026-09-09 | modelSettings in deploy | deploy
IMP-195 | impl | 2026-09-09 | Window by record timestamp | skills
IMP-196 | impl | 2026-09-09 | visual-qa-agent | agent
IMP-197 | impl | 2026-09-09 | research-agent may Write | agent
IMP-198 | impl | 2026-09-09 | Background-squad watchdog | hook
IMP-199 | impl | 2026-09-09 | Resume, not restart | agent
IMP-200 | impl | 2026-09-09 | Corrects 162 (44/50 foreign; recount 43) | ledger only
IMP-201 | impl | 2026-09-09 | Brief negative-list check | agent
IMP-202 | impl | 2026-09-09 | 3 inert Write denies removed | settings
IMP-203 | impl | 2026-09-09 | Web-fetch gate: dates not hosts | hook
IMP-204 | impl | 2026-09-09 | Dispatch meter logs model | hook
IMP-205 | impl | 2026-09-09 | Suite counts generated | script
IMP-206 | impl | 2026-09-09 | gate log line quarantined | runtime
IMP-207 | impl | 2026-09-09 | Security-review feedback | hook
IMP-208 | prop | 2026-09-09 | Archive folder archives nothing | agents/
IMP-209 | impl | 2026-09-09 | 11 bypass forms of 163 | eag
IMP-210 | prop | 2026-09-09 | Obs loop stalled; alarm 255x | write-back
IMP-211 | prop | 2026-09-20 | weekly-improve blocked | SKILL.md
IMP-212 | impl | 2026-09-21 | Subagent model floor | settings
IMP-213 | impl | 2026-09-21 | Rationale must name specialist | hook
IMP-214 | impl | 2026-09-21 | rcode/VERSION 07-03->08-06 | rcode/VERSION
IMP-215 | impl | 2026-09-23 | R.Code plan follows practice | rcode, ADR 0002
IMP-216 | impl | 2026-09-23 | Watchdog empty stop_reason | hook
IMP-217 | impl | 2026-09-24 | Instruction diet 1 | rules
IMP-218 | impl | 2026-09-24 | Instruction diet 2 | rules->skills
IMP-219 | impl | 2026-09-25 | Vault + pseudonymization | scripts/vault
IMP-220 | impl | 2026-09-27 | Model-era review 5.x | rule
IMP-221 | impl | 2026-09-27 | Empty gz shard (no signals) | rotate-signals
IMP-222 | impl | 2026-09-27 | User-global corrections file | rule
IMP-223 | impl | 2026-09-27 | daily-docs lone surrogate | logbook-count
IMP-224 | impl | 2026-09-27 | "Done: yes/no" reports | rule
IMP-225 | impl | 2026-09-27 | daily-docs in-tree symlinks | logbook-count
IMP-226 | impl | 2026-09-27 | rotate-signals merges late | rotate-signals
IMP-227 | impl | 2026-09-27 | empty_verified zero row | metrics script
IMP-228 | prop | 2026-09-27 | logbook-count ABORT design | logbook-count
IMP-229 | impl | 2026-09-27 | Watchdog marker context | hook
IMP-230 | prop | 2026-09-27 | rotate-signals 7 follow-ups | rotate-signals
IMP-231 | prop | 2026-09-27 | 3 inert deny rules | settings
IMP-232 | prop | 2026-09-27 | Watchdog residuals | hook
IMP-233 | prop | 2026-09-27 | Model defaults decision | CLAUDE.md
IMP-234 | impl | 2026-09-29 | Instruction diet 3 | 21 rules
IMP-235 | prop | 2026-09-29 | Triage 31 rule disagreements | plan doc
IMP-236 | prop | 2026-09-29 | Budget guard, loaded text | inventory
IMP-237 | prop | 2026-09-29 | Demote 3 rules to skills | rules
IMP-238 | prop | 2026-09-29 | Condense R.Code rails | rcode/rules
IMP-239 | impl | 2026-10-01 | governing-path-guard | hook
IMP-240 | impl | 2026-10-01 | git-bypass-guard | hook
IMP-241 | impl | 2026-10-01 | R.Code RED/GREEN + review | issue, develop
IMP-242 | impl | 2026-10-01 | run-all-tests.sh + CI | script, CI
IMP-243 | impl | 2026-10-01 | Deploy gate: clean + suites | deploy
IMP-244 | impl | 2026-10-01 | config-security-audit | script
IMP-245 | impl | 2026-10-01 | 14 ECC skills adapted | skills
IMP-246 | impl | 2026-10-01 | Completion contract in brief | template
Sources read: dossiers 05/06 tables, ledger meta block, writer-script header; id/status/date of all 231 grep-checked in the real ledger; Not verified: what/mechanism wording vs full entry text (paraphrased from dossiers; ~35 entries re-read).
