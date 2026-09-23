#!/usr/bin/env bash
set -euo pipefail

if [ -f package.json ]; then
  if jq -e '.scripts.format' package.json >/dev/null 2>&1; then
    npm run format || true
  fi
fi

exit 0
