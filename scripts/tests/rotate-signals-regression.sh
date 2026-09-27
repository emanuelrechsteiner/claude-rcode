#!/usr/bin/env bash
# Regression suite for scripts/rotate-signals.sh — IMP-221 empty shards.
#
# Why this suite exists: a day with zero signals produced NO archive shard, and
# daily-docs' logbook-count.sh treats a missing shard inside the source epoch
# as ABORT(5) "archive MISSING". Result: 8 of 13 failed daily-docs runs
# (09-12..09-25), one missing day blocking two runs (D-1 and D). The fix makes
# the producer write an explicit, valid, content-empty gz for every zero-signal
# date in (anchor, yesterday], which reaches the consumer's designed
# empty_verified state instead.
#
# This suite works EXCLUSIVELY in a scratch dir under $TMPDIR (env overrides
# CLAUDE_SIGNALS_FILE / CLAUDE_ARCHIVE_DIR / CLAUDE_ALERTS_FILE) and never
# touches ~/.claude/global-observation/.
#
# The wall clock is read ONCE: every fixture date derives from $TODAY and every
# run pins it via the test-only CLAUDE_ROTATE_TODAY, so a run across midnight
# UTC cannot flake. Later sections cover review findings #4 (continuity proof
# before the empty-shard fill), #13/#14 (every failure path: alert + documented
# exit code) and #6 (LC_ALL=C on every sort).
#
# Usage: bash scripts/tests/rotate-signals-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ROT_UNDER_TEST: negative control — point the suite at another version.
ROT="${ROT_UNDER_TEST:-$SCRIPT_DIR/../rotate-signals.sh}"
[ -f "$ROT" ] || { echo "rotate-signals.sh not found: $ROT" >&2; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf '  [%s] %s\n' "$1" "$2"; }
check(){ # check <name> <expected> <got>
  if [ "$2" = "$3" ]; then ok; else bad "$1" "expected='$2' got='$3'"; fi
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rotate-signals-reg.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT

TODAY=$(date -u +%Y-%m-%d)   # the ONLY wall-clock read in this suite
day() { jq -rn --arg t "$TODAY" --argjson n "$1" '($t+"T00:00:00Z"|fromdateiso8601)+($n*86400)|strftime("%Y-%m-%d")'; }
D1=$(day -1); D2=$(day -2); D3=$(day -3); D4=$(day -4); D5=$(day -5)
[ "$(day 0)" = "$TODAY" ] || { echo "date helper does not round-trip $TODAY" >&2; exit 1; }

sig() { printf '{"ts":"%sT12:00:%02dZ","tool":"Edit","n":%d}\n' "$1" "$2" "$2"; }
# gz_lines <file> -> decompressed line count, or "ERR" if the gz is invalid
gz_lines() { if gzip -t "$1" 2>/dev/null; then gzip -dc < "$1" | wc -l | tr -d ' '; else echo ERR; fi; }
# run <case-dir> [args...] -> runs the script with scratch paths; sets RC/OUT.
# RUN_TODAY / RUN_PATH (set via run_on / run_shim) pin the date / prepend a shim.
run() {
  local c="$1"; shift
  OUT=$(PATH="${RUN_PATH:-$PATH}" CLAUDE_ROTATE_TODAY="${RUN_TODAY:-$TODAY}" \
        CLAUDE_SIGNALS_FILE="$c/signals.jsonl" CLAUDE_ARCHIVE_DIR="$c/archives" \
        CLAUDE_ALERTS_FILE="$c/alerts.jsonl" bash "$ROT" "$@" 2>&1)
  RC=$?
}
run_on()   { local RUN_TODAY="$1"; shift; run "$@"; }          # run_on <date> <case> ...
run_shim() { local RUN_PATH="$1:$PATH"; shift; run "$@"; }     # run_shim <shimdir> <case> ...
# nfiles <dir> <glob> -> number of entries in <dir> matching <glob> (incl. dotfiles)
nfiles() { find "$1" -mindepth 1 -maxdepth 1 -name "$2" 2>/dev/null | wc -l | tr -d ' '; }
snapshot() { (cd "$1/archives" && for f in signals-*; do cksum "$f"; done) 2>/dev/null; }
wrote_count() { printf '%s\n' "$OUT" | grep -c 'EMPTY-SHARD: wrote' | tr -d ' '; }

# ── A) live file D-3 + D-1 (+ today) → shards D-3, D-2 (empty), D-1 ──────────
A="$ROOT/a"; mkdir -p "$A"
{ sig "$D3" 1; sig "$D3" 2; sig "$D1" 3; sig "$D1" 4; sig "$D1" 5; sig "$TODAY" 6; } > "$A/signals.jsonl"
ORIG=$(wc -l < "$A/signals.jsonl" | tr -d ' ')
run "$A"
check "a/exit0" 0 "$RC"
check "a/D-3-lines" 2 "$(gz_lines "$A/archives/signals-$D3.jsonl.gz")"
check "a/D-2-empty-valid-gz" 0 "$(gz_lines "$A/archives/signals-$D2.jsonl.gz")"
check "a/D-1-lines" 3 "$(gz_lines "$A/archives/signals-$D1.jsonl.gz")"
check "a/no-shard-before-anchor(D-4)" 0 "$(nfiles "$A/archives" "signals-$D4*")"
check "a/no-shard-for-today" 0 "$(nfiles "$A/archives" "signals-$TODAY*")"
check "a/one-empty-shard-logged" 1 "$(wrote_count)"
check "a/no-tmp-leftovers" 0 "$(nfiles "$A/archives" "*.empty.*")"

# ── D) count conservation: archived + kept == original; no alert ──────────────
ARCHIVED=0
for f in "$A"/archives/signals-*.jsonl.gz; do ARCHIVED=$((ARCHIVED + $(gz_lines "$f"))); done
KEPT=$(wc -l < "$A/signals.jsonl" | tr -d ' ')
check "d/conservation" "$ORIG" "$((ARCHIVED + KEPT))"
check "d/kept-today-only" 1 "$KEPT"
check "d/assertion-passed-logged" 1 "$(printf '%s\n' "$OUT" | grep -c 'assertion PASSED' | tr -d ' ')"
check "d/no-alert" 0 "$([ -s "$A/alerts.jsonl" ] && echo 1 || echo 0)"

# ── B) re-run → nothing new, nothing changed ─────────────────────────────────
BEFORE=$(snapshot "$A")
run "$A"
check "b/exit0" 0 "$RC"
check "b/no-new-empty-shard" 0 "$(wrote_count)"
check "b/archive-unchanged" "$BEFORE" "$(snapshot "$A")"

# ── C) existing shards untouched; older interior gap NOT auto-filled ─────────
C="$ROOT/c"; mkdir -p "$C/archives"
sig "$D5" 7 | gzip -c > "$C/archives/signals-$D5.jsonl.gz"
{ sig "$D3" 8; sig "$D3" 9; } | gzip -c > "$C/archives/signals-$D3.jsonl.gz"
cp "$C/archives/signals-$D5.jsonl.gz" "$ROOT/c-d5.ref"; cp "$C/archives/signals-$D3.jsonl.gz" "$ROOT/c-d3.ref"
sig "$D1" 10 > "$C/signals.jsonl"
run "$C"
check "c/exit0" 0 "$RC"
check "c/D-5-byte-identical" 0 "$(cmp -s "$ROOT/c-d5.ref" "$C/archives/signals-$D5.jsonl.gz"; echo $?)"
check "c/D-3-byte-identical" 0 "$(cmp -s "$ROOT/c-d3.ref" "$C/archives/signals-$D3.jsonl.gz"; echo $?)"
check "c/D-2-filled" 0 "$(gz_lines "$C/archives/signals-$D2.jsonl.gz")"
check "c/D-1-archived" 1 "$(gz_lines "$C/archives/signals-$D1.jsonl.gz")"
check "c/interior-gap-D-4-not-filled" 0 "$([ -e "$C/archives/signals-$D4.jsonl.gz" ] && echo 1 || echo 0)"

# ── E) zero-signal yesterday on the two no-op paths ──────────────────────────
for mode in no-past empty-file; do
  E="$ROOT/e-$mode"; mkdir -p "$E/archives"
  sig "$D2" 11 | gzip -c > "$E/archives/signals-$D2.jsonl.gz"
  if [ "$mode" = no-past ]; then sig "$TODAY" 12 > "$E/signals.jsonl"; else : > "$E/signals.jsonl"; fi
  run "$E"
  check "e/$mode/exit0" 0 "$RC"
  check "e/$mode/D-1-empty" 0 "$(gz_lines "$E/archives/signals-$D1.jsonl.gz")"
  check "e/$mode/no-backup-made" 0 "$(nfiles "$E/archives" "*.bak-*")"
done

# ── F) missing live file → no fill (absence proves nothing) ──────────────────
F="$ROOT/f"; mkdir -p "$F/archives"
sig "$D3" 13 | gzip -c > "$F/archives/signals-$D3.jsonl.gz"
run "$F"
check "f/exit0" 0 "$RC"
check "f/nothing-filled" 1 "$(ls "$F/archives" | wc -l | tr -d ' ')"

# ── G) non-JSON live file → abort exit 1, NO empty shard written ─────────────
G="$ROOT/g"; mkdir -p "$G/archives"
sig "$D3" 14 | gzip -c > "$G/archives/signals-$D3.jsonl.gz"
{ sig "$D1" 15; echo 'not json'; } > "$G/signals.jsonl"
run "$G"
check "g/exit1" 1 "$RC"
check "g/no-empty-shard-on-abort" 1 "$(nfiles "$G/archives" "signals-*")"

# ── H) dry-run: reports the empty shard, writes nothing ──────────────────────
H="$ROOT/h"; mkdir -p "$H"
{ sig "$D3" 16; sig "$D1" 17; } > "$H/signals.jsonl"
cp "$H/signals.jsonl" "$ROOT/h.ref"
run "$H" --dry-run
check "h/exit0" 0 "$RC"
check "h/reports-D-2" 1 "$(printf '%s\n' "$OUT" | grep -c "would write empty shard for $D2" | tr -d ' ')"
check "h/reports-only-D-2" 1 "$(printf '%s\n' "$OUT" | grep -c 'would write empty shard' | tr -d ' ')"
check "h/no-archive-dir" 0 "$([ -d "$H/archives" ] && echo 1 || echo 0)"
check "h/live-untouched" 0 "$(cmp -s "$ROOT/h.ref" "$H/signals.jsonl"; echo $?)"

# ── I) explicit backfill mode (--fill-empty-shard) ───────────────────────────
I="$ROOT/i"; mkdir -p "$I/archives"
sig "$D4" 18 | gzip -c > "$I/archives/signals-$D4.jsonl.gz"; cp "$I/archives/signals-$D4.jsonl.gz" "$ROOT/i-d4.ref"
sig "$D2" 19 > "$I/signals.jsonl"
run "$I" "--fill-empty-shard=$D5"
check "i/fill-exit0" 0 "$RC"
check "i/fill-D-5-empty" 0 "$(gz_lines "$I/archives/signals-$D5.jsonl.gz")"
check "i/live-untouched" 1 "$(wc -l < "$I/signals.jsonl" | tr -d ' ')"
run "$I" "--fill-empty-shard=$D4"
check "i/existing-exit0" 0 "$RC"
check "i/existing-untouched" 0 "$(cmp -s "$ROOT/i-d4.ref" "$I/archives/signals-$D4.jsonl.gz"; echo $?)"
run "$I" "--fill-empty-shard=$D2"
check "i/refuse-live-entries-exit1" 1 "$RC"
check "i/refuse-live-entries-no-shard" 0 "$([ -e "$I/archives/signals-$D2.jsonl.gz" ] && echo 1 || echo 0)"
run "$I" "--fill-empty-shard=$TODAY"
check "i/refuse-today-exit2" 2 "$RC"
run "$I" "--fill-empty-shard=2026-02-30"
check "i/refuse-invalid-date-exit2" 2 "$RC"
run "$I" "--fill-empty-shard=$D3" --dry-run
check "i/refuse-with-dry-run-exit2" 2 "$RC"
check "i/nothing-written-by-refusals" 2 "$(ls "$I/archives" | wc -l | tr -d ' ')"

# ── IMP-226: a late entry for an already-archived date MERGES into its gz ─────
# Bug: STEP 2 appended to a fresh plain .jsonl and STEP 5 `gzip -f` replaced
# the existing gz with only the late entries — the old shard content was lost.
gz_body() { gzip -dc < "$1" | sort; }
# J) late entry merged into an existing 3-line shard → 4 lines, union content
J="$ROOT/j"; mkdir -p "$J/archives"
{ sig "$D2" 21; sig "$D2" 22; sig "$D2" 23; } | gzip -c > "$J/archives/signals-$D2.jsonl.gz"
{ sig "$D2" 24; sig "$TODAY" 25; } > "$J/signals.jsonl"
EXPECT_J=$({ sig "$D2" 21; sig "$D2" 22; sig "$D2" 23; sig "$D2" 24; } | sort)
run "$J"
check "j/exit0" 0 "$RC"
check "j/merged-4-lines" 4 "$(gz_lines "$J/archives/signals-$D2.jsonl.gz")"
check "j/merged-content-is-union" "$EXPECT_J" "$(gz_body "$J/archives/signals-$D2.jsonl.gz")"
check "j/no-plain-leftover" 0 "$(nfiles "$J/archives" "signals-$D2.jsonl")"
check "j/no-tmp-leftovers" 0 "$(nfiles "$J/archives" ".*")"
check "j/conservation(pre3+late1)" 4 "$(for f in "$J"/archives/signals-*.jsonl.gz; do gzip -dc < "$f"; done | wc -l | tr -d ' ')"
check "j/kept-today" 1 "$(wc -l < "$J/signals.jsonl" | tr -d ' ')"
check "j/no-alert" 0 "$([ -s "$J/alerts.jsonl" ] && echo 1 || echo 0)"
# K) late DUPLICATE of an existing line → still 3 lines
K="$ROOT/k"; mkdir -p "$K/archives"
{ sig "$D2" 31; sig "$D2" 32; sig "$D2" 33; } | gzip -c > "$K/archives/signals-$D2.jsonl.gz"
EXPECT_K=$(gz_body "$K/archives/signals-$D2.jsonl.gz")
{ sig "$D2" 32; sig "$TODAY" 34; } > "$K/signals.jsonl"
run "$K"
check "k/exit0" 0 "$RC"
check "k/dedup-3-lines" 3 "$(gz_lines "$K/archives/signals-$D2.jsonl.gz")"
check "k/content-unchanged" "$EXPECT_K" "$(gz_body "$K/archives/signals-$D2.jsonl.gz")"
# L) late entry for a day holding an IMP-221 EMPTY shard → 1 line, valid gz
L="$ROOT/l"; mkdir -p "$L/archives"
gzip -c < /dev/null > "$L/archives/signals-$D2.jsonl.gz"
sig "$D2" 41 > "$L/signals.jsonl"
run "$L"
check "l/exit0" 0 "$RC"
check "l/one-line-valid-gz" 1 "$(gz_lines "$L/archives/signals-$D2.jsonl.gz")"
check "l/content" "$(sig "$D2" 41)" "$(gz_body "$L/archives/signals-$D2.jsonl.gz")"
# M) simulated gzip WRITE failure → old shard byte-identical, non-zero exit,
#    late entry still on disk (plain shard + backup), blocker alert written.
M="$ROOT/m"; mkdir -p "$M/archives" "$ROOT/shim"
REAL_GZIP=$(command -v gzip)
cat > "$ROOT/shim/gzip" <<SHIM
#!/bin/bash
for a in "\$@"; do case "\$a" in -d|-dc|-cd|-t|--decompress|--test) exec "$REAL_GZIP" "\$@";; esac; done
echo "shim: simulated gzip write failure" >&2; exit 1
SHIM
chmod +x "$ROOT/shim/gzip"
{ sig "$D1" 51; sig "$D1" 52; sig "$D1" 53; } | "$REAL_GZIP" -c > "$M/archives/signals-$D1.jsonl.gz"
cp "$M/archives/signals-$D1.jsonl.gz" "$ROOT/m-d1.ref"
{ sig "$D1" 54; sig "$TODAY" 55; } > "$M/signals.jsonl"
cp "$M/signals.jsonl" "$ROOT/m-live.ref"
run_shim "$ROOT/shim" "$M"
check "m/exit2-exactly" 2 "$RC"
check "m/old-shard-byte-identical" 0 "$(cmp -s "$ROOT/m-d1.ref" "$M/archives/signals-$D1.jsonl.gz"; echo $?)"
check "m/late-entry-kept-in-plain-shard" 1 "$(grep -c '"n":54' "$M/archives/signals-$D1.jsonl" 2>/dev/null | tr -d ' ')"
check "m/no-tmp-leftovers" 0 "$(nfiles "$M/archives" ".*")"
check "m/live-file-untouched" 0 "$(cmp -s "$ROOT/m-live.ref" "$M/signals.jsonl"; echo $?)"
check "m/alert-written" 1 "$([ -s "$M/alerts.jsonl" ] && echo 1 || echo 0)"
# M2) recovery: next run with a working gzip merges the leftover plain shard
run "$M"
check "m2/recovery-exit0" 0 "$RC"
check "m2/recovered-4-lines" 4 "$(gz_lines "$M/archives/signals-$D1.jsonl.gz")"
check "m2/no-plain-leftover" 0 "$(nfiles "$M/archives" "signals-$D1.jsonl")"

# ── Review #4: a lost live file must NEVER be certified as zero-signal days ──
# The previous nightly run is simulated with run_on "$D2"; the receipt it
# writes is the continuity proof the next run checks before any fill.
ex()        { [ -e "$1" ] && echo 1 || echo 0; }
alert_f()   { tail -1 "$1/alerts.jsonl" 2>/dev/null | jq -r ".$2"; }   # alert_f <case> <field>
receipt_f() { awk -v n="$2" 'NR == 1 {print $n}' "$1/archives/signals.jsonl.continuity" 2>/dev/null; }
has()       { printf '%s\n' "$OUT" | grep -qF -- "$1" && echo 1 || echo 0; }   # reason text in last output
# N) live file TRUNCATED to empty after a rotation that kept 2 lines → exit 3
N="$ROOT/n"; mkdir -p "$N"
{ sig "$D3" 61; sig "$D2" 62; sig "$D2" 63; } > "$N/signals.jsonl"
run_on "$D2" "$N"
check "n/prev-run-exit0" 0 "$RC"
check "n/prev-run-receipt" 1 "$(ex "$N/archives/signals.jsonl.continuity")"
: > "$N/signals.jsonl"
run "$N"
check "n/exit3" 3 "$RC"
check "n/no-false-zero-shard-D-2" 0 "$(ex "$N/archives/signals-$D2.jsonl.gz")"
check "n/no-false-zero-shard-D-1" 0 "$(ex "$N/archives/signals-$D1.jsonl.gz")"
check "n/alert-exit3" 3 "$(alert_f "$N" exit)"
check "n/alert-blocker" true "$(alert_f "$N" blocker)"
check "n/reason-shrank" 1 "$(has 'shrank')"
check "n/receipt-floor-today" "$TODAY" "$(receipt_f "$N" 5)"
# review-2 #2: floor=today leaves (anchor, today] unproven — the alert must say so
check "n/alert-range-(D-3,today]" 1 "$(alert_f "$N" error | grep -cF "($D3, $TODAY]" | tr -d ' ')"
# N2) next run: proof holds again, but the floor keeps the unproven days unfilled
run "$N"
check "n2/exit0" 0 "$RC"
check "n2/D-2-still-unfilled" 0 "$(ex "$N/archives/signals-$D2.jsonl.gz")"
check "n2/D-1-still-unfilled" 0 "$(ex "$N/archives/signals-$D1.jsonl.gz")"
check "n2/one-alert-total" 1 "$(wc -l < "$N/alerts.jsonl" | tr -d ' ')"
# O) truncated then REGROWN past the old size → prefix checksum catches it;
#    present dates are still rotated, only the fill is skipped
O="$ROOT/o"; mkdir -p "$O"
{ sig "$D3" 71; sig "$D2" 72; } > "$O/signals.jsonl"
run_on "$D2" "$O"
: > "$O/signals.jsonl"
{ sig "$D1" 73; sig "$D1" 74; sig "$D1" 75; sig "$TODAY" 76; } >> "$O/signals.jsonl"
run "$O"
check "o/exit3" 3 "$RC"
check "o/no-false-zero-shard-D-2" 0 "$(ex "$O/archives/signals-$D2.jsonl.gz")"
check "o/D-1-still-archived" 3 "$(gz_lines "$O/archives/signals-$D1.jsonl.gz")"
check "o/live-trimmed-to-today" 1 "$(wc -l < "$O/signals.jsonl" | tr -d ' ')"
check "o/reason-prefix" 1 "$(has 'bytes of the live file changed')"
# P) DELETED and recreated after a run that kept 0 lines → inode proof
P="$ROOT/p"; mkdir -p "$P"
sig "$D3" 81 > "$P/signals.jsonl"
run_on "$D2" "$P"
check "p/prev-run-kept-0" 0 "$(wc -c < "$P/signals.jsonl" | tr -d ' ')"
sig "$TODAY" 82 > "$P/new.jsonl"; mv "$P/new.jsonl" "$P/signals.jsonl"   # new inode
run "$P"
check "p/exit3" 3 "$RC"
check "p/no-false-zero-shard-D-2" 0 "$(ex "$P/archives/signals-$D2.jsonl.gz")"
check "p/no-false-zero-shard-D-1" 0 "$(ex "$P/archives/signals-$D1.jsonl.gz")"
check "p/reason-replaced" 1 "$(has 'replaced since the last run')"
# Q) written to and truncated back to the same (0-byte) size → mtime proof
Q="$ROOT/q"; mkdir -p "$Q"
sig "$D3" 91 > "$Q/signals.jsonl"
run_on "$D2" "$Q"
sig "$D2" 92 >> "$Q/signals.jsonl"; : > "$Q/signals.jsonl"
run "$Q"
check "q/exit3" 3 "$RC"
check "q/no-false-zero-shard-D-2" 0 "$(ex "$Q/archives/signals-$D2.jsonl.gz")"
check "q/reason-no-growth" 1 "$(has 'without growing')"
# R) (b) intact continuity via receipt → the zero-signal day IS still filled
R="$ROOT/r"; mkdir -p "$R"
{ sig "$D3" 101; sig "$D2" 102; } > "$R/signals.jsonl"
run_on "$D2" "$R"
sig "$TODAY" 103 >> "$R/signals.jsonl"
run "$R"
check "r/exit0" 0 "$RC"
check "r/D-2-archived" 1 "$(gz_lines "$R/archives/signals-$D2.jsonl.gz")"
check "r/D-1-zero-signal-filled" 0 "$(gz_lines "$R/archives/signals-$D1.jsonl.gz")"
check "r/no-alert" 0 "$(ex "$R/alerts.jsonl")"
# S) bootstrap (no receipt yet): backup shows kept entries after the anchor,
#    live truncated → exit 3; S2) same backup, kept line still heads → fills
for mode in lost intact; do
  S="$ROOT/s-$mode"; mkdir -p "$S/archives"
  sig "$D3" 111 | gzip -c > "$S/archives/signals-$D3.jsonl.gz"
  { sig "$D3" 111; sig "$D2" 112; } > "$S/archives/signals.jsonl.bak-${D2//-/}T000500Z"
  if [ "$mode" = lost ]; then : > "$S/signals.jsonl"; else { sig "$D2" 112; sig "$TODAY" 113; } > "$S/signals.jsonl"; fi
  run "$S"
  if [ "$mode" = lost ]; then
    check "s/lost/exit3" 3 "$RC"
    check "s/lost/no-false-zero-shard-D-2" 0 "$(ex "$S/archives/signals-$D2.jsonl.gz")"
    check "s/lost/no-false-zero-shard-D-1" 0 "$(ex "$S/archives/signals-$D1.jsonl.gz")"
    check "s/lost/alert-exit3" 3 "$(alert_f "$S" exit)"
  else
    check "s/intact/exit0" 0 "$RC"
    check "s/intact/D-1-zero-signal-filled" 0 "$(gz_lines "$S/archives/signals-$D1.jsonl.gz")"
  fi
done
# T) live file deleted while a receipt exists → exit 3, nothing filled
T="$ROOT/t"; mkdir -p "$T"
sig "$D3" 121 > "$T/signals.jsonl"
run_on "$D2" "$T"
rm -f "$T/signals.jsonl"
run "$T"
check "t/exit3" 3 "$RC"
check "t/no-false-zero-shard-D-2" 0 "$(ex "$T/archives/signals-$D2.jsonl.gz")"
check "t/alert-exit3" 3 "$(alert_f "$T" exit)"

# ── Review #13/#14: every failure path → alert line + documented exit code ───
mkshim() { # mkshim <dir> <cmd> <case-pattern-that-fails>
  mkdir -p "$1"; local real; real=$(command -v "$2")
  printf '#!/bin/bash\ncase " $* " in %s) echo "shim: simulated %s failure" >&2; exit 1;; esac\nexec "%s" "$@"\n' \
    "$3" "$2" "$real" > "$1/$2"; chmod +x "$1/$2"
}
# U) gzip failure inside write_empty_shard → exit 2 (not 1), alert, no leftovers
U="$ROOT/u"; mkdir -p "$U/archives"
sig "$D2" 131 | gzip -c > "$U/archives/signals-$D2.jsonl.gz"
sig "$TODAY" 132 > "$U/signals.jsonl"; cp "$U/signals.jsonl" "$ROOT/u-live.ref"
run_shim "$ROOT/shim" "$U"
check "u/exit2" 2 "$RC"
check "u/alert-exit2" 2 "$(alert_f "$U" exit)"
check "u/no-D-1-shard" 0 "$(nfiles "$U/archives" "signals-$D1*")"
check "u/no-tmp-leftovers" 0 "$(nfiles "$U/archives" ".*")"
check "u/live-untouched" 0 "$(cmp -s "$ROOT/u-live.ref" "$U/signals.jsonl"; echo $?)"
# V) shard listing (find) failure → exit 2 + alert, nothing mutated
mkshim "$ROOT/shim-find-maxdepth" find '*" -maxdepth "*'
V="$ROOT/v"; mkdir -p "$V/archives"
sig "$D3" 141 | gzip -c > "$V/archives/signals-$D3.jsonl.gz"
{ sig "$D1" 142; sig "$TODAY" 143; } > "$V/signals.jsonl"; cp "$V/signals.jsonl" "$ROOT/v-live.ref"
run_shim "$ROOT/shim-find-maxdepth" "$V"
check "v/exit2" 2 "$RC"
check "v/alert-exit2" 2 "$(alert_f "$V" exit)"
check "v/live-untouched" 0 "$(cmp -s "$ROOT/v-live.ref" "$V/signals.jsonl"; echo $?)"
check "v/no-backup-made" 0 "$(nfiles "$V/archives" "*.bak-*")"
# W) #14: STEP 3c plain-shard listing fails → exit 2, alert, NO trim
mkshim "$ROOT/shim-find-bang" find '*" ! "*'
W="$ROOT/w"; mkdir -p "$W"
{ sig "$D1" 151; sig "$TODAY" 152; } > "$W/signals.jsonl"; cp "$W/signals.jsonl" "$ROOT/w-live.ref"
run_shim "$ROOT/shim-find-bang" "$W"
check "w/exit2" 2 "$RC"
check "w/alert-exit2" 2 "$(alert_f "$W" exit)"
check "w/live-NOT-trimmed" 0 "$(cmp -s "$ROOT/w-live.ref" "$W/signals.jsonl"; echo $?)"
check "w/alert-trimmed-false" false "$(alert_f "$W" trimmed)"
# X) an unguarded command failing → EXIT-trap catch-all: exit 2 + alert
mkshim "$ROOT/shim-wc-l" wc '*" -l "*'
X="$ROOT/x"; mkdir -p "$X"
{ sig "$D1" 161; sig "$TODAY" 162; } > "$X/signals.jsonl"; cp "$X/signals.jsonl" "$ROOT/x-live.ref"
run_shim "$ROOT/shim-wc-l" "$X"
check "x/exit2" 2 "$RC"
check "x/alert-catch-all" 1 "$(alert_f "$X" error | grep -c 'unexpected failure' | tr -d ' ')"
check "x/live-untouched" 0 "$(cmp -s "$ROOT/x-live.ref" "$X/signals.jsonl"; echo $?)"
check "x/one-alert" 1 "$(wc -l < "$X/alerts.jsonl" | tr -d ' ')"

# ── Review #6: every sort in the script runs byte-wise (LC_ALL=C) ────────────
UNPINNED=$(grep -nE '(^|[|;&(]|\$\()[[:space:]]*sort([[:space:]]|$)' "$ROT" | grep -cvE '^[0-9]+:[[:space:]]*#')
check "y/every-sort-pins-LC_ALL=C" 0 "$UNPINNED"
check "y/pinned-sorts-present" 1 "$([ "$(grep -c 'LC_ALL=C sort' "$ROT")" -ge 7 ] && echo 1 || echo 0)"

# ── Review-2: second adversarial review (#1 #2 #3 #5 #6 #7 #8 #9) ────────────
run_on_shim() { local RUN_TODAY="$1" RUN_PATH="$2:$PATH"; shift 2; run "$@"; }
inode_of()    { ls -di "$1" | awk '{print $1}'; }
# 1) receipt write fails in STEP 4 → the next run must NOT be a false exit 3.
#    Old order (trim mv, then receipt) left a stale receipt naming the pre-trim
#    inode; now the receipt is written BEFORE the mv.
mkshim "$ROOT/shim-mktemp-receipt" mktemp '*".continuity."*'
R1="$ROOT/r1"; mkdir -p "$R1"
{ sig "$D4" 240; sig "$D3" 241; } > "$R1/signals.jsonl"
run_on "$D3" "$R1"
check "r1/prev-run-exit0" 0 "$RC"
sig "$D2" 242 >> "$R1/signals.jsonl"
run_on_shim "$D2" "$ROOT/shim-mktemp-receipt" "$R1"
check "r1/receipt-fail-exit2" 2 "$RC"
check "r1/receipt-fail-live-not-trimmed" false "$(alert_f "$R1" trimmed)"
sig "$TODAY" 243 >> "$R1/signals.jsonl"
run "$R1"
check "r1/next-run-exit0(no-false-exit3)" 0 "$RC"
check "r1/D-1-zero-signal-filled" 0 "$(gz_lines "$R1/archives/signals-$D1.jsonl.gz")"
check "r1/D-2-archived" 1 "$(gz_lines "$R1/archives/signals-$D2.jsonl.gz")"
check "r1/D-3-deduped" 1 "$(gz_lines "$R1/archives/signals-$D3.jsonl.gz")"
check "r1/one-alert-total" 1 "$(wc -l < "$R1/alerts.jsonl" | tr -d ' ')"
check "r1/receipt-line1-is-live-inode" "$(inode_of "$R1/signals.jsonl")" "$(receipt_f "$R1" 2)"
# 1b) the trim mv itself fails AFTER the receipt → the "pre" line proves it
mkshim "$ROOT/shim-mv-trim" mv '*"signals.jsonl.tmp."*'
for mode in intact replaced; do
  R1B="$ROOT/r1b-$mode"; mkdir -p "$R1B"
  { sig "$D4" 250; sig "$D3" 251; } > "$R1B/signals.jsonl"
  run_on "$D3" "$R1B"
  sig "$D2" 252 >> "$R1B/signals.jsonl"
  run_on_shim "$D2" "$ROOT/shim-mv-trim" "$R1B"
  check "r1b/$mode/mv-fail-exit2" 2 "$RC"
  check "r1b/$mode/receipt-has-pre-line" 1 "$(grep -c '^pre ' "$R1B/archives/signals.jsonl.continuity" | tr -d ' ')"
  if [ "$mode" = replaced ]; then
    cp "$R1B/signals.jsonl" "$R1B/new.jsonl"; mv "$R1B/new.jsonl" "$R1B/signals.jsonl"   # new inode
  fi
  sig "$TODAY" 253 >> "$R1B/signals.jsonl"
  run "$R1B"
  if [ "$mode" = intact ]; then
    check "r1b/intact/exit0" 0 "$RC"
    check "r1b/intact/proof-via-pre-line" 1 "$(has 'pre-trim line')"
    check "r1b/intact/D-1-filled" 0 "$(gz_lines "$R1B/archives/signals-$D1.jsonl.gz")"
  else
    check "r1b/replaced/exit3" 3 "$RC"
    check "r1b/replaced/no-false-zero-shard-D-1" 0 "$(ex "$R1B/archives/signals-$D1.jsonl.gz")"
  fi
done
# 3) empty / short / null / missing ts → exit 1 before any mutation
for mode in empty short null missing; do
  case "$mode" in
    empty) bad='{"ts":"","n":211}' ;; short) bad='{"ts":"abc","n":211}' ;;
    null)  bad='{"ts":null,"n":211}' ;; missing) bad='{"n":211}' ;;
  esac
  B3="$ROOT/b3-$mode"; mkdir -p "$B3"
  { sig "$D1" 210; printf '%s\n' "$bad"; sig "$TODAY" 212; } > "$B3/signals.jsonl"
  cp "$B3/signals.jsonl" "$ROOT/b3-$mode.ref"
  run "$B3"
  check "b3/$mode/exit1" 1 "$RC"
  check "b3/$mode/live-untouched" 0 "$(cmp -s "$ROOT/b3-$mode.ref" "$B3/signals.jsonl"; echo $?)"
  check "b3/$mode/nothing-archived" 0 "$(nfiles "$B3/archives" "*")"
  check "b3/$mode/alert-exit1" 1 "$(alert_f "$B3" exit)"
  check "b3/$mode/alert-names-line-2" 1 "$(alert_f "$B3" error | grep -cF 'first lines: 2)' | tr -d ' ')"
done
B3D="$ROOT/b3-dry"; mkdir -p "$B3D"
{ sig "$D1" 213; echo '{"ts":"","n":214}'; } > "$B3D/signals.jsonl"
run "$B3D" --dry-run
check "b3/dry-run-exit1" 1 "$RC"
# 5) a partial line left in a plain shard must never be archived
P5="$ROOT/p5"; mkdir -p "$P5/archives"
sig "$D1" 230 | gzip -c > "$P5/archives/signals-$D1.jsonl.gz"; cp "$P5/archives/signals-$D1.jsonl.gz" "$ROOT/p5-gz.ref"
{ sig "$D1" 231; printf '{"ts":"%sT12:00:3' "$D1"; } > "$P5/archives/signals-$D1.jsonl"   # killed mid-write
{ sig "$D1" 232; sig "$TODAY" 233; } > "$P5/signals.jsonl"; cp "$P5/signals.jsonl" "$ROOT/p5-live.ref"
run "$P5"
check "p5/exit2" 2 "$RC"
check "p5/old-gz-byte-identical" 0 "$(cmp -s "$ROOT/p5-gz.ref" "$P5/archives/signals-$D1.jsonl.gz"; echo $?)"
check "p5/live-untouched" 0 "$(cmp -s "$ROOT/p5-live.ref" "$P5/signals.jsonl"; echo $?)"
check "p5/alert-names-non-JSON" 1 "$(alert_f "$P5" error | grep -c 'non-JSON' | tr -d ' ')"
check "p5/no-tmp-leftovers" 0 "$(nfiles "$P5/archives" ".*")"
# 6) dry-run exits 3 (like the real run) when continuity is not proven
for mode in empty regrown; do
  D6="$ROOT/d6-$mode"; mkdir -p "$D6"
  { sig "$D3" 201; sig "$D2" 202; } > "$D6/signals.jsonl"
  run_on "$D2" "$D6"
  : > "$D6/signals.jsonl"
  if [ "$mode" = regrown ]; then { sig "$D1" 203; sig "$D1" 204; sig "$D1" 205; sig "$TODAY" 206; } >> "$D6/signals.jsonl"; fi
  cp "$D6/signals.jsonl" "$ROOT/d6-$mode-live.ref"; cp "$D6/archives/signals.jsonl.continuity" "$ROOT/d6-$mode-rc.ref"
  SNAP6=$(snapshot "$D6")
  run "$D6" --dry-run
  check "d6/$mode/dry-run-exit3" 3 "$RC"
  check "d6/$mode/alert-exit3" 3 "$(alert_f "$D6" exit)"
  check "d6/$mode/live-untouched" 0 "$(cmp -s "$ROOT/d6-$mode-live.ref" "$D6/signals.jsonl"; echo $?)"
  check "d6/$mode/receipt-untouched" 0 "$(cmp -s "$ROOT/d6-$mode-rc.ref" "$D6/archives/signals.jsonl.continuity"; echo $?)"
  check "d6/$mode/archive-untouched" "$SNAP6" "$(snapshot "$D6")"
done
# 7) CLAUDE_ROTATE_TODAY against the DEFAULT live file: refused beyond +-1 day.
#    HOME points at a scratch dir, so the default path is a scratch file too.
FH="$ROOT/fakehome"; mkdir -p "$FH/.claude/global-observation"
sig "$D1" 220 > "$FH/.claude/global-observation/signals.jsonl"; cp "$FH/.claude/global-observation/signals.jsonl" "$ROOT/fh.ref"
run_home() { OUT=$(env -u CLAUDE_SIGNALS_FILE -u CLAUDE_ARCHIVE_DIR -u CLAUDE_ALERTS_FILE HOME="$FH" \
               CLAUDE_ROTATE_TODAY="$1" bash "$ROT" --dry-run 2>&1); RC=$?; }
run_home "$D5"
check "p7/far-pin-default-path-exit2" 2 "$RC"
check "p7/far-pin-nothing-created" 0 "$(ex "$FH/.claude/global-observation/archives")"
check "p7/far-pin-live-untouched" 0 "$(cmp -s "$ROOT/fh.ref" "$FH/.claude/global-observation/signals.jsonl"; echo $?)"
check "p7/far-pin-alert-exit2" 2 "$(tail -1 "$FH/.claude/global-observation/alerts.jsonl" 2>/dev/null | jq -r .exit)"
run_home "$TODAY"
check "p7/near-pin-default-path-exit0" 0 "$RC"
# 8) large dry-run: head -1 SIGPIPEd sort under pipefail → false exit 2
BIG="$ROOT/big"; mkdir -p "$BIG"
awk -v d="$D2" 'BEGIN { for (i = 0; i < 60000; i++) printf "{\"ts\":\"%sT12:00:00Z\",\"n\":%d}\n", d, i }' > "$BIG/signals.jsonl"
run "$BIG" --dry-run
check "big/dry-run-exit0" 0 "$RC"
check "big/reports-D-1-empty" 1 "$(has "would write empty shard for $D1")"
check "big/no-archive-dir" 0 "$(ex "$BIG/archives")"
# 9) a failing rm inside die's cleanup must not add a 2nd "unexpected" alert
mkdir -p "$ROOT/shim-9"; cp "$ROOT/shim/gzip" "$ROOT/shim-9/gzip"; mkshim "$ROOT/shim-9" rm '*" -- "*'
Z9="$ROOT/z9"; mkdir -p "$Z9/archives"
sig "$D1" 260 | gzip -c > "$Z9/archives/signals-$D1.jsonl.gz"
{ sig "$D1" 261; sig "$TODAY" 262; } > "$Z9/signals.jsonl"
run_shim "$ROOT/shim-9" "$Z9"
check "z9/exit2" 2 "$RC"
check "z9/exactly-one-alert" 1 "$(wc -l < "$Z9/alerts.jsonl" | tr -d ' ')"
check "z9/alert-is-the-merge-failure" 1 "$(alert_f "$Z9" error | grep -c 'IMP-226 shard merge failed' | tr -d ' ')"
check "z9/cleanup-warning-shown" 1 "$(has 'temp cleanup incomplete')"
# the shimmed rm left z9's shard list behind on purpose — remove only that one
for f in /tmp/rotate-signals-shards.*; do
  [[ -f "$f" ]] && grep -q -- "$Z9/" "$f" && /bin/rm -f -- "$f"
done
# 8b) no `| head` left under pipefail (SIGPIPE class)
check "y/no-pipe-into-head" 0 "$(grep -nE '\|[[:space:]]*head([[:space:]]|$)' "$ROT" | grep -cvE '^[0-9]+:[[:space:]]*#' | tr -d ' ')"

printf '── rotate-signals-regression: %d passed, %d failed ──\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
