#!/bin/bash
# install-routine-timers.sh — idempotent installer for the 3 routine launchd timers
# ─────────────────────────────────────────────────────────────────────────────
# IMP-135 (2026-08-22; label/path genericized IMP-219, 2026-09-25). Renders
# scripts/launchd/routine-<task>.plist.template into ~/Library/LaunchAgents/
# and (re)loads them via launchctl bootstrap.
#
# Templates carry two placeholders, substituted at install time:
#   __HOME__  -> $HOME (this machine's real home directory)
#   __LABEL__ -> the generic label com.claude-code.routine-<task>
# No machine path or username is hardcoded in the templates themselves
# (rules/fail-loud.md — a config repo must not ship a real absolute path).
#
# Pre-IMP-219 installs used a per-user label (com.<user>.claude-routine-<task>)
# and shipped one plist per literal username. This installer migrates away
# from that: before (re)installing the new generic label, it unloads and
# removes any plist still registered under the historical per-user label,
# computed at RUNTIME from the current user — never as a literal string, so
# this script itself never contains anyone's username.
#
# This script is NOT run as part of building the timer package — it is meant
# to be run by hand, ONCE, AFTER `claude-deploy config` has copied
# scripts/routine-run.sh (and this installer, and the templates) from the
# workshop into ~/.claude. Running it before that deploy installs plists whose
# ProgramArguments point at a script that does not exist yet in ~/.claude.
#
# Usage:
#   bash ~/.claude/scripts/install-routine-timers.sh              # install/reload all 3
#   bash ~/.claude/scripts/install-routine-timers.sh --dry-run     # preview only, no writes, no launchctl
#   bash ~/.claude/scripts/install-routine-timers.sh --uninstall   # bootout + remove all 3 (new + historical label)
#
# Idempotent: safe to re-run. Each label is booted out first (ignoring "not
# loaded" errors) before being bootstrapped again, so re-running after an
# edit to a template picks up the change.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_NAME="install-routine-timers.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_SRC_DIR="$SCRIPT_DIR/launchd"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

TASKS=(daily-docs nightly-observation weekly-improve)
LABEL_PREFIX="com.claude-code.routine"
# Historical (pre-IMP-219) label prefix — built at runtime from the current
# user, NEVER as a literal, so this file never contains a real username.
OLD_LABEL_PREFIX="com.${USER:-$(id -un)}.claude-routine"

UNINSTALL=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *)
      echo "$SCRIPT_NAME: unknown argument '$arg'" >&2
      exit 2
      ;;
  esac
done

UID_NUM="$(id -u)"

# render_plist TASK -> renders the template for TASK to stdout with __HOME__
# and __LABEL__ substituted. No side effects (no launchctl, no file writes).
render_plist() {
  local task="$1" label="${LABEL_PREFIX}-${task}"
  local tmpl="$PLIST_SRC_DIR/routine-${task}.plist.template"
  [ -f "$tmpl" ] || { echo "$SCRIPT_NAME: ABORT — template not found: $tmpl" >&2; return 1; }
  sed -e "s|__HOME__|$HOME|g" -e "s|__LABEL__|$label|g" "$tmpl"
}

# ── --dry-run: show exactly what would happen, write nothing, never call
#    launchctl. Runs BEFORE the deploy precondition below on purpose — the
#    whole point of a preview is that it must work even pre-deploy. ─────────
if [ "$DRY_RUN" = "1" ]; then
  echo "$SCRIPT_NAME: --dry-run — no files written, launchctl NOT invoked"
  for task in "${TASKS[@]}"; do
    label="${LABEL_PREFIX}-${task}"
    old_label="${OLD_LABEL_PREFIX}-${task}"
    dest="$LAUNCH_AGENTS_DIR/${label}.plist"
    echo "  task:          $task"
    echo "  new label:     $label"
    echo "  historical:    $old_label (unloaded + removed if still present)"
    echo "  would write:   $dest"
    if render_plist "$task" >/dev/null; then
      echo "  template:      OK ($PLIST_SRC_DIR/routine-${task}.plist.template renders without error)"
    else
      echo "  template:      FAIL"
    fi
  done
  exit 0
fi

# ── Precondition (real install/uninstall only) — the runner this installer's
#    plists point at must already be deployed. Installing without it loads a
#    timer that fires into thin air on schedule, silently, exactly the
#    failure mode this package exists to end. ───────────────────────────────
if [ "$UNINSTALL" = "0" ]; then
  if [ ! -x "$HOME/.claude/scripts/routine-run.sh" ]; then
    echo "$SCRIPT_NAME: ABORT — $HOME/.claude/scripts/routine-run.sh does not exist or is not executable." >&2
    echo "$SCRIPT_NAME: run 'claude-deploy config' first, THEN install the timers." >&2
    exit 1
  fi
fi

if [ "$UNINSTALL" = "1" ]; then
  echo "$SCRIPT_NAME: uninstalling ${#TASKS[@]} routine timer(s) (new + historical label)..."
  for task in "${TASKS[@]}"; do
    label="${LABEL_PREFIX}-${task}"
    old_label="${OLD_LABEL_PREFIX}-${task}"
    launchctl bootout "gui/${UID_NUM}/${label}" 2>/dev/null
    launchctl bootout "gui/${UID_NUM}/${old_label}" 2>/dev/null
    for f in "$LAUNCH_AGENTS_DIR/${label}.plist" "$LAUNCH_AGENTS_DIR/${old_label}.plist"; do
      if [ -f "$f" ]; then
        rm -f "$f"
        echo "  removed: $f"
      else
        echo "  (already absent: $f)"
      fi
    done
  done
  echo "$SCRIPT_NAME: uninstall complete. Verifying none remain loaded:"
  launchctl list | grep -i 'claude.*routine' || echo "  (none loaded — clean)"
  exit 0
fi

echo "$SCRIPT_NAME: installing ${#TASKS[@]} routine timer(s)..."
mkdir -p "$LAUNCH_AGENTS_DIR"

for task in "${TASKS[@]}"; do
  label="${LABEL_PREFIX}-${task}"
  old_label="${OLD_LABEL_PREFIX}-${task}"
  plist_dest="$LAUNCH_AGENTS_DIR/${label}.plist"
  old_plist_dest="$LAUNCH_AGENTS_DIR/${old_label}.plist"

  # Migration: unload+remove a pre-IMP-219 install under the historical
  # per-user label before (re)installing under the new generic one — never
  # leaves both registered at once.
  launchctl bootout "gui/${UID_NUM}/${old_label}" 2>/dev/null
  if [ -f "$old_plist_dest" ]; then
    rm -f "$old_plist_dest"
    echo "  migrated away historical label: $old_label"
  fi

  render_plist "$task" > "$plist_dest" || { echo "$SCRIPT_NAME: ABORT — failed to render $task" >&2; exit 1; }
  echo "  rendered: $plist_dest"

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
echo "$SCRIPT_NAME: verifying via 'launchctl list | grep claude':"
launchctl list | grep -i claude || echo "  (none reported by launchctl list — check manually if this is unexpected)"
exit 0
