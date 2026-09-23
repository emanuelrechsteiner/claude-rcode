#!/usr/bin/env bash
# session-start-path-canon-regression.sh — regression suite for the IMP-162
# path-canon block in hooks/session-start-context.sh.
#
# Anlass (IMP-162): 66 "File does not exist" errors over 37 sessions in the
# August 2026 chat analysis, traced to the Bauhof/Haus two-roots split plus
# two dead historical directory names. The fix prints the two real roots (and
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

MARKER="Pfad-Kanon (Zwei-Orte-Steuer, IMP-162"

TESTHOME="$(mktemp -d)"
BAUHOF_DIR="$(mktemp -d)"
FOREIGN_DIR="$(mktemp -d)"
trap 'rm -rf "$TESTHOME" "$BAUHOF_DIR" "$FOREIGN_DIR"' EXIT

echo "── session-start-context.sh path-canon regression (IMP-162) ──"

# ── Case 1: session cwd IS the (test-)Bauhof root → canon must appear. ──
out=$(cd "$BAUHOF_DIR" && HOME="$TESTHOME" \
      CLAUDE_BAUHOF_ROOT="$BAUHOF_DIR" CLAUDE_HAUS_ROOT="$TESTHOME/.claude" \
      CLAUDE_SESSION_NUDGE=0 \
      bash "$HOOK" </dev/null 2>&1)
RC=$?
if printf '%s' "$out" | grep -qF "$MARKER"; then
    ok "framework cwd (Bauhof root): canon appears"
else
    bad "framework cwd (Bauhof root): canon appears" "no marker in:
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

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
