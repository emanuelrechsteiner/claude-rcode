#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
# knowledge-mirror-regression cases: IMP-<digits> text -> [[ledger/IMP-<digits>|IMP-<digits>]].
# Sourced by scripts/tests/lib/km-cases-links.sh (never run on its own); shares its helpers and
# variables (T H K run check ...). One mini home and mirror; ledger notes IMP-5 and IMP-211 exist.

echo "== IMP ids -> ledger wikilinks =="
H_KEEP="$H"; K_KEEP="$K"; H="$T/home-imp"; K="$T/know-imp"
mkdir -p "$H/.claude/logbook" "$H/.claude/rules" "$H/.claude/global-observation"
cat > "$H/.claude/global-observation/improvement-ledger.json" <<'EOF2'
{"lastUpdated": "2026-01-05", "b": {"entries": [
  {"id": "IMP-5", "status": "implemented", "title": "Follows IMP-211", "notes": "Refers to IMP-211 and IMP-5 itself."},
  {"id": "IMP-211", "status": "implemented", "title": "Base", "notes": "Own IMP-211, next IMP-5, ghost IMP-999."}]}}
EOF2
cat > "$H/.claude/logbook/2026-02-01.md" <<'EOF2'
# Day
Plain IMP-211 and IMP-999 and IMP-211b and XIMP-1 and IMP- and IMP-211-x end.
Range IMP-211/IMP-5 and IMP-211..213, (IMP-5).
Code `IMP-211` and ``IMP-5`` end IMP-5.
```text
fenced IMP-211
```
Linked [[ledger/IMP-211|IMP-211]] and [md](ledger/IMP-5.md) and [IMP-5](x.md) and https://x.org/IMP-5 then IMP-5.
EOF2
printf -- '---\nrelated: IMP-5\n---\nBody IMP-5.\n' > "$H/.claude/rules/fm.md"
run
LG="$K/mirror/logbook/2026-02-01.md"; N211="$K/mirror/ledger/IMP-211.md"; N5="$K/mirror/ledger/IMP-5.md"
l5() { printf '[[ledger/IMP-5|IMP-5]]'; }; l211() { printf '[[ledger/IMP-211|IMP-211]]'; }
check "IMP run: exit 0" "rc=$RC err=$ERR" test "$RC" -eq 0
check "existing id linked with alias; unknown id, IMP-211b, XIMP-1, IMP-, IMP-211-x untouched" "$(cat "$LG")" \
  grep -qxF "Plain $(l211) and IMP-999 and IMP-211b and XIMP-1 and IMP- and IMP-211-x end." "$LG"
check "ranges: each full id linked, separators and the bare 213 untouched" "$(cat "$LG")" \
  grep -qxF "Range $(l211)/$(l5) and $(l211)..213, ($(l5))." "$LG"
check "inline code spans untouched, plain id after them linked" "$(cat "$LG")" \
  grep -qxF "Code \`IMP-211\` and \`\`IMP-5\`\` end $(l5)." "$LG"
check "fenced block untouched" "$(cat "$LG")" grep -qxF 'fenced IMP-211' "$LG"
check "already linked / markdown link text / link target / URL untouched, plain id linked" "$(cat "$LG")" \
  grep -qxF "Linked $(l211) and [md](ledger/IMP-5.md) and [IMP-5](x.md) and https://x.org/IMP-5 then $(l5)." "$LG"
check "frontmatter untouched, body linked" "$(cat "$K/mirror/rules/fm.md")" \
  /bin/bash -c 'grep -qxF "related: IMP-5" "$1" && grep -qxF "Body $2." "$1"' _ "$K/mirror/rules/fm.md" "$(l5)"
check "ledger note IMP-211: own id never self-linked, other ids linked, unknown untouched" "$(cat "$N211")" \
  grep -qxF "Own IMP-211, next $(l5), ghost IMP-999." "$N211"
check "ledger note IMP-5: heading untouched, own id in body not linked, IMP-211 linked" "$(cat "$N5")" \
  /bin/bash -c 'grep -qxF "# IMP-5 — Follows IMP-211" "$1" && grep -qxF "Refers to $2 and IMP-5 itself." "$1"' _ "$N5" "$(l211)"
check "LINKS counts the alias links as resolved, none dangling" "$OUT" \
  /bin/bash -c 'grep -qE "^LINKS total=[0-9]+ resolved=[0-9]+ ambiguous=0 dangling=0$" <<<"$1"' _ "$OUT"
run
check "second run: CHANGED 0 (idempotent)" "$OUT" grep -qx 'CHANGED 0' <<<"$OUT"
run --check-links
check "--check-links: 13 links, all resolved" "$OUT" grep -qx 'LINKS total=13 resolved=13 ambiguous=0 dangling=0' <<<"$OUT"
H="$H_KEEP"; K="$K_KEEP"
