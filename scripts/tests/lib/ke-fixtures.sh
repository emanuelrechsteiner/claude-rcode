#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034 # variables are read by lib/ke-cases.sh, sourced into the same shell
# knowledge-eval-regression fixtures: a scratch library (K), a mirror (M) and question-file helpers.
# Sourced by scripts/tests/knowledge-eval-regression.sh (never run on its own). All values invented.

K="$T/know"; M="$K/mirror"; OUT="$T/out"; ERR="$T/err"
mkdir -p "$M/memory/p" "$M/rules" "$M/logbook" "$K/eval"
w() { printf '%s\n' "${@:2}" > "$1"; }   # w <file> <line>...
w "$M/README.md" "# Knowledge mirror" "Last run: 2026-10-09T08:47:44Z (UTC)."
w "$M/memory/p/a1.md" "# A" "alphatok only here"
# betatok: b1 has 3 matching lines, b2 two, b3 one -> ranks 1, 2, 3
w "$M/memory/p/b1.md" "betatok one" "betatok two" "betatok three"
w "$M/memory/p/b2.md" "betatok one" "betatok two"
w "$M/memory/p/b3.md" "betatok one"
w "$M/rules/c1.md" "gammatok in a rule"
# phrase fixture: the contiguous phrase lives in ph1, the loose words in ph2 (2-of-2 keywords if split)
w "$M/logbook/ph1.md" "the zed yarn phrase"
w "$M/logbook/ph2.md" "zed here" "yarn there"
w "$M/rules/d1.md" "deltatok in d1"
w "$M/rules/d2.md" "deltatok in d2"
# hundtok: file hNN has NN matching lines -> h12 is rank 1, h06 rank 7, h02 rank 11 (with --max 12)
mkdir -p "$M/memory/hund"
for n in 01 02 03 04 05 06 07 08 09 10 11 12; do
  : > "$M/memory/hund/h$n.md"; i=0; while [ "$i" -lt $((10#$n)) ]; do echo "hundtok line $i" >> "$M/memory/hund/h$n.md"; i=$((i+1)); done
done

HDR=$(printf 'id\tset\tquery\texpected\tclass\tsource\tconfirmed')
# qrow <id> <set> <query> <expected> <class> <confirmed>
qrow() { printf '%s\t%s\t%s\t%s\t%s\tsyn\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6"; }
# mkq <file> <row>... : header plus the rows
mkq() { local f=$1; shift; { printf '%s\n' "$HDR"; [ $# -eq 0 ] || printf '%s\n' "$@"; } > "$f"; }
# ev <args...>: run the real eval against the scratch library; RC, $OUT, $ERR
ev() { CLAUDE_KNOWLEDGE_DIR="$K" /bin/bash "$EVAL" "$@" >"$OUT" 2>"$ERR" </dev/null; RC=$?; }
has() { grep -qF -- "$1" "$2"; }
hasx() { grep -qxF -- "$1" "$2"; }
evalline() { grep '^EVAL ' "$OUT"; }

# alts fixtures: arow <id> <query> <expected> <alts> builds an 8-column row (set dev, class lookup); the shim lookup drops
# --alt pairs (the real lookup may not know them yet), records every argv (one arg per line,
# calls separated by "--call--") in $T/shim.log, then runs the real lookup on the remaining args.
AHDR=$(printf '%s\talts' "$HDR")
arow() { printf '%s\tdev\t%s\t%s\tlookup\tsyn\tyes\t%s\n' "$1" "$2" "$3" "$4"; }
mkqa() { local f=$1; shift; { printf '%s\n' "$AHDR"; [ $# -eq 0 ] || printf '%s\n' "$@"; } > "$f"; }
SHIM="$T/lk-shim.sh"
{ echo '#!/bin/bash'
  echo 'echo "--call--" >> "$SHIM_LOG"; printf "%s\n" "$@" >> "$SHIM_LOG"'
  echo 'a=(); while [ $# -gt 0 ]; do if [ "$1" = "--alt" ]; then shift 2; else a+=("$1"); shift; fi; done'
  echo "exec /bin/bash \"$LK\" \"\${a[@]}\""; } > "$SHIM"
eva() { SHIM_LOG="$T/shim.log" KNOWLEDGE_EVAL_LOOKUP="$SHIM" ev "$@"; }
