#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
# knowledge-mirror-regression cases: ledger notes, hashes.tsv, README counts.
# Sourced by scripts/tests/knowledge-mirror-regression.sh (never run on its own); shares its
# helpers, fixtures and variables (T H C K run check ok bad ...) and its order of cases.

echo "== ledger notes =="
LG="$K/mirror/ledger.md"
for id in $LEDGER_IDS; do
  check "ledger/$id.md exists" "missing" test -f "$K/mirror/ledger/$id.md"
done
check "no ledger note for the non-IMP id or the out-of-scope container" "$(ls "$K/mirror/ledger")" \
  /bin/bash -c '[ ! -e "$1/OTHER-7.md" ] && [ ! -e "$1/IMP-077.md" ] && [ "$(ls "$1" | wc -l | tr -d " ")" = 8 ]' _ "$K/mirror/ledger"
check "nested relatedTo reference does not replace the real IMP-002 (status, title, no stub text)" "$(head -12 "$K/mirror/ledger/IMP-002.md")" \
  /bin/bash -c 'grep -qx "ledger_status: implemented" "$1/ledger/IMP-002.md" && grep -q "^# IMP-002 .* Second" "$1/ledger/IMP-002.md" && ! grep -rq STUB-MUST-NOT-REPLACE "$1" && ! grep -rq OUT-OF-SCOPE-CONTAINER "$1"' _ "$K/mirror"
L1="$K/mirror/ledger/IMP-001.md"; L2="$K/mirror/ledger/IMP-002.md"; L3="$K/mirror/ledger/IMP-003.md"; L9="$K/mirror/ledger/IMP-900.md"
check "duplicate id: last occurrence wins (implemented, 'Dup last', no first-version text)" "$(cat "$L1")" \
  /bin/bash -c 'grep -qx "ledger_status: implemented" "$1" && grep -q "^# IMP-001 .* Dup last" "$1" && ! grep -rq -e "Dup first" -e FIRST-VERSION-MUST-LOSE "$2"' _ "$L1" "$K/mirror"
check "IMP-001 frontmatter: id, category, riskLevel, proposedAt, origin" "$(head -14 "$L1")" \
  /bin/bash -c 'for k in "id: IMP-001" "category: cat-a" "riskLevel: medium" "proposedAt: 2026-01-01" "origin: \"~/.claude/global-observation/improvement-ledger.json\""; do grep -qx "$k" "$1" || exit 1; done' _ "$L1"
check "IMP-001: measured true (verification.measured set)" "$(head -14 "$L1")" grep -qx 'measured: true' "$L1"
check "IMP-001: implementedAt null is omitted" "$(head -14 "$L1")" /bin/bash -c '! grep -q "^implementedAt" "$1"' _ "$L1"
check "IMP-001: Verification lists kpi/baseline/target/measured/measuredAt/note" "$(cat "$L1")" \
  /bin/bash -c 'grep -q "^## Verification" "$1" && for k in kpi-x baseline target measuredAt note-x; do grep -q "$k" "$1" || exit 1; done' _ "$L1"
check "IMP-002: measured false (verification.measured null)" "$(head -14 "$L2")" grep -qx 'measured: false' "$L2"
check "IMP-002: implementedAt present" "$(head -14 "$L2")" grep -qx 'implementedAt: 2026-01-03' "$L2"
check "IMP-002: Notes and Evidence verbatim under their headings" "$(cat "$L2")" \
  /bin/bash -c 'grep -q "^## Notes" "$1" && grep -q "^## Evidence" "$1" && grep -qx "Verbatim note text." "$1" && grep -qx "Verbatim evidence text." "$1"' _ "$L2"
check "IMP-002: Files links the mirrored rule" "$(cat "$L2")" /bin/bash -c 'sed -n "/^## Files/,\$p" "$1" | grep -qF "[[rules/a]]"' _ "$L2"
check "IMP-002: Files links the mirrored ADR from filesCreated" "$(cat "$L2")" /bin/bash -c 'sed -n "/^## Files/,\$p" "$1" | grep -qF "[[adr/0001-x]]"' _ "$L2"
check "IMP-002: Files keeps the non-mirrored path in backticks" "$(cat "$L2")" \
  /bin/bash -c 'sed -n "/^## Files/,\$p" "$1" | grep -qF "\`scripts/other.sh\`" && ! grep -qF "[[scripts" "$1"' _ "$L2"
check "IMP-003: ledger_status unknown, measured false" "$(head -14 "$L3")" \
  /bin/bash -c 'grep -qx "ledger_status: unknown" "$1" && grep -qx "measured: false" "$1"' _ "$L3"
check "V-05: no IMP note has a status: key (that name is the authored curation key), each has exactly one ledger_status:" "$(grep -c '^status:' "$K"/mirror/ledger/*.md | head -3)" \
  /bin/bash -c 'for f in "$1"/ledger/*.md; do [ "$(grep -c "^status:" "$f")" = 0 ] && [ "$(grep -c "^ledger_status:" "$f")" = 1 ] || exit 1; done' _ "$K/mirror"
check "IMP-900 (improvementQueue id) has a note with id/kind" "$(head -14 "$L9")" \
  /bin/bash -c 'grep -qx "id: IMP-900" "$1" && grep -qx "kind: imp" "$1"' _ "$L9"
check "ledger.md index: one link line per id, sorted, with status and title" "$(cat "$LG")" \
  /bin/bash -c '[ "$(grep "^- \[\[ledger/" "$1")" = "$(printf "%s\n" \
"- [[ledger/IMP-001]] · implemented · Dup last" "- [[ledger/IMP-002]] · implemented · Second" \
"- [[ledger/IMP-003]] · unknown · No status entry" "- [[ledger/IMP-004]] · proposed · Holds a reference" \
"- [[ledger/IMP-005]] · proposed · Fix [a] [b](c) ]] stray [[" "- [[ledger/IMP-006]] · proposed · Hostile notes" \
"- [[ledger/IMP-007]] · implemented · Files with trailing notes" "- [[ledger/IMP-900]] · queued · Queue item")" ]' _ "$LG"
L5="$K/mirror/ledger/IMP-005.md"; L6="$K/mirror/ledger/IMP-006.md"
check "bracket title: note heading verbatim, frontmatter intact" "$(head -12 "$L5")" \
  /bin/bash -c 'grep -qxF "# IMP-005 — Fix [a] [b](c) ]] stray [[" "$1" && sed -n 2p "$1" | grep -qx "kind: imp" && [ "$(head -9 "$1" | grep -c "^---$")" = 2 ]' _ "$L5"
check "hostile notes: every original line is kept verbatim (---, ## heading, fence, backtick path)" "$(cat "$L6")" \
  /bin/bash -c 'for l in "first line" "---" "## Fake heading" "unclosed fence \`rules/a.md\`" "plain evidence"; do grep -qxF -- "$l" "$1" || exit 1; done; grep -qx "\`\`\`" "$1"' _ "$L6"
check "hostile notes: the fence they leave open is closed before ## Evidence (even number of fence lines)" "$(cat "$L6")" \
  /bin/bash -c '[ "$(grep -c "^\`\`\`" "$1")" = 2 ] && [ "$(grep -n "^\`\`\`\`\`\`\`\`\`\`$" "$1" | cut -d: -f1)" -lt "$(grep -n "^## Evidence" "$1" | tail -1 | cut -d: -f1)" ]' _ "$L6"
check "hostile notes: the backtick path inside their fence is NOT linked" "$(cat "$L6")" \
  grep -qxF 'unclosed fence `rules/a.md`' "$L6"
check "hostile notes: Files link is outside any fence (real ## Files, [[rules/a]])" "$(cat "$L6")" \
  /bin/bash -c 'sed -n "/^## Files/,\$p" "$1" | grep -qxF -- "- [[rules/a]]"' _ "$L6"
L7="$K/mirror/ledger/IMP-007.md"
EXP_L7='- [[rules/a]]: two valid forms of reference
- [[rules/with space]] (new, always-loaded) more words
- [[adr/0001-x]]: first ADR
- [[docs/CONTEXT]] — glossary
- [[rules/a]]:12
- `scripts/x.sh: not a mirrored path`
- `rules/missing.md: absent target`
- `see rules/a.md`'
check "Files entries with a trailing note: the leading mirrored path is linked, the rest stays text; unmapped entries stay whole in backticks" "$(sed -n '/^## Files/,$p' "$L7")" \
  /bin/bash -c '[ "$(sed -n "/^## Files/,\$p" "$1" | grep "^- ")" = "$2" ]' _ "$L7" "$EXP_L7"
check "ledger note provenance carries no timestamp (idempotent)" "$(grep -h 'knowledge-mirror' "$L1")" \
  /bin/bash -c '! grep -h "knowledge-mirror" "$1" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}T"' _ "$L1"

HT="$K/mirror/.state/hashes.tsv"
check "hashes.tsv has one line per written target ($EXPECT_TOTAL)" "$(cat "$HT" 2>&1)" \
  /bin/bash -c '[ "$(grep -vc "README" "$1")" = "$2" ]' _ "$HT" "$EXPECT_TOTAL"
check "hashes.tsv covers ledger notes" "$(cat "$HT")" grep -q '^ledger/IMP-001.md	' "$HT"
check "hashes.tsv rows are <path><TAB><sha256>" "$(head -2 "$HT" 2>&1)" \
  /bin/bash -c '! grep -vE "^[^	]+	[0-9a-f]{64}$" "$1" | grep -q .' _ "$HT"
check "mirror/README.md exists" "missing" test -f "$K/mirror/README.md"
for pair in "evidence:2" "adr:1" "docs:4" "ledger:8"; do
  check "README lists a '${pair%%:*}' count of ${pair##*:}" "$(cat "$K/mirror/README.md")" \
    grep -qiE "^- *${pair%%:*}[^0-9]*${pair##*:}([^0-9]|$)" "$K/mirror/README.md"
done
check "notes/ exists and is empty" "$(ls -A "$K/notes" 2>&1)" \
  /bin/bash -c '[ -d "$1/notes" ] && [ -z "$(ls -A "$1/notes")" ]' _ "$K"
