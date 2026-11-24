#!/bin/bash
# mcp-agency-gate-regression.sh - regression suite for hooks/mcp-agency-gate.sh
# (IMP-271a: execute_sql is allowed silently only for a statement positively
# recognised as read-only; every other non-empty statement asks. The ESCALATE,
# deploy and non-MCP routing decisions are pinned as well.)
# Runs with HOME pointed at a scratch dir so the real observation log is never
# touched. Usage: bash hooks/tests/mcp-agency-gate-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../mcp-agency-gate.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0
FAKE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/mcp-gate-test.XXXXXX")
trap 'rm -rf "$FAKE_HOME"' EXIT
mkdir -p "$FAKE_HOME/.claude/global-observation"

# run_gate <tool_name> <tool_input-json> -> sets RC, OUT, DEC (DEC=defer when no decision is printed)
run_gate() {
    local json
    json=$(jq -n --arg t "$1" --argjson i "$2" '{tool_name:$t,tool_input:$i}')
    OUT=$(printf '%s' "$json" | HOME="$FAKE_HOME" bash "$HOOK" 2>/dev/null)
    RC=$?
    DEC=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
    DEC=${DEC:-defer}
}
expect() {   # expect <name> <want: allow|ask|defer>   (uses RC and DEC from run_gate)
    if [[ "$RC" -eq 0 && "$DEC" = "$2" ]]; then
        PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
    else
        FAIL=$((FAIL+1)); printf '  FAIL %s (rc=%s want %s got %s)\n' "$1" "$RC" "$2" "$DEC"
    fi
}
sql_case() { # sql_case <name> <statement> <want: allow|ask>
    local input
    input=$(jq -n --arg q "$2" '{query:$q}')
    run_gate mcp__supabase__execute_sql "$input"
    expect "$1" "$3"
}

echo "-- mcp-agency-gate.sh regression (IMP-271a) --"

echo "-- execute_sql: positively recognised read-only is allowed --"
sql_case "plain SELECT allowed" "SELECT * FROM users" allow
sql_case "WITH ... SELECT allowed" "WITH x AS (SELECT 1) SELECT * FROM x" allow
sql_case "SHOW allowed" "SHOW search_path" allow
sql_case "EXPLAIN without ANALYZE allowed" "EXPLAIN SELECT * FROM t" allow
sql_case "VALUES allowed" "VALUES (1), (2)" allow
sql_case "updated_at/created_at columns do not trigger" "SELECT updated_at, created_at FROM t" allow
sql_case "trailing semicolon allowed" "SELECT 1;" allow
sql_case "trailing line comment allowed" "SELECT 1 -- trailing note" allow
sql_case "leading comments and whitespace before SELECT allowed" $'  -- lead note\n/* block */ SELECT 1' allow
run_gate mcp__supabase__execute_sql '{"sql":"SELECT 1"}'
expect "sql field (fallback key) read allowed" allow

echo "-- execute_sql: unrecognised, multi-statement or write text asks --"
sql_case "data-modifying CTE asks" "WITH x AS (DELETE FROM t RETURNING 1) SELECT * FROM x" ask
sql_case "VACUUM asks" "VACUUM t" ask
sql_case "CALL asks" "CALL some_proc()" ask
sql_case "DO block asks" 'DO $$ BEGIN END $$' ask
sql_case "random text asks" "foo bar" ask
sql_case "SELECT followed by DROP asks" "SELECT 1; DROP TABLE t" ask
sql_case "EXPLAIN ANALYZE DELETE asks" "EXPLAIN ANALYZE DELETE FROM t" ask
sql_case "EXPLAIN ANALYZE SELECT asks" "EXPLAIN ANALYZE SELECT 1" ask
sql_case "EXPLAIN (ANALYZE, BUFFERS) asks" "EXPLAIN (ANALYZE, BUFFERS) SELECT 1" ask
sql_case "EXPLAIN ANALYSE spelling asks" "EXPLAIN ANALYSE SELECT 1" ask
sql_case "two read statements asks (multi-statement)" "SELECT 1; SELECT 2" ask
sql_case "SELECT INTO asks" "SELECT * INTO t2 FROM t" ask
sql_case "SELECT FOR UPDATE asks" "SELECT * FROM t FOR UPDATE" ask
sql_case "WITH ending in UPDATE asks" "WITH x AS (SELECT 1) UPDATE t SET a = 1" ask
sql_case "write keyword after a leading comment asks" $'-- SELECT 1\nDELETE FROM t' ask
sql_case "keyword inside a block comment asks" "/* DELETE */ SELECT 1" ask
sql_case "identifier starting with SELECT not recognised" "SELECT_x(1)" ask
# Findings of the commit security review (2026-11-11): comment nesting and side-effect functions.
sql_case "nested block comment hiding a statement asks" "/* a /* b */ SELECT 1 */ SET ROLE admin" ask
sql_case "block comment inside the statement asks" "SELECT 1 /* note */" ask
sql_case "sequence function asks" "SELECT nextval('s')" ask
sql_case "backend control function asks" "SELECT pg_terminate_backend(123)" ask
sql_case "session setting function asks" "SELECT set_config('a', 'b', false)" ask
sql_case "large object function asks" "SELECT lo_unlink(1)" ask
sql_case "dblink call asks" "SELECT * FROM dblink('c', 'select 1') AS t(a int)" ask
sql_case "aggregate functions still allowed" "SELECT count(*), max(id) FROM t" allow
sql_case "a column named like a function is not a call" "SELECT nextval_hint, setval FROM t" allow
sql_case "function name and call split by a newline asks" $'SELECT nextval\n(\'s\')' ask
sql_case "quoted function name asks" 'SELECT "nextval"('"'"'s'"'"')' ask
sql_case "line comment between name and call asks" $'SELECT nextval -- c\n(\'s\')' ask
sql_case "line comment inside the statement asks" $'SELECT 1 -- note\nFROM t' ask
sql_case "schema-qualified quoted function asks" 'SELECT "pg_catalog"."setval"('"'"'s'"'"', 1)' ask
# Third round of the commit security review (2026-11-11): whitespace classes, carriage
# return as a line end, Unicode-escape names, quoted names before a call.
sql_case "form feed between name and call asks" $'SELECT nextval\f(\'s\')' ask
sql_case "vertical tab between name and call asks" $'SELECT nextval\v(\'s\')' ask
sql_case "carriage return between name and call asks" $'SELECT nextval\r(\'s\')' ask
sql_case "carriage return ends a line comment inside the statement asks" $'SELECT 1 -- x\rFROM t' ask
sql_case "carriage return ends a leading comment asks" $'-- a\rNOTIFY ch, \'\nSELECT 1\'' ask
sql_case "Unicode-escape identifier asks" 'SELECT U&"\006eextval"('"'"'s'"'"')' ask
sql_case "lower-case Unicode-escape identifier asks" 'SELECT u&"d\0061ta" FROM t' ask
sql_case "Unicode-escape string asks" "SELECT U&'\\0041'" ask
sql_case "quoted name directly before a call asks" 'SELECT "count"(*) FROM t' ask
sql_case "quoted name, blank, then a call asks" 'SELECT "lower" (name) FROM t' ask
sql_case "notification function asks" "SELECT pg_notify('ch', 'x')" ask
sql_case "try-form of the advisory lock asks" "SELECT pg_try_advisory_lock(1)" ask
sql_case "scheduler extension call asks" "SELECT cron.schedule('j', '* * * * *', 'select 1')" ask
sql_case "scheduler call with blanks around the schema dot asks" "SELECT cron . unschedule ('j')" ask
sql_case "quoted schema of the scheduler asks" 'SELECT "cron".schedule('"'"'j'"'"', '"'"'1 1 1 1 1'"'"', '"'"'select 1'"'"')' ask
sql_case "HTTP sender extension call asks" "SELECT net.http_post('https://example.com/hook', '{}')" ask
sql_case "reading the scheduler table is still allowed" "SELECT jobid, schedule FROM cron.job" allow
sql_case "quoted columns without a call are still allowed" 'SELECT "id", "name" FROM "t"' allow
sql_case "CR LF line ends in a plain read are allowed" $'SELECT 1\r\nFROM t' allow
sql_case "trailing comment line with a final line end is allowed" $'SELECT 1 -- note\r\n' allow
sql_case "parenthesised SELECT not recognised" "(SELECT 1)" ask
sql_case "delete inside a string literal asks (unchanged)" "SELECT * FROM logs WHERE msg = 'delete me'" ask
sql_case "empty statement asks" "" ask
sql_case "whitespace-only statement asks" "   " ask
sql_case "comment-only statement asks" "-- nothing here" ask
run_gate mcp__supabase__execute_sql '{}'
expect "missing query field asks" ask

echo "-- other MCP routing unchanged --"
run_gate mcp__supabase__apply_migration '{"name":"m","query":"create table t()"}'
expect "apply_migration asks" ask
run_gate mcp__supabase__list_tables '{}'
expect "list_tables passes silently" defer
run_gate mcp__x__deploy_to_vercel '{"target":"preview"}'
expect "preview deploy passes silently" defer
run_gate mcp__x__deploy_to_vercel '{"target":"production"}'
expect "production deploy asks" ask
run_gate Bash '{"command":"ls"}'
expect "non-MCP tool ignored" defer

echo "------------------------------------"
echo "PASS: $PASS   FAIL: $FAIL"
if [[ "$FAIL" -ne 0 ]]; then exit 1; fi
exit 0
