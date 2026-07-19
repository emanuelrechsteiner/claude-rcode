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
trap 'rm -rf "$TESTHOME"' EXIT
unset CLAUDE_GATE_TESTMODE 2>/dev/null || true

PASS=0; FAIL=0; FAILURES=""

json_cmd() {  # $1 = raw command string -> full hook JSON on stdout
  python3 - "$1" <<'PY'
import json, sys, os
print(json.dumps({"tool_input": {"command": sys.argv[1]},
                  "session_id": "gate-regression-" + str(os.getppid())}))
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

echo "── gate-regression: $PASS passed, $FAIL failed ──"
if [ "$FAIL" -gt 0 ]; then
  printf "%b" "$FAILURES"
  exit 1
fi
exit 0
