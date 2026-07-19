#!/bin/bash
# Gateguard — Layer 1 of the Quality Trinity (2026-05-26; downgraded 2026-06-09 per IMP-044/IMP-045)
# ─────────────────────────────────────────────────────────────────────
# PreToolUse hook on Edit|Write.
#
# ORIGINAL behavior: on the FIRST touch of a file per session it returned
# a JSON `deny`, forcing a second attempt even when the file had already
# been Read + investigated. That blocked every legitimate first edit once,
# costing a round-trip on well-investigated changes.
#
# DOWNGRADE (IMP-044/IMP-045): fold in the read-check signal. A file that
# was already Read in this session (the investigation we actually care
# about, tracked by posttool-track-read.sh in /tmp/claude-reads-<sid>.txt)
# PASSES first-touch silently — no friction, no round-trip. Only a
# genuinely un-investigated first touch gets a NON-BLOCKING note
# (additionalContext) reminding the agent to Read + grep importers first.
#
# Why a note and not a deny: pretool-auto-read.sh runs immediately after
# this hook in the same PreToolUse chain and HARD-blocks (exit 2) any
# Edit/Write on a file not Read in-session. So an un-read edit cannot slip
# through — gateguard's old first-touch deny was redundant with that gate.
# Gateguard now only adds a lightweight investigation nudge on top.
#
# Per-session state: /tmp/gateguard-<session>/<sha1-of-path>
# Read-tracker (shared with pretool-auto-read.sh): /tmp/claude-reads-<sid>.txt
#
# Bypass:
#   - Creating a new file (file doesn't exist) — bootstrap is allowed
#   - File already Read this session — passes first-touch
#   - File already in this-session's gateguard touch-list
#   - CLAUDE_GATEGUARD_OFF=1 env var
#
# Rationale: signals.jsonl shows 23 files edited 3+ times in same day —
# evidence of insufficient investigation before edit. The discipline lives
# in tool-discipline.md Rule 1; this hook now nudges rather than blocks.
set -u

[ "${CLAUDE_GATEGUARD_OFF:-0}" = "1" ] && exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Bypass: not an Edit/Write, no path, or no session
[ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || exit 0
[ -n "$FILE_PATH" ] || exit 0
[ -n "$SESSION_ID" ] || exit 0

# Bypass: file doesn't exist = new file creation (Write to fresh path)
[ -e "$FILE_PATH" ] || exit 0

# Bypass: trivial files (markdown drafts, config dotfiles, fixtures)
case "$FILE_PATH" in
    */NOTES.md|*/BRAINSTORM.md|*/TODO.md|*/SCRATCH.md|*/draft-*.md) exit 0 ;;
    */test/fixtures/*|*/__fixtures__/*|*/__snapshots__/*) exit 0 ;;
esac

# Bypass: file was already Read in this session = investigated.
# This is the core downgrade: investigation (not a forced retry) is what we
# want, and a prior Read is direct evidence of it. Shared tracker written by
# posttool-track-read.sh.
READ_TRACK="/tmp/claude-reads-${SESSION_ID}.txt"
if [ -f "$READ_TRACK" ] && grep -Fxq "$FILE_PATH" "$READ_TRACK"; then
    exit 0
fi

# State directory: per-session, ephemeral via /tmp
STATE_DIR="/tmp/gateguard-${SESSION_ID}"
mkdir -p "$STATE_DIR" 2>/dev/null

# Touch-file key: sha1 of absolute path
KEY=$(printf '%s' "$FILE_PATH" | shasum | awk '{print $1}')
TOUCH_FILE="$STATE_DIR/$KEY"

# Bypass: this file already got the gateguard note in this session
if [ -f "$TOUCH_FILE" ]; then
    exit 0
fi

# First touch of an un-Read file — mark and emit a NON-BLOCKING note.
# (pretool-auto-read.sh, next in the chain, will hard-block the un-read edit;
#  this note tells the agent WHY and what investigation to do.)
touch "$TOUCH_FILE"

REL_PATH=$(echo "$FILE_PATH" | sed "s|$HOME|~|")
EXT="${FILE_PATH##*.}"
LANG="code"
case "$EXT" in
    ts|tsx|js|jsx) LANG="JS/TS" ;;
    py) LANG="Python" ;;
    swift) LANG="Swift" ;;
    sh|bash) LANG="shell" ;;
    md) LANG="markdown" ;;
esac

NOTE="Gateguard (Layer 1): first touch of ${REL_PATH} this session, and it was not Read first. Before editing this ${LANG} file: (1) Read it to understand current shape; (2) Grep for importers/callers so you know what the change affects; (3) confirm the change matches the user's instruction (no scope creep). NOTE: this is a non-blocking reminder — pretool-auto-read.sh will still require a prior Read."
NOTE_JSON=$(printf '%s' "$NOTE" | jq -Rs '.')

cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": ${NOTE_JSON}
  }
}
JSON
exit 0
