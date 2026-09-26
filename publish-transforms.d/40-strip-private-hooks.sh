#!/usr/bin/env bash
# 40-strip-private-hooks.sh — remove hook registrations (and the
# statusLine key) whose target can never exist on a fresh public install,
# then prove the remaining hook surface is actually shippable.
#
# Neutralizes TWO independent private-target problems in settings.json:
#
# 1. The 8 Cockpit hook registrations (SessionStart x2, PreToolUse
#    Task|Agent, PostToolUse Edit|Write, PostToolUse TaskCreate,
#    PostToolUse TaskUpdate, Stop, SubagentStop) plus the Cockpit
#    statusLine key. All point at "$HOME/.claude/cockpit/..." — Cockpit is
#    a private, unversioned repo (see CLAUDE.md "Zwei Orte") and is
#    structurally absent from every public install.
#
# 2. The 2 graphify hook-guard entries (PreToolUse Bash|Grep, PreToolUse
#    Read|Glob). Earlier versions of this transform deliberately left
#    these alone on the theory that graphify is "a real, documented,
#    installable public tool" — true, but irrelevant: the private
#    settings.json bakes in a hardcoded, per-machine absolute path
#    ("/Users/<name>/.local/bin/graphify"), which does not exist on any
#    other machine, public or private. graphify itself is optional and
#    hand-installed (CLAUDE.md's "Graphify" section) — nothing in the
#    manifest ships a `graphify` binary or install step, so the entry
#    can never resolve on a fresh public checkout either. Removed by
#    matching the tool-invocation shape ("graphify hook-guard"), not the
#    machine-specific path, so this survives a different installer's
#    username without edits.
#
# Documented behavior for both (code.claude.com/docs/en/hooks, "Exit code
# 2" / non-blocking section, checked 2026-09-23): a hook whose script path
# doesn't exist exits 127 and is treated as a NON-BLOCKING failure for
# hook events — nothing is actually prevented, but the transcript shows a
# "<hook name> hook error" notice on every firing (SessionStart, every
# Task/Agent dispatch, every Bash/Grep/Read/Glob call for graphify, every
# Edit/Write, every Stop, every SubagentStop). The statusLine key is a
# separate feature (not covered by that same documented non-blocking
# hooks table) but points at the same non-shippable target and fails the
# same way on every render.
#
# statusLine handling: before the 2026-08-03 switch to the Cockpit
# statusline (commit c4f5a2c, "feat(statusline): switch to cockpit
# statusline"), settings.json pointed statusLine at
# "~/.claude/statusline-command.sh" — a plain, tracked, non-excluded file
# that ships in every public checkout (git ls-files confirms it, and it
# is absent from publish-manifest.txt). So when the Cockpit statusLine is
# found: if that prior script exists in staging, redirect statusLine back
# to it (restores a real, working, pre-Cockpit feature instead of just
# deleting one); if it doesn't exist in staging for any reason, delete
# the statusLine key instead of shipping a dangling reference — never
# guess a path that isn't actually there.
#
# subagentStatusLine (2026-09-26): the Cockpit also registers
# "~/.claude/cockpit/statusline/subagent-statusline.sh" as subagentStatusLine
# (it feeds the Cockpit's subagent card). There is no pre-Cockpit equivalent
# to redirect to, so the key is deleted. Without this it would ship pointing
# at a missing script and fail on every agent-panel refresh of every public
# install — and the generic reference walk below did not look at this key.
#
# outputStyle (2026-09-26): the "Hausbau" output style is the repo owner's
# personal runtime preference (same category as `model`/`effortLevel` in
# CLAUDE.md's "Zwei Orte" section) — it is NOT a framework default. A fresh
# public install must answer in plain developer language unless someone
# opts in explicitly (`/output-style Hausbau`). The style file itself
# (output-styles/hausbau.md) still ships — only the private settings.json's
# unconditional selection of it is removed. `del(.outputStyle)` is a no-op
# (idempotent) when the key is already absent.
#
# Replaces the old "expected exactly 8 cockpit hooks" fail-loud check,
# which aborted the whole transform the moment the count drifted even by
# one (e.g. after adding/removing an unrelated cockpit hook, or after
# graphify's own hook count changed). The stricter, more general
# replacement: after removing every cockpit/graphify entry by pattern,
# walk EVERY remaining hook .command (and statusLine.command) in the
# result, extract any script path under ~/.claude/ or $HOME/.claude/ it
# invokes, and require that path to actually exist in staging. This
# catches the same class of defect (a hook pointing at a target absent
# from the public tree) for ANY hook, not just the 8 named ones, and
# doesn't need to be re-tuned every time the private hook count changes.
#
# Idempotent: matches on the literal command substrings, not on position
# or count — re-running on an already-stripped settings.json finds
# nothing left to remove and the existence check still passes (nothing
# new was introduced), so it exits 0 as a no-op.
#
# Usage: 40-strip-private-hooks.sh <staging-dir>
set -euo pipefail

STAGING="${1:?usage: $0 <staging-dir>}"
SETTINGS="$STAGING/settings.json"

if [[ ! -f "$SETTINGS" ]]; then
  echo "40-strip-private-hooks: FAIL — $SETTINGS not present in staging" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "40-strip-private-hooks: FAIL — jq is required" >&2
  exit 1
fi

if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "40-strip-private-hooks: FAIL — $SETTINGS is not valid JSON before transform" >&2
  exit 1
fi

COCKPIT_HOOK_RE='cockpit-event\.sh'
GRAPHIFY_HOOK_RE='graphify hook-guard'
COCKPIT_STATUSLINE_RE='cockpit/statusline'
PRIOR_STATUSLINE_PATH='~/.claude/statusline-command.sh'
PRIOR_STATUSLINE_FILE="$STAGING/statusline-command.sh"

BEFORE_COCKPIT_COUNT="$(jq --arg re "$COCKPIT_HOOK_RE" \
  '[.hooks[][].hooks[]? | select(.command | test($re))] | length' "$SETTINGS")"
BEFORE_GRAPHIFY_COUNT="$(jq --arg re "$GRAPHIFY_HOOK_RE" \
  '[.hooks[][].hooks[]? | select(.command | test($re))] | length' "$SETTINGS")"
STATUSLINE_HAS_COCKPIT="$(jq --arg re "$COCKPIT_STATUSLINE_RE" \
  '(.statusLine.command? // "") | test($re)' "$SETTINGS")"
SUBAGENT_STATUSLINE_HAS_COCKPIT="$(jq --arg re "$COCKPIT_STATUSLINE_RE" \
  '(.subagentStatusLine.command? // "") | test($re)' "$SETTINGS")"
HAD_OUTPUT_STYLE="$(jq 'has("outputStyle")' "$SETTINGS")"

# Decide the statusLine action up front — this needs a filesystem check
# (does the pre-Cockpit script exist in staging?), which jq cannot do.
if [[ "$STATUSLINE_HAS_COCKPIT" == "true" && -f "$PRIOR_STATUSLINE_FILE" ]]; then
  STATUSLINE_ACTION="redirect"
elif [[ "$STATUSLINE_HAS_COCKPIT" == "true" ]]; then
  STATUSLINE_ACTION="delete"
else
  STATUSLINE_ACTION="none"
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

jq \
  --arg cockpit_re "$COCKPIT_HOOK_RE" \
  --arg graphify_re "$GRAPHIFY_HOOK_RE" \
  --arg action "$STATUSLINE_ACTION" \
  --arg prior_statusline "$PRIOR_STATUSLINE_PATH" \
  --arg del_subagent "$SUBAGENT_STATUSLINE_HAS_COCKPIT" \
  '
  .hooks |= with_entries(
    .value |= (
      map(.hooks |= map(select(
        (.command | test($cockpit_re)) or (.command | test($graphify_re))
        | not
      )))
      | map(select((.hooks | length) > 0))
    )
  )
  | .hooks |= with_entries(select((.value | length) > 0))
  | if $action == "redirect" then .statusLine.command = $prior_statusline
    elif $action == "delete" then del(.statusLine)
    else .
    end
  | if $del_subagent == "true" then del(.subagentStatusLine) else . end
  | del(.outputStyle)
' "$SETTINGS" > "$TMP"

if ! jq -e . "$TMP" >/dev/null 2>&1; then
  echo "40-strip-private-hooks: FAIL — transform produced invalid JSON, aborting (settings.json left untouched)" >&2
  exit 1
fi

AFTER_COCKPIT_COUNT="$(jq --arg re "$COCKPIT_HOOK_RE" \
  '[.hooks[][].hooks[]? | select(.command | test($re))] | length' "$TMP")"
AFTER_GRAPHIFY_COUNT="$(jq --arg re "$GRAPHIFY_HOOK_RE" \
  '[.hooks[][].hooks[]? | select(.command | test($re))] | length' "$TMP")"
STILL_HAS_COCKPIT_STATUSLINE="$(jq --arg re "$COCKPIT_STATUSLINE_RE" \
  '(.statusLine.command? // "") | test($re)' "$TMP")"
STILL_HAS_COCKPIT_SUBAGENT_STATUSLINE="$(jq --arg re "$COCKPIT_STATUSLINE_RE" \
  '(.subagentStatusLine.command? // "") | test($re)' "$TMP")"
STILL_HAS_OUTPUT_STYLE="$(jq 'has("outputStyle")' "$TMP")"

if [[ "$AFTER_COCKPIT_COUNT" -ne 0 ]]; then
  echo "40-strip-private-hooks: FAIL — $AFTER_COCKPIT_COUNT cockpit-event.sh hook(s) still present after transform (expected 0)" >&2
  exit 1
fi

if [[ "$AFTER_GRAPHIFY_COUNT" -ne 0 ]]; then
  echo "40-strip-private-hooks: FAIL — $AFTER_GRAPHIFY_COUNT graphify hook-guard entry/entries still present after transform (expected 0)" >&2
  exit 1
fi

if [[ "$STILL_HAS_COCKPIT_STATUSLINE" == "true" ]]; then
  echo "40-strip-private-hooks: FAIL — cockpit statusLine still present after transform" >&2
  exit 1
fi

if [[ "$STILL_HAS_COCKPIT_SUBAGENT_STATUSLINE" == "true" ]]; then
  echo "40-strip-private-hooks: FAIL — cockpit subagentStatusLine still present after transform" >&2
  exit 1
fi

if [[ "$STILL_HAS_OUTPUT_STYLE" == "true" ]]; then
  echo "40-strip-private-hooks: FAIL — outputStyle still present after transform" >&2
  exit 1
fi

# --- Generic replacement for the old "expected exactly 8" count check ------
#
# Walk every remaining hook .command plus statusLine.command in the
# transformed result. For each one, extract any script path it invokes
# under ~/.claude/ or $HOME/.claude/ (the only two forms this settings.json
# actually uses) and require that path to exist in staging. A command with
# no such path (echo one-liners, inline `if`-blocks, absolute paths
# outside ~/.claude such as a hand-installed tool) is not this transform's
# concern and is skipped.
PATH_RE='(~|\$HOME|\$\{HOME\})/\.claude/[A-Za-z0-9_./-]+\.sh'

# Deliberately NOT using bash arrays / mapfile here: this pipeline runs
# under stock macOS bash 3.2 (no `mapfile`; and under `set -u`, bash 3.2
# has the well-known bug where `"${arr[@]}"` on a zero-element array
# throws "unbound variable" instead of expanding to nothing — the exact
# failure this transform hit in testing). Plain files + a while-read loop
# sidestep both problems and match the bash-3.2-compatible convention
# already used elsewhere in this pipeline (see verify-public-mirror.sh's
# header comment).
REFS_FILE="$(mktemp)"
MISSING_FILE="$(mktemp)"
trap 'rm -f "$TMP" "$REFS_FILE" "$MISSING_FILE"' EXIT

jq -r '
  [ (.hooks[][].hooks[]?.command // empty), (.statusLine.command? // empty),
    (.subagentStatusLine.command? // empty) ]
  | .[]
' "$TMP" \
  | grep -oE "$PATH_RE" \
  | sort -u > "$REFS_FILE" || true

REF_COUNT=0
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  REF_COUNT=$((REF_COUNT + 1))
  rel="$(printf '%s' "$ref" | sed -E 's#^(~|\$HOME|\$\{HOME\})/\.claude/##')"
  target="$STAGING/$rel"
  if [[ ! -f "$target" ]]; then
    printf '%s -> %s\n' "$ref" "$target" >> "$MISSING_FILE"
  fi
done < "$REFS_FILE"

MISSING_COUNT="$(wc -l < "$MISSING_FILE" | tr -d ' ')"

if [[ "$MISSING_COUNT" -gt 0 ]]; then
  echo "40-strip-private-hooks: FAIL — $MISSING_COUNT remaining hook(s)/statusLine reference a ~/.claude script that is not present in staging:" >&2
  while IFS= read -r m; do
    echo "  - $m" >&2
  done < "$MISSING_FILE"
  echo "  Either the target is genuinely missing from the public manifest (fix" >&2
  echo "  publish-manifest.txt), or it is another private-only hook this" >&2
  echo "  transform needs to learn to strip (add a removal pattern above)." >&2
  exit 1
fi

mv "$TMP" "$SETTINGS"

SUMMARY="removed ${BEFORE_COCKPIT_COUNT} cockpit-event.sh hook registration(s), ${BEFORE_GRAPHIFY_COUNT} graphify hook-guard entry/entries"
case "$STATUSLINE_ACTION" in
  redirect) SUMMARY="$SUMMARY, redirected statusLine to the pre-Cockpit ~/.claude/statusline-command.sh" ;;
  delete)   SUMMARY="$SUMMARY, deleted the cockpit statusLine key (no pre-Cockpit script found in staging)" ;;
  none)     ;;
esac
if [[ "$SUBAGENT_STATUSLINE_HAS_COCKPIT" == "true" ]]; then
  SUMMARY="$SUMMARY, deleted the cockpit subagentStatusLine key"
fi
if [[ "$HAD_OUTPUT_STYLE" == "true" ]]; then
  SUMMARY="$SUMMARY, removed outputStyle (owner's personal preference, not a framework default)"
fi

echo "40-strip-private-hooks: OK — $SUMMARY; verified ${REF_COUNT} remaining ~/.claude hook-script reference(s) all exist in staging"
