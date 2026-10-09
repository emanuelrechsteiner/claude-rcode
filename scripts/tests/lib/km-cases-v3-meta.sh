#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
# knowledge-mirror-regression v3 cases: generated dated / dated_from / origin_session keys, authored keys
# copied through, a source that owns a generated key. Sourced by scripts/tests/knowledge-mirror-regression.sh
# after km-fixtures-v3.sh (never run on its own); shares its helpers and variables (T run v3_run check ...).

echo "== v3 meta: dated / dated_from / origin_session =="
v3_run
check "v3 run: exit 0, TOTAL $EXPECT_V3_TOTAL" "rc=$RC out=$OUT err=$ERR" \
  /bin/bash -c '[ "$1" = 0 ] && grep -qx "TOTAL $2" <<<"$3"' _ "$RC" "$EXPECT_V3_TOTAL" "$OUT"
MV="$K3/mirror/memory/-pa"
dk() { grep -m1 "^$2:" "$1" | sed "s/^$2: //"; } # value of a generated key in a copy
for row in "alpha_note.md|2026-02-01|frontmatter" "beta.md|2026-03-05|body" "gamma.md|2026-04-04|description" \
           "delta.md|2026-01-15|mtime" "epsilon.md|2026-06-06|body" "zeta.md|2026-01-01|frontmatter" \
           "bfonly.md|2026-05-09|body" "bfmt.md|2026-01-20|mtime" "vfwin.md|2026-01-20|frontmatter" "modok.md|2026-03-01|frontmatter"; do
  IFS='|' read -r f d from <<<"$row"
  check "$f: dated $d, dated_from $from (priority frontmatter > body > description > mtime)" "$(sed -n 1,8p "$MV/$f")" \
    /bin/bash -c '[ "$(sed -n 4p "$1")" = "dated: $2" ] && [ "$(sed -n 5p "$1")" = "dated_from: $3" ]' _ "$MV/$f" "$d" "$from"
done
check "generated keys sit right after kind: / origin: (lines 2, 3) in a rule copy too" "$(sed -n 1,6p "$K3/mirror/rules/plain.md")" \
  /bin/bash -c 'sed -n 2p "$1" | grep -qx "kind: rule" && sed -n 4p "$1" | grep -q "^dated: " && sed -n 5p "$1" | grep -qE "^dated_from: (body|mtime)$"' _ "$K3/mirror/rules/plain.md"
check "a copy with no date anywhere falls back to the source mtime (rules/plain.md: dated_from mtime)" "$(sed -n 4,5p "$K3/mirror/rules/plain.md")" \
  grep -qx 'dated_from: mtime' "$K3/mirror/rules/plain.md"
check "every non-ledger copy has exactly one dated: and one dated_from: line (own.md / ownall.md own theirs: checked below)" "a copy lacks dated: or dated_from:, or has it twice" \
  /bin/bash -c 'cd "$1/mirror" && for f in $(find . -name "*.md" ! -path "./ledger/*" ! -name README.md ! -name ledger.md ! -name own.md ! -name ownall.md); do [ "$(grep -c "^dated: " "$f")" = 1 ] && [ "$(grep -c "^dated_from: " "$f")" = 1 ] || { echo "$f"; exit 1; }; done' _ "$K3"
check "ledger notes and the index carry no dated: key (generated notes, not copies)" "$(grep -l '^dated: ' "$K3/mirror/ledger.md" "$K3"/mirror/ledger/*.md 2>&1)" \
  /bin/bash -c '! grep -q "^dated" "$1/mirror/ledger.md" && ! grep -lq "^dated" "$1"/mirror/ledger/*.md' _ "$K3"
check "origin_session present: the transcript exists (it is unreadable, chmod 000: only existence is tested)" "$(grep -n origin_session "$MV/alpha_note.md")" \
  grep -qx 'origin_session: present' "$MV/alpha_note.md"
check "origin_session missing: no transcript with that id" "$(grep -n origin_session "$MV/beta.md")" grep -qx 'origin_session: missing' "$MV/beta.md"
check "V-19 a session id that appears only in the BODY is ignored: no origin_session key (delta.md; its transcript exists)" "$(grep -n origin_session "$MV/delta.md")" \
  /bin/bash -c '! grep -q origin_session "$1"' _ "$MV/delta.md"
check "V-19 the frontmatter key originSessionId wins over an earlier UUID in another key (sidkey.md: missing, not the present one)" "$(grep -n origin_session "$MV/sidkey.md")" \
  grep -qx 'origin_session: missing' "$MV/sidkey.md"
check "V-19 without originSessionId the first UUID in the frontmatter counts, a different one in the body does not (sidfm.md: present)" "$(grep -n origin_session "$MV/sidfm.md")" \
  grep -qx 'origin_session: present' "$MV/sidfm.md"
check "V-03 backfilled alone is not a date: bfonly.md takes the body date, bfmt.md the mtime (never 2026-09-09)" "$(sed -n 4,5p "$MV/bfonly.md" "$MV/bfmt.md")" \
  /bin/bash -c '! grep -q "dated: 2026-09-09" "$1" "$2"' _ "$MV/bfonly.md" "$MV/bfmt.md"
check "V-03 valid_from wins over modified (vfwin.md 2026-01-20, not 2026-03-01); modified: counts when valid_from is absent (modok.md)" "$(sed -n 4,5p "$MV/vfwin.md" "$MV/modok.md")" \
  /bin/bash -c 'grep -qx "dated: 2026-01-20" "$1" && grep -qx "dated: 2026-03-01" "$2"' _ "$MV/vfwin.md" "$MV/modok.md"
check "no session id, no origin_session key (gamma.md, MEMORY.md, rules)" "$(grep -c origin_session "$MV/gamma.md" "$MV/MEMORY.md" "$K3/mirror/rules/plain.md")" \
  /bin/bash -c '! grep -q origin_session "$1" "$2" "$3"' _ "$MV/gamma.md" "$MV/MEMORY.md" "$K3/mirror/rules/plain.md"
check "a transcript is never copied or read into the mirror" "$(grep -rl TRANSCRIPT-SENTINEL "$K3" 2>/dev/null)" \
  /bin/bash -c '! grep -rq TRANSCRIPT-SENTINEL "$1" 2>/dev/null && [ -z "$(find "$1" -name "*.jsonl")" ]' _ "$K3"

echo "== v3 meta: authored keys are copied through, a source-owned generated key is kept =="
check "status / superseded_by / valid_from / backfilled: byte-identical, once, not generated by the script" "$(sed -n 1,14p "$MV/zeta.md")" \
  /bin/bash -c 'for k in "status: superseded" "superseded_by: memory/-pa/alpha_note.md" "valid_from: 2026-01-01" "backfilled: 2026-02-02"; do [ "$(grep -cxF "$k" "$1")" = 1 ] || exit 1; done' _ "$MV/zeta.md"
check "a copy whose source lacks the authored keys does not get them" "$(grep -c -e '^status:' -e '^superseded_by:' "$MV/beta.md")" \
  /bin/bash -c '! grep -qE "^(status|superseded_by|valid_from|backfilled):" "$1"' _ "$MV/beta.md"
check "V-12 source owning dated:: its value is kept, exactly one dated: line, NO generated dated_from" "$(sed -n 1,9p "$MV/own.md")" \
  /bin/bash -c '[ "$(grep -c "^dated: " "$1")" = 1 ] && grep -qx "dated: 2020-01-01" "$1" && [ "$(grep -c "^dated_from: " "$1")" = 0 ]' _ "$MV/own.md"
check "V-11 source owning all five generated keys: each appears once with the SOURCE value, nothing generated, valid YAML" "$(sed -n 1,12p "$MV/ownall.md")" \
  /bin/bash -c 'f=$1; for k in "kind: custom" "origin: mine" "dated: 2020-01-01" "dated_from: manual" "origin_session: x"; do [ "$(grep -cxF "$k" "$f")" = 1 ] || exit 1; done; for k in kind origin dated dated_from origin_session; do [ "$(grep -c "^$k:" "$f")" = 1 ] || exit 1; done' _ "$MV/ownall.md"
check "V-11 source-owned generated key: loud warning naming each copy (own.md, ownall.md), exit 0" "rc=$RC err=$ERR" \
  /bin/bash -c '[ "$1" = 0 ] && grep -qF "source owns a generated key" <<<"$2" && grep -F "source owns" <<<"$2" | grep -qF "memory/-pa/own.md" && grep -F "source owns" <<<"$2" | grep -qF "memory/-pa/ownall.md"' _ "$RC" "$ERR"
nodup3() { local kk=$K rc; K="$K3"; no_dup_keys; rc=$?; K="$kk"; return $rc; }
check "no duplicate frontmatter key anywhere in the v3 mirror" "$(nodup3 2>&1)" nodup3
v3_run
check "v3 rerun: CHANGED 0 (idempotent, mtime-dated copies are stable)" "$OUT" grep -qx 'CHANGED 0' <<<"$OUT"
