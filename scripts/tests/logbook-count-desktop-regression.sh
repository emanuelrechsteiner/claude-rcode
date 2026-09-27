#!/usr/bin/env bash
# Regression suite for the S6 desktop step of
# scheduled-tasks/daily-docs/bin/logbook-count.sh (IMP-223).
#
# Why this suite exists: 5 of the 13 daily-docs fails between 2026-08-27 and
# 2026-09-26 (runs of 09-10, 09-11, 09-18, 09-20, 09-21) ended with
#   ABORT(16): S6-Desktop-jq scheiterte (rc=1) ...
#   jq: parse error: Invalid \uXXXX\uXXXX surrogate pair escape at line N, column 1609
# One desktop audit.jsonl line carrying a lone UTF-16 high surrogate escape made
# jq reject the whole batch, so the whole run aborted. The step now reads line by
# line, counts unparseable lines (unparseable=N in the receipt), and only aborts
# when the scan is genuinely incomplete: unreadable file, or more than
# DESK_UNPARSEABLE_MAX_PCT (1%) of the scanned lines unparseable.
#
# Isolation: every case runs against a scratch $HOME under $TMPDIR (desktop
# session dir, empty transcript dir, epoch cache placing signals/transcripts in
# the future) and sets LOGBOOK_STOP_AFTER_S6=1, the script's test hook that exits
# 99 right after the S6 receipt (99, never 0: a leaked hook variable must not fake
# a passing run). Nothing under the real ~/.claude is read or written.
#
# Also covered: the known-tool membership test of S3 and S6 (cases k, l — the
# separator used to be raw NUL bytes, which bash drops) and the in-window share of
# unparseable lines (cases m, n — the corpus-wide share alone dilutes a bad day).
#
# Usage: bash scripts/tests/logbook-count-desktop-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# LOGBOOK_COUNT_SH: optional override, e.g. to prove the suite fails against the pre-fix script.
LBC="${LOGBOOK_COUNT_SH:-$SCRIPT_DIR/../../scheduled-tasks/daily-docs/bin/logbook-count.sh}"
[ -f "$LBC" ] || { echo "logbook-count.sh not found: $LBC" >&2; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf '  [%s] %s\n' "$1" "$2"; }
check(){ # check <name> <expected> <got>
  if [ "$2" = "$3" ]; then ok; else bad "$1" "expected='$2' got='$3'"; fi
}
has(){ # has <name> <needle> <file>
  if /usr/bin/grep -aqF -- "$2" "$3"; then ok; else bad "$1" "missing '$2' in: $(tr '\n' '|' < "$3" | cut -c1-600)"; fi
}

# pwd -P: on macOS $TMPDIR lives under /var -> /private/var; the script's root
# guard (ABORT 19) rejects symlinked roots, so every path here is resolved.
ROOT=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/lbc-desk-reg.XXXXXX")" && pwd -P)
trap 'chmod -R u+rwX "$ROOT" 2>/dev/null; rm -rf "$ROOT"' EXIT

DAY=2026-09-20
VALID='{"timestamp":"2026-09-20T10:00:00.123Z","session_id":"s1","message":{"content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":"/abs/regression/x.txt"}}]}}'
OUTWIN='{"timestamp":"2026-09-01T10:00:00.000Z","message":{"content":[{"type":"text","text":"old"}]}}'
# Lone high surrogate followed by a marker — the shape measured in the real data.
LONE='{"timestamp":"2026-09-20T11:00:00.000Z","message":{"content":[{"type":"tool_result","content":"abc\ud835[TRUNCATED]"}]}}'

# setup_case <name> -> fresh scratch HOME, roots file and epoch cache; sets H/DESKDIR/ENVV.
setup_case() {
  local c="$ROOT/$1"
  H="$c/home"; DESKDIR="$H/Library/Application Support/Claude/local-agent-mode-sessions"
  mkdir -p "$H/.claude/projects" "$H/.claude/global-observation/archives" "$DESKDIR" "$c/repo" "$c/tmp"
  : > "$c/repo/sentinel"
  printf '%s\t%s\n' "$c/repo" "$c/repo/sentinel" > "$c/roots.txt"
  printf 'signals\t2099-01-01\ntranskripte\t2099-01-01\ndesktop\t2000-01-01\n' > "$c/epochs.tsv"
  CASE_DIR="$c"
}
# run_case -> runs the script, sets RC and ERR (stderr file).
run_case() {
  ERR="$CASE_DIR/stderr.txt"
  HOME="$H" TMPDIR="$CASE_DIR/tmp" TZ=Europe/Berlin \
    LOGBOOK_ROOTS="$CASE_DIR/roots.txt" LOGBOOK_EPOCH_CACHE="$CASE_DIR/epochs.tsv" \
    LOGBOOK_STOP_AFTER_S6=1 LOGBOOK_KEEP="${KEEP:-}" bash "$LBC" "$DAY" > "$CASE_DIR/stdout.txt" 2> "$ERR"
  RC=$?
}
# audit <session> <valid-count> [extra line...] -> writes an audit.jsonl
audit() {
  local d="$DESKDIR/$1"; local n="$2"; shift 2
  mkdir -p "$d"; : > "$d/audit.jsonl"
  local i; for ((i=0; i<n; i++)); do printf '%s\n' "$VALID" >> "$d/audit.jsonl"; done
  local x; for x in "$@"; do printf '%s\n' "$x" >> "$d/audit.jsonl"; done
  AUDIT="$d/audit.jsonl"
}

# ── (a) one lone-surrogate line among 199 valid ones (0.5%) -> exit 0, unparseable=1
setup_case a; audit s1 198 "$LONE" "$OUTWIN"
run_case
check "a/exit99-stop-hook" 99 "$RC"
has "a/receipt-unparseable" "unparseable=1 " "$ERR"
has "a/receipt-lines" "lines=200 " "$ERR"
has "a/valid-records-still-counted" "raw_paths=1 " "$ERR"
has "a/warn-names-file-and-line" "audit.jsonl:199" "$ERR"
has "a/reached-stop-hook" "STOP after S6" "$ERR"

# ── (b) an unreadable audit file -> ABORT(16)
setup_case b; audit s1 5; audit s2 5; chmod 000 "$AUDIT"
run_case
check "b/exit16" 16 "$RC"
has "b/abort16-unreadable" "ABORT(16): S1b/S6 desktop scan INCOMPLETE — find_rc=0 unreadable=1 of 2" "$ERR"

# ── (c) 2 unparseable of 100 lines (2% > 1%) -> ABORT(16)
setup_case c; audit s1 98 "$LONE" "$LONE"
run_case
check "c/exit16" 16 "$RC"
has "c/abort16-threshold" "ABORT(16): S6 desktop scan INCOMPLETE — unparseable=2 of 100 lines exceeds 1%" "$ERR"

# ── (d) all lines valid -> exit 0, unparseable=0
setup_case d; audit s1 3 "$OUTWIN"; audit s2 2
run_case
check "d/exit99-stop-hook" 99 "$RC"
has "d/receipt-unparseable0" "lines=6 unparseable=0 " "$ERR"
has "d/raw-paths" "raw_paths=1 " "$ERR"
if /usr/bin/grep -aq '^WARN S6' "$ERR"; then bad "d/no-warn" "WARN printed with 0 unparseable"; else ok; fi

# ── (e) boundary: exactly 1% (1 of 100) passes
setup_case e; audit s1 99 "$LONE"
run_case
check "e/exit99-at-exactly-1pct" 99 "$RC"
has "e/receipt" "lines=100 unparseable=1 " "$ERR"

# ── (f) file WITHOUT trailing newline before another file: a raw concatenation
#        (e.g. `jq -R` over several files) glues the two lines into one
#        "unparseable" line; the pre-pass re-terminates every line.
setup_case f; audit s1 1; printf '%s' "$VALID" > "$AUDIT"; audit s2 1
run_case
check "f/exit99-stop-hook" 99 "$RC"
has "f/no-glue" "lines=2 unparseable=0 " "$ERR"

# ── (g) a PARSEABLE non-object line is not a parse problem -> still ABORT(16)
#        (the event filter errors; fail-loud behaviour of the old step preserved)
setup_case g; audit s1 3 '[1,2,3]'
run_case
check "g/exit16" 16 "$RC"
has "g/abort16-jq" "ABORT(16): S6 desktop jq FAILED" "$ERR"

# ── (h) blank lines are neither scanned nor unparseable
setup_case h; audit s1 2 "" "   "
run_case
check "h/exit99-stop-hook" 99 "$RC"
has "h/blank-ignored" "lines=2 unparseable=0 " "$ERR"

# ── (i) the pre-pass itself fails (a DIRECTORY named audit.jsonl passes the -r
#        census but cannot be read as a file) -> ABORT(16), never a silent skip
setup_case i; audit s1 3; mkdir -p "$DESKDIR/s2/audit.jsonl"
run_case
check "i/exit16" 16 "$RC"
has "i/abort16-prepass" "ABORT(16): S6 desktop pre-pass FAILED" "$ERR"

# ── (j) multibyte UTF-8 straddling a 4 KiB boundary survives byte-exact
#        (jq -R corrupted exactly this on the real data: "€" -> U+FFFD)
#        Fixture chosen by measurement: with this exact line prefix, 2500 x "€a"
#        is corrupted by `jq -R 'fromjson'` (jq-1.7.1 splits raw lines at ~4095-byte
#        seams), while plain `jq` keeps it intact. (2500 x "€" happens to align and is NOT.)
setup_case j
EUROS=$(for _ in $(seq 1 2500); do printf '€a'; done)
MB="{\"timestamp\":\"2026-09-20T10:00:00.000Z\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"t2\",\"name\":\"Write\",\"input\":{\"file_path\":\"/abs/regression/${EUROS}.txt\"}}]}}"
audit s1 0 "$MB"
KEEP=1 run_case
check "j/exit99-stop-hook" 99 "$RC"
has "j/receipt" "lines=1 unparseable=0 raw_paths=1 " "$ERR"
QD=$(/usr/bin/find "$CASE_DIR/tmp" -name qd_raw.txt 2>/dev/null | head -1)
if [ -n "$QD" ]; then
  check "j/euro-intact" "/abs/regression/${EUROS}.txt" "$(cat "$QD")"
else bad "j/euro-intact" "qd_raw.txt not kept (LOGBOOK_KEEP)"; fi

# kept <file-name> -> path of that file in the kept $WORK of the current case
kept() { /usr/bin/find "$CASE_DIR/tmp" -name "$1" 2>/dev/null | head -1; }
# sc_of <events.jsonl> <tool> -> the sc array jq emitted for that tool, compact
sc_of() { jq -c --arg n "$2" '.tu[] | select(.n==$n) | .sc' "$1" | head -1; }
# Three tools in one record: Write (known), and two unknown names that are
# substrings of the known names run together ("Writ" of "Write", "EditWrite" of
# "Edit"+"Write" — exactly what a dropped separator produces). The unknown ones
# carry their path under a key the map does not declare, so only sc can find it.
TOOLS='[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":"/abs/regression/known.txt"}},{"type":"tool_use","id":"t2","name":"Writ","input":{"target":"/abs/regression/writ.txt"}},{"type":"tool_use","id":"t3","name":"EditWrite","input":{"target":"/abs/regression/editwrite.txt"}}]'

# ── (k) S6: known tool recognised (sc empty), substring-named unknown tools NOT
#        recognised (sc collected, path lands in the unknown bucket)
setup_case k
audit s1 0 "{\"timestamp\":\"2026-09-20T10:00:00.000Z\",\"session_id\":\"s1\",\"message\":{\"content\":$TOOLS}}"
KEEP=1 run_case
check "k/exit99-stop-hook" 99 "$RC"
DEV=$(kept devents.jsonl); UQD=$(kept unknown_qd.tsv)
if [ -n "$DEV" ] && [ -n "$UQD" ]; then
  check "k/S6-known-Write-no-sc" "[]" "$(sc_of "$DEV" Write)"
  check "k/S6-unknown-Writ-sc" '["/abs/regression/writ.txt"]' "$(sc_of "$DEV" Writ)"
  check "k/S6-unknown-EditWrite-sc" '["/abs/regression/editwrite.txt"]' "$(sc_of "$DEV" EditWrite)"
  has "k/S6-bucket-Writ" "Writ"$'\t'"/abs/regression/writ.txt" "$UQD"
  has "k/S6-bucket-EditWrite" "EditWrite"$'\t'"/abs/regression/editwrite.txt" "$UQD"
  if /usr/bin/grep -aq "^Write"$'\t' "$UQD"; then bad "k/S6-known-not-in-bucket" "Write in unknown bucket"; else ok; fi
else bad "k/kept-files" "devents.jsonl/unknown_qd.tsv not kept (LOGBOOK_KEEP)"; fi

# ── (l) S3 (CLI transcripts): the same three tools, same expectations
setup_case l
printf 'signals\t2099-01-01\ntranskripte\t2000-01-01\ndesktop\t2000-01-01\n' > "$CASE_DIR/epochs.tsv"
mkdir -p "$H/.claude/projects/-proj"
printf '%s\n' "{\"timestamp\":\"2026-09-20T10:00:00.000Z\",\"sessionId\":\"c1\",\"cwd\":\"/abs/regression\",\"message\":{\"content\":$TOOLS}}" \
  > "$H/.claude/projects/-proj/c1.jsonl"
KEEP=1 run_case
check "l/exit99-stop-hook" 99 "$RC"
has "l/S3b-two-unknown-tools" "unknown_tools=2 unknown_paths=2" "$ERR"
EV=$(kept events.jsonl); UQT=$(kept unknown_qt.tsv)
if [ -n "$EV" ] && [ -n "$UQT" ]; then
  check "l/S3-known-Write-no-sc" "[]" "$(sc_of "$EV" Write)"
  check "l/S3-unknown-Writ-sc" '["/abs/regression/writ.txt"]' "$(sc_of "$EV" Writ)"
  check "l/S3-unknown-EditWrite-sc" '["/abs/regression/editwrite.txt"]' "$(sc_of "$EV" EditWrite)"
  has "l/S3-bucket-Writ" "Writ"$'\t'"/abs/regression/writ.txt" "$UQT"
else bad "l/kept-files" "events.jsonl/unknown_qt.tsv not kept (LOGBOOK_KEEP)"; fi

# Window of $DAY under TZ=Europe/Berlin: [2026-09-19T22:00:00Z, 2026-09-20T22:00:00Z)
LONE_AT(){ printf '{"timestamp":"%s","message":{"content":[{"type":"tool_result","content":"abc\\ud835[TRUNCATED]"}]}}' "$1"; }
BROKEN_AT(){ printf '{"timestamp":"%s","message":{"content":[{"type":"text","text":"cut' "$1"; }

# ── (m) scaled-down real shape: the bad lines all fall on the counted day. Corpus
#        share 3/453 = 0.66% (passes), window share 3/53 = 5.7% -> ABORT(16).
#        One bad line is not even JSON (timestamp read from the raw prefix), one sits
#        exactly on WSTART (inclusive bound).
setup_case m
audit s1 50 "$(LONE_AT 2026-09-20T11:00:00.000Z)" "$(BROKEN_AT 2026-09-19T22:00:00.000Z)" "$(LONE_AT 2026-09-20T12:00:00Z)"
audit s2 0; for _ in $(seq 1 400); do printf '%s\n' "$OUTWIN" >> "$AUDIT"; done
run_case
check "m/exit16" 16 "$RC"
has "m/abort16-window" "ABORT(16): S6 desktop scan INCOMPLETE — in-window unparseable=3 of 53 window lines [2026-09-19T22:00:00Z,2026-09-20T22:00:00Z) exceeds 1%" "$ERR"
has "m/corpus-figure-kept" "corpus: 3 of 453" "$ERR"
has "m/warn-window" "in window: 3 of 53, undated: 0" "$ERR"

# ── (n) same volumes, bad lines OUTSIDE the window (one exactly on WEND, exclusive)
#        plus one undated garbage line -> both shares hold, run continues
setup_case n
audit s1 50 "$(LONE_AT 2026-09-01T11:00:00.000Z)" "$(BROKEN_AT 2026-09-20T22:00:00.500Z)" "$(LONE_AT 2026-09-21T09:00:00.000Z)" "not json at all"
audit s2 0; for _ in $(seq 1 400); do printf '%s\n' "$OUTWIN" >> "$AUDIT"; done
run_case
check "n/exit99-stop-hook" 99 "$RC"
has "n/receipt-corpus" "lines=454 unparseable=4 " "$ERR"
has "n/receipt-window" "window_lines=50 window_unparseable=0 undated_unparseable=1" "$ERR"

TOTAL=$((PASS+FAIL))
echo "logbook-count-desktop-regression: $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ]
