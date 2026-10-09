#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # awk programs in single quotes
# knowledge-lookup-fields.sh - superseded ordering, output formatting and the usage log for
# scripts/knowledge-lookup.sh (sourced by it, never executed). bash 3.2 / BSD awk.
# Rows (tab-separated, from knowledge-lookup-rank.sh): distinct, score, path, bytes, status,
# superseded_by, description, then (line, heading, text) x <= 3.

# kl_supersede (stdin -> stdout): a note with `status: superseded` follows directly after its
# successor (superseded_by) when that note is in the result set, otherwise it follows every
# non-superseded row. Chains keep their order. Pure reordering: no row is added or dropped.
kl_supersede() {
  awk -F '\t' '
    function emit(i,  j) { if (done[i]) return; done[i] = 1; print row[i]; for (j = 1; j <= nc[i]; j++) emit(ch[i, j]) }
    { row[NR] = $0; idx[$3] = NR; isup[NR] = ($5 == "superseded"); s = $6
      sub(/^[ ]*\[\[/, "", s); sub(/\|.*$/, "", s); sub(/\]\].*$/, "", s); sub(/^(\.\/)?(mirror\/)?/, "", s)
      if (s != "" && s !~ /\.md$/) s = s ".md"
      sup[NR] = s }
    END {
      for (i = 1; i <= NR; i++) if (isup[i] && (sup[i] in idx) && idx[sup[i]] != i) {
        p = idx[sup[i]]; nc[p]++; ch[p, nc[p]] = i; hasp[i] = 1 }
      for (i = 1; i <= NR; i++) if (!isup[i]) emit(i)
      for (i = 1; i <= NR; i++) if (isup[i] && !hasp[i]) emit(i)
      for (i = 1; i <= NR; i++) emit(i) # cycles: nothing may be lost
    }'
}

# kl_fuse <best|rrf> <n1 n2 ...> <ranked1.tsv ranked2.tsv ...> (stdout): fuses the per-set rankings.
# best: ascending best rank in any set, then descending RRF sum (1/(60+rank) over the sets a file matches),
# then descending distinct-keyword count of the best set, then path. rrf: RRF sum, distinct count, path.
# Every file keeps the row of its BEST set (best rank; on a tie more distinct keywords; then the earlier
# set), with field 1 rewritten to "k:n:m" = distinct matched : keywords of that set : number of sets
# the file matches (see kl_format).
kl_fuse() {
  local mode=$1 ns=$2 TAB; shift 2; TAB=$(printf '\t')
  awk -F '\t' -v ns="$ns" -v mode="$mode" '
    BEGIN { split(ns, N, " ") }
    FNR == 1 { si++ }
    { p = $3; r = FNR; rrf[p] += 1 / (60 + r); m[p]++
      if (!(p in br) || r < br[p] || (r == br[p] && $1 > bd[p])) {
        br[p] = r; bd[p] = $1; bn[p] = N[si]; rest[p] = substr($0, index($0, "\t") + 1) } }
    END { for (p in rrf) printf "%d\t%.9f\t%d\t%s\t%d:%d:%d\t%s\n", (mode == "best" ? br[p] : 0), rrf[p], bd[p], p, bd[p], bn[p], m[p], rest[p] }' "$@" \
    | LC_ALL=C sort -t "$TAB" -k1,1n -k2,2nr -k3,3nr -k4,4 | cut -f5-
}

# kl_format <keyword count> (stdin -> stdout): header, description line and up to 3 hit lines per file.
# Field 1 is a plain number, or "k:n:m" from kl_fuse (n replaces the keyword count; m > 1 adds sets=<m>).
kl_format() {
  awk -F '\t' -v k="$1" '
    function cut(t, lim,  i, n, len, c) { # lim characters; byte-mode awk: keep every continuation byte
      if (!bytemode) return substr(t, 1, lim)
      t = substr(t, 1, lim * 4); len = length(t); n = 0
      for (i = 1; i <= len; i++) { c = substr(t, i, 1)
        if (!(c in cont)) { if (n == lim) break; n++ } }
      return substr(t, 1, i - 1) }
    BEGIN { bytemode = (length("\303\244") == 2)
            if (bytemode) for (i = 128; i <= 191; i++) cont[sprintf("%c", i)] = 1 }
    function kindof(p,  f) { f = p; sub(/\/.*$/, "", f)
      if (f == "ledger.md") return "index"
      if (f == "rules") return "rule"
      if (f == "plans") return "plan"
      if (f == "docs") return "doc"
      if (f == "ledger") return "imp"
      return f }
    { split($1, e, ":"); kk = (e[2] == "" ? k : e[2])
      printf "== %s  [%d/%d]  (%s)  ~%d tok", $3, e[1], kk, kindof($3), int($4 / 4)
      if (e[3] + 0 > 1) printf "  sets=%d", e[3]
      if ($5 == "superseded") printf "  [superseded → %s]", ($6 == "" ? "(unknown)" : $6)
      printf "\n"
      if ($7 != "") printf "   » %s\n", cut($7, 160)
      for (i = 8; i + 2 <= NF; i += 3) {
        if ($(i + 2) == "" && $(i + 1) != "") printf "   L%d § %s\n", $i, cut($(i + 1), 160) # the hit IS the heading
        else printf "   L%d § %s: %s\n", $i, ($(i + 1) == "" ? "(top)" : cut($(i + 1), 60)), cut($(i + 2), 160) } }'
}

# kl_log <eval dir> <query text> <ranked.tsv>: append "timestamp<TAB>query<TAB>top3" (paths joined by |).
# Auxiliary write: a failure prints one NOTE on stderr and never fails the lookup.
kl_log() {
  local dir=$1 q top ts lf="$1/lookup-log.tsv"
  q=$(printf '%s' "$2" | tr '\t\n\r' '   ')
  while [ "${q% }" != "$q" ]; do q=${q% }; done
  top=$(awk -F '\t' 'NR <= 3 { printf "%s%s", (NR > 1 ? "|" : ""), $3 } END { if (NR == 0) printf "-" }' "$3") \
    && ts=$(date -u +%Y-%m-%dT%H:%M:%SZ) && [ -n "$ts" ] \
    || { echo "NOTE: knowledge-lookup: usage log not written (cannot compute top3 or timestamp)" >&2; return 0; }
  {
    mkdir -p "$dir" \
      && { [ -s "$lf" ] || printf 'timestamp\tquery\ttop3\n' > "$lf"; } \
      && printf '%s\t%s\t%s\n' "$ts" "$q" "$top" >> "$lf"
  } 2>/dev/null || echo "NOTE: knowledge-lookup: usage log not written ($lf)" >&2
  return 0
}
