#!/usr/bin/env bash
# 10-ledger-stub.sh — replace global-observation/improvement-ledger.json with
# a minimal, schema-valid, content-empty stub.
#
# Neutralizes: the ~15 PII/rebrand findings inside improvement-ledger.json
# (real names via cwd-embedded paths, /Volumes/... absolute paths quoted as
# evidence in old IMP write-ups, the pre-rebrand project's old codename in
# historical descriptions). These are prose inside dated history entries —
# not safely regex-scrubbable without risking JSON corruption or mangling
# unrelated prose — so the whole content-bearing part of the file is
# dropped. The schema/versioning CONTRACT (the fields other tooling reads:
# improvementLedgerVersion, schemaVersion, versioningProtocol, category and
# status enums) is preserved so a fresh public install has a valid ledger
# to append to, starting from zero history.
#
# Idempotent: re-running on an already-stubbed file produces the same stub
# (keyed off the ORIGINAL file's meta fields, captured before overwrite;
# if the file is already a stub, jq still extracts the same meta fields
# from it and re-emits an equivalent stub).
#
# Usage: 10-ledger-stub.sh <staging-dir>
set -euo pipefail

STAGING="${1:?usage: $0 <staging-dir>}"
LEDGER="$STAGING/global-observation/improvement-ledger.json"
README="$STAGING/global-observation/README.md"

if [[ ! -f "$LEDGER" ]]; then
  echo "10-ledger-stub: SKIP — $LEDGER not present in staging (already excluded upstream?)" >&2
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "10-ledger-stub: FAIL — jq is required to safely extract the ledger's meta fields" >&2
  exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

jq '{
  improvementLedgerVersion: (.improvementLedgerVersion // "0.0.0"),
  createdAt: (.createdAt // null),
  lastUpdated: (.lastUpdated // null),
  versioningSystem: (.versioningSystem // "semver_with_implementation_tracking"),
  schemaVersion: (.schemaVersion // "1.0.0"),
  totalImprovements: 0,
  totalImplementations: 0,
  totalStaged: 0,
  totalRollbacks: 0,
  versioningProtocol: (.versioningProtocol // {}),
  improvementCategories: (.improvementCategories // {}),
  implementationStatuses: (.implementationStatuses // {}),
  riskLevels: (.riskLevels // {}),
  improvementQueue: {},
  implementationHistory: {},
  activeImprovements: {},
  rollbackHistory: {},
  metrics: {},
  continuityProtocol: (.continuityProtocol // {}),
  _publishNote: "This is a fresh public-release stub. The private source-of-truth ledger'\''s historical entries (IMP-001..IMP-1xx) are not published — see docs/PUBLISHING.md for why. Schema/versioning fields above are carried over so tooling that reads this file keeps working from a clean slate."
}' "$LEDGER" > "$TMP"

mv "$TMP" "$LEDGER"

if [[ ! -f "$README" ]]; then
  echo "10-ledger-stub: WARN — global-observation/README.md missing from staging; expected to survive untouched" >&2
fi

echo "10-ledger-stub: OK — stubbed $LEDGER (history dropped, schema preserved)"
