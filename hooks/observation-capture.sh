#!/bin/bash
# Lightweight PostToolUse observer — replaces archived improvement-agent Project Layer.
#
# Captures Edit/Write events + git commit-intent patterns to a JSONL signal stream.
# Designed to be <10ms per invocation. Always exits 0 (non-blocking).
#
# Consumed by:
#   - /meta-observe skill (on-demand pattern synthesis, Opus)
#   - session-end-check.sh (daily signal count → /meta-observe prompt)
#
# Schema per line:
#   {"ts": "2026-04-20T14:23:01Z", "cwd": "/path", "intent": "fix|refactor|edit",
#    "file": "relative/path", "branch": "main", "rcode": true}

LEDGER="$HOME/.claude/global-observation/signals.jsonl"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CWD=$(pwd)

# Read JSON input from stdin (Claude Code standard, matches guard-unsafe.sh pattern).
# IMP-A fix 2026-05-24: previously read $1 (positional arg) which received the literal
# unexpanded string "$file_path" from settings.json — causing 1728/1729 signals to have
# empty .file fields. See ~/claude-framework-consolidation/02-triage/META-OBSERVER-SAMPLE-REPORT.md
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Derive intent from most recent commit message (heuristic)
LAST_MSG=$(git log -1 --pretty=%s 2>/dev/null | head -c 120)
INTENT="edit"
# IMP-052: R.Code meta-doc commits (handoff/scope/migration/project/audit/status/
# architecture/conventions) must NOT bleed their full commit type into subsequent
# code-edit signals. A code edit made while such a commit is HEAD is still an "edit",
# not "docs(handoff)". This guard must precede the generic ^(test|docs) arm below.
if echo "$LAST_MSG" | grep -qiE "^docs\((handoff|scope|migration|project|audit|status|architecture|conventions)\)"; then
    INTENT="edit"
elif echo "$LAST_MSG" | grep -qiE "^(fix|bug|hotfix)"; then
    INTENT="fix"
elif echo "$LAST_MSG" | grep -qiE "^(refactor|cleanup|chore)"; then
    INTENT="refactor"
elif echo "$LAST_MSG" | grep -qiE "^(feat|feature|add)"; then
    INTENT="feature"
elif echo "$LAST_MSG" | grep -qiE "^(test|docs)"; then
    INTENT="${LAST_MSG%%:*}"
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
RCODE="false"
[[ -d .rcode ]] && RCODE="true"

# JSON-escape file path (basic: replace backslash/quote)
FILE_ESC=$(printf '%s' "$FILE_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')
CWD_ESC=$(printf '%s' "$CWD" | sed 's/\\/\\\\/g; s/"/\\"/g')

printf '{"ts":"%s","cwd":"%s","intent":"%s","file":"%s","branch":"%s","rcode":%s,"tool":"%s","session_id":"%s"}\n' \
    "$TS" "$CWD_ESC" "$INTENT" "$FILE_ESC" "$BRANCH" "$RCODE" "$TOOL_NAME" "$SESSION_ID" >> "$LEDGER"

# === Layer 2 Accumulator (2026-05-26) ===
# Atomic append of edited path to a session-scoped queue file. Read by
# stop-batched-checks.sh at Stop time for consolidated format/typecheck/
# lint pass. POSIX O_APPEND on small writes is atomic — no lock needed.
if [ -n "$FILE_PATH" ] && [ -n "$SESSION_ID" ]; then
    QUEUE="/tmp/claude-edit-queue-${SESSION_ID}.txt"
    printf '%s\n' "$FILE_PATH" >> "$QUEUE"
fi

# === Read-before-Edit tracking bridge (IMP-093) ===
# pretool-auto-read.sh's TRACK_FILE was previously only ever populated by
# posttool-track-read.sh (PostToolUse, matcher "Read"). A successful Edit or
# Write demonstrates the SAME full knowledge of the file's current content
# that a Read would, but was never recorded there — so a later Edit of a
# file this session already Wrote/Edited (not just Read) could still be
# blocked for "not Read". This hook already fires on PostToolUse for
# Edit|Write (see settings.json matcher above), so it is the natural place
# to close that gap without touching settings.json. Mirrors
# posttool-track-read.sh's append-only contract on the same TRACK_FILE.
if [ -n "$FILE_PATH" ] && [ -n "$SESSION_ID" ] && { [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; }; then
    TRACK_FILE="/tmp/claude-reads-${SESSION_ID}.txt"
    printf '%s\n' "$FILE_PATH" >> "$TRACK_FILE"
fi

exit 0
