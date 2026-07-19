#!/bin/bash
# session-handoff-write.sh — Stop hook that auto-writes a lightweight handoff doc.
# Added 2026-06-21 per IMP-057, Feature F4.
#
# NOTE: This hook does NOT and CANNOT archive the chat transcript — archiving is
# a Claude.ai client UI action with no programmatic hook API. The transcript copy
# in ~/.claude/global-observation/chat-archives/ (written by session-end-check.sh)
# is the closest available proxy.
#
# What it does:
#   • Reads Stop JSON from stdin (session_id, cwd, transcript_path)
#   • Gates on: .rcode/ present AND (commits in last 4h > 0 OR signals today >= 3)
#   • Writes <gitroot>/.rcode/handoff-<UTC-date>-<first8-session-id>.md
#   • Idempotent: overwrites if the file already exists (refresh, no duplicates)
#   • Appends a single pointer line to .rcode/agent-log.md if not already there
#
# Opt-out: export CLAUDE_AUTO_HANDOFF=0
#
# Always exits 0 — non-blocking.

set -u

# ─── Opt-out ────────────────────────────────────────────────────────────────
[ "${CLAUDE_AUTO_HANDOFF:-1}" = "0" ] && exit 0

# ─── Read stdin (Stop JSON) ─────────────────────────────────────────────────
STOP_INPUT="$(cat 2>/dev/null || true)"

# ─── Parse session_id and cwd from JSON ─────────────────────────────────────
SESSION_ID=""
STOP_CWD=""

if command -v jq >/dev/null 2>&1 && [ -n "$STOP_INPUT" ]; then
    SESSION_ID=$(printf '%s' "$STOP_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
    STOP_CWD=$(printf '%s' "$STOP_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
fi

# Fallback: use current working directory if cwd not in JSON
[ -n "$STOP_CWD" ] || STOP_CWD="$(pwd 2>/dev/null || true)"
[ -n "$SESSION_ID" ] || SESSION_ID="unknown-session"

# ─── Locate git root ────────────────────────────────────────────────────────
GIT_ROOT=""
if command -v git >/dev/null 2>&1; then
    # Try from the Stop-provided cwd first, then from pwd
    if [ -n "$STOP_CWD" ] && [ -d "$STOP_CWD" ]; then
        GIT_ROOT=$(git -C "$STOP_CWD" rev-parse --show-toplevel 2>/dev/null || true)
    fi
    if [ -z "$GIT_ROOT" ]; then
        GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
    fi
fi

# No git root → nothing to do
[ -n "$GIT_ROOT" ] || exit 0

# ─── GATE: .rcode/ must exist ──────────────────────────────────────────
[ -d "$GIT_ROOT/.rcode" ] || exit 0

# ─── GATE: meaningful activity (commits in last 4h > 0 OR signals today >= 3) ──
COMMITS_4H=0
if command -v git >/dev/null 2>&1; then
    COMMITS_4H=$(git -C "$GIT_ROOT" log --since="4 hours ago" --oneline 2>/dev/null | wc -l | tr -d ' ' || true)
    COMMITS_4H=${COMMITS_4H//[!0-9]/}
    COMMITS_4H=${COMMITS_4H:-0}
fi

SIGNALS_FILE="$HOME/.claude/global-observation/signals.jsonl"
SIGNALS_TODAY=0
TODAY=$(date -u +%Y-%m-%d)
if [ -f "$SIGNALS_FILE" ]; then
    SIGNALS_TODAY=$(grep -c "\"ts\":\"$TODAY" "$SIGNALS_FILE" 2>/dev/null | tr -d '\n' || true)
    SIGNALS_TODAY=${SIGNALS_TODAY//[!0-9]/}
    SIGNALS_TODAY=${SIGNALS_TODAY:-0}
fi

# Exit silently if neither threshold is met
if [ "$COMMITS_4H" -eq 0 ] && [ "$SIGNALS_TODAY" -lt 3 ]; then
    exit 0
fi

# ─── Compute output path ────────────────────────────────────────────────────
UTC_DATE=$(date -u +%Y-%m-%d)
SESSION_SHORT="${SESSION_ID:0:8}"
HANDOFF_FILE="$GIT_ROOT/.rcode/handoff-${UTC_DATE}-${SESSION_SHORT}.md"

# ─── Gather content ─────────────────────────────────────────────────────────
BRANCH="unknown"
if command -v git >/dev/null 2>&1; then
    BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null || echo "unknown")
fi

# Recent commits (4h)
RECENT_COMMITS=""
if command -v git >/dev/null 2>&1; then
    RECENT_COMMITS=$(git -C "$GIT_ROOT" log --since="4 hours ago" --oneline 2>/dev/null || true)
fi
[ -n "$RECENT_COMMITS" ] || RECENT_COMMITS="(none in last 4h)"

# Changed files (git status --porcelain)
CHANGED_FILES=""
if command -v git >/dev/null 2>&1; then
    CHANGED_FILES=$(git -C "$GIT_ROOT" status --porcelain 2>/dev/null || true)
fi
[ -n "$CHANGED_FILES" ] || CHANGED_FILES="(working tree clean)"

# Last agent-log entry (tail of .rcode/agent-log.md if present)
AGENT_LOG_TAIL=""
AGENT_LOG_PATH="$GIT_ROOT/.rcode/agent-log.md"
if [ -f "$AGENT_LOG_PATH" ]; then
    AGENT_LOG_TAIL=$(tail -20 "$AGENT_LOG_PATH" 2>/dev/null || true)
fi
[ -n "$AGENT_LOG_TAIL" ] || AGENT_LOG_TAIL="(agent-log.md not present or empty)"

# UTC timestamp
UTC_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ─── Write handoff doc (idempotent — overwrite if exists) ───────────────────
mkdir -p "$GIT_ROOT/.rcode"

# IMP-071/081 (2026-07-03): ensure snapshots NEVER dirty the tracked tree.
# Root cause of the non-convergent commit loop: this hook embeds HEAD-volatile
# content (git log --since 4h, git status, timestamp) into a TRACKED file —
# every commit changed HEAD, which changed the next snapshot, which dirtied the
# tree again (3+ loop commits observed, ledger IMP-071). A nested
# .rcode/.gitignore keeps handoff snapshots machine-local; the ignore file
# itself has stable content, so the loop converges. Repos where handoff files
# were ALREADY committed need a one-time:  git rm --cached '.rcode/handoff-*.md'
GITIGNORE_T="$GIT_ROOT/.rcode/.gitignore"
if ! grep -qx 'handoff-\*.md' "$GITIGNORE_T" 2>/dev/null; then
    printf '# session handoff snapshots are per-machine transients (IMP-071/081)\nhandoff-*.md\n' >> "$GITIGNORE_T"
fi

cat > "$HANDOFF_FILE" <<HANDOFF_DOC
# Handoff: ${UTC_DATE} — session ${SESSION_SHORT}

> Auto-generated by session-handoff-write.sh — does NOT archive the chat (client action).
> Refresh of previous content if file already existed. Delete safely once read.

## Date

${UTC_NOW}

## Session

- **Session ID:** ${SESSION_ID}
- **CWD at Stop:** ${STOP_CWD}

## Branch

\`${BRANCH}\`

## Recent commits (4h)

\`\`\`
${RECENT_COMMITS}
\`\`\`

## Changed files

\`\`\`
${CHANGED_FILES}
\`\`\`

## Signals today

${SIGNALS_TODAY} observation signal(s) recorded in global-observation/signals.jsonl for ${TODAY}.

## Last agent-log entry

\`\`\`
${AGENT_LOG_TAIL}
\`\`\`
HANDOFF_DOC

# ─── Append pointer to agent-log.md (once per handoff file) ─────────────────
POINTER_LINE="- [Auto-handoff written: ${UTC_DATE} → \`${HANDOFF_FILE}\`]"

if [ -f "$AGENT_LOG_PATH" ]; then
    # Only append if this handoff file path is not already referenced
    if ! grep -qF "$HANDOFF_FILE" "$AGENT_LOG_PATH" 2>/dev/null; then
        printf '\n%s\n' "$POINTER_LINE" >> "$AGENT_LOG_PATH"
    fi
fi

# ─── Done — always exit 0 ────────────────────────────────────────────────────
exit 0
