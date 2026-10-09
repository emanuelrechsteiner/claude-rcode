#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: eval bodies expand at run time
# klint-cases.sh — cases for knowledge-lint-regression.sh. Sourced, never run; shares its helpers
# (check lint line noline has hasnt), variables (T H OUT ERR RC LINT) and the fixtures.

P=memory/projA
# ---- per-note codes (R1) -------------------------------------------------------------------
lint "$R1"
check "default report exits 0 although it holds FAILs" "rc=$RC" 'test "$RC" -eq 0 && has "$OUT" "^FAIL "'
check "desc: note without description FAILs" "$(cat "$OUT")" 'line FAIL desc $P/nodesc.md'
check "desc: note with description passes" "" 'noline desc $P/good.md'
check "good note has no finding at all" "$(grep "good.md" "$OUT")" 'hasnt "$OUT" "^(FAIL|WARN) [a-z]+ $P/good.md( |\$)"'
for n in claim-date claim-status claim-stand claim-state claim-on claim-am claim-during claim-today claim-yesterday claim-insession claim-session; do
  check "claim: $n WARNs" "" 'line WARN claim $P/$n.md'
done
check "claim: a claim-first note does not WARN" "" 'noline claim $P/claim-ok.md'
check "claim: 'Online' / 'Statement' are not markers (whole-word)" "" 'noline claim $P/claim-online.md && noline claim $P/claim-statement.md'
check "claim is a WARN, never a FAIL" "" 'hasnt "$OUT" "^FAIL claim "'
check "why: feedback without Why FAILs, its How passes" "" 'line FAIL why $P/nowhy.md && noline how $P/nowhy.md'
check "how: project without How FAILs, its Why passes" "" 'line FAIL how $P/nohow.md && noline why $P/nohow.md'
check "exemption: reference note needs neither Why nor How" "" 'noline why $P/refexempt.md && noline how $P/refexempt.md'
check "exemption: user note needs neither Why nor How" "" 'noline why $P/userexempt.md && noline how $P/userexempt.md'
check "type: untyped note WARNs and is treated as project" "" 'line WARN type $P/untyped.md && line FAIL why $P/untyped.md && line FAIL how $P/untyped.md'
check "type: unknown value WARNs" "" 'line WARN type $P/badtype.md'
check "date: note without any date FAILs (generated modified: does not count)" "" 'line FAIL date $P/nodate.md'
check "date: a date only in the description counts" "" 'noline date $P/descdate.md'
check "date: a dated: key counts" "" 'noline date $P/datedkey.md'
check "date: dated_from: mtime does not count as a real date" "" 'line FAIL date $P/datedmtime.md'
check "size: over 8192 bytes FAILs" "" 'line FAIL size $P/big.md && noline size $P/small.md'
check "dangling: unresolved basename and unresolved path FAIL" "" 'has "$OUT" "^FAIL dangling $P/dang.md \[\[nonexistent-xyz\]\]" && has "$OUT" "^FAIL dangling $P/dang.md \[\[memory/projA/nope\]\]"'
check "dangling: exact path and unique basename resolve" "" 'noline dangling $P/good.md'
check "dangling: links in inline code and fenced code are ignored" "" 'hasnt "$OUT" "in-code|in-fence"'
check "dangling: two basename matches are WARN ambiguous, not FAIL" "" 'has "$OUT" "^WARN ambiguous $P/dang.md \[\[dupname\]\]"'
check "dangling: MEMORY.md index is checked for links" "" 'has "$OUT" "^FAIL dangling $P/MEMORY.md "'
check "per-note codes skip MEMORY.md" "" 'hasnt "$OUT" "^(FAIL|WARN) (desc|why|how|date|claim|type) $P/MEMORY.md"'
check "dangling is scoped to memory (a rules note is not scanned)" "" 'hasnt "$OUT" "never-scanned"'
check "status: unknown value FAILs" "" 'has "$OUT" "^FAIL status $P/stbad.md value=bogus"'
check "status: superseded + existing superseded_by passes" "" 'noline status $P/stok.md && noline status $P/stactive.md'
check "status: superseded_by naming a missing file FAILs" "" 'has "$OUT" "^FAIL status $P/stgone.md superseded_by=memory/projA/gone.md"'
check "frontmatter: missing and unclosed frontmatter are reported" "" 'line FAIL frontmatter $P/nofm.md && line FAIL frontmatter $P/unclosed.md'
if [ "$UNREADABLE_OK" -eq 1 ]; then
  check "unreadable file is reported, not skipped" "" 'line FAIL unreadable $P/locked.md && test "$RC" -eq 0'
else ok "unreadable file case skipped (running with privileges that ignore chmod 000)"; fi
check "findings are sorted by path" "" 'grep -E "^(FAIL|WARN) " "$OUT" | awk "{print \$3}" | LC_ALL=C sort -c'
check "summary: LINT line carries every code" "$(grep '^LINT n=' "$OUT")" 'has "$OUT" "^LINT n=[0-9]+ desc=[0-9]+ claim=[0-9]+ why=[0-9]+ how=[0-9]+ date=[0-9]+ size=[0-9]+ dangling=[0-9]+ status=[0-9]+ type=[0-9]+\$"'
check "summary: MEMORY.md is not a memory note (n excludes it)" "" 'test "$(( $(find "$R1/mirror/memory" -name "*.md" ! -name MEMORY.md | wc -l) - UNREADABLE_OK ))" = "$(sed -n "s/^LINT n=\([0-9]*\) .*/\1/p" "$OUT")"'
lint "$R1" --summary
check "--summary prints only LINT lines" "$(cat "$OUT")" 'test -s "$OUT" && hasnt "$OUT" "^(FAIL|WARN) " && hasnt "$OUT" "^[^L]"'
before=$(cd "$R1" && find . -type f | LC_ALL=C sort | xargs -I{} cksum "{}" 2>/dev/null | cksum)
lint "$R1"; after=$(cd "$R1" && find . -type f | LC_ALL=C sort | xargs -I{} cksum "{}" 2>/dev/null | cksum)
check "the report never edits the mirror" "$before vs $after" 'test "$before" = "$after"'

# ---- pinned summary (R4) ---------------------------------------------------------------------
lint "$R4" --summary
check "summary lines match the hand-computed values" "$(cat "$OUT")" 'test "$(cat "$OUT")" = "LINT n=3 desc=1 claim=1 why=1 how=1 date=1 size=0 dangling=1 status=0 type=0
LINT why_present=1 how_present=1 both=1
LINT type=feedback n=1 why=1 how=1
LINT type=project n=1 why=0 how=0
LINT type=reference n=1 why=0 how=0
LINT type=user n=0 why=0 how=0
LINT ambiguous=0 frontmatter=0 unreadable=0"'

# ---- usage and IO errors -------------------------------------------------------------------
lint "$R4" --help
check "--help documents every flag and code in <= 40 lines" "$(wc -l < "$OUT") lines" 'test "$RC" -eq 0 && test "$(wc -l < "$OUT")" -le 40 && for w in --summary --contradictions --refs --orphans --superseded --rules-without-evidence desc claim why how date size dangling status; do has "$OUT" "$w" || exit 1; done'
lint "$R4" --bogus
check "unknown flag: exit 1 with usage hint" "rc=$RC" 'test "$RC" -eq 1 && has "$ERR" "unknown argument"'
CLAUDE_KNOWLEDGE_DIR="" HOME="$H" /bin/bash "$LINT" > "$OUT" 2> "$ERR"; RC=$?
check "CLAUDE_KNOWLEDGE_DIR unset: exit 1, loud" "rc=$RC" 'test "$RC" -eq 1 && has "$ERR" "CLAUDE_KNOWLEDGE_DIR is not set"'
lint "$T/nowhere"
check "missing mirror: exit 1, loud" "rc=$RC" 'test "$RC" -eq 1 && has "$ERR" "no mirror at"'
mkdir -p "$T/emptyk/mirror/rules"; lint "$T/emptyk"
check "mirror without memory notes: exit 1, loud" "rc=$RC" 'test "$RC" -eq 1 && has "$ERR" "no memory notes"'

# ---- contradictions (R2) -----------------------------------------------------------------------
lint "$R2" --contradictions
cx() { has "$OUT" "^CONTRADICTION $1 memory/$2 memory/$3 "; }
check "rule status: same stem, pending vs done" "$(cat "$OUT")" 'test "$RC" -eq 0 && cx status p1/launch_pending.md p1/launch_done.md'
check "rule status: same subject by >= 3 shared title tokens" "" 'cx status p1/tok-a.md p1/tok-b.md'
check "rule status: unrelated subject is not paired" "" 'hasnt "$OUT" "neg-subject"'
check "rule status: word boundary (abandoned/deliver are neither done nor live)" "" 'hasnt "$OUT" "boundary"'
check "rule status: different projects are not paired" "" 'hasnt "$OUT" "solo_"'
check "rule dup-basename: same file name in two projects" "" 'has "$OUT" "^CONTRADICTION dup-basename memory/p1/dup.md memory/p2/dup.md basename=dup\$"'
check "rule abandoned: absolute path declared abandoned" "" 'has "$OUT" "^CONTRADICTION abandoned memory/$(enc "$H/old-proj")/stale.md memory/p3/decl.md "'
check "rule abandoned: ~/ path declared retired" "" 'has "$OUT" "^CONTRADICTION abandoned memory/$(enc "$H/old2")/stale2.md memory/p3/decl2.md "'
check "rule overtaken: a linked note called outdated" "" 'cx overtaken p4/old-claim.md p4/new.md'
check "evidence snippet is at most 80 characters" "" 'awk "{ s=\$0; sub(/^CONTRADICTION [^ ]+ [^ ]+ [^ ]+ /, \"\", s); if (length(s) > 80) bad = 1 } END { exit bad }" "$OUT"'
check "summary: CONTRADICTIONS n counts the lines" "$(tail -1 "$OUT")" 'test "$(tail -1 "$OUT")" = "CONTRADICTIONS n=6" && test "$(grep -c "^CONTRADICTION " "$OUT")" -eq 6'

# ---- refs (R6) ------------------------------------------------------------------------------------
lint "$R6" --refs
check "refs: existing paths are external, missing are dead (per kind, distinct)" "$(cat "$OUT")" 'test "$RC" -eq 0 && has "$OUT" "^REFS kind=memory external=2 dead=1\$" && has "$OUT" "^REFS kind=rule external=0 dead=1\$" && hasnt "$OUT" "kind=(rules|ledger|plans|docs)"'
check "refs: dead paths are named with their note" "" 'has "$OUT" "^REFS dead hooks/missing.sh in memory/pj/r1.md\$" && has "$OUT" "^REFS dead docs/gone.md in rules/q.md\$"'
check "refs: fenced code and non-repo paths are ignored" "" 'hasnt "$OUT" "fenced-missing|foo.ts"'
check "refs: session transcript present/missing by existence (unreadable file still counts)" "$(grep session "$OUT")" 'has "$OUT" "^REFS session present=1 missing=1\$" && has "$OUT" "^REFS session noid=1 of=3\$"'
check "refs: transcript contents are never printed" "" 'hasnt "$OUT" "never read" && hasnt "$ERR" "never read"'

check "refs: folder names map to graph kinds (ledger->imp, plans->plan)" "$(grep 'REFS kind' "$OUT")" 'has "$OUT" "^REFS kind=imp external=0 dead=1\$" && has "$OUT" "^REFS kind=plan external=1 dead=0\$"'

# ---- graph queries (R3, R3B, R3C, R5) -------------------------------------------------------
lint "$R3" --orphans
check "--orphans: nodes without inbound edge, grouped by kind (imp, not ledger)" "$(cat "$OUT")" 'test "$RC" -eq 0 && has "$OUT" "^ORPHAN kind=rule rules/b.md\$" && has "$OUT" "^ORPHAN kind=memory memory/p/m.md\$" && has "$OUT" "^ORPHAN kind=imp ledger/IMP-001.md\$" && has "$OUT" "^ORPHANS kind=rule n=1 of=2 mentions_only=0\$" && has "$OUT" "^ORPHANS kind=evidence n=0 of=1 mentions_only=0\$" && has "$OUT" "^ORPHANS total n=5 of=8\$"'
check "--orphans: header rows are skipped (no kind=kind phantom, totals not off by one)" "$(cat "$OUT")" 'hasnt "$OUT" "kind=kind" && hasnt "$OUT" "^ORPHAN kind=[a-z]+ path\$" && has "$OUT" "^ORPHANS total n=5 of=8\$"'
check "--orphans: a mentions-only node is an orphan and counted in mentions_only" "$(cat "$OUT")" 'has "$OUT" "^ORPHAN kind=memory memory/p/o.md\$" && has "$OUT" "^ORPHANS kind=memory n=2 of=3 mentions_only=1\$"'
check "--orphans: a same-day-only node is an orphan and counted in mentions_only" "$(cat "$OUT")" 'has "$OUT" "^ORPHAN kind=imp ledger/IMP-001.md\$" && has "$OUT" "^ORPHANS kind=imp n=2 of=2 mentions_only=1\$"'
lint "$R3" --superseded
check "--superseded: status superseded with superseded_by from the note" "$(cat "$OUT")" 'has "$OUT" "^SUPERSEDED memory/p/m.md -> memory/p/n.md\$" && has "$OUT" "^SUPERSEDED n=1\$"'
lint "$R3" --rules-without-evidence
check "--rules-without-evidence: rules without outbound evidence edge" "$(cat "$OUT")" 'has "$OUT" "^RULE_NO_EVIDENCE rules/b.md\$" && hasnt "$OUT" "rules/a.md" && has "$OUT" "^RULES_WITHOUT_EVIDENCE n=1 of=2\$"'
lint "$R3B" --orphans
check "malformed graph row is reported with file:line" "$(cat "$ERR")" 'has "$ERR" "malformed row .*edges.tsv:8"'
for q in --orphans --superseded --rules-without-evidence; do
  lint "$R4" "$q"
  check "graph export missing ($q): message + exit 1, nothing on stdout" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 1 && has "$ERR" "^LINT graph export missing at .*/mirror/graph/nodes.tsv — run knowledge-mirror.sh v3 first\$" && test ! -s "$OUT"'
done
lint "$R3C" --orphans
check "graph export missing: edges.tsv alone missing is also exit 1" "rc=$RC" 'test "$RC" -eq 1 && has "$ERR" "graph/edges.tsv — run knowledge-mirror.sh v3 first"'

# ---- header rows in the rules query, status-form, backfilled, imp status, pipeline failures ------
lint "$R3" --superseded
check "--superseded: an imp node with status superseded is not listed" "$(cat "$OUT")" 'hasnt "$OUT" "IMP-002"'
lint "$R3" --rules-without-evidence
check "--rules-without-evidence: header rows are not counted as nodes or edges" "$(cat "$OUT")" 'has "$OUT" "^RULES_WITHOUT_EVIDENCE n=1 of=2\$" && hasnt "$OUT" "path"'
lint "$R1"
check "status-form: [[wrapped|alias]] value WARNs but still resolves" "$(grep stwrap "$OUT")" 'has "$OUT" "^WARN status-form $P/stwrap.md " && noline status $P/stwrap.md'
check "status-form: ./ prefix and missing .md WARN but resolve" "$(grep stnoext "$OUT")" 'has "$OUT" "^WARN status-form $P/stnoext.md " && noline status $P/stnoext.md'
check "status-form: canonical superseded_by gets no WARN" "" 'noline status-form $P/stok.md'
check "date: backfilled: stamp is not a date (FAIL date stays)" "" 'line FAIL date $P/backfilled.md'
check "date: valid_from counts as a date" "" 'noline date $P/validfrom.md'
check "imp kind: generated status/superseded_by is ignored" "$(grep impstatus "$OUT")" 'hasnt "$OUT" "impstatus"'
FAILAWK() { KL_TEST_AWK_FAIL=$1 PATH="$T/shim:$PATH" lint "${@:2}"; }
FAILAWK ORPHANS "$R3" --orphans
check "pipeline failure: --orphans awk crash is exit 1 with LINT error" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 1 && has "$ERR" "^LINT error --orphans"'
FAILAWK superseded "$R3" --superseded
check "pipeline failure: --superseded awk crash is exit 1 with LINT error" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 1 && has "$ERR" "^LINT error --superseded"'
FAILAWK CONTRADICTION "$R2" --contradictions
check "pipeline failure: --contradictions awk crash is exit 1 with LINT error" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 1 && has "$ERR" "^LINT error --contradictions"'
FAILAWK "tok ~" "$R6" --refs
check "pipeline failure: --refs token awk crash is exit 1 with LINT error" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 1 && has "$ERR" "^LINT error --refs"'
FAILAWK originSessionId "$R6" --refs
check "pipeline failure: --refs session-id pipe crash is exit 1 with LINT error" "rc=$RC $(cat "$ERR")" 'test "$RC" -eq 1 && has "$ERR" "^LINT error --refs"'
