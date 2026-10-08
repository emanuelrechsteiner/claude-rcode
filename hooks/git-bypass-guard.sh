#!/usr/bin/env bash
# PreToolUse|Bash hook — blocks git hook-bypass (IMP-240).
#
# Mechanism adapted from everything-claude-code scripts/hooks/block-no-verify.js
# (Copyright (c) 2026 Affaan Mustafa, MIT License, commit c70874f). Re-implemented
# in bash + python3 for this framework; no code copied verbatim.
#
# WHY: scripts/git-hooks/pre-commit (vault + scrub gate) and the pre-push scrub
# gate are the last line against real secret values entering history. An agent
# that can run `git commit --no-verify` can skip all of it silently.
#
# Blocked, at COMMAND POSITION only (start, or after ; && || | & newline ( ), also
# inside `bash -c "..."`, `sh -c`, `eval`, here-docs fed to a shell, and `echo ... | sh`):
#   git commit|push|merge|pull|cherry-pick|rebase|am|revert  with  --no-verify (any
#     unambiguous prefix, `=` forms, even after `--`), or  commit -n  (incl. clusters
#     such as -an; NOT push -n, which is --dry-run, NOT log/tag/clean/stash -n)
#   git -c core.hooksPath=... <protected cmd>   (also --config-env, -ccore.hooksPath=)
#   git config core.hooksPath <v> | --unset | --add | --replace-all | set | unset
#     (read forms --get/--get-all/--get-regexp/--list/bare key stay allowed)
#   HUSKY=0, HUSKY_SKIP_HOOKS=*, VAULT_PRECOMMIT_BYPASS=<any value>, GIT_CONFIG_KEY_n=core.hooksPath,
#     GIT_CONFIG_PARAMETERS=...hooksPath... set before a protected git command
#     (inline prefix, env/sudo/nice/timeout/arch/caffeinate/stdbuf/setsid wrapper, or an
#     earlier export in the same command string)
# Mentions inside quotes, here-doc bodies of non-shells, echo/printf/grep/jq args,
# `git log --grep no-verify` never fire.
#
# Override (single-use, op-bound, logged authorizer=user): after the USER approves,
# re-run the same command with CLAUDE_GIT_BYPASS_ACK=<sha256 of normalized command>
# prepended (the block message prints the exact line). Replays re-block.
# CLAUDE_GATE_TESTMODE=1 exempts (logged to a separate test log).
# Fails OPEN (exit 0) on unparsable JSON / empty command. A classifier crash, missing
# python3 or missing jq is NOT silent: if the raw input mentions git/HUSKY/
# VAULT_PRECOMMIT/GIT_CONFIG the hook emits a native permissionDecision "ask";
# otherwise it exits 0. Crash output is appended to the log.
#
# KNOWN LIMITS (not chased): alias resolution (git ci, -c alias.*), --git-dir pointing at
# another repo's hooks, plumbing (commit-tree, update-ref), chmod/rm of .git/hooks, $X
# variable expansion, xargs/find -exec, log tampering. This is a fence against ACCIDENTAL
# bypass, not a wall against deliberate evasion.
#
# Exit: 0 allow, 2 block.

set -uo pipefail

INPUT=$(cat 2>/dev/null || printf '')
LOG_DIR="$HOME/.claude/global-observation"
LOG_FILE="$LOG_DIR/git-bypass-guard.log"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
GIT_RE='(^|[^[:alnum:]_])git([^[:alnum:]_]|$)|HUSKY|VAULT_PRECOMMIT|GIT_CONFIG'

log_line() { # band token sig authorizer detail [file]
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ts "$TS" --arg band "$1" --arg token "$2" --arg sig "$3" \
      --arg authorizer "$4" --arg detail "$5" --arg cwd "$(pwd)" \
      '{ts:$ts,band:$band,token:$token,sig:$sig,authorizer:$authorizer,detail:$detail,cwd:$cwd}' \
      >> "${6:-$LOG_FILE}" 2>/dev/null || true
  else
    printf '{"ts":"%s","band":"%s","token":"%s","sig":"%s","authorizer":"%s","detail":"%s"}\n' \
      "$TS" "$1" "$2" "$3" "$4" "$(printf '%s' "$5" | tr -d '"\\' | tr '\n' ' ')" >> "${6:-$LOG_FILE}" 2>/dev/null || true
  fi
}

# Degraded mode: cannot analyze. Never silent for anything git-shaped -> native ask.
degraded() { # why  raw-text-to-test
  log_line ERROR none "" none "$1"
  if printf '%s' "$2" | grep -qiE "$GIT_RE"; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"git-bypass-guard could not analyze this command (%s); confirm it contains no git hook bypass (--no-verify, -n, core.hooksPath, HUSKY=0)."}}\n' \
      "$(printf '%s' "$1" | tr -d '"\\' | tr '\n' ' ' | cut -c1-120)"
  else
    echo "git-bypass-guard: WARNING analysis unavailable ($1); command is not git-related, allowed (logged)." >&2
  fi
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then degraded "jq not found" "$INPUT"; fi
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || printf '')
HOOK_SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || printf '')

[ -z "$COMMAND" ] && exit 0

if [ "${CLAUDE_GATE_TESTMODE:-}" = "1" ]; then
  log_line TESTMODE none "" testmode "" "$LOG_DIR/git-bypass-guard-test.log"
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then degraded "python3 not found" "$COMMAND"; fi
ERRF=$(mktemp "${TMPDIR:-/tmp}/gbg-err.XXXXXX")
VERDICT=$(GBG_CMD="$COMMAND" python3 "$(dirname "${BASH_SOURCE[0]}")/lib/git-bypass-classify.py" 2>"$ERRF")
RC=$?
CRASH=$(head -c 1500 "$ERRF" | tr '\n' ' '); rm -f "$ERRF"
if [ "$RC" -ne 0 ] || [ -z "$VERDICT" ]; then degraded "classifier failed rc=$RC: $CRASH" "$COMMAND"; fi
[ "$VERDICT" = "ALLOW" ] && exit 0

IFS=$'\t' read -r _ REASON GATE SIG <<<"$VERDICT"
SESS="${HOOK_SESSION_ID:-${CLAUDE_SESSION_ID:-$PPID}}"
CONSUMED_FILE="$LOG_DIR/.git-bypass-consumed-$SESS"
PROVIDED_ACK=$(printf '%s' "$COMMAND" | grep -oE 'CLAUDE_GIT_BYPASS_ACK=[A-Fa-f0-9]{64}' | head -1 | cut -d= -f2 || true)

if [ -n "$PROVIDED_ACK" ]; then
  if [ "$PROVIDED_ACK" != "$SIG" ]; then
    log_line BLOCK ack-mismatch "$SIG" none "$REASON"
    echo "git-bypass-guard: BLOCKED ($REASON) — CLAUDE_GIT_BYPASS_ACK does not match this command; ask the user, then re-run: CLAUDE_GIT_BYPASS_ACK=$SIG $COMMAND" >&2
    exit 2
  fi
  if [ -f "$CONSUMED_FILE" ] && grep -qxF "$SIG" "$CONSUMED_FILE" 2>/dev/null; then
    log_line BLOCK replay "$SIG" none "$REASON"
    echo "git-bypass-guard: BLOCKED ($REASON) — ack token already consumed (single-use); ask the user again." >&2
    exit 2
  fi
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s\n' "$SIG" >> "$CONSUMED_FILE" 2>/dev/null || true
  log_line BLOCK consumed "$SIG" user "$REASON"
  echo "NOTE: git-bypass-guard ack valid — allowing this single user-approved bypass ($REASON), logged." >&2
  exit 0
fi

log_line BLOCK none "$SIG" none "$REASON"
{
  echo "git-bypass-guard: BLOCKED — $REASON would skip $GATE; git hooks must not be bypassed by agents."
  echo "Ask the user (verbatim y/n). If approved, re-run EXACTLY (op-bound, single-use, logged):"
  echo "  CLAUDE_GIT_BYPASS_ACK=$SIG $COMMAND"
} >&2
exit 2
