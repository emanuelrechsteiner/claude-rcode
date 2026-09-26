#!/usr/bin/env bash
# session-start-path-canon-regression.sh — regression suite for the IMP-162
# path-canon block in hooks/session-start-context.sh.
#
# Cause (IMP-162): 66 "File does not exist" errors over 37 sessions in the
# August 2026 chat analysis, traced to the workshop/live-install two-roots split
# plus two dead historical directory names. The fix prints the two real roots (and
# names the dead ones) at session start — but ONLY when the session's cwd is
# actually inside one of the two real roots, so it stays silent in unrelated
# projects instead of becoming noise there.
#
# Runs the hook directly with CLAUDE_BAUHOF_ROOT/CLAUDE_HAUS_ROOT overridden
# to temp directories, so this suite never depends on this machine's real
# absolute paths and never touches ~/.claude.
#
# Usage: bash hooks/tests/session-start-path-canon-regression.sh
# Exit: 0 = all cases pass, 1 = at least one failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../session-start-context.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     %s\n' "$1" "$2"; }

MARKER="Path canon (Two-Location Rule, IMP-162"

TESTHOME="$(mktemp -d)"
BAUHOF_DIR="$(mktemp -d)"
FOREIGN_DIR="$(mktemp -d)"
trap 'rm -rf "$TESTHOME" "$BAUHOF_DIR" "$FOREIGN_DIR"' EXIT

echo "── session-start-context.sh path-canon regression (IMP-162) ──"

# ── Case 1: session cwd IS the (test-)workshop root → canon must appear. ──
out=$(cd "$BAUHOF_DIR" && HOME="$TESTHOME" \
      CLAUDE_BAUHOF_ROOT="$BAUHOF_DIR" CLAUDE_HAUS_ROOT="$TESTHOME/.claude" \
      CLAUDE_SESSION_NUDGE=0 \
      bash "$HOOK" </dev/null 2>&1)
RC=$?
if printf '%s' "$out" | grep -qF "$MARKER"; then
    ok "framework cwd (workshop root): canon appears"
else
    bad "framework cwd (workshop root): canon appears" "no marker in:
$out"
fi

# ── Case 2: session cwd is an UNRELATED project → canon must NOT appear. ──
out=$(cd "$FOREIGN_DIR" && HOME="$TESTHOME" \
      CLAUDE_BAUHOF_ROOT="$BAUHOF_DIR" CLAUDE_HAUS_ROOT="$TESTHOME/.claude" \
      CLAUDE_SESSION_NUDGE=0 \
      bash "$HOOK" </dev/null 2>&1)
RC2=$?
if printf '%s' "$out" | grep -qF "$MARKER"; then
    bad "foreign cwd: canon absent" "marker present in:
$out"
else
    ok "foreign cwd: canon absent"
fi

# ── Case 3: the hook exits 0 in both cases (SessionStart must never block). ──
if [[ $RC -eq 0 && $RC2 -eq 0 ]]; then
    ok "hook exits 0 in both cases (framework rc=$RC, foreign rc=$RC2)"
else
    bad "hook exits 0 in both cases" "framework rc=$RC, foreign rc=$RC2"
fi

# ── IMP-219: workshop-root resolution has 3 states — "set" (env var),
#    "file" (~/.claude/env.local.sh), "none" (neither -> "unknown").
#    All three MUST work without any hardcoded machine path in the hook's
#    source, and none of them may ever touch the real ~/.claude — HOME is
#    always overridden to a scratch dir first. ──────────────────────────────
UNKNOWN_MARKER="Workshop: unknown"

# ── Case "set": CLAUDE_BAUHOF_ROOT already set -> shown verbatim, no
#    env.local.sh needed (none exists in TESTHOME), no "unknown" text. ────
out=$(cd "$BAUHOF_DIR" && HOME="$TESTHOME" \
      CLAUDE_BAUHOF_ROOT="$BAUHOF_DIR" CLAUDE_HAUS_ROOT="$TESTHOME/.claude" \
      CLAUDE_SESSION_NUDGE=0 \
      bash "$HOOK" </dev/null 2>&1)
if printf '%s' "$out" | grep -qF "$BAUHOF_DIR" && ! printf '%s' "$out" | grep -qF "$UNKNOWN_MARKER"; then
    ok "Case 'set': env var shown verbatim, no 'unknown'"
else
    bad "Case 'set': env var shown verbatim, no 'unknown'" "$out"
fi

# ── Case "file": no env var, but ~/.claude/env.local.sh (fake HOME) sets
#    CLAUDE_BAUHOF_ROOT -> resolved via the sourced file, no "unknown". ───
ENVLOCAL_HOME="$(mktemp -d)"
mkdir -p "$ENVLOCAL_HOME/.claude"
FILE_BAUHOF_DIR="$(mktemp -d)"
cat > "$ENVLOCAL_HOME/.claude/env.local.sh" <<EOF
export CLAUDE_BAUHOF_ROOT="$FILE_BAUHOF_DIR"
EOF
out=$(cd "$FILE_BAUHOF_DIR" && HOME="$ENVLOCAL_HOME" \
      CLAUDE_HAUS_ROOT="$ENVLOCAL_HOME/.claude" \
      CLAUDE_SESSION_NUDGE=0 \
      env -u CLAUDE_BAUHOF_ROOT bash "$HOOK" </dev/null 2>&1)
if printf '%s' "$out" | grep -qF "$FILE_BAUHOF_DIR" && ! printf '%s' "$out" | grep -qF "$UNKNOWN_MARKER"; then
    ok "Case 'file': resolved via ~/.claude/env.local.sh, no 'unknown'"
else
    bad "Case 'file': resolved via ~/.claude/env.local.sh, no 'unknown'" "$out"
fi
rm -rf "$ENVLOCAL_HOME" "$FILE_BAUHOF_DIR"

# ── Case "none": no env var, no env.local.sh anywhere under this fake
#    HOME -> cwd inside the fake live-install root still fires the canon block
#    (live install is always resolvable from HOME), but the workshop line must
#    read "unknown" and MUST NOT contain any real machine path as a fallback. ──
BLANK_HOME="$(mktemp -d)"
mkdir -p "$BLANK_HOME/.claude"
out=$(cd "$BLANK_HOME/.claude" && HOME="$BLANK_HOME" \
      CLAUDE_SESSION_NUDGE=0 \
      env -u CLAUDE_BAUHOF_ROOT -u CLAUDE_HAUS_ROOT bash "$HOOK" </dev/null 2>&1)
if printf '%s' "$out" | grep -qF "$UNKNOWN_MARKER"; then
    ok "Case 'none': prints '$UNKNOWN_MARKER' when neither env var nor file resolve it"
else
    bad "Case 'none': prints '$UNKNOWN_MARKER' when neither env var nor file resolve it" "$out"
fi
if printf '%s' "$out" | grep -qE '/Volumes/|/Users/'; then
    bad "Case 'none': no hardcoded /Volumes or /Users fallback leaks into output" "$out"
else
    ok "Case 'none': no hardcoded /Volumes or /Users fallback leaks into output"
fi
rm -rf "$BLANK_HOME"

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
