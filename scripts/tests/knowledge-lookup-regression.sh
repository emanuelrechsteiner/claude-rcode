#!/usr/bin/env bash
# knowledge-lookup-regression.sh — regression suite for scripts/knowledge-lookup.sh
# (docs/OBSIDIAN.md, Stage 2) plus the "Library:" hint of hooks/session-start-context.sh.
#
# Pins: ranking (distinct keywords, then lines, then path), scope (only *.md in
# memory/rules/logbook/plans + ledger.md, NEVER anything outside mirror/),
# frontmatter and provenance lines never count, --max, --stack derivation, exit
# codes (0 ok, 1 library missing, 2 usage) and the 160-char line trim.
#
# MECHANICS — synthetic HOME and knowledge dir under mktemp -d; the REAL script
# ("$REPO_ROOT/scripts/knowledge-lookup.sh") and the REAL hook are called with
# /bin/bash (no reimplementation; rules/testing-quality.md "Verify Via the Same
# Code Path"). Never touches the real ~/.claude. All values are invented.
#
# bash 3.2 compatible. Usage: /bin/bash scripts/tests/knowledge-lookup-regression.sh
# check() evals its condition lazily: single-quoted conditions are expanded at eval
# time on purpose (SC2016), and the variables they name look unused to shellcheck (SC2034).
# shellcheck disable=SC2016,SC2034
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
w "$M/plans/fm.md" "---" "name: fmonlytok" "description: invented" "---" "$PROV" "body without the word"
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
LONG="longtok$(printf 'x%.0s' $(seq 1 400))"
w "$M/rules/long.md" "$LONG"
# multibyte trim fixtures (escapes only: 2-byte a-umlaut, 4-byte emoji)
rep() { local i=0 s=""; while [ "$i" -lt "$2" ]; do s="$s$1"; i=$((i+1)); done; printf '%s' "$s"; }
UML="$(printf '\303\244')"; EMO="$(printf '\360\237\230\200')"
w "$M/memory/proj/mb-a.md" "mbtok$(rep "$UML" 300)"
w "$M/memory/proj/mb-b.md" "mbtok$(rep "$EMO" 300)"
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

# lk <args...>: run the real script; sets RC, writes $OUT / $ERR. Env: HOME=$H, K set.
lk() { HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K" /bin/bash "$LK" "$@" >"$OUT" 2>"$ERR" </dev/null; RC=$?; }
first() { head -n 1 "$OUT"; }
has() { grep -qF -- "$1" "$2"; }
hasx() { grep -qxF -- "$1" "$2"; }   # whole-line match
blocks() { grep -c '^== ' "$OUT"; }

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
env -u CLAUDE_KNOWLEDGE_DIR HOME="$T/h2" /bin/bash "$LK" singletok >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "dir sourced from env.local.sh when env unset" "rc=$RC err=$(cat "$ERR")" "test \"$RC\" -eq 0 && has \"logbook/2026-01-01.md\" \"$OUT\""
CLAUDE_KNOWLEDGE_DIR="$T/nomirror" HOME="$T/h2" /bin/bash "$LK" singletok >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "environment wins over env.local.sh" "rc=$RC" "test \"$RC\" -eq 1"

# ---- matching ----------------------------------------------------------------
lk singletok
check "single keyword finds the right file, exit 0" "rc=$RC out=$(cat "$OUT")" "test \"$RC\" -eq 0 && has \"== logbook/2026-01-01.md  [1/1]\" \"$OUT\" && has \"2: the singletok lives here\" \"$OUT\""
check "first line format" "$(first)" "test \"$(first | sed 's/ in .*//')\" = \"knowledge-lookup: 1 files match (1 keywords)\""

mkdir -p "$H/know3/mirror/memory"; w "$H/know3/mirror/memory/t.md" "tildetok"
HOME="$H" CLAUDE_KNOWLEDGE_DIR="$H/know3" /bin/bash "$LK" tildetok >"$OUT" 2>"$ERR" </dev/null
check "mirror path shows \$HOME as ~" "$(first)" "has \" in ~/know3/mirror\" \"$OUT\""

lk rankone ranktwo
L1="$(grep '^== ' "$OUT" | sed -n 1p)"; L2="$(grep '^== ' "$OUT" | sed -n 2p)"
check "ranking: 2-of-2 file beats 1-of-2 file with more lines" "1st='$L1' 2nd='$L2'" "test \"$L1\" = \"== memory/proj/z-both.md  [2/2]\" -a \"$L2\" = \"== memory/proj/a-many.md  [1/2]\""
A_LINES="$(awk '/^== memory\/proj\/a-many/{f=1;next} /^== /{f=0} f&&/^[0-9]+: /{n++} END{print n+0}' "$OUT")"
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
check "mirror/ledger.md is searched" "$(cat "$OUT")" "has \"== ledger.md\" \"$OUT\""

lk longtok
EXP="1: ${LONG:0:160}"
check "ASCII line is cut to exactly 160 chars" "rc=$RC got=$(sed -n 2p "$OUT")" 'test "$RC" -eq 0 && hasx "$EXP" "$OUT"'

# Multibyte: the expectation is built independently (5 ASCII + 155 characters = 160).
lk mbtok
EXP_A="1: mbtok$(rep "$UML" 155)"; EXP_B="1: mbtok$(rep "$EMO" 155)"
check "2-byte characters: cut at exactly 160 chars, whole characters, exit 0" "rc=$RC err=$(cat "$ERR")" 'test "$RC" -eq 0 && hasx "$EXP_A" "$OUT"'
check "4-byte characters: cut at exactly 160 chars, whole characters, exit 0" "rc=$RC" 'hasx "$EXP_B" "$OUT"'
check "multibyte output has exactly header + 2 blocks of 2 lines (nothing dropped or added)" "lines=$(wc -l < "$OUT")" 'test "$(wc -l < "$OUT" | tr -d " ")" -eq 5'
lk mbtok --max 1
check "multibyte with truncation: exit 0 and remainder line still printed" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && hasx "... 1 more files (raise --max)" "$OUT"'

# ---- ranking tie-breaks ------------------------------------------------------
lk tiealpha
check "same distinct count: more matching lines ranks first (not path order)" "$(grep '^== ' "$OUT")" 'test "$(grep "^== " "$OUT" | sed -n 1p)" = "== memory/proj/tie-b-lines.md  [1/1]" -a "$(grep "^== " "$OUT" | sed -n 2p)" = "== memory/proj/tie-a-line.md  [1/1]"'
lk pathtok
check "identical counts: path ascending (created c, a, b)" "$(grep '^== ' "$OUT" | tr '\n' '|')" 'test "$(grep "^== " "$OUT" | tr "\n" "|")" = "== rules/p-a.md  [1/1]|== rules/p-b.md  [1/1]|== rules/p-c.md  [1/1]|"'
lk pathtok --max 1
check "--max 1 shows the path-first file" "$(cat "$OUT")" 'hasx "== rules/p-a.md  [1/1]" "$OUT" && ! has "p-b.md" "$OUT" && hasx "... 2 more files (raise --max)" "$OUT"'

# ---- exclusions (mechanical pins) -------------------------------------------
excluded() { # <keyword> <label>
  lk "$1"
check "$2" "rc=$RC out=$(cat "$OUT")" "test \"$RC\" -eq 0 && has \"0 files match\" \"$OUT\" && test \"$(blocks)\" -eq 0"
}
excluded fmonlytok "YAML frontmatter line does NOT count"
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
HOME="$H" CLAUDE_KNOWLEDGE_DIR="$T/know-ledger" /bin/bash "$LK" symledgertok controltok >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "symlinked ledger.md is not followed (control file still found)" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "== memory/ok.md" "$OUT" && ! has "ledger.md" "$OUT"'
HOME="$H" CLAUDE_KNOWLEDGE_DIR="$T/know-plans" /bin/bash "$LK" symplanstok controltok >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "symlinked scope directory (plans -> outside) is not descended (control found)" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "== memory/ok.md" "$OUT" && ! has "symplanstok" "$OUT" && ! has "== plans/" "$OUT"'

# Frontmatter edge cases: only the header lines are excluded, nothing else.
lk bodyfmtok
check "frontmatter file: header hit ignored, body hit still counts (line 4 only)" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "knowledge-lookup: 1 files match" "$OUT" && hasx "== plans/fm-body.md  [1/1]" "$OUT" && hasx "4: bodyfmtok in the body" "$OUT" && ! has "2: description" "$OUT"'
lk bodyruletok
check "no frontmatter: a body '---' rule excludes nothing (lines 2 and 4 both match)" "rc=$RC out=$(cat "$OUT")" 'hasx "2: bodyruletok before the rule" "$OUT" && hasx "4: bodyruletok after the rule" "$OUT"'
lk unclosedtok
check "unclosed frontmatter is no frontmatter: its lines match" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && hasx "== plans/unclosed.md  [1/1]" "$OUT" && hasx "2: name: unclosedtok" "$OUT"'

# ---- --stack -----------------------------------------------------------------
S="$T/stackproj"; mkdir -p "$S"
printf '{"name":"p","dependencies":{"next":"14.0.0"},"devDependencies":{"zustand":"4.0.0"}}\n' > "$S/package.json"
printf '// swift-tools-version:5.9\nlet package = Package(dependencies: [\n  .package(url: "https://example.invalid/org/SwiftyThing.git", from: "1.0.0"),\n])\n' > "$S/Package.swift"
lk --stack "$S"
check "--stack prints derived keywords on stderr" "rc=$RC err=$(cat "$ERR")" "test \"$RC\" -eq 0 && grep -q '^keywords:.*next' \"$ERR\" && grep -q '^keywords:.*zustand' \"$ERR\" && grep -q '^keywords:.* swiftything\$' \"$ERR\""
check "--stack finds fixture files for derived keywords" "$(cat "$OUT")" "has \"memory/proj/zs.md\" \"$OUT\" && has \"memory/proj/nx.md\" \"$OUT\" && has \"memory/proj/sw.md\" \"$OUT\""

# One directory per manifest, exact derived keyword line (also pins lowercasing: the
# fixtures use mixed-case names). Junk that must NOT leak is part of every fixture.
ST="$T/st"; mkdir -p "$ST"
mkp() { mkdir -p "$ST/$1"; printf '%s' "$ST/$1"; }
kwline() { sed -n 's/^keywords: //p' "$ERR"; }
stack_is() { # <label> <dir> <expected keyword line>
  WANT="$3"; lk --stack "$2"
  check "$1" "rc=$RC got='$(kwline)' want='$WANT'" 'test "$RC" -eq 0 && test "$(kwline)" = "$WANT"'
}
PJ='{
  "name": "p",
  "scripts": {"build": "tool --flag"},
  "dependencies": {
    "Next": "14.0.0",
    "@scope/Pkg": "1.0.0"
  },
  "peerDependencies": {"peerpkg": "1"},
  "devDependencies": {"ZuStand": "4.0.0"}
}'
w "$(mkp pj-jq)/package.json" "$PJ"
stack_is "package.json (jq): dependencies + devDependencies keys, lowercased, nothing else" "$ST/pj-jq" "next @scope/pkg zustand"

# No-jq fallback: a PATH with every tool the script needs EXCEPT jq.
NJ="$T/nojq-bin"; mkdir -p "$NJ"
for t in awk sed tr cat wc grep find sort head mkdir mktemp rm; do ln -sf "$(command -v $t)" "$NJ/$t"; done
check "no-jq PATH really hides jq (test precondition)" "jq still resolvable" '! PATH="$NJ" command -v jq >/dev/null 2>&1'
lk_nojq() { HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K" PATH="$NJ" /bin/bash "$LK" "$@" >"$OUT" 2>"$ERR" </dev/null; RC=$?; }
lk_nojq --stack "$ST/pj-jq"
check "package.json (no-jq awk fallback): same keywords as the jq path" "rc=$RC got='$(kwline)' err=$(cat "$ERR")" 'test "$RC" -eq 0 && test "$(kwline)" = "next @scope/pkg zustand"'
w "$(mkp pj-oneline)/package.json" '{"name":"p","dependencies":{"A1":"1","b2":"2"},"devDependencies":{"C3":"3"}}'
lk_nojq --stack "$ST/pj-oneline"
check "package.json single line (no-jq awk fallback)" "rc=$RC got='$(kwline)'" 'test "$RC" -eq 0 && test "$(kwline)" = "a1 b2 c3"'

w "$(mkp swift)/Package.swift" '// .package(url: "https://x.invalid/commented/Nope.git", from: "1")' \
  'let p = Package(dependencies: [' \
  '  .package(url: "https://example.invalid/org/SwiftyThing.git", from: "1.0.0"),' \
  '  .package(name: "Named", path: "../Local/"),' \
  '], targets: [.target(name: "T", dependencies: [.product(name: "Prod", package: "SwiftyThing")])])'
stack_is "Package.swift: package url/name/path segments and product names, comments ignored" "$ST/swift" "swiftything named local prod"

w "$(mkp req)/requirements.txt" "# comment" "Flask==2.0  # pin" 'Requests>=2.0; python_version<"3"' "-r other.txt" \
  "git+https://example.invalid/x.git" "numpy[extra]~=1.0" "" "   " "PyYAML" "./libs/localpkg" "/abs/path/otherpkg" "mypkg @ ./vendor/mypkg"
stack_is "requirements.txt: names without pins/extras/markers; comments, options, URLs, blanks, local paths skipped" "$ST/req" "flask requests numpy pyyaml"

w "$(mkp pyproj)/pyproject.toml" "[build-system]" 'requires = ["setuptools>=61"]' "" "[project]" 'name = "demo"' "dependencies = [" \
  '  "FastAPI>=0.100",' '  "Pydantic[email]==2.0",  # c' "  \"uvicorn ; python_version>'3'\"," "]" \
  "[project.optional-dependencies]" 'dev = ["pytest"]'
stack_is "pyproject.toml: only [project] dependencies (no build-system, optional or project name)" "$ST/pyproj" "fastapi pydantic uvicorn"

w "$(mkp cargo)/Cargo.toml" "[package]" 'name = "demo"' "[dependencies]" 'Serde = { version = "1" }' 'tokio = "1"' \
  "[dependencies.Reqwest]" 'version = "1"' "[dev-dependencies]" 'criterion = "1"'
stack_is "Cargo.toml: [dependencies] keys and [dependencies.x] tables, not dev-dependencies or the package name" "$ST/cargo" "serde tokio reqwest"

w "$(mkp gomod)/go.mod" "module example.invalid/demo" "" "go 1.21" "" "require github.com/Gin-Gonic/gin v1.9.0" "require (" \
  "	github.com/stretchr/testify/v2 v2.0.0" "	golang.org/x/text v0.3.0 // indirect" "	// github.com/commented/out v1.0.0" ")"
stack_is "go.mod: last path segment, /vN suffix dropped, '// indirect' and comment lines ignored" "$ST/gomod" "gin testify text"

# Dedup + lowercase across manifests (same name in different case, in two manifests).
w "$(mkp dedup)/package.json" '{"dependencies":{"Lodash":"1","vite":"5"},"devDependencies":{"LODASH":"1"}}'
w "$ST/dedup/requirements.txt" "LoDash" "vite"
stack_is "dedup across entries and manifests, case-insensitive" "$ST/dedup" "lodash vite"

# 25-keyword cap. 6000 dependencies make the old `| head -n 25` trailing stage close the
# pipe while awk still had output to write (SIGPIPE, exit 141 under pipefail).
mkdir -p "$ST/many"
awk 'BEGIN { printf "{\"dependencies\": {\n"; for (i = 1; i <= 6000; i++) printf "  \"dep%05d\": \"1\"%s\n", i, (i < 6000 ? "," : ""); printf "}}\n" }' > "$ST/many/package.json"
lk --stack "$ST/many"
check "25 cap (jq): exit 0 and exactly the first 25 names" "rc=$RC words=$(kwline | wc -w)" 'test "$RC" -eq 0 && test "$(kwline | wc -w | tr -d " ")" -eq 25 && test "$(kwline | cut -d" " -f1)" = "dep00001" && test "$(kwline | cut -d" " -f25)" = "dep00025"'
check "25 cap: the count shown in line 1 is 25" "$(first)" 'has "(25 keywords)" "$OUT"'
lk_nojq --stack "$ST/many"
check "25 cap (no-jq fallback): exit 0 and exactly 25 names" "rc=$RC words=$(kwline | wc -w)" 'test "$RC" -eq 0 && test "$(kwline | wc -w | tr -d " ")" -eq 25'
w "$(mkp manyfiles)/requirements.txt" $(seq -f 'req%03g' 1 40)
cp "$ST/many/package.json" "$ST/manyfiles/package.json"
lk --stack "$ST/manyfiles"
check "25 cap across several manifests: exit 0, 25 names" "rc=$RC words=$(kwline | wc -w)" 'test "$RC" -eq 0 && test "$(kwline | wc -w | tr -d " ")" -eq 25'

# Explicit keywords + --stack: combined; and explicit keywords rescue an empty stack.
lk --stack "$ST/cargo" singletok
check "explicit keyword + --stack are combined (K = 3 derived + 1)" "rc=$RC first=$(first)" 'test "$RC" -eq 0 && has "(4 keywords)" "$OUT" && has "== logbook/2026-01-01.md  [1/4]" "$OUT"'
mkdir -p "$ST/none"
lk --stack "$ST/none" singletok
check "empty stack + explicit keywords: exit 0, search runs, reason on stderr" "rc=$RC err=$(cat "$ERR")" 'test "$RC" -eq 0 && has "no stack keywords found" "$ERR" && has "(1 keywords)" "$OUT" && has "== logbook/2026-01-01.md" "$OUT"'
lk --stack "$ST/does-not-exist-dir"
check "--stack with a missing directory exits 2" "rc=$RC err=$(cat "$ERR")" 'test "$RC" -eq 2'

E="$T/emptyproj"; mkdir -p "$E"
lk --stack "$E"
check "--stack in empty dir without keywords exits 2" "rc=$RC" "test \"$RC\" -eq 2"
check "--stack empty dir explains on stderr" "$(cat "$ERR")" "has \"no stack keywords found\" \"$ERR\""

# ---- runtime on ~320 files ---------------------------------------------------
K2="$T/know2"; mkdir -p "$K2/mirror/memory" "$K2/mirror/logbook"
i=0
while [ "$i" -lt 320 ]; do
  d=memory; [ $((i % 2)) -eq 0 ] && d=logbook
  printf '# note %s\nsome filler text about topic %s\nspeedtok on line three\n' "$i" "$i" > "$K2/mirror/$d/n$i.md"
  i=$((i+1))
done
command -v perl >/dev/null 2>&1 || { bad "perl available for timing" "perl missing"; summary; }
T0="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K2" /bin/bash "$LK" speedtok topic >"$OUT" 2>"$ERR" </dev/null; RC=$?
T1="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
EL="$(perl -e "printf '%.3f', $T1 - $T0")"
check "runtime on 320 files < 2 s (took ${EL}s)" "rc=$RC took ${EL}s" "test \"$RC\" -eq 0 && perl -e \"exit(($EL < 2.0) ? 0 : 1)\""

# ---- session-start hook hint -------------------------------------------------
echo "-- hooks/session-start-context.sh library hint --"
HK="$T/hookknow"; HH="$T/hookhome"
mkdir -p "$HK/mirror/memory/a" "$HH/.claude" "$T/hookcwd"
for n in 1 2 3; do w "$HK/mirror/memory/a/n$n.md" "# note $n"; done
w "$HK/mirror/memory/skipped.jsonl" "{}"
w "$HK/mirror/README.md" "# Knowledge mirror" "Last run: 2026-10-08T12:00:00Z (UTC)."
hook() { # [VAR=value ...]  (library env is UNSET unless passed; nudge setting is the hook default)
  ( cd "$T/hookcwd" && env -u CLAUDE_BAUHOF_ROOT -u CLAUDE_KNOWLEDGE_DIR -u CLAUDE_SESSION_NUDGE \
      HOME="$HH" "$@" /bin/bash "$HOOK" </dev/null >"$OUT" 2>&1 ); RC=$?
}
libline() { grep -c 'Library: ' "$OUT"; }
if [ ! -f "$HOOK" ]; then
  bad "hook under test exists" "hook not found: $HOOK"
else
  hook CLAUDE_KNOWLEDGE_DIR="$HK"
  check "hint present with exact count and date (default nudge setting)" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "Library: 3 cross-project memory notes mirrored 2026-10-08" "$OUT" && has "knowledge-lookup.sh --stack" "$OUT" && test "$(libline)" -eq 1'
  hook CLAUDE_KNOWLEDGE_DIR="$HK" CLAUDE_SESSION_NUDGE=0
  check "hint still printed with CLAUDE_SESSION_NUDGE=0 (no extra condition)" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "Library: 3 cross-project" "$OUT" && ! has "Subagents available" "$OUT"'
  printf 'export CLAUDE_KNOWLEDGE_DIR="%s"\n' "$HK" > "$HH/.claude/env.local.sh"
  hook
  check "hint present via ~/.claude/env.local.sh when the env var is unset" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "Library: 3 cross-project" "$OUT"'
  hook CLAUDE_KNOWLEDGE_DIR="$T/nolib"
  check "environment wins over env.local.sh (env dir has no mirror -> no hint)" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "cwd:" "$OUT" && ! has "Library:" "$OUT"'
  rm "$HH/.claude/env.local.sh"
  hook
  check "hint absent when no env var and no env.local.sh, hook exits 0" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "cwd:" "$OUT" && ! has "Library:" "$OUT"'
  printf 'export CLAUDE_KNOWLEDGE_DIR=""\n' > "$HH/.claude/env.local.sh"
  hook
  check "hint absent when env.local.sh sets an empty dir, hook exits 0" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "cwd:" "$OUT" && ! has "Library:" "$OUT"'
  rm "$HH/.claude/env.local.sh"
  rm "$HK/mirror/README.md"
  hook CLAUDE_KNOWLEDGE_DIR="$HK"
  check "hint absent when mirror/README.md is missing, hook exits 0" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && has "cwd:" "$OUT" && ! has "Library:" "$OUT"'
  hook CLAUDE_KNOWLEDGE_DIR="$HK" CLAUDE_SESSION_NUDGE=0
  check "hint absent when README is missing, also with CLAUDE_SESSION_NUDGE=0" "rc=$RC out=$(cat "$OUT")" 'test "$RC" -eq 0 && ! has "Library:" "$OUT"'
fi

summary
