#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: eval bodies expand at run time
# knowledge-eval-regression cases. Sourced by scripts/tests/knowledge-eval-regression.sh (never run on
# its own); shares its helpers and fixtures (T K M OUT ERR RC EVAL LK check ev has hasx mkq qrow ...).

Q="$T/q.tsv"
mkq "$Q" \
  "$(qrow R1 dev alphatok memory/p/a1.md lookup yes)" \
  "$(qrow R2 dev betatok memory/p/b3.md lookup no)" \
  "$(qrow R3 dev gammatok rules/nope.md lookup yes)" \
  "$(qrow R4 dev deltatok 'rules/nope.md|rules/d1.md' lookup yes)" \
  "$(qrow R5 dev alphatok - lookup yes)" \
  "$(qrow R6 dev '"zed yarn"' logbook/ph1.md lookup yes)" \
  "$(qrow R7 dev alphatok memory/p/a1.md structural yes)" \
  "$(qrow T1 test alphatok memory/p/a1.md lookup yes)"
ev --set dev --questions "$Q" --no-history --verbose
check "dev summary: n=5 hit@1=3 hit@3=4 mrr10=0.667 unconfirmed=1" "rc=$RC $(cat "$OUT" "$ERR")" \
  'test "$RC" -eq 0 && evalline | grep -q "^EVAL dev n=5 hit@1=3/5 hit@3=4/5 hit@10=4/5 mrr10=0.667 tta_median=[0-9]* tta_p90=[0-9]* unconfirmed=1 mode=single runtime=[0-9.]*s$"'
check "hit@1 row: rank=1" "$(cat "$OUT")" 'grep -q "^ROW R1 rank=1 tta=" "$OUT"'
check "hit@3-only row: rank=3, not listed as MISS" "$(cat "$OUT")" 'grep -q "^ROW R2 rank=3 " "$OUT" && ! grep -q "^MISS R2" "$OUT"'
check "miss row: MISS line with rank=- and top3" "$(cat "$OUT")" 'hasx "MISS R3 q=\"gammatok\" expected=rules/nope.md rank=-, top3=rules/c1.md" "$OUT"'
check "miss row: ROW flagged tta-miss" "$(cat "$OUT")" 'grep -q "^ROW R3 rank=0 tta=[0-9]* tta-miss$" "$OUT"'
check "| alternatives: any one expected path is a hit (rank 1)" "$(cat "$OUT")" 'grep -q "^ROW R4 rank=1 " "$OUT"'
check "quoted phrase stays one keyword (rank 1, loose-words file would win if split)" "$(cat "$OUT")" 'grep -q "^ROW R6 rank=1 " "$OUT"'
check "- expected row is unscored: no ROW, not in n" "$(cat "$OUT")" '! grep -q "^ROW R5" "$OUT"'
check "structural row: SKIP line, no ROW" "$(cat "$OUT")" 'hasx "SKIP R7 class=structural" "$OUT" && ! grep -q "^ROW R7" "$OUT"'
check "set filter: test rows are not scored in dev" "$(cat "$OUT")" '! grep -q "T1" "$OUT"'

ev --set test --questions "$Q" --no-history
check "test set: n=1 hit@1=1/1 mrr10=1.000" "$(cat "$OUT")" 'evalline | grep -q "^EVAL test n=1 hit@1=1/1 hit@3=1/1 hit@10=1/1 mrr10=1.000 "'
ev --questions "$Q" --no-history
check "set all (default): n=6" "$(cat "$OUT")" 'evalline | grep -q "^EVAL all n=6 "'

# tta proxy: lookup stdout bytes + the listed files up to the expected one, /4; recomputed independently
mkq "$T/q1.tsv" "$(qrow A1 dev alphatok memory/p/a1.md lookup yes)"
ev --questions "$T/q1.tsv" --no-history --verbose
LKB=$(CLAUDE_KNOWLEDGE_DIR="$K" /bin/bash "$LK" --max 10 -- alphatok | wc -c | tr -d ' '); FSZ=$(wc -c < "$M/memory/p/a1.md" | tr -d ' ')
WANT=$(( (LKB + FSZ) / 4 ))
check "tta = (lookup bytes + file bytes) / 4 = $WANT" "$(cat "$OUT")" 'grep -q "^ROW A1 rank=1 tta=$WANT$" "$OUT" && evalline | grep -q "tta_median=$WANT tta_p90=$WANT "'
mkq "$T/q2.tsv" "$(qrow A2 dev betatok memory/p/b3.md lookup yes)"
ev --questions "$T/q2.tsv" --no-history
check "rank-3 row: hit@1=0/1 hit@3=1/1" "$(cat "$OUT")" 'evalline | grep -q "hit@1=0/1 hit@3=1/1 hit@10=1/1 mrr10=0.333 "'

# extra unknown column and permuted column order
{ printf 'id\tquery\trationale\texpected\tset\tclass\tsource\tconfirmed\n'
  printf 'X1\talphatok\twhy\tmemory/p/a1.md\tdev\tlookup\tsyn\tyes\n'; } > "$T/q3.tsv"
ev --questions "$T/q3.tsv" --no-history
check "unknown extra column ignored, columns selected by name" "rc=$RC $(cat "$OUT" "$ERR")" 'test "$RC" -eq 0 && evalline | grep -q "^EVAL all n=1 hit@1=1/1 "'

# EVAL SKIP paths: exit 3, stderr only, never a pass line
ev --questions "$T/does-not-exist.tsv" --no-history
check "missing question file: EVAL SKIP on stderr, exit 3, empty stdout" "rc=$RC out=$(cat "$OUT") err=$(cat "$ERR")" 'test "$RC" -eq 3 && grep -q "^EVAL SKIP no question file at $T/does-not-exist.tsv$" "$ERR" && test ! -s "$OUT"'
ev --no-history
check "default question file path is <K>/eval/questions.tsv" "$(cat "$ERR")" 'test "$RC" -eq 3 && grep -q "no question file at $K/eval/questions.tsv" "$ERR"'
mkq "$T/q4.tsv" "$(qrow S1 dev alphatok memory/p/a1.md lookup yes)"
ev --set test --questions "$T/q4.tsv" --no-history
check "set without rows: EVAL SKIP, exit 3, empty stdout" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 3 && grep -q "^EVAL SKIP set test has no rows$" "$ERR" && test ! -s "$OUT"'
mkq "$T/q5.tsv" "$(qrow S1 dev alphatok - lookup yes)" "$(qrow S2 dev alphatok memory/p/a1.md structural yes)"
ev --questions "$T/q5.tsv" --no-history
check "only unscored/structural rows: EVAL SKIP, exit 3, no pass line" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 3 && ! grep -q "^EVAL dev" "$OUT" && grep -q "EVAL SKIP" "$ERR"'

# fail-loud: malformed input and environment
printf '%s\n' "$HDR" "S1	dev	alphatok" > "$T/bad1.tsv"
ev --questions "$T/bad1.tsv" --no-history
check "row with too few fields: exit 2, names the line" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 2 && grep -q "bad1.tsv:2:" "$ERR" && test ! -s "$OUT"'
mkq "$T/bad2.tsv" "$(qrow S1 dev alphatok memory/p/a1.md bogus yes)"
ev --questions "$T/bad2.tsv" --no-history
check "unknown class: exit 2" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 2 && grep -q "bad class" "$ERR"'
mkq "$T/bad3.tsv" "$(qrow S1 dev alphatok memory/p/a1.md lookup maybe)"
ev --questions "$T/bad3.tsv" --no-history
check "bad confirmed value: exit 2" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 2 && grep -q "confirmed must be" "$ERR"'
mkq "$T/bad4.tsv" "$(qrow S1 dev alphatok memory/p/a1.md lookup yes)" "$(qrow S1 dev alphatok memory/p/a1.md lookup yes)"
ev --questions "$T/bad4.tsv" --no-history
check "duplicate id: exit 2" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 2 && grep -q "duplicate id" "$ERR"'
printf 'id\tset\tquery\n' > "$T/bad5.tsv"
ev --questions "$T/bad5.tsv" --no-history
check "header without required column: exit 2" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 2 && grep -q "header lacks column" "$ERR"'
mkq "$T/bad6.tsv" "$(qrow S1 dev '"alphatok' memory/p/a1.md lookup yes)"
ev --questions "$T/bad6.tsv" --no-history
check "unterminated quote in query: exit 2" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 2 && grep -q "unterminated quote" "$ERR"'
env -u CLAUDE_KNOWLEDGE_DIR /bin/bash "$EVAL" --no-history >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "CLAUDE_KNOWLEDGE_DIR unset: exit 1, explained" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 1 && grep -q "CLAUDE_KNOWLEDGE_DIR is not set" "$ERR"'
mkdir -p "$T/nomirror"
CLAUDE_KNOWLEDGE_DIR="$T/nomirror" /bin/bash "$EVAL" --no-history >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "mirror missing: exit 1, explained" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 1 && grep -q "mirror missing" "$ERR"'
ev --bogus
check "unknown flag: exit 2" "rc=$RC" 'test "$RC" -eq 2'
ev --help
check "help documents the tta proxy and the exit codes" "rc=$RC" 'test "$RC" -eq 0 && has "PROXY" "$OUT" && has "Exit codes" "$OUT"'

# history: --no-history writes nothing; a normal run appends one 12-column line
HF="$K/eval/history.tsv"
ev --questions "$Q" --set dev --no-history
check "--no-history writes no history file" "rc=$RC" 'test "$RC" -eq 0 && test ! -e "$HF"'
ev --questions "$Q" --set dev
check "history: header + one line after the first run" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 0 && test "$(wc -l < "$HF" | tr -d " ")" -eq 2'
check "history header has 13 columns, hit10 is 6, last is mode" "$(head -n 1 "$HF")" 'test "$(head -n 1 "$HF" | awk -F"\t" "{print NF}")" -eq 13 && test "$(head -n 1 "$HF" | cut -f13)" = mode && test "$(head -n 1 "$HF" | cut -f6)" = hit10'
check "history line has 13 columns with set, n, hit1, hit3, stamp, hash" "$(sed -n 2p "$HF")" 'test "$(sed -n 2p "$HF" | awk -F"\t" "{print NF}")" -eq 13 && test "$(sed -n 2p "$HF" | cut -f13)" = single && test "$(sed -n 2p "$HF" | cut -f6)" = 4 && test "$(sed -n 2p "$HF" | cut -f2-5)" = "$(printf "dev\t5\t3\t4")" && test "$(sed -n 2p "$HF" | cut -f11)" = "2026-10-09T08:47:44Z" && test -n "$(sed -n 2p "$HF" | cut -f12)"'
ev --questions "$Q" --set dev
check "second run appends (3 lines, header once)" "$(cat "$HF")" 'test "$(wc -l < "$HF" | tr -d " ")" -eq 3 && test "$(grep -c "^timestamp" "$HF")" -eq 1'
rm "$M/README.md"
ev --questions "$Q" --set dev
check "history without mirror stamp: exit 1, explained" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 1 && grep -q "mirror stamp" "$ERR"'

# --alts: one lookup per row, query = primary keywords, each "|" set = one --alt before "--"
echo "-- --alts --"
rm -f "$T/shim.log"
mkqa "$T/a1.tsv" "$(arow A1 alphatok memory/p/a1.md 'betatok|gammatok two')"
eva --questions "$T/a1.tsv" --alts --no-history --verbose
WANTARGV=$(printf '%s\n' --call-- --max 10 --alt betatok --alt 'gammatok two' -- alphatok)
check "alts: one call, --alt per set, all before -- and the query as primary" "rc=$RC $(cat "$T/shim.log" 2>&1)" 'test "$RC" -eq 0 && test "$(cat "$T/shim.log")" = "$WANTARGV"'
check "alts: --verbose ROW shows sets=2" "$(cat "$OUT")" 'grep -q "^ROW A1 rank=1 tta=[0-9]* sets=2$" "$OUT"'
LKB=$(CLAUDE_KNOWLEDGE_DIR="$K" /bin/bash "$LK" --max 10 -- alphatok | wc -c | tr -d ' ')
WANT=$(( (LKB + $(wc -c < "$M/memory/p/a1.md" | tr -d ' ')) / 4 ))
check "alts: tta counts the single fused output = $WANT" "$(cat "$OUT")" 'grep -q "tta=$WANT sets=2" "$OUT"'

rm -f "$T/shim.log"
mkqa "$T/a2.tsv" "$(arow A1 alphatok memory/p/a1.md 'betatok')" "$(arow A2 alphatok memory/p/a1.md '')" "$(arow A3 betatok memory/p/b1.md 'x|y|z')"
eva --questions "$T/a2.tsv" --alts --no-history --verbose
check "alts: EVAL line has mode=alts and no_alts=1 after unconfirmed" "rc=$RC $(cat "$OUT" "$ERR")" 'test "$RC" -eq 0 && evalline | grep -q "^EVAL all n=3 .* unconfirmed=0 mode=alts no_alts=1 runtime=[0-9.]*s$"'
check "alts: row without alts runs once without --alt, sets=1" "$(cat "$OUT")" 'grep -q "^ROW A2 rank=1 tta=[0-9]* sets=1$" "$OUT" && grep -q "^ROW A3 rank=1 tta=[0-9]* sets=3$" "$OUT" && test "$(grep -c -- "--alt" "$T/shim.log")" -eq 4'

rm -f "$T/shim.log"
eva --questions "$T/a2.tsv" --no-history --verbose
check "no --alts: alts column ignored, no --alt passed, mode=single, no no_alts" "rc=$RC $(cat "$OUT" "$ERR")" 'test "$RC" -eq 0 && ! has "--alt" "$T/shim.log" && evalline | grep -q " unconfirmed=0 mode=single runtime=" && ! grep -q "no_alts" "$OUT" && ! grep -q "sets=" "$OUT"'

rm -f "$T/shim.log"
mkqa "$T/a3.tsv" "$(arow Q1 alphatok memory/p/a1.md "it's \"quoted\" \$HOME")"
eva --questions "$T/a3.tsv" --alts --no-history
check "alts with quote characters pass through verbatim as one argument" "rc=$RC $(cat "$T/shim.log" "$ERR")" 'test "$RC" -eq 0 && grep -qxF "it'"'"'s \"quoted\" \$HOME" "$T/shim.log"'

eva --questions "$Q" --alts --no-history
check "--alts without an alts column: EVAL SKIP, exit 3, empty stdout" "rc=$RC out=$(cat "$OUT") err=$(cat "$ERR")" 'test "$RC" -eq 3 && grep -q "^EVAL SKIP no alts column" "$ERR" && test ! -s "$OUT"'
mkqa "$T/a4.tsv" "$(arow Q1 alphatok memory/p/a1.md 'betatok||gammatok')"
eva --questions "$T/a4.tsv" --alts --no-history
check "alts with an empty set: exit 2, names the row" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 2 && grep -q "Q1: alts has an empty set" "$ERR"'
ev --help
check "help documents --alts and the alts column in at most 40 lines" "lines=$(wc -l < "$OUT")" 'has "--alts" "$OUT" && has "alts column" "$OUT" && test "$(wc -l < "$OUT")" -le 40'

# history: mode column, upgrade of an old 11-column header, refusal of a foreign header
HF="$K/eval/history.tsv"; rm -f "$HF"
w "$M/README.md" "# Knowledge mirror" "Last run: 2026-10-09T08:47:44Z (UTC)."
eva --questions "$T/a2.tsv" --alts
check "history: alts run records mode=alts in column 13" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 0 && test "$(sed -n 2p "$HF" | cut -f13)" = alts'
OLDH=$(head -n 1 "$HF" | cut -f1-5,7-12)
printf '%s\nold\trow\n' "$OLDH" > "$HF"
eva --questions "$T/a2.tsv" --alts
check "history: old 11-column header is upgraded, old rows kept, new row has 13" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 0 && test "$(head -n 1 "$HF" | cut -f13)" = mode && test "$(sed -n 2p "$HF")" = "$(printf "old\trow")" && test "$(sed -n 3p "$HF" | cut -f13)" = alts && test "$(wc -l < "$HF" | tr -d " ")" -eq 3'
printf 'foo\tbar\n' > "$HF"
eva --questions "$T/a2.tsv" --alts
check "history: foreign header fails loud (exit 1), file untouched" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 1 && grep -q "unexpected header" "$ERR" && test "$(cat "$HF")" = "$(printf "foo\tbar")"'

# hit@10: the window the agent sees (rank 1..10), counted independently of hit@3
mkq "$T/h1.tsv" "$(qrow H1 dev hundtok memory/hund/h06.md lookup yes)"
ev --questions "$T/h1.tsv" --no-history --verbose
check "hit@10 counts a rank-7 row; hit@3 does not" "rc=$RC $(cat "$OUT" "$ERR")" 'grep -q "^ROW H1 rank=7 " "$OUT" && evalline | grep -q "hit@3=0/1 hit@10=1/1 mrr10=0.143 "'
mkq "$T/h2.tsv" "$(qrow H2 dev hundtok memory/hund/h02.md lookup yes)"
ev --questions "$T/h2.tsv" --no-history --verbose --max 12
check "hit@10 does not count a rank-11 row" "rc=$RC $(cat "$OUT" "$ERR")" 'grep -q "^ROW H2 rank=11 " "$OUT" && evalline | grep -q "hit@3=0/1 hit@10=0/1 mrr10=0.000 "'
mkq "$T/h3.tsv" "$(qrow H3 dev hundtok memory/hund/h06.md lookup yes)" "$(qrow H4 dev gammatok rules/nope.md lookup yes)" "$(qrow H5 dev alphatok memory/p/a1.md lookup yes)"
ev --questions "$T/h3.tsv" --no-history
check "hit@10 does not count a miss; EVAL field order hit@1 hit@3 hit@10 mrr10" "rc=$RC $(cat "$OUT" "$ERR")" 'evalline | grep -q "^EVAL all n=3 hit@1=1/3 hit@3=1/3 hit@10=2/3 mrr10=0.381 tta_median="'
ev --help
check "help mentions hit@10 within 40 lines" "lines=$(wc -l < "$OUT")" 'has "hit@10" "$OUT" && test "$(wc -l < "$OUT")" -le 40'
HF="$K/eval/history.tsv"
printf '%s\n' "$(printf 'timestamp\tset\tn\thit1\thit3\tmrr10\ttta_median\ttta_p90\truntime_s\tmirror_stamp\tlookup_git_hash\tmode')" "old12" > "$HF"
ev --questions "$T/h3.tsv" --set dev
check "history: 12-column header is upgraded to 13 (header only), hit10 recorded" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 0 && test "$(head -n 1 "$HF" | cut -f6)" = hit10 && test "$(head -n 1 "$HF" | awk -F"\t" "{print NF}")" -eq 13 && test "$(sed -n 2p "$HF")" = old12 && test "$(sed -n 3p "$HF" | cut -f6)" = 2'
