#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # awk programs live in single-quoted strings on purpose
# knowledge-mirror-links.sh - link hygiene, link report, Mentions and graph export for
# scripts/knowledge-mirror.sh (v3). Sourced by knowledge-mirror-graph.sh, never executed.
# Works on COPIES (a scratch stage directory or <K>/mirror); sources are never touched.
#   awk (appended to KM_AWK_COMMON): km_memlink / km_mdl rewrite memory links inside the project
#     folder, km_proj rewrites projects/<f>/memory/<x>.md in logbook and plans
#   km_scan / km_check_links   one pass over a directory of copies: LINKS report with dangling
#                    causes, nodes and edges (km_check_links also serves --check-links)
#   knowledge-mirror-meta.sh (sourced below): generated dated keys, km_stage / km_one (stage render and
#                    Mentions), km_graph_export (graph/*.tsv)
# KM_V3L=0 (flag --no-v3-links) switches off the v3 link features: memory link rewrite, MEMORY.md
# rewrite, logbook/plan memory paths, Mentions, markdown-link counting and the memory-path check.
# This text lives in shell single-quoted strings: awk code and comments must never contain a single quote.
KM_AWK_COMMON="$KM_AWK_COMMON"'
function km_fold(s) { s = tolower(s); gsub(/_/, "-", s); return s }
function km_meta(rel, cr,    n, j, ML, mk) { # generated dated keys of this copy (KM_METAMAP, loaded by the render BEGIN)
  if (!(rel in MT)) return
  n = split(MT[rel], ML, "\t")
  for (j = 1; j <= n; j++) { # a key the source owns (OWN, set by the render) is not generated; a source owning dated gets no dated_from
    mk = ML[j]; sub(/:.*$/, "", mk)
    if ((mk in OWN) || (mk == "dated_from" && ("dated" in OWN))) continue
    print ML[j] cr
  }
}
# logbook/plan backtick path projects/<folder>/memory/<file>.md -> memory/<folder>/<file>, or ""
function km_proj(p,    r, k, f) {
  r = ENVIRON["KM_REL"]
  if (ENVIRON["KM_V3L"] == "0" || (r !~ /^logbook\// && r !~ /^plans\//)) return ""
  if (p !~ /^projects\/[^\/]+\/memory\/[^\/]+\.md$/) return ""
  p = substr(p, 10); k = index(p, "/memory/")
  f = substr(p, k + 8); f = substr(f, 1, length(f) - 3)
  return km_okname(f) ? "memory/" substr(p, 1, k - 1) "/" f : ""
}
# own project folder of a memory copy: PROJ, PC[fold(base)] = count, PB[fold(base)] = base
function km_pinit(    r, pr, k, b) {
  if (PINIT) return
  PINIT = 1; r = ENVIRON["KM_REL"]
  if (r !~ /^memory\/[^\/]+\//) return
  PROJ = r; sub(/^memory\//, "", PROJ); sub(/\/.*$/, "", PROJ)
  pr = "memory/" PROJ "/"
  for (k in T) if (index(k, pr) == 1) {
    b = substr(k, length(pr) + 1)
    if (index(b, "/") > 0 || b !~ /\.md$/) continue
    b = substr(b, 1, length(b) - 3); PC[km_fold(b)]++; PB[km_fold(b)] = b
  }
}
# bare token (name, rest of token = #heading and/or |alias) -> [[memory/<proj>/<file>...]] on a UNIQUE folded match;
# the bare token itself when the fold is not unique (final: no later rule lookup); "" when the folder has no match
function km_memlink(tok, nm,    f) {
  if (ENVIRON["KM_V3L"] == "0" || ENVIRON["KM_REL"] !~ /^memory\//) return ""
  km_pinit(); f = nm; sub(/\.md$/, "", f); f = km_fold(f)
  if (f in PC) return (PC[f] == 1) ? "[[memory/" PROJ "/" PB[f] substr(tok, length(nm) + 1) "]]" : "[[" tok "]]" # non-unique: bare, and the caller must not try a rule
  return ""
}
function km_btodd(s,    t) { t = s; return gsub(/`/, "", t) % 2 } # 1 when s ends inside a backtick span (odd count)
# [title](file.md) in a memory copy -> [[memory/<proj>/<file>|title]] on a unique folded match
function km_mdl(s,    out, rest, a, t, e, tg, pre, k, ti, f) {
  if (ENVIRON["KM_V3L"] == "0" || ENVIRON["KM_REL"] !~ /^memory\// || index(s, "](") == 0) return s
  km_pinit(); out = ""; rest = s
  while ((a = index(rest, "](")) > 0) {
    pre = substr(rest, 1, a - 1); t = substr(rest, a + 2); e = index(t, ")")
    if (e == 0) break
    tg = substr(t, 1, e - 1); k = km_lastidx(pre, "["); ti = substr(pre, k + 1); rest = substr(t, e + 1)
    f = tg; sub(/\.md$/, "", f); f = km_fold(f)
    if (k > 0 && !(k > 1 && substr(pre, k - 1, 1) == "!") && km_btodd(out substr(pre, 1, k - 1)) == 0 && tg ~ /\.md$/ && tg !~ /[\/: #]/ \
        && ti !~ /[\[\]|]/ && (f in PC) && PC[f] == 1) {
      out = out substr(pre, 1, k - 1) "[[memory/" PROJ "/" PB[f] (ti == "" ? "" : "|" ti) "]]"
    } else out = out pre "](" tg ")"
  }
  return out rest
}
'

# ---- link scan: one pass over a directory of copies -> report (stdout), .nodes, .edges ----------
# Env: KM_LIST (relative paths), KM_MIRROR (directory), KM_DETAIL, KM_OUT (output prefix), KM_V3L.
# nodes: path kind status dated description implementedAt proposedAt. edges: src dst via, one row per
# resolved link occurrence (a link counted twice is two rows). Ambiguous and dangling ones are no rows.
KM_AWK_SCAN='
function km_cause(t, nvar,    b) {
  if (t ~ /[<>]/ || index(t, "{{") > 0 || index(t, "}}") > 0 || index(t, "...") > 0) return "template"
  b = t; sub(/^.*\//, "", b); sub(/\.md$/, "", b)
  if (b == "name" || b == "file" || b == "path" || b == "slug" || b == "title" || b == "id" || b == "filename") return "template"
  if (t ~ /\.local(\.md)?$/ || t ~ /\.jsonl$/ || t ~ /(^|\/)(cockpit|vault)(\/|$)/) return "excluded-by-design"
  return (nvar > 0) ? "slug" : "missing"
}
function km_dang(t, src, cause,    key) {
  dang++; key = t SUBSEP src
  if (!(key in dseen)) { dseen[key] = 1; if (nd < 30) dl[++nd] = "dangling: " t " cause=" cause " in " src }
}
function km_wl(t, src, ln,    c, cnt, d, n, via, pj, fc) {
  total++
  if (index(t, "/") > 0) { c = t; if (c !~ /\.md$/) c = c ".md"; cnt = (c in P) ? 1 : 0; d = c; n = FP[km_fold(substr(c, 1, length(c) - 3))] + 0 }
  else { c = t; sub(/\.md$/, "", c); cnt = B[c] + 0; d = BP[c]; n = FB[km_fold(c)] + 0 }
  if (cnt == 0 && n >= 2) cnt = n
  if (cnt == 1 && v3 && index(t, "/") == 0 && src ~ /^memory\/[^\/]+\//) { # an ambiguous in-folder fold is not resolved by a target outside the folder
    pj = src; sub(/^memory\//, "", pj); sub(/\/.*$/, "", pj); fc = FF[pj "/" km_fold(c)] + 0
    if (fc >= 2 && index(d, "memory/" pj "/") != 1) cnt = fc
  }
  if (cnt == 1) {
    ok++; via = "wikilink"
    if (imen) via = (index(ln, "(same-day)") > 0) ? "same-day" : "mentions"
    else if (src ~ /^rules\// && d == ("evidence/" substr(src, 7))) via = "evidence"
    print src "\t" d "\t" via > fe
  } else if (cnt == 0) km_dang(t, src, km_cause(t, n))
  else { amb++; if (!(t in aseen)) { aseen[t] = 1; if (na < 30) al[++na] = "ambiguous: " t " (" cnt " candidates)" } }
}
function km_norm(p,    n, a, i, o, k, r) { # collapse ./ and ../ ; "" when it leaves the mirror
  n = split(p, a, "/"); k = 0
  for (i = 1; i <= n; i++) {
    if (a[i] == "" || a[i] == ".") continue
    if (a[i] == "..") { if (k == 0) return ""; k--; continue }
    o[++k] = a[i]
  }
  r = ""; for (i = 1; i <= k; i++) r = r (i > 1 ? "/" : "") o[i]
  return r
}
function km_md(tg, src,    dir, c, b) { # a relative markdown link to a .md file
  total++; dir = src
  if (sub(/\/[^\/]*$/, "", dir) == 0) dir = ""
  c = km_norm((dir == "" ? "" : dir "/") tg)
  if (c == "" || !(c in P)) c = km_norm(tg)
  if (c != "" && (c in P)) { ok++; print src "\t" c "\tmdlink" > fe; return }
  b = tg; sub(/^.*\//, "", b); sub(/\.md$/, "", b)
  km_dang(tg, src, km_cause(tg, FB[km_fold(b)] + 0))
}
function km_mdscan(rest, src,    a, t, e, tg, pre, k) {
  while ((a = index(rest, "](")) > 0) {
    pre = substr(rest, 1, a - 1); t = substr(rest, a + 2); e = index(t, ")")
    if (e == 0) return
    tg = substr(t, 1, e - 1); rest = substr(t, e + 1); k = km_lastidx(pre, "[")
    if (k == 0 || (k > 1 && substr(pre, k - 1, 1) == "!")) continue
    sub(/[ \t].*$/, "", tg); if (substr(tg, 1, 1) == "<") { sub(/^</, "", tg); sub(/>.*$/, "", tg) }
    sub(/#.*$/, "", tg)
    if (tg ~ /\.md$/ && index(tg, "://") == 0 && tg !~ /^mailto:/) km_md(tg, src)
  }
}
# logbook/plan backtick path projects/<f>/memory/<x>.md that is still a backtick: its target does not exist
function km_pj(s, src,    rest, a, n, cl, c, k, d) {
  rest = s
  while ((a = index(rest, "`")) > 0) {
    n = 1; while (substr(rest, a + n, 1) == "`") n++
    cl = km_close(rest, a, n)
    if (!cl) { rest = substr(rest, a + n); continue }
    c = substr(rest, a + n, cl - 1); rest = substr(rest, a + 2 * n + cl - 1)
    if (n != 1) continue
    if (index(c, "~/.claude/") == 1) c = substr(c, 11)
    if (c !~ /^projects\/[^\/]+\/memory\/[^\/]+\.md$/) continue
    d = substr(c, 10); k = index(d, "/memory/"); d = "memory/" substr(d, 1, k - 1) "/" substr(d, k + 8)
    total++
    if (d in P) { ok++; print src "\t" d "\twikilink" > fe } else km_dang(c, src, "missing")
  }
}
function km_fmkey(x,    k, v, q) {
  if (x ~ /^[A-Za-z_][A-Za-z0-9_-]*[ \t]*:/) {
    k = x; sub(/[ \t]*:.*$/, "", k); v = x; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); lastk = k
    if (v ~ /^[>|][-+0-9]*$/) v = ""
    q = substr(v, 1, 1)
    if (length(v) >= 2 && (q == "\"" || q == "\047") && substr(v, length(v), 1) == q) v = substr(v, 2, length(v) - 2)
    if (k == "kind" && nk == "") nk = v
    else if (k == "status" && nst == "") nst = v
    else if (k == "dated" && ndt == "") ndt = v
    else if (k == "description" && !hd) { dsc = v; hd = 1 }
    else if (k == "implementedAt" && ia == "") ia = v
    else if (k == "proposedAt" && ip == "") ip = v
  } else if (lastk == "description" && x ~ /^[ \t]+[^ \t]/) { sub(/^[ \t]+/, "", x); dsc = (dsc == "" ? "" : dsc " ") x }
}
BEGIN {
  list = ENVIRON["KM_LIST"]; m = ENVIRON["KM_MIRROR"]; detail = (ENVIRON["KM_DETAIL"] == "1"); v3 = (ENVIRON["KM_V3L"] != "0")
  fe = ENVIRON["KM_OUT"] ".edges"; fn = ENVIRON["KM_OUT"] ".nodes"; printf "" > fe; printf "" > fn
  while ((getline r < list) > 0) {
    files[++nf] = r; P[r] = 1; b = r; sub(/^.*\//, "", b); sub(/\.md$/, "", b); B[b]++; BP[b] = r; FB[km_fold(b)]++
    if (r ~ /^memory\/[^\/]+\/[^\/]+\.md$/) { pj = r; sub(/^memory\//, "", pj); sub(/\/.*$/, "", pj); FF[pj "/" km_fold(b)]++ }
    b = r; sub(/\.md$/, "", b); FP[km_fold(b)]++
  }
  close(list)
  for (i = 1; i <= nf; i++) {
    path = m "/" files[i]; src = files[i]; st = 0; fm = 0; ln = 0; imen = 0; lastk = ""
    nk = ""; nst = ""; ndt = ""; dsc = ""; hd = 0; ia = ""; ip = ""
    while ((getline line < path) > 0) {
      ln++; cl = line; sub(/\r$/, "", cl)
      if (ln == 1 && cl == "---") { fm = 1; continue }
      if (fm == 1) { if (cl == "---") fm = 2; else km_fmkey(cl); continue } # frontmatter lines are metadata, never scanned for links
      fs = km_fence(line, st); prose = (!st && !fs); st = fs
      if (!prose) continue
      if (cl ~ /^#/) imen = (cl == "## Mentions")
      rest = km_prose(line)
      if (v3) { km_mdscan(rest, src); if (src ~ /^(logbook|plans)\//) km_pj(line, src) }
      while ((a = index(rest, "[[")) > 0) {
        r2 = substr(rest, a + 2); e = index(r2, "]]")
        if (e == 0) break
        tok = substr(r2, 1, e - 1)
        k = index(tok, "[")
        if (k > 0) { rest = substr(r2, k); continue }
        rest = substr(r2, e + 2)
        if (tok ~ /^[ \t]/ || tok ~ /[ \t]$/) continue
        t = tok; sub(/[|#].*$/, "", t)
        if (t == "" || t ~ /^:/ || t !~ /[A-Za-z0-9]/) continue # not a link: empty, POSIX class [[:space:]], "..."
        km_wl(t, src, line)
      }
    }
    close(path)
    if (src == "README.md") continue
    if (ndt == "" && nk == "imp") { ndt = (ia != "") ? ia : ip; ndt = (ndt ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) ? substr(ndt, 1, 10) : "" }
    gsub(/[\t\r]/, " ", dsc); gsub(/[\t\r]/, " ", nst); gsub(/[\t\r]/, " ", ndt)
    print src "\t" nk "\t" (nst == "" ? "active" : nst) "\t" ndt "\t" dsc "\t" ia "\t" ip > fn
  }
  printf "LINKS total=%d resolved=%d ambiguous=%d dangling=%d\n", total, ok, amb, dang
  if (detail) { for (i = 1; i <= nd; i++) print dl[i]; for (i = 1; i <= na; i++) print al[i] }
}
'

# km_scan <dir> <listfile> <out-prefix> <detail:1|0> -> LINKS report on stdout; <prefix>.nodes/.edges
km_scan() {
  KM_LIST=$2 KM_MIRROR=$1 KM_OUT=$3 KM_DETAIL=$4 LC_ALL=C awk "$KM_AWK_COMMON$KM_AWK_SCAN" < /dev/null
}

# km_check_links <mirror> <detail:1|0> <scratch-dir>: prints the LINKS summary on stdout (plus up to
# 30 dangling and 30 ambiguous lines when detail=1). A report: returns 0 whatever it finds; returns 1
# (library unavailable) when there is no mirror or it holds no copies, so a missing library is never a
# healthy empty graph.
# Leaves <scratch>/chk.nodes and chk.edges for km_graph_export.
km_check_links() {
  local list=$3/links.list
  if [ ! -d "$1" ]; then
    echo "knowledge-mirror: library unavailable: no mirror at $1 (run without --check-links first)" >&2
    return 1
  fi
  ( cd "$1" && find . -type f -name '*.md' ! -path './.state/*' | sed 's|^\./||' | LC_ALL=C sort ) > "$list"
  if [ -z "$(grep -vx 'README.md' "$list" | head -n 1)" ]; then # a mirror without copies is not a healthy empty graph
    echo "knowledge-mirror: library unavailable: $1 holds no mirror copies (run without --check-links first)" >&2
    return 1
  fi
  km_scan "$1" "$list" "$3/chk" "$2"
}

# shellcheck source=/dev/null
. "${BASH_SOURCE[0]%/*}/knowledge-mirror-meta.sh"
