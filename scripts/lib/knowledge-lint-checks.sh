#!/usr/bin/env bash
# shellcheck shell=bash
# knowledge-lint-checks.sh — per-note codes and the contradiction report for
# scripts/knowledge-lint.sh. Sourced, never run. Read-only: nothing is written but scratch files.
# BSD awk / bash 3.2 only (no gensub, no declare -A, no mapfile, no regex intervals).
#
# kl_notes <scratch> <summary-only:0|1>   FAIL/WARN lines (sorted by path) + LINT summary
# kl_contradictions <scratch>             CONTRADICTION lines + CONTRADICTIONS n=
# Env contract: KL_MIRROR (mirror dir), KL_ALL (all mirror paths), KL_TODO (memory paths).

KL_AWK_COMMON='
function fence(x, st,    t, r) {
  t = x; sub(/^[ \t]+/, "", t)
  if (st) { r = t; sub(/[ \t\r]+$/, "", r); return (r ~ /^`+$/ && length(r) >= st) ? 0 : st }
  if (substr(t, 1, 3) == "```") { r = t; sub(/^`+/, "", r); if (index(r, "`") == 0) return length(t) - length(r) }
  return 0
}
function codespan(x,    o, b) {
  o = ""
  while (index(x, "`") > 0) {
    o = o substr(x, 1, index(x, "`") - 1); x = substr(x, index(x, "`") + 1)
    b = index(x, "`"); if (b == 0) return o
    x = substr(x, b + 1)
  }
  return o x
}
function slurp(f,    n, ln, rc) {
  delete L; n = 0
  while ((rc = (getline ln < f)) > 0) { sub(/\r$/, "", ln); L[++n] = ln }
  close(f)
  return (rc < 0 && n == 0) ? -1 : n
}
function unq(v) { sub(/^["\047]/, "", v); sub(/["\047]$/, "", v); return v }
function hit(s, re,    off, t, rs, a, b) { # first whole-word match of re in lowercase s, or ""
  off = 0; t = s
  while (match(t, re)) {
    rs = off + RSTART; a = (rs > 1) ? substr(s, rs - 1, 1) : ""; b = substr(s, rs + RLENGTH, 1)
    if (a !~ /[a-z0-9_]/ && b !~ /[a-z0-9_]/) return substr(s, rs, RLENGTH)
    off = rs; t = substr(s, off + 1)
  }
  return ""
}
function fmkey(line) { # sets KEY (name), KIND_IND (1 = indented), VAL; returns 1 when line is "key: value"
  if (!match(line, /^[ \t]*[A-Za-z_][A-Za-z0-9_-]*:/)) return 0
  KEY = substr(line, 1, RLENGTH - 1); VAL = substr(line, RLENGTH + 1)
  KIND_IND = (KEY ~ /^[ \t]/); sub(/^[ \t]+/, "", KEY); sub(/^[ \t]+/, "", VAL); sub(/[ \t]+$/, "", VAL)
  return 1
}
'

KL_AWK_NOTES='
function emit(sev, code, f, d) { print sev " " code " " f ((d != "") ? " " d : ""); C[code]++ }
function narrative(x,    s, w, lw) {
  s = x
  while (s ~ /^[ \t#>*_`(-]/ || substr(s, 1, 1) == "[") s = substr(s, 2)
  if (s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return 1
  lw = tolower(s)
  if (index(lw, "in this session") == 1) return 1
  w = lw; sub(/[^a-z].*$/, "", w)
  # German input aliases: stand, am
  if (w == "status" || w == "stand" || w == "state" || w == "during" || w == "today" || w == "yesterday" || w == "session") return 1
  return ((w == "on" || w == "am") && substr(lw, 3, 1) == " ")
}
function normsb(v,    t) { # canonical superseded_by: mirror-relative path with .md
  t = v; sub(/^\[\[/, "", t); sub(/\]\]$/, "", t); sub(/\|.*$/, "", t)
  while (substr(t, 1, 2) == "./") t = substr(t, 3)
  sub(/^mirror\//, "", t)
  return (t ~ /\.md$/) ? t : t ".md"
}
function parsefm(e,    i, line, blk) {
  for (i = 2; i < e; i++) {
    line = L[i]
    if (!fmkey(line)) { if (line ~ ISO) fmdate = 1; continue }
    if (KEY == "type" && typ == "") typ = unq(VAL)
    if (KEY == "kind" && !KIND_IND) nkind = unq(VAL)
    if (KEY == "originSessionId" || KEY == "modified" || KEY == "origin" || KEY == "dated_from" || KEY == "kind" || KEY == "backfilled") continue
    if (VAL ~ ISO && KEY != "dated") fmdate = 1
    if (KIND_IND) continue
    if (KEY == "description") {
      blk = (VAL ~ /^[>|][-+]?$/)
      hasdesc = blk ? (L[i + 1] ~ /^[ \t]+[^ \t]/ && i + 1 < e) : (unq(VAL) != "")
    } else if (KEY == "status") { hasst = 1; st = unq(VAL) }
    else if (KEY == "superseded_by") sb = unq(VAL)
    else if (KEY == "dated") dated = unq(VAL)
  }
  for (i = 2; i < e; i++) if (fmkey(L[i]) && KEY == "dated_from" && !KIND_IND) dfrom = unq(VAL)
}
function links(f, line,    rest, a, r2, e2, tok, k, t, c, cnt) {
  rest = codespan(line)
  while ((a = index(rest, "[[")) > 0) {
    r2 = substr(rest, a + 2); e2 = index(r2, "]]"); if (e2 == 0) break
    tok = substr(r2, 1, e2 - 1); k = index(tok, "[")
    if (k > 0) { rest = substr(r2, k); continue }
    rest = substr(r2, e2 + 2)
    if (tok ~ /^[ \t]/ || tok ~ /[ \t]$/) continue
    t = tok; sub(/[|#].*$/, "", t)
    if (t == "" || t ~ /^:/ || t !~ /[A-Za-z0-9]/ || (t in DS)) continue
    DS[t] = 1
    if (index(t, "/") > 0) { c = t; if (c !~ /\.md$/) c = c ".md"; cnt = (c in P) ? 1 : 0 }
    else { c = t; sub(/\.md$/, "", c); cnt = B[c] + 0 }
    if (cnt == 0) emit("FAIL", "dangling", f, "[[" t "]]")
    else if (cnt > 1) emit("WARN", "ambiguous", f, "[[" t "]]")
  }
}
function note(f,    nl, i, e, line, ns, fs, idx, first, why, how, bodydate, eff, ok, sbp, t) {
  nl = slurp(m "/" f)
  if (nl < 0) { print "FAIL unreadable " f; unread++; return }
  idx = (f ~ /\/MEMORY\.md$/); e = 0; fs = 0
  typ = ""; nkind = ""; hasdesc = 0; hasst = 0; st = ""; sb = ""; dated = ""; dfrom = ""; fmdate = 0; delete DS
  if (L[1] == "---") { for (i = 2; i <= nl; i++) if (L[i] == "---") { e = i; break } }
  if (!idx && !e) { emit("FAIL", "frontmatter", f, (L[1] == "---") ? "(unclosed)" : "(missing)"); fmbad++ }
  if (e) parsefm(e)
  if (nkind == "imp") { hasst = 0; sb = "" } # IMP copies carry the generated ledger status
  for (i = e + 1; i <= nl; i++) {
    line = L[i]
    if (line ~ /^<!-- knowledge-mirror:/) continue
    ns = fence(line, fs)
    if (first == "" && line !~ /^[ \t]*$/) first = line
    if (line ~ ISO) bodydate = 1
    if (index(line, "**Why:**")) why = 1
    if (index(line, "**How to apply:**")) how = 1
    if (!fs && !ns) links(f, line)
    fs = ns
  }
  if (idx) return
  n++
  if (!hasdesc) emit("FAIL", "desc", f)
  if (first != "" && narrative(first)) emit("WARN", "claim", f)
  ok = (typ == "feedback" || typ == "project" || typ == "reference" || typ == "user")
  if (typ == "") emit("WARN", "type", f, "(missing, treated as project)")
  else if (!ok) emit("WARN", "type", f, "(unknown value " typ ", treated as project)")
  eff = ok ? typ : "project"; t = ok ? typ : ((typ == "") ? "none" : "other")
  TN[t]++; if (why) { TW[t]++; wn++ }; if (how) { TH[t]++; hn++ }; if (why && how) both++
  if ((eff == "feedback" || eff == "project") && !why) emit("FAIL", "why", f)
  if ((eff == "feedback" || eff == "project") && !how) emit("FAIL", "how", f)
  if (!(fmdate || bodydate || (dated != "" && dfrom != "mtime"))) emit("FAIL", "date", f)
  if (SZ[f] > 8192) emit("FAIL", "size", f, SZ[f] " bytes")
  if (hasst && st !~ /^(active|superseded|archived)$/) emit("FAIL", "status", f, "value=" st)
  if (sb != "") {
    sbp = normsb(sb)
    if (sbp != sb) emit("WARN", "status-form", f, "superseded_by=" sb " (want " sbp ")")
    if (!(sbp in P)) emit("FAIL", "status", f, "superseded_by=" sb " (no such file)")
  }
}
BEGIN {
  m = ENVIRON["KL_MIRROR"]; ISO = "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"
  while ((getline r < ENVIRON["KL_ALL"]) > 0) { P[r] = 1; b = r; sub(/^.*\//, "", b); sub(/\.md$/, "", b); B[b]++ }
  while ((getline r < ENVIRON["KL_SIZES"]) > 0) { s = r; sub(/^[ \t]*[0-9]+[ \t]+/, "", s); z = r; sub(/^[ \t]*/, "", z); sub(/[ \t].*$/, "", z); SZ[s] = z + 0 }
  while ((getline f < ENVIRON["KL_TODO"]) > 0) note(f)
  printf "LINT n=%d desc=%d claim=%d why=%d how=%d date=%d size=%d dangling=%d status=%d type=%d\n", n, C["desc"], C["claim"], C["why"], C["how"], C["date"], C["size"], C["dangling"], C["status"], C["type"]
  printf "LINT why_present=%d how_present=%d both=%d\n", wn, hn, both
  split("feedback project reference user none other", TY, " ")
  for (i = 1; i <= 6; i++) if (i <= 4 || TN[TY[i]] > 0) printf "LINT type=%s n=%d why=%d how=%d\n", TY[i], TN[TY[i]], TW[TY[i]], TH[TY[i]]
  printf "LINT ambiguous=%d frontmatter=%d unreadable=%d\n", C["ambiguous"], fmbad, unread
}
'

# kl_notes <scratch> <summary-only>
kl_notes() {
  local s=$1 only=$2
  : > "$s/sizes.txt"
  if [ -s "$KL_TODO" ]; then
    ( cd "$KL_MIRROR" && tr '\n' '\0' < "$KL_TODO" | LC_ALL=C xargs -0 wc -c ) > "$s/sizes.txt" 2> "$s/wc.err" \
      || [ -s "$s/sizes.txt" ] \
      || { echo "knowledge-lint: cannot size mirror files: $(head -n 1 "$s/wc.err")" >&2; return 1; }
    # a file wc cannot read is reported as FAIL unreadable by the awk pass below, not skipped
  fi
  KL_SIZES=$s/sizes.txt LC_ALL=C awk "$KL_AWK_COMMON$KL_AWK_NOTES" < /dev/null > "$s/notes.out" || return 1
  if [ "$only" -eq 0 ]; then
    grep -v '^LINT ' "$s/notes.out" | LC_ALL=C sort -s -t ' ' -k3,3 -k2,2
  fi
  grep '^LINT ' "$s/notes.out"
}

KL_AWK_CONTRA='
function stem(b,    s) {
  s = tolower(b); gsub(/[^a-z0-9]+/, "_", s)
  sub(/^(project|feedback|reference|user)_/, "", s); sub(/_(pending|done|completed|final)$/, "", s)
  return s
}
function toks(s,    a, n, i, t, o) {
  s = tolower(s); gsub(/[^a-z0-9]+/, " ", s); n = split(s, a, " "); o = " "
  for (i = 1; i <= n; i++) {
    t = a[i]
    if (length(t) < 3 || t ~ /^[0-9]/ || index(STOPS, " " t " ") > 0 || index(o, " " t " ") > 0) continue
    o = o t " "
  }
  return o
}
function shared(x, y,    a, n, i, c) {
  n = split(x, a, " "); c = 0
  for (i = 1; i <= n; i++) if (index(y, " " a[i] " ") > 0) c++
  return c
}
function out(rule, a, b, ev) { print "CONTRADICTION " rule " " a " " b " " substr(ev, 1, 80) }
function load(f,    nl, i, e, line, lw, pw, dw, tk, p, x, nm, ds, pp) {
  nl = slurp(m "/" f)
  if (nl < 0) { print "UNREADABLE " f; return }
  split(f, pp, "/"); N[++cnt] = f; F[cnt] = pp[2]; b = pp[3]; sub(/\.md$/, "", b); BN[cnt] = b; FO[pp[2]] = 1; FB[pp[2] SUBSEP b] = cnt
  e = 0; nm = ""; ds = ""
  if (L[1] == "---") for (i = 2; i <= nl; i++) if (L[i] == "---") { e = i; break }
  for (i = 2; i < e; i++) if (fmkey(L[i]) && !KIND_IND) { if (KEY == "name") nm = VAL; else if (KEY == "description") ds = VAL }
  TK[cnt] = toks(b " " nm " " ds); ST[cnt] = stem(b)
  for (i = 2; i <= nl; i++) {
    line = L[i]
    if (line ~ /^<!-- knowledge-mirror:/ || line ~ /^[ \t]*(origin|originSessionId|modified|kind|node_type|type):/) continue
    lw = tolower(line)
    if (PD[cnt] == "") PD[cnt] = hit(lw, PEND)
    x = lw; gsub(/not (yet )?(launched|deployed|done|live)/, " ", x)
    if (DN[cnt] == "") DN[cnt] = hit(x, DONE)
    if (hit(lw, ABAND) != "") { x = line
      while (match(x, /(~|\/[A-Za-z0-9._-]+)\/[A-Za-z0-9._\/-]+/)) {
        p = substr(x, RSTART, RLENGTH); x = substr(x, RSTART + RLENGTH); sub(/[.\/,:;)]+$/, "", p)
        if (substr(p, 1, 1) == "~") p = ENVIRON["HOME"] substr(p, 2)
        gsub(/[^A-Za-z0-9-]/, "-", p); AB[++na] = cnt SUBSEP p
      } }
    if (hit(lw, OVER) != "" && match(line, /\[\[[^\]|#\/]+/)) OV[++no] = cnt SUBSEP substr(line, RSTART + 2, RLENGTH - 2)
  }
}
BEGIN {
  m = ENVIRON["KL_MIRROR"]
  # German input aliases: offen, geplant, noch nicht, erledigt, fertig, abgeschlossen, verworfen, eingestellt, berholt, veraltet, nie und der die das ein mit von ist nur wird wenn
  PEND = "pending|planned|not (yet )?(launched|deployed|done|live)|offen|geplant|noch nicht|ready to execute"
  DONE = "done|completed|live|deployed|launched|erledigt|fertig|abgeschlossen|deploys production|merged|fixed|shipped|released|implemented"
  ABAND = "abandoned|archived|retired|verworfen|eingestellt"; OVER = "berholt|obsolete|outdated|superseded|veraltet"
  STOPS = " the and for with from that this note notes project memory session claude feedback reference user was are not via nie und der die das ein mit von ist nur wird wenn when into over only also use used using file files "
  while ((getline f < ENVIRON["KL_TODO"]) > 0) if (f !~ /\/MEMORY\.md$/) load(f)
  for (i = 1; i <= cnt; i++) for (j = i + 1; j <= cnt; j++) {
    if (BN[i] == BN[j] && F[i] != F[j]) out("dup-basename", N[i], N[j], "basename=" BN[i])
    if (F[i] != F[j]) continue
    if (ST[i] != ST[j] && shared(TK[i], TK[j]) < 3) continue
    if (PD[i] != "" && DN[j] != "") out("status", N[i], N[j], "pending:\"" PD[i] "\" done:\"" DN[j] "\"")
    else if (PD[j] != "" && DN[i] != "") out("status", N[j], N[i], "pending:\"" PD[j] "\" done:\"" DN[i] "\"")
  }
  for (k = 1; k <= na; k++) { split(AB[k], q, SUBSEP)
    if (q[2] in FO && FO[q[2]] && F[q[1]] != q[2]) for (j = 1; j <= cnt; j++) if (F[j] == q[2]) out("abandoned", N[j], N[q[1]], "declared abandoned: " q[2]) }
  for (k = 1; k <= no; k++) { split(OV[k], q, SUBSEP)
    if ((F[q[1]] SUBSEP q[2]) in FB && FB[F[q[1]] SUBSEP q[2]] != q[1]) out("overtaken", N[FB[F[q[1]] SUBSEP q[2]]], N[q[1]], "[[" q[2] "]] called outdated") }
}
'

# kl_contradictions <scratch>
kl_contradictions() {
  local s=$1 n
  LC_ALL=C awk "$KL_AWK_COMMON$KL_AWK_CONTRA" < /dev/null | LC_ALL=C sort -u > "$s/contra.out" || return 1
  grep '^UNREADABLE ' "$s/contra.out" >&2
  grep '^CONTRADICTION ' "$s/contra.out"
  n=$(grep -c '^CONTRADICTION ' "$s/contra.out")
  echo "CONTRADICTIONS n=$n"
}
