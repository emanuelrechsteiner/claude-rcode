#!/usr/bin/env bash
# Deploy from the workshop (SSD working copy) into the live install (~/.claude).
#
# Why this step exists: changes to rules/hooks/skills take effect in
# ~/.claude immediately — you're rewiring the electrics while the power is on.
# Development therefore happens in the workshop; this script is the deliberate handoff.
#
# Runtime preferences (since 2026-08-04):
#   Claude Code itself writes some values back to ~/.claude/settings.json at
#   runtime (e.g. when switching models). That made the live install "dirty" and blocked
#   every deploy until someone manually copied the values back into the workshop.
#   This script now pulls them back itself: values from the live install -> workshop,
#   its own commit there, after which the live install is a clean mirror again.
#   The detour via a ~/.claude/settings.local.json does NOT work — at the
#   user level Claude Code does not read that file (verified 2026-08-04).
#
# Test precondition (IMP-243): a config deploy first runs
# scripts/run-all-tests.sh --workshop and refuses on anything but green.
# Override (logged in deploy-skips.log and the deploy checklist): CLAUDE_DEPLOY_SKIP_TESTS=1
# together with CLAUDE_DEPLOY_SKIP_REASON="<why>" - the reason is mandatory.
#
# Live drift (P-IMP-263, report-only, never a block): untracked paths that external
# installers wrote into the live install under the governed directories are listed on
# every config deploy, unless they match an entry in the workshop's tracked
# live-only-manifest.txt (shell globs, one per line, '#' comments). Nested git repos are
# not drift: an untracked governed directory that holds its own .git (file or dir) is a
# separately deployed repo (cockpit, via `claude-deploy cockpit`). It is printed once in a
# sub-list, never counted, never escalated, never written to the state file, and needs no
# manifest entry (the manifest is also the security-findings vendor list, so it must not
# hide them). The governed set is
# the classifier's, hooks/lib/governing-path-classify.py (same set as
# hooks/governing-path-guard.sh). State file: <live>/global-observation/live-drift-state.tsv,
# one "<consecutive-count><TAB><path>" line per unlisted path, rewritten on every run; a path
# unlisted on the 3rd consecutive run gets the ESCALATION: prefix (IMP-164).
# Check without a deploy:  deploy-to-live.sh --drift-check <live-dir> <workshop-dir> [state-file]
#
# Usage:  deploy-to-live.sh [config|cockpit|all]   (default: all)
set -euo pipefail

fail() { printf '\033[31mABORT: %s\033[0m\n' "$1" >&2; exit 1; }
note() { printf '\033[36m▸ %s\033[0m\n' "$1"; }
warn() { printf '\033[33m! %s\033[0m\n' "$1"; }

# Durable backup of the live-install-only settings.json keys (HAUS_ONLY_KEYS_JSON,
# e.g. autoMode) for the reset->pull->restore window in deploy() (added 2026-09-25):
# previously the saved value lived ONLY in a shell variable — if
# restore_haus_only failed (e.g. under set -e in the middle of its own
# jq call), the script aborted AND the value was lost, with no path to it
# recorded anywhere. Now the value is additionally written to a
# 0600 file as soon as it's read (before the reset, see deploy());
# haus_only_exit_guard (EXIT trap, registered below) names, on EVERY
# abort while this file still exists, its path and how to restore it —
# even if the abort comes from an unrelated command (e.g. `git pull`), not
# only from restore_haus_only itself. After a successful restore, deploy()
# deletes the file and clears this variable again (invariant: the success
# path leaves NOTHING behind).
HAUS_ONLY_BACKUP_FILE=""

haus_only_exit_guard() {
  if [ -n "$HAUS_ONLY_BACKUP_FILE" ] && [ -f "$HAUS_ONLY_BACKUP_FILE" ]; then
    {
      printf '\033[31mLIVE-INSTALL-ONLY BACKUP NOT LOST: %s\033[0m\n' "$HAUS_ONLY_BACKUP_FILE"
      printf 'The most recently saved live-install-only value (e.g. autoMode) is intact in this file.\n'
      printf 'Restore it by hand (TARGET = the affected settings.json in the live install):\n'
      printf '  jq --argjson entries "$(cat %s)" '"'"'reduce $entries[] as $e (.; setpath($e.path; $e.value))'"'"' TARGET > /tmp/settings.restored.json && mv /tmp/settings.restored.json TARGET\n' "$HAUS_ONLY_BACKUP_FILE"
    } >&2
  fi
}
trap haus_only_exit_guard EXIT

command -v jq >/dev/null || fail "jq is required but not installed."

# Machine paths come from the environment, never from a hardcoded default
# (IMP-219, vault-by-design — a hardcoded path in a versioned script
# would itself be a machine path in the framework). Already-set variables
# take precedence (test suites set them directly); if both are missing,
# ~/.claude/env.local.sh is sourced (template: templates/env.local.sh.template).
if [ -z "${CLAUDE_WORKSHOP_ROOT:-}" ] && [ -z "${CLAUDE_BAUHOF_ROOT:-}" ] \
  && [ -f "${HOME}/.claude/env.local.sh" ]; then
  # shellcheck disable=SC1091
  . "${HOME}/.claude/env.local.sh"
fi
if [ -n "${CLAUDE_WORKSHOP_ROOT:-}" ]; then
  WORKSHOP_ROOT="${CLAUDE_WORKSHOP_ROOT}"
elif [ -n "${CLAUDE_BAUHOF_ROOT:-}" ]; then
  WORKSHOP_ROOT="$(dirname "${CLAUDE_BAUHOF_ROOT}")"
else
  fail "Workshop root unknown: neither CLAUDE_WORKSHOP_ROOT nor CLAUDE_BAUHOF_ROOT is set, and ${HOME}/.claude/env.local.sh does not exist. Create it from the template: templates/env.local.sh.template"
fi
LIVE_CONFIG="${CLAUDE_LIVE_CONFIG:-$HOME/.claude}"
LIVE_COCKPIT="${CLAUDE_LIVE_COCKPIT:-$LIVE_CONFIG/cockpit}"
TARGET="${1:-all}"

# Runtime keys that belong to the LIVE INSTALL: Claude Code itself writes them
# back to ~/.claude/settings.json at runtime. Each entry is a jq PATH (array of
# field names, getpath/setpath/delpaths-compatible) — ["model"] for a
# top-level key, ["permissions","defaultMode"] for a nested one.
# Deliberately kept short — every entry here switches off a protection check for
# EXACTLY that path; nested siblings (e.g. permissions.allow/deny/ask
# next to permissions.defaultMode) stay protected. If the live install diverges on a
# path NOT listed here, the deploy still aborts (fail-loud.md). Extend
# only with evidence that Claude Code writes the value itself. This list gets
# pulled back into the workshop REGULARLY (sync_runtime_prefs below) — unlike
# HAUS_ONLY_KEYS_JSON right after it, whose values NEVER move to the workshop.
#
#   ["model"]                      — the /model switcher (since 2026-08-04, IMP-127)
#   ["effortLevel"]                — the /config effort switcher (since 2026-08-04, IMP-127)
#   ["theme"]                      — the /config theme-picker switcher writes the
#                                     theme choice directly to settings.json (observed:
#                                     "light-daltonized" -> "dark-daltonized")
#   ["permissions","defaultMode"]  — the permission-mode switcher writes
#                                     permissions.defaultMode (observed:
#                                     "dontAsk" -> "auto"). ONLY this sub-key
#                                     is runtime churn — permissions.allow/deny/ask
#                                     stay protected and still trigger an ABORT
#                                     on divergence.
RUNTIME_KEYS_JSON='[["model"],["effortLevel"],["theme"],["permissions","defaultMode"],["modelSettings"],["switchModelsOnFlag"]]'

# Live-install-only keys: exist ONLY in the live install, NEVER move to the
# workshop (no pull-back, no workshop commit) and NEVER trigger an abort
# when the live install diverges from the workshop HEAD here. They survive reset+fast-forward in
# deploy() via extract_haus_only/restore_haus_only (backed up before `git
# checkout -- .`, restored after the fast-forward) instead of via a
# pull-back into the workshop.
#
#   ["autoMode"] — the Auto Mode setup creates an autoMode block with
#                  an environment array that describes EXACTLY what was
#                  the problem before IMP-219 (vault-by-design): private
#                  project/account/path data. A field that is by definition
#                  machine- and session-specific does not belong in a
#                  versioned, public repo — not even filtered
#                  through a publish transform. Generic template for the
#                  content: templates/automode-environment.template.json.
HAUS_ONLY_KEYS_JSON='[["autoMode"]]'

# Union of both lists — for the check "does the live install diverge OUTSIDE the
# protected paths?", BOTH categories are allowed to diverge without triggering
# an abort.
PROTECTED_KEYS_JSON=$(jq -c -n --argjson a "$RUNTIME_KEYS_JSON" --argjson b "$HAUS_ONLY_KEYS_JSON" '$a + $b')

# Pure runtime churn in the live install: constantly rewritten by Claude Code, no longer
# versioned since 2026-08-04. Preserved across the deploy.
VOLATILE_FILES=(plugins/installed_plugins.json plugins/known_marketplaces.json)

[ -d "$WORKSHOP_ROOT" ] || fail "Workshop not reachable: $WORKSHOP_ROOT (SSD mounted?)"

# Removes a list of jq paths (arrays) from a settings.json — used
# for the "does the live install diverge OUTSIDE the protected paths?" check.
strip_keys() { # strip_keys <keys-json> <file>
  jq -S --argjson k "$1" 'delpaths($k)' "$2"
}

# Reads the current live-install-only values (HAUS_ONLY_KEYS_JSON) from a
# settings.json — independent of git status, because the block can either
# sit unversioned in the working tree OR already be baked into the last
# live-install commit (older deploys used to pull it into the workshop).
# Output: compact JSON array [{"path":[...],"value":...}, ...], empty if no
# live-install-only key is set.
extract_haus_only() { # extract_haus_only <file>
  # Bind $root BEFORE iterating over $k: otherwise "." inside the getpath call
  # points at the path array currently being iterated instead of the document, and
  # getpath tries to index the path array with itself.
  jq -c --argjson k "$HAUS_ONLY_KEYS_JSON" \
    '. as $root | [$k[] | . as $path | ($root | getpath($path)) as $v | select($v != null) | {path: $path, value: $v}]' "$1"
}

# Restores values previously backed up with extract_haus_only into a
# settings.json — counterpart to extract_haus_only, called AFTER reset+fast-
# forward. Without this pair, `git checkout -- .` would delete an unversioned
# autoMode block with nothing to replace it, and the subsequent fast-forward to
# a workshop state without autoMode would also strip it from an
# already-committed live-install state (IMP-219: autoMode never moves into the
# workshop, see HAUS_ONLY_KEYS_JSON above).
restore_haus_only() { # restore_haus_only <file> <extract-haus-only-json>
  local file="$1" entries="$2"
  [ "$entries" = "[]" ] && return 0
  local tmp; tmp=$(mktemp)
  jq --argjson entries "$entries" \
    'reduce $entries[] as $e (.; setpath($e.path; $e.value))' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

# Pulls the runtime values changed in the live install back into the workshop.
# Aborts if the live install diverges OUTSIDE these keys.
sync_runtime_prefs() {
  local workshop="$1" live="$2"
  local ws_settings="$workshop/settings.json" live_settings="$live/settings.json"

  [ -f "$live_settings" ] || return 0
  git -C "$live" diff --quiet -- settings.json && return 0   # unchanged, nothing to do

  note "config — checking runtime preferences from the live install"

  local head_settings; head_settings=$(mktemp)
  git -C "$live" show HEAD:settings.json > "$head_settings" 2>/dev/null \
    || fail "config: settings.json is not tracked in the live install — please resolve by hand."

  if ! diff -q <(strip_keys "$PROTECTED_KEYS_JSON" "$head_settings") <(strip_keys "$PROTECTED_KEYS_JSON" "$live_settings") >/dev/null; then
    rm -f "$head_settings"
    git -C "$live" diff -- settings.json
    fail "config: the live install differs in settings.json OUTSIDE the runtime keys ($(jq -r '[.[] | join(".")] | join(", ")' <<<"$PROTECTED_KEYS_JSON")).
      This is a manual change made to the live install — it belongs in the workshop.
      Either rebuild it there and discard it here (git -C '$live' checkout -- settings.json),
      or — if Claude Code demonstrably writes the value itself — add the key to
      RUNTIME_KEYS_JSON (gets pulled into the workshop) or HAUS_ONLY_KEYS_JSON (stays in
      the live install) in this script."
  fi
  rm -f "$head_settings"

  # Adopt values: the live install wins for exactly these keys.
  # WITHOUT -S: the file's key order must be preserved, otherwise
  # the first deploy produces a full rewrite instead of two changed lines.
  # There's no direct "has" for paths — getpath()!=null stands in
  # for it (no runtime key here legitimately carries the value null).
  local merged; merged=$(mktemp)
  jq --argjson k "$RUNTIME_KEYS_JSON" --slurpfile live "$live_settings" \
     'reduce $k[] as $path (.; if (($live[0] | getpath($path)) != null) then setpath($path; $live[0] | getpath($path)) else . end)' \
     "$ws_settings" > "$merged" || { rm -f "$merged"; fail "config: merging settings.json failed."; }

  if diff -q <(jq -S . "$ws_settings") <(jq -S . "$merged") >/dev/null; then
    rm -f "$merged"
    note "config: runtime preferences in the workshop are already up to date"
    return 0
  fi

  local changed; changed=$(jq -rn --argjson k "$RUNTIME_KEYS_JSON" \
    --slurpfile live "$live_settings" --slurpfile ws "$ws_settings" \
    '[$k[] | . as $path
       | (($live[0] | getpath($path)) // null) as $lv
       | (($ws[0]   | getpath($path)) // null) as $wv
       | select($lv != $wv)
       | "\($path | join(".")): \($wv // "—") → \($lv // "—")"] | join(", ")')

  # Check first, then overwrite — a broken settings.json starts Claude Code
  # silently, without hooks and without permissions.
  jq -e 'has("hooks") and has("permissions")' "$merged" >/dev/null \
    || { rm -f "$merged"; fail "config: generated settings.json is incomplete (hooks/permissions missing) — nothing written."; }

  # No backup copy alongside: the file is unchanged-committed at this point,
  # so the workshop commit itself is the backup. Should the write abort,
  # `git -C <workshop> checkout -- settings.json` restores it.
  # (A copy in the working directory would make the following cleanliness check
  #  fail — that is exactly what the first version got wrong.)
  cat "$merged" > "$ws_settings"
  rm -f "$merged"

  note "config: runtime preferences pulled back into the workshop ($changed)"
  git -C "$workshop" add settings.json
  git -C "$workshop" commit -q -m "chore(config): pulled runtime preferences back from the live install ($changed)"
  note "config: workshop commit $(git -C "$workshop" rev-parse --short HEAD)"
}

# IMP-243: refuse to deploy the config workshop unless every regression suite
# is green, and unless what was tested is what will land (clean workshop, on
# main - deploy pulls `workshop main`). A skip is deliberate, never silent: it
# needs a non-blank reason, is printed, appended to
# $LIVE_CONFIG/global-observation/deploy-skips.log (durable even when the deploy
# turns out to be "already up to date") and shown in pending-verification.md.
# Runs BEFORE sync_runtime_prefs (which commits in the workshop). That pull-back
# only changes runtime keys of settings.json, so testing HEAD first is the
# safest order: nothing is written anywhere until the gate has passed.
TEST_SKIP_NOTE=""
require_green_suites() { # require_green_suites <config-workshop>
  local ws="$1" runner="$1/scripts/run-all-tests.sh" reason branch
  if [ "${CLAUDE_DEPLOY_SKIP_TESTS:-}" = "1" ]; then
    reason=$(printf '%s' "${CLAUDE_DEPLOY_SKIP_REASON:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -n "$reason" ] \
      || fail "CLAUDE_DEPLOY_SKIP_TESTS=1 requires a non-blank CLAUDE_DEPLOY_SKIP_REASON=\"<why>\" - a skipped test gate must state its reason."
    TEST_SKIP_NOTE="regression suites SKIPPED (CLAUDE_DEPLOY_SKIP_TESTS=1), reason: ${reason}"
    mkdir -p "$LIVE_CONFIG/global-observation" \
      && printf '%s skip-tests workshop_head=%s reason=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
           "$(git -C "$ws" rev-parse --short HEAD 2>/dev/null || echo unknown)" "$reason" \
           >> "$LIVE_CONFIG/global-observation/deploy-skips.log" \
      || fail "config: cannot record the test skip in $LIVE_CONFIG/global-observation/deploy-skips.log"
    warn "config - $TEST_SKIP_NOTE"
    return 0
  fi
  [ -d "$ws/.git" ] || fail "config: no repo in the workshop ($ws)"
  [ -z "$(git -C "$ws" status --porcelain)" ] \
    || { git -C "$ws" status --short; fail "config: workshop has uncommitted changes - the suites would test something other than what lands. Commit first, then deploy."; }
  branch=$(git -C "$ws" rev-parse --abbrev-ref HEAD)
  [ "$branch" = "main" ] \
    || fail "config: workshop is on '$branch', not main - the deploy pulls main, so the suites would test something else. Check out main first."
  [ -f "$runner" ] || fail "config: test runner not found: $runner - cannot verify the suites, refusing to deploy."
  note "config - running all regression suites (run-all-tests.sh --workshop)"
  # Operator env must not weaken the gate (skip rules, platform, real HOME).
  if ! env -u CLAUDE_TEST_SKIP_RULES -u CLAUDE_TEST_PLATFORM -u CLAUDE_TEST_REAL_HOME bash "$runner" --workshop; then
    fail "config: regression suites are not green (summary above) - refusing to deploy. Fix them, or override: CLAUDE_DEPLOY_SKIP_TESTS=1 CLAUDE_DEPLOY_SKIP_REASON=\"<why>\""
  fi
}

# Writes the pending-verification checklist for the next session (IMP-147). Only called
# for "config" — only there do hook/rule/skill changes land that need
# verification IN a new Claude Code session; cockpit
# changes are checked by the cockpit workshop itself (npm test/typecheck).
# Deliberately overwrites an existing file — the old checklist is obsolete
# with the new deploy (fail-loud: no appending, no stale leftovers).
write_pending_verification() {
  local live="$1" before="$2" after="$3"
  local out="$live/pending-verification.md"
  local subjects; subjects=$(git -C "$live" log --format='- [ ] %s' "$before..$after")
  {
    printf '# Pending verification — deploy %s\n\n' "$(date '+%Y-%m-%d %H:%M')"
    printf 'Commit range: %s..%s\n\n' "$before" "$after"
    printf '## Verification steps\n\n'
    printf '%s\n' "$subjects"
    printf '\nVerification steps per the session acceptance protocol.\n'
    [ -z "$TEST_SKIP_NOTE" ] || printf '\n**WARNING: %s**\n' "$TEST_SKIP_NOTE"
  } > "$out"
  note "config: checklist written → $out"
}

# ── Live drift (P-IMP-263) ─────────────────────────────────────────────────────
# External installers (e.g. `rea.mjs setup`) write UNTRACKED paths straight into the
# live install; the tracked-file checks in deploy() cannot see them. The governed set
# is NOT copied here: membership is decided by the classifier's governed(), invoked
# once per candidate path with a PreToolUse-shaped JSON on stdin.
LIVE_DRIFT_ESCALATE_AT=3
LIVE_DRIFT_HINT="adopt (copy into the workshop + THIRD-PARTY notice) or list in live-only-manifest.txt"

# Is <path> (live-relative, no trailing slash) covered by a manifest entry? Entries are
# shell globs; a trailing slash on an entry is optional; blank lines and '#' lines are ignored.
drift_listed() { # drift_listed <manifest> <path> -> 0 when listed
  local manifest="$1" path="$2" line pat
  [ -f "$manifest" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in ''|'#'*) continue ;; esac
    pat="${line%/}"
    case "$path" in $pat|$pat/*) return 0 ;; esac
  done < "$manifest"
  return 1
}

# Is <path> (live-relative, no trailing slash) a nested git repo, i.e. a directory holding
# its own .git (directory or file, as in worktrees and submodules)? -> 0 when it is.
drift_nested_repo() { # drift_nested_repo <live> <path>
  [ -d "$1/$2" ] && [ -e "$1/$2/.git" ]
}

# Classifier verdict for one live-relative path: 0 = governed, 1 = not governed,
# 2 = the classifier itself failed (a failure is never read as "not governed").
drift_governed() { # drift_governed <classifier> <live> <path>
  local verdict
  verdict=$(jq -cn --arg f "$2/$3" --arg c "$2" '{tool_input: {file_path: $f}, cwd: $c}' \
    | python3 "$1" "$2" 2>/dev/null) || return 2
  case "$verdict" in HIT*) return 0 ;; esac
  return 1
}

# Prints the drift report for <live> against <workshop>'s manifest and classifier.
# $3 (optional) = escalation state file; without it nothing is counted across runs.
# Always returns 0: drift is reported, never a failure. Tool failures print UNCHECKED.
live_drift_report() { # live_drift_report <live> <workshop> [state-file]
  local live="$1" workshop="$2" state="${3:-}"
  local classifier="$workshop/hooks/lib/governing-path-classify.py"
  local manifest="$workshop/live-only-manifest.txt"
  local listing entry path rc unlisted="" nested="" newstate="" out="" header skipped_out=""
  local p prev n count=0 escalated=0
  command -v python3 >/dev/null 2>&1 \
    || { warn "live drift: UNCHECKED - python3 not found (needed to read the governed set)"; return 0; }
  [ -f "$classifier" ] || { warn "live drift: UNCHECKED - classifier not found: $classifier"; return 0; }
  [ -f "$manifest" ] || warn "live drift: no live-only-manifest.txt in $workshop - nothing is exempt from the check"
  listing=$(git -C "$live" status --porcelain -z --untracked-files=normal | tr '\0' '\n') \
    || { warn "live drift: UNCHECKED - git status failed in $live"; return 0; }

  while IFS= read -r entry; do
    case "$entry" in '?? '*) ;; *) continue ;; esac
    path="${entry:3}"
    path="${path%/}"
    drift_listed "$manifest" "$path" && continue
    rc=0
    drift_governed "$classifier" "$live" "$path" || rc=$?
    case "$rc" in
      0) ;;
      1) continue ;;
      *) warn "live drift: UNCHECKED - classifier failed on '$path' (run it by hand: python3 $classifier $live)"; return 0 ;;
    esac
    if drift_nested_repo "$live" "$path"; then
      nested="${nested}${path}"$'\n'
    else
      unlisted="${unlisted}${path}"$'\n'
    fi
  done <<< "$listing"

  while IFS= read -r p; do
    [ -n "$p" ] || continue
    skipped_out="${skipped_out}  ${p} - nested git repo, skipped (separate deploy target)"$'\n'
  done <<< "$nested"

  while IFS= read -r p; do
    [ -n "$p" ] || continue
    prev=""
    if [ -n "$state" ] && [ -f "$state" ]; then
      prev=$(awk -F '\t' -v path="$p" '$2 == path { print $1; exit }' "$state") \
        || { warn "live drift: cannot read $state - counting '$p' from 0"; prev=""; }
    fi
    prev="${prev:-0}"
    case "$prev" in *[!0-9]*) warn "live drift: non-numeric count for '$p' in $state - restarting at 0"; prev=0 ;; esac
    n=$((prev + 1))
    newstate="${newstate}${n}"$'\t'"${p}"$'\n'
    count=$((count + 1))
    if [ "$n" -ge "$LIVE_DRIFT_ESCALATE_AT" ]; then
      escalated=1
      out="${out}  ESCALATION: ${p} - unlisted for ${n} consecutive deploys (IMP-164) - ${LIVE_DRIFT_HINT}"$'\n'
    else
      out="${out}  ${p} - ${LIVE_DRIFT_HINT}"$'\n'
    fi
  done <<< "$unlisted"

  if [ "$count" -eq 0 ]; then
    printf 'live drift: none\n'
  else
    header="live drift: ${count} untracked path(s) under governed dirs"
    if [ "$escalated" -eq 1 ]; then header="ESCALATION: ${header}"; fi
    printf '%s\n%s' "$header" "$out"
  fi
  # Sub-list: informational only, outside N, never escalated, never in the state file.
  if [ -n "$skipped_out" ]; then
    printf 'nested git repo(s) under governed dirs, skipped (not counted):\n%s' "$skipped_out"
  fi

  if [ -n "$state" ]; then
    if mkdir -p "$(dirname "$state")" && printf '%s' "$newstate" > "$state.tmp" && mv -f "$state.tmp" "$state"; then
      :
    else
      warn "live drift: escalation state NOT written to $state - counts are unreliable for this run"
    fi
  fi
  return 0
}

deploy() {
  local name="$1" workshop="$2" live="$3"
  [ -d "$workshop/.git" ] || fail "$name: no repo in the workshop ($workshop)"
  [ -d "$live/.git" ]     || fail "$name: no repo in the live install ($live)"

  # Must run BEFORE the workshop check — the pull-back creates a commit there.
  [ "$name" = "config" ] && sync_runtime_prefs "$workshop" "$live"

  note "$name — checking the workshop"
  if [ -n "$(git -C "$workshop" status --porcelain)" ]; then
    git -C "$workshop" status --short
    fail "$name: workshop has uncommitted changes. Commit first, then deploy."
  fi

  note "$name — checking the live install"
  local dirty tolerated=() remaining=()
  dirty=$(git -C "$live" diff --name-only HEAD --)
  if [ -n "$dirty" ]; then
    [ "$name" = "config" ] && tolerated=(settings.json "${VOLATILE_FILES[@]}")
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      local ok=0
      for t in ${tolerated[@]+"${tolerated[@]}"}; do [ "$f" = "$t" ] && ok=1; done
      [ "$ok" = 1 ] || remaining+=("$f")
    done <<< "$dirty"
  fi
  if [ ${#remaining[@]} -gt 0 ]; then
    printf '  %s\n' "${remaining[@]}"
    fail "$name: the live install has local changes to tracked files (above). These belong in the workshop — rebuild them there, discard them here."
  fi

  # P-IMP-263: untracked governed-dir paths that installers wrote into the live install.
  # Config only; report-only (live_drift_report never aborts the deploy).
  if [ "$name" = "config" ]; then
    live_drift_report "$live" "$workshop" "$live/global-observation/live-drift-state.tsv"
  fi

  # Preserve runtime churn across the deploy: the fast-forward removes the
  # files from version control; Claude Code should find them unchanged afterward.
  local stash; stash=$(mktemp -d)
  local haus_only_backup="[]"
  if [ "$name" = "config" ]; then
    for f in "${VOLATILE_FILES[@]}"; do
      [ -f "$live/$f" ] && { mkdir -p "$stash/$(dirname "$f")"; cp "$live/$f" "$stash/$f"; }
    done
    # Back up live-install-only keys (autoMode) BEFORE the reset — the
    # workshop state never carries them (HAUS_ONLY_KEYS_JSON above), a plain
    # fast-forward would otherwise strip them with nothing to replace them.
    # Also written to a 0600 file (haus_only_exit_guard above) — the shell
    # variable alone does not survive a set -e abort between here and the
    # successful restore_haus_only further below.
    if [ -f "$live/settings.json" ]; then
      haus_only_backup=$(extract_haus_only "$live/settings.json")
      if [ "$haus_only_backup" != "[]" ]; then
        HAUS_ONLY_BACKUP_FILE=$(mktemp "${TMPDIR:-/tmp}/deploy-haus-only-backup.XXXXXX")
        chmod 0600 "$HAUS_ONLY_BACKUP_FILE"
        printf '%s' "$haus_only_backup" > "$HAUS_ONLY_BACKUP_FILE"
      fi
    fi
  fi

  # Reset the live install to the commit state — only that makes a fast-forward possible.
  if [ -n "$dirty" ]; then
    note "$name — resetting the live install to the commit state"
    git -C "$live" checkout -- . 2>/dev/null || true
  fi

  local before after
  before=$(git -C "$live" rev-parse --short HEAD)
  note "$name — pulling in from the workshop"
  git -C "$live" pull --ff-only workshop main
  after=$(git -C "$live" rev-parse --short HEAD)

  if [ "$name" = "config" ]; then
    for f in "${VOLATILE_FILES[@]}"; do
      if [ -f "$stash/$f" ]; then
        mkdir -p "$live/$(dirname "$f")"
        cp "$stash/$f" "$live/$f"
      fi
    done
    [ -f "$live/settings.json" ] && restore_haus_only "$live/settings.json" "$haus_only_backup"
    # This line is only reached once restore_haus_only (if called) has
    # already succeeded under set -e — the backup file is
    # superfluous from here on.
    if [ -n "$HAUS_ONLY_BACKUP_FILE" ]; then
      rm -f "$HAUS_ONLY_BACKUP_FILE"
      HAUS_ONLY_BACKUP_FILE=""
    fi
  fi
  rm -rf "$stash"

  if [ "$before" = "$after" ]; then
    note "$name: already up to date ($after)"
  else
    note "$name: $before → $after"
    git -C "$live" log --oneline "$before..$after"
    # if/fi, NOT `[ … ] && …`: as the function's last line, the
    # wrong test returned exit 1 for the cockpit, and set -e aborted before
    # `npm install` ran (found 2026-09-24, regression "cockpit-neu" in deploy-regression.sh).
    if [ "$name" = "config" ]; then
      write_pending_verification "$live" "$before" "$after"
    fi
  fi
}

# Drift check without a deploy (P-IMP-263): report only, always exit 0 on a report.
# Without a state file nothing is counted across runs (no ESCALATION).
if [ "$TARGET" = "--drift-check" ]; then
  [ "$#" -ge 3 ] && [ "$#" -le 4 ] \
    || fail "usage: deploy-to-live.sh --drift-check <live-dir> <workshop-dir> [state-file]"
  [ -d "$2/.git" ] || fail "--drift-check: live install is not a git repo: $2"
  live_drift_report "$2" "$3" "${4:-}"
  exit 0
fi

# Test gate before anything is touched (sync_runtime_prefs commits, deploy() checks).
case "$TARGET" in
  config|all) require_green_suites "$WORKSHOP_ROOT/claude-code-config" ;;
esac

case "$TARGET" in
  config)  deploy "config"  "$WORKSHOP_ROOT/claude-code-config" "$LIVE_CONFIG" ;;
  cockpit) deploy "cockpit" "$WORKSHOP_ROOT/cockpit"            "$LIVE_COCKPIT" ;;
  all)     deploy "config"  "$WORKSHOP_ROOT/claude-code-config" "$LIVE_CONFIG"
           deploy "cockpit" "$WORKSHOP_ROOT/cockpit"            "$LIVE_COCKPIT" ;;
  *)       fail "unknown target: $TARGET (allowed: config, cockpit, all)" ;;
esac

if [ "$TARGET" = "cockpit" ] || [ "$TARGET" = "all" ]; then
  note "cockpit — syncing dependencies"
  ( cd "$LIVE_COCKPIT" && npm install --no-fund --no-audit --silent )
fi

printf '\033[32m✔ Deploy complete.\033[0m Hook/rule changes take effect starting with the NEXT Claude session.\n'
