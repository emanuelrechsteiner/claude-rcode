#!/bin/bash
# command-contract-lint.sh — IMP-089 L3 (2026-07-15, Controller-First Enforcement)
# reconciled 2026-07-15 (IMP-089 closeout): the linter now checks the syntax
# ACTUALLY present in all 16 commands/*.md instead of an invented one.
# ─────────────────────────────────────────────────────────────────────────────
# Checks per command:
#   M. The `<!-- controller-contract:v1 -->` marker (lowercase, HTML comment)
#      is present. It MAY carry an inline `exempt="<reason>"` attribute —
#      that attribute is how a command declares itself read-only/mechanical
#      (handoff, simple-onboard, status-sync, ...). There is no longer a
#      separate CONTROLLER-EXEMPT marker — exemption lives on the contract
#      marker itself.
#   1. model: frontmatter present, value on the allowed-substrate pattern.
#      Skipped when the marker carries `exempt="..."`.
#   2. frontmatter allowed-tools contains Task/TaskCreate/TaskUpdate, OR the
#      marker carries `exempt="..."`. (The exempt attribute itself satisfies
#      this check — a command that doesn't dispatch subagents doesn't need
#      the Task family.)
#   3. The controller-contract preamble block contains its three mandatory
#      lines: "Controller-First", "Model×Effort per spawn ... §2", and
#      "Second-order checkpoints". A separate 2ND-ORDER-CHECKPOINT marker is
#      NOT required — the Second-order-checkpoints line inside the preamble
#      already covers that ground; requiring a second, distinct marker for
#      the same fact was redundant and didn't match any file on disk.
#      Skipped when the marker carries `exempt="..."`.
#   4. deny-grep against stale references (excessive-agency-gate.md,
#      autonomy-arbiter.md, ux-agent, frontend-agent). Runs unconditionally.
#   5. every agent named via "**<name>-agent**" is a real file under
#      agents/. Runs unconditionally.
#
# Usage:   bash scripts/command-contract-lint.sh [commands-dir]
#          (defaults to ~/.claude/commands)
# Exit:    0 = every file passed every applicable check; 1 = at least one
#          failure (report printed to stdout, one line per failure).
#
# Consumers (per IMP-089): stop-batched-checks.sh (commands/-touch trigger),
# /meta --verify, audit-config skill.
#
# Note (IMP-092 dependency, out of scope here): the allowed-substrate pattern
# below is intentionally permissive — it accepts today's mixed model-id shapes
# already in the repo (e.g. commands/bootstrap.md's "claude-fable-5[1m]") as
# well as short aliases ("opus", "fable") until IMP-092 lands and narrows the
# pin to the Fable class only. Override via CLAUDE_CONTRACT_MODEL_RE.
set -u

CMD_DIR="${1:-$HOME/.claude/commands}"
AGENTS_DIR="$HOME/.claude/agents"

MODEL_RE="${CLAUDE_CONTRACT_MODEL_RE:-^(opus|sonnet|haiku|fable)(\[1m\])?\$|^claude-(opus|sonnet|haiku|fable)-[0-9][0-9.-]*(\[1m\])?\$}"

DENY_TERMS=(
  "excessive-agency-gate.md"
  "autonomy-arbiter.md"
  "ux-agent"
  "frontend-agent"
)

if [ ! -d "$CMD_DIR" ]; then
  echo "command-contract-lint: commands dir not found: $CMD_DIR" >&2
  exit 1
fi

FAIL=0
REPORT=""
CHECKED=0

for f in "$CMD_DIR"/*.md; do
  [ -e "$f" ] || continue
  CHECKED=$((CHECKED+1))
  BASE=$(basename "$f")
  CONTENT=$(cat "$f")

  # Frontmatter block (between the first and second `---` fence lines).
  FRONTMATTER=$(printf '%s\n' "$CONTENT" | awk '
    /^---[[:space:]]*$/{c++; next}
    c==1{print}
    c>=2{exit}
  ')

  # Check M — the controller-contract:v1 marker itself (lowercase, HTML
  # comment). Its optional `exempt="<reason>"` attribute is the ONLY signal
  # for exemption — there is no separate CONTROLLER-EXEMPT marker.
  MARKER_LINE=$(printf '%s\n' "$CONTENT" | grep -E '<!--[[:space:]]*controller-contract:v1' | head -1)
  if [ -z "$MARKER_LINE" ]; then
    FAIL=1
    REPORT="${REPORT}[$BASE] checkM: missing controller-contract:v1 marker\n"
    EXEMPT_REASON=""
  else
    EXEMPT_REASON=$(printf '%s' "$MARKER_LINE" | grep -oE 'exempt="[^"]*"' | sed -E 's/^exempt="//; s/"$//')
  fi

  if [ -z "$EXEMPT_REASON" ]; then
    # Check 1 — model: frontmatter, on the allowed-substrate pattern
    MODEL_VAL=$(printf '%s\n' "$FRONTMATTER" | grep -E '^model:' | head -1 \
      | sed -E 's/^model:[[:space:]]*//; s/^"//; s/"[[:space:]]*$//')
    if [ -z "$MODEL_VAL" ]; then
      FAIL=1
      REPORT="${REPORT}[$BASE] check1: missing model: frontmatter\n"
    elif ! printf '%s' "$MODEL_VAL" | grep -qE "$MODEL_RE"; then
      FAIL=1
      REPORT="${REPORT}[$BASE] check1: model '$MODEL_VAL' not on allowed-substrate pattern\n"
    fi

    # Check 3 — controller-contract preamble carries its three mandatory
    # lines (Controller-First / Model×Effort-per-spawn-§2 / Second-order
    # checkpoints). No separate 2ND-ORDER-CHECKPOINT marker is required.
    if ! printf '%s' "$CONTENT" | grep -qE 'Controller-First'; then
      FAIL=1
      REPORT="${REPORT}[$BASE] check3: preamble missing Controller-First line\n"
    fi
    # NOTE: matches on "Effort per spawn" rather than "Model×Effort" — the
    # literal × (U+00D7, 2 UTF-8 bytes) breaks a single-byte "." wildcard
    # under plain /usr/bin/grep in the C locale (confirmed: this repo's
    # interactive tool shell shadows `grep` with a UTF-8-aware `ugrep`
    # wrapper that masked the bug; a bare `bash` invocation — exactly how
    # hooks/skills call this script — does not have that wrapper).
    if ! printf '%s' "$CONTENT" | grep -qE 'Effort per spawn.*agents/control-agent\.md.*§2'; then
      FAIL=1
      REPORT="${REPORT}[$BASE] check3: preamble missing Model x Effort per control-agent.md §2 line\n"
    fi
    if ! printf '%s' "$CONTENT" | grep -qE 'Second-order checkpoints'; then
      FAIL=1
      REPORT="${REPORT}[$BASE] check3: preamble missing Second-order checkpoints line\n"
    fi
  fi

  # Check 2 — frontmatter allowed-tools contains Task/TaskCreate/TaskUpdate,
  # OR the marker's exempt="..." attribute is present. Runs unconditionally,
  # but the exempt attribute alone satisfies it.
  if [ -z "$EXEMPT_REASON" ]; then
    if ! printf '%s\n' "$FRONTMATTER" | grep -qE '\b(Task|TaskCreate|TaskUpdate)\b'; then
      FAIL=1
      REPORT="${REPORT}[$BASE] check2: allowed-tools missing Task/TaskCreate/TaskUpdate (or needs exempt=\"...\" on the marker)\n"
    fi
  fi

  # Check 4 — deny-grep (applies regardless of exemption). A line that only
  # explains a stale reference HISTORICALLY (case-insensitive hit on
  # archiv|superseded|retired|ersetzt on the SAME line as the term) is not a
  # live/functional reference and is exempted from the deny-grep — e.g.
  # "ux-agent was archived 2026-05-27, replaced by the ux-design skill".
  for term in "${DENY_TERMS[@]}"; do
    while IFS= read -r HIT_LINE; do
      [ -n "$HIT_LINE" ] || continue
      if ! printf '%s' "$HIT_LINE" | grep -qiE 'archiv|superseded|retired|ersetzt'; then
        FAIL=1
        REPORT="${REPORT}[$BASE] check4: stale reference '$term'\n"
      fi
    done < <(printf '%s\n' "$CONTENT" | grep -F "$term")
  done

  # Check 5 — every "**X-agent**"-named agent exists in agents/ (applies
  # regardless of exemption — a bogus agent name is a bug either way)
  while IFS= read -r AGENT_NAME; do
    [ -n "$AGENT_NAME" ] || continue
    if [ ! -f "$AGENTS_DIR/$AGENT_NAME.md" ]; then
      FAIL=1
      REPORT="${REPORT}[$BASE] check5: referenced agent '$AGENT_NAME' has no agents/$AGENT_NAME.md\n"
    fi
  done < <(printf '%s' "$CONTENT" | grep -oE '\*\*[a-z][a-z0-9-]*-agent\*\*' | sed 's/\*\*//g' | sort -u)
done

if [ "$CHECKED" -eq 0 ]; then
  echo "command-contract-lint: no *.md files found in $CMD_DIR" >&2
  exit 1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "command-contract-lint: all $CHECKED command(s) in $CMD_DIR pass"
  exit 0
else
  printf "command-contract-lint: FAILURES (checked %d command(s))\n%b" "$CHECKED" "$REPORT"
  exit 1
fi
