#!/usr/bin/env bash
# read-tracking-regression.sh — IMP-093/094/095/096 regression suite for the
# read-before-edit tracking chain (pretool-auto-read.sh + posttool-track-read.sh
# + observation-capture.sh's TRACK_FILE bridge).
#
# Runs the hooks DIRECTLY with synthetic PreToolUse/PostToolUse JSON on an
# ISOLATED $HOME (mktemp) and unique per-case session ids, so test runs never
# pollute ~/.claude/global-observation logs and never collide with a real
# session's /tmp/claude-reads-*.txt or /tmp/claude-block-log-*.txt state.
#
# Usage:  bash ~/.claude/hooks/tests/read-tracking-regression.sh
# Exit:   0 = all assertions pass, 1 = failures (listed on stdout)
#
# Cases (per the IMP-093 spec, minimum set):
#   1. Edit-without-Read on an existing file still BLOCKS.
#   2. Read -> Edit PASSES.
#   3. Write(new file) -> Edit PASSES NOW (the IMP-093 fix — was previously
#      guaranteed-BLOCKED because pretool-auto-read.sh's own bootstrap bypass
#      never registered the path in TRACK_FILE).
#   4. Write(existing file, no prior Read) still BLOCKS.
#   5. observation-capture.sh's PostToolUse bridge (IMP-093 part 2): a
#      successful Write/Edit on an EXISTING file, observed only via
#      observation-capture.sh (not via a Read), unblocks a later Edit of the
#      same file in the same session.
#   6. IMP-096: a second block on the SAME file within <2min in the SAME
#      session carries the "DIAGNOSIS (IMP-096)" extension in stderr; the
#      first block does not.

set -u
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTHOME="$(mktemp -d)"
TESTDIR="$(mktemp -d)"
mkdir -p "$TESTHOME/.claude/global-observation"

# Track every session-scoped /tmp state file this run touches so it can be
# cleaned up regardless of which case created it (TRACK_FILE/BLOCK_LOG live
# under the real /tmp, not TESTHOME, because pretool-auto-read.sh hardcodes
# that path — see hooks/pretool-auto-read.sh).
TMP_STATE_GLOB_PREFIX="claude-rtr-regress"
cleanup() {
  rm -rf "$TESTHOME" "$TESTDIR"
  rm -f /tmp/claude-reads-${TMP_STATE_GLOB_PREFIX}-*.txt
  rm -f /tmp/claude-block-log-${TMP_STATE_GLOB_PREFIX}-*.txt
  # observation-capture.sh's pre-existing Layer 2 Accumulator (unrelated to
  # this suite, but case5 calls that hook directly and it writes here too).
  rm -f /tmp/claude-edit-queue-${TMP_STATE_GLOB_PREFIX}-*.txt
}
trap cleanup EXIT

PASS=0; FAIL=0; FAILURES=""
CASE_N=0
next_sid() { CASE_N=$((CASE_N+1)); echo "${TMP_STATE_GLOB_PREFIX}-$$-${CASE_N}"; }

json_cmd() {  # $1=tool_name $2=file_path $3=session_id -> hook JSON on stdout
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
tool, file_path, session_id = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    "tool_name": tool,
    "tool_input": {"file_path": file_path},
    "session_id": session_id,
}))
PY
}

run_pretool() {  # $1=tool $2=file_path $3=session_id $4=stderr_capture_file -> exit code on stdout
  # NOTE: this runs inside a `$(...)` command substitution at call sites (to
  # capture the exit code), which is a SUBSHELL — any variable assigned here
  # would NOT propagate to the caller. The stderr file path is therefore
  # passed IN as $4 rather than exported as a side-effect global.
  json_cmd "$1" "$2" "$3" | HOME="$TESTHOME" bash "$HOOKS_DIR/pretool-auto-read.sh" \
      >/dev/null 2>"$4"
  echo $?
}

run_posttool_read() {  # $1=file_path $2=session_id
  json_cmd "Read" "$1" "$2" | HOME="$TESTHOME" bash "$HOOKS_DIR/posttool-track-read.sh" >/dev/null 2>&1
}

run_observation_capture() {  # $1=tool $2=file_path $3=session_id
  json_cmd "$1" "$2" "$3" | HOME="$TESTHOME" bash "$HOOKS_DIR/observation-capture.sh" >/dev/null 2>&1
}

assert_rc() {  # $1=label $2=expectation(ALLOW|BLOCK) $3=actual_rc
  local ok=0
  if [ "$2" = "ALLOW" ] && [ "$3" -eq 0 ]; then ok=1; fi
  if [ "$2" = "BLOCK" ] && [ "$3" -ne 0 ]; then ok=1; fi
  if [ "$ok" -eq 1 ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [$1] expected $2 (got rc=$3)\n"
  fi
}

assert_stderr_contains() {  # $1=label $2=expect(YES|NO) $3=needle $4=file
  local hit=0
  grep -qF "$3" "$4" 2>/dev/null && hit=1
  local ok=0
  if [ "$2" = "YES" ] && [ "$hit" -eq 1 ]; then ok=1; fi
  if [ "$2" = "NO" ] && [ "$hit" -eq 0 ]; then ok=1; fi
  if [ "$ok" -eq 1 ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [$1] expected stderr-contains($2) '$3'\n"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Case 1 — Edit-without-Read on an existing file still BLOCKS.
# ═══════════════════════════════════════════════════════════════════════════
SID1=$(next_sid)
F1="$TESTDIR/case1-existing.txt"
echo "content" > "$F1"
ERR1="$(mktemp)"
RC=$(run_pretool "Edit" "$F1" "$SID1" "$ERR1")
assert_rc "case1: Edit-without-Read (existing file)" BLOCK "$RC"
rm -f "$ERR1"

# ═══════════════════════════════════════════════════════════════════════════
# Case 2 — Read -> Edit PASSES.
# ═══════════════════════════════════════════════════════════════════════════
SID2=$(next_sid)
F2="$TESTDIR/case2-existing.txt"
echo "content" > "$F2"
run_posttool_read "$F2" "$SID2"
ERR2="$(mktemp)"
RC=$(run_pretool "Edit" "$F2" "$SID2" "$ERR2")
assert_rc "case2: Read -> Edit" ALLOW "$RC"
rm -f "$ERR2"

# ═══════════════════════════════════════════════════════════════════════════
# Case 3 — Write(new file) -> Edit PASSES NOW (IMP-093 core fix).
# ═══════════════════════════════════════════════════════════════════════════
SID3=$(next_sid)
F3="$TESTDIR/case3-brandnew.txt"   # deliberately never created — Write target
ERR3A="$(mktemp)"; ERR3B="$(mktemp)"
RC=$(run_pretool "Write" "$F3" "$SID3" "$ERR3A")
assert_rc "case3a: Write on new file itself is never blocked" ALLOW "$RC"
RC=$(run_pretool "Edit" "$F3" "$SID3" "$ERR3B")
assert_rc "case3b: Edit immediately after Write(new file) — was guaranteed-blocked pre-IMP-093" ALLOW "$RC"
rm -f "$ERR3A" "$ERR3B"

# ═══════════════════════════════════════════════════════════════════════════
# Case 4 — Write(existing file, no prior Read) still BLOCKS.
# ═══════════════════════════════════════════════════════════════════════════
SID4=$(next_sid)
F4="$TESTDIR/case4-existing.txt"
echo "content" > "$F4"
ERR4="$(mktemp)"
RC=$(run_pretool "Write" "$F4" "$SID4" "$ERR4")
assert_rc "case4: Write(existing file) without prior Read" BLOCK "$RC"
rm -f "$ERR4"

# ═══════════════════════════════════════════════════════════════════════════
# Case 5 — observation-capture.sh PostToolUse bridge (IMP-093 part 2): a
# successful Write/Edit on an EXISTING file, observed only via
# observation-capture.sh (no Read at all), unblocks a LATER Edit of the same
# file in the same session.
# ═══════════════════════════════════════════════════════════════════════════
SID5=$(next_sid)
F5="$TESTDIR/case5-existing.txt"
echo "content" > "$F5"
# Simulate the harness firing PostToolUse for a Write that the harness itself
# already approved (e.g. it passed pretool's gate via some other exempted
# path) — we test observation-capture.sh's bridge logic in isolation from
# pretool's own gate decision, since PostToolUse only ever fires after a
# tool call the harness allowed to execute.
run_observation_capture "Write" "$F5" "$SID5"
ERR5="$(mktemp)"
RC=$(run_pretool "Edit" "$F5" "$SID5" "$ERR5")
assert_rc "case5: observation-capture.sh Write-bridge unblocks later Edit (no Read ever happened)" ALLOW "$RC"
rm -f "$ERR5"

# ═══════════════════════════════════════════════════════════════════════════
# Case 6 — IMP-096: second block on the SAME file within <2min in the SAME
# session carries the DIAGNOSIS extension; the first block does not.
# ═══════════════════════════════════════════════════════════════════════════
SID6=$(next_sid)
F6="$TESTDIR/case6-existing.txt"
echo "content" > "$F6"
ERR6A="$(mktemp)"; ERR6B="$(mktemp)"
RC=$(run_pretool "Edit" "$F6" "$SID6" "$ERR6A")
assert_rc "case6a: first block on file (baseline)" BLOCK "$RC"
assert_stderr_contains "case6a: first block has NO diagnosis extension" NO "DIAGNOSIS (IMP-096)" "$ERR6A"

RC=$(run_pretool "Edit" "$F6" "$SID6" "$ERR6B")
assert_rc "case6b: second block on same file within window (baseline still blocks)" BLOCK "$RC"
assert_stderr_contains "case6b: second block WITHIN 2min carries diagnosis extension" YES "DIAGNOSIS (IMP-096)" "$ERR6B"

rm -f "$ERR6A" "$ERR6B"

echo "── read-tracking-regression: $PASS passed, $FAIL failed ──"
if [ "$FAIL" -gt 0 ]; then
  printf "%b" "$FAILURES"
  exit 1
fi
exit 0
