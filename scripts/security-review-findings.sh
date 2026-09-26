#!/bin/bash
# security-review-findings.sh — durable feedback channel for the automatic
# security-review sub-sessions (IMP-207, 2026-09-09).
# ─────────────────────────────────────────────────────────────────────────────
# PROBLEM MEASURED, NOT ASSUMED: the bundled security-review plugin
# (`security-guidance@claude-code-plugins`) runs its checks as independent
# background sessions — `"entrypoint":"sdk-py"`, first user message
# "Review this change for security vulnerabilities. Changed files …" — under
# ~/.claude/projects/<project-slug>/<session-id>.jsonl. Its result reaches a
# human ONLY as a task-notification chat message to the PARENT session, and
# only if that parent session is still alive when the review finishes. There
# is no durable record. A real finding sat unseen for 16 days (2026-08-24 ->
# 2026-09-09, category "allowlist-semantic-escape" in
# hooks/excessive-agency-gate.sh) until a manual grep found it.
#
# Lead measurement (2026-09-09), full corpus (not a time-windowed sample):
#   grep -rl 'Review this change for security vulnerabilities'
#        ~/.claude/projects --include='*.jsonl'
#   -> 191 files across 8 projects + 2 worktree copies. claude-code-config
#      alone contributed 44 (29 top-level + 11 + 5 subagent-path
#      false-positive matches — see classifier note below); the remaining
#      147 were spread across the other 7 projects and 2 worktree copies of
#      one of them, one project alone accounting for 61 of those — this is
#      a volume problem across the whole projects/ tree, not specific to
#      any single project (per-project breakdown omitted here by design,
#      IMP-219 — see the durable JSONL feed this script produces for the
#      live, per-machine numbers).
#
# RESULT SHAPE (empirically confirmed across multiple projects, including
# claude-code-config — identical field names in every project, so this is
# the plugin's fixed schema, not per-project drift):
#   The session's final answer is a `StructuredOutput` tool_use call:
#     {"name":"StructuredOutput","input":{"findings":[
#       {"filePath":"...", "category":"...", "severity":"high|medium|...",
#        "confidence":0.95, "vulnerableCode":"...", "explanation":"...",
#        "fix":"..."}
#     ]}}
#   A session can carry >1 StructuredOutput call — observed live (a real
#   session, id fragment aaaa0004): the FIRST call failed native schema
#   validation ("Output does not match required schema: /findings: must be
#   array", is_error:true) and got auto-retried; the retry's tool_result was
#   "Structured output provided successfully". Taking the first call, or
#   summing all calls, would have misreported that specific session's real
#   answer (1 finding -> corrected to 0). This script always takes the LAST
#   StructuredOutput call whose matching tool_result is NOT is_error:true.
#   A session with zero accepted calls (still running, or aborted mid-review
#   — observed live, id fragment aaaa0005) is reported as "incomplete",
#   never as "clean" (0 findings) — conflating the two would silently hide
#   unfinished reviews.
#
# CLASSIFIER — why grep -l alone is not enough: this very task's own prompt
# quotes the marker string "Review this change for security vulnerabilities",
# so grep -l flags THIS session's own transcript (and any subagent forked
# from it) even though nothing here is a real review. Confirmed live: those
# false positives all have entrypoint "cli"/"claude-desktop" on their user
# lines, never "sdk-py". A file only counts as a genuine review session when
# jq finds a type=="user" line with entrypoint=="sdk-py" AND a plain-string
# message.content that STARTS WITH the marker — grep -l is only the cheap
# first-pass filter, this jq check is the actual gate.
#
# TWO INDEPENDENT SAFETY NETS, deliberately not merged into one:
#   - SEEN file: the correctness net. Every finding line ever written to OUT
#     has its dedup key "<session_id>#<index>" appended to SEEN in the SAME
#     call, same order -> OUT and SEEN are always line-for-line paired. This
#     is what makes re-running the whole scan from scratch safe (no
#     duplicates), and it's how --to-ledger recovers each row's original
#     per-finding index without storing it in OUT's public schema (see the
#     "OUT/SEEN pairing" note above --to-ledger below).
#   - STATE file: the performance net. Per-session {mtime, resolved,
#     findings_count}. On an unchanged, already-resolved session, the script
#     skips the (expensive, jq -s over a multi-MB transcript) re-parse
#     entirely. This is what keeps the SessionStart hook's ~2s time budget
#     from being blown on every session start once the corpus has been
#     scanned once. A --dry-run touches NEITHER file (see below).
#
# TRUST BOUNDARY (mirrors ledger-append-proposed.sh — do not "improve" this
# away): --to-ledger writes status:"proposed" ONLY, never "implemented", and
# never applies a fix. A human reviews and promotes. This script does not
# judge whether a finding is correct — it only makes sure a human CAN see it.
#
# Usage:
#   security-review-findings.sh [--since YYYY-MM-DD] [--project SUBSTR]
#                                [--dry-run] [--to-ledger]
#   security-review-findings.sh --ack SESSION_ID
#
# Exit codes: 0 normal completion (incl. nothing found). 1 bad usage/missing
# root. 2 missing dependency (jq).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail   # not -e: one malformed session file must not abort the scan

log()  { echo "[security-review-findings] $*" >&2; }
die()  { echo "[security-review-findings] FATAL: $*" >&2; exit "${2:-2}"; }

usage() {
  cat <<'EOF'
Usage: security-review-findings.sh [options]

Extracts findings from the automatic security-review sub-sessions recorded
under ~/.claude/projects/**/*.jsonl and writes them to a durable JSONL feed,
so a finding is no longer visible ONLY as an ephemeral chat notification to
whichever parent session happens to still be alive when the review finishes.

Options:
  --since YYYY-MM-DD   only consider findings whose OWN record timestamp is
                       on/after this date (never file mtime — a file's mtime
                       can be far newer than the review content it holds)
  --project SUBSTR     only scan project directories whose slug contains
                       SUBSTR (case-insensitive)
  --dry-run            compute and report only; OUT/STATE/SEEN files are not
                       touched. Combine with --to-ledger to preview that
                       write too (ledger-append-proposed.sh's own --dry-run)
  --ack SESSION_ID     mark one session's findings as human-reviewed;
                       excludes it from --to-ledger and from the SessionStart
                       hook's "unseen findings" count. Standalone action —
                       writes the ack and exits immediately, no scan runs.
  --to-ledger          additionally push unacked findings for the
                       claude-code-config project into improvement-ledger.json
                       as status:"proposed" (via ledger-append-proposed.sh).
                       Never promotes past "proposed" — see header comment.
  --root PATH          override the projects root (default: ~/.claude/projects)
  -h, --help           this text

Env overrides:
  CLAUDE_SEC_FINDINGS_ROOT             default: ~/.claude/projects
  CLAUDE_SEC_FINDINGS_OUT              default: ~/.claude/global-observation/security-review-findings.jsonl
  CLAUDE_SEC_FINDINGS_STATE            default: ~/.claude/global-observation/security-review-findings-state.json
  CLAUDE_SEC_FINDINGS_SEEN             default: ~/.claude/global-observation/security-review-findings-seen.txt
  CLAUDE_SEC_FINDINGS_ACK              default: ~/.claude/global-observation/security-review-findings-ack.txt
  CLAUDE_SEC_FINDINGS_LEDGER_PROJECT   default: claude-code-config (substring match against the project slug)
  CLAUDE_LEDGER_APPEND_SCRIPT          default: ~/.claude/scripts/ledger-append-proposed.sh
  CLAUDE_VAULT_SCRIPT                  default: ~/.claude/scripts/vault/vault.sh (IMP-219; derives the
                                        --to-ledger sourceProposal id — no vault/secret means that
                                        session's ledger write is skipped, never a raw session id)
EOF
}

command -v jq >/dev/null 2>&1 || die "jq not found"

GREP_BIN="/usr/bin/grep"
[[ -x "$GREP_BIN" ]] || GREP_BIN="$(command -v grep || true)"
[[ -n "$GREP_BIN" ]] || die "no usable grep found"

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

mtime_of() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

HOME_DIR="${HOME:?HOME not set}"
ROOT="${CLAUDE_SEC_FINDINGS_ROOT:-$HOME_DIR/.claude/projects}"
OUT="${CLAUDE_SEC_FINDINGS_OUT:-$HOME_DIR/.claude/global-observation/security-review-findings.jsonl}"
STATE="${CLAUDE_SEC_FINDINGS_STATE:-$HOME_DIR/.claude/global-observation/security-review-findings-state.json}"
SEEN="${CLAUDE_SEC_FINDINGS_SEEN:-$HOME_DIR/.claude/global-observation/security-review-findings-seen.txt}"
ACK="${CLAUDE_SEC_FINDINGS_ACK:-$HOME_DIR/.claude/global-observation/security-review-findings-ack.txt}"
LEDGER_PROJECT="${CLAUDE_SEC_FINDINGS_LEDGER_PROJECT:-claude-code-config}"
LEDGER_APPEND="${CLAUDE_LEDGER_APPEND_SCRIPT:-$HOME_DIR/.claude/scripts/ledger-append-proposed.sh}"
# IMP-219: the real session id must never reach the ledger's sourceProposal
# key as plaintext (it is a personal/machine identifier, same class as the
# paths/names the vault exists for) — `vault.sh token id` derives a stable,
# secret-keyed, non-reversible stand-in WITHOUT storing the session id
# itself anywhere (see --to-ledger below).
VAULT_SH="${CLAUDE_VAULT_SCRIPT:-$HOME_DIR/.claude/scripts/vault/vault.sh}"
MARKER='Review this change for security vulnerabilities'

SINCE=""
PROJECT_FILTER=""
DRY_RUN=0
ACK_ID=""
TO_LEDGER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)      SINCE="${2:?--since requires YYYY-MM-DD}"; shift 2 ;;
    --project)    PROJECT_FILTER="${2:?--project requires a substring}"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --ack)        ACK_ID="${2:?--ack requires a session_id}"; shift 2 ;;
    --to-ledger)  TO_LEDGER=1; shift ;;
    --root)       ROOT="${2:?--root requires a path}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown argument: $1 (see --help)" 1 ;;
  esac
done

if [[ -n "$SINCE" ]]; then
  [[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "--since must be YYYY-MM-DD, got: $SINCE" 1
fi

# ── --ack: standalone action, no scan ────────────────────────────────────────
if [[ -n "$ACK_ID" ]]; then
  mkdir -p "$(dirname "$ACK")"
  touch "$ACK"
  if "$GREP_BIN" -Fxq "$ACK_ID" "$ACK" 2>/dev/null; then
    log "already acked: $ACK_ID"
  else
    echo "$ACK_ID" >> "$ACK"
    log "acked: $ACK_ID"
  fi
  exit 0
fi

[[ -d "$ROOT" ]] || die "root not found: $ROOT" 1

mkdir -p "$(dirname "$OUT")" "$(dirname "$STATE")" "$(dirname "$SEEN")" "$(dirname "$ACK")"
[[ -f "$STATE" ]] || echo '{}' > "$STATE"
[[ -f "$SEEN"  ]] || : > "$SEEN"
[[ -f "$OUT"   ]] || : > "$OUT"
[[ -f "$ACK"   ]] || : > "$ACK"

# ── the extraction program: run once per candidate session file (slurped) ──
# See header comment for the retry/acceptance rationale.
read -r -d '' EXTRACT_JQ <<'JQEOF'
def is_user_review:
  select(.type=="user" and .entrypoint=="sdk-py")
  | (.message.content // "") as $c
  | ($c | type) == "string" and ($c | startswith("Review this change for security vulnerabilities"));

. as $lines
| ($lines | any(is_user_review)) as $is_review
| ($lines | map(.timestamp // null) | map(select(. != null)) | (if length == 0 then null else max end)) as $last_ts
| if ($is_review | not) then
    {is_review: false}
  else
    ( [ $lines[] | select(.type=="assistant") | . as $l
        | ($l.message.content // [])[]?
        | select(.type=="tool_use" and .name=="StructuredOutput")
        | {id: .id, ts: ($l.timestamp // null), findings: (.input.findings // null)}
      ] ) as $so_calls
    | ( [ $lines[] | select(.type=="user")
        | (.message.content // [])[]?
        | select(.type=="tool_result")
        | select((.is_error // false) != true)
        | .tool_use_id
      ] ) as $accepted_ids
    | ( $so_calls | map(select(.id as $i | ($accepted_ids | index($i)) != null and .findings != null)) ) as $accepted
    | if ($accepted | length) == 0 then
        {is_review: true, resolved: false, last_ts: $last_ts}
      else
        ($accepted[-1]) as $final
        | {is_review: true, resolved: true, ts: $final.ts, findings: $final.findings, last_ts: $last_ts}
      end
  end
JQEOF

# ── candidate files: cheap grep -l pre-filter, jq confirms below ────────────
CANDIDATES="$("$GREP_BIN" -rl "$MARKER" "$ROOT" --include='*.jsonl' 2>/dev/null || true)"

TMP_CAND="$(mktemp "${TMPDIR:-/tmp}/sec-findings-cand.XXXXXX")"
trap 'rm -f "$TMP_CAND" "${TMP_STATE:-}"' EXIT

N_FILES=0; N_NOTREVIEW=0; N_REVIEW=0; N_CLEAN=0; N_INCOMPLETE=0
N_SKIPPED_PROJECT=0; N_SKIPPED_WINDOW=0

in_window() {  # in_window TS -> 0 if within --since (or no --since set)
  local ts="$1"
  [[ -n "$SINCE" ]] || return 0
  [[ -n "$ts" ]] || return 0   # no timestamp to judge by -> don't exclude
  local d="${ts:0:10}"
  [[ "$d" > "$SINCE" || "$d" == "$SINCE" ]]
}

while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  N_FILES=$((N_FILES + 1))

  rel="${f#"$ROOT"/}"
  project="${rel%%/*}"
  session_id="$(basename "$f" .jsonl)"

  if [[ -n "$PROJECT_FILTER" ]]; then
    lp="$(lc "$project")"; lf="$(lc "$PROJECT_FILTER")"
    case "$lp" in
      *"$lf"*) ;;
      *) N_SKIPPED_PROJECT=$((N_SKIPPED_PROJECT + 1)); continue ;;
    esac
  fi

  mtime="$(mtime_of "$f")"
  cached="$(jq -c --arg sid "$session_id" '.[$sid] // null' "$STATE" 2>/dev/null)"
  cache_hit=0
  is_review="true"; resolved=""; ts=""; n_findings=0; last_ts=""

  if [[ "$cached" != "null" && -n "$cached" ]]; then
    c_mtime="$(printf '%s' "$cached" | jq -r '.mtime // ""')"
    if [[ "$c_mtime" == "$mtime" ]]; then
      cache_hit=1
      resolved="$(printf '%s' "$cached" | jq -r '.resolved')"
      ts="$(printf '%s' "$cached" | jq -r '.ts // ""')"
      last_ts="$(printf '%s' "$cached" | jq -r '.last_ts // ""')"
      n_findings="$(printf '%s' "$cached" | jq -r '.findings_count // 0')"
    fi
  fi

  if [[ "$cache_hit" -eq 0 ]]; then
    result="$(jq -s "$EXTRACT_JQ" "$f" 2>/dev/null || true)"
    if [[ -z "$result" ]]; then
      log "WARN: unparseable/empty session, skipped: $f"
      continue
    fi
    is_review="$(printf '%s' "$result" | jq -r '.is_review')"
    if [[ "$is_review" != "true" ]]; then
      N_NOTREVIEW=$((N_NOTREVIEW + 1))
      continue
    fi
    resolved="$(printf '%s' "$result" | jq -r '.resolved')"
    ts="$(printf '%s' "$result" | jq -r '.ts // ""')"
    last_ts="$(printf '%s' "$result" | jq -r '.last_ts // ""')"
    n_findings="$(printf '%s' "$result" | jq -r '(.findings // []) | length')"

    if [[ "$DRY_RUN" -eq 0 ]]; then
      TMP_STATE="$(mktemp "${TMPDIR:-/tmp}/sec-findings-state.XXXXXX")"
      jq --arg sid "$session_id" --argjson mtime "$mtime" --argjson resolved_b "$resolved" \
         --arg ts "$ts" --arg last_ts "$last_ts" --argjson n "$n_findings" '
        .[$sid] = {mtime: $mtime, resolved: $resolved_b,
                    ts: ($ts | if . == "" then null else . end),
                    last_ts: ($last_ts | if . == "" then null else . end),
                    findings_count: $n}
      ' "$STATE" > "$TMP_STATE" && mv "$TMP_STATE" "$STATE"
    fi

    if [[ "$resolved" == "true" && "$n_findings" -gt 0 ]]; then
      # emit candidate rows now, in this same (non-cache) pass — a cache HIT
      # never re-emits: its rows were already committed to OUT/SEEN the run
      # it was first resolved (that is the entire point of the SEEN dedup
      # net described in the header comment).
      printf '%s' "$result" | jq -c \
        --arg session_id "$session_id" --arg project "$project" --arg source "$f" '
        .ts as $ts
        | .findings | to_entries[]
        | {
            _k: ($session_id + "#" + (.key | tostring)),
            ts: $ts,
            session_id: $session_id,
            project: $project,
            file: (.value.filePath // null),
            severity: (.value.severity // null),
            category: (.value.category // null),
            summary: (.value.explanation // null),
            fix: (.value.fix // null),
            source: $source
          }
      ' >> "$TMP_CAND"
    fi
  fi

  N_REVIEW=$((N_REVIEW + 1))

  if [[ "$resolved" != "true" ]]; then
    if in_window "$last_ts"; then
      N_INCOMPLETE=$((N_INCOMPLETE + 1))
    else
      N_SKIPPED_WINDOW=$((N_SKIPPED_WINDOW + 1))
    fi
    continue
  fi

  if ! in_window "$ts"; then
    N_SKIPPED_WINDOW=$((N_SKIPPED_WINDOW + 1))
    continue
  fi

  if [[ "$n_findings" -eq 0 ]]; then
    N_CLEAN=$((N_CLEAN + 1))
  fi
  # n_findings > 0 was already queued into TMP_CAND above (fresh parse) or
  # was already committed to OUT/SEEN in a prior run (cache hit) — nothing
  # further to do here either way.

done <<< "$CANDIDATES"

# ── window-filter the candidate rows too (fresh-parse rows aren't yet
#    filtered by --since — do it once, here, uniformly) ─────────────────────
if [[ -n "$SINCE" && -s "$TMP_CAND" ]]; then
  TMP_CAND2="$(mktemp "${TMPDIR:-/tmp}/sec-findings-cand2.XXXXXX")"
  jq -c --arg since "$SINCE" 'select((.ts // "")[0:10] as $d | $d == "" or $d >= $since)' "$TMP_CAND" > "$TMP_CAND2"
  mv "$TMP_CAND2" "$TMP_CAND"
fi

N_CAND=$(wc -l < "$TMP_CAND" 2>/dev/null | tr -d ' ')
[[ -n "$N_CAND" ]] || N_CAND=0

SEEN_JSON="$(jq -R -s -c 'split("\n") | map(select(length > 0))' "$SEEN")"
NEW_ROWS=""
if [[ "$N_CAND" -gt 0 ]]; then
  NEW_ROWS="$(jq -c --argjson seen "$SEEN_JSON" 'select(._k as $k | ($seen | index($k)) == null)' "$TMP_CAND" 2>/dev/null || true)"
fi
N_NEW=0
[[ -z "$NEW_ROWS" ]] || N_NEW="$(printf '%s\n' "$NEW_ROWS" | jq -s 'length')"
N_DUP=$((N_CAND - N_NEW))

if [[ "$DRY_RUN" -eq 0 && "$N_NEW" -gt 0 ]]; then
  printf '%s\n' "$NEW_ROWS" | jq -c 'del(._k)' >> "$OUT"
  printf '%s\n' "$NEW_ROWS" | jq -r '._k' >> "$SEEN"
fi

log "files matched (grep pre-filter): $N_FILES   confirmed non-review (false positive): $N_NOTREVIEW"
log "review sessions confirmed: $N_REVIEW   clean(0 findings): $N_CLEAN   incomplete(no accepted result yet): $N_INCOMPLETE"
log "skipped(project filter): $N_SKIPPED_PROJECT   skipped(outside --since window): $N_SKIPPED_WINDOW"
log "finding candidates this run: $N_CAND   new: $N_NEW   duplicate(already recorded): $N_DUP"
if [[ "$N_NEW" -gt 0 ]]; then
  log "new findings by project | severity | category:"
  printf '%s\n' "$NEW_ROWS" | jq -r '[.project, (.severity // "?"), (.category // "?")] | @tsv' \
    | sort | uniq -c | while IFS= read -r line; do log "  $line"; done
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY-RUN — nothing written to $OUT / $STATE / $SEEN"
fi

# ── --to-ledger: push UNACKED claude-code-config findings as status:proposed ─
if [[ "$TO_LEDGER" -eq 1 ]]; then
  [[ -x "$LEDGER_APPEND" ]] || die "--to-ledger requires an executable ledger-append-proposed.sh at: $LEDGER_APPEND" 1

  OUT_LINES="$(cat "$OUT" 2>/dev/null || true)"
  SEEN_LINES="$(cat "$SEEN" 2>/dev/null || true)"
  if [[ "$DRY_RUN" -eq 1 && "$N_NEW" -gt 0 ]]; then
    # simulate what a real run would have persisted, so --to-ledger --dry-run
    # previews the SAME set a real run would push
    OUT_LINES="$(printf '%s%s\n' "${OUT_LINES:+$OUT_LINES$'\n'}" "$(printf '%s\n' "$NEW_ROWS" | jq -c 'del(._k)')")"
    SEEN_LINES="$(printf '%s%s\n' "${SEEN_LINES:+$SEEN_LINES$'\n'}" "$(printf '%s\n' "$NEW_ROWS" | jq -r '._k')")"
  fi

  OUT_N=0;  [[ -z "$OUT_LINES"  ]] || OUT_N=$(printf '%s\n'  "$OUT_LINES"  | wc -l | tr -d ' ')
  SEEN_N=0; [[ -z "$SEEN_LINES" ]] || SEEN_N=$(printf '%s\n' "$SEEN_LINES" | wc -l | tr -d ' ')
  if [[ "$OUT_N" -ne "$SEEN_N" ]]; then
    die "OUT/SEEN line-count mismatch ($OUT_N vs $SEEN_N) — the pairing invariant this script relies on to recover per-finding indices is broken; refusing --to-ledger rather than writing a wrong sourceProposal key. Do not hand-edit $OUT or $SEEN." 1
  fi

  ACK_JSON="$(jq -R -s -c 'split("\n") | map(select(length > 0))' "$ACK")"

  # pair OUT and SEEN line-for-line (see header comment), filter to the
  # ledger-target project + not-acked, tag each with its recovered index.
  PAIRED="$(paste -d '\t' <(printf '%s\n' "$SEEN_LINES") <(printf '%s\n' "$OUT_LINES") 2>/dev/null || true)"
  TO_SEND="$(printf '%s\n' "$PAIRED" | jq -R -c --arg proj "$LEDGER_PROJECT" --argjson ack "$ACK_JSON" '
    select(length > 0)
    | split("\t") as $parts
    | ($parts[0]) as $key
    | ($parts[1] | fromjson) as $row
    | select(($row.project // "") | ascii_downcase | test($proj | ascii_downcase; "i"))
    | select(($ack | index($row.session_id)) == null)
    | $row + {_idx: ($key | split("#") | .[-1])}
  ' 2>/dev/null || true)"

  N_TOSEND=0
  [[ -z "$TO_SEND" ]] || N_TOSEND="$(printf '%s\n' "$TO_SEND" | jq -s 'length')"

  if [[ "$N_TOSEND" -eq 0 ]]; then
    log "--to-ledger: no unacked findings for project substring '$LEDGER_PROJECT' — nothing to send"
  else
    log "--to-ledger: $N_TOSEND unacked finding(s) for project substring '$LEDGER_PROJECT'"
    SESSIONS="$(printf '%s\n' "$TO_SEND" | jq -r '.session_id' | sort -u)"
    N_SID_SKIPPED=0
    while IFS= read -r sid; do
      [[ -n "$sid" ]] || continue
      GROUP="$(printf '%s\n' "$TO_SEND" | jq -c --arg sid "$sid" '
        select(.session_id == $sid)
        | {
            finding: ._idx,
            title: ("security-review: " + (.file // "unknown file") + " [" + (.severity // "unknown") + "/" + (.category // "uncategorized") + "]"),
            category: (.category // "uncategorized"),
            riskLevel: (.severity // "unknown"),
            recommendation: (.fix // ""),
            evidence: (.summary // "")
          }
      ')"
      sid_token=""
      if [[ -f "$VAULT_SH" ]]; then
        sid_token="$(bash "$VAULT_SH" token id "$sid" 2>/dev/null || true)"
      fi
      if [[ -z "$sid_token" ]]; then
        # IMP-219: never name the real session id here, not even in a WARN
        # — same "kind-only reporting" convention as the vault gate's own
        # BLOCKED messages (never print the value the vault exists to
        # protect). Aggregated below into ONE summary line instead of one
        # per skipped session.
        N_SID_SKIPPED=$((N_SID_SKIPPED + 1))
        continue
      fi
      LEDGER_ARGS=(--proposal "security-review-$sid_token")
      [[ "$DRY_RUN" -eq 1 ]] && LEDGER_ARGS+=(--dry-run)
      printf '%s\n' "$GROUP" | "$LEDGER_APPEND" "${LEDGER_ARGS[@]}" \
        | while IFS= read -r line; do log "  ledger: $line"; done
    done <<< "$SESSIONS"
    if [[ "$N_SID_SKIPPED" -gt 0 ]]; then
      log "WARN: $N_SID_SKIPPED session(s) skipped — no vault/secret available to derive a token (run: scripts/vault/vault.sh init); fail-loud, no raw-session-id fallback"
    fi
  fi
fi

exit 0
