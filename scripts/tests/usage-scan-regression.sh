#!/usr/bin/env bash
# usage-scan-regression.sh - regression suite for scripts/usage-scan.py (IMP-279).
# Builds a fixture transcript tree in a mktemp directory, runs the scan with a
# fixed --now, and asserts the exact counts. The fixture contains prompt-like
# marker strings; none may appear in any output. HOME is pointed at the scratch
# dir for the default-root case. Bytecode is not written (-B). No network.
# Usage: bash scripts/tests/usage-scan-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="${USAGE_SCAN:-$SCRIPT_DIR/../usage-scan.py}"
[[ -f "$SCAN" ]] || { echo "ERROR: scan not found: $SCAN" >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 1; }

PASS=0; FAIL=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/usage-scan-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/projects"
NOW="2026-11-11T12:00:00Z"

pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL  %s %s\n' "$1" "${2:-}"; }
# check <name> <want> <got>
check() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "(want $2, got $3)"; fi; }
# scan [args...] -> runs the tool on the fixture; sets RC
scan() { python3 -B -I "$SCAN" --root "$ROOT" --now "$NOW" "$@" </dev/null; RC=$?; }

echo "-- usage-scan.py regression (IMP-279) --"

# Fixture A: depth-1 transcript (main session).
mkdir -p "$ROOT/proj-a/s1/subagents" "$ROOT/proj-b" "$ROOT/proj-c" "$WORK/empty"
cat > "$ROOT/proj-a/s1.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-11-10T09:00:00Z","message":{"role":"user","content":"PROMPT-MARKER-USER please do the thing"}}
{"type":"assistant","timestamp":"2026-11-10T09:01:00Z","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/fixture/file.txt"}}]}}
{"type":"assistant","timestamp":"2026-11-10T09:02:00Z","message":{"content":[{"type":"tool_use","id":"t2","name":"mcp__plugin_serena_serena__find_symbol","input":{"name_path_pattern":"PROMPT-MARKER-TOOLINPUT"}}]}}
{"type":"assistant","timestamp":"2026-11-10T09:03:00Z","message":{"content":[{"type":"tool_use","id":"t3","name":"Skill","input":{"skill":"team-lead","args":"PROMPT-MARKER-SKILLARGS"}}]}}
{"type":"assistant","timestamp":"2026-11-10T09:04:00Z","message":{"content":[{"type":"tool_use","id":"t4","name":"Agent","input":{"subagent_type":"backend-agent","model":"haiku","prompt":"PROMPT-MARKER-AGENT"}}]}}
{"type":"assistant","timestamp":"2026-11-10T09:05:00Z","message":{"content":[{"type":"tool_use","id":"t5","name":"Agent","input":{"subagent_type":"Explore","prompt":"explore"}}]}}
{"type":"assistant","timestamp":"2026-11-10T09:06:00Z","message":{"content":[{"type":"tool_use","id":"t6","name":"Task","input":{"subagent_type":"backend-agent","model":"sonnet"}}]}}
{"type":"assistant","timestamp":"2026-11-10T09:07:00Z","message":{"content":[
{"type":"assistant","timestamp":"2026-09-01T00:00:00Z","message":{"content":[{"type":"tool_use","id":"t7","name":"Bash","input":{"command":"echo PROMPT-MARKER-OUT"}}]}}
{"type":"assistant","timestamp":"2026-11-11T13:00:00Z","message":{"content":[{"type":"tool_use","id":"t8","name":"Write","input":{}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t9","name":"Grep","input":{}}]}}
{"type":"assistant","timestamp":"2026-11-10T09:01:00Z","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{}}]}}
EOF

# Fixture B: sub-agent transcript at depth 3 under the main session.
cat > "$ROOT/proj-a/s1/subagents/agent-1.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-11-10T10:00:00Z","message":{"content":[{"type":"tool_use","id":"s1","name":"Bash","input":{"command":"ls PROMPT-MARKER-SUB"}}]}}
{"type":"assistant","timestamp":"2026-11-10T10:01:00Z","message":{"content":[{"type":"tool_use","id":"s2","name":"mcp__plugin_serena_serena__read_memory","input":{}}]}}
{"type":"assistant","timestamp":"2026-11-10T10:02:00Z","message":{"content":[{"type":"tool_use","id":"s3","name":"mcp__claude_ai_Notion__notion-fetch","input":{}}]}}
EOF

# Fixture C: window edges (one record inside at the exact start, one 1 s before it).
cat > "$ROOT/proj-b/s2.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-10-20T08:00:00Z","message":{"content":[{"type":"tool_use","id":"u1","name":"Skill","input":{"skill":"team-lead"}}]}}
{"type":"assistant","timestamp":"2026-10-12T12:00:00Z","message":{"content":[{"type":"tool_use","id":"u2","name":"Skill","input":{"skill":"bootstrap"}}]}}
{"type":"assistant","timestamp":"2026-10-12T11:59:59Z","message":{"content":[{"type":"tool_use","id":"u3","name":"Skill","input":{"skill":"old-skill"}}]}}
{"type":"user","timestamp":"2026-11-01T10:00:00Z","message":{"role":"user","content":"PROMPT-MARKER-COMMAND-TEXT"}}
EOF

# Fixture D: only out-of-window records; mtime set to now must not matter.
cat > "$ROOT/proj-c/old.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-08-01T00:00:00Z","message":{"content":[{"type":"tool_use","id":"o1","name":"Edit","input":{}}]}}
EOF
# Not a transcript: must never be scanned.
printf '%s\n' '{"type":"assistant","timestamp":"2026-11-10T09:00:00Z","message":{"content":[{"type":"tool_use","id":"x1","name":"Glob","input":{}}]}}' > "$ROOT/proj-c/ignored.txt"

# mtime: an in-window transcript with a 2001 mtime still counts; an
# out-of-window transcript with a fresh mtime still does not.
touch -t 200101010000 "$ROOT/proj-a/s1.jsonl"
touch "$ROOT/proj-c/old.jsonl"

J="$WORK/out.json"
scan --days 30 --format json > "$J"; check "default run exits 0" 0 "$RC"
check "files scanned (4 .jsonl, depth 1 and 3 included, .txt ignored)" 4 "$(jq '.totals.files_scanned' "$J")"
check "records in window" 14 "$(jq '.totals.records_in_window' "$J")"
check "tool_use blocks in window" 11 "$(jq '.totals.tool_use_blocks' "$J")"
check "malformed line counted and skipped" 1 "$(jq '.totals.malformed_lines_skipped' "$J")"
check "duplicate tool_use id skipped once" 1 "$(jq '.totals.duplicate_tool_use_skipped' "$J")"
check "window start" "2026-10-12T12:00:00+00:00" "$(jq -r '.window.start' "$J")"
check "window end" "2026-11-11T12:00:00+00:00" "$(jq -r '.window.end' "$J")"
check "tools by name" \
    '{"Agent":2,"Bash":1,"Read":1,"Skill":3,"Task":1,"mcp__claude_ai_Notion__notion-fetch":1,"mcp__plugin_serena_serena__find_symbol":1,"mcp__plugin_serena_serena__read_memory":1}' \
    "$(jq -S -c '.tools' "$J")"
check "mcp servers" '{"claude_ai_Notion":1,"plugin_serena_serena":2}' "$(jq -S -c '.mcp_servers' "$J")"
check "skills" '{"bootstrap":1,"team-lead":2}' "$(jq -S -c '.skills' "$J")"
check "agent types" '{"Explore":1,"backend-agent":2}' "$(jq -S -c '.agents.by_type' "$J")"
check "agent types by model (missing model is inherit)" \
    '{"Explore":{"inherit":1},"backend-agent":{"haiku":1,"sonnet":1}}' \
    "$(jq -S -c '.agents.by_type_and_model' "$J")"
check "out-of-window Skill (1 s before start) not counted" 0 "$(jq '.skills["old-skill"] // 0' "$J")"
check "out-of-window Bash (2026-09-01) not counted; in-window Bash only" 1 "$(jq '.tools.Bash // 0' "$J")"
check "record after --now not counted" 0 "$(jq '.tools.Write // 0' "$J")"
check "tool_use without timestamp not counted" 0 "$(jq '.tools.Grep // 0' "$J")"
check "out-of-window file with fresh mtime not counted" 0 "$(jq '.tools.Edit // 0' "$J")"

scan --days 30 --format md --out "$WORK/out.md"; check "md run with --out exits 0" 0 "$RC"
check "--out writes the file" 1 "$(grep -c '^# Usage scan' "$WORK/out.md")"
check "md lists the sub-agent model line" 1 "$(grep -c '^  - model haiku: 1$' "$WORK/out.md")"
scan --days 30 --format md >/dev/null; check "md to stdout exits 0" 0 "$RC"

S="$WORK/since.json"
scan --since 2026-10-12 --format json > "$S"; check "--since run exits 0" 0 "$RC"
check "--since includes the 11:59:59 record of the start day" 12 "$(jq '.totals.tool_use_blocks' "$S")"
check "--since records in window" 15 "$(jq '.totals.records_in_window' "$S")"
check "--since window start is midnight UTC" "2026-10-12T00:00:00+00:00" "$(jq -r '.window.start' "$S")"

PRIV=$(cat "$J" "$WORK/out.md" "$S")
check "no prompt marker in any output" 0 "$(grep -c 'PROMPT-MARKER' <<<"$PRIV")"
check "no fixture path in any output" 0 "$(grep -cF "$WORK" <<<"$PRIV")"

scan --format json --root "$WORK/empty" > "$WORK/empty.json"; check "empty root exits 0" 0 "$RC"
check "empty root has zero files" 0 "$(jq '.totals.files_scanned' "$WORK/empty.json")"

mkdir -p "$WORK/home/.claude"; ln -s "$ROOT" "$WORK/home/.claude/projects"
HOME="$WORK/home" python3 -B -I "$SCAN" --now "$NOW" --format json </dev/null > "$WORK/home.json"; RC=$?
check "default root (Path.home) exits 0" 0 "$RC"
check "default root finds the fixture" 4 "$(jq '.totals.files_scanned' "$WORK/home.json")"

scan --root "$WORK/missing" >/dev/null 2>&1; check "missing root exits 2" 2 "$RC"
scan --days 0 >/dev/null 2>&1; check "--days 0 exits 2" 2 "$RC"
scan --days 3 --since 2026-10-12 >/dev/null 2>&1; check "--days with --since exits 2" 2 "$RC"
scan --now not-a-date >/dev/null 2>&1; check "malformed --now exits 2" 2 "$RC"
scan --since 2026-12-01 >/dev/null 2>&1; check "start after end exits 2" 2 "$RC"

echo "------------------------------------"
echo "Summary: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
