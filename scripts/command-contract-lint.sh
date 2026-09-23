#!/bin/bash
# command-contract-lint.sh — IMP-089 L3 (2026-07-15, Controller-First Enforcement)
# reconciled 2026-07-15 (IMP-089 closeout): the linter now checks the syntax
# ACTUALLY present in all 16 commands/*.md instead of an invented one.
# extended 2026-09-23 (M20/§5/A4, R.Code rework "Plan folgt Praxis", unit U9):
# an optional --root flag turns on a second sweep (checks C4-extended, C6-C9)
# over the wider R.Code artifact set. See "Extended scope" below.
# ─────────────────────────────────────────────────────────────────────────────
# Checks per command (unconditional; ALWAYS run over commands-dir, unchanged
# since 2026-07-15 — this is the "default behavior" the M20 rework promises
# to leave untouched):
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
#      autonomy-arbiter.md, ux-agent, frontend-agent). Runs unconditionally
#      over commands-dir; ALSO scans the extended scope (below) when --root
#      is given.
#   5. every agent named via "**<name>-agent**" is a real file under
#      agents/. Runs unconditionally.
#
# Extended scope (checks C6, C7, C8, C9 + the C4 deny-grep widened; only
# when the caller passes --root):
#   C6. no repo-relative gather-script call (`bash scripts/<gather-script>.sh`
#       instead of `bash ~/.claude/scripts/<gather-script>.sh`) — M1.
#   C7. no bare `/review` command reference (the real command is
#       `/rcode-review`) — M2.
#   C8. no zsh `"$name:letter` modifier trap in a double-quoted shell
#       snippet — a bare (unbraced) variable directly followed by `:` and a
#       letter is read by zsh as a history-style modifier
#       (`"$sha:rcode/VERSION"` → `e7eb35bcode/VERSION`) — M3. `${name}:` is
#       never flagged (braced), and `$name:` followed by anything other than
#       a letter (space, digit, …) is never flagged either.
#   C9. no repo-relative framework-file reference — a backtick-quoted path
#       starting with `commands/`, `rules/`, `agents/`, `templates/`,
#       `scripts/`, `skills/` or `rcode/` that is NOT already qualified
#       `~/.claude/...` — M18. A project-relative path with a leading dot
#       (`` `.claude/rules/...` ``, a PROJECT's own installed copy) is never
#       flagged — the match requires the group word to sit immediately after
#       the opening backtick.
# These four checks run over: commands-dir/*.md, `<root>/rcode/**/*.md`,
# `<root>/skills/rcode-*/SKILL.md`, `<root>/skills/scope-check/SKILL.md`
# (the A4 scope). An HTML comment `<!-- lint:allow -->` on the SAME LINE
# exempts that line from C6-C9 (not from C4/M/1-5) — for docs that must
# quote the old broken strings as an example.
#
# --root is deliberately opt-in: without it, the script's behavior, output
# and exit code are BYTE-IDENTICAL to the pre-2026-09-23 version (checks
# M,1-5 only, over commands-dir only). This matters because the extended
# scope reaches into rcode/ and skills/rcode-*/skills/scope-check — files
# owned by OTHER concurrently-worked units during the R.Code rework; a caller
# that hasn't opted in must not start failing because of work-in-progress
# elsewhere in the tree.
#
# Usage:   bash scripts/command-contract-lint.sh [commands-dir]
#          bash scripts/command-contract-lint.sh --root <dir> [commands-dir]
#          (commands-dir defaults to ~/.claude/commands; when --root is given
#          without a commands-dir, it defaults to <root>/commands)
# Exit:    0 = every file passed every applicable check; 1 = at least one
#          failure (report printed to stdout, one line per failure).
#
# Consumers (per IMP-089): stop-batched-checks.sh (commands/-touch trigger),
# /meta --verify, audit-config skill. Extended-scope consumers (2026-09-23):
# the same three, now passing --root "$HOME/.claude" (or, for the Bauhof
# self-check, --root <repo-root>).
#
# Note (IMP-092 dependency, out of scope here): the allowed-substrate pattern
# below is intentionally permissive — it accepts today's mixed model-id shapes
# already in the repo (e.g. commands/bootstrap.md's "claude-fable-5[1m]") as
# well as short aliases ("opus", "fable") until IMP-092 lands and narrows the
# pin to the Fable class only. Override via CLAUDE_CONTRACT_MODEL_RE.
set -u

# ── Argument parsing: [--root <dir>] [commands-dir] ────────────────────────
# --root is the ONLY new flag (space-separated form only, matching the one
# form the spec documents: `--root "$PWD" "$PWD/commands"`). Any other
# argument is treated as the positional commands-dir, first-one-wins.
CMD_DIR=""
ROOT=""
ROOT_EXPLICIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      if [ $# -lt 2 ]; then
        echo "command-contract-lint: --root requires a value" >&2
        exit 1
      fi
      ROOT="$2"
      ROOT_EXPLICIT=1
      shift 2
      ;;
    *)
      [ -n "$CMD_DIR" ] || CMD_DIR="$1"
      shift
      ;;
  esac
done

if [ -z "$CMD_DIR" ]; then
  if [ "$ROOT_EXPLICIT" -eq 1 ]; then
    CMD_DIR="$ROOT/commands"
  else
    CMD_DIR="$HOME/.claude/commands"
  fi
fi
if [ "$ROOT_EXPLICIT" -eq 0 ]; then
  # Default-value formula per §5 ("parent of commands-dir when given, else
  # ~/.claude"), kept for consistency/messages even though — per the
  # byte-identical-default-behavior guarantee above — nothing reads $ROOT
  # for extended-scope scanning unless --root was explicitly passed.
  ROOT=$(dirname "$CMD_DIR")
fi

AGENTS_DIR="$HOME/.claude/agents"

MODEL_RE="${CLAUDE_CONTRACT_MODEL_RE:-^(opus|sonnet|haiku|fable)(\[1m\])?\$|^claude-(opus|sonnet|haiku|fable)-[0-9][0-9.-]*(\[1m\])?\$}"

DENY_TERMS=(
  "excessive-agency-gate.md"
  "autonomy-arbiter.md"
  "ux-agent"
  "frontend-agent"
)

# ── Extended-scope (C6-C9) regexes and same-line escape marker ─────────────
C6_RE='bash scripts/(phase-gate-check|status-metrics|resume-state)\.sh'
C7_RE='(^|[^-A-Za-z0-9_/~.])/review([^-A-Za-z0-9_]|$)'
C8_RE='"\$[A-Za-z_][A-Za-z0-9_]*:[A-Za-z]'
C9_RE='`(commands|rules|agents|templates|scripts|skills|rcode)/[^`]*`'
LINT_ALLOW_MARKER='<!-- lint:allow -->'

# run_c6_c9 <label> <content> — runs checks C6-C9 against <content>, doing
# ONE whole-file grep pass per check (never a per-line subprocess loop —
# C0/C22/C27/C36, 2026-09-23: the previous while-read-line loop forked up to
# 9 processes PER LINE of every scanned file — measured 45.7s-156s against
# this repo's extended scope, hung past a 90s timeout against the fuller
# tree). A line carrying the same-line escape comment is dropped from EVERY
# check's match set via a second grep on the already-small matched-line
# output — appending to the shared $FAIL/$REPORT (bash: not a subshell, so
# mutations are visible to the caller).
run_c6_c9() {
  local label="$1" content="$2"
  _lint_c6c9_one "$label" "$content" "$C6_RE" "check6" \
    "repo-relative gather-script call (use ~/.claude/scripts/...)"
  _lint_c6c9_one "$label" "$content" "$C7_RE" "check7" \
    "bare /review command reference (the real command is /rcode-review)"
  _lint_c6c9_one "$label" "$content" "$C8_RE" "check8" \
    'zsh $name: modifier trap (brace it: ${name}:)'
  _lint_c6c9_one "$label" "$content" "$C9_RE" "check9" \
    "repo-relative framework-file reference (use ~/.claude/...)"
}

# _lint_c6c9_one <label> <content> <regex> <tag> <message> — one whole-file
# `grep -nE` pass for <regex>, then one `grep -vF` pass over that (small)
# matched-line set to drop lines carrying $LINT_ALLOW_MARKER. O(1) forks
# per check regardless of file length (was O(lines)). One REPORT line is
# appended per surviving match — same granularity as the old per-line loop.
_lint_c6c9_one() {
  local label="$1" content="$2" re="$3" tag="$4" msg="$5" matches
  matches=$(grep -nE "$re" <<< "$content" 2>/dev/null | grep -vF "$LINT_ALLOW_MARKER")
  [ -n "$matches" ] || return 0
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    FAIL=1
    REPORT="${REPORT}[$label] $tag: $msg\n"
  done <<< "$matches"
}

# _lint_check4_scan <label> <content> — deny-grep over DENY_TERMS, ONE
# `grep -F` pass + ONE `grep -viE` pass PER TERM against the whole file
# (never per hit-line — same C0/C22/C27/C36 fix, applied to the two
# DENY_TERMS loops the finding also named). A hit line carrying an
# archived/superseded/retired/ersetzt marker ON THE SAME LINE is exempt
# (case-insensitive) — e.g. "ux-agent was archived 2026-05-27, replaced by
# the ux-design skill". Shared by the unconditional commands-dir check4
# below and the --root-only widened-scope check4.
_lint_check4_scan() {
  local label="$1" content="$2" term hits
  for term in "${DENY_TERMS[@]}"; do
    hits=$(grep -F "$term" <<< "$content" | grep -viE 'archiv|superseded|retired|ersetzt')
    [ -n "$hits" ] || continue
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      FAIL=1
      REPORT="${REPORT}[$label] check4: stale reference '$term'\n"
    done <<< "$hits"
  done
}

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
  _lint_check4_scan "$BASE" "$CONTENT"

  # Check 5 — every "**X-agent**"-named agent exists in agents/ (applies
  # regardless of exemption — a bogus agent name is a bug either way)
  while IFS= read -r AGENT_NAME; do
    [ -n "$AGENT_NAME" ] || continue
    if [ ! -f "$AGENTS_DIR/$AGENT_NAME.md" ]; then
      FAIL=1
      REPORT="${REPORT}[$BASE] check5: referenced agent '$AGENT_NAME' has no agents/$AGENT_NAME.md\n"
    fi
  done < <(printf '%s' "$CONTENT" | grep -oE '\*\*[a-z][a-z0-9-]*-agent\*\*' | sed 's/\*\*//g' | sort -u)

  # Checks C6-C9 (only with --root — see "byte-identical default behavior"
  # note in the header). Part of the A4 scope's "commands/*.md" leg; the
  # rest of that scope (rcode/**, skills/rcode-*, skills/scope-check) is
  # swept separately below, after this loop.
  if [ "$ROOT_EXPLICIT" -eq 1 ]; then
    run_c6_c9 "$BASE" "$CONTENT"
  fi
done

if [ "$CHECKED" -eq 0 ]; then
  echo "command-contract-lint: no *.md files found in $CMD_DIR" >&2
  exit 1
fi

# ── Extended scope (only with --root): C4 widened + C6-C9 over
#    <root>/rcode/**/*.md, <root>/skills/rcode-*/SKILL.md,
#    <root>/skills/scope-check/SKILL.md (the A4 scope, minus the
#    commands/*.md leg already covered inside the loop above). ─────────────
if [ "$ROOT_EXPLICIT" -eq 1 ]; then
  EXT_FILES_LIST=$(mktemp)
  if [ -d "$ROOT/rcode" ]; then
    find "$ROOT/rcode" -type f -name '*.md' 2>/dev/null | sort >> "$EXT_FILES_LIST"
  fi
  for f in "$ROOT"/skills/rcode-*/SKILL.md; do
    [ -e "$f" ] && printf '%s\n' "$f" >> "$EXT_FILES_LIST"
  done
  if [ -f "$ROOT/skills/scope-check/SKILL.md" ]; then
    printf '%s\n' "$ROOT/skills/scope-check/SKILL.md" >> "$EXT_FILES_LIST"
  fi

  while IFS= read -r EXT_FILE; do
    [ -n "$EXT_FILE" ] || continue
    [ -f "$EXT_FILE" ] || continue
    EXT_BASE=${EXT_FILE#"$ROOT"/}
    EXT_CONTENT=$(cat "$EXT_FILE")

    # Check 4, widened scope — same deny-grep + archived-marker exemption
    # as the unconditional check4 above, just over rcode/skills instead of
    # commands-dir.
    _lint_check4_scan "$EXT_BASE" "$EXT_CONTENT"

    run_c6_c9 "$EXT_BASE" "$EXT_CONTENT"
  done < "$EXT_FILES_LIST"
  rm -f "$EXT_FILES_LIST"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "command-contract-lint: all $CHECKED command(s) in $CMD_DIR pass"
  exit 0
else
  printf "command-contract-lint: FAILURES (checked %d command(s))\n%b" "$CHECKED" "$REPORT"
  exit 1
fi
