#!/bin/bash
# config-drift-check.sh — Drift guard for the ~/.claude config repo (IMP-084)
# ─────────────────────────────────────────────────────────────────────────────
# Warns when the config repo silently diverges from its remote — the failure
# class that let weeks of uncommitted/unpushed config changes accumulate
# (metareview 2026-07-03, finding K2).
#
# Checks (ONE line of output per problem, silent when clean):
#   (a) Tracked files with uncommitted changes whose mtime is older than
#       N days (default 3, env CLAUDE_DRIFT_MAX_DAYS) — stale local edits.
#   (b) Local commits on HEAD not present on origin/main
#       (git rev-list origin/main..HEAD) — unpushed work.
#   (c) origin/main ref missing locally (no remote / never fetched) — soft warn.
#
# Design constraints (Stop-hook friendly):
#   - MUST run < 500ms: git plumbing only, NO network fetch by default.
#     Comparison is against the LAST-FETCHED origin ref (refs/remotes/origin/main);
#     staleness of that ref is reported as context, not re-fetched.
#   - ALWAYS exits 0 — this is a warner, not a gate. A Stop hook must never
#     block the session over drift.
#   - Deleted-but-uncommitted tracked files cannot be mtime-aged; they are
#     excluded from check (a) but are still caught by (b) once committed.
#
# Env overrides (for testing / tuning):
#   CLAUDE_CONFIG_DIR        default: $HOME/.claude
#   CLAUDE_DRIFT_MAX_DAYS    default: 3
#   CLAUDE_DRIFT_FETCH=1     opt-in: attempt a real `git fetch` first (weekly
#                            cron use — NOT for the Stop chain). Fetch failure
#                            downgrades to the soft warn from (c).
#
# Registered by the orchestrator into the Stop chain — do not self-register.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MAX_DAYS="${CLAUDE_DRIFT_MAX_DAYS:-3}"
PREFIX="[config-drift]"

# ── Preconditions (soft — never block the Stop chain) ─────────────────────────
command -v git >/dev/null 2>&1 || { echo "$PREFIX git not found — drift check skipped" ; exit 0; }
[ -d "$CONFIG_DIR/.git" ] || { echo "$PREFIX $CONFIG_DIR is not a git repo — drift check skipped"; exit 0; }

g() { git -C "$CONFIG_DIR" "$@"; }

# Portable mtime (macOS stat -f %m vs GNU stat -c %Y)
if stat -f %m "$CONFIG_DIR" >/dev/null 2>&1; then
  mtime() { stat -f %m "$1" 2>/dev/null; }
else
  mtime() { stat -c %Y "$1" 2>/dev/null; }
fi

now=$(date +%s)
cutoff=$(( now - MAX_DAYS * 86400 ))

# ── Optional real fetch (weekly mode only — never in the Stop chain) ─────────
if [ "${CLAUDE_DRIFT_FETCH:-0}" = "1" ]; then
  g fetch --quiet origin main 2>/dev/null || true   # failure surfaces via check (c)
fi

# ── (a) Uncommitted tracked changes older than MAX_DAYS ──────────────────────
# Refresh the stat cache cheaply, then diff index+worktree against HEAD.
g update-index -q --refresh 2>/dev/null || true

stale_count=0
oldest_file=""
oldest_age=0
while IFS= read -r -d '' f; do
  [ -e "$CONFIG_DIR/$f" ] || continue          # deleted files: cannot mtime-age → skip
  m=$(mtime "$CONFIG_DIR/$f") || continue
  if [ "$m" -lt "$cutoff" ]; then
    stale_count=$(( stale_count + 1 ))
    age_days=$(( (now - m) / 86400 ))
    if [ "$age_days" -gt "$oldest_age" ]; then
      oldest_age=$age_days
      oldest_file="$f"
    fi
  fi
done < <(g diff-index --name-only -z HEAD -- 2>/dev/null)

if [ "$stale_count" -gt 0 ]; then
  echo "$PREFIX $stale_count tracked file(s) uncommitted for >${MAX_DAYS}d in $CONFIG_DIR (oldest: $oldest_file, ${oldest_age}d) — commit or discard"
fi

# ── (b)+(c) Local commits not on origin/main ─────────────────────────────────
if g rev-parse --verify --quiet refs/remotes/origin/main >/dev/null 2>&1; then
  ahead=$(g rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
  if [ "${ahead:-0}" -gt 0 ]; then
    # Context: how stale is the origin ref we compared against? (FETCH_HEAD mtime)
    fetch_note=""
    if [ -f "$CONFIG_DIR/.git/FETCH_HEAD" ]; then
      fm=$(mtime "$CONFIG_DIR/.git/FETCH_HEAD")
      [ -n "${fm:-}" ] && fetch_note=" (origin ref last fetched $(( (now - fm) / 86400 ))d ago)"
    fi
    echo "$PREFIX $ahead local commit(s) not on origin/main${fetch_note} — push when ready"
  fi
else
  # (c) soft warn: no remote configured, or never fetched, or fetch failed above
  echo "$PREFIX origin/main not found locally (remote missing, never fetched, or unreachable) — soft warn, backup coverage unknown"
fi

exit 0
