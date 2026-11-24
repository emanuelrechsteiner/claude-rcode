#!/usr/bin/env bash
# counts-drift-regression.sh - IMP-272: fails when a count that a document states as
# current fact differs from the generated inventory (scripts/framework-inventory.sh --json).
# CLAIMS is the only list of checked claims. A regex that matches nothing is a FAIL
# ("claim not found: the table is stale"), so a reworded sentence cannot drop out silently.
# History sections, changelog notes, quoted measurements and non-inventory counts are
# deliberately not in the table. Reads only; writes nothing.
# Usage: bash scripts/tests/counts-drift-regression.sh   (from any cwd)
# Exit: 0 every claim matches, 1 any mismatch or stale claim.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INVENTORY="$ROOT/scripts/framework-inventory.sh"
PASS=0; FAIL=0

# Row: label@@file (relative to repo root)@@ERE with exactly one number capture@@inventory key
# Keys: rules commands skills hooks_disk hooks_registered agents scheduled_tasks
#       test_suites (number of regression suites) | case:<suite path relative to repo root>
CLAIMS=(
    'rules, workshop@@docs/FRAMEWORK-REFERENCE.md@@workshop = \*\*([0-9]+) rules\*\*@@rules'
    'commands, reference line@@docs/FRAMEWORK-REFERENCE.md@@: ([0-9]+) commands · @@commands'
    'skills, reference line@@docs/FRAMEWORK-REFERENCE.md@@· ([0-9]+) skills · @@skills'
    'hooks on disk, reference line@@docs/FRAMEWORK-REFERENCE.md@@· ([0-9]+) hooks on disk /@@hooks_disk'
    'hooks registered, reference line@@docs/FRAMEWORK-REFERENCE.md@@hooks on disk / ([0-9]+) registered ·@@hooks_registered'
    'agents, reference line@@docs/FRAMEWORK-REFERENCE.md@@· ([0-9]+) agents ·@@agents'
    'scheduled tasks, reference line@@docs/FRAMEWORK-REFERENCE.md@@· ([0-9]+) scheduled tasks\.@@scheduled_tasks'
    'commands, skills section@@docs/FRAMEWORK-REFERENCE.md@@\(([0-9]+) commands total@@commands'
    'commands, R.Code section@@docs/FRAMEWORK-REFERENCE.md@@^Rails install per project\. ([0-9]+) commands@@commands'
    'commands, R.Code stage text@@docs/FRAMEWORK-REFERENCE.md@@se, /rcode-init, /rcode-migrate\. Rails install per project\. ([0-9]+) commands@@commands'
    'agents, subagent roster@@HARNESS.md@@\*\*4\. Subagents\*\* \| ([0-9]+) agents@@agents'
    'regression suites, README@@README.md@@All ([0-9]+) regression suites are green@@test_suites'
    'cases gate-regression, HARNESS@@HARNESS.md@@`hooks/tests/gate-regression\.sh` \(([0-9]+) cases\)@@case:hooks/tests/gate-regression.sh'
    'cases web-fetch-gate, HARNESS@@HARNESS.md@@`web-fetch-gate-regression\.sh` \(([0-9]+)\)@@case:hooks/tests/web-fetch-gate-regression.sh'
    'cases session-end-staleness, HARNESS@@HARNESS.md@@session-end-staleness-regression\.sh`, ([0-9]+) cases@@case:hooks/tests/session-end-staleness-regression.sh'
    'cases session-end-staleness, reference@@docs/FRAMEWORK-REFERENCE.md@@session-end-staleness-regression\.sh`, ([0-9]+) cases@@case:hooks/tests/session-end-staleness-regression.sh'
    'cases serena-gate, reference@@docs/FRAMEWORK-REFERENCE.md@@serena-gate-regression\.sh` \(([0-9]+) cases@@case:hooks/tests/serena-gate-regression.sh'
    'cases vault-write-gate, reference@@docs/FRAMEWORK-REFERENCE.md@@vault-write-gate-regression\.sh` \(([0-9]+) cases@@case:hooks/tests/vault-write-gate-regression.sh'
    'cases web-fetch-gate, reference@@docs/FRAMEWORK-REFERENCE.md@@web-fetch-gate-regression\.sh` \(([0-9]+) cases@@case:hooks/tests/web-fetch-gate-regression.sh'
)

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }
[[ -f "$INVENTORY" ]] || { echo "ERROR: inventory script not found: $INVENTORY" >&2; exit 1; }

# Inventory is generated against the workshop checkout, never against ~/.claude.
INV=$(CLAUDE_DIR="$ROOT" bash "$INVENTORY" --json) \
    || { echo "ERROR: framework-inventory.sh --json failed" >&2; exit 1; }

# inventory_value <key> -> the inventory number, or "missing" when there is none
inventory_value() {
    case "$1" in
        case:*)      jq -r --arg f "${1#case:}" \
                         '([.test_suites[] | select(.file == $f) | .cases][0]) // "missing"' <<<"$INV" ;;
        test_suites) jq -r '.test_suites | length' <<<"$INV" ;;
        *)           jq -r --arg k "$1" '.[$k] | tostring' <<<"$INV" ;;
    esac
}

# row_check <label> <file> <regex> <key>
row_check() {
    local label="$1" rel="$2" re="$3" key="$4"
    local path="$ROOT/$rel" hit num line n cap inv
    if [[ ! -f "$path" ]]; then
        FAIL=$((FAIL+1))
        printf 'FAIL  %-36s %s  claim file missing\n' "$label" "$rel"
        return 0
    fi
    hit=$(grep -nE -- "$re" "$path" | head -n 1)
    if [[ -z "$hit" ]]; then
        FAIL=$((FAIL+1))
        printf 'FAIL  %-36s %s  claim not found: the table is stale\n' "$label" "$rel"
        return 0
    fi
    num=${hit%%:*}
    line=${hit#*:}
    n=$(printf '%s\n' "$line" | grep -oE -- "$re" | wc -l | tr -d ' ')
    cap=""
    if [[ "$line" =~ $re ]]; then
        cap=${BASH_REMATCH[1]:-}
    fi
    if [[ "$n" -ne 1 || -z "$cap" ]]; then
        FAIL=$((FAIL+1))
        printf 'FAIL  %-36s %s:%s  claim ambiguous (%s matches on the line) or capture empty\n' \
            "$label" "$rel" "$num" "$n"
        return 0
    fi
    inv=$(inventory_value "$key")
    if [[ "$cap" == "$inv" ]]; then
        PASS=$((PASS+1))
        printf 'PASS  %-36s %s:%s  documented=%s inventory=%s\n' "$label" "$rel" "$num" "$cap" "$inv"
    elif [[ "$inv" == "missing" ]]; then
        FAIL=$((FAIL+1))
        printf 'FAIL  %-36s %s:%s  documented=%s inventory=missing (no count from the inventory: see its NOTE)\n' \
            "$label" "$rel" "$num" "$cap"
    else
        FAIL=$((FAIL+1))
        printf 'FAIL  %-36s %s:%s  documented=%s inventory=%s\n' "$label" "$rel" "$num" "$cap" "$inv"
    fi
    return 0
}

for row in "${CLAIMS[@]}"; do
    label=${row%%@@*}
    rest=${row#*@@}
    rel=${rest%%@@*}
    rest=${rest#*@@}
    re=${rest%%@@*}
    key=${rest#*@@}
    row_check "$label" "$rel" "$re" "$key"
done

echo "== counts-drift: $((PASS+FAIL)) claims, $PASS PASS, $FAIL FAIL =="
if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi
exit 0
