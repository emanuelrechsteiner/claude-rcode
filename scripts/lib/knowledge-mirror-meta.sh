#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # awk programs live in single-quoted strings on purpose
# knowledge-mirror-meta.sh - generated freshness keys for scripts/knowledge-mirror.sh (v3).
# Sourced by knowledge-mirror-links.sh, never executed. For every source copy it computes
#   dated:          an ISO date (YYYY-MM-DD), in this priority: the frontmatter key valid_from; any other
#                   frontmatter value except description, backfilled, dated, dated_from, origin_session, kind,
#                   origin and originSessionId (modified: counts); the body text; the description value; else
#                   the source mtime (UTC date)
#   dated_from:     frontmatter | body | description | mtime
#   origin_session: present | missing, for memory notes that carry a session id: the frontmatter key
#                   originSessionId, else the first UUID anywhere in the frontmatter, never one in the body.
#                   present when ~/.claude/projects/*/<id>.jsonl exists. Existence only ([ -e ]); a transcript
#                   is never opened or read.
# Also here: km_stage / km_one (render once into a stage dir, Mentions from its edges), km_graph_export.
# The keys are written into the COPY only (km_render inserts them after kind:/origin:). A source that
# already owns one of the generated keys keeps its own: the render omits the generated one (see km_meta).
# This text lives in a shell single-quoted string: awk code and comments must never contain a single quote.
KM_AWK_META='
function km_rep(s, n,    r) { r = ""; while (n-- > 0) r = r s; return r }
function km_isodate(s,    off, t, p, d, c0, c1, y, mo, da) {
  off = 0; t = s
  while (match(t, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) {
    p = off + RSTART; d = substr(s, p, 10)
    c0 = (p > 1) ? substr(s, p - 1, 1) : ""; c1 = substr(s, p + 10, 1)
    y = substr(d, 1, 4) + 0; mo = substr(d, 6, 2) + 0; da = substr(d, 9, 2) + 0
    if (c0 !~ /^[0-9]$/ && c1 !~ /^[0-9]$/ && y >= 2000 && y <= 2099 && mo >= 1 && mo <= 12 && da >= 1 && da <= 31) return d
    off = p; t = substr(s, p + 1)
  }
  return ""
}
function km_uuid(s,    re, off, t, p, c0, c1) {
  re = km_rep("[0-9a-fA-F]", 8) "-" km_rep("[0-9a-fA-F]", 4) "-" km_rep("[0-9a-fA-F]", 4) "-" km_rep("[0-9a-fA-F]", 4) "-" km_rep("[0-9a-fA-F]", 12)
  off = 0; t = s
  while (match(t, re)) {
    p = off + RSTART; c0 = (p > 1) ? substr(s, p - 1, 1) : ""; c1 = substr(s, p + 36, 1)
    if (c0 !~ /^[0-9A-Za-z]$/ && c1 !~ /^[0-9A-Za-z]$/) return substr(s, p, 36)
    off = p; t = substr(s, p + 1)
  }
  return ""
}
function km_okey(k) { # frontmatter keys that never date a note: generated, backfill and harness bookkeeping
  return (k == "backfilled" || k == "dated" || k == "dated_from" || k == "origin_session" || k == "kind" || k == "origin" || k == "originSessionId")
}
function km_meta_file(rel, src, kind,    n, i, x, close_at, key, v, vf, fmd, bd, dsc, indesc, skip, osid, fsid, sid, d, from) {
  n = 0; while ((getline x < src) > 0) { sub(/\r$/, "", x); L[++n] = x }
  close(src)
  close_at = 0
  if (n >= 1 && L[1] == "---") for (i = 2; i <= n; i++) if (L[i] == "---") { close_at = i; break }
  vf = ""; fmd = ""; bd = ""; dsc = ""; indesc = 0; skip = 0; osid = ""; fsid = ""
  for (i = 2; close_at && i < close_at; i++) {
    x = L[i]; key = ""
    if (x ~ /^[A-Za-z_][A-Za-z0-9_-]*[ \t]*:/) { indesc = (L[i] ~ /^description[ \t]*:/); key = x }
    else if (!indesc && x ~ /^[ \t]+[A-Za-z_][A-Za-z0-9_-]*[ \t]*:/) { key = x; sub(/^[ \t]+/, "", key) } # nested key
    if (key != "") {
      v = key; sub(/^[^:]*:/, "", v); sub(/[ \t]*:.*$/, "", key); skip = km_okey(key) || key == "valid_from"
      if (key == "description") dsc = v
      else if (key == "valid_from") { if (vf == "") vf = km_isodate(v) }
      else if (!skip && fmd == "") fmd = km_isodate(v)
      if (key == "originSessionId" && osid == "") osid = km_uuid(v)
    } else if (indesc) dsc = dsc " " x
    else if (!skip && fmd == "") fmd = km_isodate(x)
    if (fsid == "") fsid = km_uuid(x)
  }
  for (i = close_at + 1; i <= n && bd == ""; i++) bd = km_isodate(L[i])
  sid = (osid != "") ? osid : fsid
  if (vf != "") { d = vf; from = "frontmatter" }
  else if (fmd != "") { d = fmd; from = "frontmatter" }
  else if (bd != "") { d = bd; from = "body" }
  else if (km_isodate(dsc) != "") { d = km_isodate(dsc); from = "description" }
  else { d = MT[src]; from = "mtime"; if (d == "") { print "knowledge-mirror: no mtime for " src > "/dev/stderr"; bad = 1 } }
  print rel "\tdated: " d "\tdated_from: " from
  if (kind == "memory" && sid != "") print rel "\t" sid > ENVIRON["KM_METASID"]
}
BEGIN {
  while ((getline ln < ENVIRON["KM_METAMT"]) > 0) { i = index(ln, "\t"); MT[substr(ln, 1, i - 1)] = substr(ln, i + 1) }
  while ((getline ln < ENVIRON["KM_METAIN"]) > 0) { split(ln, f, "\t"); km_meta_file(f[1], f[2], f[3]) }
  exit bad
}
'

# km_meta_build <plan.tsv> <scratch-dir> <claude-src-dir>: writes <scratch>/meta.tsv ("<rel>\t<key: value>...")
# and exports KM_METAMAP for km_render, which drops the keys a source owns.
km_meta_build() {
  local w=$2 rel sid f present
  awk -F "$TAB" '$3 == "copy" { print $1 "\t" $2 "\t" $4 }' "$1" > "$w/meta-in.tsv"
  cut -f 2 "$w/meta-in.tsv" | tr '\n' '\0' | TZ=UTC xargs -0 -r stat -f '%N%t%Sm' -t '%Y-%m-%d' > "$w/meta-mt.tsv" \
    || err "could not read the modification times of the source files"
  : > "$w/meta-sid.tsv"
  KM_METAIN=$w/meta-in.tsv KM_METAMT=$w/meta-mt.tsv KM_METASID=$w/meta-sid.tsv LC_ALL=C \
    awk "$KM_AWK_META" < /dev/null > "$w/meta-keys.tsv" || err "could not compute the generated dated keys"
  : > "$w/meta-os.tsv"
  while IFS="$TAB" read -r rel sid; do # existence check only, never a read
    present=missing
    for f in "$3"/projects/*/"$sid".jsonl; do
      if [ -e "$f" ]; then present=present; break; fi
    done
    printf '%s\torigin_session: %s\n' "$rel" "$present" >> "$w/meta-os.tsv"
  done < "$w/meta-sid.tsv"
  awk -F "$TAB" 'FILENAME == ARGV[1] { os[$1] = $2; next } { print $0 (($1 in os) ? "\t" os[$1] : "") }' "$w/meta-os.tsv" "$w/meta-keys.tsv" > "$w/meta.tsv"
  export KM_METAMAP=$w/meta.tsv
}

# km_graph_export <mirror> <scratch-dir>: graph/nodes.tsv and graph/edges.tsv (header + sorted rows),
# written last and outside the hash, stale and CHANGED logic (TSV, like README.md).
km_graph_export() {
  local g=$1/graph
  [ -f "$2/chk.nodes" ] && [ -f "$2/chk.edges" ] || err "graph export: no link scan result (internal error)"
  [ ! -L "$g" ] || err "refuse: symlink inside mirror/: $g"
  mkdir -p "$g"
  [ ! -L "$g/nodes.tsv" ] && [ ! -L "$g/edges.tsv" ] || err "refuse: symlink inside mirror/: $g"
  { printf 'path\tkind\tstatus\tdated\tdescription\n'; LC_ALL=C sort "$2/chk.nodes" | cut -f 1-5; } > "$g/nodes.tsv.tmp" || err "could not write the graph export: $g/nodes.tsv.tmp"
  mv "$g/nodes.tsv.tmp" "$g/nodes.tsv" || err "could not replace the graph export: $g/nodes.tsv"
  { printf 'src\tdst\tvia\n'; LC_ALL=C sort "$2/chk.edges"; } > "$g/edges.tsv.tmp" || err "could not write the graph export: $g/edges.tsv.tmp"
  mv "$g/edges.tsv.tmp" "$g/edges.tsv" || err "could not replace the graph export: $g/edges.tsv"
}

# ---- Mentions: for each IMP, rule, ADR, evidence, doc and memory copy up to 10 notes that link to it ----
# Order memory > rule > adr > logbook > plan, then evidence, doc, imp (the ledger.md index never
# mentions); newest dated first inside a kind, then the later path first. IMP copies also list the logbook day of
# implementedAt / proposedAt (same-day); such a day is not repeated among the mentioners.
KM_AWK_MENT='
function km_rank(k) { return (k == "memory") ? 1 : (k == "rule") ? 2 : (k == "adr") ? 3 : (k == "logbook") ? 4 : (k == "plan") ? 5 : (k == "evidence") ? 6 : (k == "doc") ? 7 : 8 }
function km_before(a, b,    ra, rb) {
  ra = km_rank(KD[a]); rb = km_rank(KD[b])
  if (ra != rb) return ra < rb
  if (DT[a] != DT[b]) return DT[a] > DT[b]
  return a > b # equal dates: the later path first (logbook days, meta-proposals, ADR numbers sort chronologically)
}
function km_day(v) { return (v ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) ? substr(v, 1, 10) : "" }
BEGIN {
  nf = ENVIRON["KM_NODES"]; ef = ENVIRON["KM_EDGES"]; od = ENVIRON["KM_MENT"]
  while ((getline ln < nf) > 0) { split(ln, f, "\t"); p = f[1]; KD[p] = f[2]; DT[p] = f[4]; IA[p] = km_day(f[6]); IP[p] = km_day(f[7]); NODE[p] = 1 }
  while ((getline ln < ef) > 0) {
    split(ln, f, "\t"); s = f[1]; d = f[2]
    if (f[3] == "mentions" || f[3] == "same-day" || s == d || s == "ledger.md" || s ~ /[|#\[\]]/) continue
    if ((s SUBSEP d) in SEEN) continue
    SEEN[s SUBSEP d] = 1; NC[d]++; C[d, NC[d]] = s
  }
  for (d in NODE) {
    k = KD[d]
    if (d == "ledger.md" || d == "README.md" || !(k == "imp" || k == "rule" || k == "adr" || k == "evidence" || k == "doc" || k == "memory")) continue
    sd = ""; delete SD
    if (k == "imp") {
      if (IA[d] != "" && ("logbook/" IA[d] ".md") in NODE) { SD[IA[d]] = 1; sd = sd "- [[logbook/" IA[d] "]] (same-day)\n" }
      if (IP[d] != "" && IP[d] != IA[d] && ("logbook/" IP[d] ".md") in NODE) { SD[IP[d]] = 1; sd = sd "- [[logbook/" IP[d] "]] (same-day)\n" }
    }
    m = 0
    for (i = 1; i <= NC[d]; i++) { s = C[d, i]; if (s ~ /^logbook\// && length(s) == 21 && (substr(s, 9, 10) in SD)) continue; X[++m] = s }
    if (m == 0 && sd == "") continue
    for (i = 2; i <= m; i++) { v = X[i]; j = i - 1; while (j > 0 && km_before(v, X[j])) { X[j + 1] = X[j]; j-- } X[j + 1] = v }
    out = "\n## Mentions\n\n" sd
    for (i = 1; i <= m && i <= 10; i++) out = out "- [[" substr(X[i], 1, length(X[i]) - 3) "]]\n"
    if (m > 10) out = out "and " (m - 10) " more\n"
    fn = d; gsub(/\//, "%", fn); fn = od "/" fn; printf "%s", out > fn; close(fn)
  }
}
'

# km_stage <plan.tsv> <scratch-dir>: render every copy once into <scratch>/stage (exports KM_STAGE and
# KM_MENT), then, unless KM_V3L=0, scan the stage and write the Mentions blocks to <scratch>/mentions.
# Needs MIRROR, TAB and the exports of the caller (KM_TARGETS, KM_TSMAP, KM_NOW, KM_HOME, ...).
km_stage() {
  local rel src mode kind fnow
  KM_STAGE=$2/stage; KM_MENT=$2/mentions; export KM_STAGE KM_MENT
  mkdir -p "$KM_STAGE" "$KM_MENT"
  while IFS="$TAB" read -r rel src mode kind; do
    fnow=0; if [ ! -f "$MIRROR/$rel" ]; then fnow=1; fi
    case "$rel" in */*) [ -d "$KM_STAGE/${rel%/*}" ] || mkdir -p "$KM_STAGE/${rel%/*}" ;; esac
    case "$mode" in
      ledger) cp "$2/ledger.md" "$KM_STAGE/$rel" ;;
      lnote) km_render "$rel" "$2/$rel" "$kind" 0 0 > "$KM_STAGE/$rel" ;;
      *) km_render "$rel" "$src" "$kind" 1 "$fnow" > "$KM_STAGE/$rel" ;;
    esac
  done < "$1"
  [ "${KM_V3L:-1}" != 0 ] || return 0
  cut -f 1 "$1" | LC_ALL=C sort > "$2/stage.list"
  km_scan "$KM_STAGE" "$2/stage.list" "$2/stg" 0 > /dev/null
  KM_NODES=$2/stg.nodes KM_EDGES=$2/stg.edges LC_ALL=C awk "$KM_AWK_COMMON$KM_AWK_MENT" < /dev/null
}

# km_one <rel> <src> <kind> <force:1|0> -> stdout: the final copy. force=0: the staged render plus
# Mentions; force=1 (content changed, stamp now): a fresh render plus Mentions. A copy that ends inside a
# fence gets a closing fence of the same length before the Mentions. Not for mode ledger/lnote.
km_body() { if [ "$4" = 1 ]; then km_render "$1" "$2" "$3" 1 1; else cat "$KM_STAGE/$1"; fi; }
km_one() {
  local mf=$KM_MENT/${1//\//%}
  if [ ! -f "$mf" ]; then km_body "$@"; return; fi
  km_body "$@" | LC_ALL=C awk "$KM_AWK_COMMON"'{ print; st = km_fence($0, st) } END { if (st) print km_ticks(st) }'
  cat "$mf"
}
