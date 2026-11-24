#!/bin/bash
# audit-config-regression.sh - regression suite for scripts/audit-config.sh
# (IMP-278: keys Claude Code writes itself, and live-install-only keys, are not
# reported as invalid; the lists are read from scripts/deploy-to-live.sh).
# Every run uses a throwaway HOME, so the real ~/.claude is never read or written.
# Usage: bash scripts/tests/audit-config-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SCRIPTS="$SCRIPT_DIR/.."
AUDIT="${CLAUDE_AUDIT:-$REPO_SCRIPTS/audit-config.sh}"
DEPLOY="$REPO_SCRIPTS/deploy-to-live.sh"
[[ -f "$AUDIT" ]] || { echo "ERROR: audit not found: $AUDIT" >&2; exit 1; }
[[ -f "$DEPLOY" ]] || { echo "ERROR: deploy script not found: $DEPLOY" >&2; exit 1; }

PASS=0; FAIL=0
BASE=$(mktemp -d "${TMPDIR:-/tmp}/audit-config-test.XXXXXX")
trap 'rm -rf "$BASE"' EXIT
mkdir -p "$BASE/bin"
# Stub for the claude CLI: keeps the audit from calling the real one.
printf '#!/bin/bash\nexit 0\n' > "$BASE/bin/claude"
chmod +x "$BASE/bin/claude"

# report <name> <0|1>  (0 = case passed)
report() {
    if [[ "$2" -eq 0 ]]; then
        PASS=$((PASS+1)); printf '  PASS %s\n' "$1"
    else
        FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"
    fi
}

# run_audit <audit-script> <case-name> <settings-json> -> sets RC, REPORT_TXT, OUT_TXT
run_audit() {
    local home="$BASE/home-$2"
    mkdir -p "$home/.claude"
    printf '%s\n' "$3" > "$home/.claude/settings.json"
    HOME="$home" PATH="$BASE/bin:$PATH" bash "$1" </dev/null >"$home/stdout.txt" 2>&1
    RC=$?
    local report_file="$home/.claude/audit-reports/audit-$(date '+%Y-%m-%d').md"
    REPORT_TXT=""
    [[ -f "$report_file" ]] && REPORT_TXT=$(<"$report_file")
    OUT_TXT=$(<"$home/stdout.txt")
}

echo "-- audit-config.sh regression (IMP-278) --"

RUNTIME_FIXTURE='{"theme":"dark","agentPushNotifEnabled":true,"model":"haiku","effortLevel":"low","autoMode":{"environment":[]},"deniedMcpServers":[],"permissions":{"defaultMode":"auto"}}'
run_audit "$AUDIT" runtime "$RUNTIME_FIXTURE"
[[ "$REPORT_TXT" != *"invalid field"* ]]; report "runtime-written and live-install keys produce no invalid-field finding" $?
[[ "$RC" -eq 0 ]]; report "runtime fixture gives exit 0 (no CRITICAL)" $?

run_audit "$AUDIT" theme '{"theme":"dark"}'
[[ "$REPORT_TXT" != *'invalid field `theme`'* ]]; report "theme is not invalid" $?

run_audit "$AUDIT" apnotif '{"agentPushNotifEnabled":true}'
[[ "$REPORT_TXT" != *'invalid field `agentPushNotifEnabled`'* ]]; report "agentPushNotifEnabled is not invalid" $?

run_audit "$AUDIT" skipperm '{"skipAutoPermissionPrompt":true}'
[[ "$REPORT_TXT" == *'invalid field `skipAutoPermissionPrompt`'* && "$RC" -eq 1 ]]; report "denylisted key outside the lists is still CRITICAL (exit 1)" $?

run_audit "$AUDIT" observations '{"observations":{}}'
[[ "$REPORT_TXT" == *'invalid field `observations`'* ]]; report "observations is still reported as invalid" $?

run_audit "$AUDIT" invented '{"notARealSetting":1}'
[[ "$REPORT_TXT" != *"invalid field"* ]]; report "invented key notARealSetting: no settings finding (audit checks a fixed denylist only, unchanged)" $?

# Every key path named in the two lists of deploy-to-live.sh is accepted.
# The lists are extracted here independently of the audit's own parser.
RT_LINE=$(grep -E "^RUNTIME_KEYS_JSON='" "$DEPLOY" | head -1)
HO_LINE=$(grep -E "^HAUS_ONLY_KEYS_JSON='" "$DEPLOY" | head -1)
RT_JSON=${RT_LINE#*=}; RT_JSON=${RT_JSON#\'}; RT_JSON=${RT_JSON%\'}
HO_JSON=${HO_LINE#*=}; HO_JSON=${HO_JSON#\'}; HO_JSON=${HO_JSON%\'}
ALL_FIXTURE=$(jq -c -n --argjson a "$RT_JSON" --argjson b "$HO_JSON" \
    '[($a + $b)[] | {p: ., v: "x"}] | reduce .[] as $e ({}; setpath($e.p; $e.v))')
ALL_FIXTURE=$(jq -c --argjson extra '{"theme":"dark","agentPushNotifEnabled":true}' '. + $extra' <<<"$ALL_FIXTURE")
run_audit "$AUDIT" allkeys "$ALL_FIXTURE"
[[ -n "$RT_JSON" && -n "$HO_JSON" && "$REPORT_TXT" != *"invalid field"* ]]; report "every key path in RUNTIME_KEYS_JSON and HAUS_ONLY_KEYS_JSON is accepted" $?

# The lists are read from deploy-to-live.sh, not hard-coded: a copy of that
# script with skipAutoPermissionPrompt added to RUNTIME_KEYS_JSON must make the
# audit accept it, and a copy with theme removed must make the audit report it.
MUT="$BASE/mut/scripts"
mkdir -p "$MUT"
cp "$AUDIT" "$MUT/audit-config.sh"
MUT_JSON=$(jq -c '[["skipAutoPermissionPrompt"]] + [.[] | select(. != ["theme"])]' <<<"$RT_JSON")
SRC=$(<"$DEPLOY")
SRC=${SRC//"$RT_LINE"/"RUNTIME_KEYS_JSON='$MUT_JSON'"}
printf '%s\n' "$SRC" > "$MUT/deploy-to-live.sh"
run_audit "$MUT/audit-config.sh" mutated '{"theme":"dark","skipAutoPermissionPrompt":true}'
[[ "$REPORT_TXT" == *'invalid field `theme`'* && "$REPORT_TXT" != *'invalid field `skipAutoPermissionPrompt`'* ]]; report "lists come from deploy-to-live.sh (mutated copy: theme reported, skipAutoPermissionPrompt accepted)" $?

# Fail loud: without a readable deploy-to-live.sh the invalid-field check is
# skipped with a WARN, and no runtime key is reported as a false CRITICAL.
NODEPLOY="$BASE/nodeploy/scripts"
mkdir -p "$NODEPLOY"
cp "$AUDIT" "$NODEPLOY/audit-config.sh"
run_audit "$NODEPLOY/audit-config.sh" nodeploy '{"theme":"dark"}'
[[ "$REPORT_TXT" == *"WARN"*"not readable"* && "$REPORT_TXT" != *'invalid field `theme`'* ]]; report "missing deploy-to-live.sh: WARN and no false CRITICAL" $?

echo "------------------------------------"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
