#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016,SC2034 # awk programs in single quotes; RANK/TTA/TOP3/TTAMISS/QARGS/SETS are read by the caller
# knowledge-eval-score.sh - helpers for scripts/knowledge-eval.sh (sourced by it, never executed):
# question-file parsing, query splitting, per-row scoring, aggregate statistics.
# bash 3.2 / BSD awk compatible. Callers set LK, KDIR, MIRROR, MAXN, WORK before scoring.

ke_die() { echo "knowledge-eval: $1" >&2; exit "${2:-1}"; }

# ke_read_questions <file> <set|all>: validate the whole file, print the selected rows as
# id US set US query US expected US class US confirmed US alts (US = \037; alts is empty when
# the file has no alts column). Columns are found by header name; unknown extra columns are ignored. Any malformed row aborts with exit 2.
ke_read_questions() {
  awk -F '\t' -v want="$2" -v file="$1" '
    function err(m) { printf "knowledge-eval: %s:%d: %s\n", file, NR, m > "/dev/stderr"; bad = 1; exit 2 }
    { sub(/\r$/, "") }
    NR == 1 {
      for (i = 1; i <= NF; i++) col[$i] = i
      n = split("id set query expected class source confirmed", need, " ")
      for (j = 1; j <= n; j++) if (!(need[j] in col)) err("header lacks column \"" need[j] "\"")
      hn = NF; next }
    $0 == "" { next }
    {
      if (NF != hn) err("row has " NF " fields, header has " hn)
      id = $col["id"]; st = $col["set"]; q = $col["query"]; ex = $col["expected"]
      cl = $col["class"]; cf = $col["confirmed"]
      al = ("alts" in col) ? $col["alts"] : ""
      if (id == "") err("empty id")
      if (id in seen) err("duplicate id " id)
      seen[id] = 1
      if (st != "dev" && st != "test") err(id ": set must be dev|test, got \"" st "\"")
      if (q == "" || q ~ /^[ \t]+$/) err(id ": empty query")
      if (ex == "") err(id ": empty expected (use - for none)")
      if (cl !~ /^(lookup|paraphrase|crosslang|supersession|structural)$/) err(id ": bad class \"" cl "\"")
      if (cf != "yes" && cf != "no") err(id ": confirmed must be yes|no, got \"" cf "\"")
      if (want == "all" || want == st) printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\n", id, st, q, ex, cl, cf, al
    }' "$1"
}

# ke_split_query <query>: split like the shell would for the lookup CLI (single or double
# quotes keep a phrase together). Fills QARGS; returns 1 on an unterminated quote.
ke_split_query() {
  QARGS=()
  local s=$1 n=${#1} i=0 c cur="" q="" have=0
  while [ "$i" -lt "$n" ]; do
    c=${s:$i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=""; else cur="$cur$c"; fi
    else
      case "$c" in
        '"'|"'") q=$c; have=1 ;;
        ' '|$'\t') if [ "$have" -eq 1 ]; then QARGS+=("$cur"); cur=""; have=0; fi ;;
        *) cur="$cur$c"; have=1 ;;
      esac
    fi
    i=$((i + 1))
  done
  [ -z "$q" ] || return 1
  if [ "$have" -eq 1 ]; then QARGS+=("$cur"); fi
  return 0
}

# ke_score_row <id> <query> <expected> [alts]: run the real lookup, set RANK (0 = absent), TTA,
# TOP3 and SETS (number of alt sets, 1 without alts). alts = "|"-separated keyword sets, each
# passed verbatim as one --alt argument before "--" (the query stays the primary keywords).
ke_score_row() {
  local id=$1 rc=0 out="$WORK/lk.out" p i f total=0 found=0 alt s al=${4:-}
  local -a altargs=() sets=()
  SETS=1
  if [ -n "$al" ]; then
    case "$al" in '|'*|*'|'|*'||'*) ke_die "$id: alts has an empty set" 2 ;; esac
    IFS='|' read -r -a sets <<< "$al"
    for s in "${sets[@]}"; do
      [ -n "${s//[[:space:]]/}" ] || ke_die "$id: alts has an empty set" 2
      altargs+=(--alt "$s")
    done
    SETS=${#sets[@]}
  fi
  ke_split_query "$2" || ke_die "$id: unterminated quote in query" 2
  [ "${#QARGS[@]}" -gt 0 ] || ke_die "$id: query has no keywords" 2
  CLAUDE_KNOWLEDGE_DIR="$KDIR" /bin/bash "$LK" --max "$MAXN" ${altargs[@]+"${altargs[@]}"} -- "${QARGS[@]}" >"$out" 2>"$WORK/lk.err" </dev/null || rc=$?
  if [ "$rc" -ne 0 ]; then
    cat "$WORK/lk.err" >&2
    ke_die "$id: knowledge-lookup failed (exit $rc)" 1
  fi
  local -a paths=() alts=()
  while IFS= read -r p; do paths+=("$p"); done < <(grep '^== ' "$out" | sed 's/^== //; s/  \[.*$//')
  IFS='|' read -r -a alts <<< "$3"
  RANK=0; i=0
  while [ "$i" -lt "${#paths[@]}" ]; do
    for alt in "${alts[@]}"; do
      if [ "${paths[$i]}" = "$alt" ] && [ "$RANK" -eq 0 ]; then RANK=$((i + 1)); fi
    done
    i=$((i + 1))
  done
  TOP3=""; i=0
  while [ "$i" -lt 3 ] && [ "$i" -lt "${#paths[@]}" ]; do TOP3="$TOP3${TOP3:+,}${paths[$i]}"; i=$((i + 1)); done
  [ -n "$TOP3" ] || TOP3="-"
  total=$(wc -c < "$out" | tr -d ' '); i=0
  while [ "$i" -lt "${#paths[@]}" ] && [ "$i" -lt 5 ]; do
    f="$MIRROR/${paths[$i]}"
    [ -f "$f" ] || ke_die "$id: lookup listed a file that is not in the mirror: ${paths[$i]}" 1
    total=$((total + $(wc -c < "$f" | tr -d ' ')))
    i=$((i + 1))
    if [ "$RANK" -eq "$i" ]; then found=1; break; fi
  done
  TTA=$((total / 4))
  TTAMISS=$((1 - found))
}

# ke_stats <rows.tsv>: rows are "id rank tta" (rank 0 = absent); prints
# "hit1 hit3 hit10 mrr10 median p90". Median/p90 use nearest rank: element ceil(p*n) of the sorted tta.
ke_stats() {
  awk -F '\t' '
    { n++; r = $2 + 0; t[n] = $3 + 0
      if (r == 1) h1++
      if (r >= 1 && r <= 3) h3++
      if (r >= 1 && r <= 10) h10++
      if (r >= 1 && r <= 10) rr += 1 / r }
    function nr(p,  k) { k = p * n; if (k > int(k)) k = int(k) + 1; return (k < 1) ? 1 : k }
    END {
      for (i = 2; i <= n; i++) { v = t[i]; j = i - 1; while (j >= 1 && t[j] > v) { t[j + 1] = t[j]; j-- } t[j + 1] = v }
      printf "%d %d %d %.3f %d %d\n", h1, h3, h10, rr / n, t[nr(0.5)], t[nr(0.9)] }' "$1"
}
