<!--
Status: ACTIVE
Last Updated: 2026-10-03
Purpose: scripts, deploy, contract lint, tests, CI, installers; ws=workshop <WORKSHOP>, live=~/.claude
Source: scripts/, hooks/tests, install.*, .github/workflows, docs/WORKING-IN-THIS-REPO.md; path:line 2026-10-03 -->
# Scripts, deploy, tests — reference
script (not vault/publish/scrub) or topic (deploy, lint, run = that .sh)|purpose/facts; :N = line|exit|key env|callers (blank = manual)
-|-|-|-|-
deploy-to-live.sh, run-all-tests.sh, command-contract-lint.sh|deploy; runner; linter|see rows deploy, run, lint
framework-inventory.sh|disk counts, suite case counts; runs none|0;1 --check miss;2 no jq/python3 :33-43|CLAUDE_DIR default LIVE :29
audit-config.sh|quarterly live audit to audit-reports/|0 even WARN-only :368;1 CRITICAL;2 never|none (HOME fixed :20)|launchd
config-drift-check.sh|Stop warner: stale uncommitted, unpushed|0 always|CLAUDE_DRIFT_MAX_DAYS=3, _FETCH, CLAUDE_CONFIG_DIR|settings.json:352
config-security-audit.sh|read-only audit of a config tree, ids next row|0;1 CRITICAL :226;2 usage|--root --live --json --report --allow
CSA ids|001/002 perms;010-014 hooks;020-022 MCP;030 hidden-char;031 comment;032 BOM;033 unread;040 clone;050/051 bad JSON|CRIT 030,050,051
secret-patterns.sh, ledger-append-vault-gate.sh|sourced: PEM/JWT regex; ledger text gate|-|-|security-audit.sh:36, ledger-append
git-hooks/pre-commit, install-git-hooks.sh|vault+scrub gate on staged blobs; writes 3 wrappers|0;1|VAULT_PRECOMMIT_BYPASS="reason"
imp-submit.sh|validate IMP form via vault check, no network|0;1 form/usage/no vault;2 finding OR vault.sh infra failure :302,305|CLAUDE_LEDGER_FILE, CLAUDE_VAULT_DIR
install-routine-timers.sh|daily-docs 07:10, nightly-observation 02:05, weekly-improve Sun 22:06|0;1 no live routine-run.sh :100;2 arg
routine-run.sh|claude -p, SKILL.md on stdin (--- = option) :224-238|0;1 bad task/lock held :217-219;2 no jq;N = claude's own exit code propagated :249|CLAUDE_BIN, CLAUDE_ROUTINE_*|launchd
rotate-signals.sh|archive+trim signals.jsonl|0;1 refused;2 error;3 continuity unproven|CLAUDE_SIGNALS_FILE, _ARCHIVE_DIR|nightly-observation
compute-daily-metrics.sh|daily-metrics row from shard, idempotent|0;1 bad shard;2 args|CLAUDE_METRICS_FILE, _ARCHIVE_DIR|nightly-observation
backfill-daily-metrics-provenance.sh|one-off IMP-111 backfill|0;1 gate;2 inputs|HOME fixed :22-25|none
ledger-append-proposed.sh|proposed-only ledger entries from stdin JSONL|0;1 any block aborts all;2 error|CLAUDE_LEDGER_FILE|nightly, weekly
parallel-claim.sh|mkdir-atomic file locks (claim, bind, release)|claim 0/2;bind 0/1;usage 2|CLAUDE_LOCK_ROOT, _LOCK_TTL_SECS|lock hooks
restore-drill.sh|shallow-clone origin, check restore surface|0;1 gap;2 no URL/clone|CLAUDE_RESTORE_REPO_URL, _KEEP
security-review-findings.sh|findings from security-review sessions|0;1 usage/pairing;2 no jq|CLAUDE_SEC_FINDINGS_*|security-findings-check
backport-pr.sh|public PR to local backport branch, no push|0;1 abort
rcode-units.sh|R.Code gather (JSON stdout): workflow.md|0;1 prerequisite;2 usage||status-metrics, phase-gate-check, resume-state
status-metrics.sh|R.Code gather /status-sync: workflow.md|0;1;2|CLAUDE_STALE_DAYS=14|/status-sync
phase-gate-check.sh|R.Code gather /phase-gate: workflow.md|0;1;2||/phase-gate
resume-state.sh|R.Code gather /continue: workflow.md|0;1;2||/continue
deploy 1|jq :56; root = CLAUDE_WORKSHOP_ROOT else dirname(CLAUDE_BAUHOF_ROOT); both unset: source ~/.claude/env.local.sh, else ABORT :63-74
deploy 2|[config/cockpit/all] default all; cockpit skips the gate :398; root = PARENT of repos claude-code-config, cockpit :400-407
deploy 3|gate IMP-243, before any write :249-276: ws clean (untracked too), branch main, runner green, env -u CLAUDE_TEST_*
deploy 4|skip: CLAUDE_DEPLOY_SKIP_{TESTS=1,REASON=non-blank}, else ABORT; logged live global-observation/deploy-skips.log :251-262
deploy 5|.git in ws+live; live remote workshop (unchecked :363); ws clean :308; live diff beyond settings.json+volatile ABORTs :315-328
deploy 6|runtime keys live to ws in own commit, first :102,171-237: model, effortLevel, theme, permissions.defaultMode, modelSettings
deploy 7|live-only autoMode :119 never to ws/abort, 0600 backup :347; volatile :128: plugins/installed_plugins.json, known_marketplaces.json
deploy 8|git checkout -- . if dirty :357; git pull --ff-only workshop main :363 (no merge); restore volatile+autoMode :366-382
deploy 9|before!=after: config overwrites ~/.claude/pending-verification.md (+skip WARNING) :284-297; cockpit then npm install :413
deploy 10|exit: fail() 1, set -e codes, 0 :416. Rollback manual only: git -C ~/.claude reset --hard <before-sha>
deploy 11|unverified: failed pull leaves live reset. claude-deploy = alias named in WORKING-IN-THIS-REPO.md:302, defined in no repo file
lint args|[--root dir] [commands-dir], default ~/.claude/commands (--root alone: <root>/commands); --root=x read as dir :99-121
lint M|line `<!-- controller-contract:v1` required :231; same line may carry exempt="reason" (empty = none): skips 1-3, never 4-9
lint 1|model: frontmatter = opus/sonnet/haiku/fable[1m] or claude-<tier>-<ver> (CLAUDE_CONTRACT_MODEL_RE) :132,242
lint 2|frontmatter has word Task/TaskCreate/TaskUpdate :279
lint 3|whole file has Controller-First, "Effort per spawn.*agents/control-agent.md.*§2", Second-order checkpoints :255-271
lint 4|no excessive-agency-gate.md/autonomy-arbiter.md/ux-agent/frontend-agent :134,196; same-line archiv/superseded/retired/ersetzt passes
lint 5|each **<name>-agent** needs $HOME/.claude/agents/<name>.md :130,296 (ignores --root)
lint 6|--root only: bash scripts/<phase-gate-check/status-metrics/resume-state>.sh :142; same-line `<!-- lint:allow -->` exempts 6-9
lint 7|--root only: bare /review (real: /rcode-review) :143
lint 8|--root only: "$name:letter, quote directly before $ (zsh modifier) :144
lint 9|--root only: backtick path starting commands/ rules/ agents/ templates/ scripts/ skills/ rcode/ :145; .claude/ and ~/.claude/ pass
lint scope|default: commands-dir/*.md, M,1-5. --root adds rcode/**/*.md, skills/rcode-*/SKILL.md, skills/scope-check/SKILL.md (4,6-9) :320
lint exit|0 pass; 1 any failure, missing dir, zero *.md :208,313,353. Callers: stop-batched-checks.sh:145, audit-config.sh:177, /meta, skill
lint runtime|old per-line loop 45.7-156 s :151-155, now whole-file greps (unmeasured); stop hook: timeout 90, expiry = unverified :157-160
run args|--workshop/--live/--filter/--list; hooks/tests/*.sh + scripts/tests/*.sh, *.bak* skipped :105-115
run sandbox|stdin /dev/null, timeout CLAUDE_SUITE_TIMEOUT=300 :62; HOME=mktemp, .claude/ links root minus .git/global-observation :143-156
run env|CLAUDE_* removed except CLAUDE_SUITE_TIMEOUT, CLAUDE_TEST_*; GATE_TESTMODE unset :169-174; CLAUDE_HOOK/_SETTINGS per suite :85-91
run status|SUSPECT = exit 0 + empty log or line starting RED/FAIL :195-196, counts FAIL; TIMEOUT kills the process group :181-187
run exit|0 only if no FAIL/TIMEOUT/SUSPECT and >=1 PASS :246-250; 1 else or 0 suites :116-120; 2 usage; 130 signal
run linux|skips :75-79: background-watchdog, routine-liveness, session-end-staleness (BSD date), logbook-count-symlink
CI tests.yml|push+PR, ubuntu, 30 min; jq rsync gawk; stat shim maps stat -f %m/%Lp, loud on others; runner --workshop
CI others|scrub-check.yml: push+PR, scrub-check.sh, no permissions block. pr-guard.yml: PR, public mirror only :47,69, always fails
install.sh|--mode auto/fresh/overwrite/augment, --yes, --dry-run (augment only), CLAUDE_DIR; --yes = DEFAULT :128-137, abort stays :728
install.sh auto|empty = fresh; origin=public: pull --ff-only, divergence asks even with --yes :767-793; else scan+recommend
install.sh fresh|in place if in target clone :352 else backup+clone; 3 overlays, chmod, rm settings.framework.json :403; overwrite = backup+fresh
install.sh augment|clone only; NEW-only templates/rcode/scripts :688; settings hook-merge only, backup :604
install.ps1|fresh/overwrite only; in-repo run never clones into target :29-31; backs up without confirm :44-48; no augment
audit-config.sh:62 vs settings.json:500|audit flags theme CRITICAL; deploy-to-live.sh:102 lists it as runtime key (verified 2026-10-03)
audit-config.sh:111 vs lint:279|audit flags TaskCreate/TaskUpdate invalid only in agents/*.md tool lists (:115-125); linter accepts Task|TaskCreate|TaskUpdate in commands/*.md frontmatter: tension, not a direct conflict
deploy-to-live.sh:243-246, :63-74|pull-back commit lands untested; BAUHOF_ROOT = working copy, WORKSHOP_ROOT = parent (template :20,25)
command-contract-lint-regression.sh:214|real-tree pass only with LINT_REGRESSION_TREE_ROOT: no suite lints the live tree
suite (hooks/tests + scripts/tests; -regression.sh implied)|pins|suite|pins|suite|pins|suite|pins
-|-|-|-|-|-|-|-
security-review-findings-vault|--to-ledger token|session-end-staleness|stalled alarm|git-hooks|installer, hooks|vault|vault.sh, lib.sh
logbook-count-symlink|symlinks|chain-probe-imp108.sh|hook chain order|ledger-append|proposed-only|gate|agency+unsafe
session-start-path-canon|path-canon block|read-tool-advisory|once per session|scrub-check|redaction, --staged|run-all-tests|the runner
observation-intent|intent classifier|controller-first|3 controller-first hooks + dispatch-capture.sh|imp-submit|form, --from-ledger|parallel-lock|lock registry
security-findings|script+hook|config-security-audit|CSA rules|serena-gate|write inspectors|deploy|ff, pull-back, gate
governing-path-guard|live-write guard|logbook-count-desktop|logbook-count.sh|rotate-signals|exit 3 cases|routine-run|stdin, lock, timers
read-tracking|read-before-edit|git-bypass-guard|bypass forms|gather-scripts|4 gather scripts|security-audit|PEM/JWT
web-fetch-gate|ASK vs ALLOW|publish-strip|transform 40|background-watchdog|stop states|compute-daily-metrics|shard states
dispatch-specialist|rationale ask|git-state-check|abort passes|command-contract-lint|M,1-9|vault-write-gate|temp-repo gate
publish-manifest|rsync anchoring|routine-liveness|liveness hook
Sources read: scripts/*.sh, scripts/tests, hook-suite headers, installers, workflows, docs; Not verified: any run, hook-suite bodies
