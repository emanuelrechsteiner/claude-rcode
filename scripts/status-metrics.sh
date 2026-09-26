#!/usr/bin/env bash
# status-metrics.sh — deterministic GATHER half of the R.Code /status-sync
# command (Step 2: per-milestone completion percentage; Step 5: stale-issue
# detection).
# ─────────────────────────────────────────────────────────────────────────────
# WHY THIS EXISTS: see phase-gate-check.sh's header — same rationale. All
# figures here come from a script counting real state — never from a model
# eyeballing `gh`/file output (that is exactly the bug class that made all
# 12 historical daily-docs entries wrong; fixed 2026-07-18 by making a script
# count instead — see the memory index).
#
# TRACKER-AGNOSTIC (M14, 2026-09-23): a project's units live in GitHub issues
# (tracker "github") or in BRAINSTORM.md (tracker "plan", for projects with
# no issue tracker — a real project was measured at 0/28 commits
# referencing any unit, with no git remote at all). This script now calls
# `rcode-units.sh` (the ONE tracker-agnostic
# parser — see its header) to learn which tracker is active, and to source
# ALL plan-mode unit data — deliberately never re-implementing BRAINSTORM.md
# parsing here (rules/testing-quality.md "Verify via the same code path, not
# a reimplementation": two independently-written counters drift).
#
# github mode is DELIBERATELY left calling `gh issue list` directly here too
# (a second call, in addition to the one rcode-units.sh already made to
# resolve the tracker) rather than being derived from rcode-units.sh's
# minimal {id,title,phase,state} shape: this script's github-mode output
# must stay byte-compatible with existing consumers (milestones[].title is
# the exact `.milestone.title` string — e.g. "Phase 2: Core Systems", not
# the coarser phase-only int rcode-units.sh carries; stale_issues[] and
# issues_blocked need `updatedAt`/labels rcode-units.sh's schema omits by
# design). The extra `gh` call is the accepted cost of that compatibility
# guarantee — this is a periodic gather script, not a hot loop.
#
# plan mode has NO hard prerequisite beyond a readable project directory —
# this is the actual M14 fix: `gh`/git-remote/auth are no longer required
# unconditionally, only when the tracker resolves to "github".
#
# Usage:
#   status-metrics.sh [project-dir]
#   status-metrics.sh --help
#
# Env overrides:
#   CLAUDE_STALE_DAYS   default: 14 (status-sync.md: "more than 2 weeks")
#
# Exit codes:
#   0  ok:true  — gather succeeded
#   1  ok:false — a prerequisite was missing or a command could not be run
#   2  usage error (bad arguments) — JSON is still emitted
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# SELF_DIR (N0/N17 FIX, 2026-09-23): see phase-gate-check.sh's header
# comment for the full rationale — resolved as the FIRST executable
# statement, before any `cd "$PROJECT_DIR"` below, so a relative
# invocation of this script (relative to the CALLER's original cwd) still
# resolves rcode-units.sh correctly, even against a project directory that
# has no "scripts/" subdirectory of its own.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: status-metrics.sh [project-dir]
       status-metrics.sh --help

Gathers per-milestone completion percentages and stale-issue detection for
/status-sync's Step 2 + Step 5. Tracker-agnostic: resolves the active
tracker via rcode-units.sh. github mode additionally requires `gh` (binary +
authenticated) and a git repo with a resolvable GitHub remote; plan mode has
no such prerequisite.

Arguments:
  [project-dir]   Optional. Defaults to the current directory.

Env overrides:
  CLAUDE_STALE_DAYS   Days without update before an open issue counts as
                      stale. Default: 14. github mode only.

Output (stdout, JSON):
  {
    "ok": bool,
    "tracker": "github"|"plan"|null,
    "milestones": [{"title":string,"total":int,"closed":int|null,"percent":number|null}],
    "stale_issues": [{"number":int,"title":string,"updatedAt":string}],
    "counts": {
      "issues_total": int|null,
      "issues_open": int|null,   // N18 FIX (2026-09-23): null (not a
                                 // fabricated 0) when EVERY unit is
                                 // state=="unknown" — plan mode only
      "issues_closed": int|null, // same null-when-fully-unknown rule
      "issues_unknown": int|null, // plan mode only: units with no
                                 // determinable state; numeric open/
                                 // closed above still cover the KNOWN
                                 // units when this is a PARTIAL count
                                 // (>0 but < issues_total); always null
                                 // in github mode (a GitHub issue's
                                 // state is always OPEN/CLOSED)
      "issues_no_milestone": int|null,
      "issues_blocked": int|null,
      "milestones_total": int|null
    },
    "findings": [string],
    "errors":   [string]
  }

github mode: milestones[].title is the exact GitHub milestone title (e.g.
"Phase 2: Core Systems"); milestones with ZERO issues are invisible (gh
issue list only returns milestones that have >=1 issue attached) — a
deliberate single-API-call design, not an oversight. issues_blocked counts
the "blocked" label.

plan mode: milestones[].title is "Phase N — <Name>" when the phase's
`### Phase N — <Name>` heading carries a name (K-B, 2026-09-23 — the name
comes from rcode-units.sh's `phase_name` field, the first unit in the
group's value, never re-derived here — same-code-path discipline), else
the bare "Phase N"; closed/percent are null for any phase where completion
could not be determined (no Status/State column in that phase's table —
see rcode-units.sh). stale_issues is always [] (no updatedAt data exists in
a markdown file) and a finding names the gap. issues_blocked is null
(plan-tracker "blocked-by:" tags are dependency markers, not the same
concept as the github "blocked" label — not counted here). N18 FIX
(2026-09-23): counts.issues_open/issues_closed are computed by an EXACT
state match ("open"/"closed") and, before this fix, silently came back 0
(never null) whenever every project unit had state=="unknown" — a
technically-true-but-misleading 0 ("0 happen to match state==closed", not
"0 are actually done"), which status-sync.md's Ship-vs-Consolidate
strategic-posture logic could have derived a fabricated completion % from
(rules/fail-loud.md: never a fabricated 0 standing in for "not measured").
counts.issues_unknown (new field) reports how many units have no
determinable state; when issues_unknown equals issues_total (EVERY unit is
unknown), issues_open/issues_closed are null instead of 0. When the count
is PARTIAL (some units known, some not), issues_open/issues_closed stay
numeric and cover only the units with a known state, issues_unknown is
>0, and a finding names the gap.

Exit codes:
  0  ok:true   (gather succeeded)
  1  ok:false  (a prerequisite was missing or a command failed — see errors[])
  2  usage error (bad arguments) — JSON is still emitted on stdout
EOF
}

json_array() { jq -n --args '$ARGS.positional' -- "$@"; }

# run_capture — see phase-gate-check.sh for full rationale.
run_capture() {
  local out_f err_f rc
  out_f=$(mktemp "${TMPDIR:-/tmp}/sm-out.XXXXXX")
  err_f=$(mktemp "${TMPDIR:-/tmp}/sm-err.XXXXXX")
  set +e
  "$@" >"$out_f" 2>"$err_f"
  rc=$?
  set -e
  RUN_OUT="$(cat "$out_f")"
  RUN_ERR="$(cat "$err_f")"
  RUN_RC=$rc
  rm -f "$out_f" "$err_f"
}

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
    --argjson milestones "${milestones_json:-[]}" \
    --argjson stale_issues "${stale_issues_json:-[]}" \
    --argjson counts "${counts_json:-null}" \
    --argjson findings "$(json_array "${findings[@]+"${findings[@]}"}")" \
    --argjson errors "$(json_array "${errors[@]+"${errors[@]}"}")" \
    '{ok:$ok, tracker: (if $has_tracker then $tracker else null end), milestones:$milestones, stale_issues:$stale_issues, counts:$counts, findings:$findings, errors:$errors}'
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
# Canonicalize once so every later reuse (cd, rcode-units.sh argument) is
# correct even when the caller passed a RELATIVE project dir (final-check fix).
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
cd "$PROJECT_DIR"

STALE_DAYS="${CLAUDE_STALE_DAYS:-14}"
if ! [[ "$STALE_DAYS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: CLAUDE_STALE_DAYS must be a positive integer, got: $STALE_DAYS" >&2
  errors+=("CLAUDE_STALE_DAYS must be a positive integer, got: $STALE_DAYS")
  emit_and_exit 2
fi

# ── Tracker resolution: delegate to the ONE parser (A3) ──────────────────
# rcode-units.sh always resolves + emits "tracker" before it enters any
# hard-fail branch, so its tracker field is safe to read even when its own
# run_capture $RUN_RC below is non-zero (e.g. a github-mode auth failure —
# that failure is re-surfaced naturally when THIS script makes its own gh
# calls a few lines down, for github mode's byte-compat reasons — see header).
RCU_SCRIPT="$SELF_DIR/rcode-units.sh"
HAS_TRACKER=false
if [[ ! -f "$RCU_SCRIPT" ]]; then
  errors+=("rcode-units.sh not found next to this script: $RCU_SCRIPT")
  emit_and_exit 1
fi
run_capture bash "$RCU_SCRIPT" "$PROJECT_DIR"
rcu_json="$RUN_OUT"
TRACKER=$(jq -r '.tracker // empty' <<<"$rcu_json" 2>/dev/null || true)
if [[ -z "$TRACKER" ]]; then
  errors+=("rcode-units.sh produced no usable tracker: $(printf '%s' "$RUN_ERR" | head -c 300)")
  emit_and_exit 1
fi
HAS_TRACKER=true

if [[ "$TRACKER" == "github" ]]; then

# ── Hard prerequisites: git repo + gh binary + gh auth ──────────────────
if ! command -v git >/dev/null 2>&1; then
  errors+=("git binary not found")
  emit_and_exit 1
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  errors+=("not a git repository: $PROJECT_DIR")
  emit_and_exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  errors+=("gh CLI not found — this script is entirely gh-issue-derived, there is no degraded mode")
  emit_and_exit 1
fi
run_capture gh auth status
if [[ $RUN_RC -ne 0 ]]; then
  errors+=("gh is not authenticated (gh auth status failed): $(printf '%s' "$RUN_ERR" | head -c 300)")
  emit_and_exit 1
fi

# ── Single source of truth: one gh issue list call ───────────────────────
run_capture gh issue list --state all --json number,title,state,milestone,labels,updatedAt --limit 500
if [[ $RUN_RC -ne 0 ]]; then
  errors+=("gh issue list failed: $(printf '%s' "$RUN_ERR" | head -c 300)")
  emit_and_exit 1
fi
issues_json="$RUN_OUT"

issue_count=$(jq 'length' <<<"$issues_json")
if [[ "$issue_count" -eq 500 ]]; then
  findings+=("issue count hit the 500-item fetch limit — results may be truncated; increase --limit if this repo has more than 500 issues")
fi

# `read -d ''` always returns 1 at EOF even on a fully-successful heredoc
# capture (well-documented bash quirk, not a real failure) — the `|| true`
# here masks ONLY that specific known-benign EOF status, never a broken
# filter: an empty/malformed JQ_FILTER still fails loudly below, at the
# `run_capture jq ...` call whose $RUN_RC is checked explicitly.
read -r -d '' JQ_FILTER <<'JQEOF' || true
{
  milestones: (
    [ .[] | select(.milestone != null) ]
    | group_by(.milestone.title)
    | map({
        title: .[0].milestone.title,
        total: length,
        closed: ([.[] | select(.state=="CLOSED")] | length)
      })
    | map(. + {percent: (if .total > 0 then ((.closed / .total * 100) | round) else null end)})
    | sort_by(.title)
  ),
  stale_issues: (
    [ .[]
      | select(.state=="OPEN")
      | select( (now - (.updatedAt | fromdateiso8601)) > ($stale_days * 86400) )
      | {number, title, updatedAt}
    ]
  ),
  counts: {
    issues_total: length,
    issues_open: ([.[] | select(.state=="OPEN")] | length),
    issues_closed: ([.[] | select(.state=="CLOSED")] | length),
    issues_no_milestone: ([.[] | select(.milestone==null)] | length),
    issues_blocked: ([.[] | select((.labels // []) | map(.name) | index("blocked") != null)] | length),
    milestones_total: ([.[] | select(.milestone != null) | .milestone.title] | unique | length)
  }
}
JQEOF

run_capture jq --argjson stale_days "$STALE_DAYS" "$JQ_FILTER" <<<"$issues_json"
if [[ $RUN_RC -ne 0 ]]; then
  errors+=("failed to compute milestone/stale-issue metrics: $(printf '%s' "$RUN_ERR" | head -c 300)")
  emit_and_exit 1
fi
result_json="$RUN_OUT"

milestones_json=$(jq '.milestones' <<<"$result_json")
stale_issues_json=$(jq '.stale_issues' <<<"$result_json")
counts_json=$(jq '.counts' <<<"$result_json")

no_milestone_count=$(jq '.issues_no_milestone' <<<"$counts_json")
[[ "$no_milestone_count" -gt 0 ]] && findings+=("${no_milestone_count} issue(s) have no milestone assigned")

stale_count=$(jq 'length' <<<"$stale_issues_json")
[[ "$stale_count" -gt 0 ]] && findings+=("${stale_count} issue(s) are stale (open >${STALE_DAYS}d without update)")

blocked_count=$(jq '.issues_blocked' <<<"$counts_json")
[[ "$blocked_count" -gt 0 ]] && findings+=("${blocked_count} issue(s) carry the 'blocked' label")

else
  # ── plan mode: no hard prerequisite — this is the M14 fix. Every field
  # below is sourced from rcode-units.sh's units[] alone (A3's "same code
  # path" — status-metrics.sh never re-parses BRAINSTORM.md itself). ──────
  if [[ $RUN_RC -ne 0 ]]; then
    rcu_errors_json=$(jq '.errors // []' <<<"$rcu_json" 2>/dev/null || echo '[]')
    while IFS= read -r e; do
      [[ -n "$e" ]] && errors+=("rcode-units.sh: ${e}")
    done < <(jq -r '.[]' <<<"$rcu_errors_json" 2>/dev/null || true)
    [[ ${#errors[@]} -eq 0 ]] && errors+=("rcode-units.sh failed with no reported errors[]")
    emit_and_exit 1
  fi

  rcu_findings_json=$(jq '.findings // []' <<<"$rcu_json" 2>/dev/null || echo '[]')
  while IFS= read -r f; do
    [[ -n "$f" ]] && findings+=("$f")
  done < <(jq -r '.[]' <<<"$rcu_findings_json" 2>/dev/null || true)

  units_json=$(jq '.units // []' <<<"$rcu_json")

  read -r -d '' PLAN_JQ_FILTER <<'JQEOF' || true
{
  milestones: (
    [ .[] | select(.phase != null) ]
    | group_by(.phase)
    | map({
        title: (
          (.[0].phase_name // "") as $name
          | if ($name | length) > 0
            then ("Phase " + (.[0].phase|tostring) + " — " + $name)
            else ("Phase " + (.[0].phase|tostring))
            end
        ),
        total: length,
        has_unknown: (any(.[]; .state == "unknown")),
        closed: ([.[] | select(.state=="closed")] | length)
      })
    | map(. + {
        closed: (if .has_unknown then null else .closed end),
        percent: (if .has_unknown or .total == 0 then null else ((.closed / .total * 100) | round) end)
      })
    | map(del(.has_unknown))
    | sort_by(.title)
  ),
  counts: (
    (length) as $total
    | ([.[] | select(.state=="unknown")] | length) as $unknown
    | ([.[] | select(.state=="open")] | length) as $open
    | ([.[] | select(.state=="closed")] | length) as $closed
    # N18 FIX (2026-09-23): when EVERY unit is state=="unknown", $open/
    # $closed are null instead of a technically-correct-but-misleading 0
    # (rules/fail-loud.md — see the header comment above). A PARTIAL
    # unknown count keeps the numeric open/closed for the KNOWN units
    # unchanged (select() already excludes "unknown" units from both).
    | {
        issues_total: $total,
        issues_open: (if $total > 0 and $unknown == $total then null else $open end),
        issues_closed: (if $total > 0 and $unknown == $total then null else $closed end),
        issues_unknown: $unknown,
        issues_no_milestone: ([.[] | select(.phase==null)] | length),
        issues_blocked: null,
        milestones_total: ([.[] | select(.phase != null) | .phase] | unique | length)
      }
  )
}
JQEOF

  run_capture jq "$PLAN_JQ_FILTER" <<<"$units_json"
  if [[ $RUN_RC -ne 0 ]]; then
    errors+=("failed to compute plan-mode milestone metrics: $(printf '%s' "$RUN_ERR" | head -c 300)")
    emit_and_exit 1
  fi
  result_json="$RUN_OUT"

  milestones_json=$(jq '.milestones' <<<"$result_json")
  stale_issues_json='[]'
  counts_json=$(jq '.counts' <<<"$result_json")

  findings+=("stale-issue detection unavailable in plan mode — BRAINSTORM.md carries no updatedAt timestamp")

  no_milestone_count=$(jq '.issues_no_milestone' <<<"$counts_json")
  [[ "$no_milestone_count" -gt 0 ]] && findings+=("${no_milestone_count} unit(s) have no phase assigned")

  # N18 FIX (2026-09-23): name the issues_unknown gap explicitly — see the
  # header comment and the PLAN_JQ_FILTER comment above for the full
  # rationale (never a fabricated 0 standing in for "not measured").
  unknown_count=$(jq '.issues_unknown' <<<"$counts_json")
  if [[ "$unknown_count" -gt 0 ]]; then
    total_count=$(jq '.issues_total' <<<"$counts_json")
    if [[ "$unknown_count" -eq "$total_count" ]]; then
      findings+=("completion not recorded for any of the ${total_count} unit(s) — counts.issues_open/issues_closed are null (not a fabricated 0)")
    else
      findings+=("completion not recorded for ${unknown_count} of ${total_count} unit(s) — counts.issues_open/issues_closed cover only the units with a known state")
    fi
  fi
fi

if [[ ${#errors[@]} -eq 0 ]]; then
  emit_and_exit 0
else
  emit_and_exit 1
fi
