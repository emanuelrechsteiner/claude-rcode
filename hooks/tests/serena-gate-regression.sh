#!/bin/bash
# Regression suite for serena-write-gate.sh + serena-post-tool.sh (IMP-130)
# ─────────────────────────────────────────────────────────────────────────────
# Proves the delegating gate has batteries: every inspector is exercised at
# least once through the Serena door, incl. a deliberate secret that MUST be
# blocked. Secret patterns are assembled at RUNTIME so this file itself never
# contains a matchable literal (security-audit would rightly block writing it).
#
# Run: bash hooks/tests/serena-gate-regression.sh
set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$HOOKS_DIR/serena-write-gate.sh"
POST="$HOOKS_DIR/serena-post-tool.sh"

T=$(mktemp -d)
trap 'rm -rf "$T" "$T2"' EXIT

# Real fixture files: the six "existing-file" write suffixes now require
# their target to actually exist on disk (fail-closed on a resolved path
# that names nothing — see the CWD/project-root mismatch guard in the gate).
mkdir -p "$T/src" "$T/.ssh"
printf 'export function bar() { return 1 }\n' > "$T/src/a.ts"
printf 'SECRET=dont-panic-this-is-a-fixture\n' > "$T/.env"
printf 'not-a-real-key-fixture-only\n' > "$T/.ssh/id_rsa"

# A SECOND, unrelated directory standing in for "Serena's real active
# project" — used by the CWD-mismatch cases below. $T stays "this session's
# cwd" (what the gate sees as $CWD); $T2 is where the file actually lives.
# ghost.ts deliberately does NOT exist under $T.
T2=$(mktemp -d)
mkdir -p "$T2/src"
printf 'export function ghost() {}\n' > "$T2/src/ghost.ts"

PASS=0; FAIL=0; N=0

# Runtime-assembled secret-like strings (never literal in this file)
PAD36=$(printf 'A%.0s' $(seq 1 36))
PAD82=$(printf 'b%.0s' $(seq 1 82))
PAD16=$(printf 'Q%.0s' $(seq 1 16))
PAD32=$(printf 'z%.0s' $(seq 1 32))
SECRET_GHP="ghp_${PAD36}"
SECRET_PAT="github_pat_${PAD82}"
SECRET_AWS="AKIA${PAD16}"
SECRET_SK="sk-${PAD32}"

payload() { # tool_name, tool_input_json
    jq -cn --arg tn "$1" --argjson ti "$2" --arg cwd "$T" --arg sid "serena-gate-test" \
        '{tool_name:$tn, tool_input:$ti, cwd:$cwd, session_id:$sid}'
}

payload_cwd() { # tool_name, tool_input_json, cwd — for cases that need a cwd other than $T
    jq -cn --arg tn "$1" --argjson ti "$2" --arg cwd "$3" --arg sid "serena-gate-test" \
        '{tool_name:$tn, tool_input:$ti, cwd:$cwd, session_id:$sid}'
}

run_gate() { # payload → sets OUT, ERR, CODE
    OUT=$(printf '%s' "$1" | "$GATE" 2>"$T/stderr"); CODE=$?
    ERR=$(cat "$T/stderr" 2>/dev/null || true)
}

verdict() { # got expected: allow|deny|ask|block
    local got="$1"
    case "$got" in
        block) [ "$CODE" -eq 2 ] ;;
        deny)  [ "$CODE" -eq 0 ] && printf '%s' "$OUT" | grep -q '"permissionDecision": *"deny"' ;;
        ask)   [ "$CODE" -eq 0 ] && printf '%s' "$OUT" | grep -q '"permissionDecision": *"ask"' ;;
        allow) [ "$CODE" -eq 0 ] && ! printf '%s' "$OUT" | grep -q '"permissionDecision"' ;;
    esac
}

t() { # desc, expected, payload
    N=$((N+1))
    run_gate "$3"
    if verdict "$2"; then
        PASS=$((PASS+1)); printf '  ok %2d — %s\n' "$N" "$1"
    else
        FAIL=$((FAIL+1)); printf 'FAIL %2d — %s\n     expected=%s code=%s\n     out=%s\n     err=%s\n' \
            "$N" "$1" "$2" "$CODE" "$OUT" "$ERR"
    fi
}

echo "── serena-write-gate regression ──────────────────────────────────────"

# ── Read tools pass through ──────────────────────────────────────────────
t "read: find_symbol → allow" allow \
    "$(payload mcp__serena__find_symbol '{"name_path_pattern":"Foo"}')"
t "read: get_symbols_overview → allow" allow \
    "$(payload mcp__serena__get_symbols_overview '{"relative_path":"src/a.ts"}')"

# ── Symbol editors: clean content allowed ────────────────────────────────
t "replace_symbol_body clean → allow" allow \
    "$(payload mcp__serena__replace_symbol_body '{"relative_path":"src/a.ts","name_path":"Foo/bar","body":"function bar() { return 1 }"}')"
t "insert_after_symbol clean → allow" allow \
    "$(payload mcp__serena__insert_after_symbol '{"relative_path":"src/a.ts","name_path":"Foo","body":"export const x = 1"}')"
t "insert_before_symbol clean → allow" allow \
    "$(payload mcp__serena__insert_before_symbol '{"relative_path":"src/a.ts","name_path":"Foo","body":"import { y } from \"./y\""}')"
t "replace_content clean (repl) → allow" allow \
    "$(payload mcp__serena__replace_content '{"relative_path":"src/a.ts","pattern":"old","repl":"new"}')"
t "create_text_file clean → allow" allow \
    "$(payload mcp__serena__create_text_file '{"relative_path":"src/new.ts","content":"export {}"}')"
t "rename_symbol clean → ask (multi-file: LSP writes N reference sites)" ask \
    "$(payload mcp__serena__rename_symbol '{"relative_path":"src/a.ts","name_path":"Foo/bar","new_name":"baz"}')"
t "safe_delete_symbol clean → ask (multi-file)" ask \
    "$(payload mcp__serena__safe_delete_symbol '{"relative_path":"src/a.ts","name_path_pattern":"Foo/dead"}')"
t "plugin-prefixed name handled identically → allow" allow \
    "$(payload mcp__plugin_serena_serena__replace_symbol_body '{"relative_path":"src/a.ts","name_path":"Foo/bar","body":"function bar() {}"}')"

# ── CWD/project-root mismatch — found via LIVE testing, not this fixture:
# resolve_path() always saw cwd == fixture root here, so this gap could never
# have shown up until an actual Serena project was activated somewhere other
# than the session's cwd. ghost.ts is real (it exists under $T2, standing in
# for Serena's true active project) but invisible from this session's cwd
# ($T) — the old behavior silently checked/logged a fabricated, nonexistent
# path; the gate must now fail closed instead, for both the plain write path
# and the multi-file "ask" path (which must never be reached with a
# fabricated target — fail-closed takes priority per the gate's own ordering).
t "replace_content: target real only under the actual project, not cwd → deny" deny \
    "$(payload_cwd mcp__serena__replace_content '{"relative_path":"src/ghost.ts","pattern":"a","repl":"b"}' "$T")"
t "rename_symbol: same mismatch → deny (fails closed BEFORE the multi-file ask)" deny \
    "$(payload_cwd mcp__serena__rename_symbol '{"relative_path":"src/ghost.ts","name_path":"Foo/bar","new_name":"baz"}' "$T")"

# ── THE BATTERY TEST: secrets through the Serena door must be blocked ────
t "replace_symbol_body with GitHub classic PAT → block" block \
    "$(payload mcp__serena__replace_symbol_body "$(jq -cn --arg s "$SECRET_GHP" '{relative_path:"src/a.ts",name_path:"Foo/bar",body:("const token = \"" + $s + "\"")}')")"
t "replace_symbol_body with fine-grained PAT → block" block \
    "$(payload mcp__serena__replace_symbol_body "$(jq -cn --arg s "$SECRET_PAT" '{relative_path:"src/a.ts",name_path:"Foo/bar",body:$s}')")"
t "replace_content with sk- key → block" block \
    "$(payload mcp__serena__replace_content "$(jq -cn --arg s "$SECRET_SK" '{relative_path:"src/a.ts",pattern:"x",repl:$s}')")"
t "write_memory with AWS key → block" block \
    "$(payload mcp__serena__write_memory "$(jq -cn --arg s "$SECRET_AWS" '{memory_name:"notes",content:("key: " + $s)}')")"

# ── Protected paths through the Serena door must be blocked ──────────────
t "safe_delete_symbol in .env → block" block \
    "$(payload mcp__serena__safe_delete_symbol '{"relative_path":".env","name_path_pattern":"X"}')"
t "replace_symbol_body in .ssh/id_rsa → block" block \
    "$(payload mcp__serena__replace_symbol_body '{"relative_path":".ssh/id_rsa","name_path":"x","body":"y"}')"
t "create_text_file under secrets/ → block" block \
    "$(payload mcp__serena__create_text_file '{"relative_path":"secrets/prod.txt","content":"harmless"}')"

# ── config-protection's recoverable ask is forwarded ─────────────────────
printf '{"rules":{}}' > "$T/.eslintrc.json"
t "replace_content on existing .eslintrc.json → ask (forwarded)" ask \
    "$(payload mcp__serena__replace_content '{"relative_path":".eslintrc.json","pattern":"a","repl":"b"}')"

# ── Memory writers ───────────────────────────────────────────────────────
t "write_memory clean → allow" allow \
    "$(payload mcp__serena__write_memory '{"memory_name":"project_notes","content":"harmless note"}')"
t "delete_memory → allow" allow \
    "$(payload mcp__serena__delete_memory '{"memory_name":"project_notes"}')"
t "rename_memory → allow" allow \
    "$(payload mcp__serena__rename_memory '{"memory_name":"project_notes","new_name":"project_notes_v2"}')"

# ── Memory path escape refused (slug names only) ─────────────────────────
t "write_memory with ../ traversal → deny" deny \
    "$(payload mcp__serena__write_memory '{"memory_name":"../../outside","content":"x"}')"
t "write_memory with global/ prefix (writes outside project) → deny" deny \
    "$(payload mcp__serena__write_memory '{"memory_name":"global/notes","content":"x"}')"
t "rename_memory to traversal target → deny" deny \
    "$(payload mcp__serena__rename_memory '{"memory_name":"notes","new_name":"../escape"}')"

# ── Fail-closed: contracts, drift, unknowns, garbage ─────────────────────
t "replace_symbol_body missing body → deny (drift detection)" deny \
    "$(payload mcp__serena__replace_symbol_body '{"relative_path":"src/a.ts","name_path":"Foo/bar"}')"
t "replace_symbol_body missing relative_path → deny" deny \
    "$(payload mcp__serena__replace_symbol_body '{"name_path":"Foo/bar","body":"x"}')"
t "replace_content with unrecognized content param → deny" deny \
    "$(payload mcp__serena__replace_content '{"relative_path":"src/a.ts","pattern":"a","totally_new_param":"b"}')"
t "replace_in_files → always deny (multi-file)" deny \
    "$(payload mcp__serena__replace_in_files '{"pattern":"a","repl":"b"}')"
t "execute_shell_command → deny (wrong door)" deny \
    "$(payload mcp__serena__execute_shell_command '{"command":"ls"}')"
t "unknown future write tool → deny (fail-closed)" deny \
    "$(payload mcp__serena__write_everything '{"relative_path":"src/a.ts","data":"x"}')"
t "garbage stdin → deny (fail-closed)" deny "this is not json"
t "valid JSON but missing tool_name → deny" deny '{"tool_input":{}}'

# ── Fail-closed when inspectors are missing (broken deployment) ──────────
ISOL=$(mktemp -d)
cp "$GATE" "$ISOL/"
OUT=$(printf '%s' "$(payload mcp__serena__replace_symbol_body '{"relative_path":"src/a.ts","name_path":"F","body":"x"}')" \
    | "$ISOL/serena-write-gate.sh" 2>"$T/stderr"); CODE=$?
ERR=$(cat "$T/stderr" 2>/dev/null || true)
N=$((N+1))
if verdict deny && printf '%s' "$OUT" | grep -q 'inspector'; then
    PASS=$((PASS+1)); printf '  ok %2d — gate without inspectors → deny (never green-without-checking)\n' "$N"
else
    FAIL=$((FAIL+1)); printf 'FAIL %2d — gate without inspectors: code=%s out=%s\n' "$N" "$CODE" "$OUT"
fi
rm -rf "$ISOL"

# ── Post-tool companion: read tracking + write event exit 0 ──────────────
N=$((N+1))
rm -f "/tmp/claude-reads-serena-gate-test.txt"
printf '%s' "$(payload mcp__serena__get_symbols_overview '{"relative_path":"src/tracked.ts"}')" | "$POST" >/dev/null 2>&1
if grep -q "src/tracked.ts" "/tmp/claude-reads-serena-gate-test.txt" 2>/dev/null; then
    PASS=$((PASS+1)); printf '  ok %2d — post-tool records Serena read into read tracker\n' "$N"
else
    FAIL=$((FAIL+1)); printf 'FAIL %2d — post-tool did not record Serena read\n' "$N"
fi
rm -f "/tmp/claude-reads-serena-gate-test.txt"

N=$((N+1))
printf '%s' "$(payload mcp__serena__rename_symbol '{"relative_path":"src/nonexistent.ts","name_path":"A","new_name":"B"}')" | "$POST" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    PASS=$((PASS+1)); printf '  ok %2d — post-tool write event on missing file exits 0 (fail-open)\n' "$N"
else
    FAIL=$((FAIL+1)); printf 'FAIL %2d — post-tool write event errored\n' "$N"
fi

echo "──────────────────────────────────────────────────────────────────────"
echo "serena-gate regression: $PASS/$N passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
