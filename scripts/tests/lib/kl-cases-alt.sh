#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016,SC2034 # single quotes are intended: the check bodies expand at run time, not here
# knowledge-lookup-regression cases: --alt (several keyword sets in one call, best-rank-first fusion; --fuse rrf).
# Sourced last by scripts/tests/knowledge-lookup-regression.sh (never run on its own); shares its
# helpers and fixtures (lk lkl check has hasx hdr hdrs blocks first order K2 K M T LOGF ...).

echo "-- lookup: --alt (fused keyword sets) --"

# ---- fixtures (every token invented, unique to this file) ----------------------------------
w "$M/memory/proj/alt-a.md" "# A" "alphaalt appears here"
w "$M/memory/proj/alt-b.md" "# B" "betaalt appears here"
w "$M/rules/alt-rule.md" "# R" "alphaalt in a rule"
# RRF: gammaalt: many lines in y-g (rank 1), one in x-both (rank 2); deltaalt only in x-both (rank 1)
w "$M/memory/proj/alt-y-g.md" "# Y" "gammaalt 1" "gammaalt 2" "gammaalt 3" "gammaalt 4" "gammaalt 5"
w "$M/memory/proj/alt-x-both.md" "# X" "gammaalt and deltaalt together"
# best set: z matches both words of the 2-keyword set on one line, the 1-keyword set once
w "$M/memory/proj/alt-z.md" "# Z" "epsilonalt zetaalt etaalt on one line" "etaalt again"
w "$M/memory/proj/alt-z2.md" "# Z2" "zetaalt alone"

# best-rank fixture (D12 shape): p is rank 1 in set bfa only; q is rank 3 in each of bfa, bfb, bfc
w "$M/memory/proj/bf-p.md" "# P" "bfa 1" "bfa 2" "bfa 3" "bfa 4" "bfa 5"
w "$M/memory/proj/bf-u1.md" "# U1" "bfa 1" "bfa 2" "bfa 3" "bfa 4"
w "$M/memory/proj/bf-v1.md" "# V1" "bfb 1" "bfb 2" "bfb 3" "bfb 4" "bfb 5"
w "$M/memory/proj/bf-v2.md" "# V2" "bfb 1" "bfb 2" "bfb 3" "bfb 4"
w "$M/memory/proj/bf-w1.md" "# W1" "bfc 1" "bfc 2" "bfc 3" "bfc 4" "bfc 5"
w "$M/memory/proj/bf-w2.md" "# W2" "bfc 1" "bfc 2" "bfc 3" "bfc 4"
w "$M/memory/proj/bf-q.md" "# Q" "bfa x" "bfb x" "bfc x"

altmark() { grep -c 'sets=' "$OUT"; }
fl() { first | sed 's/) in .*$/)/'; }   # first line without the mirror path

# ---- union of two sets, sets= marker ---------------------------------------------------------
lk alphaalt --alt betaalt
check "union: a file from each set is found" "$(cat "$OUT")" 'test "$RC" -eq 0 && has "== memory/proj/alt-a.md" "$OUT" && has "== memory/proj/alt-b.md" "$OUT" && has "== rules/alt-rule.md" "$OUT"'
check "first line names keywords and sets" "$(first)" 'test "$(fl)" = "knowledge-lookup: 3 files match (2 keywords in 2 sets)"'
check "a file found by one set only has no sets= marker" "$(cat "$OUT")" 'test "$(altmark)" -eq 0'
lk gammaalt --alt deltaalt
check "best rank tie (both rank 1): RRF sum decides, x-both (rank 2 + rank 1) before y-g (item: was plain RRF)" "$(order)" 'test "$(order)" = "memory/proj/alt-x-both.md memory/proj/alt-y-g.md "'
check "sets=2 only on the file found by both sets" "$(grep '^== ' "$OUT")" 'grep "^== memory/proj/alt-x-both.md" "$OUT" | grep -q "  sets=2" && ! grep "^== memory/proj/alt-y-g.md" "$OUT" | grep -q sets='
lk deltaalt --alt gammaalt
check "fusion is symmetric in the order of the sets" "$(order)" 'test "$(order)" = "memory/proj/alt-x-both.md memory/proj/alt-y-g.md "'
lk gammaalt --alt gammaalt
check "two identical sets: same files as one set, sets=2 on each" "$(order)" 'test "$(order)" = "memory/proj/alt-y-g.md memory/proj/alt-x-both.md " && test "$(altmark)" -eq 2'

# ---- header [k/n] of the best set -------------------------------------------------------------
lk etaalt --alt "epsilonalt zetaalt etaalt"
check "[k/n] is that of the best set (3/3, not 1/1) and carries sets=2" "$(grep '^== ' "$OUT")" 'grep "^== memory/proj/alt-z.md  \[3/3\]" "$OUT" | grep -q "  sets=2"'
check "a file found by one set keeps that set's n (alt-z2: 1/3)" "$(grep '^== ' "$OUT")" 'grep -q "^== memory/proj/alt-z2.md  \[1/3\]" "$OUT" && ! grep "^== memory/proj/alt-z2.md" "$OUT" | grep -q sets='

# ---- empty primary, parsing, validation --------------------------------------------------------
lk --alt alphaalt
check "empty primary with one --alt: exit 0, files found" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "== memory/proj/alt-a.md" "$OUT" && test "$(fl)" = "knowledge-lookup: 2 files match (1 keywords in 1 sets)"'
lk --alt "  alphaalt   betaalt "
check "an --alt value is split on whitespace into keywords" "$(first)" 'test "$(fl)" = "knowledge-lookup: 3 files match (2 keywords in 1 sets)"'
lk --alt=alphaalt --alt=betaalt
check "--alt=VALUE form and repetition work" "$(first)" 'test "$RC" -eq 0 && test "$(fl)" = "knowledge-lookup: 3 files match (2 keywords in 2 sets)"'
lk alphaalt --alt "alphaalt gammaalt"
check "keyword count is the union of distinct keywords over all sets" "$(first)" 'test "$(fl)" = "knowledge-lookup: 4 files match (2 keywords in 2 sets)"'
lk --alt
check "--alt without a value exits 2 with usage" "rc=$RC" 'test "$RC" -eq 2 && has "--alt" "$ERR"'
lk --alt ""
check "--alt with an empty value exits 2" "rc=$RC" 'test "$RC" -eq 2'
lk --alt "   "
check "--alt with only whitespace exits 2" "rc=$RC" 'test "$RC" -eq 2'

# ---- filters and collision list apply to every set ------------------------------------------------
lk alphaalt --alt zustand
check "collision list applies to an --alt set: German 'Zustand' stays out, the store note is in" "$(order)" 'has "memory/proj/en-store.md" "$OUT" && ! has "de-noun" "$OUT"'
lk --kind rule --alt alphaalt --alt betaalt
check "--kind applies to every set: only the rule is found" "$(order)" 'test "$(order)" = "rules/alt-rule.md "'
lk --project proj-alpha --alt kindtok --alt alphaalt
check "--project applies to every set" "$(order)" 'test "$(order)" = "memory/proj-alpha/a.md "'
lk --prefix --alt alphaal
check "--prefix applies to --alt sets" "$(order)" 'has "memory/proj/alt-a.md" "$OUT"'

# ---- ordering rules after fusion --------------------------------------------------------------------
lk pathtok --alt pathtok
check "ties after fusion: path ascending" "$(order)" 'test "$(order)" = "rules/p-a.md rules/p-b.md rules/p-c.md "'
lk suptok
BASE_ORDER="$(order)"
lk suptok --alt suptok
check "superseded ordering still applies after fusion" "$(order)" 'test "$(order)" = "$BASE_ORDER"'
lk --max 1 gammaalt --alt deltaalt
check "--max cuts after fusion: top fused file plus the remainder line" "$(cat "$OUT")" 'test "$(order)" = "memory/proj/alt-x-both.md " && has "... 1 more files (raise --max)" "$OUT"'

# ---- --fuse best|rrf ----------------------------------------------------------------------------------
BEST_ORD="memory/proj/bf-p.md memory/proj/bf-v1.md memory/proj/bf-w1.md memory/proj/bf-u1.md memory/proj/bf-v2.md memory/proj/bf-w2.md memory/proj/bf-q.md "
lk bfa --alt bfb --alt bfc
check "best is the default: rank 1 in one set (p) outranks rank 3 in all three sets (q)" "$(order)" 'test "$(order)" = "$BEST_ORD"'
lk bfa --alt bfb --alt bfc --fuse best
check "--fuse best equals the default order" "$(order)" 'test "$(order)" = "$BEST_ORD"'
lk bfa --alt bfb --alt bfc --fuse rrf
check "--fuse rrf reproduces pure RRF: q (3 sets) first, then the rank-1 files, then rank 2" "$(order)" 'test "$(order)" = "memory/proj/bf-q.md memory/proj/bf-p.md memory/proj/bf-v1.md memory/proj/bf-w1.md memory/proj/bf-u1.md memory/proj/bf-v2.md memory/proj/bf-w2.md "'
lk bfa --alt bfb --alt bfc --fuse=rrf
check "--fuse=rrf form works" "$(order)" 'test "$(order | cut -d" " -f1)" = "memory/proj/bf-q.md"'
lk bfa --alt bfb --alt bfc --fuse best
check "sets= unchanged under best: only q carries sets=3, header counts 3 sets" "$(grep '^== ' "$OUT")" 'test "$(altmark)" -eq 1 && grep "^== memory/proj/bf-q.md" "$OUT" | grep -q "  sets=3" && test "$(fl)" = "knowledge-lookup: 7 files match (3 keywords in 3 sets)"'
lk bfa --alt bfb --alt bfc --fuse rrf
check "sets= unchanged under rrf: only q carries sets=3" "$(grep '^== ' "$OUT")" 'test "$(altmark)" -eq 1 && grep "^== memory/proj/bf-q.md" "$OUT" | grep -q "  sets=3"'
lk bfc --alt bfb --alt bfa
check "best is symmetric in set order up to the rank-1 path tie-break (q last)" "$(order)" 'test "$(order | awk "{print \$NF}")" = "memory/proj/bf-q.md" && test "$(order | cut -d" " -f1)" = "memory/proj/bf-p.md"'
lk gammaalt --alt deltaalt --fuse best
check "best: rank tie broken by RRF sum (x-both before y-g)" "$(order)" 'test "$(order)" = "memory/proj/alt-x-both.md memory/proj/alt-y-g.md "'
lk suptok --alt suptok --fuse rrf
check "superseded ordering still applies after fusion under rrf" "$(order)" 'test "$(order)" = "$BASE_ORDER"'
lk bfa --alt bfb --fuse sum
check "--fuse with an invalid value exits 2 with usage" "rc=$RC" 'test "$RC" -eq 2 && has "--fuse" "$ERR"'
lk bfa --fuse
check "--fuse without a value exits 2" "rc=$RC" 'test "$RC" -eq 2'

# ---- unchanged without --alt ----------------------------------------------------------------------------
lk pathtok
check "without --alt: first line keeps '(N keywords)' and no sets= marker" "$(first)" 'test "$(fl)" = "knowledge-lookup: 3 files match (1 keywords)" && test "$(altmark)" -eq 0'

# ---- usage log ------------------------------------------------------------------------------------------
lkl pathtok --alt rankone --alt "kindtok x"
check "log: query column = primary keywords + ' || <alt set>' per alt" "$(tail -n 1 "$LOGF")" 'test "$(tail -n 1 "$LOGF" | cut -f2)" = "pathtok || rankone || kindtok x"'
lkl --alt alphaalt
check "log: empty primary gives ' || <alt set>'" "$(tail -n 1 "$LOGF")" 'test "$(tail -n 1 "$LOGF" | cut -f2)" = " || alphaalt" && test "$(tail -n 1 "$LOGF" | cut -f3)" = "rules/alt-rule.md|memory/proj/alt-a.md"'

# ---- --help ---------------------------------------------------------------------------------------------
lk --help
check "help has the 4-line retrieval protocol and documents --alt" "$(cat "$OUT")" 'has "Retrieval protocol: run 2-4 keyword sets in ONE call" "$OUT" && has "translation (German/English)" "$OUT" && has "technical terms behind it" "$OUT" && has "Judge by the \"»\" description lines" "$OUT" && has "open only the top note'"'"'s section (L<n>)" "$OUT" && has "--alt" "$OUT" && has "--fuse best|rrf" "$OUT" && test "$(sed -n "/^Retrieval protocol/,\$p" "$OUT" | wc -l | tr -d " ")" -eq 4'
check "help stays at most 40 lines" "lines=$(wc -l < "$OUT")" 'test "$(wc -l < "$OUT" | tr -d " ")" -le 40'

# ---- runtime: 3 sets on the 600-file fixture ------------------------------------------------------------
T0="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
KNOWLEDGE_LOOKUP_LOG=0 HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K2" /bin/bash "$LK" speedtok --alt topic --alt "filler text" >"$OUT" 2>"$ERR" </dev/null; RC=$?
T1="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
EL="$(perl -e "printf '%.3f', $T1 - $T0")"
check "runtime for 3 sets on 600 files <= 1.2 s (took ${EL}s)" "rc=$RC took ${EL}s" "test \"$RC\" -eq 0 && perl -e \"exit(($EL <= 1.2) ? 0 : 1)\""
check "3 sets on 600 files: all 600 files fused, 3 sets reported" "$(first)" 'test "$(fl)" = "knowledge-lookup: 600 files match (4 keywords in 3 sets)" && has "sets=3" "$OUT"'
