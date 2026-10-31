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
#   - SEEN file: the correctness net. Every finding line appended to OUT has
#     its dedup key "<session_id>#<index>" appended to SEEN right after it
#     (see PERSIST ORDER below). This is what makes re-running the scan safe
#     (no duplicates), and it is how --to-ledger recovers each row's original
#     per-finding index without storing it in OUT's public schema.
#   - STATE file: the performance net. Per-session {mtime, resolved,
#     findings_count}. On an unchanged, already-resolved session, the script
#     skips the (expensive, jq -s over a multi-MB transcript) re-parse
#     entirely. A cold scan of the real corpus took ~80 s (measured
#     2026-10-31), far above the hook's 2 s budget: the STATE cache is what
#     lets the scan converge over several SessionStart runs. A --dry-run
#     touches NEITHER file (see below).
#
# PERSIST ORDER (review findings 1 and 2, 2026-10-31) — a session is committed
# as a unit, and STATE only ever records what is already persisted:
#   1. its findings are staged in TMP_CAND after the parse;
#   2. its rows are committed: vendor upstream lines first, then OUT, then SEEN;
#   3. ONLY THEN its STATE entry is written (temp file + mv).
#   A kill (the hook runs this under `timeout 2`) before step 3 leaves the
#   session out of STATE, so the next run re-parses it and emits its rows. A
#   kill before step 2 leaves nothing behind. Upstream goes first because a
#   silently lost upstream line is never re-written, while a re-written one
#   only repeats. Per-session commits (not one batch at the end) keep the
#   progress of a killed run: a whole-run batch would never finish a cold scan
#   inside the hook's budget.
#   --since: a session with findings outside the window is neither staged nor
#   recorded in STATE, so a later unfiltered run still emits its rows.
#   RESIDUAL, not closed: a kill in the gap between the OUT append and the SEEN
#   append (microseconds) leaves OUT with rows SEEN does not list. No row is
#   lost. The next run logs a WARN "unpaired" at start, re-emits those rows
#   marked duplicate_of the orphan copy, and --to-ledger refuses (its
#   line-count check) until the feed is repaired by hand. Closing the gap needs
#   a lock plus a journal — an owner decision, not made here.
#
# DEDUP + UPSTREAM ROUTING (P-IMP-264, 2026-10-31; extends IMP-172 / IMP-207)
# Problem (plans/meta-proposal-2026-10-31.md § P-IMP-264): one finding reached the
# parent session 16 times in 5 paraphrased variants, and vendor-owned files
# (skills/synced/, plugins/) are overwritten on the next sync, so re-reporting them
# per session never leads to an action. This section changes the FEED side only:
# repeats stay in the record but stop counting as unacked; vendor-owned findings go
# once to an upstream list. There is NO path exclusion from the review trigger.
#
# Dedup key (computed by one perl process per commit, Digest::SHA):
#   sha1( normalized_path, lowercased category, sha1(lowercased summary) )
#   - normalized_path: backslashes -> "/", leading "./" dropped, "$HOME/" -> "~/"
#   - summary: the record's `summary` field (= the reviewer's `explanation`). `fix`
#     is not hashed.
#   - Why this key: the record has no diff hunk and no vulnerableCode excerpt
#     (fields: ts, session_id, project, file, severity, category, summary, fix,
#     source), so the reviewer's explanation is the only text that can tell two
#     findings apart. This key is the implementer's choice, not a fallback from
#     the P-IMP-264 spec.
#   - Measured consequence (2026-10-31, real corpus, cold scan: 66 new rows, 0 marked
#     duplicate_of): exact repeats collapse (regression case 11), but REWORDED
#     repeats do NOT. None of the 66 collapsed, so the paraphrase case the spec
#     targets is still counted as unacked.
#   - A looser key, (normalized_path, lowercased category), would collapse 3 of
#     those 66 rows (63 distinct pairs). It would also merge genuinely distinct
#     findings: one session has two findings on App/Korridor/Scene/HUDLayer.swift
#     (a precondition in WaveProgress.init, and basePercent called from
#     HUD.apply) with the same category. Choosing a looser key is an OPEN OWNER
#     DECISION. The key is deliberately NOT changed here.
#   - Commits are per session (see PERSIST ORDER), so the anchor ("first-seen") is the
#     first record COMMITTED for a key, not the earliest record of a whole run. Scan
#     order is file mtime, so this approximates chronology. If a later-committed
#     record is EARLIER than its anchor, it is marked as the repeat (one unacked row
#     either way). Before this rule, an earlier repeat arriving after a later
#     persisted row was never marked: both rows counted (measured by hand during the
#     2026-10-31 fix). An exact whole-run chronological batch would need a staging
#     file; not built.
#   - Added record fields (new rows only; old rows keep their shape):
#       dedup_key     sha1 hex of the key above
#       vendor        true when the path is vendor-owned (rules below)
#       duplicate_of  null, or "<first_session_id>@<first_ts>": the first-seen
#                     record of the same key that this repeat points at
#
# Window, non-vendor paths: a record is a duplicate when it lies within 7 days
#   (604800 s, either direction) of the first-seen record of its key. A repeat more
#   than 7 days away is counted again and becomes the new first-seen anchor.
# Vendor-owned paths: a record is a duplicate when ANY earlier record has the same
#   key (no window). So each vendor finding is written to the upstream list once.
#
# Vendor-owned paths: skills/synced/..., plugins/... (and .../.claude/skills/synced/...,
#   .../.claude/plugins/... in absolute form), plus every non-comment line of
#   live-only-manifest.txt. Its format (as documented in that file, shared with
#   scripts/deploy-to-live.sh): one shell glob per line, case match, relative to the
#   live install root; "#" and blank lines ignored; trailing slash optional; a glob
#   matches the path itself or anything below it. Only * and ? are supported: a
#   bracket expression makes the run fail loudly. The file is read ONLY when present;
#   a missing file is not an error. Default: <this script's dir>/../live-only-manifest.txt.
#   Override: CLAUDE_SEC_FINDINGS_MANIFEST.
#
# What a duplicate or vendor row does:
#   - Always appended to OUT and SEEN (logged, never dropped; the OUT/SEEN pairing
#     invariant still holds).
#   - Not counted as unacked by hooks/security-findings-check.sh (duplicates are
#     skipped; vendor rows are counted in the "(+N upstream ...)" token instead, and
#     that token is printed only when the upstream list has gained rows since the
#     reader last printed it — see the reader's header).
#   - Not sent by --to-ledger (a repeat would become a second proposal; a vendor
#     finding is not actionable in this repo).
#   - A first-seen vendor row is also appended as one line to the upstream list:
#     CLAUDE_SEC_FINDINGS_UPSTREAM, default ~/.claude/plans/upstream-findings.md
#     (runtime file, not tracked; created with a header on first write):
#       - <date> <path> — <category>: <one-line summary>
#
# Existing rows (no dedup_key) are keyed on the fly from their own fields, so a new
#   repeat of an old row is marked against it. Old rows are NEVER rewritten (the feed
#   is append-only); --dry-run reports how many existing rows are repeats.
# This does NOT touch the security-review plugin's own task notifications to the
#   parent session. Those come from the plugin, not from this feed.
#
# ARGV: the feed and the seen-set can grow without bound, so they are NEVER passed to
#   jq as --argjson/--arg values (the OS argument limit, ARG_MAX, is 1 MB on macOS).
#   They travel on stdin or in files. A jq failure is fatal, never an empty result.
#
# Usage:
#   security-review-findings.sh [--since YYYY-MM-DD] [--project SUBSTR]
#                                [--dry-run] [--to-ledger]
#   security-review-findings.sh --ack SESSION_ID
#
# Exit codes: 0 normal completion (incl. nothing found). 1 bad usage/missing
# root. 2 missing dependency (jq), or a fatal persist/parse failure.
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
  CLAUDE_SEC_FINDINGS_UPSTREAM         default: ~/.claude/plans/upstream-findings.md (P-IMP-264 vendor-owned list)
  CLAUDE_SEC_FINDINGS_MANIFEST         default: <script dir>/../live-only-manifest.txt (read only if present)
  CLAUDE_SEC_FINDINGS_LEDGER_PROJECT   default: claude-code-config (substring match against the project slug)
  CLAUDE_LEDGER_APPEND_SCRIPT          default: ~/.claude/scripts/ledger-append-proposed.sh
  CLAUDE_VAULT_SCRIPT                  default: ~/.claude/scripts/vault/vault.sh (IMP-219; derives the
                                        --to-ledger sourceProposal id — no vault/secret means that
                                        session's ledger write is skipped, never a raw session id)
  CLAUDE_SEC_FINDINGS_TEST_KILL_AT     regression tests only: SIGKILL this run at the named point,
                                        "after-parse:<session_id>" or "after-out:<session_id>"
                                        (see PERSIST ORDER in the header)
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
UPSTREAM="${CLAUDE_SEC_FINDINGS_UPSTREAM:-$HOME_DIR/.claude/plans/upstream-findings.md}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${CLAUDE_SEC_FINDINGS_MANIFEST:-$SCRIPT_DIR/../live-only-manifest.txt}"
VENDOR_PREFIXES=""   # filled from $MANIFEST by the dedup pass, only when that file exists
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

OUT_N_START=$(wc -l < "$OUT" | tr -d ' ')
SEEN_N_START=$(wc -l < "$SEEN" | tr -d ' ')
if [[ "$OUT_N_START" -ne "$SEEN_N_START" ]]; then
  log "WARN: feed and seen-set are unpaired (OUT $OUT_N_START rows, SEEN $SEEN_N_START keys): an earlier run was interrupted between its two appends. --to-ledger will refuse until the feed is repaired by hand; the scan continues (see PERSIST ORDER)."
fi

# ── temp files: all removed on a normal or error exit (a SIGKILL leaves them) ──
TMP_CAND=""; TMP_NEW=""; TMP_STATE=""; DRY_OUT=""; DRY_SEEN=""; NEW_ALL=""
TMP_CAND="$(mktemp "${TMPDIR:-/tmp}/sec-findings-cand.XXXXXX")" || die "cannot create temp file"
TMP_NEW="$(mktemp "${TMPDIR:-/tmp}/sec-findings-new.XXXXXX")" || die "cannot create temp file"
DRY_OUT="$(mktemp "${TMPDIR:-/tmp}/sec-findings-dryout.XXXXXX")" || die "cannot create temp file"
DRY_SEEN="$(mktemp "${TMPDIR:-/tmp}/sec-findings-dryseen.XXXXXX")" || die "cannot create temp file"
NEW_ALL="$(mktemp "${TMPDIR:-/tmp}/sec-findings-newall.XXXXXX")" || die "cannot create temp file"
cleanup_tmp() {
  local f
  for f in "$TMP_CAND" "$TMP_NEW" "$TMP_STATE" "$DRY_OUT" "$DRY_SEEN" "$NEW_ALL"; do
    [[ -n "$f" ]] && rm -f "$f"
  done
  return 0
}
trap cleanup_tmp EXIT

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

# ── P-IMP-264 dedup: mark program (input: annotated rows; output: {_ord: duplicate_of}) ──
# Persisted history rows (_new false) are visited first, in chronological order; they
# are never re-marked in a way that matters (the feed is append-only), but they set the
# anchors. New rows are then judged in chronological order. A row is a duplicate of
# the anchor of its key when they lie within 7 days of each other IN EITHER DIRECTION
# (|dt| <= window), or at any time for vendor rows. The anchor is the first record seen
# for the key. Rows without a parseable ts are never judged and never become anchors.
read -r -d '' MARK_JQ <<'MARKEOF' || true
def epoch:
  (.ts // "") as $ts
  | if $ts == "" then null
    else $ts | sub("\\.[0-9]+Z$"; "Z") | (try (strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) catch null)
    end;
def window_secs: 604800;
reduce (sort_by([(._new // false), epoch, ._ord])[]) as $r (
  {anchors: {}, marks: {}};
  ($r | epoch) as $t
  | if $t == null then .
    else
      $r.dedup_key as $k
      | .anchors[$k] as $a
      | if $a != null and (($r.vendor == true) or ((($t - $a.epoch) | fabs) <= window_secs)) then
          .marks[($r._ord | tostring)] = $a.ref
        else
          .anchors[$k] = {epoch: $t, ref: (($r.session_id // "?") + "@" + ($r.ts // "?"))}
        end
    end
)
| .marks
MARKEOF

# ── P-IMP-264 dedup: key + vendor flag per row (one perl call per commit) ──
# stdin: one row per line, fields separated by ASCII unit separator (\x1f):
#        file, category, summary. stdout: "<dedup_key>\t<0|1 vendor>" per row.
read -r -d '' PERL_KEYS <<'PERLEOF' || true
use strict;
use warnings;
use Digest::SHA qw(sha1_hex);
my $home = $ENV{HOME_NORM} // "";
# live-only-manifest.txt: one shell glob per line (case match, * and ? only),
# trailing slash optional, matches the path itself or anything below it.
sub glob_re {
    my ($glob) = @_;
    my $re = "";
    for my $ch (split //, $glob) {
        if ($ch eq '*')    { $re .= '.*' }
        elsif ($ch eq '?') { $re .= '.' }
        else               { $re .= quotemeta($ch) }
    }
    return $re;
}
my @patterns;
for my $raw (split /\n/, $ENV{VENDOR_PREFIXES} // "") {
    my $pf = $raw;
    $pf =~ s/^\s+//;
    $pf =~ s/\s+$//;
    next if $pf eq "" || $pf =~ /^#/;
    $pf =~ s{^\./}{};
    $pf =~ s{/+$}{};
    die "live-only manifest entry has a bracket expression (unsupported; use * or ?): $pf\n" if $pf =~ /[\[\]]/;
    push @patterns, glob_re($pf);
}
while (my $line = <STDIN>) {
    chomp $line;
    my ($file, $cat, $sum) = split /\x1f/, $line, 3;
    for my $v ($file, $cat, $sum) {
        $v = "" unless defined $v;
        $v =~ s/\s+/ /g;
        $v =~ s/^ //;
        $v =~ s/ $//;
    }
    my $path = $file;
    $path =~ s{\\}{/}g;
    $path =~ s{^\./}{};
    $path =~ s{^\Q$home\E/}{~/} if length $home;
    my $key = sha1_hex(join("\x1f", $path, lc $cat, sha1_hex(lc $sum)));
    my $vendor = 0;
    $vendor = 1 if $path =~ m{^(?:skills/synced/|plugins/)};
    $vendor = 1 if $path =~ m{/\.claude/(?:skills/synced/|plugins/)};
    # manifest globs: against the path as recorded, and against the part after
    # "/.claude/" for absolute or ~/.claude/ paths (the live install root)
    my $live_rel = $path;
    $live_rel =~ s{^.*/\.claude/}{};
    for my $re (@patterns) {
        if ($path =~ /^$re(?:\/.*)?\z/ || $live_rel =~ /^$re(?:\/.*)?\z/) { $vendor = 1; last; }
    }
    print "$key\t$vendor\n";
}
PERLEOF

# ── feed/seen views: what the dedup and --to-ledger passes see. A dry run also
#    sees the rows it has NOT persisted, so its counts match a real run. ──
history_stream() {
  cat "$OUT"
  if [[ "$DRY_RUN" -eq 1 ]]; then cat "$DRY_OUT"; fi
}
seen_stream() {
  cat "$SEEN"
  if [[ "$DRY_RUN" -eq 1 ]]; then cat "$DRY_SEEN"; fi
}
history_count() {
  history_stream | jq -R -s 'split("\n") | map(select(length > 0)) | length'
}

# dedup_annotate: reads history_stream + TMP_NEW, needs H_N (history row count).
# Sets ANNOTATED (JSON array of every row, with _ord/_new/dedup_key/vendor) and
# MARKS (object _ord -> duplicate_of ref). Rows travel on stdin, never argv.
dedup_annotate() {
  local rows_json row_tsv key_lines keys_json
  rows_json="$( { history_stream; cat "$TMP_NEW"; } \
    | jq -R -s -c --argjson h "$H_N" '
        split("\n") | map(select(length > 0) | fromjson)
        | to_entries | map(.value + {_ord: .key, _new: (.key >= $h)})')" || return 1
  row_tsv="$(printf '%s' "$rows_json" | jq -r '.[]
        | [(.file // ""), (.category // ""), (.summary // "")]
        | map(tostring | gsub("[\n\r\t\u001f]"; " ")) | join("\u001f")')" || return 1
  key_lines=""
  if [[ -n "$row_tsv" ]]; then
    key_lines="$(printf '%s\n' "$row_tsv" \
      | HOME_NORM="$HOME_DIR" VENDOR_PREFIXES="$VENDOR_PREFIXES" perl -MDigest::SHA=sha1_hex -e "$PERL_KEYS")" || return 1
  fi
  keys_json="$(printf '%s\n' "$key_lines" \
    | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {dedup_key: .[0], vendor: (.[1] == "1")})')" || return 1
  ANNOTATED="$(printf '%s\n%s\n' "$rows_json" "$keys_json" | jq -c -s '
        if (.[0] | length) != (.[1] | length) then error("dedup: row/key count mismatch")
        else [range(0; .[0] | length) as $i | .[0][$i] + .[1][$i]] end')" || return 1
  MARKS="$(printf '%s' "$ANNOTATED" | jq -c "$MARK_JQ")" || return 1
}

# write_upstream LINES: create the upstream list with a header if missing, then append.
write_upstream() {
  mkdir -p "$(dirname "$UPSTREAM")" || die "cannot create directory for $UPSTREAM"
  if [[ ! -f "$UPSTREAM" ]]; then
    cat > "$UPSTREAM" <<'UPSTREAM_HEADER' || die "cannot create $UPSTREAM"
# Upstream findings (vendor-owned paths)

Security-review findings on plugin-owned or synced files (`skills/synced/`,
`plugins/`, and paths in `live-only-manifest.txt`). Such a file is overwritten on
the next sync, so the fix belongs upstream or in the source repo, not in a local
edit. One line per dedup key, written once (P-IMP-264). Runtime file, not tracked.

UPSTREAM_HEADER
  fi
  printf '%s\n' "$1" >> "$UPSTREAM" || die "cannot append to $UPSTREAM"
}

# kill_point NAME — regression tests only. SIGKILLs this run at the named point, the
# same way the hook's `timeout` ends an overrun run (no EXIT trap, no cleanup).
kill_point() {
  if [[ -n "${CLAUDE_SEC_FINDINGS_TEST_KILL_AT:-}" && "$CLAUDE_SEC_FINDINGS_TEST_KILL_AT" == "$1" ]]; then
    log "TEST KILL at $1"
    kill -KILL $$
  fi
}

in_window() {  # in_window TS -> 0 if within --since (or no --since set)
  local ts="$1"
  [[ -n "$SINCE" ]] || return 0
  [[ -n "$ts" ]] || return 0   # no timestamp to judge by -> don't exclude
  local d="${ts:0:10}"
  [[ "$d" > "$SINCE" || "$d" == "$SINCE" ]]
}

# save_state_entry SID MTIME RESOLVED TS LAST_TS N — called ONLY after that session's
# rows are persisted (PERSIST ORDER). A dry run never writes STATE.
save_state_entry() {
  [[ "$DRY_RUN" -eq 0 ]] || return 0
  TMP_STATE="$(mktemp "${TMPDIR:-/tmp}/sec-findings-state.XXXXXX")" || die "cannot create temp state file"
  jq --arg sid "$1" --argjson mtime "$2" --argjson resolved_b "$3" \
     --arg ts "$4" --arg last_ts "$5" --argjson n "$6" '
    .[$sid] = {mtime: $mtime, resolved: $resolved_b,
                ts: ($ts | if . == "" then null else . end),
                last_ts: ($last_ts | if . == "" then null else . end),
                findings_count: $n}
  ' "$STATE" > "$TMP_STATE" && mv "$TMP_STATE" "$STATE" \
    || die "cannot record session state in $STATE"
}

# persist_pending SID — commits the rows staged in TMP_CAND (one session's findings).
# Order: upstream lines, OUT, (kill point), SEEN. Any failure is fatal (no STATE follows).
persist_pending() {
  local sid="$1" n_cand n_new seen_json
  [[ -s "$TMP_CAND" ]] || return 0
  n_cand=$(wc -l < "$TMP_CAND" | tr -d ' ')
  seen_json="$(seen_stream | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
    || die "cannot read seen-set: $SEEN"
  NEW_ROWS="$({ printf '%s\n' "$seen_json"; cat "$TMP_CAND"; } \
    | jq -c -s '.[0] as $seen | .[1:][] | select(._k as $k | ($seen | index($k)) == null)')" \
    || die "cannot compute new rows for session $sid"
  n_new=0
  if [[ -n "$NEW_ROWS" ]]; then n_new=$(printf '%s\n' "$NEW_ROWS" | jq -s 'length') || die "cannot count new rows"; fi
  N_CAND=$((N_CAND + n_cand)); N_NEW=$((N_NEW + n_new)); N_DUP=$((N_DUP + n_cand - n_new))
  : > "$TMP_CAND"
  [[ "$n_new" -gt 0 ]] || return 0

  printf '%s\n' "$NEW_ROWS" >> "$NEW_ALL" || die "cannot write temp file"
  printf '%s\n' "$NEW_ROWS" > "$TMP_NEW" || die "cannot write temp file"
  H_N="$(history_count)" || die "cannot count rows in feed: $OUT"
  dedup_annotate || die "dedup (P-IMP-264) failed for session $sid: refusing to write rows without dedup marks"
  n_dup_new="$(printf '%s' "$MARKS" | jq --argjson h "$H_N" '[keys[] | tonumber | select(. >= $h)] | length')" \
    || die "dedup count failed (new rows)"
  N_NEW_DUP=$((N_NEW_DUP + n_dup_new))
  NEW_FINAL="$({ printf '%s\n' "$MARKS"; printf '%s\n' "$ANNOTATED"; } \
    | jq -c -s '.[0] as $m | .[1][] | select(._new == true)
                | . + {duplicate_of: ($m[(._ord | tostring)] // null)}')" \
    || die "dedup annotation failed (new rows)"
  UPSTREAM_LINES="$(printf '%s\n' "$NEW_FINAL" | jq -r '
    select(.vendor == true and .duplicate_of == null)
    | "- " + ((.ts // "?") | .[0:10]) + " " + (.file // "?") + " — " + (.category // "uncategorized")
      + ": " + ((.summary // "") | gsub("\\s+"; " ") | .[0:160])')" \
    || die "upstream line build failed"
  n_up=0
  if [[ -n "$UPSTREAM_LINES" ]]; then n_up=$(printf '%s\n' "$UPSTREAM_LINES" | wc -l | tr -d ' '); fi
  N_UPSTREAM_NEW=$((N_UPSTREAM_NEW + n_up))

  if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ -n "$UPSTREAM_LINES" ]]; then write_upstream "$UPSTREAM_LINES"; fi
    printf '%s\n' "$NEW_FINAL" | jq -c 'del(._k, ._ord, ._new)' >> "$OUT" || die "cannot append to feed: $OUT"
    kill_point "after-out:$sid"
    printf '%s\n' "$NEW_FINAL" | jq -r '._k' >> "$SEEN" || die "cannot append to seen-set: $SEEN"
  else
    printf '%s\n' "$NEW_FINAL" | jq -c 'del(._k, ._ord, ._new)' >> "$DRY_OUT" || die "dry-run buffer write failed"
    printf '%s\n' "$NEW_FINAL" | jq -r '._k' >> "$DRY_SEEN" || die "dry-run buffer write failed"
  fi
}

# ── startup: the upstream manifest, and the dedup view of the EXISTING feed ──
if [[ -e "$MANIFEST" ]]; then
  [[ -r "$MANIFEST" ]] || die "live-only manifest exists but is not readable: $MANIFEST" 1
  VENDOR_PREFIXES="$(cat "$MANIFEST")" || die "cannot read live-only manifest: $MANIFEST" 1
fi
: > "$TMP_NEW"
H_N="$(history_count)" || die "cannot count rows in feed: $OUT"
ANNOTATED=""
MARKS="{}"
dedup_annotate || die "dedup (P-IMP-264) failed: refusing to write rows without dedup marks"
N_HIST_DUP="$(printf '%s' "$MARKS" | jq '[keys[]] | length')" || die "dedup count failed (history)"
HIST_N_START="$H_N"   # H_N is overwritten by each commit; the summary needs the start-of-run count

# ── candidate files: cheap grep -l pre-filter, jq confirms below ────────────
# Scan order = file mtime ascending, then path. Per-session commits make the first
# committed record the dedup anchor, so an earlier-finished review is committed first
# (approximates chronological order; grep order would be filesystem-dependent).
CANDIDATES="$("$GREP_BIN" -rl "$MARKER" "$ROOT" --include='*.jsonl' 2>/dev/null \
  | while IFS= read -r cand_path; do printf '%s\t%s\n' "$(mtime_of "$cand_path")" "$cand_path"; done \
  | sort -t $'\t' -k1,1n -k2,2 | cut -f2- || true)"

N_FILES=0; N_NOTREVIEW=0; N_REVIEW=0; N_CLEAN=0; N_INCOMPLETE=0
N_SKIPPED_PROJECT=0; N_SKIPPED_WINDOW=0
N_CAND=0; N_NEW=0; N_DUP=0; N_NEW_DUP=0; N_UPSTREAM_NEW=0
NEW_ROWS=""; NEW_FINAL=""; UPSTREAM_LINES=""; n_up=0

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

    # --since: a session whose findings fall outside the window is neither staged
    # nor recorded, so a later unfiltered run still emits its rows (finding 2).
    record=1
    if [[ "$n_findings" -gt 0 ]] && ! in_window "$ts"; then record=0; fi
    if [[ "$record" -eq 1 && "$resolved" == "true" && "$n_findings" -gt 0 ]]; then
      # stage this session's candidate rows; a cache HIT never re-emits (its rows were
      # committed the run it was first resolved — the SEEN net, see header comment)
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
      ' >> "$TMP_CAND" || die "cannot stage findings of session $session_id"
    fi
    kill_point "after-parse:$session_id"
    # PERSIST ORDER: rows first, then this session's STATE entry (never the reverse)
    persist_pending "$session_id"
    if [[ "$record" -eq 1 ]]; then
      save_state_entry "$session_id" "$mtime" "$resolved" "$ts" "$last_ts" "$n_findings"
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
  # n_findings > 0 was already committed to OUT/SEEN in this run (fresh parse)
  # or in a prior run (cache hit) — nothing further to do here either way.

done <<< "$CANDIDATES"

log "files matched (grep pre-filter): $N_FILES   confirmed non-review (false positive): $N_NOTREVIEW"
log "review sessions confirmed: $N_REVIEW   clean(0 findings): $N_CLEAN   incomplete(no accepted result yet): $N_INCOMPLETE"
log "skipped(project filter): $N_SKIPPED_PROJECT   skipped(outside --since window): $N_SKIPPED_WINDOW"
log "finding candidates this run: $N_CAND   new: $N_NEW   duplicate(already recorded): $N_DUP"
log "dedup (P-IMP-264): new rows marked duplicate_of: $N_NEW_DUP (7-day window; logged, not counted as unacked)"
log "dedup (P-IMP-264): existing feed rows that are repeats: $N_HIST_DUP of $HIST_N_START (reported, not rewritten: feed is append-only)"
log "dedup (P-IMP-264): first-seen vendor-owned rows for $UPSTREAM: $N_UPSTREAM_NEW"
if [[ "$N_NEW" -gt 0 ]]; then
  log "new findings by project | severity | category:"
  jq -r '[.project, (.severity // "?"), (.category // "?")] | @tsv' "$NEW_ALL" \
    | sort | uniq -c | while IFS= read -r line; do log "  $line"; done
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY-RUN — nothing written to $OUT / $STATE / $SEEN"
fi

# ── --to-ledger: push UNACKED claude-code-config findings as status:proposed ─
if [[ "$TO_LEDGER" -eq 1 ]]; then
  [[ -x "$LEDGER_APPEND" ]] || die "--to-ledger requires an executable ledger-append-proposed.sh at: $LEDGER_APPEND" 1

  OUT_LINES="$(history_stream)"
  SEEN_LINES="$(seen_stream)"
  OUT_N=0;  [[ -z "$OUT_LINES"  ]] || OUT_N=$(printf '%s\n'  "$OUT_LINES"  | wc -l | tr -d ' ')
  SEEN_N=0; [[ -z "$SEEN_LINES" ]] || SEEN_N=$(printf '%s\n' "$SEEN_LINES" | wc -l | tr -d ' ')
  if [[ "$OUT_N" -ne "$SEEN_N" ]]; then
    die "OUT/SEEN line-count mismatch ($OUT_N vs $SEEN_N) — the pairing invariant this script relies on to recover per-finding indices is broken; refusing --to-ledger rather than writing a wrong sourceProposal key. Do not hand-edit $OUT or $SEEN." 1
  fi

  # pair OUT and SEEN line-for-line (see header comment), filter to the
  # ledger-target project + not-acked, tag each with its recovered index.
  # The ack list travels as a file (--rawfile), never as an argv value.
  TO_SEND=""
  if [[ "$OUT_N" -gt 0 ]]; then
    PAIRED="$(paste -d '\t' <(printf '%s\n' "$SEEN_LINES") <(printf '%s\n' "$OUT_LINES"))" \
      || die "cannot pair feed rows with seen keys"
    TO_SEND="$(printf '%s\n' "$PAIRED" | jq -n -R -c --rawfile ackfile "$ACK" --arg proj "$LEDGER_PROJECT" '
      ($ackfile | split("\n") | map(select(length > 0))) as $ack
      | inputs
      | select(length > 0)
      | split("\t") as $parts
      | ($parts[0]) as $key
      | ($parts[1] | fromjson) as $row
      | select(($row.project // "") | ascii_downcase | test($proj | ascii_downcase; "i"))
      | select(($ack | index($row.session_id)) == null)
      | select(($row.duplicate_of // "") == "")
      | select(($row.vendor // false) != true)
      | $row + {_idx: ($key | split("#") | .[-1])}
    ')" || die "cannot select unacked rows for --to-ledger"
  fi

  N_TOSEND=0
  [[ -z "$TO_SEND" ]] || N_TOSEND="$(printf '%s\n' "$TO_SEND" | jq -s 'length')" || die "cannot count --to-ledger rows"

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
