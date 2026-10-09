#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
# shellcheck disable=SC2034,SC2153 # RUN_FLAGS is read by run(); ERR comes from the last run()
# knowledge-mirror-regression v3 cases: graph/*.tsv export, ## Mentions, same-day, IMP trim, and the
# guarantee that graph/ stays outside the hash / stale / CHANGED logic. Sourced by
# knowledge-mirror-regression.sh after km-cases-v3-links.sh; shares its helpers and variables.

echo "== v3 graph: nodes.tsv / edges.tsv =="
TAB3=$(printf '\t')
v3_run
check "nodes.tsv header is exactly: path kind status dated description" "$(head -1 "$G3/nodes.tsv" | od -c | head -3)" \
  /bin/bash -c '[ "$(head -n 1 "$1")" = "$(printf "path\tkind\tstatus\tdated\tdescription")" ]' _ "$G3/nodes.tsv"
check "edges.tsv header is exactly: src dst via" "$(head -1 "$G3/edges.tsv")" \
  /bin/bash -c '[ "$(head -n 1 "$1")" = "$(printf "src\tdst\tvia")" ]' _ "$G3/edges.tsv"
check "nodes.tsv: one row per copy (TOTAL $EXPECT_V3_TOTAL), five columns, README.md and graph/ not nodes" "$(wc -l < "$G3/nodes.tsv")" \
  /bin/bash -c '[ "$(tail -n +2 "$1" | wc -l | tr -d " ")" = "$2" ] && ! tail -n +2 "$1" | awk -F "\t" "NF != 5 || \$1 == \"README.md\" { bad = 1 } END { exit bad }" | grep -q . && ! grep -q "^graph/" "$1"' _ "$G3/nodes.tsv" "$EXPECT_V3_TOTAL"
check "every node path is a copy in the mirror" "$(cut -f1 "$G3/nodes.tsv" | tail -n +2 | while IFS= read -r p; do [ -f "$K3/mirror/$p" ] || echo "no $p"; done)" \
  /bin/bash -c 'cut -f1 "$1/graph/nodes.tsv" | tail -n +2 | while IFS= read -r p; do [ -f "$1/$p" ] || exit 1; done' _ "$K3/mirror"
check "edges.tsv: three columns, via in {wikilink, mdlink, evidence, mentions, same-day}, both ends are nodes" "$(tail -n +2 "$G3/edges.tsv" | cut -f3 | sort | uniq -c)" \
  /bin/bash -c 'awk -F "\t" "NR == FNR { n[\$1] = 1; next } FNR > 1 && (NF != 3 || !(\$3 ~ /^(wikilink|mdlink|evidence|mentions|same-day)\$/) || !(\$1 in n) || !(\$2 in n)) { bad = 1; print } END { exit bad }" "$1/nodes.tsv" "$1/edges.tsv"' _ "$G3"
for v in "memory/-pa/alpha_note.md|memory/-pa/beta.md|wikilink" "docs/d.md|docs/sibling.md|mdlink" "rules/r1.md|evidence/r1.md|evidence" \
         "rules/ord.md|memory/-pa/ordm2.md|mentions" "ledger/IMP-1.md|logbook/2026-03-03.md|same-day"; do
  IFS='|' read -r s d via <<<"$v"
  check "edge $s -> $d via $via" "$(grep -F "$s" "$G3/edges.tsv" | head -3)" edge "$s" "$d" "$via"
done
check "an unresolved target is not an edge row (ghost-pa, ghost-rule, gone.md, nowhere.md)" "$(grep -E 'ghost|gone|nowhere' "$G3/edges.tsv")" \
  /bin/bash -c '! grep -qE "ghost|gone\.md|nowhere" "$1"' _ "$G3/edges.tsv"
check "a link counted twice in one note is two rows (one row per resolved occurrence)" "$(grep -c "^memory/-pa/alpha_note.md${TAB3}memory/-pa/beta.md${TAB3}wikilink" "$G3/edges.tsv")" \
  /bin/bash -c '[ "$(grep -c "^memory/-pa/alpha_note.md	memory/-pa/beta.md	wikilink" "$1")" = 2 ]' _ "$G3/edges.tsv"
ZN=$(grep "^memory/-pa/zeta.md${TAB3}" "$G3/nodes.tsv"); BN=$(grep "^memory/-pa/beta.md${TAB3}" "$G3/nodes.tsv")
check "node zeta: authored status superseded, dated 2026-01-01, tab in the description replaced by a space" "$ZN" \
  /bin/bash -c '[ "$1" = "$(printf "memory/-pa/zeta.md\tmemory\tsuperseded\t2026-01-01\ttab here")" ]' _ "$ZN"
check "node beta: status defaults to active, description unquoted" "$BN" \
  /bin/bash -c '[ "$1" = "$(printf "memory/-pa/beta.md\tmemory\tactive\t2026-03-05\tBeta")" ]' _ "$BN"
check "V-05 node IMP-1: kind imp, status column active (the ledger vocabulary is not a lifecycle status), dated from implementedAt" "$(grep '^ledger/IMP-1.md' "$G3/nodes.tsv")" \
  /bin/bash -c '[ "$1" = "$(printf "ledger/IMP-1.md\timp\tactive\t2026-03-03\t")" ]' _ "$(grep '^ledger/IMP-1.md' "$G3/nodes.tsv")"
check "V-05 no IMP node carries a ledger-vocabulary status (implemented, proposed, unknown) in nodes.tsv" "$(grep '^ledger/' "$G3/nodes.tsv" | cut -f1-3)" \
  /bin/bash -c '[ "$(grep "^ledger/" "$1" | cut -f3 | sort -u)" = active ]' _ "$G3/nodes.tsv"
check "V-05 the IMP copies keep the ledger value under ledger_status: and have no status: line" "$(grep -c '^status:' "$K3"/mirror/ledger/IMP-*.md | head -2)" \
  /bin/bash -c 'grep -qx "ledger_status: implemented" "$1/IMP-1.md" && grep -qx "ledger_status: proposed" "$1/IMP-2.md" && ! grep -q "^status:" "$1"/IMP-*.md' _ "$K3/mirror/ledger"

echo "== v3 graph: ## Mentions =="
OR="$K3/mirror/rules/ord.md"
EXP_ORD='- [[memory/-pa/ordm2]]
- [[memory/-pa/ordm1]]
- [[rules/ordr]]
- [[adr/0001-x]]
- [[logbook/2026-03-01]]
- [[plans/meta-proposal-2026-03-10]]
- [[docs/d]]
- [[ledger/IMP-1]]'
check "mention order memory > rule > adr > logbook > plan > doc > imp, newest dated first inside a kind" "$(sed -n '/^## Mentions/,$p' "$OR")" \
  /bin/bash -c '[ "$(sed -n "/^## Mentions/,\$p" "$1" | grep "^- ")" = "$2" ]' _ "$OR" "$EXP_ORD"
CP="$K3/mirror/rules/cap.md"
check "cap: 10 bullets, newest logbook days first, then 'and 2 more' as the last line" "$(sed -n '/^## Mentions/,$p' "$CP")" \
  /bin/bash -c 'b=$(sed -n "/^## Mentions/,\$p" "$1" | grep -c "^- "); [ "$b" = 10 ] && [ "$(sed -n "/^## Mentions/,\$p" "$1" | sed -n 3p)" = "- [[logbook/2026-04-12]]" ] && [ "$(sed -n "/^## Mentions/,\$p" "$1" | sed -n 12p)" = "- [[logbook/2026-04-03]]" ] && [ "$(tail -n 1 "$1")" = "and 2 more" ]' _ "$CP"
check "a copy without mentioners gets no section (rules/plain.md, rules/b-like, logbook and plan copies)" "$(grep -l '^## Mentions' "$K3/mirror/rules/plain.md" "$K3"/mirror/logbook/*.md "$K3"/mirror/plans/*.md 2>&1 | head -2)" \
  /bin/bash -c '! grep -q "^## Mentions" "$1/rules/plain.md" && ! grep -lq "^## Mentions" "$1"/logbook/*.md "$1"/plans/*.md' _ "$K3/mirror"
R1="$K3/mirror/rules/r1.md"
check "a rule with an evidence twin ends: ## Evidence, its link, then ## Mentions (after Evidence, at the very end)" "$(tail -n 7 "$R1")" \
  /bin/bash -c '[ "$(tail -n 7 "$1")" = "$(printf "## Evidence\n\n[[evidence/r1]]\n\n## Mentions\n\n- [[evidence/r1]]")" ]' _ "$R1"
I1="$K3/mirror/ledger/IMP-1.md"
check "IMP copy: same-day lines for implementedAt then proposedAt first, the logbook day is not repeated as a mentioner" "$(sed -n '/^## Mentions/,$p' "$I1")" \
  /bin/bash -c '[ "$(sed -n "/^## Mentions/,\$p" "$1" | grep "^- ")" = "$(printf "%s\n" "- [[logbook/2026-03-03]] (same-day)" "- [[logbook/2026-03-01]] (same-day)" "- [[plans/meta-proposal-2026-03-10]]")" ]' _ "$I1"
check "same-day is skipped when the logbook day does not exist (IMP-5 has no days; IMP-2 none): no Mentions at all" "$(tail -n 3 "$K3/mirror/ledger/IMP-5.md")" \
  /bin/bash -c '! grep -q "^## Mentions" "$1/ledger/IMP-5.md" && ! grep -q "^## Mentions" "$1/ledger.md"' _ "$K3/mirror"
check "mention order is a deterministic function of the corpus: the rerun is byte-identical (CHANGED 0)" "$OUT" grep -qx 'CHANGED 0' <<<"$OUT"

echo "== v3 graph: a copy that ends inside a fence gets a closing fence before Evidence / Mentions =="
FE3="$K3/mirror/rules/fenceend.md"; EV3="$K3/mirror/evidence/fenceend.md"
F4='````'; F3='```'; export F4 F3
check "V-13 rule: its 4-backtick fence is closed by a 4-backtick line, then blank, ## Evidence, link, ## Mentions" "$(tail -n 11 "$FE3")" \
  /bin/bash -c '[ "$(tail -n 9 "$1")" = "$(printf "%s\n" "$F4" "" "## Evidence" "" "[[evidence/fenceend]]" "" "## Mentions" "" "- [[docs/fence]]")" ]' _ "$FE3"
check "V-13 evidence: its 3-backtick fence is closed before ## Mentions" "$(tail -n 7 "$EV3")" \
  /bin/bash -c '[ "$(tail -n 5 "$1")" = "$(printf "%s\n" "$F3" "" "## Mentions" "" "- [[rules/fenceend]]")" ]' _ "$EV3"
check "V-13 the appended links are real links: rule -> evidence (evidence), evidence -> rule (mentions), doc -> rule" "x" \
  /bin/bash -c 'edge rules/fenceend.md evidence/fenceend.md evidence && edge evidence/fenceend.md rules/fenceend.md mentions && edge docs/fence.md rules/fenceend.md wikilink'
check "V-13 the source text before the closing fence is byte-identical (open code line kept)" "$(sed -n 1,12p "$FE3")" grep -qxF 'open code' "$FE3"

echo "== v3 graph: IMP trim =="
I2="$K3/mirror/ledger/IMP-2.md"; I3="$K3/mirror/ledger/IMP-3.md"; I4="$K3/mirror/ledger/IMP-4.md"
check "IMP-2 (no notes/evidence/files): no ## Notes / ## Evidence / ## Files; verification keeps kpi, drops the boilerplate" "$(cat "$I2")" \
  /bin/bash -c '! grep -qE "^## (Notes|Evidence|Files)" "$1" && grep -qx -- "- kpi: k2" "$1" && ! grep -q "proposed entries carry no measurement" "$1"' _ "$I2"
check "IMP-3 (boilerplate only): no ## Verification section" "$(cat "$I3")" /bin/bash -c '! grep -q "^## Verification" "$1"' _ "$I3"
check "IMP-4: a custom verification note is kept; the measured: key stays in every IMP copy" "$(cat "$I4")" \
  /bin/bash -c 'grep -qx -- "- note: custom note kept" "$1" && for n in 1 2 3 4 5; do grep -qx "measured: false" "$2/ledger/IMP-$n.md" || exit 1; done' _ "$I4" "$K3/mirror"
check "IMP-1: non-empty Notes and Files stay, Evidence (empty) is dropped" "$(cat "$I1")" \
  /bin/bash -c 'grep -q "^## Notes" "$1" && grep -q "^## Files" "$1" && ! grep -q "^## Evidence" "$1"' _ "$I1"
check "--no-v3-links keeps the verification boilerplate (it carries the IMP-075 link of the v2 edge set)" "$(grep -c 'proposed entries carry no measurement' "$KNL/mirror/ledger/IMP-3.md")" \
  grep -q 'proposed entries carry no measurement' "$KNL/mirror/ledger/IMP-3.md"

echo "== v3 graph: graph/ stays outside hash / stale / CHANGED =="
HT3="$K3/mirror/.state/hashes.tsv"
check "hashes.tsv has no graph/ row and covers exactly the $EXPECT_V3_TOTAL copies" "$(grep -c graph "$HT3")" \
  /bin/bash -c '! grep -q "graph/" "$1" && [ "$(wc -l < "$1" | tr -d " ")" = "$2" ]' _ "$HT3" "$EXPECT_V3_TOTAL"
check "no stale: line mentions graph, README.md or any tsv" "$ERR" /bin/bash -c '! grep -q "^stale:" <<<"$1"' _ "$ERR"
printf 'HAND-EDIT\n' >> "$G3/edges.tsv"; rm -f "$G3/nodes.tsv"
v3_run
check "a hand-edited / deleted graph file is not drift: exit 0, CHANGED 0, both files regenerated" "rc=$RC out=$OUT err=$ERR" \
  /bin/bash -c '[ "$1" = 0 ] && grep -qx "CHANGED 0" <<<"$2" && ! grep -q HAND-EDIT "$3/edges.tsv" && [ -s "$3/nodes.tsv" ]' _ "$RC" "$OUT" "$G3"
SHA3=$(shasum "$G3/edges.tsv" "$G3/nodes.tsv" | cut -d ' ' -f 1 | tr '\n' ' ')
v3_run
check "the graph export is byte-identical on a rerun" "$SHA3" \
  /bin/bash -c '[ "$(shasum "$1/edges.tsv" "$1/nodes.tsv" | cut -d " " -f 1 | tr "\n" " ")" = "$2" ]' _ "$G3" "$SHA3"
printf 'HAND-EDIT\n' >> "$G3/edges.tsv"
v3_run --check-links
check "--check-links does not write or rewrite graph/ (the hand edit is still there)" "rc=$RC" grep -q HAND-EDIT "$G3/edges.tsv"
v3_run --dry-run
check "--dry-run does not write or rewrite graph/ either" "rc=$RC" grep -q HAND-EDIT "$G3/edges.tsv"
v3_run
KD3="$T/know-v3-dry"
( cd "$T" && env -u CLAUDE_BAUHOF_ROOT HOME="$H3" CLAUDE_KNOWLEDGE_DIR="$KD3" /bin/bash "$KM" --dry-run >"$T/out" 2>"$T/err" ); RC=$?
check "--dry-run on a fresh target creates nothing (no mirror/, no graph/)" "rc=$RC $(ls -A "$KD3" 2>&1)" /bin/bash -c '[ "$1" = 0 ] && [ ! -e "$2" ]' _ "$RC" "$KD3"
mv "$G3" "$T/graph-away"; ln -s "$T/graph-away" "$G3"
v3_run
check "a symlinked graph/ is refused like any symlink under mirror/ (exit 1, refuse prefix)" "rc=$RC err=$ERR" \
  /bin/bash -c '[ "$1" = 1 ] && head -n 1 <<<"$2" | grep -q "^knowledge-mirror: refuse: symlink inside mirror/"' _ "$RC" "$ERR"
rm -f "$G3"; mv "$T/graph-away" "$G3"
v3_run
check "after removing the link the run succeeds again (exit 0, CHANGED 0)" "rc=$RC out=$OUT" /bin/bash -c '[ "$1" = 0 ] && grep -qx "CHANGED 0" <<<"$2"' _ "$RC" "$OUT"

echo "== v3 graph: a failed write is an error, never a silent exit 0 (V-06) =="
HK="$H"; KK="$K"; H="$T/home-wf"; K="$T/know-wf"; mkdir -p "$H/.claude/rules"; RUN_FLAGS=""
printf '# W\n' > "$H/.claude/rules/w.md"
run
WF="$K/mirror"
check "precondition: the first run succeeds and a mode-555 directory refuses writes (not running as root)" "rc=$RC err=$ERR" \
  /bin/bash -c '[ "$1" = 0 ] && [ "$(id -u)" != 0 ] && chmod 555 "$2" && ! touch "$2/probe" 2>/dev/null; r=$?; chmod 755 "$2"; exit $r' _ "$RC" "$WF/rules"
printf '# W changed\n' > "$H/.claude/rules/w.md"
chmod 555 "$WF/rules"; run; WRC=$RC; WERR=$ERR; chmod 755 "$WF/rules"
check "V-06 a copy that cannot be written: exit 1, error line naming the copy, the old copy kept" "rc=$WRC err=$WERR" \
  /bin/bash -c '[ "$1" = 1 ] && grep -q "^knowledge-mirror: could not write the mirror copy: rules/w.md" <<<"$2" && ! grep -q changed "$3" && [ ! -e "$3.tmp" ]' _ "$WRC" "$WERR" "$WF/rules/w.md"
run
check "after the permission is back the same run succeeds and writes the copy (CHANGED 1)" "rc=$RC out=$OUT err=$ERR" \
  /bin/bash -c '[ "$1" = 0 ] && grep -qx "CHANGED 1" <<<"$2" && grep -q changed "$3"' _ "$RC" "$OUT" "$WF/rules/w.md"
chmod 555 "$WF/.state"; run; WRC=$RC; WERR=$ERR; chmod 755 "$WF/.state"
check "V-06 a state file that cannot be written: exit 1 and an error line (the stale hashes.tsv is not a success)" "rc=$WRC err=$WERR" \
  /bin/bash -c '[ "$1" = 1 ] && grep -q "^knowledge-mirror: could not write the state file" <<<"$2"' _ "$WRC" "$WERR"
chmod 555 "$WF/graph"; run; WRC=$RC; WERR=$ERR; chmod 755 "$WF/graph"
check "V-06 a graph export that cannot be written: exit 1 and an error line" "rc=$WRC err=$WERR" \
  /bin/bash -c '[ "$1" = 1 ] && grep -q "^knowledge-mirror: could not write the graph export" <<<"$2"' _ "$WRC" "$WERR"
run
check "after the permissions are back the run is clean again (exit 0, CHANGED 0)" "rc=$RC out=$OUT err=$ERR" /bin/bash -c '[ "$1" = 0 ] && grep -qx "CHANGED 0" <<<"$2"' _ "$RC" "$OUT"
H="$HK"; K="$KK"; RUN_FLAGS=--no-v3-links
