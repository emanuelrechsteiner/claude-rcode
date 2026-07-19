#!/usr/bin/env bash
# SessionStart hook — warn if YOLO/--dangerously-skip-permissions detected outside sandbox.
# Added 2026-05-26 per Wave 4 of MIGRATION-PLAN.md v3.
# Reason: KB cluster 09 — Casco YC red-team finding (7/16 agents hacked in 30 min).
# Per ~/.claude/rules/agents-as-users.md + ~/.claude/rules/excessive-agency-gate.md,
# YOLO should only run in containers/sandboxes.

set -euo pipefail

# Detect known sandbox markers
IS_SANDBOX=0
if [ -n "${CLAUDE_YOLO_SANDBOX:-}" ]; then IS_SANDBOX=1; fi
if [ -f /.dockerenv ]; then IS_SANDBOX=1; fi
if [ -n "${CONTAINER:-}" ]; then IS_SANDBOX=1; fi
if [ -f /run/.containerenv ]; then IS_SANDBOX=1; fi

# Detect YOLO mode from env or settings.json
YOLO_MODE=0
if [ -n "${CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS:-}" ]; then YOLO_MODE=1; fi
if grep -q '"skipDangerousModePermissionPrompt"\s*:\s*true' "$HOME/.claude/settings.json" 2>/dev/null; then
  YOLO_MODE=1
fi
if grep -q '"skipAutoPermissionPrompt"\s*:\s*true' "$HOME/.claude/settings.json" 2>/dev/null; then
  YOLO_MODE=1
fi

if [ "$YOLO_MODE" = "1" ] && [ "$IS_SANDBOX" = "0" ]; then
  cat <<'EOF'
⚠️  Sandbox-Guard: YOLO/auto-permission mode active but NOT in a known sandbox.

   Per ~/.claude/rules/agents-as-users.md + Casco YC finding (7/16 agents hacked in 30min):
   autonomous/YOLO modes should only run in containers, sandboxes, or throwaway envs.

   This is a soft warning, not a block. Recommended actions:
   • Mark this env as sandbox:  export CLAUDE_YOLO_SANDBOX=1
   • Disable YOLO globally:     set "skipDangerousModePermissionPrompt": false in settings.json
   • Run in container:          docker run / devcontainer / etc.

   Excessive-agency-gate hook (PreToolUse|Bash) still gates irreversible ops regardless of this warning.
EOF
fi
