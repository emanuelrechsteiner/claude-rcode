#!/bin/bash
# observation-intent-regression.sh — regression suite for the commit-subject
# intent classifier in hooks/observation-capture.sh (IMP-136, 2026-08-22)
# ─────────────────────────────────────────────────────────────────────────────
# Finding: the classifier matched intent on a bare keyword PREFIX
# ("^fix", "^refactor", ...) with no requirement that the rest of the subject
# be actual Conventional Commits shape. In one repository, a German prose
# commit "Fix-Runde: 9 Arbeitspakete umgesetzt" sat at HEAD while 297
# unrelated Edit/Write events fired — every one of them was stamped
# intent:"fix" (65% of all fix-signals in that window), because "Fix-Runde"
# starts with "Fix". A second, unrelated repository uses real Conventional
# Commits subjects throughout and must keep classifying correctly after the
# fix.
#
# The fix requires the type token to be followed immediately by an optional
# "(scope)", an optional "!", and a mandatory ":" before falling back to
# "edit" — i.e. https://www.conventionalcommits.org form, not a keyword
# prefix. This suite proves both directions: the false-positive class is
# gone, and the true-positive class (real conventional commits) still works.
#
# Uses a REAL temp git repo (not a stubbed `git` binary) to control HEAD's
# subject — the same technique already used by
# hooks/tests/git-state-check-regression.sh in this directory. This is more
# faithful than a fake-git PATH shim (the hook's actual `git log -1
# --pretty=%s` runs unmodified) and avoids maintaining a second git stub.
#
# The signals ledger path is overridden via $CLAUDE_OBS_LEDGER (added to
# hooks/observation-capture.sh by this same change) so this suite never
# touches ~/.claude/global-observation/signals.jsonl — everything happens in
# an isolated $WORK dir.
#
# Aufruf:  bash hooks/tests/observation-intent-regression.sh
# Exit:    0 = alle Fälle grün · 1 = mindestens ein Fall rot
# ─────────────────────────────────────────────────────────────────────────────
set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${CLAUDE_OBS_HOOK:-$HOOKS_DIR/observation-capture.sh}"
[ -f "$HOOK" ] || { echo "FEHLER: Hook nicht gefunden: $HOOK" >&2; exit 1; }

WORK=$(mktemp -d /tmp/obs-intent-regression.XXXXXX)
REPO="$WORK/repo"
LEDGER="$WORK/signals.jsonl"
SESSION_ID="obs-intent-test-$$"
QUEUE_FILE="/tmp/claude-edit-queue-${SESSION_ID}.txt"
TRACK_FILE="/tmp/claude-reads-${SESSION_ID}.txt"
cleanup() { rm -rf "$WORK" "$QUEUE_FILE" "$TRACK_FILE"; }
trap cleanup EXIT

mkdir -p "$REPO"
git -C "$REPO" init -q .
git -C "$REPO" config user.email "test@example.invalid"
git -C "$REPO" config user.name "Regression Test"
git -C "$REPO" commit --allow-empty -q -m "initial"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected intent=%s got=%s (subject: %s)\n' "$1" "$2" "$3" "$4"; }

# Sets $REPO's HEAD subject to $1, then invokes the hook exactly once from
# inside $REPO and returns the .intent field the hook wrote to $LEDGER.
run_case() {
    local subject="$1"
    git -C "$REPO" commit --allow-empty -q -m "$subject" >/dev/null 2>&1

    : > "$LEDGER"   # isolate: only this invocation's line should exist after
    (
        cd "$REPO" || exit 1
        # NOTE: a var=value prefix on a pipeline only scopes to the FIRST
        # command (printf here), not the piped-to command — export is
        # required so $HOOK actually sees the override.
        export CLAUDE_OBS_LEDGER="$LEDGER"
        printf '{"tool_name":"Edit","tool_input":{"file_path":"x.ts"},"session_id":"%s"}' "$SESSION_ID" \
            | bash "$HOOK" >/dev/null 2>&1
    )

    jq -r '.intent' "$LEDGER" 2>/dev/null | tail -1
}

check() {
    local desc="$1" subject="$2" expected="$3"
    local got
    got=$(run_case "$subject")
    if [ "$got" = "$expected" ]; then
        ok "$desc"
    else
        bad "$desc" "$expected" "$got" "$subject"
    fi
}

echo "── Intent classifier regression (IMP-136) ──"
echo ""
echo "── The finding: German prose starting with a type keyword ──"

# The exact reported case: must NOT be stamped fix.
check "German prose 'Fix-Runde: ...' is NOT fix" \
    "Fix-Runde: 9 Arbeitspakete umgesetzt" "edit"
# Same class on a different type keyword, proving the fix isn't fix-only.
check "German prose 'Refactor-Runde: ...' is NOT refactor" \
    "Refactor-Runde: mehrere Module überarbeitet" "edit"

echo ""
echo "── Real Conventional Commits subjects (second repo) still classify ──"

check "'fix: typo' is fix"                      "fix: typo"                          "fix"
check "'fix(auth): token refresh' is fix"       "fix(auth): token refresh"           "fix"
check "'bug: crash on null' is fix"             "bug: crash on null"                 "fix"
check "'feat: add login' is feature"            "feat: add login"                    "feature"
check "'feat(auth): add login flow' is feature" "feat(auth): add login flow"         "feature"
check "'refactor: simplify parser' is refactor" "refactor: simplify parser"          "refactor"
check "'chore: bump deps' is refactor"          "chore: bump deps"                   "refactor"
check "'docs: update readme' is docs"           "docs: update readme"                "docs"
check "'test(gyms): add coverage' is test, scope stripped (IMP-119)" \
    "test(gyms): add coverage" "test"
check "'docs(handoff): session summary' is edit (IMP-052 meta-doc guard)" \
    "docs(handoff): session summary" "edit"

echo ""
echo "── Edge cases: word-boundary, not just the one reported subject ──"

check "'fixing typo issue' (no ':' right after the type) is edit" \
    "fixing typo issue" "edit"
check "bare 'fix' with no colon at all is edit" \
    "fix" "edit"
check "unrelated prose commit is edit" \
    "Some unrelated commit message" "edit"

echo ""
echo "── intent_source provenance field is always present ──"
: > "$LEDGER"
(
    cd "$REPO" || exit 1
    export CLAUDE_OBS_LEDGER="$LEDGER"
    printf '{"tool_name":"Edit","tool_input":{"file_path":"x.ts"},"session_id":"%s"}' "$SESSION_ID" \
        | bash "$HOOK" >/dev/null 2>&1
)
SRC=$(jq -r '.intent_source' "$LEDGER" 2>/dev/null | tail -1)
if [ "$SRC" = "commit-subject" ]; then
    ok "intent_source:\"commit-subject\" is emitted"
else
    bad "intent_source:\"commit-subject\" is emitted" "commit-subject" "$SRC" "(n/a)"
fi

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
