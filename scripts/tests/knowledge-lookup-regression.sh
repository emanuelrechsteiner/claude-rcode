#!/usr/bin/env bash
# knowledge-lookup-regression.sh — regression suite for scripts/knowledge-lookup.sh
# (docs/OBSIDIAN.md, Stage 2/3, lookup v3) plus the "Library:" hint of hooks/session-start-context.sh.
#
# Pins: scope (only *.md in mirror/memory, rules, logbook, plans, evidence, adr, docs and the flat
# mirror/ledger/ folder; ledger.md only with --kind index; NEVER anything outside mirror/, no symlink
# followed), the kind tag per folder, frontmatter (only name:/description: searched; kind:/origin:/ids
# and provenance never), --max, --stack derivation, exit codes (0 ok, 1 library missing, 2 usage), the
# 160-char trim, and the v3 contract: word-boundary matching, BM25F-lite ranking, collision list,
# --kind/--project/--prefix, superseded ordering, ## Mentions, descriptions/tokens/sections, usage log.
#
# MECHANICS — synthetic HOME and knowledge dir under mktemp -d; the REAL script and the REAL hook are
# called with /bin/bash (rules/testing-quality.md "Verify Via the Same Code Path"). Never touches the
# real ~/.claude. All values are invented. bash 3.2 compatible.
# Usage: /bin/bash scripts/tests/knowledge-lookup-regression.sh
# check() evals its condition lazily: single-quoted conditions are expanded at eval time.
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
# shellcheck disable=SC2034 # variables are assigned for the other files sourced into this shell, not read here
#
# LAYOUT — cases live in scripts/tests/lib/ and are sourced in place (one shell, shared variables):
# kl-cases-stack.sh (--stack), kl-fixtures-rank.sh + kl-cases-rank.sh (v3 ranking/matching/filters),
# kl-cases-output.sh (kinds, output format, usage log, session-start hint), kl-cases-alt.sh (--alt fusion).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LK="$REPO_ROOT/scripts/knowledge-lookup.sh"
HOOK="$REPO_ROOT/hooks/session-start-context.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \xe2\x9c\x85 %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \xe2\x9d\x8c %s\n     %s\n' "$1" "$2"; }
check() { local l="$1" d="$2"; if eval "$3"; then ok "$l"; else bad "$l" "$d"; fi; }
summary() {
  echo
  echo "knowledge-lookup-regression: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
}

if [ ! -f "$LK" ]; then
  bad "script under test exists" "script not found: $LK"
  summary
fi

T="$(mktemp -d "${TMPDIR:-/tmp}/kl-regress.XXXXXX")" || { echo "ERROR: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
H="$T/home"; K="$T/know"; M="$K/mirror"; OUT="$T/out"; ERR="$T/err"
mkdir -p "$H/.claude" "$M/memory/proj" "$M/rules" "$M/logbook" "$M/plans" "$M/other" "$K/notes" "$T/foreign"

# ---- fixtures ---------------------------------------------------------------
PROV='<!-- knowledge-mirror: copied from ~/.claude/x.md at 2026-10-08T12:00:00Z; read-only copy, edits are refused on the next run -->'
w() { printf '%s\n' "${@:2}" > "$1"; }   # w <file> <line>...
w "$M/logbook/2026-01-01.md" "# Log" "the singletok lives here" "$PROV"
w "$M/memory/proj/z-both.md" "# Z" "rankone appears once" "ranktwo appears once"
w "$M/memory/proj/a-many.md" "# A" "rankone 1" "rankone 2" "rankone 3" "rankone 4" "rankone 5"
for n in 1 2 3; do w "$M/rules/max$n.md" "# R$n" "maxtok in rule $n"; done
w "$M/plans/fm.md" "---" "name: fmonlytok" "description: invented" "kindlike: fmkeytok" "---" "$PROV" "body without the word"
w "$M/plans/prov.md" "# P" "$(printf '<!-- knowledge-mirror: copied from ~/.claude/provtok.md at 2026-10-08T12:00:00Z; read-only copy -->')"
w "$M/memory/decoy.jsonl" '{"k":"jsonltok"}'
w "$M/other/x.md" "othertok in a directory outside the search scope"
w "$K/notes/secret.md" "outsidetok must never be found"
w "$M/ledger.md" "# Ledger" "- IMP-001 ledgertok entry"
w "$M/rules/case.md" "# C" "This has CaseMixTok inside"
w "$M/rules/metaa.md" "# A" "qmeta a.b literal dot"
w "$M/rules/metab.md" "# B" "qmeta axb would match only as a regex"
w "$M/memory/proj/zs.md" "# S" "uses zustand for state"
w "$M/memory/proj/nx.md" "# N" "the next framework router"
w "$M/memory/proj/sw.md" "# W" "SwiftyThing package notes"
LONG="longtok $(printf 'x%.0s' $(seq 1 400))"
w "$M/rules/long.md" "$LONG"
# multibyte trim fixtures (escapes only: 2-byte a-umlaut, 4-byte emoji)
rep() { local i=0 s=""; while [ "$i" -lt "$2" ]; do s="$s$1"; i=$((i+1)); done; printf '%s' "$s"; }
UML="$(printf '\303\244')"; EMO="$(printf '\360\237\230\200')"
w "$M/memory/proj/mb-a.md" "mbtok $(rep "$UML" 300)"
w "$M/memory/proj/mb-b.md" "mbtok $(rep "$EMO" 300)"
# ranking tie-breaks: same distinct count, different line count / identical counts
w "$M/memory/proj/tie-a-line.md" "# T" "tiealpha once"
w "$M/memory/proj/tie-b-lines.md" "# T" "tiealpha one" "tiealpha two" "tiealpha three"
w "$M/rules/p-c.md" "# P" "pathtok c"
w "$M/rules/p-a.md" "# P" "pathtok a"
w "$M/rules/p-b.md" "# P" "pathtok b"
# frontmatter edge cases
w "$M/plans/fm-body.md" "---" "description: bodyfmtok in the header" "---" "bodyfmtok in the body"
w "$M/plans/rule-body.md" "# Title" "bodyruletok before the rule" "---" "bodyruletok after the rule"
w "$M/plans/unclosed.md" "---" "name: unclosedtok" "no closing marker follows"
# symlink fixtures: everything they point at lives OUTSIDE the mirror
mkdir -p "$T/foreign/dir"
w "$T/foreign/linkfile.md" "symfiletok in a file outside the mirror"
w "$T/foreign/dir/inner.md" "symdirtok in a directory outside the mirror"
ln -s "$T/foreign/linkfile.md" "$M/memory/proj/link.md"
ln -s "$T/foreign/dir" "$M/memory/linkdir"

# lk <args...>: run the real script; sets RC, writes $OUT / $ERR. Env: HOME=$H, K set. The usage log is
# off here (KNOWLEDGE_LOOKUP_LOG=0) except in the log cases of kl-cases-output.sh.
lk() { KNOWLEDGE_LOOKUP_LOG=0 HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K" /bin/bash "$LK" "$@" >"$OUT" 2>"$ERR" </dev/null; RC=$?; }
first() { head -n 1 "$OUT"; }
has() { grep -qF -- "$1" "$2"; }
hasx() { grep -qxF -- "$1" "$2"; }   # whole-line match
blocks() { grep -c '^== ' "$OUT"; }
hdrs() { grep '^== ' "$OUT" | sed 's/  ~[0-9]* tok.*$//'; }   # headers without the "~n tok" tail
hdr() { hdrs | grep -qxF -- "$1"; }

echo "-- knowledge-lookup.sh --"

# ---- usage / config ----------------------------------------------------------
lk --help
check "help exits 0 and documents --stack" "rc=$RC out=$(cat "$OUT" "$ERR")" "test \"$RC\" -eq 0 && has \"--stack\" \"$OUT\""

lk
check "no args exits 2" "rc=$RC" "test \"$RC\" -eq 2"
check "no args prints usage on stderr" "$(cat "$ERR")" "test -s \"$ERR\""

HOME="$T/blank" CLAUDE_KNOWLEDGE_DIR="" /bin/bash "$LK" singletok >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "unset dir exits 1, empty stdout" "rc=$RC stdout=$(cat "$OUT")" "test \"$RC\" -eq 1 -a ! -s \"$OUT\""
check "unset dir explains on stderr" "$(cat "$ERR")" "has \"library not available\" \"$ERR\""

mkdir -p "$T/nomirror"
CLAUDE_KNOWLEDGE_DIR="$T/nomirror" HOME="$H" /bin/bash "$LK" singletok >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "dir set but mirror/ missing exits 1, empty stdout" "rc=$RC stdout=$(cat "$OUT")" "test \"$RC\" -eq 1 -a ! -s \"$OUT\""

mkdir -p "$T/h2/.claude"
printf 'export CLAUDE_KNOWLEDGE_DIR="%s"\n' "$K" > "$T/h2/.claude/env.local.sh"
env -u CLAUDE_KNOWLEDGE_DIR HOME="$T/h2" KNOWLEDGE_LOOKUP_LOG=0 /bin/bash "$LK" singletok >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "dir sourced from env.local.sh when env unset" "rc=$RC err=$(cat "$ERR")" "test \"$RC\" -eq 0 && has \"logbook/2026-01-01.md\" \"$OUT\""
CLAUDE_KNOWLEDGE_DIR="$T/nomirror" HOME="$T/h2" /bin/bash "$LK" singletok >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "environment wins over env.local.sh" "rc=$RC" "test \"$RC\" -eq 1"

# ---- matching ----------------------------------------------------------------
lk singletok
# v3 contract: hit-line format "   L<n> § <heading>: <text>" (was "<n>: <text>"); the heading above L2 is "Log".
check "single keyword finds the right file, exit 0" "rc=$RC out=$(cat "$OUT")" "test \"$RC\" -eq 0 && has \"== logbook/2026-01-01.md  [1/1]\" \"$OUT\" && hasx \"   L2 § Log: the singletok lives here\" \"$OUT\""
check "first line format" "$(first)" "test \"$(first | sed 's/ in .*//')\" = \"knowledge-lookup: 1 files match (1 keywords)\""

mkdir -p "$H/know3/mirror/memory"; w "$H/know3/mirror/memory/t.md" "tildetok"
HOME="$H" CLAUDE_KNOWLEDGE_DIR="$H/know3" KNOWLEDGE_LOOKUP_LOG=0 /bin/bash "$LK" tildetok >"$OUT" 2>"$ERR" </dev/null
check "mirror path shows \$HOME as ~" "$(first)" "has \" in ~/know3/mirror\" \"$OUT\""

lk rankone ranktwo
L1="$(hdrs | sed -n 1p)"; L2="$(hdrs | sed -n 2p)"
check "ranking: 2-of-2 file beats 1-of-2 file with more lines" "1st='$L1' 2nd='$L2'" "test \"$L1\" = \"== memory/proj/z-both.md  [2/2]  (memory)\" -a \"$L2\" = \"== memory/proj/a-many.md  [1/2]  (memory)\""
A_LINES="$(awk '/^== memory\/proj\/a-many/{f=1;next} /^== /{f=0} f&&/^   L[0-9]+ § /{n++} END{print n+0}' "$OUT")"
check "at most 3 matching lines per file block" "a-many lines=$A_LINES" "test \"$A_LINES\" -eq 3"

lk maxtok --max 1
check "--max 1 prints one block and the remainder line" "blocks=$(blocks) out=$(cat "$OUT")" "test \"$(blocks)\" -eq 1 && has \"... 2 more files (raise --max)\" \"$OUT\""

lk nonexistenttoken
check "zero hits: exit 0 and F=0 first line" "rc=$RC first=$(first)" "test \"$RC\" -eq 0 && has \"knowledge-lookup: 0 files match (1 keywords)\" \"$OUT\""

lk casemixtok
check "case-insensitive match" "$(cat "$OUT")" "has \"== rules/case.md\" \"$OUT\""

lk a.b
check "fixed-string match: a.b finds the literal file only (not axb)" "$(cat "$OUT")" "has \"== rules/metaa.md\" \"$OUT\" && ! has \"metab.md\" \"$OUT\""

lk ledgertok
# v3 contract: ledger.md is excluded by default (it repeats every IMP title); --kind index opts in.
check "mirror/ledger.md is NOT searched by default" "$(cat "$OUT")" "has \"0 files match\" \"$OUT\""
lk --kind index ledgertok
check "mirror/ledger.md is searched with --kind index" "$(cat "$OUT")" "has \"== ledger.md\" \"$OUT\""

lk longtok
EXP="   L1 § (top): ${LONG:0:160}"
check "ASCII line is cut to exactly 160 chars" "rc=$RC got=$(sed -n 2p "$OUT")" 'test "$RC" -eq 0 && hasx "$EXP" "$OUT"'

# Multibyte: the expectation is built independently (5 ASCII + 1 space + 154 characters = 160).
lk mbtok
EXP_A="   L1 § (top): mbtok $(rep "$UML" 154)"; EXP_B="   L1 § (top): mbtok $(rep "$EMO" 154)"
check "2-byte characters: cut at exactly 160 chars, whole characters, exit 0" "rc=$RC err=$(cat "$ERR")" 'test "$RC" -eq 0 && hasx "$EXP_A" "$OUT"'
check "4-byte characters: cut at exactly 160 chars, whole characters, exit 0" "rc=$RC" 'hasx "$EXP_B" "$OUT"'
check "multibyte output has exactly header + 2 blocks of 2 lines (nothing dropped or added)" "lines=$(wc -l < "$OUT")" 'test "$(wc -l < "$OUT" | tr -d " ")" -eq 5'
lk mbtok --max 1
check "multibyte with truncation: exit 0 and remainder line still printed" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && hasx "... 1 more files (raise --max)" "$OUT"'

# ---- ranking tie-breaks ------------------------------------------------------
lk tiealpha
check "same distinct count: more matching lines ranks first (not path order)" "$(hdrs)" 'test "$(hdrs | sed -n 1p)" = "== memory/proj/tie-b-lines.md  [1/1]  (memory)" -a "$(hdrs | sed -n 2p)" = "== memory/proj/tie-a-line.md  [1/1]  (memory)"'
lk pathtok
check "identical counts: path ascending (created c, a, b)" "$(hdrs | tr '\n' '|')" 'test "$(hdrs | tr "\n" "|")" = "== rules/p-a.md  [1/1]  (rule)|== rules/p-b.md  [1/1]  (rule)|== rules/p-c.md  [1/1]  (rule)|"'
lk pathtok --max 1
check "--max 1 shows the path-first file" "$(cat "$OUT")" 'hdr "== rules/p-a.md  [1/1]  (rule)" && ! has "p-b.md" "$OUT" && hasx "... 2 more files (raise --max)" "$OUT"'

# ---- exclusions (mechanical pins) -------------------------------------------
excluded() { # <keyword> <label>
  lk "$1"
  check "$2" "rc=$RC out=$(cat "$OUT")" "test \"$RC\" -eq 0 && has \"0 files match\" \"$OUT\" && test \"$(blocks)\" -eq 0"
}
# v3 contract: frontmatter name: and description: ARE searched; every other key never is.
lk fmonlytok
check "frontmatter name: IS searched (v3), shown without a hit line" "rc=$RC out=$(cat "$OUT")" 'hdr "== plans/fm.md  [1/1]  (plan)" && ! has "   L" "$OUT"'
excluded fmkeytok "other frontmatter keys do NOT count"
excluded provtok "provenance comment line does NOT count"
excluded jsonltok ".jsonl decoy under mirror/ is never searched"
excluded outsidetok "file OUTSIDE mirror/ is never searched"
excluded othertok "mirror/ subdir outside the search scope is not searched"
excluded symfiletok "symlinked FILE under memory/ pointing outside mirror/ is not followed"
excluded symdirtok "symlinked SUBDIRECTORY under memory/ pointing outside mirror/ is not followed"

# Scope: a symlinked ledger.md and a symlinked top-level scope dir (separate libraries).
w "$T/foreign/ledger-out.md" "symledgertok outside"
w "$T/foreign/plansdir-in.md" "symplanstok outside"
for v in ledger plans; do
  mkdir -p "$T/know-$v/mirror/memory"; w "$T/know-$v/mirror/memory/ok.md" "controltok"
done
ln -s "$T/foreign/ledger-out.md" "$T/know-ledger/mirror/ledger.md"
ln -s "$T/foreign" "$T/know-plans/mirror/plans"
HOME="$H" CLAUDE_KNOWLEDGE_DIR="$T/know-ledger" KNOWLEDGE_LOOKUP_LOG=0 /bin/bash "$LK" --kind memory,index symledgertok controltok >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "symlinked ledger.md is not followed even with --kind index (control file still found)" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "== memory/ok.md" "$OUT" && ! has "ledger.md" "$OUT"'
HOME="$H" CLAUDE_KNOWLEDGE_DIR="$T/know-plans" KNOWLEDGE_LOOKUP_LOG=0 /bin/bash "$LK" symplanstok controltok >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "symlinked scope directory (plans -> outside) is not descended (control found)" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "== memory/ok.md" "$OUT" && ! has "symplanstok" "$OUT" && ! has "== plans/" "$OUT"'

# Frontmatter edge cases: only name:/description: of a CLOSED block are searched; hit lines come from the body.
lk bodyfmtok
check "frontmatter file: description hit shown as description, hit line only from the body (line 4)" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "knowledge-lookup: 1 files match" "$OUT" && hdr "== plans/fm-body.md  [1/1]  (plan)" && hasx "   » bodyfmtok in the header" "$OUT" && hasx "   L4 § (top): bodyfmtok in the body" "$OUT" && ! has "L2 " "$OUT"'
lk bodyruletok
check "no frontmatter: a body '---' rule excludes nothing (lines 2 and 4 both match)" "rc=$RC out=$(cat "$OUT")" 'hasx "   L2 § Title: bodyruletok before the rule" "$OUT" && hasx "   L4 § Title: bodyruletok after the rule" "$OUT"'
lk unclosedtok
check "unclosed frontmatter is no frontmatter: its lines match" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && hdr "== plans/unclosed.md  [1/1]  (plan)" && hasx "   L2 § (top): name: unclosedtok" "$OUT"'

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/kl-cases-stack.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/kl-fixtures-rank.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/kl-cases-rank.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/kl-cases-output.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/kl-cases-alt.sh"

summary
