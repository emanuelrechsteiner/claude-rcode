#!/usr/bin/env bash
set -euo pipefail

# Block edits to sensitive paths
while read -r path; do
  case "$path" in
    *.env|.env|.env.*|.git/*|package-lock.json|pnpm-lock.yaml|yarn.lock)
      echo "Blocked unsafe write to $path" >&2
      exit 2
      ;;
  esac
done < <(jq -r '.changes[].path // empty')

exit 0
