#!/bin/bash
# security-audit-regression.sh - regression suite for hooks/security-audit.sh
# (IMP-244: PEM + JWT shapes, shared pattern lib; the "ALLOWED:" marker must have no effect).
# Runs with HOME pointed at a scratch dir so the real observation log is never
# touched. Fixture secrets are assembled from fragments so this file itself
# carries no secret-shaped literal.
# Usage: bash hooks/tests/security-audit-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../security-audit.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0
FAKE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/sec-audit-test.XXXXXX")
trap 'rm -rf "$FAKE_HOME"' EXIT

# run_hook <file_path> <content> -> sets RC and ERR
run_hook() {
    local json
    json=$(jq -n --arg p "$1" --arg c "$2" \
        '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}')
    ERR=$(printf '%s' "$json" | HOME="$FAKE_HOME" bash "$HOOK" 2>&1 >/dev/null)
    RC=$?
}
expect() {   # expect <name> <want-rc> [stderr-substring]
    if [[ "$RC" -eq "$2" ]] && { [[ -z "${3:-}" ]] || [[ "$ERR" == *"$3"* ]]; }; then
        PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
    else
        FAIL=$((FAIL+1)); printf '  FAIL %s (rc=%s want %s) %s\n' "$1" "$RC" "$2" "$ERR"
    fi
}

DASH="-----"
PEM_HEAD="${DASH}BEGIN RSA PRIVATE ""KEY${DASH}"
PEM_PLAIN="${DASH}BEGIN PRIVATE ""KEY${DASH}"
SEG="abcdefghijklmnop12345"
JWT="eyJ${SEG}.eyJ${SEG}.${SEG}"

echo "-- security-audit.sh regression (IMP-244) --"

run_hook /tmp/a.txt "$PEM_HEAD
MIIEowIBAAKCAQEA
${DASH}END RSA PRIVATE KEY${DASH}"
expect "PEM RSA block blocked" 2 "PEM private key"

run_hook /tmp/a.txt "$PEM_PLAIN"
expect "PEM plain PKCS8 header blocked" 2 "PEM private key"

run_hook /tmp/a.txt "token=$JWT"
expect "JWT blocked" 2 "JSON Web Token"

run_hook /tmp/a.txt "the prefix eyJhbGciOi is a base64 JSON opener"
expect "eyJ in non-JWT prose allowed" 0

run_hook /tmp/a.txt "value eyJ${SEG} only one segment"
expect "single eyJ segment (no dots) allowed" 0

rep() { printf "$1%.0s" $(seq 1 "$2"); }   # rep <char> <n>

# The "ALLOWED:" marker has NO effect (negative tests).
run_hook /tmp/a.txt "AKIA$(rep A 16) # ALLOWED: test fixture only"
expect "marker does not exempt a single-line AWS key" 2 "AWS"
run_hook /tmp/a.txt "${PEM_HEAD} # ALLOWED: test fixture only
MIIEowIBAAKCAQEA
${DASH}END RSA PRIVATE KEY${DASH}"
expect "marker on PEM header does not exempt a multi-line key" 2 "PEM private key"
run_hook /tmp/a.txt "ALLOWED:ghp_$(rep a 36)ALLOWED: test fixture only"
expect "marker inside a secret value does not matter" 2 "GitHub Classic"

# Parity: every pre-existing pattern still blocks.
run_hook /tmp/a.txt "github_pat_$(rep a 82)"; expect "github_pat_ blocked" 2 "Fine-Grained"
run_hook /tmp/a.txt "ghp_$(rep a 36)";        expect "ghp_ blocked" 2 "GitHub Classic"
run_hook /tmp/a.txt "ghs_$(rep b 36)";        expect "ghs_ blocked" 2 "GitHub Classic"
run_hook /tmp/a.txt "AKIA$(rep A 16)";        expect "AKIA blocked" 2 "AWS"
run_hook /tmp/a.txt "sk-$(rep a 40)";         expect "sk- blocked" 2 "sk-"
run_hook /tmp/a.txt "AIza$(rep a 35)";        expect "AIza blocked" 2 "Google"
run_hook /tmp/a.txt "xoxb-$(rep 1 12)";       expect "xox blocked" 2 "Slack"
run_hook /tmp/a.txt "fc-$(rep a 24)";         expect "fc- blocked" 2 "Firecrawl"
run_hook /tmp/a.txt "password = \"$(rep a 24)\""; expect "generic credential literal blocked" 2 "Hardcoded credential"
run_hook /tmp/a.ts  "apiKey: 'x', authDomain: 'y', projectId: 'z'"; expect "Firebase config outside config file blocked" 2 "Firebase"
run_hook /tmp/firebase.ts "apiKey: 'x', authDomain: 'y', projectId: 'z'"; expect "Firebase config in firebase file allowed" 0
run_hook /tmp/a.txt "just ordinary text"; expect "clean content allowed" 0

# Path whitelist.
run_hook /x/.env.local "AKIA$(rep A 16)";            expect "whitelist: .env path" 0
run_hook /x/secrets/k.txt "AKIA$(rep A 16)";         expect "whitelist: /secrets/ path" 0
run_hook /x/hooks/security-audit.sh "AKIA$(rep A 16)"; expect "whitelist: the hook's own file" 0

# Lib missing fails closed, except when editing the lib itself.
MISS="$FAKE_HOME/miss"; mkdir -p "$MISS/hooks"; cp "$HOOK" "$MISS/hooks/security-audit.sh"
SAVE_HOOK="$HOOK"; HOOK="$MISS/hooks/security-audit.sh"
run_hook /tmp/a.txt "ordinary text"; expect "lib missing: fail closed (rc 2)" 2 "missing"
run_hook /x/scripts/lib/secret-patterns.sh "ordinary text"; expect "lib missing: editing the lib itself allowed" 0
HOOK="$SAVE_HOOK"

echo "------------------------------------"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
