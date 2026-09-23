#!/usr/bin/env bash
# phase-gate-check.sh — deterministic GATHER half of the R.Code /phase-gate
# command's Steps 1-2 (issue/milestone closure + tsc/eslint/test/build facts).
# ─────────────────────────────────────────────────────────────────────────────
# WHY THIS EXISTS (read before editing):
#   /phase-gate runs on a frontier model. Its boundary work splits into a
#   GATHER half (deterministic file/git/gh state) and a DECIDE half (judgment
#   — is a caveat acceptable, is this WARN or does it block). The gather half
#   must NOT be model-estimated: the daily-docs routine had an agent COUNT git
#   activity and all 12 historical entries were wrong (fixed 2026-07-18 by
#   making a script count instead). This script is that fix, applied here.
#
#   The equal-and-opposite failure mode: weekly-improve had its data paths
#   pointing at nonexistent files and ran blind for weeks, producing output
#   that LOOKED normal. A silently-wrong script is worse than a wrong model
#   output — it fails identically, every run, forever, until an audit catches
#   it. So every gather step below either (a) determines a real number, or
#   (b) explicitly says "could not determine" (null + errors[]/findings[]) —
#   NEVER a fabricated 0 standing in for "I didn't check" (see rules/fail-loud.md).
#
#   The verdict this script emits is a DETERMINISTIC fact-check ONLY — hard
#   pass/fail facts (open issues, compiler/lint/test failures). Judgment calls
#   ("is 78% coverage acceptable", "is this tech debt OK to defer") are
#   explicitly NOT this script's job; the lead (a frontier model) decides that
#   from the facts this script hands it.
#
#   TRACKER-AGNOSTIC (M14, A3, 2026-09-23): Step 1 (issue/milestone closure)
#   now resolves its tracker via `rcode-units.sh` (the ONE unit parser).
#   github mode's Step 1 body for an UNAMBIGUOUS milestone match (exactly
#   one milestone titled "Phase N") is UNCHANGED — same milestone-title
#   lookup, same `gh` calls, byte-compatible output. plan mode filters
#   rcode-units.sh's units[] by the requested Phase number, and requires
#   neither git remote nor `gh` (the actual M14 fix).
#
#   C15 FIX (2026-09-23): a github-mode project with ZERO GitHub milestones
#   at all (every issue's `.milestone` is null — a real, measured case, not
#   hypothetical) used to hard-error unconditionally ("no milestone found").
#   Before that, this script now falls back to counting issues carrying the
#   `phase-N` label instead, reusing rcode-units.sh's ALREADY-fetched
#   units[] — the SAME phase-extraction code path github mode already uses
#   for an issue without a milestone (see rcode-units.sh's JQ_FILTER; no
#   second re-implementation). Only when that fallback ALSO finds zero
#   units for the phase does this become a clear, named finding ("issues
#   are on GitHub but were never organized into Phase milestones or
#   phase-N labels") instead of an opaque per-invocation error.
#
#   C16 FIX (2026-09-23): Step 2 (tsc/eslint/test/build) used to look only
#   at $PROJECT_DIR's own package.json — a real monorepo (package.json in
#   an immediate subdirectory, e.g. web/, with no package.json at the
#   root) was silently reported as "not an npm project" and quality-
#   checked NOTHING. Step 2 now probes exactly ONE level of subdirectories
#   for a package.json and runs the SAME checks per directory, summing
#   counts and prefixing findings with the directory; when neither the
#   root nor any immediate subdirectory has a package.json, it also checks
#   for a recognizable non-npm manifest (pyproject.toml/Cargo.toml/go.mod/
#   Package.swift) and names the actual stack in the finding — verdict
#   stays WARN (never a fabricated PASS) either way, per the DECIDE-half
#   contract: this script hands the lead facts, the lead runs the project's
#   own CLAUDE.md "Mandatory Pre-Commit" trio for a non-npm stack.
#
# Usage:
#   phase-gate-check.sh <phase-number> [project-dir]
#   phase-gate-check.sh --help
#
# Output: single JSON object on stdout (see usage() below for the exact
# shape). Human-readable progress notes go to stderr only.
#
# Exit codes:
#   0  ok:true  — gather succeeded (verdict may still be WARN or BLOCK)
#   1  ok:false — a prerequisite was missing or a command could not be run
#   2  usage error (bad/missing CLI arguments) — JSON is still emitted
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# SELF_DIR (N0/N17 FIX, 2026-09-23): resolved as the FIRST executable
# statement, before any argument parsing or `cd "$PROJECT_DIR"` below. A
# caller may invoke this script with a path RELATIVE to their own cwd
# (e.g. `bash scripts/phase-gate-check.sh 1 <dir>` from a repo root — this
# script's own usage() text implies exactly that form is fine). If
# BASH_SOURCE[0]'s directory were resolved AFTER `cd "$PROJECT_DIR"`
# instead, `dirname "${BASH_SOURCE[0]}"` would be interpreted relative to
# the NEW cwd (the target project directory) rather than the caller's
# original cwd — and when that project directory has no "scripts/"
# subdirectory of its own (the common case), the inner `cd` fails and,
# under `set -euo pipefail`, aborts the WHOLE SCRIPT with a bare shell
# error instead of the documented always-JSON contract. Resolving here,
# before any `cd`, makes SELF_DIR correct regardless of what the script
# does with its cwd afterward, and regardless of whether the caller passed
# a relative or absolute path to this script itself.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCRIPT_NAME="phase-gate-check.sh"

usage() {
  cat <<'EOF'
Usage: phase-gate-check.sh <phase-number> [project-dir]
       phase-gate-check.sh --help

Gathers the deterministic facts /phase-gate needs (issue/milestone closure —
tracker-agnostic, via rcode-units.sh — and tsc/eslint/test/build results via
`npm`/`npx`) and emits them as a single JSON object on stdout. Does NOT judge
subjective WARN-vs-PASS nuance — it emits hard facts and lets the calling
command's frontier-model lead decide.

Arguments:
  <phase-number>   Required. Positive integer. github mode: matched against
                    milestone titles as /^phase <N>(\D|$)/i (so "1" won't
                    match "10"); when NO milestone matches, falls back to
                    counting issues carrying the "phase-<N>" label instead
                    (C15, 2026-09-23 — see header comment). plan mode:
                    matched against each unit's parsed phase number (see
                    rcode-units.sh).
  [project-dir]     Optional. Defaults to the current directory.

Environment:
  PHASE_GATE_TIMEOUT_SECS   Optional. Bounds each external command (tsc,
                             eslint, jest/vitest, npm run build) to this many
                             seconds. Default: 300. Uses GNU `timeout` if on
                             PATH, else macOS `gtimeout` (coreutils via
                             Homebrew — NOT installed by default on macOS).
                             If neither is found, commands run unbounded and
                             a WARN-worthy finding is emitted once.

Output (stdout, JSON):
  {
    "ok": bool,                 // true iff the GATHER itself succeeded
    "tracker": "github"|"plan"|null,
    "verdict": "PASS"|"WARN"|"BLOCK",
    "counts": {
      "issues_total":   int|null,
      "issues_closed":  int|null,  // N18 FIX (2026-09-23): null (not a
                                 // fabricated 0) when EVERY unit in the
                                 // requested Phase has state "unknown" —
                                 // plan mode only, see issues_unknown
                                 // below; github mode unaffected (a
                                 // GitHub issue's state is always
                                 // OPEN/CLOSED, never "unknown")
      "issues_unknown": int|null,  // plan mode only: units with no
                                 // determinable state (no Status/State
                                 // column in that unit's table — see
                                 // rcode-units.sh); always null in
                                 // github mode
      "tsc_errors":     int|null,
      "lint_errors":    int|null,  // ESLint errorCount ONLY (blocking)
      "lint_warnings":  int|null,  // ESLint warningCount ONLY (non-blocking)
      "tests_passed":   int|null,
      "tests_failed":   int|null
    },
    "findings": [string],       // WARN-worthy notes ONLY: skipped checks,
                                 // ambiguity, truncation, non-blocking lint
                                 // warnings, missing timeout binary. Purely
                                 // informational success notes (e.g. a clean
                                 // build) are NEVER pushed here — they would
                                 // force verdict:WARN on an all-green project
                                 // (see verdict semantics below). Those go to
                                 // stderr only, per this script's own
                                 // "human-readable progress notes go to
                                 // stderr" convention.
    "errors":   [string]        // fatal gather failures — see errors[] for why
  }

verdict semantics (computed from hard facts only):
  BLOCK — an objective failure was found (open issues remain, tsc errors > 0,
          lint ERRORS > 0 — lint WARNINGS alone do not block, failing tests,
          or a failed build)
  WARN  — no hard failures, but something could not be fully verified, or a
          non-blocking issue was found (skipped check, missing tool,
          ambiguous/missing milestone match, ESLint warnings present with 0
          errors, no bounded-timeout binary found for external commands)
  PASS  — every check ran, came back clean, and nothing was skipped or
          flagged — a fully clean project CAN and MUST reach this verdict

Exit codes:
  0  ok:true   (gather succeeded; verdict may still be WARN or BLOCK)
  1  ok:false  (a prerequisite was missing or a command failed — see errors[])
  2  usage error (bad/missing arguments) — JSON is still emitted on stdout
EOF
}

# ── Helpers (bash-3.2-safe: macOS /usr/bin/env bash resolves to 3.2.57,
#    which throws "unbound variable" under `set -u` on `${arr[@]}` for a
#    truly EMPTY array — the `${arr[@]+"${arr[@]}"}` guard below is the
#    portable workaround; `$@` inside a function is exempt from this bug) ──
json_array() { jq -n --args '$ARGS.positional' -- "$@"; }

# run_capture CMD... — runs a command with stdout/stderr captured to separate
# temp files (NOT merged — merging can corrupt JSON-producing commands like
# `eslint --format json`), without letting `set -e` abort the script. Every
# call site MUST inspect $RUN_RC explicitly; this function never swallows it.
run_capture() {
  local out_f err_f rc
  out_f=$(mktemp "${TMPDIR:-/tmp}/pgc-out.XXXXXX")
  err_f=$(mktemp "${TMPDIR:-/tmp}/pgc-err.XXXXXX")
  set +e
  "$@" >"$out_f" 2>"$err_f"
  rc=$?
  set -e
  RUN_OUT="$(cat "$out_f")"
  RUN_ERR="$(cat "$err_f")"
  RUN_RC=$rc
  rm -f "$out_f" "$err_f"
}

# count_matches PATTERN — counts ERE matches on stdin. grep rc=1 ("no match")
# is a VALID zero-count here, not an error (fail-loud.md Allowed Patterns #2:
# a genuinely optional/zero-is-valid outcome). grep rc>=2 (bad pattern, read
# error) is a real failure and is surfaced via $COUNT_RC for the caller.
count_matches() {
  local pattern="$1" n rc
  set +e
  n=$(grep -c -E "$pattern")
  rc=$?
  set -e
  COUNT_RC=$rc
  if [[ $rc -ge 2 ]]; then echo 0; else echo "$n"; fi
}

findings=()
errors=()
HARD_FAIL=false
warn_count=0

# add_finding NOTE — pushes a WARN-worthy finding: something could not be
# fully verified (skipped check, missing tool, ambiguity, truncation,
# non-blocking lint warnings, no timeout binary). This is the verdict-
# relevant path — WARN fires when warn_count > 0. Use this for anything that
# means "not a hard failure, but not a clean/complete verification either."
add_finding() {
  findings+=("$1")
  warn_count=$((warn_count + 1))
}

# add_info_note NOTE — pushes a purely informational, already-fully-verified
# success note that must NOT affect the verdict. BLOCKER 1 FIX: the prior
# version pushed "npm run build: PASS" straight into findings[] via
# findings+=(), which made emit_and_exit's `${#findings[@]} -gt 0` check force
# verdict:WARN even on a fully clean, all-green gather. Never use this for
# anything skipped/ambiguous/unverified — only for "this ran, and it was
# clean" — and never for anything that should move the verdict.
add_info_note() {
  findings+=("$1")
}

# Bounded-timeout detection for external commands (tsc/eslint/test/build).
# GNU `timeout` is NOT present by default on macOS; `gtimeout` (coreutils via
# Homebrew) is the macOS equivalent. If neither is on PATH, commands run
# unbounded — degrade gracefully with a one-time WARN-worthy finding rather
# than silently emitting a command that doesn't exist on the default macOS
# toolchain (fail-loud.md: no silent "it just didn't run" gap).
TIMEOUT_SECS="${PHASE_GATE_TIMEOUT_SECS:-300}"
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi
NO_TIMEOUT_WARNED=false

# run_capture_timeout CMD... — same contract as run_capture, but bounds CMD
# with the detected timeout binary (if any) so a hung tsc/eslint/test/build
# invocation cannot hang the gate indefinitely.
run_capture_timeout() {
  if [[ -n "$TIMEOUT_BIN" ]]; then
    run_capture "$TIMEOUT_BIN" "$TIMEOUT_SECS" "$@"
  else
    if [[ "$NO_TIMEOUT_WARNED" == "false" ]]; then
      add_finding "no 'timeout' or 'gtimeout' binary found on PATH — external commands (tsc/eslint/test/build) are running WITHOUT a bounded timeout; install GNU coreutils for gtimeout support on macOS"
      NO_TIMEOUT_WARNED=true
    fi
    run_capture "$@"
  fi
}

emit_and_exit() {
  local exit_code="$1"
  local ok_bool="false"
  [[ ${#errors[@]} -eq 0 ]] && ok_bool="true"

  local verdict="PASS"
  if [[ "$HARD_FAIL" == "true" ]]; then
    verdict="BLOCK"
  elif [[ $warn_count -gt 0 || ${#errors[@]} -gt 0 ]]; then
    verdict="WARN"
  fi

  local counts_json
  counts_json=$(jq -n \
    --argjson issues_total "${issues_total:-null}" \
    --argjson issues_closed "${issues_closed:-null}" \
    --argjson issues_unknown "${issues_unknown:-null}" \
    --argjson tsc_errors "${tsc_errors:-null}" \
    --argjson lint_errors "${lint_errors:-null}" \
    --argjson lint_warnings "${lint_warnings:-null}" \
    --argjson tests_passed "${tests_passed:-null}" \
    --argjson tests_failed "${tests_failed:-null}" \
    '{issues_total:$issues_total, issues_closed:$issues_closed, issues_unknown:$issues_unknown, tsc_errors:$tsc_errors, lint_errors:$lint_errors, lint_warnings:$lint_warnings, tests_passed:$tests_passed, tests_failed:$tests_failed}')

  jq -n \
    --argjson ok "$ok_bool" \
    --arg tracker "${TRACKER:-}" \
    --argjson has_tracker "${HAS_TRACKER:-false}" \
    --arg verdict "$verdict" \
    --argjson counts "$counts_json" \
    --argjson findings "$(json_array "${findings[@]+"${findings[@]}"}")" \
    --argjson errors "$(json_array "${errors[@]+"${errors[@]}"}")" \
    '{ok:$ok, tracker: (if $has_tracker then $tracker else null end), verdict:$verdict, counts:$counts, findings:$findings, errors:$errors}'
  exit "$exit_code"
}

# ── Argument parsing ─────────────────────────────────────────────────────
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

PHASE_NUM="${1:-}"
if [[ -z "$PHASE_NUM" ]]; then
  echo "ERROR: missing required <phase-number> argument" >&2
  usage >&2
  errors+=("missing required <phase-number> argument")
  emit_and_exit 2
fi
if ! [[ "$PHASE_NUM" =~ ^[0-9]+$ ]]; then
  echo "ERROR: <phase-number> must be a positive integer, got: $PHASE_NUM" >&2
  errors+=("<phase-number> must be a positive integer, got: $PHASE_NUM")
  emit_and_exit 2
fi

PROJECT_DIR="${2:-$(pwd)}"
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: project directory does not exist: $PROJECT_DIR" >&2
  errors+=("project directory does not exist: $PROJECT_DIR")
  emit_and_exit 2
fi
# Canonicalize once so every later reuse (cd, rcode-units.sh argument) is
# correct even when the caller passed a RELATIVE project dir (final-check fix).
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
cd "$PROJECT_DIR"

# ── Tracker resolution: delegate to the ONE parser (A3) ──────────────────
# Same pattern as status-metrics.sh — see that script's header for the full
# rationale on why github mode still makes its own `gh` calls below (byte
# compatibility: the milestone-title ambiguity check has no equivalent in
# rcode-units.sh's phase-int-only schema) while plan mode is sourced
# entirely from rcode-units.sh's units[].
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

# ── Step 1: issue/milestone verification ────────────────────────────────
issues_total="null"
issues_closed="null"
issues_unknown="null"

if [[ "$TRACKER" == "github" ]]; then

if ! command -v git >/dev/null 2>&1; then
  errors+=("git binary not found")
elif ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  errors+=("not a git repository: $PROJECT_DIR")
elif ! command -v gh >/dev/null 2>&1; then
  errors+=("gh CLI not found — cannot verify issue/milestone completion")
else
  run_capture gh auth status
  if [[ $RUN_RC -ne 0 ]]; then
    errors+=("gh is not authenticated (gh auth status failed) — cannot query issues")
  else
    # NOTE: query params go in the URL, NOT via -f/--field — gh api silently
    # switches the HTTP method to POST when any -f is given without an
    # explicit -X, which 404s a list endpoint like this one (verified
    # empirically while testing this script against a real repo).
    run_capture gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --paginate
    if [[ $RUN_RC -ne 0 ]]; then
      errors+=("gh api milestones call failed: $(printf '%s' "$RUN_ERR" | head -c 300)")
    else
      run_capture jq -r --arg n "$PHASE_NUM" \
        '[.[] | select(.title | test("^phase\\s+" + $n + "(\\D|$)"; "i")) | .title] | .[]' \
        <<<"$RUN_OUT"
      if [[ $RUN_RC -ne 0 ]]; then
        errors+=("failed to parse milestones JSON: $(printf '%s' "$RUN_ERR" | head -c 300)")
      else
        matched_titles="$RUN_OUT"
        titles_joined=""
        match_count=0
        while IFS= read -r t; do
          [[ -z "$t" ]] && continue
          match_count=$((match_count + 1))
          if [[ -z "$titles_joined" ]]; then titles_joined="$t"; else titles_joined="${titles_joined}; ${t}"; fi
        done <<<"$matched_titles"

        if [[ "$match_count" -eq 0 ]]; then
          # C15 fix: no GitHub milestone matched "Phase N" — before treating
          # this as a hard failure, fall back to counting issues carrying
          # the `phase-N` label via rcode-units.sh's ALREADY-fetched
          # units[] (rcu_json, fetched at tracker-resolution time above) —
          # the SAME phase-extraction code path github mode already uses
          # when an issue has no milestone (rcode-units.sh's JQ_FILTER;
          # never a second, independently-written phase resolver here).
          rcu_ok=$(jq -r '.ok // false' <<<"$rcu_json" 2>/dev/null || echo false)
          if [[ "$rcu_ok" != "true" ]]; then
            errors+=("no milestone found matching 'Phase ${PHASE_NUM}', and the phase-N-label fallback is unavailable (rcode-units.sh did not complete successfully) — cannot verify issue completion")
          else
            run_capture jq --arg n "$PHASE_NUM" '
              [.units[] | select((.phase|tostring) == $n)]
              | {total: length, closed: ([.[] | select(.state=="closed")] | length)}
            ' <<<"$rcu_json"
            if [[ $RUN_RC -ne 0 ]]; then
              errors+=("no milestone found matching 'Phase ${PHASE_NUM}', and the phase-N-label fallback failed to parse: $(printf '%s' "$RUN_ERR" | head -c 300)")
            else
              label_total=$(jq -r '.total' <<<"$RUN_OUT")
              label_closed=$(jq -r '.closed' <<<"$RUN_OUT")
              if [[ "$label_total" -eq 0 ]]; then
                errors+=("this project's issues are on GitHub but were never organized into Phase milestones or phase-${PHASE_NUM} labels — /phase-gate cannot verify closure until they are")
              else
                issues_total="$label_total"
                issues_closed="$label_closed"
                add_finding "no GitHub milestone matched 'Phase ${PHASE_NUM}' — counted via the 'phase-${PHASE_NUM}' label instead (source: rcode-units.sh)"
                if [[ "$issues_total" -ne "$issues_closed" ]]; then
                  HARD_FAIL=true
                fi
              fi
            fi
          fi
        elif [[ "$match_count" -gt 1 ]]; then
          errors+=("ambiguous: ${match_count} milestones match 'Phase ${PHASE_NUM}': ${titles_joined} — cannot determine which to use")
        else
          milestone_title="$titles_joined"
          run_capture gh issue list --milestone "$milestone_title" --state all --json number,state --limit 500
          if [[ $RUN_RC -ne 0 ]]; then
            errors+=("gh issue list failed for milestone '${milestone_title}': $(printf '%s' "$RUN_ERR" | head -c 300)")
          else
            # SHOULD-FIX 5: previously two bare $(jq ...) command
            # substitutions with NO exit-code check. Worse than "flows into
            # arithmetic as a wrong value": under `set -euo pipefail`, a
            # bare `var=$(jq ...)` assignment whose jq call fails on
            # malformed JSON aborts the WHOLE SCRIPT right there (verified
            # empirically) — no JSON is ever emitted on stdout, breaking the
            # documented "always emits one JSON object" contract. Routing
            # through run_capture (which internally does `set +e`) is what
            # keeps the failure local and reportable via errors[].
            run_capture jq -r '[length, ([.[] | select(.state=="CLOSED")] | length)] | @tsv' <<<"$RUN_OUT"
            if [[ $RUN_RC -ne 0 || -z "$RUN_OUT" ]]; then
              errors+=("failed to parse gh issue list JSON for milestone '${milestone_title}': $(printf '%s' "$RUN_ERR" | head -c 300)")
            else
              IFS=$'\t' read -r issues_total issues_closed <<<"$RUN_OUT"
              if [[ "$issues_total" -eq 500 ]]; then
                add_finding "issue count for milestone '${milestone_title}' hit the 500-item fetch limit — results may be truncated"
              fi
              if [[ "$issues_total" -ne "$issues_closed" ]]; then
                HARD_FAIL=true
              fi
            fi
          fi
        fi
      fi
    fi
  fi
fi

else
  # ── plan mode: no gh/git prerequisite — this is the M14 fix. Every unit
  # fact below is sourced from rcode-units.sh's units[] alone (A3's "same
  # code path" — phase-gate-check.sh never re-parses BRAINSTORM.md itself),
  # filtered to the requested Phase number. ────────────────────────────────
  if [[ $RUN_RC -ne 0 ]]; then
    rcu_errors_json=$(jq '.errors // []' <<<"$rcu_json" 2>/dev/null || echo '[]')
    while IFS= read -r e; do
      [[ -n "$e" ]] && errors+=("rcode-units.sh: ${e}")
    done < <(jq -r '.[]' <<<"$rcu_errors_json" 2>/dev/null || true)
    [[ ${#errors[@]} -eq 0 ]] && errors+=("rcode-units.sh failed with no reported errors[]")
  else
    rcu_findings_json=$(jq '.findings // []' <<<"$rcu_json" 2>/dev/null || echo '[]')
    while IFS= read -r f; do
      [[ -n "$f" ]] && findings+=("$f")
    done < <(jq -r '.[]' <<<"$rcu_findings_json" 2>/dev/null || true)

    run_capture jq --arg n "$PHASE_NUM" '
      [.units[] | select((.phase|tostring) == $n)]
      | {
          total: length,
          closed: ([.[] | select(.state=="closed")] | length),
          open: ([.[] | select(.state=="open")] | length),
          unknown: ([.[] | select(.state=="unknown")] | length)
        }
    ' <<<"$rcu_json"
    if [[ $RUN_RC -ne 0 ]]; then
      errors+=("failed to filter units for Phase ${PHASE_NUM}: $(printf '%s' "$RUN_ERR" | head -c 300)")
    else
      phase_total=$(jq -r '.total' <<<"$RUN_OUT")
      phase_closed=$(jq -r '.closed' <<<"$RUN_OUT")
      phase_open=$(jq -r '.open' <<<"$RUN_OUT")
      phase_unknown=$(jq -r '.unknown' <<<"$RUN_OUT")

      if [[ "$phase_total" -eq 0 ]]; then
        errors+=("no plan units found for Phase ${PHASE_NUM} — cannot verify issue completion")
      else
        issues_total="$phase_total"
        if [[ "$phase_unknown" -gt 0 ]]; then
          issues_unknown="$phase_unknown"
          if [[ "$phase_unknown" -eq "$phase_total" ]]; then
            # N18 FIX (2026-09-23): every unit in this phase is "unknown"
            # (no Status/State column at all) — issues_closed would
            # otherwise report a technically-correct-but-misleading 0 (0
            # units happen to carry state=="closed", which reads as "0 are
            # done" rather than "completion was never recorded"). null it
            # instead, matching status-metrics.sh's analogous fix — never
            # a fabricated 0 standing in for "not measured"
            # (rules/fail-loud.md).
            issues_closed="null"
          else
            issues_closed="$phase_closed"
          fi
          add_finding "completion not recorded for ${phase_unknown} unit(s) in Phase ${PHASE_NUM} — cannot fully verify closure"
        else
          issues_closed="$phase_closed"
        fi
        if [[ "$phase_open" -gt 0 ]]; then
          HARD_FAIL=true
        fi
      fi
    fi
  fi
fi

# ── Step 2: quality verification (tsc / eslint / test / build) ─────────
tsc_errors="null"
lint_errors="null"
lint_warnings="null"
tests_passed="null"
tests_failed="null"

# quality_check_dir DIR — runs the tsc/eslint/test/build checks against
# $PROJECT_DIR/DIR and prints ONE JSON object describing what it found.
# C16 fix (2026-09-23): runs in a subshell (parens) so a per-dir `cd` can
# never leak into the next dir's checks or the caller's shell state;
# findings/errors/info are collected into LOCAL arrays and returned via the
# JSON object instead of calling the global add_finding/add_info_note/
# errors+=() directly — a subshell's mutations to those globals would be
# silently lost the moment it exits. The caller runs this once per
# directory that has its own package.json (root, or one level of
# subdirectories — the monorepo probe) and sums the results.
quality_check_dir() {
  local dir="$1"
  (
    set -euo pipefail
    cd "$PROJECT_DIR/$dir"

    local tsc_errors="null" lint_errors="null" lint_warnings="null"
    local tests_passed="null" tests_failed="null" hard_fail=false
    local -a d_findings=() d_errors=() d_info=()
    local no_timeout_warned_local=false

    # run_capture_timeout is redefined HERE, scoped to this subshell only
    # (a function redefinition inside `( )` dies with the subshell — the
    # outer script's own run_capture_timeout is untouched). The outer
    # version calls the global add_finding() directly, which would be lost
    # from inside a subshell the same way d_findings+=() below would be
    # lost if written to the outer findings[] instead.
    run_capture_timeout() {
      if [[ -n "$TIMEOUT_BIN" ]]; then
        run_capture "$TIMEOUT_BIN" "$TIMEOUT_SECS" "$@"
      else
        if [[ "$no_timeout_warned_local" == "false" ]]; then
          d_findings+=("no 'timeout' or 'gtimeout' binary found on PATH — external commands (tsc/eslint/test/build) are running WITHOUT a bounded timeout; install GNU coreutils for gtimeout support on macOS")
          no_timeout_warned_local=true
        fi
        run_capture "$@"
      fi
    }

    if [[ ! -d node_modules ]]; then
      d_findings+=("node_modules/ not found (run npm install) — skipping tsc/eslint/test/build checks")
    else
      # --- TypeScript ---
      if [[ ! -f node_modules/typescript/package.json ]]; then
        d_findings+=("typescript not found in node_modules — skipping tsc check")
      elif [[ ! -f tsconfig.json ]]; then
        d_findings+=("no tsconfig.json found — skipping tsc check")
      else
        run_capture_timeout npx --no-install tsc --noEmit
        combined="${RUN_OUT}"$'\n'"${RUN_ERR}"
        tsc_count=$(count_matches 'error TS[0-9]+' <<<"$combined")
        if [[ $RUN_RC -ne 0 && "$tsc_count" -eq 0 ]]; then
          d_errors+=("tsc exited non-zero with no parseable TS error lines: $(printf '%s' "$combined" | head -c 300)")
        else
          tsc_errors="$tsc_count"
          [[ "$tsc_count" -gt 0 ]] && hard_fail=true
        fi
      fi

      # --- ESLint ---
      has_eslint_config=false
      for f in .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts; do
        [[ -f "$f" ]] && has_eslint_config=true && break
      done
      if [[ "$has_eslint_config" == "false" ]]; then
        run_capture jq -e '.eslintConfig' package.json
        [[ $RUN_RC -eq 0 ]] && has_eslint_config=true
      fi

      if [[ ! -f node_modules/eslint/package.json ]]; then
        d_findings+=("eslint not found in node_modules — skipping lint check")
      elif [[ "$has_eslint_config" == "false" ]]; then
        d_findings+=("no ESLint config found — skipping lint check")
      elif [[ ! -d src ]]; then
        d_findings+=("no src/ directory found — skipping lint check (phase-gate lints src/)")
      else
        run_capture_timeout npx --no-install eslint src/ --format json
        eslint_out="$RUN_OUT"
        eslint_rc="$RUN_RC"
        if [[ -z "$eslint_out" ]]; then
          d_errors+=("eslint invocation produced no output (exit ${eslint_rc}): $(printf '%s' "$RUN_ERR" | head -c 300)")
        else
          run_capture jq -r '[([.[] | .errorCount] | add // 0), ([.[] | .warningCount] | add // 0)] | @tsv' <<<"$eslint_out"
          if [[ $RUN_RC -ne 0 || -z "$RUN_OUT" ]]; then
            d_errors+=("could not parse eslint JSON output: $(printf '%s' "$eslint_out" | head -c 300)")
          else
            IFS=$'\t' read -r lint_errors lint_warnings <<<"$RUN_OUT"
            [[ "$lint_errors" -gt 0 ]] && hard_fail=true
            [[ "$lint_warnings" -gt 0 ]] && d_findings+=("eslint reported ${lint_warnings} warning(s), 0 blocking errors — non-blocking, run \`npx eslint src/\` for detail")
          fi
        fi
      fi

      # --- Tests (prefer a JSON reporter over free-text parsing) ---
      run_capture jq -e '.scripts.test' package.json
      has_test_script=$([[ $RUN_RC -eq 0 ]] && echo true || echo false)

      if [[ "$has_test_script" == "false" ]]; then
        d_findings+=('no "test" script in package.json — skipping test check')
      else
        run_capture jq -e '.devDependencies.jest // .dependencies.jest' package.json
        has_jest=$([[ $RUN_RC -eq 0 ]] && echo true || echo false)
        run_capture jq -e '.devDependencies.vitest // .dependencies.vitest' package.json
        has_vitest=$([[ $RUN_RC -eq 0 ]] && echo true || echo false)

        if [[ "$has_jest" == "true" || "$has_vitest" == "true" ]]; then
          report_file=$(mktemp "${TMPDIR:-/tmp}/pgc-testreport.XXXXXX")
          if [[ "$has_jest" == "true" ]]; then
            run_capture_timeout npx --no-install jest --json --outputFile="$report_file"
          else
            run_capture_timeout npx --no-install vitest run --reporter=json --outputFile="$report_file"
          fi
          runner_rc="$RUN_RC"
          runner_err="$RUN_ERR"
          if [[ ! -s "$report_file" ]]; then
            d_errors+=("test runner did not produce a JSON report — cannot determine pass/fail counts: $(printf '%s' "$runner_err" | head -c 300)")
          else
            run_capture jq -e '.numPassedTests' "$report_file"
            if [[ $RUN_RC -ne 0 ]]; then
              d_errors+=("could not parse test-runner JSON report at ${report_file} (numPassedTests missing/null): $(printf '%s' "$RUN_ERR" | head -c 300)")
            else
              passed="$RUN_OUT"
              run_capture jq -e '.numFailedTests' "$report_file"
              if [[ $RUN_RC -ne 0 ]]; then
                d_errors+=("could not parse test-runner JSON report at ${report_file} (numFailedTests missing/null): $(printf '%s' "$RUN_ERR" | head -c 300)")
              else
                failed="$RUN_OUT"
                run_capture jq '.numFailedTestSuites // 0' "$report_file"
                if [[ $RUN_RC -ne 0 ]]; then
                  d_errors+=("could not parse test-runner JSON report at ${report_file} (numFailedTestSuites): $(printf '%s' "$RUN_ERR" | head -c 300)")
                else
                  failed_suites="$RUN_OUT"
                  if [[ "$runner_rc" -ne 0 && "$failed" -eq 0 && "$failed_suites" -gt 0 ]]; then
                    d_errors+=("test runner exited non-zero (exit ${runner_rc}) with ${failed_suites} failed test suite(s) but 0 failed individual tests — a suite failed to load (syntax/config/transform error), not a clean 0/0 run: $(printf '%s' "$runner_err" | head -c 300)")
                    hard_fail=true
                  else
                    tests_passed="$passed"
                    tests_failed="$failed"
                    [[ "$tests_failed" -gt 0 ]] && hard_fail=true
                  fi
                fi
              fi
            fi
          fi
          rm -f "$report_file"
        else
          run_capture_timeout npm test --silent
          if [[ $RUN_RC -ne 0 ]]; then
            d_findings+=("npm test exited non-zero (tests failed) — no jest/vitest JSON reporter detected, so granular pass/fail counts are unavailable")
            hard_fail=true
          else
            d_findings+=("npm test passed (exit 0) — no jest/vitest JSON reporter detected, so granular pass/fail counts are unavailable")
          fi
        fi
      fi

      # --- Build ---
      run_capture jq -e '.scripts.build' package.json
      has_build_script=$([[ $RUN_RC -eq 0 ]] && echo true || echo false)
      if [[ "$has_build_script" == "false" ]]; then
        d_findings+=('no "build" script in package.json — skipping build check')
      else
        run_capture_timeout npm run build --silent
        if [[ $RUN_RC -ne 0 ]]; then
          d_findings+=("npm run build failed (exit ${RUN_RC}): $(printf '%s' "$RUN_ERR" | head -c 300)")
          hard_fail=true
        else
          # A clean build is fully verified, not skipped/ambiguous — goes
          # to d_info (never d_findings) so it does not push the verdict to
          # WARN (BLOCKER 1 FIX history — see add_info_note above).
          d_info+=("npm run build: PASS")
        fi
      fi
    fi

    jq -n \
      --argjson tsc_errors "$tsc_errors" \
      --argjson lint_errors "$lint_errors" \
      --argjson lint_warnings "$lint_warnings" \
      --argjson tests_passed "$tests_passed" \
      --argjson tests_failed "$tests_failed" \
      --argjson hard_fail "$hard_fail" \
      --argjson findings "$(json_array "${d_findings[@]+"${d_findings[@]}"}")" \
      --argjson errors "$(json_array "${d_errors[@]+"${d_errors[@]}"}")" \
      --argjson info "$(json_array "${d_info[@]+"${d_info[@]}"}")" \
      '{tsc_errors:$tsc_errors, lint_errors:$lint_errors, lint_warnings:$lint_warnings, tests_passed:$tests_passed, tests_failed:$tests_failed, hard_fail:$hard_fail, findings:$findings, errors:$errors, info:$info}'
  )
}

QUALITY_DIRS=()
if [[ -f package.json ]]; then
  QUALITY_DIRS+=(".")
else
  # C16 fix: no package.json at the project root — probe exactly ONE level
  # of subdirectories (a shallow monorepo probe) before giving up, so a
  # genuine npm/TS monorepo (e.g. web/package.json + worker/pyproject.toml
  # — the real shape of the Projekt L reference project) is not
  # silently reported as "not an npm project".
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    case "$d" in node_modules|.git|dist|build|.next|coverage) continue ;; esac
    [[ -f "$d/package.json" ]] && QUALITY_DIRS+=("$d")
  done < <(find . -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|^\./||' | sort)
fi

if [[ ${#QUALITY_DIRS[@]} -eq 0 ]]; then
  # Neither the root nor any immediate subdirectory has a package.json.
  # Before concluding "not an npm project", name the actual stack when a
  # recognizable non-npm manifest is present (C16 fix) — never a
  # fabricated PASS for a project this script simply has no way to
  # quality-check; add_finding (WARN) is the honest verdict either way.
  non_npm_marker=""
  for m in pyproject.toml Cargo.toml go.mod Package.swift; do
    [[ -f "$m" ]] && { non_npm_marker="$m"; break; }
  done
  if [[ -z "$non_npm_marker" ]]; then
    while IFS= read -r d; do
      [[ -z "$d" ]] && continue
      case "$d" in node_modules|.git|dist|build|.next|coverage) continue ;; esac
      for m in pyproject.toml Cargo.toml go.mod Package.swift; do
        if [[ -f "$d/$m" ]]; then non_npm_marker="${d}/${m}"; break 2; fi
      done
    done < <(find . -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|^\./||' | sort)
  fi
  if [[ -n "$non_npm_marker" ]]; then
    stack_name="a non-npm stack"
    case "$non_npm_marker" in
      *pyproject.toml) stack_name="Python (pyproject.toml)" ;;
      *Cargo.toml)     stack_name="Rust (Cargo.toml)" ;;
      *go.mod)         stack_name="Go (go.mod)" ;;
      *Package.swift)  stack_name="Swift (Package.swift)" ;;
    esac
    add_finding "no package.json found at ${PROJECT_DIR} or one level of subdirectories; found ${stack_name} instead — this is not an npm/TypeScript project, so this script cannot run tsc/eslint/test/build; the check trio from the project's CLAUDE.md 'Mandatory Pre-Commit' section must be run by the lead"
  else
    add_finding "no package.json found in ${PROJECT_DIR} or its immediate subdirectories — skipping tsc/eslint/test/build checks (not an npm project)"
  fi
else
  multi_dir=$([[ ${#QUALITY_DIRS[@]} -gt 1 ]] && echo true || echo false)
  seen_tsc=false; seen_lint_e=false; seen_lint_w=false; seen_passed=false; seen_failed=false
  sum_tsc=0; sum_lint_e=0; sum_lint_w=0; sum_passed=0; sum_failed=0

  for d in "${QUALITY_DIRS[@]}"; do
    label="$d"; [[ "$label" == "." ]] && label="project root"
    prefix=""
    [[ "$multi_dir" == "true" || "$d" != "." ]] && prefix="[${label}] "

    set +e
    dir_result="$(quality_check_dir "$d")"
    dir_rc=$?
    set -e
    if [[ $dir_rc -ne 0 || -z "$dir_result" ]]; then
      errors+=("${prefix}quality checks failed to run (subshell exited ${dir_rc})")
      continue
    fi

    d_tsc=$(jq -r '.tsc_errors' <<<"$dir_result")
    d_lint_e=$(jq -r '.lint_errors' <<<"$dir_result")
    d_lint_w=$(jq -r '.lint_warnings' <<<"$dir_result")
    d_passed=$(jq -r '.tests_passed' <<<"$dir_result")
    d_failed=$(jq -r '.tests_failed' <<<"$dir_result")
    d_hard=$(jq -r '.hard_fail' <<<"$dir_result")

    while IFS= read -r f; do [[ -n "$f" ]] && add_finding "${prefix}${f}"; done < <(jq -r '.findings[]' <<<"$dir_result")
    while IFS= read -r e; do [[ -n "$e" ]] && errors+=("${prefix}${e}"); done < <(jq -r '.errors[]' <<<"$dir_result")
    while IFS= read -r i; do [[ -n "$i" ]] && add_info_note "${prefix}${i}"; done < <(jq -r '.info[]' <<<"$dir_result")

    [[ "$d_hard" == "true" ]] && HARD_FAIL=true
    if [[ "$d_tsc" != "null" ]]; then sum_tsc=$((sum_tsc + d_tsc)); seen_tsc=true; fi
    if [[ "$d_lint_e" != "null" ]]; then sum_lint_e=$((sum_lint_e + d_lint_e)); seen_lint_e=true; fi
    if [[ "$d_lint_w" != "null" ]]; then sum_lint_w=$((sum_lint_w + d_lint_w)); seen_lint_w=true; fi
    if [[ "$d_passed" != "null" ]]; then sum_passed=$((sum_passed + d_passed)); seen_passed=true; fi
    if [[ "$d_failed" != "null" ]]; then sum_failed=$((sum_failed + d_failed)); seen_failed=true; fi
  done

  [[ "$seen_tsc" == "true" ]] && tsc_errors="$sum_tsc"
  [[ "$seen_lint_e" == "true" ]] && lint_errors="$sum_lint_e"
  [[ "$seen_lint_w" == "true" ]] && lint_warnings="$sum_lint_w"
  [[ "$seen_passed" == "true" ]] && tests_passed="$sum_passed"
  [[ "$seen_failed" == "true" ]] && tests_failed="$sum_failed"
fi

if [[ ${#errors[@]} -eq 0 ]]; then
  emit_and_exit 0
else
  emit_and_exit 1
fi
