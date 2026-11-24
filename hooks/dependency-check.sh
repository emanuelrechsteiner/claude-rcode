#!/bin/bash
# dependency-check.sh — SessionStart check for hook dependencies (2026-11-06)
# ──────────────────────────────────────────────────────────────────────────
# Warns when `jq` is missing. Every hook parses its input with jq, and without it:
#   - guard-unsafe.sh and mcp-agency-gate.sh REFUSE every call (fail-closed),
#   - file-protection.sh and parallel-lock-check.sh stay fail-open and print a NOTE.
# Non-blocking: always exits 0. Silent when jq is present.

if command -v jq >/dev/null 2>&1; then
    exit 0
fi

echo "WARNING: jq is not installed or not on PATH."
echo "  Without it: guard-unsafe.sh and mcp-agency-gate.sh refuse every Bash and MCP call (fail-closed);"
echo "  file-protection.sh and parallel-lock-check.sh do not enforce (fail-open, NOTE on each use);"
echo "  the routine liveness check and the batched Stop checks do not run."
echo "  Fix: brew install jq, then start a new session."
exit 0
