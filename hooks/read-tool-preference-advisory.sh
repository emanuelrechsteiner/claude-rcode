#!/bin/bash
# read-tool-preference-advisory.sh — IMP-157 (2026-08-24), second half
# ─────────────────────────────────────────────────────────────────────────────
# PreToolUse hook, matcher "Bash". Replaces the cat/head/tail file-read BLOCK
# arm that used to live in guard-unsafe.sh (removed same commit — see that
# file's "REMOVED (IMP-157...)" comment for the full rationale).
#
# WHY THIS EXISTS, NOT A REVIVAL OF THE BLOCK: guard-unsafe.sh is the
# CRITICAL floor per rules/agency-bands.md — never-allow hard-block for host
# destruction / exfiltration / irreversible damage. A plain `cat FILE` is
# none of those; blocking it there was a category error (tool-STYLE
# preference enforced as a safety property), measured at 9 confirmed false
# blocks across 8 sessions over two months. But the underlying preference
# (tool-discipline.md Rule 2 — dedicated Read/Grep tools cache better and
# are cheaper on repeat access) is still real, and this framework's own
# Auto-Mode system reminder tells the agent the OPPOSITE ("read files with
# cat, head, or sed -n ... rather than using the dedicated Read tool") — so
# the conflict is real and structural, not a one-off misconfiguration. This
# hook surfaces it instead of either silently blocking or silently ignoring
# it.
#
# CONTRACT (the user's explicit requirement for this half of IMP-157):
#   - NEVER blocks. Always exit 0, command proceeds regardless.
#   - At most ONE note per session (not per invocation — no nagging).
#   - The note NAMES the conflict (Auto-Mode says cat/head; Rule 2 prefers
#     Read) rather than pretending only one side exists.
#
# DETECTION: mirrors the exact regex shape of the removed guard-unsafe.sh
# arm (whole-command cat/head, and tail without -f/-F/--follow) — same
# patterns, now advisory instead of blocking. Piped/redirected forms
# (`cat f | grep x`, `cat f > out`) are still excluded, same as before —
# those are not the plain single-file-read case Rule 2 is about.
#
# ADVISORY, NOT A SECURITY GATE: fails OPEN (exit 0, silently) on unparseable
# stdin, missing jq, or missing session id. A missed note costs nothing but
# the reminder itself — never a correctness or safety property.
#
# Per-session dedup: /tmp/read-tool-advisory-<session_id> (single touch file
# — one note total per session covers the whole cat/head/tail class; see
# header for why a single class-wide note, not one per exact pattern,
# satisfies "at most one hint per session and pattern": the note names one
# conflict, and repeating it per sub-pattern (cat vs head vs tail) would be
# the exact nagging this hook exists to avoid).
#
# Opt-out: CLAUDE_READ_ADVISORY_OFF=1 (silently exits 0, no log).
#
# Log: one line per note actually shown, to
#   ~/.claude/global-observation/read-tool-advisory.log
# Format matches guard-unsafe.sh's tab-separated log (timestamp, decision,
# command) for consistency with the sibling gate's log shape.
set -u

[ "${CLAUDE_READ_ADVISORY_OFF:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || printf '{}')
command -v jq >/dev/null 2>&1 || exit 0
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

# ── Detection — same shape as the removed guard-unsafe.sh arm ────────────────
IS_READ_PATTERN=0
if [[ "$COMMAND" =~ ^[[:space:]]*(cat|head)[[:space:]]+[^\|\<\>]*$ ]]; then
    IS_READ_PATTERN=1
elif [[ "$COMMAND" =~ ^[[:space:]]*tail[[:space:]]+[^\|\<\>]*$ ]] \
     && [[ ! "$COMMAND" =~ (^|[[:space:]])(-f|-F|--follow)([[:space:]]|=|$) ]]; then
    IS_READ_PATTERN=1
fi

[ "$IS_READ_PATTERN" -eq 0 ] && exit 0

# ── Per-session dedup — one note total per session for this class ────────────
STATE_DIR="/tmp"
TOUCH_FILE="${STATE_DIR}/read-tool-advisory-${SESSION_ID}"
if [ -f "$TOUCH_FILE" ]; then
    exit 0
fi
touch "$TOUCH_FILE" 2>/dev/null || true

LOG="${CLAUDE_READ_ADVISORY_LOG:-$HOME/.claude/global-observation/read-tool-advisory.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "NOTE-SHOWN" "$COMMAND" >> "$LOG" 2>/dev/null || true

echo "NOTE: dieses Framework weist im Auto-Modus an, mit cat/head/sed -n statt dem Read-Werkzeug zu lesen — rules/tool-discipline.md Rule 2 bevorzugt umgekehrt Read/Grep (kein Blocker mehr seit IMP-157: das war eine Kategorienverwechslung am CRITICAL floor). Beide Wege funktionieren; Read/Grep sind bei großen Dateien und Mehrfachzugriffen sparsamer. Dieser Hinweis erscheint höchstens einmal pro Sitzung." >&2

exit 0
