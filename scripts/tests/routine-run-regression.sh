#!/usr/bin/env bash
# Regression suite for scripts/routine-run.sh — the stdin fix for the
# claude call.
#
# Why this suite exists: all three launchd routines (daily-docs,
# nightly-observation, weekly-improve) have failed with "claude exited 1"
# ever since their very first run on 2026-08-23. Cause: the prompt (the
# full SKILL.md content, starting with the YAML frontmatter "---") was
# passed as a POSITIONAL ARGUMENT. claude's own option parser reads a
# positional argument starting with "--" as an unknown option:
#   claude -p "$(printf -- '---\nname: x\n---\nSag OK')" --model X
#   -> error: unknown option '---
# The fix passes the prompt via STDIN instead
# (`claude -p --model sonnet ... < "$SKILL_FILE"`), which never reaches the
# option parser at all. Reproduced against the real binary (claude 2.1.266,
# 2026-09-09):
#   claude -p "$(printf -- '---\n...')" --model definitiv-kein-modell
#     -> exit 1, "error: unknown option '---"
#   printf -- '---\n...' | claude -p --model definitiv-kein-modell
#     -> exit 1, but ONLY because of the invalid model name — no
#        "unknown option" in stderr. Case D below repeats exactly that.
#
# This suite works EXCLUSIVELY with scratch directories
# (CLAUDE_ROUTINE_CLAUDE_DIR / CLAUDE_ROUTINE_LOG_DIR) and a stub binary
# (CLAUDE_BIN) — it writes nothing under ~/.claude/global-observation/ and
# never triggers a real claude run with a valid model.
#
# Usage: bash scripts/tests/routine-run-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../routine-run.sh"
[ -f "$RUNNER" ] || { echo "routine-run.sh not found: $RUNNER" >&2; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf '  [%s] %s\n' "$1" "$2"; }
check(){ # check <name> <expected> <got>
  if [ "$2" = "$3" ]; then ok; else bad "$1" "expected='$2' got='$3'"; fi
}

ROOT=$(mktemp -d)

# ── Stub claude: writes argv + stdin to files, NEVER calls the real binary.
#    Exit code controllable via STUB_EXIT_CODE (default 0). ────────────────
STUB="$ROOT/claude-stub.sh"
cat > "$STUB" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$@" > "$STUB_ARGV_FILE"
cat > "$STUB_STDIN_FILE"
exit "${STUB_EXIT_CODE:-0}"
STUBEOF
chmod +x "$STUB"

# setup_task <task> -> creates a scratch CLAUDE_DIR with a SKILL.md for <task>
# and sets CDIR/SKILL for the caller.
setup_task() {
  local task="$1"
  CDIR="$ROOT/claude-home-$task"
  mkdir -p "$CDIR/scheduled-tasks/$task"
  SKILL="$CDIR/scheduled-tasks/$task/SKILL.md"
  printf -- '---\nname: %s\ndescription: test routine\n---\nSay OK and stop.\n' "$task" > "$SKILL"
}

# ── A) Stub claude gets the SKILL.md byte-exact via stdin; argv contains
#      NO prompt text and does not start with "---" ────────────────────────
setup_task daily-docs
ARGV_A="$ROOT/argv-a.txt"; STDIN_A="$ROOT/stdin-a.txt"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_A" STUB_STDIN_FILE="$STDIN_A" STUB_EXIT_CODE=0 \
  bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "stdinform/exit0" 0 "$RC"
if [ -f "$STDIN_A" ] && cmp -s "$SKILL" "$STDIN_A"; then ok; else
  bad "stdinform/stdin-byte-exact" "STDIN differs from $SKILL (or is missing)"
fi
check "stdinform/argv-exact" \
  "$(printf '%s\n' -p --model sonnet --dangerously-skip-permissions)" \
  "$([ -f "$ARGV_A" ] && cat "$ARGV_A")"
check "stdinform/argv-does-not-start-with-dashdashdash" 0 \
  "$([ -f "$ARGV_A" ] && head -1 "$ARGV_A" | grep -c '^---')"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-daily-docs" 2>/dev/null

# ── B) Stub claude ends with exit 1 -> runner writes the error line to the
#      run log and itself ends with 1 (existing behavior) ──────────────────
setup_task nightly-observation
LOG_DIR_B="$ROOT/logs-b"
ARGV_B="$ROOT/argv-b.txt"; STDIN_B="$ROOT/stdin-b.txt"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_B" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_B" STUB_STDIN_FILE="$STDIN_B" STUB_EXIT_CODE=1 \
  bash "$RUNNER" nightly-observation >/dev/null 2>&1
RC=$?
check "claudefail/exit1" 1 "$RC"
check "claudefail/log-line" 1 \
  "$(jq -sr '[.[] | select(.note == "runner: claude exited 1 for nightly-observation")] | length' \
     "$LOG_DIR_B/nightly-obs-log.jsonl" 2>/dev/null)"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-nightly-observation" 2>/dev/null

# ── C) Lock already held -> runner aborts WITHOUT calling claude
#      (existing behavior, unchanged by the stdin fix) ─────────────────────
setup_task weekly-improve
LOG_DIR_C="$ROOT/logs-c"
LOCK_DIR_C="${TMPDIR:-/tmp}/claude-routine-lock-weekly-improve"
mkdir -p "$LOCK_DIR_C"
ARGV_C="$ROOT/argv-c.txt"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_C" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_C" STUB_STDIN_FILE="$ROOT/stdin-c.txt" STUB_EXIT_CODE=0 \
  bash "$RUNNER" weekly-improve >/dev/null 2>&1
RC=$?
check "lockheld/exit1" 1 "$RC"
check "lockheld/claude-not-called" 0 "$([ -f "$ARGV_C" ] && echo 1 || echo 0)"
rm -rf "$CDIR"; rmdir "$LOCK_DIR_C" 2>/dev/null

# ── D) Parser proof against the REAL claude binary (only if present):
#      stdin form + a guaranteed-invalid model -> no "unknown option"
#      in stderr. No real run: the invalid model prevents that. ────────────
if command -v claude >/dev/null 2>&1; then
  REAL_CLAUDE="$(command -v claude)"
  PROBE_SKILL="$ROOT/probe-skill.md"
  printf -- '---\nname: probe\n---\nSay OK\n' > "$PROBE_SKILL"
  # Run from a throwaway cwd ($ROOT), never from the project folder: even with
  # an invalid --model, claude still starts a real session and fires
  # SessionStart hooks in whatever directory it's invoked from — running it
  # here would hijack the Cockpit, which follows the newest session per
  # project folder (observed live: the owner's Cockpit jumped to this dead
  # probe session twice).
  REALOUT=$(cd "$ROOT" && timeout 20 "$REAL_CLAUDE" -p --model definitiv-kein-modell < "$PROBE_SKILL" 2>&1)
  check "realbinary/no-unknown-option" 0 "$(printf '%s' "$REALOUT" | grep -c 'unknown option')"
else
  echo "  [skipped] Case D: no real claude binary found on PATH"
fi

# ── E) --dry-run runs the parser proof (IMP-190): the stub binary
#      is ACTUALLY invoked with --model claude-dry-run-proof-invalid
#      (no real run, that's exactly the point) and reports PASS when
#      stderr contains no "unknown option" — the plain stub above never
#      prints anything to stderr, so the proof line here must say PASS. ────
setup_task daily-docs
ARGV_E="$ROOT/argv-e.txt"; STDIN_E="$ROOT/stdin-e.txt"
DRYOUT_E=$(CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_E" STUB_STDIN_FILE="$STDIN_E" STUB_EXIT_CODE=1 \
  bash "$RUNNER" daily-docs --dry-run 2>&1)
RC=$?
check "dryrun-proof/exit0" 0 "$RC"
check "dryrun-proof/contains-parserproof-section" 1 \
  "$(printf '%s\n' "$DRYOUT_E" | grep -c 'parser_proof:')"
check "dryrun-proof/reports-PASS" 1 \
  "$(printf '%s\n' "$DRYOUT_E" | grep -c 'PASS — CLI parser accepted')"
check "dryrun-proof/stub-actually-called-with-invalid-model" 1 \
  "$([ -f "$ARGV_E" ] && grep -c 'claude-dry-run-proof-invalid' "$ARGV_E")"
rm -rf "$CDIR"

# ── F) If the (stub) binary prints "unknown option" to stderr on EVERY
#      call, the parser proof must report that as FAIL instead of
#      swallowing it — and --dry-run still ends in exit 0 regardless
#      (the proof is advisory, not a gate). ──
setup_task nightly-observation
STUB_F="$ROOT/claude-stub-unknownopt.sh"
cat > "$STUB_F" <<'STUBEOF'
#!/bin/bash
echo "error: unknown option '---" >&2
exit 1
STUBEOF
chmod +x "$STUB_F"
DRYOUT_F=$(CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_BIN="$STUB_F" \
  bash "$RUNNER" nightly-observation --dry-run 2>&1)
RC=$?
check "dryrun-proof-fail/exit0-despite-FAIL" 0 "$RC"
check "dryrun-proof-fail/reports-FAIL" 1 \
  "$(printf '%s\n' "$DRYOUT_F" | grep -c 'FAIL — invocation shape')"
rm -rf "$CDIR"

rm -rf "$ROOT"

# ═══════════════════════════════════════════════════════════════════════════
# G) install-routine-timers.sh — render/migration cases (IMP-219)
#
# This group tests scripts/install-routine-timers.sh, not routine-run.sh
# itself — it lives in this file because scripts/tests/routine-run-regression.sh
# is the target named for the render/migration cases in the vault blueprint (P1).
#
# launchctl is NEVER actually invoked: a stub on PATH records every call
# into a log file and always answers with exit 0 (or an empty list for
# "list"). --dry-run must NOT call launchctl AT ALL — a "poison" stub
# checks that by aborting if it is called anyway.
# ═══════════════════════════════════════════════════════════════════════════
INSTALLER="$SCRIPT_DIR/../install-routine-timers.sh"
[ -f "$INSTALLER" ] || { echo "install-routine-timers.sh not found: $INSTALLER" >&2; exit 1; }

GROOT=$(mktemp -d)

# ── G1: --dry-run shows the 3 rendered target paths, does NOT call
#    launchctl (the poison stub aborts and leaves a marker if it is). ───────
G1_HOME="$GROOT/home1"
mkdir -p "$G1_HOME"
POISON_BIN="$GROOT/poison-bin"
mkdir -p "$POISON_BIN"
POISON_MARKER="$GROOT/poison-called"
cat > "$POISON_BIN/launchctl" <<EOF
#!/bin/bash
echo "\$@" >> "$POISON_MARKER"
exit 0
EOF
chmod +x "$POISON_BIN/launchctl"
DRYOUT_G1=$(HOME="$G1_HOME" PATH="$POISON_BIN:$PATH" bash "$INSTALLER" --dry-run 2>&1)
RC_G1=$?
check "install/dryrun-exit0" 0 "$RC_G1"
for t in daily-docs nightly-observation weekly-improve; do
  check "install/dryrun-shows-target-path-$t" 1 \
    "$(printf '%s\n' "$DRYOUT_G1" | grep -c "would write:   $G1_HOME/Library/LaunchAgents/com.claude-code.routine-$t.plist")"
done
check "install/dryrun-never-calls-launchctl" 0 "$([ -f "$POISON_MARKER" ] && echo 1 || echo 0)"

# ── G2: real install (stub launchctl) — precedence satisfied (dummy
#    routine-run.sh present), renders all 3 plists with the real HOME +
#    generic label, boots out the historical label, bootstraps the new one. ──
G2_HOME="$GROOT/home2"
mkdir -p "$G2_HOME/.claude/scripts"
cat > "$G2_HOME/.claude/scripts/routine-run.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$G2_HOME/.claude/scripts/routine-run.sh"

STUB_BIN="$GROOT/stub-bin"
mkdir -p "$STUB_BIN"
LAUNCHCTL_LOG="$GROOT/launchctl.log"
: > "$LAUNCHCTL_LOG"
cat > "$STUB_BIN/launchctl" <<EOF
#!/bin/bash
echo "\$@" >> "$LAUNCHCTL_LOG"
if [ "\$1" = "list" ]; then
  exit 0
fi
exit 0
EOF
chmod +x "$STUB_BIN/launchctl"

OUT_G2=$(HOME="$G2_HOME" PATH="$STUB_BIN:$PATH" bash "$INSTALLER" 2>&1)
RC_G2=$?
check "install/real-exit0" 0 "$RC_G2"
for t in daily-docs nightly-observation weekly-improve; do
  DEST="$G2_HOME/Library/LaunchAgents/com.claude-code.routine-$t.plist"
  if [ -f "$DEST" ] && grep -q "$G2_HOME" "$DEST" && grep -q "com.claude-code.routine-$t" "$DEST" \
     && ! grep -q "__HOME__\|__LABEL__" "$DEST"; then
    ok
  else
    bad "install/rendered-plist-correct-$t" "file missing or still contains a placeholder: $DEST"
  fi
  check "install/bootstrap-called-$t" 1 \
    "$(grep -c "bootstrap gui/$(id -u) $DEST" "$LAUNCHCTL_LOG")"
  check "install/historical-label-booted-out-$t" 1 \
    "$(grep -c "bootout gui/$(id -u)/com.${USER:-$(id -un)}.claude-routine-$t" "$LAUNCHCTL_LOG")"
done

# ── G3: migration — a pre-installed plist under the historical per-user
#    label is removed on install. ───────────────────────────────────────────
G3_HOME="$GROOT/home3"
mkdir -p "$G3_HOME/.claude/scripts" "$G3_HOME/Library/LaunchAgents"
cp "$G2_HOME/.claude/scripts/routine-run.sh" "$G3_HOME/.claude/scripts/routine-run.sh"
chmod +x "$G3_HOME/.claude/scripts/routine-run.sh"
OLD_LABEL="com.${USER:-$(id -un)}.claude-routine-daily-docs"
OLD_PLIST="$G3_HOME/Library/LaunchAgents/${OLD_LABEL}.plist"
echo "<plist/>" > "$OLD_PLIST"
: > "$LAUNCHCTL_LOG"
bash -c "HOME='$G3_HOME' PATH='$STUB_BIN:$PATH' bash '$INSTALLER'" >/dev/null 2>&1
check "install/migration-removes-old-plist" 0 "$([ -f "$OLD_PLIST" ] && echo 1 || echo 0)"
check "install/migration-new-plist-present" 1 \
  "$([ -f "$G3_HOME/Library/LaunchAgents/com.claude-code.routine-daily-docs.plist" ] && echo 1 || echo 0)"

# ── G4: --uninstall (stub launchctl) removes both the new AND the historical
#    label, never actually calls launchctl. ─────────────────────────────────
G4_HOME="$GROOT/home4"
mkdir -p "$G4_HOME/Library/LaunchAgents"
touch "$G4_HOME/Library/LaunchAgents/com.claude-code.routine-daily-docs.plist"
touch "$G4_HOME/Library/LaunchAgents/com.${USER:-$(id -un)}.claude-routine-daily-docs.plist"
: > "$LAUNCHCTL_LOG"
OUT_G4=$(HOME="$G4_HOME" PATH="$STUB_BIN:$PATH" bash "$INSTALLER" --uninstall 2>&1)
RC_G4=$?
check "install/uninstall-exit0" 0 "$RC_G4"
check "install/uninstall-removes-new-plist" 0 \
  "$([ -f "$G4_HOME/Library/LaunchAgents/com.claude-code.routine-daily-docs.plist" ] && echo 1 || echo 0)"
check "install/uninstall-removes-old-plist" 0 \
  "$([ -f "$G4_HOME/Library/LaunchAgents/com.${USER:-$(id -un)}.claude-routine-daily-docs.plist" ] && echo 1 || echo 0)"
check "install/uninstall-only-via-stub" 1 \
  "$([ -s "$LAUNCHCTL_LOG" ] && echo 1 || echo 0)"

rm -rf "$GROOT"

printf '── routine-run-regression: %d passed, %d failed ──\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
