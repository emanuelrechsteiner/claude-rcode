#!/usr/bin/env bash
# knowledge-mirror-regression.sh — regression suite for scripts/knowledge-mirror.sh
# (IMP-248, docs/OBSIDIAN.md).
#
# Pins the two properties that matter most: (1) *.local.md overlays and /vault/
# paths NEVER reach the copy (*.jsonl is unreachable by the allowlist; that
# check is defense in depth, not a pin), (2) a hand-edited copy is refused
# (exit 3) BEFORE any write, never silently overwritten. Plus target refusals
# (incl. symlinks inside mirror/ and protected roots), provenance, ledger
# digest, state file, idempotence and notes/ safety.
#
# MECHANICS — builds a synthetic HOME under mktemp -d and calls the REAL script
# ("$REPO_ROOT/scripts/knowledge-mirror.sh") with HOME pointed at it; no
# reimplementation of the mirror logic (rules/testing-quality.md "Verify Via
# the Same Code Path"). Sinks are checked on disk (grep -r over the target
# tree), not via the script's own counters. Never touches the real ~/.claude.
# The sentinel is a fixture string, not real private content.
#
# bash 3.2 compatible. Usage: /bin/bash scripts/tests/knowledge-mirror-regression.sh
# Every child shell is /bin/bash (3.2 on macOS) whatever bash is first in PATH, so
# 3.2 behaviour (set -e after a false `[ ] && cmd`, no assoc arrays) is what runs.
#
# LAYOUT — this file holds the harness, the real-run and frontmatter cases; the
# fixtures and the remaining cases live in scripts/tests/lib/km-*.sh, sourced in
# order (one shell, shared variables), so no file passes the 250-line limit (rules/code-quality.md).
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
KM="$REPO_ROOT/scripts/knowledge-mirror.sh"
SENTINEL="PRIVATE-SENTINEL-MUST-NOT-LEAK"
VSENTINEL="VAULT-DECOY-MUST-NOT-LEAK"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \xe2\x9c\x85 %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \xe2\x9d\x8c %s\n     %s\n' "$1" "$2"; }
# check <label> <detail-on-fail> <command...> — passes when the command succeeds
check() { local l="$1" d="$2"; shift 2; if "$@"; then ok "$l"; else bad "$l" "$d"; fi; }

summary() {
  echo
  echo "knowledge-mirror-regression: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
}

if [ ! -f "$KM" ]; then
  bad "script under test exists" "script not found: $KM"
  summary
fi

T="$(mktemp -d "${TMPDIR:-/tmp}/km-regress.XXXXXX")" || { echo "ERROR: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
H="$T/home"; C="$H/.claude"; K="$T/know"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/km-fixtures.sh"

echo "== help =="
run --help
check "--help exits 0" "rc=$RC" test "$RC" -eq 0

echo "== dry-run =="
run --dry-run
check "dry-run exits 0" "rc=$RC err=$ERR" test "$RC" -eq 0
for t in mirror/logbook/2026-01-01.md mirror/logbook/2026-01-02.md \
         mirror/memory/-proj-a/sample.md mirror/memory/-proj-a/MEMORY.md \
         mirror/plans/meta-proposal-2026-01-01.md mirror/rules/a.md mirror/rules/b.md mirror/rules/refs.md \
         mirror/evidence/a.md mirror/adr/0001-x.md mirror/docs/top.md mirror/docs/CONTEXT.md mirror/ledger.md; do
  check "dry-run lists $t" "output: $OUT" grep -qF "$t" <<<"$OUT"
done
for id in $LEDGER_IDS; do
  check "dry-run lists ledger/$id.md exactly once" "output: $OUT" \
    /bin/bash -c '[ "$(grep -cF "mirror/ledger/$1.md" <<<"$2")" = 1 ]' _ "$id" "$OUT"
done
check "dry-run lists no note for OTHER-7 / IMP-077 (outside the contract scope)" "$OUT" \
  /bin/bash -c '! grep -qE "OTHER-7|IMP-077" <<<"$1"' _ "$OUT"
check "dry-run lists the file with a space exactly once" "$OUT" \
  /bin/bash -c '[ "$(grep -cF "mirror/rules/with space.md <-" <<<"$1")" = 1 ]' _ "$OUT"
check "dry-run does not list non-allowlisted plan" "$OUT" /bin/bash -c '! grep -qF not-a-proposal <<<"$1"' _ "$OUT"
check "dry-run does not list nested doc (top level only)" "$OUT" /bin/bash -c '! grep -qF skip.md <<<"$1"' _ "$OUT"
check "dry-run prints TOTAL $EXPECT_TOTAL (fixture-derived)" "$OUT" grep -qx "TOTAL $EXPECT_TOTAL" <<<"$OUT"
check "dry-run prints CHANGED line" "$OUT" grep -qE '^CHANGED [0-9]+$' <<<"$OUT"
check "dry-run writes nothing (no mirror/, no notes/)" "$(ls -A "$K" 2>&1)" \
  /bin/bash -c '[ ! -e "$1/mirror" ] && [ ! -e "$1/notes" ]' _ "$K"
check "dry-run output has no .local.md / vault/ / .jsonl" "$OUT $ERR" no_leak_names

echo "== real run =="
run
check "real run exits 0" "rc=$RC err=$ERR" test "$RC" -eq 0
check "real run output has no .local.md / vault/ / .jsonl" "$OUT $ERR" no_leak_names
check "real run prints TOTAL $EXPECT_TOTAL and CHANGED > 0" "$OUT" \
  /bin/bash -c 'grep -qx "TOTAL $2" <<<"$1" && grep -qE "^CHANGED [1-9][0-9]*$" <<<"$1"' _ "$OUT" "$EXPECT_TOTAL"
check "real run prints the LINKS summary line (graph health signal)" "$OUT" \
  grep -qxE 'LINKS total=[0-9]+ resolved=[0-9]+ ambiguous=[0-9]+ dangling=[0-9]+' <<<"$OUT"
check "real run LINKS line has the expected totals" "$(grep '^LINKS' <<<"$OUT")" \
  grep -qx "LINKS total=$EXP_LINKS" <<<"$OUT"
check "grep -r sentinel in target finds nothing" "$(grep -rl "$SENTINEL" "$K" 2>/dev/null)" \
  /bin/bash -c '! grep -rq "$1" "$2"' _ "$SENTINEL" "$K"
check "reachable vault decoy (projects/vault/memory) content absent from target" "$(grep -rl "$VSENTINEL" "$K" 2>/dev/null)" \
  /bin/bash -c '! grep -rq "$1" "$2"' _ "$VSENTINEL" "$K"
check "no mirror/memory/vault dir" "present" test ! -e "$K/mirror/memory/vault"
check "no *.local.md / vault path in target tree" "$(find "$K" 2>/dev/null | grep -E 'local\.md|vault')" \
  /bin/bash -c '! find "$1" | grep -qE "local\.md|vault"' _ "$K"
check "no .jsonl in target: unreachable by allowlist (defense in depth)" "$(find "$K" -name '*.jsonl' 2>/dev/null)" \
  /bin/bash -c '[ -z "$(find "$1" -name "*.jsonl")" ]' _ "$K"
check "mirror/rules/a.md exists" "missing" test -f "$K/mirror/rules/a.md"
check "mirror/rules/b.md exists" "missing" test -f "$K/mirror/rules/b.md"
check "mirror/rules has no zz-private copy" "present" test ! -e "$K/mirror/rules/zz-private.local.md"
check "memory .local.md absent from copy" "present" test ! -e "$K/mirror/memory/-proj-a/secret.local.md"
check "empty memory dir yields no copy dir content" "$(ls -A "$K/mirror/memory/-proj-b" 2>&1)" \
  /bin/bash -c '[ -z "$(ls -A "$1/mirror/memory/-proj-b" 2>/dev/null)" ]' _ "$K"
check "non-allowlisted plan not copied" "present" test ! -e "$K/mirror/plans/not-a-proposal.md"

echo "== new sources: evidence / adr / docs =="
check "evidence/a.md copied" "missing" test -f "$K/mirror/evidence/a.md"
check "evidence/orphan.md copied" "missing" test -f "$K/mirror/evidence/orphan.md"
check "adr/0001-x.md copied" "missing" test -f "$K/mirror/adr/0001-x.md"
check "docs/top.md copied" "missing" test -f "$K/mirror/docs/top.md"
check "docs/CONTEXT.md copied (from ~/.claude/CONTEXT.md)" "missing" test -f "$K/mirror/docs/CONTEXT.md"
check "nested doc docs/nested/skip.md NOT copied (top level only)" "$(find "$K" -name skip.md)" \
  /bin/bash -c '[ -z "$(find "$1" -name skip.md)" ] && ! grep -rq NESTED-MUST-NOT-COPY "$1"' _ "$K"
check "no copy of the .local.md decoys in new folders" "$(find "$K" -name '*.local.md')" \
  /bin/bash -c '[ -z "$(find "$1" -name "*.local.md")" ]' _ "$K"

echo "== kind/origin frontmatter + provenance =="
# <mirror rel>|<kind>|<source rel under ~/.claude>
for row in "logbook/2026-01-01.md|logbook|logbook/2026-01-01.md" \
           "memory/-proj-a/sample.md|memory|projects/-proj-a/memory/sample.md" \
           "memory/-proj-a/MEMORY.md|memory|projects/-proj-a/memory/MEMORY.md" \
           "plans/meta-proposal-2026-01-01.md|plan|plans/meta-proposal-2026-01-01.md" \
           "rules/a.md|rule|rules/a.md" "rules/refs.md|rule|rules/refs.md" "rules/unclosed.md|rule|rules/unclosed.md" \
           "evidence/a.md|evidence|docs/archive/rules-evidence/a.md" "adr/0001-x.md|adr|docs/adr/0001-x.md" \
           "docs/top.md|doc|docs/top.md" "docs/CONTEXT.md|doc|CONTEXT.md"; do
  IFS='|' read -r rel ty sr <<<"$row"
  f="$K/mirror/$rel"
  check "$rel: line 1 is ---, line 2 'kind: $ty'" "$(head -3 "$f" 2>&1)" \
    /bin/bash -c '[ "$(sed -n 1p "$1")" = "---" ] && [ "$(sed -n 2p "$1")" = "kind: $2" ]' _ "$f" "$ty"
  check "$rel: line 3 origin: \"~/.claude/$sr\" (double-quoted scalar)" "$(head -3 "$f" 2>&1)" \
    /bin/bash -c '[ "$(sed -n 3p "$1")" = "origin: \"~/.claude/$2\"" ]' _ "$f" "$sr"
  check "$rel: provenance directly after the closing ---" "$(head -8 "$f" 2>&1)" prov_after_fm "$f"
done
for id in $LEDGER_IDS; do
  check "ledger/$id.md: kind imp + provenance after frontmatter" "$(head -14 "$K/mirror/ledger/$id.md" 2>&1)" \
    /bin/bash -c 'sed -n 2p "$1" | grep -qx "kind: imp" && "$2" "$1"' _ "$K/mirror/ledger/$id.md" prov_after_fm
done
check "ledger.md (index): kind imp, origin, provenance directly after the frontmatter" "$(head -6 "$K/mirror/ledger.md" 2>&1)" \
  /bin/bash -c '[ "$(sed -n 1p "$1")" = "---" ] && [ "$(sed -n 2p "$1")" = "kind: imp" ] && [ "$(sed -n 3p "$1")" = "origin: \"~/.claude/global-observation/improvement-ledger.json\"" ] && "$2" "$1"' _ "$K/mirror/ledger.md" prov_after_fm

SM="$K/mirror/memory/-proj-a/sample.md"
SMSRC="$C/projects/-proj-a/memory/sample.md"
check "existing frontmatter: original keys byte-identical, after the inserted kind/origin" "$(cat "$SM" 2>&1)" \
  /bin/bash -c '[ "$(sed -n $((4+GM)),$((7+GM))p "$1")" = "$(sed -n 2,5p "$2")" ] && [ "$(sed -n $((8+GM))p "$1")" = "---" ]' _ "$SM" "$SMSRC"
check "existing frontmatter: no second frontmatter block, exactly one kind: line at top level" "$(cat "$SM")" \
  /bin/bash -c '[ "$(grep -c "^kind: " "$1")" = 1 ]' _ "$SM"
check "frontmatter copy keeps body" "body lost" grep -q 'Body text.' "$SM"
check "frontmatter line with backtick path is NOT rewritten" "$(sed -n 5p "$SM")" \
  grep -qF 'description: invented see `rules/a.md` here' "$SM"
MM="$K/mirror/memory/-proj-a/MEMORY.md"
check "MEMORY.md copy: generated frontmatter (--- / kind / origin / dated / dated_from / ---) then provenance on line 5+GM" "$(head -5 "$MM" 2>&1)" \
  /bin/bash -c '[ "$(sed -n $((4+GM))p "$1")" = "---" ] && sed -n $((5+GM))p "$1" | grep -q "^<!-- knowledge-mirror: copied from ~/"' _ "$MM"
RF="$K/mirror/rules/refs.md"
check "horizontal rule in body is not treated as frontmatter (one kind: line, rule kept)" "$(cat "$RF")" \
  /bin/bash -c '[ "$(grep -c "^kind: " "$1")" = 1 ] && [ "$(sed -n $((4+GM))p "$1")" = "---" ] && [ "$(sed -n $((6+GM))p "$1")" = "# Refs" ] && [ "$(grep -c "^---$" "$1")" = 3 ]' _ "$RF"
UC="$K/mirror/rules/unclosed.md"
check "source with unclosed --- counts as no frontmatter (generated block, original --- kept)" "$(cat "$UC")" \
  /bin/bash -c '[ "$(sed -n $((4+GM))p "$1")" = "---" ] && [ "$(sed -n $((6+GM))p "$1")" = "---" ] && [ "$(sed -n $((7+GM))p "$1")" = "no closing marker here" ]' _ "$UC"
# Real shape: live memory notes carry top-level type:/source: keys of their own. Ours
# are kind:/origin: under every source shape, so there is never a clash (a duplicate
# top-level key would be invalid YAML: Obsidian drops the whole properties block).
RM="$K/mirror/memory/-proj-a/real.md"
check "real memory note: source keys type:/source: stay byte-identical" "$(cat "$RM")" \
  /bin/bash -c 'grep -qxF "type: feedback" "$1" && grep -qxF "source: web" "$1"' _ "$RM"
check "real memory note: our keys are plain kind: / origin: right after the opening --- (same as every other copy)" "$(head -4 "$RM")" \
  /bin/bash -c '[ "$(sed -n 2p "$1")" = "kind: memory" ] && [ "$(sed -n 3p "$1")" = "origin: \"~/.claude/projects/-proj-a/memory/real.md\"" ]' _ "$RM"
check "no copy and no ledger note contains the retired key names (mirror_type, mirror_source, generated type:/source:)" "$(grep -rlE '^(mirror_type|mirror_source):' "$K/mirror" 2>&1)" \
  /bin/bash -c '! grep -rqE "^(mirror_type|mirror_source):" "$1" && ! grep -rlE "^(type|source):" "$1" | grep -vE "/memory/-proj-a/real.md$"' _ "$K/mirror"
check "every written copy (hashes.tsv rows incl. ledger index and notes = TOTAL $EXPECT_TOTAL) has exactly one kind: line" "$(every_copy_one_kind 2>&1)" every_copy_one_kind
check "real memory note: original keys keep their order after ours, provenance after the closing ---" "$(head -9 "$RM")" \
  /bin/bash -c '[ "$(sed -n $((4+GM)),$((6+GM))p "$1" | tr "\n" "|")" = "name: real-memory|type: feedback|source: web|" ] && [ "$(sed -n $((7+GM))p "$1")" = "---" ]' _ "$RM"
check "NO mirror copy has a duplicate top-level frontmatter key" "$(no_dup_keys 2>&1)" no_dup_keys
CR="$K/mirror/rules/crlf.md"
check "CRLF frontmatter: line 1 and our two inserted lines end in CR, kind rule" "$(head -3 "$CR" | od -c | head -5)" \
  /bin/bash -c 'crline "$1" 1 && crline "$1" 2 && crline "$1" 3 && crline "$1" $((3+GM)) && [ "$(sed -n 2p "$1" | tr -d "\r")" = "kind: rule" ]' _ "$CR"
check "CRLF frontmatter: original key and closing --- keep their CR, provenance follows" "$(head -6 "$CR" | od -c | head -8)" \
  /bin/bash -c '[ "$(sed -n $((4+GM))p "$1" | tr -d "\r")" = "name: crlf" ] && [ "$(sed -n $((5+GM))p "$1" | tr -d "\r")" = "---" ] && sed -n $((6+GM))p "$1" | grep -q "^<!-- knowledge-mirror: copied from ~/"' _ "$CR"
check "CRLF body: backtick path linked and the line's CR is kept" "$(sed -n $((7+GM))p "$CR" | od -c | head -3)" \
  /bin/bash -c 'sed -n $((7+GM))p "$1" | grep -qF "[[rules/a]]" && crline "$1" $((7+GM))' _ "$CR"
FO="$K/mirror/rules/fmonly.md"; FE="$K/mirror/rules/fmempty.md"
check "frontmatter-only file: exactly --- / kind / origin / dated / dated_from / name / --- / provenance, nothing else" "$(cat "$FO")" \
  /bin/bash -c '[ "$(wc -l < "$1" | tr -d " ")" = $((6+GM)) ] && [ "$(sed -n 2p "$1")" = "kind: rule" ] && [ "$(sed -n $((4+GM))p "$1")" = "name: fmonly" ] && [ "$(sed -n $((5+GM))p "$1")" = "---" ]' _ "$FO"
check "empty frontmatter (--- / ---): our keys inside it, provenance after, 5+GM lines" "$(cat "$FE")" \
  /bin/bash -c '[ "$(wc -l < "$1" | tr -d " ")" = $((5+GM)) ] && [ "$(sed -n $((4+GM))p "$1")" = "---" ] && prov_after_fm "$1"' _ "$FE"
PT="$K/mirror/rules/partial.md"
check "partial path matches stay exactly as written (scripts/rules/a.md, docs/adr/top.md, docs/0001-x.md, rules/a.md.bak, xrules/a.md)" "$(tail -n 1 "$PT")" \
  grep -qxF '`scripts/rules/a.md` `docs/adr/top.md` `docs/0001-x.md` `rules/a.md.bak` `xrules/a.md`' "$PT"
check "file name with a space: copied under its exact name and hashed; bare [[with space]] is qualified like the path-qualified one" "$(ls "$K/mirror/rules")" \
  /bin/bash -c '[ -f "$1/mirror/rules/with space.md" ] && grep -qF "rules/with space.md$(printf "\t")" "$1/mirror/.state/hashes.tsv" && grep -qxF "Bare [[rules/with space]] and [[rules/with space]]." "$1/mirror/docs/spaced-ref.md"' _ "$K"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/km-cases-ledger.sh"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/km-cases-links.sh"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/km-cases-kind.sh"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/km-cases-rerun.sh"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/km-cases-refusals.sh"

# v3: generated dated keys, link hygiene, graph export, Mentions (own fixture home; default flags)
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/km-fixtures-v3.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/km-cases-v3-meta.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/km-cases-v3-links.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/km-cases-v3-graph.sh"

summary
