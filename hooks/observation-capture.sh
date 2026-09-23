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
#    "file": "relative/path", "branch": "main", "rcode": true,
#    "intent_source": "commit-subject"}
#
# intent_source (IMP-136, 2026-08-22): "intent" is NOT derived from the edit
# itself — it is a repo-global proxy read off whatever commit happens to sit
# at HEAD at the moment of the edit. One commit subject can span hundreds of
# unrelated edits. Consumers must treat "intent" as a lagging, repo-wide
# heuristic, not a per-edit classification — hence this field is always
# emitted so downstream aggregation (meta-observer, historical-signals) can
# see the provenance rather than assume per-edit fidelity.

LEDGER="${CLAUDE_OBS_LEDGER:-$HOME/.claude/global-observation/signals.jsonl}"
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
# IMP-136 (2026-08-22): every branch below used to match on a bare keyword
# PREFIX ("^fix", "^refactor", ...) with no requirement that the rest of the
# subject actually be conventional-commit shape. A German prose subject like
# "Fix-Runde: 9 Arbeitspakete umgesetzt" starts with "Fix" and was therefore
# stamped intent:"fix" for every Edit/Write that happened while it sat at
# HEAD — 297 edits, 65% of all fix-signals in one repo's window, none of them
# fixes. The type token must now be followed immediately by an optional
# "(scope)", an optional "!", and a mandatory ":" — i.e. actual Conventional
# Commits form (https://www.conventionalcommits.org) — or it falls through
# to "edit". "Fix-Runde: ..." fails this (a literal "-" follows "Fix", not
# "(", "!", or ":"); "fix: ..." and "fix(auth): ..." still match.
# IMP-052: R.Code meta-doc commits (handoff/scope/migration/project/audit/status/
# architecture/conventions) must NOT bleed their full commit type into subsequent
# code-edit signals. A code edit made while such a commit is HEAD is still an "edit",
# not "docs(handoff)". This guard must precede the generic ^(test|docs) arm below.
if echo "$LAST_MSG" | grep -qiE "^docs\((handoff|scope|migration|project|audit|status|architecture|conventions)\):"; then
    INTENT="edit"
elif echo "$LAST_MSG" | grep -qiE "^(fix|bug|hotfix)(\([^)]*\))?!?:"; then
    INTENT="fix"
elif echo "$LAST_MSG" | grep -qiE "^(refactor|cleanup|chore)(\([^)]*\))?!?:"; then
    INTENT="refactor"
elif echo "$LAST_MSG" | grep -qiE "^(feat|feature|add)(\([^)]*\))?!?:"; then
    INTENT="feature"
elif echo "$LAST_MSG" | grep -qiE "^(test|docs)(\([^)]*\))?!?:"; then
    # IMP-119 (2026-08-01): this used to be a bare `${LAST_MSG%%:*}`, which for a
    # conventional-commit subject like "test(gyms): ..." wrote the intent
    # "test(gyms)" — scope and all. Two such values ("test(gyms)", "docs(legacy)")
    # leaked into signals.jsonl and broke the field's enum, so any consumer
    # grouping by intent silently got singleton buckets.
    INTENT="${LAST_MSG%%:*}"     # "test(gyms)"
    INTENT="${INTENT%%(*}"       # → "test"
fi
# Normalize to the documented enum; anything else becomes "edit" rather than a
# free-form string. The field is aggregated by /meta-observe — an open vocabulary
# there is indistinguishable from a real behavioural signal.
case "$INTENT" in
    fix|refactor|feature|docs|test|edit|error) ;;
    *) INTENT="edit" ;;
esac

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
RCODE="false"
[[ -d .rcode ]] && RCODE="true"

# IMP-119: built with jq instead of printf + hand-rolled sed escaping. The old
# version escaped only backslash and quote in file/cwd, and nothing at all in
# $BRANCH or $TOOL_NAME — a branch name with a quote, or any control character
# in a path, produced an unparseable line. This is the same defect that made
# web-fetch-gate.log 0/41 readable (IMP-117); signals.jsonl is the input to the
# entire observation pipeline, so one bad line there is far more expensive.
# Falls back to the previous printf form if jq is somehow unavailable — a
# missing signal is worse than an imperfectly-escaped one.
INTENT_SOURCE="commit-subject"
if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ts "$TS" --arg cwd "$CWD" --arg intent "$INTENT" \
           --arg file "$FILE_PATH" --arg branch "$BRANCH" \
           --argjson rcode "$RCODE" \
           --arg tool "$TOOL_NAME" --arg session_id "$SESSION_ID" \
           --arg intent_source "$INTENT_SOURCE" \
        '{ts:$ts,cwd:$cwd,intent:$intent,file:$file,branch:$branch,rcode:$rcode,tool:$tool,session_id:$session_id,intent_source:$intent_source}' \
        >> "$LEDGER" 2>/dev/null || true
else
    FILE_ESC=$(printf '%s' "$FILE_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')
    CWD_ESC=$(printf '%s' "$CWD" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"ts":"%s","cwd":"%s","intent":"%s","file":"%s","branch":"%s","rcode":%s,"tool":"%s","session_id":"%s","intent_source":"%s"}\n' \
        "$TS" "$CWD_ESC" "$INTENT" "$FILE_ESC" "$BRANCH" "$RCODE" "$TOOL_NAME" "$SESSION_ID" "$INTENT_SOURCE" >> "$LEDGER"
fi

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
