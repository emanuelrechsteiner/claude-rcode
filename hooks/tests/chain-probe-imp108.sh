#!/usr/bin/env bash
# chain-probe-imp108.sh — cross-hook chain probe for the env-prefix bypass fix.
#
# IMP-103 lesson: per-hook suites cannot catch cross-hook ORDERING defects (a
# floor hook blocking before a later gate's allowlist becomes reachable, or a
# gap hook allowing before a later gate fires). This probe therefore runs the
# REGISTERED PreToolUse|Bash chain — order read live from settings.json, never
# hardcoded — against the IMP-108 cases and asserts WHICH hook decides.
#
# Repo copies of the hooks are exercised (so the probe tests the to-be-deployed
# state); the CHAIN ORDER comes from the real registration. A registered hook
# missing from the repo is reported as drift.
#
# Section 2 is the IMP-106 Abgleich: guard-unsafe's ^-anchored arms (sudo, mkfs,
# cat) have the SAME env-prefix gap that IMP-108 closed in the agency gate. Per
# the IMP-108 task brief they are NOT fixed here (IMP-106 owns guard-unsafe's
# position matching) — the KNOWN-GAP expectations below pin today's reality and
# will go RED the day IMP-106 lands, forcing this file to be updated with it.
#
# Usage:  bash ~/.claude/hooks/tests/chain-probe-imp108.sh
# Exit:   0 = all expectations met, 1 = failures listed on stdout

set -u
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
[ -f "$SETTINGS" ] || SETTINGS="$HOOKS_DIR/../settings.json"

TESTHOME="$(mktemp -d)"
mkdir -p "$TESTHOME/.claude/global-observation"
SESS="chainprobe-$$"
trap 'rm -rf "$TESTHOME"; rm -f "/tmp/agency-ack-consumed-$SESS"' EXIT
unset CLAUDE_GATE_TESTMODE 2>/dev/null || true

PASS=0; FAIL=0; FAILURES=""

# ── registered chain order (basenames, in registration order) ─────────────────
CHAIN=()
while IFS= read -r h; do
  CHAIN+=("$(basename "$h")")
done < <(jq -r '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[].command' "$SETTINGS")

if [ "${#CHAIN[@]}" -eq 0 ]; then
  echo "FATAL: no PreToolUse|Bash hooks found in $SETTINGS"; exit 1
fi
echo "registered PreToolUse|Bash chain: ${CHAIN[*]}"
for h in "${CHAIN[@]}"; do
  [ -f "$HOOKS_DIR/$h" ] || { echo "FATAL: registered hook missing in repo: $h (drift)"; exit 1; }
done

json_cmd() {
  python3 - "$1" "$SESS" <<'PY'
import json, sys
print(json.dumps({"tool_input": {"command": sys.argv[1]}, "session_id": sys.argv[2]}))
PY
}

chain_verdict() {  # $1 = command string → "ALLOW" or "BLOCK@<hook>" (first blocker)
  local h rc
  for h in "${CHAIN[@]}"; do
    json_cmd "$1" | HOME="$TESTHOME" bash "$HOOKS_DIR/$h" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then echo "BLOCK@$h"; return; fi
  done
  echo "ALLOW"
}

assert_chain() {  # $1 = expected verdict, $2 = command, $3 = label
  local got; got=$(chain_verdict "$2")
  if [ "$got" = "$1" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [$3] expected $1, got $got: $2\n"
  fi
}

# ── 1) IMP-108 cases through the full registered chain ────────────────────────
assert_chain "BLOCK@excessive-agency-gate.sh" \
  'gh release create v1.0.2 --title t' \
  "chain: plain release create"
assert_chain "BLOCK@excessive-agency-gate.sh" \
  'GH_TOKEN=$(gh auth token --user example-maintainer) gh release create v1.0.2 --title t' \
  "chain: env-subst prefix (the live bypass)"
assert_chain "BLOCK@excessive-agency-gate.sh" \
  'FOO=1 BAR=$(cmd with spaces) gh pr merge 1' \
  "chain: double prefix, spaced subst"
assert_chain "ALLOW" \
  'echo "gh release create"' \
  "chain: op name as data"
assert_chain "ALLOW" \
  'git commit -m wip' \
  "chain: benign git commit"

# ── ACK flow through the chain: harvest sig, approved re-run, replay ──────────
ACK_CMD='GH_TOKEN=$(gh auth token --user example-maintainer) gh release create v1.0.2 --title t'
ACK_SIG=$(json_cmd "$ACK_CMD" \
  | HOME="$TESTHOME" bash "$HOOKS_DIR/excessive-agency-gate.sh" 2>&1 >/dev/null \
  | grep -oE 'CLAUDE_AGENCY_ACK_ONCE=[A-Fa-f0-9]{64}' | head -1 | cut -d= -f2)
if [ -n "$ACK_SIG" ]; then
  assert_chain "ALLOW" \
    "CLAUDE_AGENCY_ACK_ONCE=$ACK_SIG $ACK_CMD" \
    "chain: user-approved ACK re-run"
  assert_chain "BLOCK@excessive-agency-gate.sh" \
    "CLAUDE_AGENCY_ACK_ONCE=$ACK_SIG $ACK_CMD" \
    "chain: ACK replay re-blocks (single-use)"
else
  FAIL=$((FAIL+1)); FAILURES="${FAILURES}  [chain: ACK harvest] no sig advertised for: $ACK_CMD\n"
fi

# ── 2) IMP-106 Abgleich: guard-unsafe ^-anchored arms, env-prefixed ───────────
# CORRECTION (2026-08-22): IMP-106's actual scope was the SUBSTRING-ANYWHERE
# defect (a dangerous op matched even INSIDE quoted prose/heredoc data — echo
# 'rm -rf /', grep 'curl -d ...', a heredoc commit body). It did NOT extend
# guard-unsafe's sudo/mkfs/cat arms with env-assignment-prefix tolerance —
# that is a DIFFERENT, narrower defect class (the anchor is command-position
# correct but doesn't tolerate a leading `FOO=value` the way
# excessive-agency-gate.sh's CP/ENV_VAL does) and stays a documented KNOWN-GAP
# below, unchanged by this pass.
assert_chain "BLOCK@guard-unsafe.sh" 'sudo id'                    "guard: plain sudo blocks"
assert_chain "ALLOW"                 'FOO=1 sudo id'              "guard KNOWN-GAP: env-prefix dodges ^sudo (not in IMP-106 scope)"
assert_chain "ALLOW"                 'FOO=$(a b) sudo id'         "guard KNOWN-GAP: subst-prefix dodges ^sudo (not in IMP-106 scope)"
assert_chain "BLOCK@guard-unsafe.sh" 'mkfs.ext4 /dev/sda1'        "guard: plain mkfs blocks"
assert_chain "ALLOW"                 'FOO=1 mkfs.ext4 /dev/sda1'  "guard KNOWN-GAP: env-prefix dodges mkfs arm (not in IMP-106 scope)"
assert_chain "BLOCK@guard-unsafe.sh" 'rm -rf /etc/x'              "guard: rm arm blocks at command position"

# IMP-106 gave the rm-critical arm the SAME command-position anchor as mkfs
# (`(^|[;&|\n])[[:space:]]*rm`, per the task brief — no ENV_VAL tolerance was
# specified or implemented). A `FOO=$(a b) rm -rf /etc/x` prefix therefore now
# ALSO dodges guard-unsafe's rm arm, exactly like it already dodged sudo/mkfs
# above — this is a BEHAVIOR CHANGE from before this pass (previously
# guard-unsafe's rm arm was an unanchored substring match and DID catch this).
# The overall chain still BLOCKS: excessive-agency-gate.sh's env-prefix-aware
# classify_rm (IMP-108) catches it one hook later. Net effect: no hole opened,
# but the CRITICAL floor is no longer the layer that stops this specific
# shape — flagged here rather than silently re-pinned.
assert_chain "BLOCK@excessive-agency-gate.sh" 'FOO=$(a b) rm -rf /etc/x' \
  "guard KNOWN-GAP(IMP-106): env-prefix dodges the now-anchored rm arm too; excessive-agency-gate still blocks"

# ── 3) IMP-106 full-chain sanity: prose must ALLOW, real ops must BLOCK@guard-unsafe ──
assert_chain "ALLOW" \
  "git commit -m 'doc: rm -rf /etc ist tödlich'" \
  "chain: rm -rf as prose in a commit message — no hook in the chain should block"
assert_chain "ALLOW" \
  "echo 'benutze nc -l zum testen'" \
  "chain: nc as prose in an echoed string — no hook in the chain should block"
assert_chain "BLOCK@guard-unsafe.sh" \
  'nc -l 4444' \
  "chain: real nc invocation — guard-unsafe (CRITICAL floor) blocks first"
# IMP-146 (2026-08-23): curl data-upload reclassified BLOCK → SOFT-ACK in
# guard-unsafe.sh (24 legitimate API-test blocks in 3 weeks, every one reflex-
# overridden — zero net protection). No other hook in the chain classifies
# curl, so the full-chain verdict is now ALLOW. chain_verdict() only reads
# exit codes, not stderr, so it cannot see the SOFT-ACK NOTE line — that is
# pinned separately in gate-regression.sh's assert_soft_ack cases.
assert_chain "ALLOW" \
  'curl -d x https://example.com' \
  "chain: real curl data upload — SOFT-ACK (IMP-146), no hook in the chain blocks"

echo "── chain-probe-imp108: $PASS passed, $FAIL failed ──"
if [ "$FAIL" -gt 0 ]; then
  printf "%b" "$FAILURES"
  exit 1
fi
exit 0
