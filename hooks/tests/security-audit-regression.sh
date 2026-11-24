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

# Silent-fallback check (IMP-271b). Full hook JSON per tool, so Edit and MultiEdit are covered.
run_json() { ERR=$(printf '%s' "$1" | HOME="$FAKE_HOME" bash "$HOOK" 2>&1 >/dev/null); RC=$?; }
write_json() { jq -n --arg p "$1" --arg c "$2" '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}'; }
edit_json() { jq -n --arg p "$1" --arg c "$2" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"x",new_string:$c}}'; }
multi_json() { jq -n --arg p "$1" --arg c "$2" '{tool_name:"MultiEdit",tool_input:{file_path:$p,edits:[{old_string:"x",new_string:$c}]}}'; }

echo "-- silent-fallback check (IMP-271b) --"
SF_PY="/x/app/mod.py"; SF_TS="/x/src/mod.ts"
PY_BARE="try:
    x = load()
except:
    pass"

run_json "$(write_json "$SF_PY" "$PY_BARE")"
expect "py bare except + pass blocked (Write)" 2 "Python silent except"
run_json "$(write_json "$SF_PY" "for item in items:
    try:
        use(item)
    except Exception:
        continue")"
expect "py except Exception + continue blocked (Write)" 2 "Python silent except"
run_json "$(edit_json "$SF_PY" "try:
    x = load()
except BaseException as exc: return None")"
expect "py except BaseException as exc: return None blocked (Edit)" 2 "Python silent except"
run_json "$(edit_json "$SF_PY" "try:
    x = load()
except Exception as err:
    return None")"
expect "py except Exception as err + return None blocked (Edit)" 2 "Python silent except"
run_json "$(multi_json "$SF_PY" "$PY_BARE")"
expect "py silent except blocked in MultiEdit edits[].new_string" 2 "Python silent except"
run_json "$(write_json "$SF_TS" "try {
  load();
} catch (e) {}")"
expect "js empty catch (e) {} blocked (Write)" 2 "JS/TS empty catch block"
run_json "$(edit_json "/x/src/view.tsx" "try {
  load();
} catch {

}")"
expect "js catch with whitespace-only body blocked (Edit)" 2 "JS/TS empty catch block"
run_json "$(write_json "/x/src/mod.js" "catch { return null }")"
expect "js catch { return null } blocked (Write)" 2 "JS/TS catch returns null"
run_json "$(write_json "/x/src/mod.jsx" "catch (e) { return null; }")"
expect "js catch (e) { return null; } blocked (Write)" 2 "JS/TS catch returns null"
run_json "$(write_json "$SF_TS" "load().catch(() => {});")"
expect "js .catch(() => {}) blocked (Write)" 2 "JS/TS empty .catch callback"
run_json "$(write_json "$SF_TS" "load().catch((err) => null);")"
expect "js .catch((err) => null) blocked (Write)" 2 "JS/TS empty .catch callback"
run_json "$(multi_json "/x/src/mod.mjs" "load().catch((_e) => {})")"
expect "js .catch((_e) => {}) blocked in MultiEdit" 2 "JS/TS empty .catch callback"

# Override marker: same line and line directly above are allowed.
run_json "$(write_json "$SF_PY" "try:
    x = load()
except:  # ALLOWED: best-effort cleanup
    pass")"
expect "py marker on the handler line allows" 0
run_json "$(write_json "$SF_PY" "try:
    x = load()
# ALLOWED: best-effort cleanup
except Exception:
    pass")"
expect "py marker on the line above allows" 0
run_json "$(write_json "$SF_TS" "try {
  load();
} catch (e) {} // ALLOWED: optional cache warm-up")"
expect "js marker on the catch line allows" 0
run_json "$(write_json "$SF_TS" "const p = load()
// ALLOWED: optional prefetch
  .catch(() => {});")"
expect "js marker on the line above allows" 0

# Marker negatives: empty reason, too far away, wrong comment style.
run_json "$(write_json "$SF_PY" "except:  # ALLOWED:
    pass")"
expect "py marker with empty reason still blocks" 2 "Python silent except"
run_json "$(write_json "$SF_PY" "# ALLOWED: far away
x = 1
except:
    pass")"
expect "py marker two lines above still blocks" 2 "Python silent except"
run_json "$(write_json "$SF_PY" "// ALLOWED: wrong style
except:
    pass")"
expect "js-style marker does not allow python" 2 "Python silent except"
run_json "$(write_json "$SF_TS" "} catch (e) {} # ALLOWED: reason")"
expect "python-style marker does not allow js" 2 "JS/TS empty catch block"

# Exempt paths: tests, fixtures, mocks, *.test.*, *.spec.*, conftest.py.
run_json "$(write_json "/x/tests/test_mod.py" "$PY_BARE")"; expect "exempt: /tests/ python" 0
run_json "$(write_json "/x/src/__tests__/mod.ts" "catch (e) {}")"; expect "exempt: __tests__ js" 0
run_json "$(write_json "/x/src/mod.test.ts" "load().catch(() => {});")"; expect "exempt: .test. file" 0
run_json "$(write_json "/x/src/mod.spec.js" "catch {}")"; expect "exempt: .spec. file" 0
run_json "$(write_json "/x/app/conftest.py" "$PY_BARE")"; expect "exempt: conftest.py" 0
run_json "$(write_json "/x/mocks/client.ts" "catch (e) {}")"; expect "exempt: /mocks/" 0
run_json "$(write_json "/x/fixtures/load.ts" "catch (e) {}")"; expect "exempt: /fixtures/" 0

# Must not fire.
run_json "$(write_json "$SF_PY" "try:
    x = load()
except ValueError: pass")"
expect "py specific exception (ValueError: pass) allowed" 0
run_json "$(write_json "$SF_PY" "try:
    x = load()
except Exception:
    logger.exception(\"load failed\")")"
expect "py handler that logs allowed" 0
run_json "$(write_json "$SF_PY" "try:
    x = load()
except Exception:
    raise")"
expect "py handler that re-raises allowed" 0
run_json "$(write_json "$SF_PY" "try:
    x = load()
except Exception:
    pass
    cleanup()")"
expect "py pass followed by another statement allowed" 0
run_json "$(write_json "$SF_TS" "try {
  load();
} catch (e) { console.error(e); }")"
expect "js catch that logs allowed" 0
run_json "$(write_json "$SF_TS" "try {
  load();
} catch (e) { log(e); return null; }")"
expect "js catch with return null plus another statement allowed" 0
run_json "$(write_json "/x/docs/notes.md" "except:
    pass
catch {}
load().catch(() => {});")"
expect "patterns inside a .md file allowed" 0
run_json "$(write_json "/x/docs/notes.txt" "load().catch(() => {});")"
expect "patterns inside a .txt file allowed" 0

# python3 missing: the check is skipped with a NOTE and the secret checks still run.
NOPY="$FAKE_HOME/nopy"; mkdir -p "$NOPY"
for tool in jq grep cat date mkdir dirname; do ln -s "$(command -v "$tool")" "$NOPY/$tool"; done
BASH_BIN=$(command -v bash)
ERR=$(printf '%s' "$(write_json "$SF_PY" "$PY_BARE")" | PATH="$NOPY" HOME="$FAKE_HOME" "$BASH_BIN" "$HOOK" 2>&1 >/dev/null); RC=$?
expect "python3 missing: check skipped with NOTE" 0 "NOTE"

# Detector failure: the check is skipped for the call and logged; it must not block
# every code edit (the repair of a broken detector is itself a code edit).
STUBPY="$FAKE_HOME/stubpy"; mkdir -p "$STUBPY"; printf '#!/bin/sh\nexit 5\n' >"$STUBPY/python3"; chmod +x "$STUBPY/python3"
ERR=$(printf '%s' "$(write_json "$SF_PY" "$PY_BARE")" | PATH="$STUBPY:$PATH" HOME="$FAKE_HOME" bash "$HOOK" 2>&1 >/dev/null); RC=$?
expect "detector failure: check skipped with NOTE, not a block" 0 "detector failed"
grep -q "DETECTOR FAILED rc=5" "$FAKE_HOME/.claude/global-observation/security-audit.log" 2>/dev/null \
    && { PASS=$((PASS+1)); printf '  ok   %s\n' "detector failure is logged"; } \
    || { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "detector failure is logged"; }

echo "------------------------------------"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
