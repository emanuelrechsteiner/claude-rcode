#!/usr/bin/env bash
# 20-changelog.sh — publish the curated public CHANGELOG.md.
#
# The private CHANGELOG.md (root) narrates internal improvement-cycle history
# and is excluded by publish-manifest.txt. The public changelog is a separate,
# hand-maintained file in Keep-a-Changelog format: public/CHANGELOG.md. This
# transform moves it to the root of the staging tree, so the public repo has
# exactly one CHANGELOG.md.
#
# Fail-loud: a missing public/CHANGELOG.md aborts the publish — a release
# without release notes is a defect, not a fallback case.
#
# Idempotent: the output is a byte copy of a tracked file.
#
# Usage: 20-changelog.sh <staging-dir>
set -euo pipefail

STAGING="${1:?usage: $0 <staging-dir>}"
SRC="$STAGING/public/CHANGELOG.md"
OUT="$STAGING/CHANGELOG.md"

if [[ ! -f "$SRC" ]]; then
  echo "20-changelog.sh: ABORT — public/CHANGELOG.md is missing from the staging tree." >&2
  echo "  Fix: add the release entry to public/CHANGELOG.md in the private repo." >&2
  exit 1
fi

mv "$SRC" "$OUT"
echo "20-changelog.sh: OK — published public/CHANGELOG.md as CHANGELOG.md"
