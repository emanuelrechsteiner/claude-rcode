#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
# knowledge-lookup-regression cases: --stack keyword derivation (one directory per manifest type).
# Sourced by scripts/tests/knowledge-lookup-regression.sh (never run on its own); shares its
# helpers, fixtures and variables (T H K M OUT ERR RC w lk check has hasx first excluded ...).

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
