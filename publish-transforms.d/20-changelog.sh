#!/usr/bin/env bash
# 20-changelog.sh — generate a public CHANGELOG.md stub.
#
# Neutralizes: every [REBRAND] finding inside CHANGELOG.md (the private
# file narrates internal improvement-cycle history using the pre-rebrand
# project's old codename throughout — it predates this repo's own
# public/private split) plus the IMP-history prose that isn't meant for
# public consumption (see publish-manifest.txt for the exclusion).
#
# Idempotent: always regenerates the same fixed content (no external
# state read), so re-running produces a byte-identical file.
#
# Usage: 20-changelog.sh <staging-dir>
set -euo pipefail

STAGING="${1:?usage: $0 <staging-dir>}"
OUT="$STAGING/CHANGELOG.md"

cat > "$OUT" <<'EOF'
# Changelog

This project ships as a generated public artifact — see `docs/PUBLISHING.md`
for the publish model. The detailed, dated improvement history of the
private source-of-truth configuration is not published here.

Release notes for each version are published as
[GitHub Releases](../../releases) at publish time. Each release corresponds
to one squashed commit produced by `scripts/publish.sh` from a specific
private-repo commit.

For the current state of any file, read the file itself — this repo has no
git history prior to each release's single commit, so there is nothing to
diff `CHANGELOG.md` against locally. Use the GitHub Releases page for
version-to-version deltas going forward.
EOF

echo "20-changelog.sh: OK — wrote public CHANGELOG.md stub"
