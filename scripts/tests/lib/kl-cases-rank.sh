#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the check bodies expand at run time, not here
# knowledge-lookup-regression cases: v3 matching, fields, ranking, collision list, filters, superseded,
# ## Mentions, runtime. Sourced by scripts/tests/knowledge-lookup-regression.sh (never run on its own);
# shares its helpers and fixtures (lk check has hasx hdr hdrs blocks first excluded ... M K T).
# order() prints the file paths of the last result, in order, space-separated.

order() { hdrs | sed 's/^== \([^ ]*\) .*$/\1/' | tr '\n' ' '; }

echo "-- lookup v3: matching, fields, ranking --"

# ---- frontmatter fields ------------------------------------------------------
lk walkthroughs
check "description-only token: found (>= 1 file), shown with its description, no hit line" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && hdr "== memory/proj/desc-only.md  [1/1]  (memory)" && has "   » Walkthroughs of the descriptiontok flow, quoted \"as is\"" "$OUT" && ! has "   L" "$OUT"'
lk descnote
check "frontmatter name: is searched" "$(cat "$OUT")" 'hdr "== memory/proj/desc-only.md  [1/1]  (memory)"'
excluded node_type "nested frontmatter keys (metadata:) never match"

# ---- word boundary, --prefix, umlauts, phrase -------------------------------------
lk zshtok
check "word boundary: zshtok does not match ~/.zshtokrc, matches the standalone word" "$(order)" 'test "$(order)" = "rules/prefix-b.md "'
lk --prefix zshtok
check "--prefix: keyword also matches as a word prefix (.zshtokrc), 2 files" "$(order)" 'test "$(blocks)" -eq 2 && has "== rules/prefix-a.md" "$OUT"'
lk bertok
check "umlaut bytes count as word characters: x<ue>bertok is not a hit for bertok" "$(order)" 'test "$(order)" = "memory/proj/uml-b.md "'
lk --prefix bertok
check "--prefix does not relax the LEFT boundary (umlaut word still no hit)" "$(order)" 'test "$(order)" = "memory/proj/uml-b.md "'
lk boundtok
check "D-05: curly quotes, arrow, em dash, NBSP, multiplication sign and space are word boundaries; an umlaut is not" "$(order)" 'test "$(blocks)" -eq 6 && has "memory/proj/bd-curly.md" "$OUT" && has "memory/proj/bd-arrow.md" "$OUT" && has "memory/proj/bd-dash.md" "$OUT" && has "memory/proj/bd-nbsp.md" "$OUT" && has "memory/proj/bd-times.md" "$OUT" && has "memory/proj/bd-space.md" "$OUT" && ! has "bd-uml" "$OUT"'
lk --prefix boundtok
check "D-05: --prefix keeps the umlaut-left no-hit" "$(order)" '! has "bd-uml" "$OUT" && test "$(blocks)" -eq 6'
lk Hooktok
check "D-01: an explicit keyword with capitals finds the lowercase text" "$(order)" 'test "$(order)" = "memory/proj/cap-kw.md "'
lk HOOKTOK
check "D-01: ALL CAPS keyword finds the same file as the lowercase one" "$(order)" 'test "$(order)" = "memory/proj/cap-kw.md "'
lk Zustand
check "D-01: collision keyword in capitals still keeps the German-noun rule" "$(order)" '! has "de-noun" "$OUT" && hdr "== memory/proj/zs.md  [1/1]  (memory)"'
lk "phrasea phraseb"
check "quoted argument is ONE literal phrase: only the adjacent file, K = 1" "$(cat "$OUT")" 'has "(1 keywords)" "$OUT" && test "$(order)" = "memory/proj/phrase-adj.md "'
lk phrasea phraseb
check "two arguments are two keywords: both files, adjacent one has [2/2]" "$(cat "$OUT")" 'has "(2 keywords)" "$OUT" && test "$(blocks)" -eq 2 && hdr "== memory/proj/phrase-adj.md  [2/2]  (memory)"'

# ---- collision list ------------------------------------------------------------
lk zustand
check "zustand: German noun lines (capitalised, German function word) are NOT matched" "$(order)" '! has "de-noun" "$OUT"'
check "zustand: lowercase npm mention matches (zs.md)" "$(order)" 'hdr "== memory/proj/zs.md  [1/1]  (memory)"'
# DEVIATION from the contract (reported): a capitalised "Zustand" on a line WITHOUT a German function word
# is the library (the real note for the dev query writes "Zustand 5" and "Zustand store"), so it matches.
check "zustand: capitalised mention on an English line matches (documented deviation)" "$(order)" 'hdr "== memory/proj/en-store.md  [1/1]  (memory)"'
lk immer
check "immer: matched in a code span, an import line, a from-quote, npm i and a fence" "$(order)" 'has "memory/proj/immer-span.md" "$OUT" && has "memory/proj/immer-import.md" "$OUT" && has "memory/proj/immer-from.md" "$OUT" && has "memory/proj/immer-npm.md" "$OUT" && has "memory/proj/immer-fence.md" "$OUT"'
check "immer: the German adverb in prose is NOT a hit; the capitalised library word outside code is not either" "$(order)" '! has "immer-prose" "$OUT" && ! has "en-store" "$OUT"'
lk --stack "$T/stackproj"
check "collision list applies to --stack keywords too (zustand from package.json is case-sensitive)" "$(cat "$OUT")" '! has "de-noun" "$OUT"'
CL="$T/lib-copy"; mkdir -p "$CL/lib"; cp "$REPO_ROOT/scripts/knowledge-lookup.sh" "$CL/"; cp "$REPO_ROOT"/scripts/lib/knowledge-lookup-*.sh "$CL/lib/"
printf 'keyword\tmode\nbroken\n' > "$CL/lib/knowledge-lookup-collisions.tsv"
KNOWLEDGE_LOOKUP_LOG=0 HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K" /bin/bash "$CL/knowledge-lookup.sh" zs >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "malformed collision row fails loud (exit 2, message names the file and line)" "rc=$RC err=$(cat "$ERR")" 'test "$RC" -eq 2 && has "knowledge-lookup-collisions.tsv:2" "$ERR" && test ! -s "$OUT"'
printf '# comment only\n' > "$CL/lib/knowledge-lookup-collisions.tsv"
KNOWLEDGE_LOOKUP_LOG=0 HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K" /bin/bash "$CL/knowledge-lookup.sh" zs >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "collision list without a header fails loud (exit 2)" "rc=$RC err=$(cat "$ERR")" 'test "$RC" -eq 2'

# ---- filters -------------------------------------------------------------------
lk kindtok
check "no filter: memory, rule and logbook hits all appear" "$(order)" 'test "$(blocks)" -eq 4'
lk --kind rule kindtok
check "--kind rule: only the rule" "$(order)" 'test "$(order)" = "rules/kindrule.md "'
lk --kind rule,logbook kindtok
check "--kind comma-separated: rule and logbook" "$(order)" 'test "$(blocks)" -eq 2 && has "rules/kindrule.md" "$OUT" && has "logbook/2026-02-02.md" "$OUT"'
lk --kind rule --kind memory kindtok
check "--kind repeatable: rule and both memory notes" "$(order)" 'test "$(blocks)" -eq 3'
lk --kind=memory kindtok
check "--kind=VALUE form works" "$(order)" 'test "$(blocks)" -eq 2'
lk --kind bogus kindtok
check "--kind with an unknown kind exits 2 and names it" "rc=$RC err=$(head -n 1 "$ERR")" 'test "$RC" -eq 2 && has "unknown kind: bogus" "$ERR"'
lk --kind
check "--kind without a value exits 2" "rc=$RC" 'test "$RC" -eq 2'
lk --project alpha kindtok
check "--project: only memory notes whose project folder contains the text" "$(order)" 'test "$(order)" = "memory/proj-alpha/a.md "'
lk --project ALP kindtok
check "--project is case-insensitive and a substring" "$(order)" 'test "$(order)" = "memory/proj-alpha/a.md "'
lk --project=proj- kindtok
check "--project=VALUE form; matches both project folders, no rule or logbook" "$(order)" 'test "$(blocks)" -eq 2'
lk --project nosuchproject kindtok
check "--project without a match: zero hits, exit 0" "rc=$RC" 'test "$RC" -eq 0 && has "0 files match" "$OUT"'

# ---- ranking: fields, logbook weight, co-occurrence, idf --------------------------------
lk xyztok
check "file name x3: the note named after the keyword beats a body mention" "$(order)" 'test "$(order)" = "rules/bmbase-xyztok.md rules/bmbody.md "'
lk logwtok
check "logbook is down-weighted (memory first) but not excluded" "$(order)" 'test "$(order)" = "memory/proj/logw.md logbook/2026-03-03.md "'
lk cotokone cotoktwo
check "same-line co-occurrence bonus: the same-line file beats the earlier-path split file" "$(order)" 'test "$(order)" = "memory/proj/co-z-same.md memory/proj/co-a-split.md "'

# ---- superseded ------------------------------------------------------------------
lk suptok
check "superseded: successor first, its predecessor directly after, orphan after every live hit" "$(order)" 'test "$(order)" = "memory/proj/sup-other.md memory/proj/sup-new.md memory/proj/sup-old.md memory/proj/sup-orphan.md "'
check "superseded flag on the header line" "$(grep '^== ' "$OUT")" 'has "  [superseded → memory/proj/sup-new.md]" "$OUT" && has "  [superseded → memory/proj/nowhere.md]" "$OUT" && test "$(grep -c "superseded →" "$OUT")" -eq 2'
lk swtok
check "D-10: superseded_by in [[wiki]] form without .md still orders the successor first" "$(order)" 'test "$(order)" = "memory/proj/sw-mid.md memory/proj/sw-new.md memory/proj/sw-old.md "'
lk satok
check "D-10: [[./mirror/path.md|alias]] form is normalised too" "$(order)" 'test "$(order)" = "memory/proj/sa-mid.md memory/proj/sa-new.md memory/proj/sa-old.md "'
lk imptok
check "V-05: an IMP copy with a ledger status: superseded is neither flagged nor reordered" "$(cat "$OUT")" '! has "superseded" "$OUT" && test "$(order)" = "ledger/IMP-901.md memory/proj/imp-new.md "'
lk --max 1 suptok
check "superseded ordering happens before the --max cut" "$(order)" 'test "$(order)" = "memory/proj/sup-other.md "'

# ---- ## Mentions --------------------------------------------------------------------
excluded mentghost "text after a '## Mentions' line is ignored for matching"
lk mentbody
check "text before '## Mentions' still matches" "$(order)" 'test "$(order)" = "memory/proj/mentions.md "'
lk mentfence
check "a '## Mentions' line inside a fenced block ends nothing" "$(order)" 'test "$(order)" = "memory/proj/mentions-fence.md "'

# ---- runtime on ~600 files -----------------------------------------------------------
K2="$T/know2"; for d in memory logbook rules plans evidence adr docs ledger; do mkdir -p "$K2/mirror/$d"; done
i=0
while [ "$i" -lt 600 ]; do
  case $((i % 8)) in 0) d=memory ;; 1) d=logbook ;; 2) d=rules ;; 3) d=plans ;; 4) d=evidence ;; 5) d=adr ;; 6) d=docs ;; *) d=ledger ;; esac
  printf '# note %s\nsome filler text about topic %s\nspeedtok on line three\n' "$i" "$i" > "$K2/mirror/$d/n$i.md"
  i=$((i+1))
done
command -v perl >/dev/null 2>&1 || { bad "perl available for timing" "perl missing"; summary; }
T0="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
KNOWLEDGE_LOOKUP_LOG=0 HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K2" /bin/bash "$LK" speedtok topic >"$OUT" 2>"$ERR" </dev/null; RC=$?
T1="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
EL="$(perl -e "printf '%.3f', $T1 - $T0")"
check "runtime on 600 files < 2 s (took ${EL}s)" "rc=$RC took ${EL}s" "test \"$RC\" -eq 0 && perl -e \"exit(($EL < 2.0) ? 0 : 1)\""
