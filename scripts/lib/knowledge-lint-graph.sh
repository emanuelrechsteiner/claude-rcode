#!/usr/bin/env bash
# shellcheck shell=bash
# knowledge-lint-graph.sh — canned structural queries over the mirror graph export (plan O8).
# Sourced by scripts/knowledge-lint.sh, never run. Read-only.
# Export format (tab-separated; line 1 of each file is a header row that every reader skips):
#   mirror/graph/nodes.tsv: path kind status dated description   (header starts with "path")
#   mirror/graph/edges.tsv: src dst via   (header starts with "src"; via = wikilink|mdlink|evidence|mentions|same-day)
# kind = memory|rule|evidence|adr|doc|imp|logbook|plan. edges.tsv holds one row per link occurrence
# (duplicates by design), so rows are deduplicated on src,dst,via before counting.

# kl_graph_require <mirror>: both files must exist and be readable; else message + return 1.
kl_graph_require() {
  local f
  for f in nodes.tsv edges.tsv; do
    if [ ! -r "$1/graph/$f" ]; then
      echo "LINT graph export missing at $1/graph/$f — run knowledge-mirror.sh v3 first" >&2
      return 1
    fi
  done
  return 0
}

# Malformed rows (too few columns) are reported on stderr with file:line, never skipped silently.
# A "mentions" row D->S exists only because S links to D, and same-day is derived from dates: neither
# is an inbound link, so they are counted apart (MO) and never lift a node out of the orphan list.
KL_AWK_GRAPH_LOAD='
function bad(file, ln) { print "LINT graph malformed row " file ":" ln > "/dev/stderr" }
BEGIN {
  FS = "\t"; nodes = ENVIRON["KL_NODES"]; edges = ENVIRON["KL_EDGES"]; q = ENVIRON["KL_Q"]
  while ((getline < nodes) > 0) { ln++; if (ln == 1 && $1 == "path") continue
    if (NF < 3) { bad(nodes, ln); nbad++; continue }
    N[++nn] = $1; K[$1] = $2; S[$1] = $3 }
  close(nodes); ln = 0
  while ((getline < edges) > 0) { ln++; if (ln == 1 && $1 == "src") continue
    if (NF < 3) { bad(edges, ln); nbad++; continue }
    ek = $1 SUBSEP $2 SUBSEP $3; if (ek in SEEN) continue; SEEN[ek] = 1
    if ($3 == "mentions" || $3 == "same-day") MO[$2]++
    else IN[$2]++
    if ($3 == "evidence") EV[$1]++ }
  close(edges)
}
'

KL_AWK_ORPHANS='
BEGIN {
  for (i = 1; i <= nn; i++) { p = N[i]; kinds[K[p]] = 1; tot[K[p]]++
    if (IN[p] + 0 == 0) { orph[K[p]]++; cnt[K[p]]++; row[K[p] SUBSEP cnt[K[p]]] = p; if (MO[p] + 0 > 0) mo[K[p]]++ } }
  nk = 0; for (k in kinds) ks[++nk] = k
  for (i = 1; i <= nk; i++) for (j = i + 1; j <= nk; j++) if (ks[j] < ks[i]) { t = ks[i]; ks[i] = ks[j]; ks[j] = t }
  for (i = 1; i <= nk; i++) { k = ks[i]
    for (j = 1; j <= cnt[k]; j++) print "ORPHAN kind=" k " " row[k SUBSEP j]
    printf "ORPHANS kind=%s n=%d of=%d mentions_only=%d\n", k, orph[k], tot[k], mo[k]; all += orph[k]; allt += tot[k] }
  printf "ORPHANS total n=%d of=%d\n", all, allt
}
'

KL_AWK_RULES='
BEGIN {
  for (i = 1; i <= nn; i++) { p = N[i]
    if (p ~ /^rules\/[^\/]+$/) { r++; if (EV[p] == 0) { w++; print "RULE_NO_EVIDENCE " p } } }
  printf "RULES_WITHOUT_EVIDENCE n=%d of=%d\n", w, r
}
'

# kl_graph_run <mirror> <awk-body>: load both TSVs, run the body.
kl_graph_run() {
  KL_NODES=$1/graph/nodes.tsv KL_EDGES=$1/graph/edges.tsv LC_ALL=C awk "$KL_AWK_GRAPH_LOAD$2" < /dev/null
}
kl_graph_orphans() { kl_graph_run "$1" "$KL_AWK_ORPHANS"; }
kl_graph_rules_no_evidence() { kl_graph_run "$1" "$KL_AWK_RULES"; }

# kl_graph_superseded <mirror>: nodes with status superseded; kind imp is skipped (its status is the
# generated ledger status). superseded_by comes from the note's own frontmatter (the export carries
# no such column); an undeclared target is printed as "(none)". An awk failure: LINT error + return 1.
kl_graph_superseded() {
  local m=$1 path by n=0 f list
  list=$(LC_ALL=C awk -F '\t' 'FNR == 1 && $1 == "path" { next }
    NF < 3 { print "LINT graph malformed row " FILENAME ":" FNR > "/dev/stderr"; next }
    $2 != "imp" && $3 == "superseded" { print $1 }' "$m/graph/nodes.tsv" | LC_ALL=C sort) \
    || { echo "LINT error --superseded: reading nodes.tsv failed" >&2; return 1; }
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    f=$m/$path; [ -f "$f" ] || f=$m/$path.md
    if [ -r "$f" ]; then
      by=$(awk '/^---[ \t]*$/ { st++; next } st == 1 && /^superseded_by:/ { v = $0; sub(/^superseded_by:[ \t]*/, "", v); gsub(/["\047]/, "", v); print v; exit } st >= 2 { exit }' "$f") \
        || { echo "LINT error --superseded: reading $path failed" >&2; return 1; }
    else
      by="(note unreadable)"
    fi
    echo "SUPERSEDED $path -> ${by:-(none)}"; n=$((n + 1))
  done <<LIST
$list
LIST
  echo "SUPERSEDED n=$n"
}
