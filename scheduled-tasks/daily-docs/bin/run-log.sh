#!/usr/bin/env bash
# run-log v1.0 — run receipt for the daily-docs routine (paragraph C of the SKILL.md).
#
# PURPOSE: the line in daily-docs-log.jsonl is the ONLY proof that a run
# actually happened (IMP-075). It used to be the LAST step and had no
# artifact of its own — every abort after paragraph A/B produced artifacts
# WITHOUT a receipt. Really happened on 2026-07-31 (run for 2026-07-30):
# logbook written, Notion updated, then `[Request interrupted by user]` 11
# seconds after paragraph C began — the date series jumped 2026-07-29 ->
# 2026-07-31, and every coverage check reported a FALSE NEGATIVE "never ran".
#
# CONTRACT (two-phase, ONE line per date, upgrade in place):
#   1. `start`  — the VERY FIRST durable action of the run, before counting/logbook/Notion.
#                 Writes status:"partial". From here on, an abort is VISIBLE.
#   2. `finish` — after paragraph A+B. Raises the same line to status:"ok".
#      `fail`   — on a script ABORT etc. Sets status:"fail" + reason, WITHOUT numbers.
#
# Why a script and not prose: the same lesson as with the counting (2026-07-18,
# logbook-count.sh replaced the agent's own estimate). An agent that aborts no
# longer executes a prose instruction; a call that happens FIRST, on the other
# hand, has already happened. The jq-built object from count.json additionally
# prevents hand-typing the certificate fields (historical error source: "85
# commits" instead of 83).
set -euo pipefail

LOG_DEFAULT="$HOME/.claude/global-observation/daily-docs-log.jsonl"
# $HOME instead of a literal user path (IMP-219) — the same reasoning as for
# the logbook path in the SKILL.md still applies: a mandatory env variable
# that the scheduler doesn't set is the original defect in a new shape
# (${LOGBOOK_DIR} used to silently expand to empty). $HOME is NOT an
# app-specific configuration variable like the old ${LOGBOOK_DIR} — every
# process gets it set by the login shell/launchd environment, with no
# separate wiring needed in settings.json. Override only for tests/backfill.
LOG="${DAILY_DOCS_LOG:-$LOG_DEFAULT}"

die() { echo "ABORT: $*" >&2; exit 1; }
usage() {
  cat >&2 <<'EOF'
Usage:
  run-log.sh start  <YYYY-MM-DD>
  run-log.sh finish <YYYY-MM-DD> --count-json <path> --logbook <path>
                    [--notion-page-id <id>] [--notion-modus <text>]
                    [--status ok|partial] [--reason <text>] [--extra '<json-object>']
  run-log.sh fail   <YYYY-MM-DD> --reason <text>
  run-log.sh check  [<YYYY-MM-DD>]     # self-check / gap scan
EOF
  exit 1
}

[ $# -ge 1 ] || usage
CMD="$1"; shift || true

[ -f "$LOG" ] || die "run log missing: $LOG (do NOT create it — a wrong path is more likely than a missing file)"
[ -w "$LOG" ] || die "run log not writable: $LOG"
command -v jq >/dev/null 2>&1 || die "jq missing"

valid_date() { printf '%s' "$1" | /usr/bin/grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; }

# Replaces/inserts the line for $1, content from stdin. Date ordering is
# preserved, exactly ONE line per date. Atomic via temp + mv in the same directory.
splice() {
  local d="$1" tmp new_line
  new_line="$(cat)"
  printf '%s' "$new_line" | jq -e . >/dev/null 2>&1 || die "generated line is not valid JSON"
  tmp="$(mktemp "${LOG}.tmp.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN

  jq -r .date "$LOG" > "${tmp}.dates" || die "date column not readable — run log corrupted?"
  printf '%s\n' "$new_line" > "${tmp}.line"

  awk -v newfile="${tmp}.line" -v target="$d" '
    FNR==NR { dd[FNR]=$0; next }
    {
      if (dd[FNR] == target) { next }                       # old line for the same day is dropped
      if (!ins && (dd[FNR] > target)) {
        while ((getline l < newfile) > 0) print l; close(newfile); ins=1
      }
      print
    }
    END { if (!ins) { while ((getline l < newfile) > 0) print l; close(newfile) } }
  ' "${tmp}.dates" "$LOG" > "$tmp" || die "splice failed"

  # Mandatory checks BEFORE replacing — never install an unverified log.
  jq -e . "$tmp" >/dev/null || die "result contains an invalid JSON line"
  jq -r .date "$tmp" | sort -c || die "date series no longer ascending"
  [ "$(jq -r --arg d "$d" 'select(.date==$d) | .date' "$tmp" | wc -l | tr -d ' ')" -eq 1 ] \
    || die "not exactly one line for $d"

  rm -f "${tmp}.dates" "${tmp}.line"
  mv "$tmp" "$LOG" || die "installation failed"
  trap - RETURN
}

existing_status() { jq -r --arg d "$1" 'select(.date==$d) | .status' "$LOG" | head -1; }

case "$CMD" in
  start)
    D="${1:-}"; valid_date "${D:-}" || die "day missing/invalid (YYYY-MM-DD)"
    prev="$(existing_status "$D")"
    if [ -n "$prev" ]; then
      # Idempotent: a resumed run must not duplicate, and an
      # already-completed day must not fall back to "partial".
      echo "NOTE: a line for $D already exists (status=$prev) — start skipped." >&2
      exit 0
    fi
    jq -cn --arg d "$D" --argjson ts "$(date +%s)" '{
      date: $d, ts: $ts, status: "partial",
      phase: "started",
      reason: "Run started, paragraph A/B/C not yet complete. If this line stays partial, the run was aborted — no longer a false negative, but a visible partial run."
    }' | splice "$D"
    echo "run-log: $D recorded as partial (the run now has a receipt)." >&2
    ;;

  finish)
    D="${1:-}"; shift || true
    valid_date "${D:-}" || die "day missing/invalid (YYYY-MM-DD)"
    COUNT_JSON=""; LOGBOOK=""; NOTION_ID=""; NOTION_MODUS=""; ST="ok"; REASON=""; EXTRA="{}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --count-json) COUNT_JSON="${2:?--count-json needs a path}"; shift 2;;
        --logbook) LOGBOOK="${2:?--logbook needs a path}"; shift 2;;
        --notion-page-id) NOTION_ID="${2:-}"; shift 2;;
        --notion-modus) NOTION_MODUS="${2:-}"; shift 2;;
        --status) ST="${2:?--status needs ok|partial}"; shift 2;;
        --reason) REASON="${2:-}"; shift 2;;
        --extra) EXTRA="${2:?--extra needs a JSON object}"; shift 2;;
        *) die "unknown option: $1";;
      esac
    done
    [ -n "$COUNT_JSON" ] || die "--count-json missing (numbers come ONLY from logbook-count.sh)"
    [ -r "$COUNT_JSON" ] || die "count-json not readable: $COUNT_JSON"
    [ -n "$LOGBOOK" ] || die "--logbook missing"
    [ -f "$LOGBOOK" ] || die "logbook file does not exist: $LOGBOOK (status ok without an artifact is not allowed)"
    case "$ST" in ok|partial) :;; *) die "--status must be ok or partial (fail => use the 'fail' subcommand)";; esac
    [ "$ST" = "ok" ] || [ -n "$REASON" ] || die "status=partial requires --reason (SKILL.md fail-loud contract)"
    printf '%s' "$EXTRA" | jq -e 'type=="object"' >/dev/null 2>&1 || die "--extra is not a JSON object"
    jq -e 'has("items_total") and has("count_basis") and has("evidence_tier") and has("quellen_epochen") and has("sources")' \
      "$COUNT_JSON" >/dev/null 2>&1 || die "count-json does not satisfy the script contract (items_total/count_basis/evidence_tier/quellen_epochen/sources)"
    JD="$(jq -r .day "$COUNT_JSON")"
    [ "$JD" = "$D" ] || die "count-json belongs to $JD, not $D"

    prev="$(existing_status "$D")"
    [ -n "$prev" ] || echo "WARNING: no 'start' present for $D — the line is written anyway, but the run went unrecorded for a while." >&2

    jq -c \
      --arg d "$D" --argjson ts "$(date +%s)" --arg st "$ST" \
      --arg lb "$LOGBOOK" --arg nid "$NOTION_ID" --arg nmod "$NOTION_MODUS" \
      --arg reason "$REASON" --argjson extra "$EXTRA" \
      --arg startfehlt "$([ -n "$prev" ] && echo false || echo true)" '
      {
        date: $d, ts: $ts, status: $st,
        logbook_path: $lb,
        items_total, count_basis, evidence_tier, evidence_tier_grund,
        quellen_epochen, sources,
        vcs_operationen: (.vcs_operationen | if type=="array" then length else . end),
        git_ambiguous_nicht_gezaehlt, items_sha256
      }
      + (if $nid  != "" then {notion_page_id: $nid} else {} end)
      + (if $nmod != "" then {notion_modus: $nmod} else {} end)
      + (if $reason != "" then {reason: $reason} else {} end)
      + (if $startfehlt == "true" then {start_zeile_fehlte: true} else {} end)
      + $extra
    ' "$COUNT_JSON" | splice "$D"
    echo "run-log: $D raised to status=$ST." >&2
    ;;

  fail)
    D="${1:-}"; shift || true
    valid_date "${D:-}" || die "day missing/invalid (YYYY-MM-DD)"
    REASON=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --reason) REASON="${2:?--reason needs text}"; shift 2;;
        *) die "unknown option: $1";;
      esac
    done
    [ -n "$REASON" ] || die "--reason is MANDATORY for fail (SKILL.md fail-loud contract)"
    # NO number fields — fail-loud contract: on exit != 0, no items_total, not even null.
    jq -cn --arg d "$D" --argjson ts "$(date +%s)" --arg r "$REASON" \
      '{date:$d, ts:$ts, status:"fail", reason:$r}' | splice "$D"
    echo "run-log: $D recorded as fail." >&2
    ;;

  check)
    D="${1:-}"
    if [ -n "$D" ]; then
      valid_date "$D" || die "invalid date"
      line="$(jq -c --arg d "$D" 'select(.date==$d)' "$LOG")"
      [ -n "$line" ] || { echo "MISSING: no line for $D"; exit 2; }
      printf '%s\n' "$line" | jq -r '"\(.date) status=\(.status) items_total=\(.items_total // "-")"'
      exit 0
    fi
    jq -e . "$LOG" >/dev/null || die "run log contains invalid JSON"
    jq -r .date "$LOG" | sort -c || die "run log not sorted by date"
    dup="$(jq -r .date "$LOG" | uniq -d)"
    [ -z "$dup" ] || die "duplicate date lines: $dup"
    echo "Run log structurally fine ($(wc -l < "$LOG" | tr -d ' ') lines)."
    echo "Open partial runs (status != ok):"
    jq -r 'select(.status != "ok") | "  \(.date) status=\(.status) reason=\((.reason // "-")[0:80])"' "$LOG"
    ;;

  *) usage;;
esac
