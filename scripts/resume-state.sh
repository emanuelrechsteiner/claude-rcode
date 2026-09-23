#!/usr/bin/env bash
# resume-state.sh — deterministic GATHER half of the R.Code /continue
# command (Steps A1-A4 / B1-B2: git state, branch, PROJECT-STATUS.md,
# .rcode/agent-log.md, stash, in-progress issue/phase detection).
# ─────────────────────────────────────────────────────────────────────────────
# WHY THIS EXISTS: see phase-gate-check.sh's header — same rationale (gather
# half must be script-counted, not model-estimated; see rules/fail-loud.md).
#
# This script also supports non-R.Code repos (continue.md "Path B"):
# a missing .rcode/ directory or PROJECT-STATUS.md is a FINDING, not an
# error — that is a legitimate, documented mode, not a broken prerequisite.
# The one HARD prerequisite is being inside a git repository — everything
# in this script's contract is git-state-derived.
#
# Where evidence conflicts (e.g. agent-log says issue #14, branch name says
# #12), this script reports BOTH via findings[] and sets ambiguous:true.
# SHOULD-FIX 4 (this note corrects a prior misstatement): the output schema
# requires in_progress_issue/detected_phase to carry SOME value, so on
# conflict each field carries a documented PROVISIONAL pick rather than null
# — in_progress_issue takes the branch-name reading (more likely to be
# current than a possibly-stale log entry), detected_phase takes
# PROJECT-STATUS.md's reading (status-sync's regenerated truth) — alongside
# ambiguous:true and both raw readings spelled out in findings[]. This is a
# schema-driven tie-break, NOT the script exercising judgment on which source
# is "right"; the lead must treat the field value as provisional and
# adjudicate using findings[], never trust it as authoritative on its own.
#
# TRACKER-AGNOSTIC (A3, 2026-09-23): this script now also reports `tracker`
# (resolved via rcode-units.sh, the ONE parser — a failure to resolve it is
# a finding, not a hard error, since git/branch/agent-log facts below remain
# valid regardless) and a tracker-aware `in_progress_unit` ("#N" for github,
# "P-NNN" for plan — same branch-vs-log cross-check + provisional-pick
# reasoning as in_progress_issue above, generalized to the plan tracker's
# `…/p-<NNN>-…` branch convention). `in_progress_issue` and `detected_phase`
# are UNCHANGED in computation — kept verbatim for existing consumers.
# `detected_project_phase` is a same-turn alias: identical value to
# `detected_phase`, which is now the DEPRECATED name (kept, never removed,
# per this repo's own "additive, never silently rename a contract field"
# discipline). `last_logged_step` parses the newest agent-log entry's
# `**Last step:** N` line — a field `commands/issue.md` writes going
# forward; it is legitimately null on any project whose agent-log predates
# that convention (not a bug — a finding names the gap).
#
# K-C / C2 FIX (2026-09-23): every field derived from .rcode/agent-log.md
# (last_logged_step, issue_from_log, phase_from_log, plan_unit_from_log,
# last_entry_agent) is now scoped to the content of the NEWEST
# "## Session:" block ONLY — never the whole file. Before this fix, a
# `grep`-for-the-last-match-in-the-file approach silently returned a STALE
# value from an older /issue entry whenever a non-issue session (handoff,
# phase-gate, team-lead, lessons, ...) was appended afterward, with no
# finding raised (the "not found" finding only fired when the pattern was
# absent from the WHOLE file). `last_entry_agent` (string|null) is NEW: the
# newest block's own `**Agent:**` line value, verbatim — the producer
# continue.md/team-lead need to tell an /issue entry from any other
# writer's entry (see the two findings below).
#
# C18/C34 FIX (2026-09-23): when the current branch encodes neither the
# `<type>/issue-N-…` nor the `<type>/p-NNN-…` convention, a finding now
# names that the branch-based half of the in-progress-unit cross-check is
# unavailable — including the DOMINANT real shape, a team-lead wave branch
# (`work/<date>-<slug>`, holds commits for MULTIPLE units by design under
# A1 Worker mode), which gets its own, non-alarming message rather than
# being lumped in with a genuinely non-conforming branch name.
#
# N1 FIX (2026-09-23): the free-text "**Directive:**" line (team-lead.md's
# agent-log template — the verbatim ORIGINAL user directive) is excluded
# from every whole-block regex below (phase_from_log, and the generic
# issue_from_log/plan_unit_from_log fallback) — a directive that happens
# to mention "Phase 4" or "issue #42" in prose is not this entry's actual
# phase/issue/unit evidence.
#
# N12 FIX (2026-09-23): for a newest block whose own "**Agent:**" line is
# `team-lead`, issue_from_log/plan_unit_from_log are read from that
# entry's structured "**Units:**" line (the FIRST unit whose state is
# neither closed nor done) instead of a last-match-anywhere regex over the
# whole block — a "**Next action:**"/"**Decisions:**" line mentioning a
# DIFFERENT unit could otherwise silently override the actually-bound one.
# The generic regex fallback is reserved for entries with no structured
# Units field at all (legacy entries, or an older/malformed team-lead
# entry).
#
# Usage:
#   resume-state.sh [project-dir]
#   resume-state.sh --help
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
Usage: resume-state.sh [project-dir]
       resume-state.sh --help

Gathers the deterministic facts /continue needs to resume interrupted work:
git branch/dirty-files/stash state, the last commit, open PRs on the current
branch, and a best-effort in-progress-issue/phase detection cross-checked
across .rcode/agent-log.md, PROJECT-STATUS.md, and the branch name.

Arguments:
  [project-dir]   Optional. Defaults to the current directory.

Output (stdout, JSON):
  {
    "ok": bool,
    "tracker": "github"|"plan"|null,
    "branch": string|null,           // null if detached HEAD
    "dirty_files": [string],         // git status --porcelain paths
    "stash_count": int,
    "last_commit": {"hash":string,"subject":string,"relative_date":string}|null,
    "in_progress_issue": int|null,    // DEPRECATED-in-favor-of, but kept: github-style bare issue number
    "in_progress_unit": string|null,  // "#N" (github) or "P-NNN" (plan)
    "detected_phase": int|null,       // DEPRECATED alias, kept verbatim — see detected_project_phase
    "detected_project_phase": int|null,
    "last_logged_step": int|null,     // parsed from the NEWEST "## Session:" entry's "**Last step:** N" line only
    "last_entry_agent": string|null,  // the newest "## Session:" entry's own "**Agent:**" line value, verbatim
    "open_prs": [{"number":int,"title":string,"headRefName":string}]|null,
    "ambiguous": bool,                // true iff evidence sources conflicted
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
  out_f=$(mktemp "${TMPDIR:-/tmp}/rst-out.XXXXXX")
  err_f=$(mktemp "${TMPDIR:-/tmp}/rst-err.XXXXXX")
  set +e
  "$@" >"$out_f" 2>"$err_f"
  rc=$?
  set -e
  RUN_OUT="$(cat "$out_f")"
  RUN_ERR="$(cat "$err_f")"
  RUN_RC=$rc
  rm -f "$out_f" "$err_f"
}

# last_regex_match_number PATTERN TEXT — extracts the numeric part of the
# LAST line matching PATTERN within TEXT (best-effort: assumes chronological
# append order, i.e. "most recent" == "last in TEXT"). K-C/C2 FIX
# (2026-09-23): takes TEXT (a string), not a whole file, so every call site
# can scope it to the newest "## Session:" block instead of the whole
# agent-log.md — see the header comment. Empty output if no match — grep's
# rc=1 in that case is a valid "not found", not an error (see count_matches
# in phase-gate-check.sh for the same distinction).
last_regex_match_number() {
  local pattern="$1" text="$2"
  local rc
  set +e
  printf '%s\n' "$text" | grep -oE "$pattern" | grep -oE '[0-9]+' | tail -1
  rc=$?
  set -e
  return 0
}

# last_regex_match_str PATTERN TEXT — same as last_regex_match_number but
# returns the LAST matching line's full text verbatim (no numeric
# extraction) — used for last_entry_agent, whose value is a free-form
# string, not a number.
last_regex_match_str() {
  local pattern="$1" text="$2"
  set +e
  printf '%s\n' "$text" | grep -oE "$pattern" | tail -1
  set -e
  return 0
}

# first_unit_not_closed TEXT — N12 FIX (2026-09-23): parses a "**Units:**"
# field VALUE (the text after the label — comma-separated "<ID> (<state>)"
# entries, state optional) and returns the FIRST unit id whose state is
# neither "closed" nor "done" (case-insensitive). A unit mentioned with no
# parenthesized state at all counts as "not closed" (still in progress).
# ID = "P-NNN" (plan, NNN >= 3 digits) or "#N" (github). Empty output if no
# id token is found at all, or if every mentioned unit is explicitly
# closed/done — the caller must NOT treat that as "field absent"; see the
# N12 fix at its call site below.
first_unit_not_closed() {
  local text="$1" entry id state
  local -a parts
  # Regex patterns are held in variables, not written inline after `=~` —
  # unquoted parens inline confuse bash's OWN tokenizer (a documented
  # bash quirk, distinct from the regex engine itself), not just the
  # ERE engine.
  local id_p_re='(P-[0-9][0-9][0-9]+)'
  local id_hash_re='(#[0-9]+)'
  local paren_re='\(([^)]*)\)'
  IFS=',' read -ra parts <<<"$text"
  # bash-3.2-safe (see phase-gate-check.sh's header comment): a truly
  # EMPTY $text still leaves `parts` a zero-length array here (read on an
  # empty here-string yields no fields at all, unlike a non-empty one
  # which always yields >=1), and `${parts[@]}` on a genuinely empty array
  # throws "unbound variable" under `set -u` on macOS's stock bash 3.2 —
  # the `${parts[@]+"${parts[@]}"}` guard is the portable workaround.
  for entry in "${parts[@]+"${parts[@]}"}"; do
    entry="$(printf '%s' "$entry" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$entry" ]] && continue
    id=""
    if [[ "$entry" =~ $id_p_re ]]; then
      id="${BASH_REMATCH[1]}"
    elif [[ "$entry" =~ $id_hash_re ]]; then
      id="${BASH_REMATCH[1]}"
    else
      continue
    fi
    state=""
    if [[ "$entry" =~ $paren_re ]]; then
      state="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
      state="$(printf '%s' "$state" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    fi
    case "$state" in
      closed|done) continue ;;
      *) printf '%s' "$id"; return 0 ;;
    esac
  done
  return 0
}

findings=()
errors=()
ambiguous=false

emit_and_exit() {
  local exit_code="$1"
  local ok_bool="false"
  [[ ${#errors[@]} -eq 0 ]] && ok_bool="true"

  jq -n \
    --argjson ok "$ok_bool" \
    --arg tracker "${TRACKER:-}" \
    --argjson has_tracker "${HAS_TRACKER:-false}" \
    --arg branch "${branch_out:-}" \
    --argjson has_branch "${has_branch:-false}" \
    --argjson dirty_files "$(json_array "${dirty_files[@]+"${dirty_files[@]}"}")" \
    --argjson stash_count "${stash_count:-null}" \
    --argjson last_commit "${last_commit_json:-null}" \
    --argjson in_progress_issue "${in_progress_issue:-null}" \
    --arg in_progress_unit "${in_progress_unit_val:-}" \
    --argjson has_in_progress_unit "${has_in_progress_unit:-false}" \
    --argjson detected_phase "${detected_phase:-null}" \
    --argjson last_logged_step "${last_logged_step:-null}" \
    --arg last_entry_agent "${last_entry_agent_val:-}" \
    --argjson has_last_entry_agent "${has_last_entry_agent:-false}" \
    --argjson open_prs "${open_prs_json:-null}" \
    --argjson ambiguous "$ambiguous" \
    --argjson findings "$(json_array "${findings[@]+"${findings[@]}"}")" \
    --argjson errors "$(json_array "${errors[@]+"${errors[@]}"}")" \
    '{ok:$ok, tracker: (if $has_tracker then $tracker else null end), branch: (if $has_branch then $branch else null end), dirty_files:$dirty_files, stash_count:$stash_count, last_commit:$last_commit, in_progress_issue:$in_progress_issue, in_progress_unit: (if $has_in_progress_unit then $in_progress_unit else null end), detected_phase:$detected_phase, detected_project_phase:$detected_phase, last_logged_step:$last_logged_step, last_entry_agent: (if $has_last_entry_agent then $last_entry_agent else null end), open_prs:$open_prs, ambiguous:$ambiguous, findings:$findings, errors:$errors}'
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

# ── Hard prerequisite: must be a git repo ───────────────────────────────
if ! command -v git >/dev/null 2>&1; then
  errors+=("git binary not found")
  emit_and_exit 1
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  errors+=("not a git repository: $PROJECT_DIR")
  emit_and_exit 1
fi

# ── Tracker resolution: delegate to the ONE parser (A3) ──────────────────
# Unlike status-metrics.sh/phase-gate-check.sh, a tracker-resolution failure
# here is a FINDING, not a hard error: this script's core mission (git
# branch/dirty/stash/commit state) is valid and useful independent of
# whether the tracker could be resolved.
RCU_SCRIPT="$SELF_DIR/rcode-units.sh"
HAS_TRACKER=false
if [[ ! -f "$RCU_SCRIPT" ]]; then
  findings+=("rcode-units.sh not found next to this script: $RCU_SCRIPT — tracker unavailable")
else
  run_capture bash "$RCU_SCRIPT" "$PROJECT_DIR"
  rcu_json="$RUN_OUT"
  TRACKER=$(jq -r '.tracker // empty' <<<"$rcu_json" 2>/dev/null || true)
  if [[ -n "$TRACKER" ]]; then
    HAS_TRACKER=true
  else
    findings+=("rcode-units.sh produced no usable tracker: $(printf '%s' "$RUN_ERR" | head -c 300)")
  fi
fi

# ── Branch ────────────────────────────────────────────────────────────────
run_capture git branch --show-current
has_branch=false
branch_out=""
if [[ $RUN_RC -ne 0 ]]; then
  errors+=("git branch --show-current failed: $(printf '%s' "$RUN_ERR" | head -c 300)")
elif [[ -z "$RUN_OUT" ]]; then
  findings+=("HEAD is detached (no current branch)")
else
  has_branch=true
  branch_out="$RUN_OUT"
fi

# ── Dirty files ───────────────────────────────────────────────────────────
dirty_files=()
run_capture git status --porcelain=v1 --untracked-files=all
if [[ $RUN_RC -ne 0 ]]; then
  errors+=("git status failed: $(printf '%s' "$RUN_ERR" | head -c 300)")
else
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    rest="${line:3}"
    if [[ "$rest" == *" -> "* ]]; then
      rest="${rest#* -> }"
    fi
    if [[ "$rest" == \"*\" ]]; then
      rest="${rest:1:${#rest}-2}"
    fi
    dirty_files+=("$rest")
  done <<<"$RUN_OUT"
fi

# ── Stash count ───────────────────────────────────────────────────────────
stash_count="null"
run_capture git stash list
if [[ $RUN_RC -ne 0 ]]; then
  errors+=("git stash list failed: $(printf '%s' "$RUN_ERR" | head -c 300)")
elif [[ -z "$RUN_OUT" ]]; then
  stash_count=0
else
  stash_count=$(printf '%s\n' "$RUN_OUT" | grep -c '.')
fi

# ── Last commit ───────────────────────────────────────────────────────────
last_commit_json="null"
run_capture git log -1 --format=%h%x1f%s%x1f%cr
if [[ $RUN_RC -ne 0 ]]; then
  findings+=("repository has no commits yet (unborn HEAD) — no last_commit available")
else
  IFS=$'\x1f' read -r commit_hash commit_subject commit_reldate <<<"$RUN_OUT"
  last_commit_json=$(jq -n --arg h "$commit_hash" --arg s "$commit_subject" --arg r "$commit_reldate" \
    '{hash:$h, subject:$s, relative_date:$r}')
fi

# ── Open PRs on the current branch ───────────────────────────────────────
# BLOCKER 3 FIX: this entire lookup is now a degraded-mode findings[] path,
# per the header's own contract ("the one HARD prerequisite is being inside a
# git repository — everything else degrades to findings[]"). Previously a
# missing `gh` binary, failed `gh auth`, OR a repo with no configured remote
# (e.g. a fresh clone before its first push — an ordinary, common state) all
# pushed into errors[], forcing ok:false/exit 1 even though branch,
# dirty_files, stash_count, last_commit, in_progress_issue, and
# detected_phase were all gathered fine. Because commands/continue.md
# instructs the lead to STOP on ok:false, that bug hard-stopped /continue on
# ordinary repos. open_prs_json stays "null" on every degraded branch below —
# reserve errors[] for failures that genuinely invalidate the whole result.
open_prs_json="null"
if [[ "$has_branch" == "false" ]]; then
  findings+=("no current branch (detached HEAD) — cannot determine open PRs")
elif ! command -v gh >/dev/null 2>&1; then
  findings+=("gh CLI not found — cannot determine open PRs for branch '${branch_out}' (degraded: open_prs unavailable, not a hard failure)")
else
  run_capture gh auth status
  if [[ $RUN_RC -ne 0 ]]; then
    findings+=("gh is not authenticated (gh auth status failed) — cannot determine open PRs (degraded: open_prs unavailable, not a hard failure)")
  else
    run_capture gh pr list --head "$branch_out" --state open --json number,title,headRefName --limit 50
    if [[ $RUN_RC -ne 0 ]]; then
      findings+=("gh pr list failed (no remote configured, network issue, or repo not hosted on GitHub): $(printf '%s' "$RUN_ERR" | head -c 300) — degraded: open_prs unavailable, not a hard failure")
    else
      open_prs_json="$RUN_OUT"
    fi
  fi
fi

# ── In-progress issue / phase — cross-checked across three sources ──────
# Source A: .rcode/agent-log.md (last-entry heuristic: last match in
#           file, assuming chronological append order — documented, not
#           silently assumed; see continue.md A2).
# Source B: PROJECT-STATUS.md "Active Phase" line (continue.md A1).
# Source C: current branch name, per workflow-git.md's
#           "<type>/issue-<number>-<slug>" convention (github) or
#           "<type>/p-<NNN>-<slug>" (plan, A3).
issue_from_log="" ; issue_from_branch="" ; phase_from_log="" ; phase_from_status=""
plan_unit_from_log="" ; plan_unit_from_branch="" ; step_from_log=""
last_entry_agent_val="" ; has_last_entry_agent=false

if [[ ! -d .rcode ]]; then
  findings+=("no .rcode/ directory found — generic (non-R.Code) repo; resuming from git state + branch-name heuristics only (continue.md Path B)")
elif [[ ! -f .rcode/agent-log.md ]]; then
  findings+=(".rcode/agent-log.md not found — cannot read last logged in-progress state")
else
  # K-C / C2 FIX: scope every agent-log-derived field to the content of the
  # NEWEST "## Session:" block only (awk walks the file once, remembering
  # the line number of the LAST "## Session:" match, then prints from there
  # to EOF) — never the whole file. A field from an OLDER entry must never
  # be silently treated as current (see header comment).
  newest_block="$(awk '
    /^## Session:/ { start = NR; delete lines; n = 0 }
    { n++; lines[n] = $0 }
    END { if (start > 0) for (i = 1; i <= n; i++) print lines[i] }
  ' .rcode/agent-log.md)"

  if [[ -z "$newest_block" ]]; then
    findings+=(".rcode/agent-log.md has no '## Session:' entries — cannot read last logged in-progress state")
  else
    # N1 FIX (2026-09-23): exclude the free-text "**Directive:**" line
    # before running ANY whole-block regex below. team-lead.md's agent-log
    # template puts the verbatim ORIGINAL user directive on this line —
    # free prose that can legitimately contain phrases like "Phase 4" or
    # "issue #42" as part of what the user asked for, not as this entry's
    # actual phase/issue/unit evidence. Every other field's regex below
    # scans this filtered text instead of $newest_block directly.
    newest_block_scan="$(printf '%s\n' "$newest_block" | grep -vE '^\*\*Directive:\*\*' || true)"

    agent_line="$(last_regex_match_str '\*\*Agent:\*\*[[:space:]]*.+' "$newest_block_scan")"
    if [[ -n "$agent_line" ]]; then
      last_entry_agent_val="$(printf '%s' "$agent_line" | sed -E 's/^\*\*Agent:\*\*[[:space:]]*//; s/[[:space:]]+$//')"
      has_last_entry_agent=true
    fi

    # N12 FIX (2026-09-23): a team-lead-authored entry (detected via the
    # newest block's own "**Agent:** team-lead" line, parsed just above)
    # carries a STRUCTURED "**Units:**" line ("<IDs with state>" — see
    # team-lead.md's agent-log template) — read the in-progress unit from
    # THAT line specifically, never from a last-match-anywhere regex over
    # the whole block's free text (a later "**Next action:**" or
    # "**Decisions:**" mention of a DIFFERENT unit would otherwise
    # silently override the actually-bound one). The generic whole-block
    # regex fallback below is reserved for entries that have NO structured
    # Units field at all — legacy /issue entries, or a malformed/older
    # team-lead entry (see fixture M in the regression suite for exactly
    # that case).
    units_line=""
    if [[ "$has_last_entry_agent" == "true" && "$last_entry_agent_val" == "team-lead" ]]; then
      units_line="$(last_regex_match_str '\*\*Units:\*\*[[:space:]]*.+' "$newest_block_scan")"
    fi

    if [[ -n "$units_line" ]]; then
      units_value="$(printf '%s' "$units_line" | sed -E 's/^\*\*Units:\*\*[[:space:]]*//; s/[[:space:]]+$//')"
      units_unit_val="$(first_unit_not_closed "$units_value")"
      if [[ "$units_unit_val" =~ ^P-([0-9][0-9][0-9]+)$ ]]; then
        plan_unit_from_log="${BASH_REMATCH[1]}"
      elif [[ "$units_unit_val" =~ ^\#([0-9]+)$ ]]; then
        issue_from_log="${BASH_REMATCH[1]}"
      fi
      findings+=("in-progress unit read from the newest team-lead entry's structured '**Units:**' line, not a whole-block text match")
    else
      issue_from_log="$(last_regex_match_number '[Ii]ssue[[:space:]]*#?[0-9]+' "$newest_block_scan")"
      plan_unit_from_log="$(last_regex_match_number '\bP-[0-9][0-9][0-9]+' "$newest_block_scan")"
    fi

    phase_from_log="$(last_regex_match_number '[Pp]hase[[:space:]]+[0-9]+' "$newest_block_scan")"
    step_from_log="$(last_regex_match_number '\*\*Last step:\*\*[[:space:]]*[0-9]+' "$newest_block_scan")"

    [[ -n "$issue_from_log" || -n "$phase_from_log" || -n "$plan_unit_from_log" ]] && \
      findings+=("heuristic parse of .rcode/agent-log.md's newest '## Session:' entry (best-effort — no fixed template exists in this repo)")
    [[ -z "$step_from_log" ]] && \
      findings+=("no '**Last step:** N' line found in the newest .rcode/agent-log.md entry — commands/issue.md writes this on every entry going forward; unavailable for older/other-producer entries")
  fi
fi

if [[ ! -f PROJECT-STATUS.md ]]; then
  findings+=("PROJECT-STATUS.md not found — cannot cross-check Active Phase")
else
  phase_from_status="$(grep -iE 'Active Phase' PROJECT-STATUS.md | grep -oE '[Pp]hase[[:space:]]+[0-9]+' | grep -oE '[0-9]+' | head -1 || true)"
fi

if [[ "$has_branch" == "true" && "$branch_out" =~ ^(feat|fix|refactor|test|docs|style|chore|perf)/issue-([0-9]+)- ]]; then
  issue_from_branch="${BASH_REMATCH[2]}"
fi
if [[ "$has_branch" == "true" && "$branch_out" =~ ^(feat|fix|refactor|test|docs|style|chore|perf)/[Pp]-([0-9][0-9][0-9]+)- ]]; then
  plan_unit_from_branch="P-${BASH_REMATCH[2]}"
fi

# C18/C34 FIX: name the degraded-confidence path when the branch encodes
# NEITHER recognized convention, instead of silently falling back to the
# agent-log heuristic alone. A team-lead wave branch (work/<date>-<slug>)
# is the DOMINANT real shape under A1 Worker mode and holds commits for
# MULTIPLE units by design — documented here as a distinct, expected case
# rather than lumped in with a genuinely non-conforming branch name.
if [[ "$has_branch" == "true" && -z "$issue_from_branch" && -z "$plan_unit_from_branch" ]]; then
  if [[ "$branch_out" =~ ^work/[0-9]{4}-[0-9]{2}-[0-9]{2}-.+ ]]; then
    findings+=("current branch '${branch_out}' is a team-lead wave branch (work/<date>-<slug>, holds commits for multiple units by design under Worker mode) — branch-based unit detection is unavailable; relying on agent-log.md only")
  else
    findings+=("current branch '${branch_out}' does not follow the <type>/issue-N or <type>/p-NNN convention — branch-based unit detection is unavailable; relying on agent-log.md only")
  fi
fi

# in_progress_issue: cross-check log vs branch
in_progress_issue="null"
if [[ -n "$issue_from_log" && -n "$issue_from_branch" ]]; then
  if [[ "$issue_from_log" == "$issue_from_branch" ]]; then
    in_progress_issue="$issue_from_log"
  else
    ambiguous=true
    in_progress_issue="$issue_from_branch"
    findings+=("conflicting in-progress-issue evidence: agent-log says #${issue_from_log}, branch name says #${issue_from_branch} — using branch (more likely current); verify manually")
  fi
elif [[ -n "$issue_from_branch" ]]; then
  in_progress_issue="$issue_from_branch"
elif [[ -n "$issue_from_log" ]]; then
  in_progress_issue="$issue_from_log"
else
  findings+=("could not detect an in-progress issue number from agent-log.md or the branch name")
fi

# detected_phase: cross-check log vs PROJECT-STATUS.md
detected_phase="null"
if [[ -n "$phase_from_log" && -n "$phase_from_status" ]]; then
  if [[ "$phase_from_log" == "$phase_from_status" ]]; then
    detected_phase="$phase_from_log"
  else
    ambiguous=true
    detected_phase="$phase_from_status"
    findings+=("conflicting phase evidence: agent-log says Phase ${phase_from_log}, PROJECT-STATUS.md says Phase ${phase_from_status} — using PROJECT-STATUS.md (status-sync's regenerated truth); verify manually")
  fi
elif [[ -n "$phase_from_status" ]]; then
  detected_phase="$phase_from_status"
elif [[ -n "$phase_from_log" ]]; then
  detected_phase="$phase_from_log"
else
  findings+=("could not detect the active phase from agent-log.md or PROJECT-STATUS.md")
fi

# in_progress_unit: tracker-aware unit identifier (A3). github reuses
# in_progress_issue's already-resolved (and already cross-checked) value —
# no second resolution pass. plan mirrors the SAME log-vs-branch cross-check
# shape as in_progress_issue above, generalized to P-NNN.
in_progress_unit_val=""
has_in_progress_unit=false
if [[ "$HAS_TRACKER" == "true" && "$TRACKER" == "github" ]]; then
  if [[ "$in_progress_issue" != "null" ]]; then
    in_progress_unit_val="#${in_progress_issue}"
    has_in_progress_unit=true
  fi
elif [[ "$HAS_TRACKER" == "true" && "$TRACKER" == "plan" ]]; then
  if [[ -n "$plan_unit_from_log" && -n "$plan_unit_from_branch" ]]; then
    if [[ "P-${plan_unit_from_log}" == "$plan_unit_from_branch" ]]; then
      in_progress_unit_val="P-${plan_unit_from_log}"
    else
      ambiguous=true
      in_progress_unit_val="$plan_unit_from_branch"
      findings+=("conflicting in-progress-unit evidence: agent-log says P-${plan_unit_from_log}, branch name says ${plan_unit_from_branch} — using branch (more likely current); verify manually")
    fi
    has_in_progress_unit=true
  elif [[ -n "$plan_unit_from_branch" ]]; then
    in_progress_unit_val="$plan_unit_from_branch"
    has_in_progress_unit=true
  elif [[ -n "$plan_unit_from_log" ]]; then
    in_progress_unit_val="P-${plan_unit_from_log}"
    has_in_progress_unit=true
  else
    findings+=("could not detect an in-progress plan unit from agent-log.md or the branch name")
  fi
fi

# last_logged_step: parsed above (Source A) — normalize to "null" for --argjson.
last_logged_step="${step_from_log:-null}"

if [[ ${#errors[@]} -eq 0 ]]; then
  emit_and_exit 0
else
  emit_and_exit 1
fi
