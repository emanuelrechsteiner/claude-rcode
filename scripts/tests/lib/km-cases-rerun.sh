#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
# knowledge-mirror-regression cases: idempotence, runtime, ledger id safety.
# Sourced by scripts/tests/knowledge-mirror-regression.sh (never run on its own); shares its
# helpers, fixtures and variables (T H C K run check ok bad ...) and its order of cases.

echo "== idempotence and notes safety =="
printf 'mine\n' > "$K/notes/keep.md"
run
check "second run exits 0" "rc=$RC err=$ERR" test "$RC" -eq 0
check "second run prints CHANGED 0" "$OUT" grep -qx 'CHANGED 0' <<<"$OUT"
check "notes/keep.md survives rerun" "gone" test -f "$K/notes/keep.md"
check "second run still prints the same LINKS line" "$OUT" grep -qx "LINKS total=$EXP_LINKS" <<<"$OUT"

echo "== runtime of a real run on the fixture =="
K_KEEP="$K"; K="$T/know-timing"
S0=$(date +%s); run; S1=$(date +%s)
check "fresh real run exits 0" "rc=$RC err=$ERR" test "$RC" -eq 0
check "fresh real run takes < 5 s ($((S1-S0)) s)" "$((S1-S0)) s" test "$((S1-S0))" -lt 5
K="$K_KEEP"

echo "== runtime: ~600 targets under 15 s (contract) =="
command -v perl >/dev/null 2>&1 || { bad "perl available for timing" "perl missing"; summary; }
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
H_KEEP="$H"; K_KEEP="$K"; H="$T/home600"; K="$T/know600"; C6="$H/.claude"
mkdir -p "$C6/rules" "$C6/logbook" "$C6/docs/adr" "$C6/docs/archive/rules-evidence" "$C6/projects/-p/memory" "$C6/global-observation"
cp "$C/global-observation/improvement-ledger.json" "$C6/global-observation/"
i=0
while [ "$i" -lt 600 ]; do
  case $((i % 5)) in 0) f=rules/r$i.md ;; 1) f=docs/adr/a$i.md ;; 2) f=docs/archive/rules-evidence/e$i.md ;; 3) f=logbook/l$i.md ;; *) f=projects/-p/memory/m$i.md ;; esac
  printf -- '---\nname: n%s\n---\n# T %s\nsee `rules/r0.md` and [[r5]] and `docs/adr/a1.md`\n' "$i" "$i" > "$C6/$f"
  i=$((i+1))
done
T0="$(now)"; run; T1="$(now)"; EL="$(perl -e "printf '%.1f', $T1 - $T0")"
check "600 sources + $((NIDS + 1)) ledger targets: exit 0, TOTAL $((600 + NIDS + 1)), CHANGED the same" "rc=$RC out=$OUT err=$ERR" \
  /bin/bash -c '[ "$1" = 0 ] && grep -qx "TOTAL $2" <<<"$3" && grep -qx "CHANGED $2" <<<"$3"' _ "$RC" "$((600 + NIDS + 1))" "$OUT"
check "fresh real run on ~600 targets takes < 15 s (took ${EL}s)" "took ${EL}s" perl -e "exit(($EL < 15.0) ? 0 : 1)"
T0="$(now)"; run; T1="$(now)"; EL="$(perl -e "printf '%.1f', $T1 - $T0")"
check "unchanged rerun on ~600 targets: CHANGED 0 and < 15 s (took ${EL}s)" "rc=$RC took ${EL}s" \
  /bin/bash -c '[ "$1" = 0 ] && grep -qx "CHANGED 0" <<<"$2" && perl -e "exit(($3 < 15.0) ? 0 : 1)"' _ "$RC" "$OUT" "$EL"
H="$H_KEEP"; K="$K_KEEP"

echo "== ledger id safety =="
H_KEEP="$H"; K_KEEP="$K"; H="$T/home-bad"; K="$T/know-bad"; mkdir -p "$H/.claude/global-observation"
printf '{"batch": {"entries": [{"id": "IMP-1 bad", "title": "x"}]}}\n' > "$H/.claude/global-observation/improvement-ledger.json"
run
check "unsafe ledger id aborts loudly: exit 1, 'unsafe ledger id' on stderr, nothing written" "rc=$RC err=$ERR" \
  /bin/bash -c '[ "$1" = 1 ] && grep -q "unsafe ledger id" <<<"$2" && [ ! -e "$3" ]' _ "$RC" "$ERR" "$K"
H="$H_KEEP"; K="$K_KEEP"
