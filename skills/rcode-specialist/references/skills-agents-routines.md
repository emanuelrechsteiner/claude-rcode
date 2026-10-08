<!--
Status: ACTIVE
Last Updated: 2026-10-03
Purpose: Skills, agents, output style, routines: roster, hard constraints, known drift (rcode-specialist)
Source: skills/*/SKILL.md, agents/*.md, output-styles/hausbau.md, scheduled-tasks/*/SKILL.md (workshop checkout) -->
# Skills, agents, output style, routines — reference
## Skills (67, excl. host skill rcode-specialist = 68 SKILL.md on disk: 31 M, 17 F, 3 F+X, 4 B, 6 X, 6 D) name|mode|model|tools|purpose|origin (omitted = own); "-" = unset/inherit; ";" separates
Mode: M main, F fork, B background (user-invocable:false), X manual (disable-model-invocation), D demoted rule (IMP-079/218)
Tools: R Read G Glob g Grep W Write E Edit B Bash b scoped Bash M memory MCP w Web* T Todo P Playwright S sim MCP
Origin: ECC = affaan-m/ECC c70874f (IMP-245), mp = mattpocock (IMP-124), ck = claudekit, x = 3rd party
api-design|M|-|-|REST conventions|ECC; audit-config|M|-|RGb|config audit; backend-development|M|-|REWGgb|Firebase, Zustand
canary-watch|X|-|-|post-deploy smoke check|ECC; check-parallelizable|M|-|-|parallelism check
click-path-audit|X|-|-|dead-button trace|ECC; cloud-cli-discipline|D|-|-|cloud-CLI inspect-first
context-budget|M|-|-|context-load audit|ECC; council|X|-|-|four-voice go/no-go|ECC; create-hook|F|sonnet|RWEBGg|author hooks
create-rule|F|sonnet|RWEGg|author rules; create-skill|F|sonnet|RWEGg|author skills; create-subagent|F|sonnet|RWEGg|author agents
database-migrations|M|-|-|safe migrations|ECC; dependency-audit|M|-|RGgb|npm audit report
documentation|F|sonnet|REWGg|API docs, README, JSDoc; eval-harness|X|-|-|evals, pass@k|ECC; find-docs|M|-|-|Context7 ctx7 CLI lookup|x
fix-review|B|-|RGgb|post-fix check; framework-extraction|D|-|-|extraction criteria; grilling|M|-|-|one-question interview|mp
historical-signals|F+X|haiku|BRWG|session JSONL to signals; historical-signals-v2|F+X|haiku|BRWEG|SQLite extraction
human-testing|M|-|RGgTPb|Playwright UX QA; i18n-bilingual-sync|F|haiku|RWEBG|de/en key sync; import-fixer|B|-|RGgEb|repair imports
incident-response|M|-|-|incident runbook; ios-simulator-testing|M|-|RGgSb|iOS Simulator tests; kokonutui-pro|D|-|-|KokonutUI Pro registry
ledger-entry|M|-|-|OBS/PAT/OPT ledger; legacy-codebase-audit|D|-|-|legacy audit; liquid-glass-design|M|-|-|iOS 26 Liquid Glass|ECC
memory-index|F|haiku|RGgMb|memory query layer|IMP-013; meta-intelligence|M|-|-|project registry
meta-observer|F+X|opus|RGgWMb|signals to proposals; migrate-to-skills|F|sonnet|RWEBGg|Cursor to SKILL.md
navigate-mode|F|haiku|BRgG|codebase navigation; nextjs-debug|F|haiku|RGgb|Next.js debugging; orchestration|M|-|-|scrum coordination
parallel-dispatch|M|-|-|write fan-out with locks; pattern-document|F|sonnet|RWGgb|fix to rule doc
postgres-patterns|M|-|-|Postgres index/RLS|ECC; production-audit|X|-|-|ship/block score|ECC
project-bootstrap|M|haiku|RGgb|repo exploration; project-planning|M|opus|-|phase-gate plans; prototype|F|sonnet|RWEGgB|throwaway spikes|mp
quality-review|X|-|-|6-agent review|ck; rcode-ios|D|-|-|iOS R.Code defaults; rcode-onboard|M|-|RGgb(git,gh,bash)|agent orientation
react-perf-check|B|-|RGg|React perf checks; release-cli-discipline|D|-|-|deploy/publish/CLI rules; research|F|haiku|wRGg|docs research
resolving-merge-conflicts|M|-|-|conflict resolution|mp; scope-check|M|-|RGgb(git diff,log,gh)|scope guardian
scroll-animation-patterns|F|sonnet|RWEGg|scroll animation; swift-actor-persistence|M|-|-|actor storage|ECC
swift-concurrency-6-2|M|-|-|Swift 6.2|ECC; swift-protocol-di-testing|M|-|-|protocol DI tests|ECC; swiftui-patterns|M|-|-|SwiftUI iOS17+|ECC
tailwindcss-v4-styling|B|-|REWGgb|Tailwind v4; testing-suite|M|-|RGgb|Vitest/Playwright; type-coverage|M|-|RGgb|TS any audit
ui-development|M|-|REWGgb|React components; ux-design|M|-|RgG|flows, WCAG; validate-build|F|haiku|RGgb|tsc/eslint/build/test
version-control|F|haiku|Rgb(git,gh)|git, PRs, releases; worktree-consolidate|F|haiku|b(git,gh)|worktree merge
## Hard rules (these skills only; x:N = skills/x/SKILL.md:N, a/x:N = agents/x.md:N, st/x:N = scheduled-tasks/x/SKILL.md:N)
rcode-onboard: R.Code only (:22-29); surface escalation-queue.md + re-entry-brief.md first (:115); end /team-lead "<directive>" (:225)
scope-check: tracker: .rcode/config.json else inferred+said (:27); Phase = milestone (:24); scope change only after human yes/no (:241)
rcode-ios: i18n gate mandatory, blocks /phase-gate (:32); VersionedSchema per @Model change (:69); no ObservableObject/XCTest (:119,131)
parallel-dispatch: write fan-out only; claim locks first, parallel-claim.sh (:85); ONE message of N Agent calls; release-session (:129);
 3 StructuredOutput mismatches = abort (:111); chained writers: isolation 'worktree' or lock (:177); bypass CLAUDE_PARALLEL_LOCK_OFF=1
check-parallelizable: speedup = sum/(max+30s): <1.5x skip, 1.5-2x maybe, >2x yes (:54-60)
meta-observer: proposals only; windows by entry timestamp not mtime (:43); never `implemented` (:200); gate-weakening ESCALATE (:232)
quality-review: 6 code-reviewer-agent calls in ONE message, <300 words each (:29); "Top 3 actions" (:66)
worktree-consolidate: merge/push/prune/branch-delete each ESCALATE, y/n each (:15,116); dirty trees refused (:67-74);
 branch -d not -D (:147); no --force (:173)
release-cli-discipline: local build first (:14); tarball in fresh consumer project (:27); printf "%s" never echo, verify by pull (:43-45);
 no generation-MCP while UI open (:58)
cloud-cli-discipline: gate only destructive/scope-changing/auto-pick ops (:12); --yes ok for preview deploy, whoami, confirmed link (:22);
 vercel switch = ESCALATE
context-budget: read-only, never applies cuts; /context authoritative (:38); flags desc >300 chars, agent >200 lines, MCP >20 tools (:49-52)
audit-config: CRITICAL = fix + commit "chore(config): fix audit findings <date>" (:49-53); security pass read-only (:59)
create-hook|rule|skill|subagent, pattern-document: write ~/.claude/{hooks,rules,skills,agents} = LIVE install, deploy-only (CLAUDE.md:10-16)
## Agents (12; :N = agents/<name>.md) name|model|tools|use|non-negotiable
backend-agent|sonnet|GgRWEB|APIs, DB, auth|"Maximum 200 lines per file" (:34)
cleanup-agent|haiku|BRGgE|dead code, EOF|"Never auto-fix" console.error, TODO/FIXME, commented code (:146)
code-reviewer-agent|sonnet|RgG|review|"CRITICAL: You are READ-ONLY." (:15)
control-agent|claude-fable-5-1[1m]|RWEGg+Agent,Task,TaskCreate,TaskUpdate|orchestration|"MUST be passed as the `model` parameter" (:90)
documentation-agent|sonnet|RWEGgB+Notion(search,fetch,update-page,create-pages)|Daily-Docs only|"Do NOT retry silently" (:105)
pattern-extractor-agent|sonnet|BRWGg|/lessons Step 6|"Score: X/5 - Document if >= 3" (:73)
planning-agent|opus|GgRWE|plans|"Always create a `PLANNING.md` file" (:27)
research-agent|haiku|GgRW+WebFetch,WebSearch|research|"You never edit, overwrite, or append to an existing file" (:18)
testing-agent|sonnet|GgRWEB|tests|"No skipped tests without documented reason" (:133)
ui-agent|sonnet|GgRWEB|design system|"no `any` without written justification" (:146)
version-control-agent|sonnet|BREGg|commits, PRs|"CRITICAL Rule: Report-Only Default" (:31)
visual-qa-agent|sonnet|RgGB+23 playwright browser_*|rendered check|"CRITICAL: You are READ-ONLY." (:41)
control-agent §2 (:64-159): per spawn Agent, Model (haiku|sonnet|opus|fable), Effort (low..max); model must be passed as parameter (:90),
 else agent file, else env CLAUDE_CODE_SUBAGENT_MODEL=sonnet floor, else caller (:93-105). §4 (:198-250) after EVERY wave: digest-review,
 verbatim-instruction + negative-list check, re-plan. Arbiter (:283-292): sub-agents report UP, one verbatim y/n per op.
## Output style Hausbau (hausbau.md; opt-in /output-style Hausbau; main thread; keep-coding-instructions: true load-bearing, CLAUDE.md:62)
Mapping (:21-38): architecture=blueprint/structural engineering; code=masonry/shell; function/file=component/room; interface=doorway;
 config=basement fuse box; tests=building inspection; gates/hooks=site safety rules; logs=site diary; deploy=handover;
 rework=renovation in operation; overhaul=core renovation; deferred cleanup=shoddy work; libraries=prefab suppliers;
 monitoring=superintendence; backup/version=building file; parallel helpers=trades on site.
Invariants: (1) image never swapped once introduced (:18); (2) no counterpart: say so, explain directly (:40);
 (3) numbers/dates/names exact, "fixed" says how you can tell (:49-53); (4) never softens a defect, unverified = "unverified" (:61-71);
 (5) prose leads, result first, no jargon (:58,75-81); (6) work method unchanged, questions carry recommendation (:83-87)
## Routines (st/x:N; FR = docs/FRAMEWORK-REFERENCE.md): launchd com.claude-code.routine-<x>, scripts/routine-run.sh (IMP-135/219)
Run log mandatory (IMP-075), one line per run in ~/.claude/global-observation/; no line = same as "never fired"; cwd ~/.claude
daily-docs 07:10: run-log.sh start (:20) -> logbook-count.sh (exit!=0: run-log.sh fail --reason <ABORT>, no number; :72-115)
 -> A logbook/<day>.md (:234) -> B Notion, fetch first (:336-375) -> run-log.sh finish (:390); log daily-docs-log.jsonl
nightly-observation 02:05: rotate-signals.sh (stop on exit 1,2; continue on 3) -> compute-daily-metrics.sh -> trim dispatch-capture.jsonl
 to 50,000 lines -> nightly-obs-log.jsonl (:10-42); failure -> alerts.jsonl + blocker in next daily-docs
weekly-improve Sun 22:06: meta-observer, 7 days, gunzip -c never zcat (:38) -> plans/meta-proposal-YYYY-WW.md -> ledger-append-proposed.sh
 (proposed only, IMP-112) -> Notion comment -> FINAL line to weekly-improve-log.jsonl (:70-138)
Failure 2026-08-02..22: unversioned cloud binding to a renamed directory, 20 days silent cwd outage (FR:328)
Failure 2026-08-23..09-09: 39 failed runs (nightly 18, daily 18, weekly 3): SKILL.md after -p read as option; c165871 = stdin (FR:330-346)
Failure 2026-09-10..21: lone surrogate in desktop audit.jsonl aborted 5 of 13 daily runs (ABORT 16); docs/adr/0004 (IMP-223)
Failure IMP-211 (proposed): meta-observer:6 disable-model-invocation blocks weekly-improve; owner chose split 09-27, open (ledger:3553)
## Inconsistencies (file:line)
worktree-consolidate:15,188|cites retired autonomy-arbiter.md (now agency-bands, a/control-agent:285)
a/version-control-agent:94; create-rule:199|cite identity-config-check.md; actual file is rules/identity.md
nextjs-debug:203,205; react-perf-check:248-249; type-coverage:232|cite nonexistent framework-specialist-agent, build-validator-agent, rules
check-parallelizable:99|maps UX flows to archived ux-agent (ux-design skill); no Model/Effort columns (IMP-091)
incident-response:9-11|says /launch-team Run mode is described inline; commands/launch-team.md has no such section
backend-development:4,9; documentation:6,11; +6|"Memory-First MANDATORY" (mcp__memory__*); 8 of 10 skills' allowed-tools omit it
version-control:71,93,100-101|git add ., local merge + push origin main vs rules/workflow-git.md:49,59
testing-suite:30,121; ui-development:3,159|90%+ coverage vs a/testing-agent:79-82 (80/75/80/80)
i18n-bilingual-sync:15,47; scripts/sync.py:101-102|"atomic, no partial state" vs two sequential dump_json writes
create-rule:85,193,71|"13 rules" (CLAUDE.md:20: 21 tracked, 24 live); "no path scoping" vs context-budget:28,47,59 paths:
st/daily-docs:118-139,391; bin/logbook-count.sh:300,1038,1055|ABORT table ends at 21, script exits 22-24; "$J" never defined
a/documentation-agent:22,38,53,87,100|pre-fix procedure: remote routine, repo glob, ${LOGBOOK_DIR}, hardcoded Notion id, hand log line
scope-check:245-259 vs :4-10|writes manifest/status + git commit; tools read-only + git diff/log + gh (+ rcode-onboard:87,129)
a/control-agent:13-14 vs scripts/audit-config.sh:111,123-125|control-agent lists TaskCreate/TaskUpdate; audit flags CRITICAL (read, not run)
Sources read: dossiers 09/10, skill/agent frontmatter, hausbau.md, 3 routines, ADR 0004; Not verified: skill bodies beyond cited lines
