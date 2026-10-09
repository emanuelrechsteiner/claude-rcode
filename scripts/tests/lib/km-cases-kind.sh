#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
# knowledge-mirror-regression cases: kind/origin quoting, inline code, fence length, measured.
# Sourced by scripts/tests/knowledge-mirror-regression.sh (never run on its own); shares its
# helpers and variables (T H K run check ...). Each block uses its own mini home and mirror.

echo "== origin quoting, inline code spans, fence length, source-owned kind: =="
H_KEEP="$H"; K_KEEP="$K"; H="$T/home with space"; K="$T/know-kind"
mkdir -p "$H/.claude/rules"
QN='q"u\o'
printf '# A\n' > "$H/.claude/rules/a.md"
printf '# Spaced\n' > "$H/.claude/rules/with space.md"
printf '# Quoted\n' > "$H/.claude/rules/$QN.md"
printf -- '---\nname: own\nkind: custom\n---\nbody\n' > "$H/.claude/rules/ownkind.md"
printf -- '---\nname: ownorigin\norigin: "mine"\n---\nbody\n' > "$H/.claude/rules/ownorigin.md"
cat > "$H/.claude/rules/code.md" <<'EOF'
# Code
Doc `[[a]]` real [[a]] and ``[[a]]`` and `rules/a.md`.
Unmatched `tick and [[a]] here.
````text
```
inner `rules/a.md` and [[a]]
```
````
after fence `rules/a.md` and [[a]]
```text
x `rules/a.md`
````
tail `rules/a.md`
EOF
run
check "mini home with a space in HOME: exit 0" "rc=$RC err=$ERR" test "$RC" -eq 0
check "origin is a double-quoted scalar (file name with a space, HOME shown as ~)" "$(sed -n 3p "$K/mirror/rules/with space.md")" \
  grep -qxF 'origin: "~/.claude/rules/with space.md"' "$K/mirror/rules/with space.md"
check "origin escapes a double quote and a backslash in the path" "$(sed -n 3p "$K/mirror/rules/$QN.md")" \
  grep -qxF 'origin: "~/.claude/rules/q\"u\\o.md"' "$K/mirror/rules/$QN.md"
check "provenance comment still names the path, directly after the closing ---" "$(head -8 "$K/mirror/rules/with space.md")" \
  /bin/bash -c 'sed -n $((5+GM))p "$1" | grep -qF "copied from ~/.claude/rules/with space.md at"' _ "$K/mirror/rules/with space.md"
CD="$K/mirror/rules/code.md"
check "inline code span: \`[[a]]\` and double-backtick span stay byte-identical, the real [[a]] and the \`rules/a.md\` span are linked" "$(sed -n $((7+GM))p "$CD")" \
  grep -qxF 'Doc `[[a]]` real [[rules/a]] and ``[[a]]`` and [[rules/a]].' "$CD"
check "unmatched backtick is literal text: a bare token after it is still rewritten" "$(sed -n $((8+GM))p "$CD")" \
  grep -qxF 'Unmatched `tick and [[rules/a]] here.' "$CD"
check "4-backtick fence: an inner \`\`\` line does not close it, everything inside stays untouched" "$(sed -n $((9+GM)),$((13+GM))p "$CD")" \
  /bin/bash -c '[ "$(sed -n $((9+GM)),$((13+GM))p "$1")" = "$(printf "%s\n" "\`\`\`\`text" "\`\`\`" "inner \`rules/a.md\` and [[a]]" "\`\`\`" "\`\`\`\`")" ]' _ "$CD"
check "after the 4-backtick fence prose is rewritten again" "$(sed -n $((14+GM))p "$CD")" \
  grep -qxF 'after fence [[rules/a]] and [[rules/a]]' "$CD"
check "a longer closing fence (4) closes a 3-backtick fence: inside untouched, the line after is rewritten" "$(sed -n $((15+GM)),$((18+GM))p "$CD")" \
  /bin/bash -c '[ "$(sed -n $((15+GM)),$((17+GM))p "$1")" = "$(printf "%s\n" "\`\`\`text" "x \`rules/a.md\`" "\`\`\`\`")" ] && [ "$(sed -n $((18+GM))p "$1")" = "tail [[rules/a]]" ]' _ "$CD"
check "LINKS ignores tokens inside inline code (6 links, all resolved, none counted from \`[[a]]\`)" "$OUT" \
  grep -qx 'LINKS total=6 resolved=6 ambiguous=0 dangling=0' <<<"$OUT"
check "V-11 source-owned kind: copy is written, the source key is the ONLY kind: line (no duplicate), origin: is still generated, exit 0" "rc=$RC err=$ERR" \
  /bin/bash -c '[ "$1" = 0 ] && [ "$(grep -c "^kind: " "$2")" = 1 ] && grep -qxF "kind: custom" "$2" && [ "$(grep -c "^origin: " "$2")" = 1 ] && grep -qxF "origin: \"~/.claude/rules/ownkind.md\"" "$2"' _ "$RC" "$K/mirror/rules/ownkind.md"
check "V-11 source-owned origin: the source key is the ONLY origin: line, kind: is still generated" "$(sed -n 1,6p "$K/mirror/rules/ownorigin.md")" \
  /bin/bash -c '[ "$(grep -c "^origin: " "$1")" = 1 ] && grep -qxF "origin: \"mine\"" "$1" && [ "$(grep -c "^kind: " "$1")" = 1 ] && grep -qxF "kind: rule" "$1"' _ "$K/mirror/rules/ownorigin.md"
check "V-11 one warning per colliding copy, each naming its copy and saying the generated key is omitted" "$ERR" \
  /bin/bash -c '[ "$(grep -c "warning: source owns a generated key" <<<"$1")" = 2 ] && grep -F "omitted" <<<"$1" | grep -qF "rules/ownkind.md" && grep -F "omitted" <<<"$1" | grep -qF "rules/ownorigin.md"' _ "$ERR"
check "V-11 no duplicate frontmatter key in this mini mirror" "$(no_dup_keys 2>&1)" no_dup_keys

echo "== ledger: measured, omitted keys =="
H="$T/home-meas"; K="$T/know-meas"; mkdir -p "$H/.claude/global-observation"
cat > "$H/.claude/global-observation/improvement-ledger.json" <<'EOF'
{"lastUpdated": "2026-01-05", "b": {"entries": [
  {"id": "IMP-1", "status": "implemented", "title": "false", "verification": {"measured": false}},
  {"id": "IMP-2", "status": "implemented", "title": "empty string", "verification": {"measured": ""}},
  {"id": "IMP-3", "title": "no verification, no category"},
  {"id": "IMP-4", "status": "implemented", "title": "zero", "verification": {"measured": 0}},
  {"id": "IMP-5", "status": "implemented", "title": "text", "category": "c", "riskLevel": "low", "proposedAt": "2026-01-01", "verification": {"measured": "yes"}},
  {"id": "IMP-6", "status": "implemented", "title": "empty list", "verification": {"measured": []}},
  {"id": "IMP-7", "status": "implemented", "title": "null", "verification": {"measured": null}}]}}
EOF
run
check "ledger-only mirror: exit 0" "rc=$RC err=$ERR" test "$RC" -eq 0
meas() { sed -n '/^---$/,/^---$/p' "$K/mirror/ledger/IMP-$1.md" | grep -x 'measured: .*'; }
for pair in "1:false" "2:false" "3:false" "4:true" "5:true" "6:false" "7:false"; do
  check "measured for IMP-${pair%%:*} is ${pair##*:} (null, false, empty string and empty list are not measured)" "$(meas "${pair%%:*}")" \
    /bin/bash -c '[ "$(sed -n "/^---\$/,/^---\$/p" "$1" | grep -x "measured: .*")" = "measured: $2" ]' _ "$K/mirror/ledger/IMP-${pair%%:*}.md" "${pair##*:}"
done
check "IMP-3: category, riskLevel, proposedAt, implementedAt are omitted when missing (kind, id, status, measured, origin remain)" "$(sed -n 1,9p "$K/mirror/ledger/IMP-3.md")" \
  /bin/bash -c '[ "$(sed -n "2,/^---\$/p" "$1" | tr "\n" "|")" = "kind: imp|id: IMP-3|ledger_status: unknown|measured: false|origin: \"~/.claude/global-observation/improvement-ledger.json\"|---|" ]' _ "$K/mirror/ledger/IMP-3.md"
check "IMP-5: all keys present in the contract order" "$(sed -n 1,11p "$K/mirror/ledger/IMP-5.md")" \
  /bin/bash -c '[ "$(sed -n "2,/^---\$/p" "$1" | tr "\n" "|")" = "kind: imp|id: IMP-5|ledger_status: implemented|category: c|riskLevel: low|measured: true|proposedAt: 2026-01-01|origin: \"~/.claude/global-observation/improvement-ledger.json\"|---|" ]' _ "$K/mirror/ledger/IMP-5.md"
H="$H_KEEP"; K="$K_KEEP"
