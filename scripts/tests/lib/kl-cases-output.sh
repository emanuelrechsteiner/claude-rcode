#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016,SC2034 # single quotes are intended: the check bodies expand at run time, not here
# knowledge-lookup-regression cases: kind tags, output format (description, tokens, sections), --help,
# the usage log, and the session-start "Library:" hint. Sourced by scripts/tests/knowledge-lookup-regression.sh
# (never run on its own); shares its helpers and fixtures (lk check has hasx hdr hdrs blocks first excluded ...).

# ---- lookup v2: evidence, adr, docs, ledger notes, kind tags -----------------
mkdir -p "$M/evidence" "$M/adr" "$M/docs" "$M/ledger"
w "$M/evidence/e1.md" "---" "kind: evidence" 'origin: "~/.claude/x.md"' "---" "$PROV" "evidtok in evidence"
w "$M/adr/0001-a.md" "---" "kind: adr" 'origin: "~/.claude/x.md"' "---" "adrtok in adr"
w "$M/docs/CONTEXT.md" "---" "kind: doc" 'origin: "~/.claude/CONTEXT.md"' "---" "doctok in docs"
w "$M/ledger/IMP-001.md" "---" "kind: imp" "id: IMP-001" "status: genfmtok" 'origin: "~/.claude/x.json"' "---" "# IMP-001" "imptok in note" "## Files" "- [[rules/filestok]]"
w "$M/rules/withev.md" "---" "kind: rule" 'origin: "~/.claude/rules/withev.md"' "---" "$PROV" "# W" "body line" "## Evidence" "" "[[evidence/evbodytok]]"
w "$M/ledger/deep.md" "x"; mkdir -p "$M/ledger/sub"; w "$M/ledger/sub/n.md" "subledgertok"
kindof() { grep -m1 "^== $1 " "$OUT" | sed 's/^.*  (\([a-z]*\))  ~.*$/\1/'; }   # header tail is now "(kind)  ~n tok"
lk evidtok;  check "evidence/ hit found, kind evidence" "$(cat "$OUT")" 'test "$(kindof evidence/e1.md)" = evidence'
lk adrtok;   check "adr/ hit found, kind adr" "$(cat "$OUT")" 'test "$(kindof adr/0001-a.md)" = adr'
lk doctok;   check "docs/ hit found, kind doc" "$(cat "$OUT")" 'test "$(kindof docs/CONTEXT.md)" = doc'
lk imptok;   check "ledger/IMP-001.md found, kind imp" "$(cat "$OUT")" 'test "$(kindof ledger/IMP-001.md)" = imp'
lk --kind index ledgertok; check "ledger.md searched with --kind index, kind index" "$(cat "$OUT")" 'test "$(kindof ledger.md)" = index'
lk casemixtok; check "rules/ kind rule" "$(cat "$OUT")" 'test "$(kindof rules/case.md)" = rule'
lk singletok;  check "logbook/ kind logbook" "$(cat "$OUT")" 'test "$(kindof logbook/2026-01-01.md)" = logbook'
lk bodyfmtok;  check "plans/ kind plan" "$(cat "$OUT")" 'test "$(kindof plans/fm-body.md)" = plan'
lk zustand;    check "memory/ kind memory" "$(cat "$OUT")" 'test "$(kindof memory/proj/zs.md)" = memory'
excluded genfmtok "generated v2 frontmatter (status: line) never matches"
lk "kind: imp"; check "generated kind: line never matches" "$(cat "$OUT")" 'has "0 files match" "$OUT"'
lk "origin: "; check "generated origin: line never matches" "$(cat "$OUT")" 'has "0 files match" "$OUT"'
lk evbodytok; check "generated body section (## Evidence link in a rule) is searchable by design" "$(cat "$OUT")" 'hdr "== rules/withev.md  [1/1]  (rule)" && hasx "   L10 § Evidence: [[evidence/evbodytok]]" "$OUT"'
lk filestok; check "generated ledger ## Files section is searchable by design" "$(cat "$OUT")" 'hdr "== ledger/IMP-001.md  [1/1]  (imp)"'
excluded subledgertok "ledger/ is not searched recursively"

# ---- help ----------------------------------------------------------------------
lk --help
check "help documents the kind tags, the index tag, kind:/origin:, the Mentions rule and the log" "$(cat "$OUT")" 'has "ledger.md is tagged \"index\"" "$OUT" && has "(<kind>)" "$OUT" && has "kind:/origin:" "$OUT" && has "## Mentions" "$OUT" && has "lookup-log.tsv" "$OUT"'
HF=1; for f in --max --kind --project --prefix --stack --no-log --help KNOWLEDGE_LOOKUP_LOG; do has "$f" "$OUT" || HF=0; done
check "help lists --max --kind --project --prefix --stack --no-log --help and the log switch" "missing flag" 'test "$HF" -eq 1'
check "help is at most 40 lines" "lines=$(wc -l < "$OUT")" 'test "$(wc -l < "$OUT" | tr -d " ")" -le 40'

# ---- output format: description, tokens, sections --------------------------------
lk outtok
check "header carries ~<n> tok (bytes/4 of the file)" "$(grep '^== ' "$OUT")" 'hasx "== memory/proj/outfmt.md  [1/1]  (memory)  ~$((OUTFMT_BYTES / 4)) tok" "$OUT"'
check "description line follows the header" "$(sed -n 2,3p "$OUT")" 'test "$(sed -n 3p "$OUT")" = "   » Output format note"'
check "hit lines show the nearest heading and the line number" "$(cat "$OUT")" 'hasx "   L9 § Section Alpha: outtok in alpha" "$OUT" && hasx "   L13 § Section Alpha: outtok after the fence" "$OUT"'
check "a '# ...' line inside a fenced block is no heading (but still a hit)" "$(cat "$OUT")" 'hasx "   L11 § Section Alpha: # outtok comment in a fence" "$OUT"'
lk "top heading"
check "a hit that IS a heading is shown as the heading alone" "$(cat "$OUT")" 'hasx "   L6 § Top heading" "$OUT"'
w "$M/memory/proj/longdesc.md" "---" "description: $(rep 'd' 300)" "---" "longdesctok body"
lk longdesctok
check "description is cut to 160 characters" "$(sed -n 3p "$OUT" | wc -c)" 'test "$(sed -n 3p "$OUT")" = "   » $(rep d 160)"'
for n in 1 2 3 4 5 6 7 8 9 10; do w "$M/rules/maxdef$n.md" "# R$n" "maxdeftok $n"; done
lk maxdeftok
check "default --max is 8 (8 blocks, remainder line for the other 2)" "blocks=$(blocks)" 'test "$(blocks)" -eq 8 && hasx "... 2 more files (raise --max)" "$OUT"'
lk --max 10 maxdeftok
check "--max 10 shows all 10" "blocks=$(blocks)" 'test "$(blocks)" -eq 10 && ! has "more files" "$OUT"'

# ---- usage log ---------------------------------------------------------------------
LOGF="$K/eval/lookup-log.tsv"
lkl() { env -u KNOWLEDGE_LOOKUP_LOG HOME="$H" CLAUDE_KNOWLEDGE_DIR="${LKK:-$K}" /bin/bash "$LK" "$@" >"$OUT" 2>"$ERR" </dev/null; RC=$?; }
check "no log file before the first logging run (lk() runs with the log off)" "$(ls "$K/eval" 2>&1)" 'test ! -e "$LOGF"'
lkl pathtok
check "a real run creates <K>/eval/ with the header and one line: timestamp, query, top3 joined by |" "rc=$RC log=$(cat "$LOGF" 2>&1)" 'test "$(sed -n 1p "$LOGF")" = "$(printf "timestamp\tquery\ttop3")" && printf "%s\n" "$(sed -n 2p "$LOGF")" | grep -Eq "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z	pathtok	rules/p-a.md\|rules/p-b.md\|rules/p-c.md$"'
lkl pathtok rankone
check "a second run appends; the query is the keyword list" "$(cat "$LOGF")" 'test "$(wc -l < "$LOGF" | tr -d " ")" -eq 3 && sed -n 3p "$LOGF" | cut -f2 | grep -qx "pathtok rankone"'
lkl nonexistenttoken
check "a zero-hit run is logged with top3 '-'" "$(tail -n 1 "$LOGF")" 'test "$(tail -n 1 "$LOGF" | cut -f3)" = "-"'
N0=$(wc -l < "$LOGF" | tr -d ' ')
lkl --no-log pathtok
check "--no-log writes nothing" "rc=$RC" 'test "$RC" -eq 0 && test "$(wc -l < "$LOGF" | tr -d " ")" -eq "$N0"'
env KNOWLEDGE_LOOKUP_LOG=0 HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K" /bin/bash "$LK" pathtok >"$OUT" 2>"$ERR" </dev/null; RC=$?
check "KNOWLEDGE_LOOKUP_LOG=0 writes nothing" "rc=$RC" 'test "$RC" -eq 0 && test "$(wc -l < "$LOGF" | tr -d " ")" -eq "$N0"'
lkl --help; lkl
check "--help and a usage error write no log line" "rc=$RC" 'test "$(wc -l < "$LOGF" | tr -d " ")" -eq "$N0"'
mkdir -p "$T/know4/mirror/memory" "$T/know5/mirror/memory"; w "$T/know4/mirror/memory/t.md" "logfailtok"; w "$T/know5/mirror/memory/t.md" "logfailtok"
printf 'not a directory\n' > "$T/know4/eval"
LKK="$T/know4" lkl logfailtok
check "a failed log write prints one NOTE on stderr and never fails the lookup" "rc=$RC out=$(cat "$OUT") err=$(cat "$ERR")" 'test "$RC" -eq 0 && has "== memory/t.md" "$OUT" && test "$(grep -c "^NOTE: " "$ERR")" -eq 1'
LKK="$T/know5" lkl logfailtok
check "a missing <K>/eval/ is created together with the header" "rc=$RC" 'test "$RC" -eq 0 && test "$(sed -n 1p "$T/know5/eval/lookup-log.tsv")" = "$(printf "timestamp\tquery\ttop3")" && test ! -s "$ERR"'

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
