#!/bin/bash
# install-routine-timers.sh — idempotent installer for the 3 routine launchd timers
# ─────────────────────────────────────────────────────────────────────────────
# IMP-135 (2026-08-22). Installs scripts/launchd/com.your-username.claude-routine-*.plist
# into ~/Library/LaunchAgents/ and (re)loads them via launchctl bootstrap.
#
# This script is NOT run as part of building the timer package — it is meant
# to be run by hand, ONCE, AFTER `claude-deploy config` has copied
# scripts/routine-run.sh (and this installer, and the plists) from the
# Bauhof into ~/.claude. Running it before that deploy installs plists whose
# ProgramArguments point at a script that does not exist yet in ~/.claude.
#
# Usage:
#   bash ~/.claude/scripts/install-routine-timers.sh              # install/reload all 3
#   bash ~/.claude/scripts/install-routine-timers.sh --uninstall  # bootout + remove all 3
#
# Idempotent: safe to re-run. Each label is booted out first (ignoring "not
# loaded" errors) before being bootstrapped again, so re-running after an
# edit to a plist picks up the change.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_NAME="install-routine-timers.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_SRC_DIR="$SCRIPT_DIR/launchd"
RUNNER="$SCRIPT_DIR/routine-run.sh"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

LABELS=(
  "com.your-username.claude-routine-daily-docs"
  "com.your-username.claude-routine-nightly-observation"
  "com.your-username.claude-routine-weekly-improve"
)

UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    *)
      echo "$SCRIPT_NAME: unknown argument '$arg'" >&2
      exit 2
      ;;
  esac
done

# ── Precondition — the runner this installer's plists point at must already
#    be deployed. Installing without it loads a timer that fires into thin
#    air on schedule, silently, exactly the failure mode this package exists
#    to end. ────────────────────────────────────────────────────────────────
if [ "$UNINSTALL" = "0" ]; then
  if [ ! -x "$HOME/.claude/scripts/routine-run.sh" ]; then
    echo "$SCRIPT_NAME: ABORT — $HOME/.claude/scripts/routine-run.sh does not exist or is not executable." >&2
    echo "$SCRIPT_NAME: run 'claude-deploy config' first, THEN install the timers." >&2
    exit 1
  fi
fi

UID_NUM="$(id -u)"

if [ "$UNINSTALL" = "1" ]; then
  echo "$SCRIPT_NAME: uninstalling ${#LABELS[@]} routine timer(s)..."
  for label in "${LABELS[@]}"; do
    plist_dest="$LAUNCH_AGENTS_DIR/${label}.plist"
    launchctl bootout "gui/${UID_NUM}/${label}" 2>/dev/null
    if [ -f "$plist_dest" ]; then
      rm -f "$plist_dest"
      echo "  removed: $plist_dest"
    else
      echo "  (already absent: $plist_dest)"
    fi
  done
  echo "$SCRIPT_NAME: uninstall complete. Verifying none remain loaded:"
  launchctl list | grep claude-routine || echo "  (none loaded — clean)"
  exit 0
fi

echo "$SCRIPT_NAME: installing ${#LABELS[@]} routine timer(s)..."
mkdir -p "$LAUNCH_AGENTS_DIR"

for label in "${LABELS[@]}"; do
  plist_src="$PLIST_SRC_DIR/${label}.plist"
  plist_dest="$LAUNCH_AGENTS_DIR/${label}.plist"

  if [ ! -f "$plist_src" ]; then
    echo "$SCRIPT_NAME: ABORT — expected plist not found: $plist_src" >&2
    exit 1
  fi

  cp "$plist_src" "$plist_dest"
  echo "  copied: $plist_src -> $plist_dest"

  # Ignore "not loaded" errors — first install has nothing to boot out.
  launchctl bootout "gui/${UID_NUM}/${label}" 2>/dev/null

  if launchctl bootstrap "gui/${UID_NUM}" "$plist_dest"; then
    echo "  bootstrapped: $label"
  else
    echo "$SCRIPT_NAME: ABORT — launchctl bootstrap failed for $label" >&2
    exit 1
  fi
done

echo ""
echo "$SCRIPT_NAME: verifying via 'launchctl list | grep claude-routine':"
launchctl list | grep claude-routine
