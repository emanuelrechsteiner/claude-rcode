#!/bin/bash
# restore-drill.sh — Backup-SUFFICIENCY drill for the ~/.claude config repo (IMP-084)
# ─────────────────────────────────────────────────────────────────────────────
# A backup is only as good as its restore. This script proves the origin repo
# alone can rebuild a working harness on a fresh machine — checking backup
# SUFFICIENCY, not just backup freshness (metareview 2026-07-03).
#
# What it does (read-only drill — never touches the live ~/.claude):
#   1. CLONE    — shallow-clone origin into a mktemp dir
#   2. REQUIRED — verify required files/dirs exist in the clone
#                 (settings.json, key hooks incl. excessive-agency-gate.sh +
#                  mcp-agency-gate.sh, rules/, skills/meta-observer, install.sh)
#   3. HOOKS    — every ~/.claude/hooks/*.sh command registered in the CLONED
#                 settings.json must exist in the clone (no ghost registrations)
#   4. SYNTAX   — bash -n every cloned hooks/*.sh (no committed parse errors)
#   5. MANUAL   — print the MANUAL-STEPS checklist: what a fresh machine still
#                 needs that git can NEVER restore (secrets, MCP auth, launchd)
#
# Exit codes:
#   0 — restorable (all hard checks pass; manual steps still apply)
#   1 — HARD GAP found: the origin backup is NOT sufficient to restore
#   2 — script-level error (missing deps, clone failed)
#
# Env overrides:
#   CLAUDE_RESTORE_REPO_URL  default: origin URL of $HOME/.claude (fallback:
#                            https://github.com/emanuelrechsteiner/claude-rcode.git)
#   CLAUDE_RESTORE_KEEP=1    keep the temp clone for inspection (prints path)
#
# Usage: bash ~/.claude/scripts/restore-drill.sh
# Run cadence: once now (first real drill PENDING as of 2026-07-03), then
# quarterly per docs/RETENTION-POLICY.md checklist. Requires network access.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

PREFIX="[restore-drill]"
HARD_FAILS=0

log()  { echo "$PREFIX $*"; }
pass() { echo "$PREFIX PASS: $*"; }
fail() { echo "$PREFIX FAIL: $*"; HARD_FAILS=$(( HARD_FAILS + 1 )); }

# ── Dependencies ──────────────────────────────────────────────────────────────
for cmd in git jq bash mktemp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "FATAL: required command not found: $cmd"
    exit 2
  fi
done

# ── Resolve repo URL (prefer the live repo's own origin) ─────────────────────
DEFAULT_URL="https://github.com/emanuelrechsteiner/claude-rcode.git"
LIVE_ORIGIN=$(git -C "$HOME/.claude" remote get-url origin 2>/dev/null || true)
REPO_URL="${CLAUDE_RESTORE_REPO_URL:-${LIVE_ORIGIN:-$DEFAULT_URL}}"

# ── STEP 1: CLONE into a throwaway dir ────────────────────────────────────────
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claude-restore-drill.XXXXXX") || exit 2
CLONE="$TMP_DIR/clone"

cleanup() {
  if [ "${CLAUDE_RESTORE_KEEP:-0}" = "1" ]; then
    log "keeping clone for inspection: $CLONE"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

log "STEP 1: cloning $REPO_URL (shallow, read-only drill)..."
if ! git clone --quiet --depth 1 "$REPO_URL" "$CLONE" 2>/dev/null; then
  log "FATAL: clone failed — origin unreachable or auth required. Drill aborted."
  log "A restore on a fresh machine would fail at the same point."
  exit 2
fi
pass "clone succeeded ($(git -C "$CLONE" rev-parse --short HEAD 2>/dev/null || echo '?'))"

# ── STEP 2: REQUIRED files/dirs present in the clone ─────────────────────────
log "STEP 2: checking required restore surface..."

REQUIRED_FILES=(
  "settings.json"
  "install.sh"
  "hooks/excessive-agency-gate.sh"
  "hooks/mcp-agency-gate.sh"
  "hooks/guard-unsafe.sh"
  "hooks/security-audit.sh"
  "hooks/session-start-context.sh"
  "hooks/stop-batched-checks.sh"
  "skills/meta-observer/SKILL.md"
)
for f in "${REQUIRED_FILES[@]}"; do
  if [ -f "$CLONE/$f" ]; then
    pass "required file present: $f"
  else
    fail "required file MISSING from origin: $f"
  fi
done

if [ -d "$CLONE/rules" ] && [ -n "$(ls -A "$CLONE/rules" 2>/dev/null)" ]; then
  pass "rules/ present and non-empty ($(ls "$CLONE/rules" | wc -l | tr -d ' ') entries)"
else
  fail "rules/ missing or empty in origin"
fi

# ── STEP 3: every registered hook exists in the clone ────────────────────────
log "STEP 3: cross-checking hooks registered in the CLONED settings.json..."

if [ -f "$CLONE/settings.json" ] && jq empty "$CLONE/settings.json" 2>/dev/null; then
  ghost=0
  checked=0
  # Extract every registered command; keep only ones that point at ~/.claude/hooks/
  while IFS= read -r hook_path; do
    [ -z "$hook_path" ] && continue
    checked=$(( checked + 1 ))
    base="hooks/$(basename "$hook_path")"
    if [ -f "$CLONE/$base" ]; then
      : # present
    else
      fail "registered hook NOT in clone (ghost registration): $hook_path"
      ghost=$(( ghost + 1 ))
    fi
  done < <(jq -r '.hooks // {} | to_entries[] | .value[]? | .hooks[]? | .command // empty' \
             "$CLONE/settings.json" 2>/dev/null \
           | grep -oE '(~|\$HOME|/Users/[^/ ]+)/\.claude/hooks/[A-Za-z0-9._-]+\.sh' \
           | sort -u)
  if [ "$ghost" -eq 0 ]; then
    pass "all $checked registered hook script(s) exist in the clone"
  fi
else
  fail "cloned settings.json missing or not valid JSON — registration check impossible"
fi

# ── STEP 4: bash -n every cloned hook ─────────────────────────────────────────
log "STEP 4: syntax-checking all cloned hooks (bash -n)..."
syntax_bad=0
syntax_ok=0
for h in "$CLONE"/hooks/*.sh; do
  [ -e "$h" ] || continue
  if bash -n "$h" 2>/dev/null; then
    syntax_ok=$(( syntax_ok + 1 ))
  else
    fail "syntax error in cloned hook: hooks/$(basename "$h")"
    syntax_bad=$(( syntax_bad + 1 ))
  fi
done
if [ "$syntax_bad" -eq 0 ]; then
  pass "bash -n clean on $syntax_ok cloned hook(s)"
fi

# ── STEP 5: MANUAL-STEPS checklist (git can never restore these) ─────────────
cat <<'EOF'

[restore-drill] ── MANUAL STEPS on a fresh machine (NOT restorable from git) ──
  [ ] settings.local.json — recreate by hand (gitignored). Contains the env
      block with secret tokens (e.g. KOKO_PRO_TOKEN) per kokonutui-pro.md.
  [ ] ~/.koko_pro_token + ~/.zshrc export — re-create the token file
      (chmod 600) and the shell export.
  [ ] rules/identity.local.md — re-create from templates/identity.local.md.template
      (gitignored; personal git-identity mappings).
  [ ] MCP re-auth — every OAuth-backed server needs a fresh login:
      claude.ai connectors via connector settings; local servers via
      `claude mcp` / `/mcp` in an interactive session.
  [ ] launchd jobs — copy launchd/*.plist (e.g. com.user.claude-audit.plist)
      to ~/Library/LaunchAgents/ and `launchctl load` them; verify with
      `launchctl list | grep claude`.
  [ ] Plugins — plugins/marketplaces/ is gitignored (external repos);
      reinstall plugins from their marketplaces on first run.
  [ ] Local-only data — projects/ transcripts, global-observation/ logs +
      chat-archives, logbook/, history.jsonl are gitignored by design (see
      docs/RETENTION-POLICY.md). Restore from machine backup (Time Machine)
      if needed; they are NOT part of the git restore surface.
  [ ] Git identity — set git config user.name/user.email; SessionStart
      identity hook only warns, it does not configure.
  [ ] Anthropic Routines — re-activate scheduled routines via /schedule
      (they live on Anthropic infra, keyed to the account, not this repo).
──────────────────────────────────────────────────────────────────────────────
EOF

# ── Verdict ───────────────────────────────────────────────────────────────────
if [ "$HARD_FAILS" -gt 0 ]; then
  log "VERDICT: NOT SUFFICIENT — $HARD_FAILS hard gap(s). Origin alone cannot restore the harness."
  exit 1
fi
log "VERDICT: restorable from origin (plus the manual steps above)."
exit 0
