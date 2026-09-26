#!/usr/bin/env bash
# rcode-units.sh — the ONE tracker-agnostic unit parser for the R.Code
# workflow (spec: rcode-umbau-spec.md §9 A3). status-metrics.sh and
# phase-gate-check.sh MUST call this script for unit counts rather than
# re-implementing their own count — see rules/testing-quality.md "Verify via
# the same code path, not a reimplementation": two independently-written
# counters drift, and a test built on the drifted copy passes while the real
# path stays broken.
# ─────────────────────────────────────────────────────────────────────────────
# WHY THIS EXISTS: a project's units live in one of two places — GitHub
# issues (tracker "github") or checkbox/table lines inside BRAINSTORM.md
# (tracker "plan", for projects with no issue tracker — a real project was
# measured at 0/28 commits referencing any unit, with no git remote at
# all). Every gather script that needs
# "how many units, which are open/closed, which phase" used to assume
# GitHub; M14 in the spec is exactly that hard GitHub prerequisite breaking
# on real, working, GitHub-less projects. This script is the fix: it reads
# EITHER source and normalizes to one shape.
#
# Tracker resolution is NON-INTERACTIVE (scripts never ask — see A10, which
# reserves the interactive AskUserQuestion path for the *commands*):
#   1. `.rcode/config.json` .tracker, if set.
#   2. Else inferred: "github" iff a git remote exists AND `gh auth status`
#      succeeds AND `gh issue list --limit 1` returns >=1 issue; else "plan".
#      Always recorded as a finding, never silently assumed.
#
# Plan-tracker grammar (A2 — READ both forms, this script never WRITES):
#   (a) checkbox line:  `- [ ] P-012 — <Title> ...` / `- [x] ...`
#   (b) table row whose FIRST cell is the ID:
#       `| P-001 | [Phase 1] <Title> | <Type> | <Area> | ... |`
#   (c) K-A, 2026-09-23 — LOCAL-NUMBER table: a table whose FIRST HEADER
#       cell (case-insensitive) is one of `#`, `ID`, `Nr`, `Nr.`, and whose
#       row's first cell is a bare integer or `#`+integer (e.g. a real
#       project's shape: header `| # | Titel | ... |`, row `| 12 | ... |`).
#       The unit id is written `#N` (a LOCAL plan number, NOT a GitHub
#       issue — the `tracker` field disambiguates; this grammar only ever
#       runs in plan mode, so it never collides with github `#N`
#       semantics). A P-NNN row inside such a table is still checked FIRST
#       and keeps working unchanged.
# Phase membership: the `[Phase N]` prefix in the title if present, else the
# nearest preceding markdown heading (## - ####) containing "Phase N". A
# heading of the form `### Phase N — <Name>` (em/en-dash or hyphen
# separator, same convention as the checkbox row's ID/title separator
# below) also carries a `phase_name` (K-B, 2026-09-23) — the trimmed
# <Name> suffix, or null when the heading carries no name — reported
# per-unit so status-metrics.sh can build a milestone title without
# re-reading BRAINSTORM.md itself (rules/testing-quality.md "same code
# path" discipline).
# Completion: checkbox `[x]` -> closed, `[ ]` -> open. Table row: a column
# whose header is `Status`/`State` (case-insensitive) with a value matching
# done|closed|complete|completed|check-mark|x -> closed, any other value ->
# open; a table WITHOUT such a column -> state "unknown" for every row in it
# (never a fabricated open/closed — see rules/fail-loud.md). No P-NNN IDs,
# and no local-number table, at all -> units:[] + a finding naming that,
# never a silently-empty result.
#
# Usage:
#   rcode-units.sh [project-dir]
#   rcode-units.sh --help
#
# Output (stdout, JSON):
#   {
#     "ok": bool,
#     "tracker": "github"|"plan"|null,   // null only on a usage error (exit 2)
#     "source": string,              // "gh issue list" | "BRAINSTORM.md" | null
#     "units": [{"id":string, "title":string, "phase":int|null, "phase_name":string|null, "state":"open"|"closed"|"unknown"}],
#     "findings": [string],
#     "errors":   [string]
#   }
#   phase_name (K-B, 2026-09-23): the plan tracker's `### Phase N — <Name>`
#   heading text, trimmed, or null when the heading has no name suffix or
#   the unit's phase never came from a heading. Always null in github mode
#   (status-metrics.sh's github path reads `.milestone.title` directly, not
#   this field — see that script's header for why).
#
# Exit codes:
#   0  ok:true  — gather succeeded
#   1  ok:false — a prerequisite was missing or a command could not be run
#   2  usage error (bad arguments) — JSON is still emitted
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: rcode-units.sh [project-dir]
       rcode-units.sh --help

Tracker-agnostic unit parser. Emits every work unit (GitHub issue or plan-
tracker BRAINSTORM.md line/row) as one normalized JSON array. See the
script's own header comment for the full grammar/resolution rules.

Arguments:
  [project-dir]   Optional. Defaults to the current directory.

Output (stdout, JSON):
  {
    "ok": bool,
    "tracker": "github"|"plan"|null,   // null only on a usage error (exit 2)
    "source": string|null,
    "units": [{"id":string, "title":string, "phase":int|null, "phase_name":string|null, "state":"open"|"closed"|"unknown"}],
    "findings": [string],
    "errors":   [string]
  }

Exit codes:
  0  ok:true   (gather succeeded)
  1  ok:false  (a prerequisite was missing or a command failed — see errors[])
  2  usage error (bad arguments) — JSON is still emitted on stdout
EOF
}

json_array() { jq -n --args '$ARGS.positional' -- "$@"; }

# run_capture — see phase-gate-check.sh for full rationale (split stdout/
# stderr temp-file capture so `set -e` never silently aborts on an expected
# non-zero exit; every call site inspects $RUN_RC explicitly).
run_capture() {
  local out_f err_f rc
  out_f=$(mktemp "${TMPDIR:-/tmp}/rcu-out.XXXXXX")
  err_f=$(mktemp "${TMPDIR:-/tmp}/rcu-err.XXXXXX")
  set +e
  "$@" >"$out_f" 2>"$err_f"
  rc=$?
  set -e
  RUN_OUT="$(cat "$out_f")"
  RUN_ERR="$(cat "$err_f")"
  RUN_RC=$rc
  rm -f "$out_f" "$err_f"
}

# PLAN_AWK_PROG — the A2 plan-tracker line/table parser, in portable POSIX
# awk (NO gawk extensions: no 3-arg match(), no {m,n} interval expressions —
# macOS ships the "one true" BWK awk, not gawk; verified against
# `awk --version` -> "awk version 20200816"). It walks BRAINSTORM.md once,
# tracking the nearest preceding Phase heading and, for markdown tables, a
# one-line lookahead to tell a header row (immediately followed by a
# `|---|---|` separator) from a data row. For each unit line/row it prints
# one record: `id<US>state<US>phase<US>title` (US = 0x1F / octal \037) so
# the caller can split on \u001f in jq without hand-rolled JSON escaping —
# titles may contain quotes, backticks or pipes.
#
# `read -d ''` always returns 1 at EOF even on a fully-successful heredoc
# capture (documented bash quirk — see status-metrics.sh) — the `|| true`
# masks ONLY that known-benign EOF status.
read -r -d '' PLAN_AWK_PROG <<'AWKEOF' || true
function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
function rtrim(s) { sub(/[ \t]+$/, "", s); return s }
function trim(s) { return rtrim(ltrim(s)) }

function is_separator(l,    t) {
  t = l
  gsub(/[ \t]/, "", t)
  if (t == "") return 0
  if (t !~ /^\|?[-:|]+\|?$/) return 0
  if (t !~ /-/) return 0
  return 1
}

function split_cells(l, out,    n, i, m, raw) {
  n = split(l, raw, "|")
  m = 0
  for (i = 1; i <= n; i++) {
    if (i == 1 && trim(raw[i]) == "") continue
    if (i == n && trim(raw[i]) == "") continue
    m++
    out[m] = trim(raw[i])
  }
  return m
}

function emit(id, state, phase, phase_name, title) {
  printf "%s\037%s\037%s\037%s\037%s\n", id, state, phase, phase_name, title
}

function id_is_unit(s) {
  return (s ~ /^P-[0-9][0-9][0-9]+$/)
}

# id_is_local_num / normalize_local_id — K-A local-number table grammar
# (2026-09-23): a bare integer or "#"+integer first cell, ONLY consulted
# when local_id_table (set from the header row) says the table's first
# header cell was one of "#"/"ID"/"Nr"/"Nr." — never applied outside a
# table recognized that way, and always checked AFTER id_is_unit (P-NNN),
# so a P-NNN row keeps working unchanged even inside such a table.
function id_is_local_num(s) {
  return (s ~ /^#?[0-9]+$/)
}

function normalize_local_id(s,    d) {
  d = s
  sub(/^#/, "", d)
  return "#" d
}

function extract_phase_prefix(title,    s, digits, i, c) {
  if (match(title, /\[[Pp][Hh][Aa][Ss][Ee][ \t]+[0-9]+\]/)) {
    s = substr(title, RSTART, RLENGTH)
    digits = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (c >= "0" && c <= "9") digits = digits c
      else if (digits != "") break
    }
    return digits
  }
  return ""
}

function process_table_row(l,    n, cells, id, unit_id, title, phase, state, val) {
  n = split_cells(l, cells)
  if (n < 1) return
  id = cells[1]
  if (id_is_unit(id)) {
    unit_id = id
  } else if (local_id_table && id_is_local_num(id)) {
    unit_id = normalize_local_id(id)
  } else {
    return
  }
  title = (n >= 2) ? cells[2] : ""
  phase = extract_phase_prefix(title)
  if (phase == "") phase = heading_phase
  if (status_col > 0 && status_col <= n) {
    val = tolower(cells[status_col])
    if (val ~ /done|closed|complete|completed|✅|^x$/) state = "closed"
    else state = "open"
  } else {
    state = "unknown"
  }
  emit(unit_id, state, phase, heading_phase_name, title)
}

function process_checkbox_row(l,    state, id, rest, title, phase) {
  if (l ~ /^[ \t]{0,3}-[ \t]+\[[xX]\][ \t]+P-[0-9][0-9][0-9]+/) {
    state = "closed"
  } else if (l ~ /^[ \t]{0,3}-[ \t]+\[[ \t]\][ \t]+P-[0-9][0-9][0-9]+/) {
    state = "open"
  } else {
    return
  }
  if (!match(l, /P-[0-9][0-9][0-9]+/)) return
  id = substr(l, RSTART, RLENGTH)
  rest = substr(l, RSTART + RLENGTH)
  rest = ltrim(rest)
  if (rest ~ /^[—–-][ \t]+/) sub(/^[—–-][ \t]+/, "", rest)
  title = trim(rest)
  phase = extract_phase_prefix(title)
  if (phase == "") phase = heading_phase
  emit(id, state, phase, heading_phase_name, title)
}

BEGIN { heading_phase = ""; heading_phase_name = ""; status_col = 0; local_id_table = 0; pending = "" }

{
  line = $0
  sub(/\r$/, "", line)

  if (line ~ /^#/) {
    h = line
    nhash = 0
    while (substr(h, 1, 1) == "#") { nhash++; h = substr(h, 2) }
    if (nhash >= 2 && nhash <= 4 && substr(h, 1, 1) == " ") {
      if (pending != "") { process_table_row(pending); pending = "" }
      status_col = 0
      local_id_table = 0
      if (match(line, /[Pp][Hh][Aa][Ss][Ee][ \t]+[0-9]+/)) {
        frag = substr(line, RSTART, RLENGTH)
        digits = ""
        for (i = 1; i <= length(frag); i++) {
          c = substr(frag, i, 1)
          if (c >= "0" && c <= "9") digits = digits c
        }
        if (digits != "") {
          heading_phase = digits
          # K-B, 2026-09-23: capture the heading's <Name> suffix (same
          # em/en-dash-or-hyphen separator convention as
          # process_checkbox_row's ID/title split above) — "" when the
          # heading carries no name (e.g. a bare "### Phase 4").
          hrest = substr(line, RSTART + RLENGTH)
          hrest = ltrim(hrest)
          if (hrest ~ /^[—–-][ \t]+/) sub(/^[—–-][ \t]+/, "", hrest)
          heading_phase_name = trim(hrest)
        }
      }
      next
    }
  }

  if (is_separator(line)) {
    if (pending != "") {
      m = split_cells(pending, cols)
      status_col = 0
      for (i = 1; i <= m; i++) {
        hh = tolower(cols[i])
        if (hh == "status" || hh == "state") { status_col = i; break }
      }
      local_id_table = 0
      if (m >= 1) {
        hh1 = tolower(cols[1])
        if (hh1 == "#" || hh1 == "id" || hh1 == "nr" || hh1 == "nr.") local_id_table = 1
      }
      pending = ""
    }
    next
  }

  if (line ~ /^\|/) {
    if (pending != "") process_table_row(pending)
    pending = line
    next
  }

  if (line ~ /^[ \t]{0,3}-[ \t]+\[/) {
    if (pending != "") { process_table_row(pending); pending = "" }
    process_checkbox_row(line)
    next
  }

  if (pending != "") { process_table_row(pending); pending = "" }
}

END {
  if (pending != "") process_table_row(pending)
}
AWKEOF

findings=()
errors=()

emit_and_exit() {
  local exit_code="$1"
  local ok_bool="false"
  [[ ${#errors[@]} -eq 0 ]] && ok_bool="true"

  jq -n \
    --argjson ok "$ok_bool" \
    --arg tracker "${TRACKER:-}" \
    --argjson has_tracker "${HAS_TRACKER:-false}" \
    --arg source "${SOURCE_LABEL:-}" \
    --argjson has_source "${HAS_SOURCE:-false}" \
    --argjson units "${units_json:-[]}" \
    --argjson findings "$(json_array "${findings[@]+"${findings[@]}"}")" \
    --argjson errors "$(json_array "${errors[@]+"${errors[@]}"}")" \
    '{ok:$ok, tracker: (if $has_tracker then $tracker else null end), source: (if $has_source then $source else null end), units:$units, findings:$findings, errors:$errors}'
  exit "$exit_code"
}

# ── Argument parsing ─────────────────────────────────────────────────────
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

PROJECT_DIR="${1:-$(pwd)}"
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: project directory does not exist: $PROJECT_DIR" >&2
  errors+=("project directory does not exist: $PROJECT_DIR")
  emit_and_exit 2
fi
cd "$PROJECT_DIR"

HAS_TRACKER=false
HAS_SOURCE=false
units_json="[]"

# ── Tracker resolution (A3, A10: scripts infer, never ask) ──────────────
TRACKER=""
CONFIG_FILE=".rcode/config.json"
if [[ -f "$CONFIG_FILE" ]]; then
  run_capture jq -r '.tracker // empty' "$CONFIG_FILE"
  if [[ $RUN_RC -eq 0 && -n "$RUN_OUT" ]]; then
    TRACKER="$RUN_OUT"
  fi
fi

if [[ -z "$TRACKER" ]]; then
  has_remote=false
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    run_capture git remote
    [[ $RUN_RC -eq 0 && -n "$RUN_OUT" ]] && has_remote=true
  fi
  inferred="plan"
  if [[ "$has_remote" == "true" ]] && command -v gh >/dev/null 2>&1; then
    run_capture gh auth status
    if [[ $RUN_RC -eq 0 ]]; then
      run_capture gh issue list --limit 1 --json number
      if [[ $RUN_RC -eq 0 ]]; then
        probe_n=$(jq 'length' <<<"$RUN_OUT" 2>/dev/null || echo 0)
        [[ "$probe_n" -ge 1 ]] && inferred="github"
      fi
    fi
  fi
  TRACKER="$inferred"
  findings+=("tracker not set in .rcode/config.json — inferred ${TRACKER}")
fi
HAS_TRACKER=true

if [[ "$TRACKER" != "github" && "$TRACKER" != "plan" ]]; then
  findings+=("unrecognized tracker '${TRACKER}' in .rcode/config.json — falling back to 'plan'")
  TRACKER="plan"
fi

# ── github mode: single `gh issue list` call ─────────────────────────────
if [[ "$TRACKER" == "github" ]]; then
  SOURCE_LABEL="gh issue list"
  HAS_SOURCE=true

  if ! command -v gh >/dev/null 2>&1; then
    errors+=("gh CLI not found — tracker is 'github', this script is entirely gh-issue-derived, there is no degraded mode")
    emit_and_exit 1
  fi
  if ! command -v git >/dev/null 2>&1; then
    errors+=("git binary not found")
    emit_and_exit 1
  fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    errors+=("not a git repository: $PROJECT_DIR — cannot resolve owner/repo for gh")
    emit_and_exit 1
  fi
  run_capture gh auth status
  if [[ $RUN_RC -ne 0 ]]; then
    errors+=("gh is not authenticated (gh auth status failed): $(printf '%s' "$RUN_ERR" | head -c 300)")
    emit_and_exit 1
  fi

  run_capture gh issue list --state all --json number,title,state,milestone,labels --limit 1000
  if [[ $RUN_RC -ne 0 ]]; then
    errors+=("gh issue list failed: $(printf '%s' "$RUN_ERR" | head -c 300)")
    emit_and_exit 1
  fi
  issues_json="$RUN_OUT"

  issue_count=$(jq 'length' <<<"$issues_json")
  if [[ "$issue_count" -eq 1000 ]]; then
    findings+=("issue count hit the 1000-item fetch limit — results may be truncated; increase --limit if this repo has more than 1000 issues")
  fi

  read -r -d '' JQ_FILTER <<'JQEOF' || true
[
  .[] | {
    id: ("#" + (.number|tostring)),
    title: .title,
    phase: (
      (if (.milestone != null and ((.milestone.title // "") | test("^[Pp]hase\\s+[0-9]+"))) then
         (.milestone.title | capture("^[Pp]hase\\s+(?<n>[0-9]+)").n | tonumber)
       else null end)
      // (
        (((.labels // []) | map(.name) | map(select(test("^phase-[0-9]+$"; "i"))) | .[0])) as $lbl
        | if $lbl != null then ($lbl | capture("phase-(?<n>[0-9]+)"; "i").n | tonumber) else null end
      )
    ),
    phase_name: null,
    state: (.state | ascii_downcase)
  }
]
JQEOF

  run_capture jq "$JQ_FILTER" <<<"$issues_json"
  if [[ $RUN_RC -ne 0 ]]; then
    errors+=("failed to normalize gh issue list output: $(printf '%s' "$RUN_ERR" | head -c 300)")
    emit_and_exit 1
  fi
  units_json="$RUN_OUT"

  if [[ "$(jq 'length' <<<"$units_json")" -eq 0 ]]; then
    findings+=("no GitHub issues found — run /decompose (github mode) to create units")
  fi

# ── plan mode: A2 grammar over BRAINSTORM.md ─────────────────────────────
else
  BRAINSTORM_FILE="BRAINSTORM.md"
  if [[ ! -f "$BRAINSTORM_FILE" ]]; then
    SOURCE_LABEL="BRAINSTORM.md"
    HAS_SOURCE=true
    findings+=("BRAINSTORM.md not found in ${PROJECT_DIR} — no plan units found (run /brainstorm or /rcode-init)")
    units_json="[]"
  else
    SOURCE_LABEL="BRAINSTORM.md"
    HAS_SOURCE=true

    run_capture awk "$PLAN_AWK_PROG" "$BRAINSTORM_FILE"
    if [[ $RUN_RC -ne 0 ]]; then
      errors+=("plan-tracker parse of ${BRAINSTORM_FILE} failed: $(printf '%s' "$RUN_ERR" | head -c 300)")
      emit_and_exit 1
    fi
    raw_units="$RUN_OUT"

    # Each raw line is id<US>state<US>phase<US>title (US = 0x1F). jq splits
    # on \u001f itself so no shell-side field splitting is needed — titles
    # may contain arbitrary characters (backticks, pipes, quotes) and jq's
    # -R/-s raw-slurp handles the JSON-string-escaping, never a hand-rolled
    # one.
    run_capture jq -R -s '
      split("\n")
      | map(select(length > 0))
      | map(split("\u001f"))
      | map(select(length >= 5))
      | map({
          id: .[0],
          title: (.[4:] | join("\u001f")),
          phase: (if .[2] == "" then null else (.[2] | tonumber) end),
          phase_name: (if .[3] == "" then null else .[3] end),
          state: .[1]
        })
    ' <<<"$raw_units"
    if [[ $RUN_RC -ne 0 ]]; then
      errors+=("failed to normalize plan-tracker parse output: $(printf '%s' "$RUN_ERR" | head -c 300)")
      emit_and_exit 1
    fi
    units_json="$RUN_OUT"

    total_units=$(jq 'length' <<<"$units_json")
    if [[ "$total_units" -eq 0 ]]; then
      findings+=("no plan units found — run /decompose (plan mode) to assign IDs")
    else
      unknown_count=$(jq '[.[] | select(.state=="unknown")] | length' <<<"$units_json")
      if [[ "$unknown_count" -gt 0 ]]; then
        findings+=("completion not recorded for ${unknown_count} units (add a Status column or checkboxes)")
      fi
    fi
  fi
fi

if [[ ${#errors[@]} -eq 0 ]]; then
  emit_and_exit 0
else
  emit_and_exit 1
fi
