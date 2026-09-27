#!/usr/bin/env bash
# Regression suite for the S1a symlink guard (W19, ABORT 19) of
# scheduled-tasks/daily-docs/bin/logbook-count.sh (IMP-225).
#
# Why this suite exists: the daily-docs run of 2026-09-27T05:11:30Z ended with
#   ABORT(19): symlink in the scan tree of S1a_transcripts tree=~/.claude/projects
#   root_is_symlink=nein dir_symlinks=0 pattern_symlinks=3 ...
# The 3 links are created by Claude Code itself when a background-job session
# starts: <new-session>/subagents/agent-*.jsonl -> <parent-session>/subagents/
# agent-*.jsonl in the SAME project dir. Every background job therefore aborted the
# next run. A file link whose resolved target is a regular, pattern-matching file
# under the same root is now tolerated (counted once via its target, reported as
# symlinks_tolerated=N + NOTE W19); every other link kind still aborts.
#
# Isolation: every case runs against a scratch $HOME under $TMPDIR and sets
# LOGBOOK_STOP_AFTER_S1A=1, the script's test hook that exits 99 right after the
# S1a receipt (99, never 0: a leaked hook variable must not fake a passing run).
# Nothing under the real ~/.claude is read or written.
#
# Usage: bash scripts/tests/logbook-count-symlink-regression.sh
#        LOGBOOK_COUNT_SH=/path/to/old/logbook-count.sh bash ... (prove it fails pre-fix)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LBC="${LOGBOOK_COUNT_SH:-$SCRIPT_DIR/../../scheduled-tasks/daily-docs/bin/logbook-count.sh}"
[ -f "$LBC" ] || { echo "logbook-count.sh not found: $LBC" >&2; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf '  [%s] %s\n' "$1" "$2"; }
check(){ if [ "$2" = "$3" ]; then ok; else bad "$1" "expected='$2' got='$3'"; fi; }
has(){  if /usr/bin/grep -aqF -- "$2" "$3"; then ok; else bad "$1" "missing '$2' in: $(tr '\n' '|' < "$3" | cut -c1-700)"; fi; }
hasnt(){ if /usr/bin/grep -aqF -- "$2" "$3"; then bad "$1" "unexpected '$2'"; else ok; fi; }

# pwd -P: $TMPDIR lives under /var -> /private/var on macOS; resolved so that the
# roots guard (ABORT 19, roots.txt axis) does not fire on the fixture itself.
ROOT=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/lbc-sym-reg.XXXXXX")" && pwd -P)
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "scratch dir not created" >&2; exit 1; }
trap 'rm -rf "$ROOT"' EXIT

DAY=2026-09-20
LINE='{"timestamp":"2026-09-20T10:00:00.000Z","message":{"content":[{"type":"text","text":"x"}]}}'

# setup_case <name> -> scratch HOME with one project holding a parent session
# (2 transcripts, one in subagents/) and an empty child session subagents/ dir.
setup_case() {
  local c="$ROOT/$1"
  H="$c/home"; PJ="$H/.claude/projects/-proj"
  mkdir -p "$PJ/parent/subagents" "$PJ/child/subagents" \
           "$H/.claude/global-observation/archives" \
           "$H/Library/Application Support/Claude/local-agent-mode-sessions" "$c/repo" "$c/tmp"
  printf '%s\n' "$LINE" > "$PJ/parent.jsonl"
  printf '%s\n' "$LINE" > "$PJ/parent/subagents/agent-a1.jsonl"
  : > "$c/repo/sentinel"
  printf '%s\t%s\n' "$c/repo" "$c/repo/sentinel" > "$c/roots.txt"
  printf 'signals\t2099-01-01\ntranskripte\t2000-01-01\ndesktop\t2000-01-01\n' > "$c/epochs.tsv"
  CASE_DIR="$c"
}
run_case() {
  ERR="$CASE_DIR/stderr.txt"
  HOME="$H" TMPDIR="$CASE_DIR/tmp" TZ=Europe/Berlin \
    LOGBOOK_ROOTS="$CASE_DIR/roots.txt" LOGBOOK_EPOCH_CACHE="$CASE_DIR/epochs.tsv" \
    LOGBOOK_STOP_AFTER_S1A=1 bash "$LBC" "$DAY" > "$CASE_DIR/stdout.txt" 2> "$ERR"
  RC=$?
}
s1a_receipt() { /usr/bin/grep -a '^RECEIPT S1a candidates=' "$1" || echo "<no S1a receipt>"; }
w19_n()       { /usr/bin/grep -a '^RECEIPT W19 S1a_transcripts' "$1" | /usr/bin/grep -ao ' n=[0-9]*' || echo "<no W19 n>"; }

# ── (e) no links -> baseline, symlinks_tolerated=0, state=symlinkfrei
setup_case e
run_case
check "e/exit99-stop-hook" 99 "$RC"
has "e/tolerated0" "symlinks_tolerated=0 " "$ERR"
has "e/state" "state=symlinkfrei" "$ERR"
has "e/stop-hook" "STOP after S1a" "$ERR"
BASE_S1A=$(s1a_receipt "$ERR"); BASE_N=$(w19_n "$ERR")
check "e/baseline-counts" "RECEIPT S1a candidates=2 files=2 unreadable=0 grep_rc=0" "$BASE_S1A"

# ── (a) in-tree file link (the real harness shape, absolute target) -> no abort,
#        symlinks_tolerated=1, NOTE lists it, counts identical to (e)
setup_case a
ln -s "$PJ/parent/subagents/agent-a1.jsonl" "$PJ/child/subagents/agent-a1.jsonl"
run_case
check "a/exit99-stop-hook" 99 "$RC"
has "a/tolerated1" "symlinks_tolerated=1 " "$ERR"
has "a/state" "state=tolerated" "$ERR"
has "a/note" "NOTE W19 S1a_transcripts: 1 in-tree file symlink(s) TOLERATED" "$ERR"
has "a/note-lists-link" "tolerated: $PJ/child/subagents/agent-a1.jsonl -> $PJ/parent/subagents/agent-a1.jsonl" "$ERR"
check "a/count-unchanged-S1a" "$BASE_S1A" "$(s1a_receipt "$ERR")"
check "a/count-unchanged-W19n" "$BASE_N" "$(w19_n "$ERR")"
has "a/findL-sees-link" " n_L=3 " "$ERR"
hasnt "a/no-abort" "ABORT(" "$ERR"

# ── (a2) same, RELATIVE link target -> tolerated as well
setup_case a2
ln -s "../../parent/subagents/agent-a1.jsonl" "$PJ/child/subagents/agent-a1.jsonl"
run_case
check "a2/exit99-stop-hook" 99 "$RC"
has "a2/tolerated1" "symlinks_tolerated=1 " "$ERR"
check "a2/count-unchanged" "$BASE_S1A" "$(s1a_receipt "$ERR")"

# ── (b) link to a file OUTSIDE the tree -> ABORT(19)
setup_case b
mkdir -p "$CASE_DIR/outside"; printf '%s\n' "$LINE" > "$CASE_DIR/outside/agent-x.jsonl"
ln -s "$CASE_DIR/outside/agent-x.jsonl" "$PJ/child/subagents/agent-x.jsonl"
run_case
check "b/exit19" 19 "$RC"
has "b/reason" "ABORT(19): symlink in the scan tree of S1a_transcripts" "$ERR"
has "b/fields" "pattern_symlinks=1 other=0 find_rc=0 symlinks_tolerated=0" "$ERR"
has "b/affected" "MUSTER-OUTSIDE" "$ERR"

# ── (c) dangling link -> ABORT(19)
setup_case c
ln -s "$PJ/parent/subagents/gone.jsonl" "$PJ/child/subagents/gone.jsonl"
run_case
check "c/exit19" 19 "$RC"
has "c/fields" "pattern_symlinks=1 " "$ERR"
has "c/affected" "MUSTER-DANGLING" "$ERR"

# ── (d) directory symlink -> ABORT(19)
setup_case d
ln -s "$PJ/parent/subagents" "$PJ/child/linked-subagents"
run_case
check "d/exit19" 19 "$RC"
has "d/fields" "dir_symlinks=1 " "$ERR"

# ── (f) in-tree link whose target does NOT match the pattern -> ABORT(19)
setup_case f
printf '%s\n' "$LINE" > "$PJ/parent/notes.txt"
ln -s "$PJ/parent/notes.txt" "$PJ/child/subagents/agent-n.jsonl"
run_case
check "f/exit19" 19 "$RC"
has "f/affected" "MUSTER-PATTERN_MISMATCH" "$ERR"

# ── (g) in-tree link to a non-regular file (FIFO) -> ABORT(19)
setup_case g
mkfifo "$PJ/parent/pipe.jsonl"
ln -s "$PJ/parent/pipe.jsonl" "$PJ/child/subagents/agent-p.jsonl"
run_case
check "g/exit19" 19 "$RC"
has "g/affected" "MUSTER-NONREGULAR" "$ERR"

# ── (h) cyclic link -> ABORT(19)
setup_case h
ln -s "$PJ/child/subagents/loop2.jsonl" "$PJ/child/subagents/loop1.jsonl"
ln -s "$PJ/child/subagents/loop1.jsonl" "$PJ/child/subagents/loop2.jsonl"
run_case
check "h/exit19" 19 "$RC"
has "h/affected" "MUSTER-UNRESOLVABLE" "$ERR"

# ── (i) projects root reached via a symlink -> ABORT(19) root_is_symlink=ja
setup_case i
mv "$H/.claude/projects" "$CASE_DIR/real-projects"
ln -s "$CASE_DIR/real-projects" "$H/.claude/projects"
run_case
check "i/exit19" 19 "$RC"
has "i/fields" "root_is_symlink=ja " "$ERR"

TOTAL=$((PASS+FAIL))
echo "logbook-count-symlink-regression: $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ]
