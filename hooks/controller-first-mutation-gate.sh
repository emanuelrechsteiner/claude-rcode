#!/bin/bash
# controller-first-mutation-gate.sh — IMP-090 (2026-07-15, Controller-First Enforcement)
# ─────────────────────────────────────────────────────────────────────────────
# PreToolUse hook on Write|Edit and (narrowly classified) Bash. Enforces the
# "no non-trivial mutation reaches execution before a Controller step ran in
# this session" invariant from the meta-proposal
# (~/.claude/plans/meta-proposal-2026-07-15-controller-first-enforcement.md,
# IMP-090 / GRAFT-G1). This hook is a synchronous shell script — like
# excessive-agency-gate.sh, it CANNOT invoke an LLM and does not make the
# judgment "was this decomposed correctly"; it only enforces the deterministic
# precondition "did SOME controller step run first".
#
# Session state (written by sibling hooks, READ-ONLY here):
#   /tmp/controller-first-<session_id>/substantial     — controller-first-prompt-gate.sh
#   /tmp/controller-first-<session_id>/controller-ran  — controller-first-subagent-flag.sh
#
# Modes (env CLAUDE_CONTROLLER_GATE_MODE — DEFAULT and INITIAL-ROLLOUT value
# is "note", per the migration plan's NOTE-only observation week):
#   note    → NEVER blocks. Emits a non-blocking stderr NOTE when a gate-worthy
#             mutation is seen without a prior controller step. exit 0 ALWAYS.
#   enforce → exit 2 when: substantial-flag set AND controller-ran-flag absent
#             AND the target is not exempt AND (for Bash) the command
#             classifies as a mutation at command position. Everything else:
#             exit 0.
#
# Exemptions (never gated, in EITHER mode): scratchpad dirs, /tmp, /private/tmp,
# .rcode/, agent-log*, PROJECT-STATUS*, plans/ — per the IMP-090 spec.
#
# Unlock (enforce mode only): CLAUDE_CONTROLLER_ACK_ONCE=<sha256>, op-bound,
# single-use — 1:1 pattern from excessive-agency-gate.sh (consumed-registry +
# ack-mismatch logging). For Bash the token is parsed FROM the command string
# (env exports do not reliably reach the hook subprocess — same reasoning as
# excessive-agency-gate.sh's header comment). For Write/Edit there is no
# command string to parse; the hook additionally accepts the token from its
# OWN process env (${CLAUDE_CONTROLLER_ACK_ONCE}) as a best-effort fallback.
# RESTLÜCKE (documented, not silently assumed away): the env-var fallback only
# works if the harness propagates that variable into the hook subprocess,
# which is NOT guaranteed for a value set via a prior tool call. The reliable
# unlock for Write/Edit is the controller-ran session flag, not the ack token.
#
# CLAUDE_GATE_TESTMODE=1 exempts the hook's own regression suite from self-block.
#
# Logging: ~/.claude/global-observation/controller-first.log (JSONL, one line
# per non-silent decision — mirrors excessive-agency.log's shape).
set -u

INPUT=$(cat 2>/dev/null || printf '{}')
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || printf '')
HOOK_SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || printf '')

LOG_DIR="$HOME/.claude/global-observation"
LOG_FILE="$LOG_DIR/controller-first.log"

# Only gate Write, Edit, Bash. Everything else (Read, Grep, MCP, ...) passes
# silently — this hook has nothing to say about non-mutating tools.
case "$TOOL" in
  Write|Edit|Bash) ;;
  *) exit 0 ;;
esac

# ── Test-mode exemption (mirrors excessive-agency-gate.sh's D6) ──────────────
if [ "${CLAUDE_GATE_TESTMODE:-}" = "1" ]; then
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '{"ts":"%s","band":"TESTMODE","authorizer":"testmode","cwd":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(pwd)" >> "$LOG_DIR/controller-first-test.log" 2>/dev/null || true
  exit 0
fi

MODE="${CLAUDE_CONTROLLER_GATE_MODE:-note}"

FILE_PATH=""
COMMAND=""
if [ "$TOOL" = "Bash" ]; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || printf '')
else
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || printf '')
fi

# ── Bash mutation classification (narrow, command-position) ───────────────────
# Only a Bash command that classifies as MUTATION reaches the rest of this
# gate — the overwhelming majority of Bash traffic (reads, greps, git
# status/log/diff — the agency-bands.md AUTO list) is never touched here,
# regardless of mode. This is intentionally narrower than excessive-agency-
# gate.sh's ESCALATE set: this gate cares about ANY mutation, not just
# irreversible ones, but "any mutation" still excludes pure reads.
#
# CLASS\tSIG is computed in one python pass: SIG is the sha256 of the
# data-stripped, whitespace-collapsed, ack-prefix-stripped command — same
# normalization recipe as excessive-agency-gate.sh, so a re-run with the ack
# token prepended hashes to the same signature as the original blocked command.
if [ "$TOOL" = "Bash" ]; then
  [ -n "$COMMAND" ] || exit 0
  RESULT=$(CFG_CMD="$COMMAND" python3 <<'PYEOF' 2>/dev/null
import os, re, hashlib, sys
cmd = os.environ.get("CFG_CMD", "")
if not cmd.strip():
    sys.stdout.write("READONLY\t"); sys.exit(0)

def strip_data(s):
    out, in_h, tag = [], False, None
    hd = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")
    for ln in s.split("\n"):
        if in_h:
            if ln.strip() == tag:
                in_h = False
            continue
        m = hd.search(ln)
        if m:
            tag = m.group(1); in_h = True; out.append(ln[:m.start()]); continue
        out.append(ln)
    s = "\n".join(out)
    s = re.sub(r"'[^']*'", "", s)
    s = re.sub(r'"[^"]*"', "", s)
    return s

cmd_nosig = re.sub(r"CLAUDE_CONTROLLER_ACK_ONCE=[A-Fa-f0-9]+\s*", "", cmd)
stripped = strip_data(cmd_nosig)
norm = re.sub(r"\s+", " ", stripped).strip()
sig = hashlib.sha256(norm.encode("utf-8", "replace")).hexdigest()

CP = r"(?:^|[\n;]|&&|\|\||(?<![|&])\|(?![|&]))[ \t]*(?:[A-Za-z_][A-Za-z0-9_]*=\S*[ \t]+)*"
GIT = r"git(?:\s+-[cC]\s+\S+)*\s+"

MUTATION_HEAD = (
    GIT + r"(add|commit|mv|rm|merge|rebase|cherry-pick|revert|stash|tag|checkout\s+-b)\b"
    r"|\b(mv|cp|touch|mkdir|rmdir|ln|chmod|chown|rsync)\b"
    r"|\bsed\s+-i\b"
    r"|\btee\b"
    r"|\b(npm|pnpm|yarn)\s+(install|ci|add|remove|uninstall)\b"
    r"|\bpip3?\s+install\b"
    r"|\bwget\b"
    r"|\bcurl\b.*-[oO]\b"
)

cls = "READONLY"
if re.search(CP + "(?:" + MUTATION_HEAD + ")", stripped):
    cls = "MUTATION"
# bare output-redirection at top level (best-effort; quoted content already
# stripped above, so a surviving unescaped >/>>  is a real redirection, not
# string data). Known false-positive surface: heredoc `<<` markers already
# consumed by strip_data; `=>`/`->` tokens (e.g. arrow functions) can still
# slip through as a false positive — documented restlücke, not silently hidden.
if cls == "READONLY" and re.search(r"(?<![=<-])>{1,2}(?!=)", stripped):
    cls = "MUTATION"

sys.stdout.write("%s\t%s" % (cls, sig))
PYEOF
) || RESULT="READONLY\t"
  CLASS=$(printf '%s' "$RESULT" | cut -f1)
  BASH_SIG=$(printf '%s' "$RESULT" | cut -f2)
  [ "$CLASS" = "MUTATION" ] || exit 0
fi

# ── Exemptions (Scratchpad, /tmp, .rcode/, agent-log, PROJECT-STATUS, plans/) ──
TARGET="${FILE_PATH:-$COMMAND}"
if printf '%s' "$TARGET" | grep -qiE '(scratchpad|/tmp/|/private/tmp/|\.rcode/|agent-log|PROJECT-STATUS|(^|/)plans/)'; then
  exit 0
fi

# ── Session state (read-only) ─────────────────────────────────────────────────
SESS="${HOOK_SESSION_ID:-${CLAUDE_SESSION_ID:-$PPID}}"
STATE_DIR="/tmp/controller-first-$SESS"
SUBSTANTIAL=0
[ -f "$STATE_DIR/substantial" ] && SUBSTANTIAL=1
CONTROLLER_RAN=0
[ -f "$STATE_DIR/controller-ran" ] && CONTROLLER_RAN=1

# Not (yet) flagged substantial, or a controller already ran this session →
# nothing to gate.
if [ "$SUBSTANTIAL" != "1" ] || [ "$CONTROLLER_RAN" = "1" ]; then
  exit 0
fi

# ── op signature (for ack-token matching + logging) ───────────────────────────
if [ "$TOOL" = "Bash" ]; then
  SIG="$BASH_SIG"
else
  SIG=$(printf '%s|%s' "$TOOL" "$FILE_PATH" | shasum -a 256 2>/dev/null | awk '{print $1}')
fi
[ -n "$SIG" ] || SIG="unknown"

mkdir -p "$LOG_DIR" 2>/dev/null || true
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
CWD=$(pwd)

# ── note mode: never block, one-line stderr note, logged ─────────────────────
if [ "$MODE" != "enforce" ]; then
  printf '{"ts":"%s","mode":"note","tool":"%s","sig":"%s","cwd":"%s"}\n' \
    "$TS" "$TOOL" "$SIG" "$CWD" >> "$LOG_FILE" 2>/dev/null || true
  echo "NOTE: controller-first-mutation-gate (note mode) — substantial task, no Controller step detected yet in this session for $TOOL. Not blocking. Set CLAUDE_CONTROLLER_GATE_MODE=enforce to make this a hard gate." >&2
  exit 0
fi

# ── enforce mode: check ack token first ───────────────────────────────────────
PROVIDED_ACK=""
if [ "$TOOL" = "Bash" ]; then
  PROVIDED_ACK=$(printf '%s' "$COMMAND" \
    | grep -oE 'CLAUDE_CONTROLLER_ACK_ONCE=[A-Fa-f0-9]{64}' \
    | head -1 | cut -d= -f2 || true)
fi
[ -n "$PROVIDED_ACK" ] || PROVIDED_ACK="${CLAUDE_CONTROLLER_ACK_ONCE:-}"

CONSUMED_FILE="/tmp/controller-first-ack-consumed-$SESS"

if [ -n "$PROVIDED_ACK" ]; then
  if [ "$PROVIDED_ACK" = "$SIG" ]; then
    if [ -f "$CONSUMED_FILE" ] && grep -qxF "$SIG" "$CONSUMED_FILE" 2>/dev/null; then
      printf '{"ts":"%s","tool":"%s","band":"ESCALATE","token":"replay","sig":"%s","cwd":"%s","authorizer":"none"}\n' \
        "$TS" "$TOOL" "$SIG" "$CWD" >> "$LOG_FILE" 2>/dev/null || true
      {
        echo ""
        echo "CONTROLLER-FIRST GATE — ack token already consumed (replay) for this op."
        echo "Each approval is single-use and op-bound. Re-ask the user before re-running."
      } >&2
      exit 2
    fi
    printf '%s\n' "$SIG" >> "$CONSUMED_FILE" 2>/dev/null || true
    printf '{"ts":"%s","tool":"%s","band":"ESCALATE","token":"consumed","sig":"%s","cwd":"%s","authorizer":"user"}\n' \
      "$TS" "$TOOL" "$SIG" "$CWD" >> "$LOG_FILE" 2>/dev/null || true
    echo "NOTE: controller-first ack token valid — allowing this single user-approved mutation, logged." >&2
    exit 0
  else
    printf '{"ts":"%s","tool":"%s","band":"ESCALATE","token":"ack-mismatch","sig":"%s","cwd":"%s","authorizer":"none"}\n' \
      "$TS" "$TOOL" "$SIG" "$CWD" >> "$LOG_FILE" 2>/dev/null || true
    {
      echo ""
      echo "CONTROLLER-FIRST GATE — ack-token MISMATCH."
      echo "The provided CLAUDE_CONTROLLER_ACK_ONCE does not match this op's signature."
      echo "Re-run with the exact token below (op-bound, single-use):"
      [ "$TOOL" = "Bash" ] && echo "  CLAUDE_CONTROLLER_ACK_ONCE=$SIG $COMMAND"
    } >&2
    exit 2
  fi
fi

# ── no valid ack → block ──────────────────────────────────────────────────────
printf '{"ts":"%s","tool":"%s","band":"ESCALATE","token":"none","sig":"%s","cwd":"%s","authorizer":"none"}\n' \
  "$TS" "$TOOL" "$SIG" "$CWD" >> "$LOG_FILE" 2>/dev/null || true

{
  echo ""
  echo "CONTROLLER-FIRST GATE — ESCALATE (substantial task, no Controller step ran yet in this session)"
  echo ""
  echo "  Tool: $TOOL"
  [ -n "$FILE_PATH" ] && echo "  File: $FILE_PATH"
  [ -n "$COMMAND" ] && echo "  Command: $COMMAND"
  echo ""
  echo "Per the Controller-First Enforcement proposal (IMP-090): a substantial task should"
  echo "start with a Controller step (control-agent dispatch, or an /issue-style command)"
  echo "before any mutation. Ask the user y/n to proceed without one, or route through the"
  echo "Controller. Do NOT route around this with a different tool/language."
  echo ""
  echo "After approval, re-run with the op-bound single-use token:"
  if [ "$TOOL" = "Bash" ]; then
    echo "  CLAUDE_CONTROLLER_ACK_ONCE=$SIG $COMMAND"
  else
    echo "  Sig: $SIG  (Write/Edit has no command line to prepend the token to — the reliable"
    echo "  unlock is a controller step actually running this session, not this token; see"
    echo "  this hook's header comment for the documented restlücke)."
  fi
} >&2

exit 2
