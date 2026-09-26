#!/usr/bin/env bash
# publish-strip-regression.sh — IMP-… (2026-09-26), regression suite for
# publish-transforms.d/40-strip-private-hooks.sh.
#
# Builds a minimal, ISOLATED staging tree (mktemp -d) from the files the
# transform script actually reads/checks — settings.json plus the handful
# of ~/.claude scripts its commands reference (statusline-command.sh, and
# stub targets for every remaining hook .command after cockpit/graphify
# removal, so the generic "does this referenced script exist" walk at the
# end of the transform passes without needing the whole repo copied in).
# Never touches the real repo's settings.json or the real publish pipeline.
#
# Usage:  bash ~/.claude/hooks/tests/publish-strip-regression.sh
# Exit:   0 = all assertions pass, 1 = failures (listed on stdout)
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TRANSFORM="$REPO_ROOT/publish-transforms.d/40-strip-private-hooks.sh"

PASS=0; FAIL=0; FAILURES=""

assert() {  # $1 = label, $2 = 0/1 condition (0 = pass)
  if [ "$2" -eq 0 ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [FAIL] $1\n"
  fi
}

# Builds a fresh staging dir with a synthetic settings.json (cockpit hooks +
# cockpit statusLine + cockpit subagentStatusLine + outputStyle) plus stub
# script files for every referenced hook path, so the transform's own
# post-check ("every remaining hook script exists in staging") is satisfied.
make_staging() {  # $1 = staging dir; writes settings.json with outputStyle set
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/settings.json" <<'JSON'
{
  "outputStyle": "Hausbau",
  "statusLine": { "type": "command", "command": "~/.claude/cockpit/statusline/statusline.sh" },
  "subagentStatusLine": { "type": "command", "command": "~/.claude/cockpit/statusline/subagent-statusline.sh" },
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/cockpit/hooks/cockpit-event.sh start" } ] },
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/git-identity-check.sh" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash|Grep", "hooks": [ { "type": "command", "command": "graphify hook-guard bash" } ] },
      { "matcher": "Task|Agent", "hooks": [ { "type": "command", "command": "bash ~/.claude/cockpit/hooks/cockpit-event.sh task" } ] },
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/pretool-auto-read.sh" } ] }
    ]
  }
}
JSON
  cat > "$dir/statusline-command.sh" <<'SH'
#!/usr/bin/env bash
echo "stub statusline"
SH
  mkdir -p "$dir/hooks"
  cat > "$dir/hooks/git-identity-check.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat > "$dir/hooks/pretool-auto-read.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
}

echo "── outputStyle is removed by the transform ──"
S1="$(mktemp -d)"
make_staging "$S1"
OUT1="$(bash "$TRANSFORM" "$S1" 2>&1)"
RC1=$?
assert "transform exits 0" "$([ "$RC1" -eq 0 ] && echo 0 || echo 1)"
assert "outputStyle key absent after transform" "$(jq -e 'has("outputStyle") | not' "$S1/settings.json" >/dev/null 2>&1 && echo 0 || echo 1)"
assert "summary line mentions outputStyle removal" "$(printf '%s' "$OUT1" | grep -qi 'outputStyle' && echo 0 || echo 1)"

echo "── cockpit statusLine/subagentStatusLine/hooks are still stripped (no regression) ──"
assert "statusLine redirected away from cockpit" "$(jq -e '.statusLine.command | test("cockpit") | not' "$S1/settings.json" >/dev/null 2>&1 && echo 0 || echo 1)"
assert "subagentStatusLine key removed" "$(jq -e 'has("subagentStatusLine") | not' "$S1/settings.json" >/dev/null 2>&1 && echo 0 || echo 1)"
assert "no cockpit-event.sh hook remains" "$(jq -e '[.hooks[][].hooks[]?.command // empty | select(test("cockpit-event\\.sh"))] | length == 0' "$S1/settings.json" >/dev/null 2>&1 && echo 0 || echo 1)"
assert "no graphify hook-guard entry remains" "$(jq -e '[.hooks[][].hooks[]?.command // empty | select(test("graphify hook-guard"))] | length == 0' "$S1/settings.json" >/dev/null 2>&1 && echo 0 || echo 1)"
rm -rf "$S1"

echo "── idempotent: a settings.json WITHOUT outputStyle passes through unchanged (exit 0) ──"
S2="$(mktemp -d)"
make_staging "$S2"
jq 'del(.outputStyle)' "$S2/settings.json" > "$S2/settings.json.tmp" && mv "$S2/settings.json.tmp" "$S2/settings.json"
OUT2="$(bash "$TRANSFORM" "$S2" 2>&1)"
RC2=$?
assert "idempotent re-run exits 0" "$([ "$RC2" -eq 0 ] && echo 0 || echo 1)"
assert "idempotent re-run reports no FAIL in output" "$(printf '%s' "$OUT2" | grep -qi 'FAIL' && echo 1 || echo 0)"
assert "idempotent re-run: outputStyle still absent" "$(jq -e 'has("outputStyle") | not' "$S2/settings.json" >/dev/null 2>&1 && echo 0 || echo 1)"
rm -rf "$S2"

echo ""
echo "─────────────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '\nFailures:\n%b' "$FAILURES"
  exit 1
fi
exit 0
