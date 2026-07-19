#!/bin/bash
# PreToolUse hook — enforces correct git identity before commit/config/push operations.
#
# For users with multiple git identities (work vs personal, client A vs client B),
# this hook auto-corrects the local repo's git config based on the cwd. The
# SessionStart `git-identity-check.sh` warning is insufficient because the leak
# happens at commit time, not session start, and warnings are easy to miss mid-session.
#
# This hook runs BEFORE any Bash call involving git commit / git config / gh pr / git push,
# detects the project's identity context from cwd, and auto-corrects the local repo
# git config if it doesn't match.
#
# Customize the identity patterns in derive_identity() below — or, in the future,
# source them from `~/.claude/rules/identity.local.md` (gitignored, per-user overlay).
# Default placeholders below cause the hook to no-op safely on any cwd.
#
# Invocation contract:
#   Reads JSON input from stdin (Claude Code standard).
#   Exit 0 = allow the tool call (we never block — auto-correction is enough).

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_ARGS=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only act on Bash calls that touch git identity
if [[ "$TOOL_NAME" != "Bash" ]]; then exit 0; fi
if ! echo "$TOOL_ARGS" | grep -qE "git (commit|config user|push)|gh (pr|issue) (create|close|comment)"; then exit 0; fi

CWD=$(pwd)

# Identity map — placeholders; customize for your identities.
# See rules/identity.md and templates/identity.local.md.template.
# Returns: echoes "NAME|EMAIL" if identity is unambiguous; echoes nothing if ambiguous
derive_identity() {
    local cwd="$1"
    # PERSONAL identity (placeholder — replace patterns + identity for your setup)
    if echo "$cwd" | grep -qiE "(PERSONAL_IDENTITY_PATTERN)"; then
        echo "PERSONAL_NAME|personal@email.example"
        return
    fi
    # WORK identity (placeholder — replace patterns + identity for your setup)
    if echo "$cwd" | grep -qiE "(WORK_IDENTITY_PATTERN)"; then
        echo "WORK_NAME|work@email.example"
        return
    fi
    # Ambiguous (or placeholders untouched) — leave git config unchanged
    echo ""
}

EXPECTED=$(derive_identity "$CWD")
if [[ -z "$EXPECTED" ]]; then exit 0; fi

EXPECTED_NAME="${EXPECTED%|*}"
EXPECTED_EMAIL="${EXPECTED#*|}"

CURRENT_NAME=$(git config user.name 2>/dev/null)
CURRENT_EMAIL=$(git config user.email 2>/dev/null)

# No git repo → nothing to enforce
if [[ -z "$CURRENT_EMAIL" ]]; then exit 0; fi

# Match: nothing to do
if [[ "$CURRENT_EMAIL" == "$EXPECTED_EMAIL" && "$CURRENT_NAME" == "$EXPECTED_NAME" ]]; then exit 0; fi

# Mismatch: auto-correct LOCAL repo config (never global) and log the correction
git config user.name "$EXPECTED_NAME" 2>/dev/null
git config user.email "$EXPECTED_EMAIL" 2>/dev/null

SIGNALS="$HOME/.claude/global-observation/signals.jsonl"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CWD_ESC=$(printf '%s' "$CWD" | sed 's/\\/\\\\/g; s/"/\\"/g')
PREV_ESC=$(printf '%s' "$CURRENT_EMAIL" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"ts":"%s","cwd":"%s","intent":"identity-autocorrect","file":"","branch":"","rcode":false,"prev_email":"%s","new_email":"%s"}\n' \
    "$TS" "$CWD_ESC" "$PREV_ESC" "$EXPECTED_EMAIL" >> "$SIGNALS"

# Inform via stderr (visible in hook output but non-blocking)
echo "🔧 Identity auto-corrected for this repo: $CURRENT_EMAIL → $EXPECTED_EMAIL" >&2

exit 0
