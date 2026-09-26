#!/usr/bin/env bash
# gate-regression.sh — IMP-076 regression suite for the two bash safety gates.
#
# Runs excessive-agency-gate.sh and guard-unsafe.sh DIRECTLY with synthetic
# PreToolUse JSON on an ISOLATED $HOME (mktemp), so test runs never pollute
# ~/.claude/global-observation logs and never consume real ack tokens.
#
# Usage:  bash ~/.claude/hooks/tests/gate-regression.sh
# Exit:   0 = all assertions pass, 1 = failures (listed on stdout)
#
# Add a case for EVERY gate bug fixed — this file is the behavior pin that
# CLAUDE_GATE_TESTMODE was always meant to serve (the tests it anticipated
# were never written until the 2026-07-03 metareview reproduced IMP-040's
# residual false-positive class live).

set -u
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTHOME="$(mktemp -d)"
mkdir -p "$TESTHOME/.claude/global-observation"
trap 'rm -rf "$TESTHOME"; rm -f "/tmp/agency-ack-consumed-acktest-$$"' EXIT
unset CLAUDE_GATE_TESTMODE 2>/dev/null || true

PASS=0; FAIL=0; FAILURES=""

json_cmd() {  # $1 = raw command string -> full hook JSON on stdout
  python3 - "$1" <<'PY'
import json, sys, os
# GATE_TEST_SESS pins the session_id for cases that need a STABLE consumed-token
# store across several asserts (the ACK path, IMP-108) — the getppid() default
# changes per pipeline subshell, so a later assert could never see a token
# consumed by an earlier one.
sess = os.environ.get("GATE_TEST_SESS") or "gate-regression-" + str(os.getppid())
print(json.dumps({"tool_input": {"command": sys.argv[1]}, "session_id": sess}))
PY
}

run_hook() {  # $1 = hook filename, $2 = command string; echoes exit code
  json_cmd "$2" | HOME="$TESTHOME" bash "$HOOKS_DIR/$1" >/dev/null 2>&1
  echo $?
}

assert() {  # $1 = hook, $2 = expectation (ALLOW|BLOCK), $3 = command
  local rc; rc=$(run_hook "$1" "$3")
  local ok=0
  if [ "$2" = "ALLOW" ] && [ "$rc" -eq 0 ]; then ok=1; fi
  if [ "$2" = "BLOCK" ] && [ "$rc" -ne 0 ]; then ok=1; fi
  if [ "$ok" -eq 1 ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [$1] expected $2 (got rc=$rc): $3\n"
  fi
}

# IMP-146: SOFT-ACK expectation — exit 0 (command proceeds) AND a "NOTE" line
# on stderr (the observable self-ack). Isolated $TESTHOME already keeps the
# soft_ack() log write off the real guard-overrides.log; CLAUDE_GUARD_LOG is
# additionally pinned to /dev/null here per the task brief.
run_hook_capture() {  # $1 = hook filename, $2 = command string; sets RC, ERR
  ERR=$(json_cmd "$2" | HOME="$TESTHOME" CLAUDE_GUARD_LOG=/dev/null bash "$HOOKS_DIR/$1" 2>&1 1>/dev/null)
  RC=$?
}

assert_soft_ack() {  # $1 = hook, $2 = command
  run_hook_capture "$1" "$2"
  if [ "$RC" -eq 0 ] && printf '%s' "$ERR" | grep -q "NOTE"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [$1] expected SOFT-ACK (rc=0 + stderr NOTE), got rc=$RC stderr=<$ERR>: $2\n"
  fi
}

EAG=excessive-agency-gate.sh
GUARD=guard-unsafe.sh

# ── excessive-agency-gate: op-name-as-data must be AUTO (IMP-040 + residual) ──
assert $EAG ALLOW "echo 'gh pr merge 5'"
assert $EAG ALLOW "grep -iE 'curl|rm -rf|dd|mkfs' file.txt"          # live repro 2026-07-03
assert $EAG ALLOW "echo 'cmds: curl|rm -rf|dd'"                       # live repro 2026-07-03
assert $EAG ALLOW "grep -r 'DROP TABLE' src/"
assert $EAG ALLOW "echo \"psql -c 'DROP TABLE x'\""

# ── excessive-agency-gate: disposable / relative rm targets stay AUTO ─────────
assert $EAG ALLOW "rm -rf /tmp/foo"
assert $EAG ALLOW "rm -rf node_modules"
assert $EAG ALLOW "rm -rf 'foo bar'"                                  # quoted relative target
assert $EAG ALLOW "rm -rf /tmp/o_*.png"                               # IMP-059 glob-under-tmp
assert $EAG ALLOW "git commit -m 'wip'"

# ── excessive-agency-gate: macOS RESOLVED temp roots stay AUTO (IMP-102) ──────
# /tmp -> /private/tmp, /var/tmp -> /private/var/tmp, /var/folders ->
# /private/var/folders. The session scratchpad handed to sub-agents is the
# resolved form, so a sub-agent cleaning up its own scratch dir hit ESCALATE.
assert $EAG ALLOW "rm -rf /private/tmp/claude-501/scratch"            # resolved /tmp
assert $EAG ALLOW "rm -rf /private/var/tmp/scratch"                   # resolved /var/tmp
assert $EAG ALLOW "rm -rf /private/var/folders/mf/wfd0000gn/T/scratch"  # resolved $TMPDIR
assert $EAG ALLOW "rm -rf /private/tmp/o_*.png"                       # glob under resolved tmp

# ── excessive-agency-gate: genuine irreversible ops must ESCALATE ─────────────
assert $EAG BLOCK "gh pr merge 5"
assert $EAG BLOCK "FOO=bar gh pr merge 5"                             # env-prefix dodge
assert $EAG BLOCK "rm -rf /etc/nginx"
assert $EAG BLOCK "rm -rf ~/stuff"
assert $EAG BLOCK "rm -rf ../x"                                       # parent traversal
assert $EAG BLOCK "psql -c \"DROP TABLE users;\""                     # SQL runner at head
assert $EAG BLOCK "git branch -D feature"
assert $EAG BLOCK "git clean -fd"
assert $EAG BLOCK "rm -rf src/*"                                      # non-tmp glob
assert $EAG BLOCK "kubectl delete pod x"

# ── excessive-agency-gate: /private is NOT wholesale auto-pass (IMP-102) ──────
# The temp fix adds three EXACT prefixes, never /private/*. These pin that.
assert $EAG BLOCK "rm -rf /private/etc/nginx"                         # /private/etc stays escalated
assert $EAG BLOCK "rm -rf /private/var/db/stuff"                      # /private/var/db stays escalated
assert $EAG BLOCK "rm -rf /private/var/root/x"                        # /private/var/* is not /var/tmp
assert $EAG BLOCK "rm -rf /private"                                   # the bare root itself
assert $EAG BLOCK "rm -rf /private/tmpfoo"                            # prefix must end on a path boundary
assert $EAG BLOCK "rm -rf /private/tmp/../etc"                        # traversal out of the temp root
assert $EAG BLOCK "rm -rf /private/tmp/x/.git"                        # dotpath guard outranks temp AUTO
assert $EAG BLOCK "rm -rf /private/tmp/x/.env"                        # ditto — temp root is no shelter

# ── excessive-agency-gate: env-prefix with SPACED substitution values (IMP-108) ──
# Live bypass 2026-07-26: `GH_TOKEN=$(gh auth token --user X) gh release create`
# ran UNBLOCKED. CP's env-assignment tolerance used \S* for the value, which stops
# at the first space INSIDE $(…)/${…}/`…` — the assignment loop then dies on the
# next word and the real command head is never reached → AUTO instead of ESCALATE.
assert $EAG BLOCK 'GH_TOKEN=$(gh auth token --user example-maintainer) gh release create v1.0.2'  # the live finding
assert $EAG BLOCK 'FOO=1 BAR=$(cmd with spaces) gh pr merge 1'        # multi-prefix, spaced subst
assert $EAG BLOCK 'FOO=1 BAR=$(cmd) gh pr merge 1'                    # space-free subst (already worked — pin)
assert $EAG BLOCK 'A="x y" B=$(c d) gh workflow disable ci.yml'       # quoted + subst value mix
assert $EAG BLOCK 'V=`tick tock` gh pr close 7'                       # backtick value with spaces
assert $EAG BLOCK 'X=${VAR:-a b} gh pr merge 2'                       # spaced ${…} expansion value
assert $EAG ALLOW 'echo "gh release create"'                          # op name as data (control)
assert $EAG ALLOW 'FOO=$(x) echo "gh pr merge"'                       # env-prefix + op-as-data stays data

# ── excessive-agency-gate: $( opens a command position (IMP-108 hardening) ─────
# A command substitution EXECUTES its content — `V=$(gh pr merge 1) x` performs
# the merge while parsing as a mere assignment. Backticks are deliberately NOT
# anchors (open and close are indistinguishable; anchoring both would FP on
# `echo \`date\` gh pr merge`, where the op is data AFTER the substitution).
assert $EAG BLOCK 'V=$(gh pr merge 1) true'                           # op executes inside the value
assert $EAG BLOCK 'echo $(gh release create v1 --title t)'            # subst head inside outer command
assert $EAG ALLOW 'echo $(date) gh pr merge'                          # after the subst, args are data
assert $EAG ALLOW 'echo $(rm -rf /tmp/x) done'                        # subst-anchored rm keeps temp allowlist
assert $EAG BLOCK 'V=$(rm -rf /etc) true'                             # subst-anchored rm, critical target

# ── excessive-agency-gate: ACK-token path across the env-prefix fix (IMP-108) ──
# First ACK regression in this suite. Harvest the advertised sig from a real
# block, then: (1) the advertised env-prefixed re-run line ALLOWS once, (2) a
# replay re-blocks (before IMP-108 the prefixed re-run sailed through as
# unmatched AUTO — the token was never validated OR consumed), (3) a token bound
# to another op re-blocks (ack-mismatch).
GATE_TEST_SESS="acktest-$$"; export GATE_TEST_SESS
rm -f "/tmp/agency-ack-consumed-$GATE_TEST_SESS" 2>/dev/null
ACK_CMD='GH_TOKEN=$(gh auth token --user example-maintainer) gh release create v1.0.2'
ACK_SIG=$(json_cmd "$ACK_CMD" | HOME="$TESTHOME" bash "$HOOKS_DIR/$EAG" 2>&1 >/dev/null \
          | grep -oE 'CLAUDE_AGENCY_ACK_ONCE=[A-Fa-f0-9]{64}' | head -1 | cut -d= -f2)
if [ -n "$ACK_SIG" ]; then
  assert $EAG ALLOW "CLAUDE_AGENCY_ACK_ONCE=$ACK_SIG $ACK_CMD"        # user-approved re-run, once
  assert $EAG BLOCK "CLAUDE_AGENCY_ACK_ONCE=$ACK_SIG $ACK_CMD"        # replay → single-use re-block
  assert $EAG BLOCK "CLAUDE_AGENCY_ACK_ONCE=$ACK_SIG gh pr merge 99"  # op-bound → mismatch re-block
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [$EAG] ACK harvest: no sig advertised for env-prefixed op (gate did not ESCALATE): $ACK_CMD\n"
fi
unset GATE_TEST_SESS

# ── excessive-agency-gate: global machine/account-identity changes ESCALATE
# (IMP-163, 2026-08-24). `gh auth switch --user <account>` ran once without
# a y/n and was reported only afterward; 3 documented wrong-repo/wrong-deploy-
# account incidents trace to exactly this class. Repo-local / read-only forms
# must stay AUTO — that distinction is the whole point of the fix.
assert $EAG BLOCK "gh auth switch --user someuser"
assert $EAG BLOCK "vercel switch someteam"
assert $EAG BLOCK "git config --global user.email 'user@example.com'"
assert $EAG BLOCK "npm config set registry https://registry.npmjs.org -g"
assert $EAG BLOCK "npm config set registry https://registry.npmjs.org --global"
# IMP-163-followup (2026-09-09): --location=global / --location global are npm's
# own documented equivalent of -g/--global (npm-config(1) `location`: "Default:
# 'user' unless --global is passed, which will also set this value to
# 'global'") — they write the SAME global npmrc and had silently bypassed this
# gate (measured: exit 0 before this fix, exit 2 for -g/--global on the
# identical command). -L is npm's short flag for --location; pinned too since
# the fix covers it structurally.
assert $EAG BLOCK "npm config set registry https://registry.npmjs.org --location=global"
assert $EAG BLOCK "npm config set registry https://registry.npmjs.org --location global"
assert $EAG BLOCK "npm config set registry https://registry.npmjs.org -L global"
assert $EAG BLOCK "gcloud config set account someone@example.com"
assert $EAG BLOCK "aws configure"
assert $EAG BLOCK "aws configure --profile prod"
assert $EAG ALLOW "git config user.email 'user@example.com'"                  # local (repo-scoped) — everyday, must NOT block
assert $EAG ALLOW "gh auth status"                                    # read-only
assert $EAG ALLOW "git config --global --get user.email"             # global READ stays AUTO
assert $EAG ALLOW "git config --global -l"                            # global list stays AUTO
assert $EAG ALLOW "aws configure list"                                # read-only
assert $EAG ALLOW "aws configure get region"                          # read-only
assert $EAG ALLOW "npm config get registry"                           # get, not set -g
assert $EAG ALLOW "npm config set registry https://registry.npmjs.org"  # set WITHOUT -g stays AUTO
# --location=project writes the PROJECT-local .npmrc, not the global one — the
# documented (npm-config(1)) reason -g/-L=global and --location=project must
# diverge; the fix above must not have collapsed them into one class.
assert $EAG ALLOW "npm config set registry https://registry.npmjs.org --location=project"
assert $EAG ALLOW "npm config list --global"                          # list/read of global scope stays AUTO (not `set`)

# ── excessive-agency-gate: IMP-163-followup (2026-08-24 + 2026-09-09 security-
# review findings) — the bypass family that survived the fix above:
#   (a) quote-tolerant value bypass — strip_data() erases QUOTED VALUES before
#       the --location/-L regex runs, so `--location='global'` read as
#       `--location=` and never matched (measured: exit 0, vs. exit 2 for the
#       unquoted `--location=global` on an otherwise-identical command).
#   (b) flag-before-subcommand bypass — aws/gcloud/vercel/npm all accept a
#       global option BETWEEN the binary and the subcommand; every ESCALATE
#       check below required strict "<tool> <subcommand>" adjacency and was
#       trivially defeated by inserting any such flag.
#   (c) git config's other outside-repo write scopes — `--system` (writes
#       /etc/gitconfig) and `--file <path>`/`-f <path>` (writes to ANY
#       attacker-chosen path, trivially the user's own ~/.gitconfig) have the
#       identical effect to `--global` and were not checked at all.
# All eleven measured exit=0 before this fix; all eleven now exit=2.
assert $EAG BLOCK "npm config set registry https://registry.npmjs.org --location='global'"   # (a) single-quoted value
assert $EAG BLOCK 'npm config set registry https://registry.npmjs.org --location="global"'   # (a) double-quoted value
assert $EAG BLOCK "npm config set registry https://registry.npmjs.org -L 'global'"           # (a) quoted short-flag value
assert $EAG BLOCK "npm -g config set registry https://registry.npmjs.org"                    # (b) flag BEFORE subcommand
assert $EAG BLOCK "npm --global config set registry https://registry.npmjs.org"              # (b) long flag BEFORE subcommand
assert $EAG BLOCK "aws --profile default configure set aws_access_key_id AKIAEXAMPLE"        # (b) intervening --profile
assert $EAG BLOCK "gcloud --verbosity=none config set account attacker@example.com"           # (b) intervening --verbosity=…
assert $EAG BLOCK "vercel --debug switch other-team"                                          # (b) intervening --debug
assert $EAG BLOCK "git config --file ~/.gitconfig user.email attacker@example.com"               # (c) --file to an outside-repo path
assert $EAG BLOCK "git config -f ~/.gitconfig user.email x"                                   # (c) -f short form
assert $EAG BLOCK "git config --system user.email x"                                          # (c) machine-wide /etc/gitconfig

# ── excessive-agency-gate: IMP-163-followup — the same fix must NOT widen the
# gate. Read-only / repo-local / non-config-set / op-as-data forms stay AUTO.
assert $EAG ALLOW "npm config get registry -g"                        # -g on a GET, not a set, stays AUTO
assert $EAG ALLOW "git config --get user.email"                       # repo-local get (no --global at all)
assert $EAG ALLOW "git config --list"                                 # repo-local list (no --global at all)
assert $EAG ALLOW "git config --system --list"                        # --system's own read-only exclusion
assert $EAG ALLOW "gcloud config list"                                # gcloud read, not config set account
assert $EAG ALLOW "vercel ls"                                         # unrelated vercel subcommand
assert $EAG ALLOW 'echo "npm -g config set x"'                        # op text as echoed DATA, not executed
assert $EAG ALLOW "grep -- '--location=global' file"                  # flag text as grep DATA, not executed

# ── excessive-agency-gate: ACK-token path across the IMP-163-followup fix ────
# Same three-part contract as the IMP-108 ACK block above (harvest → allow-once
# → replay-reblocks → mismatch-reblocks), exercised against one of the newly-
# closed forms so the token contract is proven for THIS fix, not just IMP-108's.
GATE_TEST_SESS="acktest163-$$"; export GATE_TEST_SESS
rm -f "/tmp/agency-ack-consumed-$GATE_TEST_SESS" 2>/dev/null
ACK163_CMD='npm -g config set registry https://registry.npmjs.org'
ACK163_SIG=$(json_cmd "$ACK163_CMD" | HOME="$TESTHOME" bash "$HOOKS_DIR/$EAG" 2>&1 >/dev/null \
          | grep -oE 'CLAUDE_AGENCY_ACK_ONCE=[A-Fa-f0-9]{64}' | head -1 | cut -d= -f2)
if [ -n "$ACK163_SIG" ]; then
  assert $EAG ALLOW "CLAUDE_AGENCY_ACK_ONCE=$ACK163_SIG $ACK163_CMD"        # user-approved re-run, once
  assert $EAG BLOCK "CLAUDE_AGENCY_ACK_ONCE=$ACK163_SIG $ACK163_CMD"        # replay → single-use re-block
  assert $EAG BLOCK "CLAUDE_AGENCY_ACK_ONCE=$ACK163_SIG git config --system user.email x"  # op-bound → mismatch re-block
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [$EAG] ACK harvest: no sig advertised for npm -g config set (gate did not ESCALATE): $ACK163_CMD\n"
fi
unset GATE_TEST_SESS

# ── guard-unsafe: op-name-as-data must pass (mkfs substring FP, 2026-07-03) ──
assert $GUARD ALLOW "grep -n 'mkfs|fdisk' hooks/guard-unsafe.sh"      # live repro 2026-07-03
assert $GUARD ALLOW "echo 'mkfs is dangerous'"
assert $GUARD ALLOW "python3 -c \"print('mkfs')\""
assert $GUARD ALLOW "git status"

# ── guard-unsafe: disposable temp roots pass the CRITICAL floor (IMP-103) ────
# This arm runs FIRST in the chain, so before IMP-103 it blocked EVERY absolute
# recursive force-delete — including /tmp — which made the excessive-agency-gate's
# temp allowlist (IMP-059 glob-under-tmp, IMP-102 resolved roots) unreachable for
# absolute targets: the floor blocked them before that gate ever ran.
assert $GUARD ALLOW "rm -rf /tmp/foo"
assert $GUARD ALLOW "rm -rf /private/tmp/claude-501/sess/scratchpad"  # the reported case
assert $GUARD ALLOW "rm -rf /var/tmp/scratch"
assert $GUARD ALLOW "rm -rf /private/var/tmp/scratch"
assert $GUARD ALLOW "rm -rf /private/var/folders/mf/wfd0000gn/T/scratch"
assert $GUARD ALLOW "rm -rf /tmp/foo && rm -rf node_modules"          # temp + relative

# ── guard-unsafe: real disk/priv-escalation ops must BLOCK ────────────────────
assert $GUARD BLOCK "mkfs.ext4 /dev/sda1"
assert $GUARD BLOCK "fdisk /dev/sda"
assert $GUARD BLOCK "sudo ls"
assert $GUARD BLOCK "rm -rf ~"                                        # CRITICAL floor

# ── guard-unsafe: the floor still holds for everything else (IMP-103) ─────────
assert $GUARD BLOCK "rm -rf /"                                        # the floor's whole point
assert $GUARD BLOCK "rm -rf /etc/nginx"
assert $GUARD BLOCK "rm -rf /private/etc/nginx"                       # no /private/* widening
assert $GUARD BLOCK "rm -rf /private/var/db/stuff"
assert $GUARD BLOCK "rm -rf /usr/local/lib"
assert $GUARD BLOCK "rm -rf ~/stuff"
assert $GUARD BLOCK "rm -rf \$HOME/stuff"
assert $GUARD BLOCK "rm -rf *"                                        # bare-wildcard arm intact
assert $GUARD BLOCK "rm -rf /tmpfoo"                                  # boundary, not prefix
assert $GUARD BLOCK "rm -rf /tmp/../etc"                              # traversal out of temp
assert $GUARD BLOCK "rm -rf /tmp/foo && rm -rf /etc"                  # temp + critical together

# ── guard-unsafe: IMP-106 command-position fix — prose/data must ALLOW ────────
# Empirically verified 2026-08-22: several CRITICAL-floor arms matched a
# dangerous substring ANYWHERE in the raw command, including inside quoted
# prose, grep patterns, and heredoc message bodies. guard_normalize_command()
# (hooks/lib/normalize-command.sh) strips heredoc bodies + quoted spans before
# these arms run, so the arms now see only what actually EXECUTES.
HEREDOC_RM_MSG="git commit -F - <<EOF
doc: rm -rf ~ is dangerous
EOF"
assert $GUARD ALLOW "$HEREDOC_RM_MSG"                                 # rm -rf inside a heredoc commit message
assert $GUARD ALLOW "git commit -m 'doc: rm -rf /etc is deadly'"      # rm -rf inside a quoted commit message
assert $GUARD ALLOW 'echo "rm -rf /"'                                 # rm -rf as an echoed string
assert $GUARD ALLOW "echo 'never run rm -rf \$HOME'"                  # rm -rf as an echoed string (single-quoted)
assert $GUARD ALLOW "grep 'rm -rf /' README.md"                       # rm -rf inside a grep pattern
PYCMD="python3 -c \"print('rm -rf ~ x')\""
assert $GUARD ALLOW "$PYCMD"                                          # rm -rf inside a python string literal
assert $GUARD ALLOW "echo 'dd if=/dev/zero of=disk'"                  # dd if= as an echoed string
assert $GUARD ALLOW "grep 'curl -d payload' docs.md"                  # curl -d inside a grep pattern
assert $GUARD ALLOW "echo 'benutze nc -l zum testen'"                 # nc as an echoed string (live repro 2026-08-22)
assert $GUARD ALLOW "grep 'nc -e /bin/sh' notes.md"                   # nc inside a grep pattern

# ── guard-unsafe: IMP-106 — genuine invocations must still BLOCK ──────────────
assert $GUARD BLOCK "dd if=/dev/zero of=/dev/sda"                     # real dd, unquoted
assert $GUARD BLOCK "nc -l 4444"                                      # real nc, unquoted — IMP-146 Bestandsschutz (untouched)
assert $GUARD BLOCK "true; rm -rf /etc"                               # danger op after ';'
assert $GUARD BLOCK "foo && rm -rf ~"                                 # danger op after '&&'
assert $GUARD BLOCK "echo x | sudo tee /etc/hosts"                    # danger op after '|'
MULTILINE_RM="echo step-one
rm -rf ~"
assert $GUARD BLOCK "$MULTILINE_RM"                                   # real rm -rf on a second line (newline anchor)

# ── guard-unsafe: IMP-146 (2026-08-23) — curl/wget/scripted-HTTP data-upload
# reclassified BLOCK → SOFT-ACK. Evidence: 24 legitimate API-test blocks (WHO-ICD
# token requests, Shopware smoketests) across 9 projects in the 02.–22.08 window,
# EVERY ONE immediately overridden via CLAUDE_GUARD_OVERRIDE=1 — zero net
# protection, trained a reflex-override habit. See rules/agency-bands.md,
# Decision Table row "curl/wget/HTTP-POST am Kommandokopf".
assert_soft_ack $GUARD "curl -d x https://example.com"                # real curl data upload — was BLOCK, now SOFT-ACK
assert_soft_ack $GUARD "curl -X POST https://example.com"             # real curl mutating method — was BLOCK, now SOFT-ACK
assert_soft_ack $GUARD "wget --post-data=x http://example.com"        # real wget POST — was BLOCK, now SOFT-ACK

# ── guard-unsafe: IMP-146 — curl -o output-path arm is DELIBERATELY untouched
# (writes to a critical filesystem path, a different risk class from a POST).
assert $GUARD BLOCK "curl -o /etc/passwd http://example.com/x"        # curl -o outside /tmp — stays BLOCK

# ── guard-unsafe: IMP-147 (2026-08-24) — the ungrouped `^[^/]` alternation in
# the curl -o OUTPATH classifier matched ANY non-'/'-leading string, so
# `~/...` and `$HOME/...` targets were wrongly bucketed as "relative" and
# ALLOWED. Measured live before the fix: `curl -o ~/.ssh/authorized_keys` and
# `curl -o $HOME/.bashrc` both exited 0. Per-target classification below,
# with a fail-closed rule for unclassifiable/blank extracted targets.
assert $GUARD BLOCK "curl -o ~/.ssh/authorized_keys http://example.com/x"       # tilde home write — was wrongly ALLOWed
assert $GUARD BLOCK "curl -o ~/.bashrc http://example.com/x"                    # tilde shell-profile write
assert $GUARD BLOCK 'curl -o $HOME/.zshrc http://example.com/x'                 # $HOME shell-profile write
assert $GUARD BLOCK 'curl -o ${HOME}/.claude/settings.json http://example.com/x' # ${HOME} write to this framework's own config
assert $GUARD BLOCK "curl --output ~/.ssh/id_rsa http://example.com/x"          # --output long-flag form, tilde target
assert $GUARD BLOCK "curl -o /dev/null -o /etc/x http://example.com/x"          # two -o targets, one critical — must not depend on match order
assert $GUARD ALLOW "curl -o /dev/null http://example.com/x"                    # IMP-047: discard sink, not a written file
assert $GUARD ALLOW "curl -o - http://example.com/x"                            # '-' = stdout
assert $GUARD ALLOW "curl -o ./out.txt http://example.com/x"                    # genuine relative path
assert $GUARD ALLOW "curl -o out.txt http://example.com/x"                      # bare relative filename
assert $GUARD ALLOW "curl -o dist/bundle.js http://example.com/x"               # relative path into a project subdir
assert $GUARD ALLOW "curl -o /tmp/x.json http://example.com/x"                  # disposable temp root
assert $GUARD ALLOW 'curl -s -o /dev/null -w "HTTP %{http_code}\n" https://example.com'  # real-world smoke-test shape

# ── guard-unsafe: IMP-148 (2026-08-24) — the IMP-147 fix above only covered
# the SPACE-separated `-o PATH` / `--output PATH` forms. curl's own
# short-option parser also accepts the CUDDLED no-space form (`-oPATH`),
# which reached real execution unblocked (measured: `curl -o/etc/passwd
# http://x` exited 0 before this fix). `-o=PATH` was checked live rather
# than assumed: curl's short-option parser does NOT treat '=' as a
# separator, so `-o=/etc/passwd` writes to a file literally named
# "=/etc/passwd" in the CWD (relative, harmless) — not to /etc/passwd —
# and is correctly ALLOWed by design, not by omission. `--output=PATH`
# (long-option '=' form) was also checked live: this curl build rejects
# ALL `--longopt=value` syntax outright ("is unknown"), so the command
# never executes either way; coverage is added anyway as defense-in-depth.
assert $GUARD BLOCK "curl -o/etc/passwd http://example.com/x"                   # cuddled short form, absolute critical path
assert $GUARD BLOCK "curl -o~/.ssh/authorized_keys http://example.com/x"        # cuddled short form, tilde home write
assert $GUARD BLOCK "curl --output=/etc/shadow http://example.com/x"            # long-option '=' form (curl rejects it; defense-in-depth)
assert $GUARD BLOCK 'curl -o$HOME/.zshrc http://example.com/x'                  # cuddled short form, $HOME write
assert $GUARD ALLOW "curl -o- http://example.com/x"                             # cuddled '-' = stdout
assert $GUARD ALLOW "curl -o/dev/null http://example.com/x"                     # cuddled /dev/null discard sink
assert $GUARD ALLOW "curl -o./out.txt http://example.com/x"                     # cuddled genuine relative path
assert $GUARD ALLOW "curl -odist/bundle.js http://example.com/x"                # cuddled bare relative path
assert $GUARD ALLOW "curl -O https://example.com/datei.tar.gz"                  # -O takes no path argument — unchanged, always CWD-relative
assert $GUARD ALLOW "curl -o=/etc/passwd http://example.com/x"                  # verified: curl writes literal "=/etc/passwd" (relative), not /etc/passwd
assert $GUARD ALLOW "curl --output-dir /tmp -O https://example.com/f.zip"       # --output-dir must not false-trigger the --output=/-o matchers

# ── guard-unsafe: IMP-157 (2026-08-24, second half) — the cat/head/tail
# file-read BLOCK arm is REMOVED (category error at the CRITICAL floor — see
# the "REMOVED (IMP-157...)" comment in guard-unsafe.sh). Measured: 9
# confirmed false blocks across 8 sessions over two months, incl. blocking a
# sub-agent from reading its own scratchpad task output. These pins lock in
# that plain file reads now pass unconditionally; the advisory note that
# replaced the block lives in a SEPARATE hook
# (read-tool-preference-advisory.sh), tested in its own regression suite.
assert $GUARD ALLOW "cat datei.txt"                                             # bare cat — was BLOCK, now ALLOW
assert $GUARD ALLOW "head -40 README.md"                                        # bare head — was BLOCK, now ALLOW
assert $GUARD ALLOW "tail -c 1200 /private/tmp/x"                               # bare tail (non-follow) — was BLOCK, now ALLOW
assert $GUARD ALLOW "sed -n '5,10p' datei"                                      # sed -n was never matched by this arm — pin as bestandsschutz
assert $GUARD ALLOW "cat rcode/VERSION"                                         # live repro from the chat corpus
assert $GUARD ALLOW 'head -5 LICENSE && echo "---" && head -60 README.md'       # live repro from the chat corpus

# ── guard-unsafe: IMP-157 — the CRITICAL floor itself must still be scharf.
# Re-check 3 pre-existing floor pins from elsewhere in this suite as an
# explicit Bestandsschutz assertion for THIS change (removing the file-read
# arm must not have widened anything else).
assert $GUARD BLOCK "rm -rf /"                                                  # floor Bestandsschutz (also pinned above)
assert $GUARD BLOCK "nc -l 4444"                                                # floor Bestandsschutz (also pinned above)
assert $GUARD BLOCK "dd if=/dev/zero of=/dev/sda"                               # floor Bestandsschutz (also pinned above)

echo "── gate-regression: $PASS passed, $FAIL failed ──"
if [ "$FAIL" -gt 0 ]; then
  printf "%b" "$FAILURES"
  exit 1
fi
exit 0
