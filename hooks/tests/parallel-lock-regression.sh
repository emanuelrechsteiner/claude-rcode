#!/bin/bash
# parallel-lock-regression.sh — regression suite for the lock registry (IMP-114)
# ─────────────────────────────────────────────────────────────────────────────
# Covers the two defects found on 2026-08-01 and, critically, the property the
# fix must NOT break: a genuinely different agent still gets denied.
#
# Runs entirely in an isolated CLAUDE_LOCK_ROOT — never touches /tmp/claude-locks.
# Usage: bash ~/.claude/hooks/tests/parallel-lock-regression.sh
# ─────────────────────────────────────────────────────────────────────────────
set -u

# IMP-140 (2026-08-22): switched from hardcoded $HOME/.claude/... to the
# self-relative + override pattern every other suite in this directory
# already uses (gate-regression.sh, controller-first-regression.sh, etc.) —
# this file was the one outlier still hardcoded to the installed (live-install)
# copy, which made it structurally incapable of testing an edit made only
# in the workshop working copy (this repo never writes to ~/.claude directly;
# changes only reach it via `claude-deploy`). Defaults are unchanged when run
# from the installed location, so this is not a behavior change post-deploy.
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAIM="${CLAUDE_CLAIM_SCRIPT:-$HOOKS_DIR/../scripts/parallel-claim.sh}"
LOCK_CHECK="${CLAUDE_LOCK_CHECK_HOOK:-$HOOKS_DIR/parallel-lock-check.sh}"
RELEASE_HOOK="${CLAUDE_RELEASE_HOOK:-$HOOKS_DIR/subagent-lock-release.sh}"

export CLAUDE_LOCK_ROOT="$(mktemp -d /tmp/lock-regression.XXXXXX)"
export CLAUDE_COORD_LOG="$CLAUDE_LOCK_ROOT/coord.jsonl"
TARGET="$CLAUDE_LOCK_ROOT/target.ts"; echo "x" > "$TARGET"
TARGET2="$CLAUDE_LOCK_ROOT/target2.ts"; echo "y" > "$TARGET2"
cleanup() { rm -rf "$CLAUDE_LOCK_ROOT"; }
trap cleanup EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected: %s\n     got:      %s\n' "$1" "$2" "$3"; }

# Ask the PreToolUse hook whether an edit is allowed.
# Prints "allow" or "deny".
decision() {
    local file="$1" agent="$2" sess="$3"
    local out
    out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"agent_id":"%s","session_id":"%s"}' \
            "$file" "$agent" "$sess" | bash "$LOCK_CHECK" 2>/dev/null)
    if [ -z "$out" ]; then echo "allow"; else
        printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
    fi
}

echo "── Lock registry regression (IMP-114) ──"

# 1. Unlocked file → allow
r=$(decision "$TARGET" "harness-aaa" "sess-1")
[ "$r" = "allow" ] && ok "unlocked file is editable" || bad "unlocked file is editable" allow "$r"

# 2. THE PRIMARY DEFECT: after the orchestrator claims, the dispatched subagent
#    must be able to edit its own file. Before IMP-114 this returned deny.
bash "$CLAIM" claim "$TARGET" "pdispatch-r1-0" 3600 "sess-1" >/dev/null 2>&1
r=$(decision "$TARGET" "harness-aaa" "sess-1")
[ "$r" = "allow" ] && ok "claimed file editable by its dispatched subagent" || bad "claimed file editable by its dispatched subagent" allow "$r"

# 3. Same agent again → still allow (binding is idempotent)
r=$(decision "$TARGET" "harness-aaa" "sess-1")
[ "$r" = "allow" ] && ok "re-edit by the bound agent stays allowed" || bad "re-edit by the bound agent stays allowed" allow "$r"

# 4. THE PROPERTY THE FIX MUST NOT BREAK: a DIFFERENT agent in the same session
#    must still be denied — this is the collision the registry exists for.
r=$(decision "$TARGET" "harness-bbb" "sess-1")
[ "$r" = "deny" ] && ok "a different agent is still DENIED (protection intact)" || bad "a different agent is still DENIED" deny "$r"

# 5. A different agent from a different session → denied too
r=$(decision "$TARGET" "harness-ccc" "sess-2")
[ "$r" = "deny" ] && ok "foreign session is denied" || bad "foreign session is denied" deny "$r"

# 6. An unbound lock claimed by ANOTHER session must not be bindable
bash "$CLAIM" claim "$TARGET2" "pdispatch-r9-0" 3600 "sess-9" >/dev/null 2>&1
r=$(decision "$TARGET2" "harness-zzz" "sess-1")
[ "$r" = "deny" ] && ok "unbound lock of a foreign session is denied" || bad "unbound lock of a foreign session is denied" deny "$r"

# 7. THE SECOND DEFECT: SubagentStop must actually release.
out=$(printf '{"agent_id":"harness-aaa"}' | bash "$RELEASE_HOOK" 2>&1; bash "$CLAIM" list)
if printf '%s' "$out" | grep -q "target.ts"; then
    bad "SubagentStop releases the bound lock" "target.ts gone" "still listed"
else
    ok "SubagentStop releases the bound lock"
fi

# 8. After release the file is editable by anyone again
r=$(decision "$TARGET" "harness-bbb" "sess-1")
[ "$r" = "allow" ] && ok "released file is editable again" || bad "released file is editable again" allow "$r"

# 9. release-session cleans locks that were claimed but never bound
bash "$CLAIM" release-session "sess-9" >/dev/null 2>&1
bash "$CLAIM" list | grep -q "target2.ts" \
    && bad "release-session removes unbound locks" "target2.ts gone" "still listed" \
    || ok "release-session removes unbound locks"

# 10. Claims are logged, not just releases (the metric gap in F-003)
if grep -q '"event":"claim"' "$CLAUDE_COORD_LOG" 2>/dev/null; then
    ok "claims appear in the coordination log"
else
    bad "claims appear in the coordination log" "a claim event" "none found"
fi

# 11. Every coordination log line is valid JSON
if [ -s "$CLAUDE_COORD_LOG" ] && jq -e -c . "$CLAUDE_COORD_LOG" >/dev/null 2>&1; then
    ok "coordination log is fully machine-readable"
else
    bad "coordination log is fully machine-readable" "all lines parse" "jq failed"
fi

# 12. Legacy locks (no session_id/harness_agent_id) must be bindable, not deadlocked
LEGACY="$CLAUDE_LOCK_ROOT/legacy.ts"; echo "z" > "$LEGACY"
key=$(printf '%s' "$LEGACY" | shasum | awk '{print $1}')
mkdir -p "$CLAUDE_LOCK_ROOT/$key"
jq -n --arg fp "$LEGACY" --argjson exp "$(( $(date +%s) + 3600 ))" \
   '{agent_id:"pdispatch-old-0", file_path:$fp, expires_at_epoch:$exp}' \
   > "$CLAUDE_LOCK_ROOT/$key/owner.json"
r=$(decision "$LEGACY" "harness-new" "sess-new")
[ "$r" = "allow" ] && ok "pre-IMP-114 lock is bindable (no deadlock on migration)" || bad "legacy lock is bindable" allow "$r"

# ── IMP-140 (2026-08-22): release-log sampling ─────────────────────────────
# subagent-lock-release.sh used to log EVERY SubagentStop unconditionally,
# including the overwhelming majority that released 0 locks (measured 4,349
# release records against 10 claim records — 99.8% noise). It now logs
# unconditionally only when a lock was actually released, and samples the
# no-op case 1-in-N (default 20) via $CLAUDE_LOCK_RELEASE_SAMPLE. The lock
# release mechanics (release-all) are untouched — only the logging changed.

# 13. A release for an agent holding NO lock, with sampling forced OFF
# (CLAUDE_LOCK_RELEASE_SAMPLE=0), must write NO log entry at all — this is
# the deterministic form of "no unsampled entry for a no-op release" (with
# sampling off, "unsampled" and "any entry" coincide, so the assertion does
# not depend on $RANDOM).
LINES_BEFORE=$(wc -l < "$CLAUDE_COORD_LOG" 2>/dev/null || echo 0)
CLAUDE_LOCK_RELEASE_SAMPLE=0 bash -c \
    'printf "{\"agent_id\":\"harness-no-lock\"}" | "'"$RELEASE_HOOK"'"' >/dev/null 2>&1
LINES_AFTER=$(wc -l < "$CLAUDE_COORD_LOG" 2>/dev/null || echo 0)
if [ "$LINES_AFTER" -eq "$LINES_BEFORE" ]; then
    ok "no-op release (sampling off) writes no log entry"
else
    bad "no-op release (sampling off) writes no log entry" "$LINES_BEFORE lines" "$LINES_AFTER lines"
fi

# 14. A release that actually held a lock must ALWAYS log — and the earlier
# claim for the same file must also be in the log (both are signal, per the
# rule: claims are always logged, unconditional releases only when real).
TARGET3="$CLAUDE_LOCK_ROOT/target3.ts"; echo "w" > "$TARGET3"
bash "$CLAIM" claim "$TARGET3" "agent-with-lock" 3600 "sess-14" >/dev/null 2>&1
CLAUDE_LOCK_RELEASE_SAMPLE=0 bash -c \
    'printf "{\"agent_id\":\"agent-with-lock\"}" | "'"$RELEASE_HOOK"'"' >/dev/null 2>&1
CLAIM_LOGGED=$(jq -sc '[.[] | select(.event=="claim" and (.file=="'"$TARGET3"'"))] | length' "$CLAUDE_COORD_LOG" 2>/dev/null || echo 0)
RELEASE_LOGGED=$(jq -sc '[.[] | select(.event=="subagent_release" and .agent_id=="agent-with-lock" and (.result | test("released [1-9]")))] | length' "$CLAUDE_COORD_LOG" 2>/dev/null || echo 0)
if [ "${CLAIM_LOGGED:-0}" -ge 1 ] 2>/dev/null && [ "${RELEASE_LOGGED:-0}" -ge 1 ] 2>/dev/null; then
    ok "claim+release with an actually-held lock logs both, unsampled"
else
    bad "claim+release with an actually-held lock logs both, unsampled" "claim>=1 and release>=1" "claim=$CLAIM_LOGGED release=$RELEASE_LOGGED"
fi

# ── IMP-286 (2026-11-11): SubagentStop releases aged UNBOUND claims ───────────
# A claim the subagent never touched has no harness id, so release-all cannot
# match it and it stayed held until TTL (3 stale sets: 5 + 6 + 4 locks, 2026-11-10).
# The hook now also runs `release-stale --older-than 120`: unbound claims only,
# older than 120 min. The hook resolves its claim script under $HOME, so these
# cases run it with a throwaway HOME whose script is a symlink to the workshop copy.
STALE_HOME="$CLAUDE_LOCK_ROOT/home"
mkdir -p "$STALE_HOME/.claude/scripts" && ln -sf "$CLAIM" "$STALE_HOME/.claude/scripts/parallel-claim.sh"
meta_of() { printf '%s/%s/owner.json' "$CLAUDE_LOCK_ROOT" "$(printf '%s' "$1" | shasum | awk '{print $1}')"; }
backdate() { # file, seconds-ago: an old claim that is still live (TTL 1h from now)
    local m t x; m=$(meta_of "$1"); t=$(( $(date +%s) - $2 )); x=$(( $(date +%s) + 3600 ))
    jq --argjson t "$t" --argjson x "$x" '.claimed_epoch = $t | .expires_at_epoch = $x' "$m" > "${m}.tmp" && mv "${m}.tmp" "$m"
}
stop_hook() { printf '%s' "$1" | HOME="$STALE_HOME" bash "$RELEASE_HOOK" >/dev/null 2>&1; }
held() { bash "$CLAIM" list | grep -qF "$1" && echo held || echo free; }

S1="$CLAUDE_LOCK_ROOT/stale-unbound.ts"; echo "s" > "$S1"
S2="$CLAUDE_LOCK_ROOT/fresh-unbound.ts"; echo "s" > "$S2"
S3="$CLAUDE_LOCK_ROOT/bound-running.ts"; echo "s" > "$S3"
bash "$CLAIM" claim "$S1" "pdispatch-r20-0" 3600 "sess-20" >/dev/null 2>&1
bash "$CLAIM" claim "$S2" "pdispatch-r20-1" 3600 "sess-20" >/dev/null 2>&1
bash "$CLAIM" claim "$S3" "pdispatch-r20-2" 3600 "sess-20" >/dev/null 2>&1
bash "$CLAIM" bind "$S3" "harness-run" "sess-20" >/dev/null 2>&1
backdate "$S1" 7200; backdate "$S3" 7200

# 15. THE IMP-286 DEFECT: an aged unbound claim of a stopped worker stays held.
stop_hook '{"agent_id":"harness-stop"}'
[ "$(held "$S1")" = free ] && ok "SubagentStop releases an aged unbound claim (IMP-286)" \
    || bad "SubagentStop releases an aged unbound claim" "stale claim free" "still listed"

# 16. A fresh unbound claim (the worker may not have started yet) is NOT released.
[ "$(held "$S2")" = held ] && ok "fresh unbound claim survives a SubagentStop" \
    || bad "fresh unbound claim survives a SubagentStop" "held" "released"

# 17. A bound claim of a RUNNING agent is never released by age alone.
[ "$(held "$S3")" = held ] && ok "aged BOUND claim of a running agent survives" \
    || bad "aged BOUND claim of a running agent survives" "held" "released"

# 18. Another agent's bound lock (from case 12) is untouched by the sweep.
[ "$(held "$LEGACY")" = held ] && ok "other agents' bound locks are not touched" \
    || bad "other agents' bound locks are not touched" "held" "released"

# 19. release-stale: valid call exits 0; missing or non-numeric age exits 2.
bash "$CLAIM" release-stale --older-than 120 >/dev/null 2>&1; rc_ok=$?
bash "$CLAIM" release-stale --older-than abc >/dev/null 2>&1; rc_bad=$?
[ "$rc_ok" -eq 0 ] && [ "$rc_bad" -eq 2 ] && ok "release-stale validates its age argument" \
    || bad "release-stale validates its age argument" "ok=0 bad=2" "ok=$rc_ok bad=$rc_bad"

# 20. Empty, truncated and non-JSON stdin: the hook exits 0 and does not crash.
rc_all=0
for payload in '' '{"agent_id":' 'not json'; do
    printf '%s' "$payload" | HOME="$STALE_HOME" bash "$RELEASE_HOOK" >/dev/null 2>&1 || rc_all=1
done
[ "$rc_all" -eq 0 ] && ok "empty and malformed stdin do not crash the hook" \
    || bad "empty and malformed stdin do not crash the hook" "exit 0" "non-zero exit"

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
