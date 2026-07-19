#!/bin/bash
# Notification TTS Hook
# ─────────────────────────────────────────────────────────────────────
# Fires on Notification event (when Claude Code needs user input or
# emits an idle prompt). Announces via macOS `say` so background
# terminals can grab attention.
#
# Opt-in: set CLAUDE_NOTIFICATION_TTS=1 in env (settings.json env block
# or shell rc). Silent if unset — no behavior change for users who
# don't want audio.
#
# Inspired by IndyDevDan video "I'm HOOKED on Claude Code Hooks"
# (2025-07-07). We use macOS `say` instead of ElevenLabs to avoid
# the API/cost dependency.
#
# Schema (per https://code.claude.com/docs/en/hooks):
#   { hook_event_name: "Notification",
#     notification_type: "permission_prompt|idle_prompt|auth_success|...",
#     message: "<text>" }
set -u

[ "${CLAUDE_NOTIFICATION_TTS:-0}" = "1" ] || exit 0

INPUT=$(cat)
TYPE=$(echo "$INPUT" | jq -r '.notification_type // "unknown"')
MSG=$(echo "$INPUT" | jq -r '.message // empty')

# Short, distinct phrase per notification class so you can recognize
# what's happening without looking at the screen.
case "$TYPE" in
    permission_prompt) PHRASE="Permission needed" ;;
    idle_prompt)       PHRASE="Claude is idle" ;;
    auth_success)      PHRASE="Authenticated" ;;
    elicitation_*)     PHRASE="Input required" ;;
    *)                 PHRASE="Claude notification" ;;
esac

# Log for observability — same dir pattern as other hooks
LOG="$HOME/.claude/global-observation/notifications.jsonl"
mkdir -p "$(dirname "$LOG")"
printf '{"ts":"%s","type":"%s","message":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$TYPE" \
    "$(printf '%s' "$MSG" | sed 's/"/\\"/g')" >> "$LOG"

# macOS `say` — non-blocking via & so the hook returns immediately
(say -v Alex "$PHRASE" 2>/dev/null &)

exit 0
