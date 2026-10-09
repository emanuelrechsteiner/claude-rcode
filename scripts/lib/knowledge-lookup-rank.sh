#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # the awk program is single-quoted by design
# knowledge-lookup-rank.sh - file selection, keyword spec and BM25F-lite scoring for
# scripts/knowledge-lookup.sh (sourced by it, never executed). bash 3.2 / BSD awk.
# Caller sets MIRROR WORK KINDS PROJ PREFIX and the array FILES is filled here.

kl_die() { echo "knowledge-lookup: $1" >&2; exit "${2:-1}"; }

# kl_want <kind>: is the kind in scope? No --kind: everything except the index (ledger.md).
kl_want() {
  if [ -z "$KINDS" ]; then [ "$1" != index ]; return; fi
  case ",$KINDS," in *",$1,"*) return 0 ;; esac
  return 1
}

# kl_ciglob <text>: a case-insensitive *text* glob built without forks (bash 3.2 has no ${x,,}).
kl_ciglob() {
  local s=$1 i c pre o="*" lo=abcdefghijklmnopqrstuvwxyz up=ABCDEFGHIJKLMNOPQRSTUVWXYZ
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:$i:1}
    pre=${lo%%"$c"*}
    if [ "$pre" != "$lo" ]; then o="${o}[${c}${up:${#pre}:1}]"; continue; fi
    pre=${up%%"$c"*}
    if [ "$pre" != "$up" ]; then o="${o}[${c}${lo:${#pre}:1}]"; else o="$o\\$c"; fi
  done
  printf '%s*' "$o"
}

# kl_collect: fill FILES with the in-scope *.md files (no symlink is followed), filtered by KINDS/PROJ.
kl_collect() {
  local sub kind f rel seg pg=""
  [ -z "$PROJ" ] || pg=$(kl_ciglob "$PROJ")
  { for sub in memory:memory rules:rule logbook:logbook plans:plan evidence:evidence adr:adr docs:doc; do
      kind=${sub#*:}; sub=${sub%%:*}
      if kl_want "$kind" && [ -d "$MIRROR/$sub" ]; then find "$MIRROR/$sub" -type f -name '*.md' -print0; fi
    done
    if kl_want imp && [ -d "$MIRROR/ledger" ]; then find "$MIRROR/ledger" -maxdepth 1 -type f -name '*.md' -print0; fi
    if kl_want index && [ -f "$MIRROR/ledger.md" ] && [ ! -L "$MIRROR/ledger.md" ]; then printf '%s\0' "$MIRROR/ledger.md"; fi
  } > "$WORK/files0"
  FILES=()
  while IFS= read -r -d '' f; do
    if [ -n "$pg" ]; then # --project: memory notes whose folder segment contains the text
      rel=${f#"$MIRROR/memory/"}; [ "$rel" != "$f" ] || continue
      seg=${rel%%/*}
      # shellcheck disable=SC2254 # $pg is a pattern on purpose
      case "$seg" in $pg) ;; *) continue ;; esac
    fi
    FILES+=("$f")
  done < "$WORK/files0"
}

# kl_kwspec <kw.txt> <collisions.tsv> <out>: "keyword<TAB>mode" per line; mode ci|cs|code. Malformed list: exit 2.
kl_kwspec() {
  [ -r "$2" ] || kl_die "collision list not readable: $2" 1
  awk -F '\t' -v cf="$2" '
    function err(m) { printf "knowledge-lookup: %s:%d: %s\n", cf, FNR, m > "/dev/stderr"; bad = 1; exit 2 }
    FILENAME == cf { sub(/\r$/, "")
      if ($0 == "" || $0 ~ /^#/) next
      if (!hdr) { hdr = 1; if ($0 != "keyword\tmode") err("header must be \"keyword<TAB>mode\""); next }
      if (NF != 2 || $1 == "" || ($2 != "cs" && $2 != "code")) err("row must be keyword<TAB>cs|code")
      mode[tolower($1)] = $2; next }
    { if (!hdr) err("empty collision list (no header)"); print $0 "\t" (($0 in mode) ? mode[$0] : "ci") }
    END { if (bad) exit 2 }' "$2" "$1" > "$3" || exit $?
}

# kl_scan_prog: the awk program. Reads the keyword spec (-v kws=), scores every file named on the
# command line and prints one row per matching file:
# distinct, score, path, bytes, status, superseded_by, description, then (line, heading, text) x <= 3.
kl_scan_prog() {
  cat <<'AWK'
function kf(x, st,    t, r) { # fence state after line x (st = state before): 0 prose, N >= 3 inside a fence of N backticks
  t = x; sub(/^[ \t]+/, "", t)
  if (st) { r = t; sub(/[ \t\r]+$/, "", r); return (r ~ /^`+$/ && length(r) >= st) ? 0 : st }
  if (substr(t, 1, 3) == "```") { r = t; sub(/^`+/, "", r); if (index(r, "`") == 0) return length(t) - length(r) }
  return 0
}
function codeof(s, fenced,    n, p, i, o) { # the part of a line a "code" keyword may match
  if (fenced) return s
  if (s ~ /^[ \t]*import[ \t]/ || s ~ /from ['"]/ || s ~ /(^|[^A-Za-z0-9_])(require\(|npm i |npm install |pnpm add |pnpm i |yarn add )/) return s
  n = split(s, p, "`"); o = ""
  for (i = 2; i < n; i += 2) o = o " " p[i]
  return o
}
function lok(s, pos,    b, c2) { # left edge of a match at pos is a word boundary? (bytes: curly quotes, arrows, NBSP, x/div are boundaries)
  if (pos < 2) return 1
  b = substr(s, pos - 1, 1)
  if (b in nw) return 1
  if (!(b in cont)) return 0
  c2 = substr(s, pos - 2, 1)
  if (c2 == "\302" || substr(s, pos - 3, 1) == "\342") return 1
  return (c2 == "\303" && (b == "\227" || b == "\267"))
}
function rok(s, p,    a) { # right edge: p = position of the byte after the match
  a = substr(s, p, 1)
  if (a == "" || a in nw) return 1
  return (a == "\303" && (substr(s, p + 1, 1) == "\227" || substr(s, p + 1, 1) == "\267"))
}
function cnt(s, k, pf,    key, kl, off, pos, n2, ok) { # whole-word (or word-prefix) occurrences of keyword k in s
  key = kw[k]; kl = kn[k]; n2 = 0; off = 0
  while ((pos = index(substr(s, off + 1), key)) > 0) {
    pos += off; ok = 1
    if (lw[k] && !lok(s, pos)) ok = 0
    if (ok && !pf && rw[k] && !rok(s, pos + kl)) ok = 0
    if (ok) { n2++; off = pos + kl - 1 } else off = pos
  }
  return n2
}
function scanline(line, fenced, skipcode,    k, s, c) { # fills LC[k] (counts), LM (distinct), LS (set string)
  low = tolower(line); cdone = 0; ddone = 0; LM = 0; LS = ""
  for (k = 1; k <= K; k++) {
    if (index(low, kw[k]) == 0) { LC[k] = 0; continue } # cheap reject (keywords are lowercase) before any boundary work
    if (md[k] == "cs") { # exact case always; another case only on a line without a German function word
      if (!ddone) { de = (low ~ GERMAN); ddone = 1 }
      s = de ? line : low
    } else if (md[k] == "code") {
      if (skipcode) { LC[k] = 0; continue }
      if (!cdone) { cd = tolower(codeof(line, fenced)); cdone = 1 }
      s = cd
    } else s = low
    c = cnt(s, k, pf); LC[k] = c
    if (c) { LM++; LS = LS k " " }
  }
}
function addco() { if (nco < 3) { nco++; COS[fi, nco] = LS } }
function fscan(s, w, skipcode,    k) { # a frontmatter/basename field counts as one pseudo-line (short field: no length norm)
  scanline(s, 0, skipcode)
  for (k = 1; k <= K; k++) if (LC[k]) wsh[k] += w * LC[k]
  if (LM >= 2) addco()
}
function fmval(line,    v) {
  v = line; sub(/^[A-Za-z_]+:[ \t]*/, "", v); sub(/[ \t\r]+$/, "", v)
  if (v ~ /^".*"$/) { v = substr(v, 2, length(v) - 2); gsub(/\\"/, "\"", v) }
  else if (v ~ /^'.*'$/) v = substr(v, 2, length(v) - 2)
  gsub(/\t/, " ", v); return v
}
function addhit(ln, line, hd, isH,    t, j, mi) { # keep the 3 best lines: most distinct keywords, earliest first
  t = line; gsub(/[\t\r]/, " ", t); sub(/^ +/, "", t); sub(/ +$/, "", t); t = isH ? "" : substr(t, 1, 640) # a heading hit is shown as its heading alone
  if (nh < 3) { nh++; j = nh }
  else { mi = 1; for (j = 2; j <= 3; j++) if (HLM[j] <= HLM[mi]) mi = j
         if (LM <= HLM[mi]) return
         j = mi }
  HLN[j] = ln; HLM[j] = LM; HTX[j] = t; HHD[j] = hd
}
function endfile(    fe, i, k, line, ns, infc, isH, hd, fst, nm, ds, base, bs, j, a, b, hs) {
  if (n == 0) return
  fi++; PATH[fi] = substr(cur, length(mp) + 1)
  fe = 0
  if (L[1] ~ /^---\r?$/) for (i = 2; i <= n; i++) if (L[i] ~ /^---\r?$/) { fe = i; break }
  bs = 0; for (i = 1; i <= n; i++) bs += length(L[i]) + 1
  BYTES[fi] = bs; totb += bs
  for (k = 1; k <= K; k++) { ws[k] = 0; wsh[k] = 0 }
  nh = 0; nco = 0; nm = ""; ds = ""; kd = ""; STAT[fi] = ""; SUP[fi] = ""
  for (i = 2; i < fe; i++) { # only these four top-level frontmatter keys are read; kind:/origin:/ids never match
    line = L[i]
    if (line ~ /^name:/) nm = fmval(line)
    else if (line ~ /^description:/) ds = fmval(line)
    else if (line ~ /^kind:/) kd = fmval(line)
    else if (line ~ /^status:/) STAT[fi] = fmval(line)
    else if (line ~ /^superseded_by:/) SUP[fi] = fmval(line)
  }
  if (kd == "imp" || PATH[fi] ~ /^ledger\//) STAT[fi] = "" # IMP copies carry the ledger status vocabulary, not a note lifecycle
  DESC[fi] = ds
  base = PATH[fi]; sub(/^.*\//, "", base); sub(/\.md$/, "", base)
  fscan(base, WB, 1)
  base = tolower(base); for (k = 1; k <= K; k++) if (md[k] != "code" && base == kw[k]) XACT[fi, k] = 1 # file name IS the keyword
  if (nm != "") fscan(nm, WF, 0)
  if (ds != "") fscan(ds, WF, 0)
  fst = 0; hd = ""
  for (i = fe + 1; i <= n; i++) {
    line = L[i]; sub(/\r$/, "", line)
    if (!fst && line ~ /^## Mentions[ \t]*$/) break # generated reverse-link section: ignored to end of file
    if (line ~ /knowledge-mirror: (copied|rendered) from/) continue
    ns = kf(line, fst); infc = (fst || ns); fst = ns
    isH = (!infc && line ~ /^#+[ \t]/)
    if (isH) { hd = line; sub(/^#+[ \t]*/, "", hd); sub(/[ \t#]+$/, "", hd); gsub(/\t/, " ", hd) }
    scanline(line, infc, 0)
    if (LM == 0) continue
    for (k = 1; k <= K; k++) if (LC[k]) ws[k] += (isH ? WH : 1) * LC[k]
    if (LM >= 2) addco()
    addhit(i, line, hd, isH)
  }
  for (a = 1; a < nh; a++) for (b = a + 1; b <= nh; b++) if (HLN[b] < HLN[a]) {
    j = HLN[a]; HLN[a] = HLN[b]; HLN[b] = j; j = HLM[a]; HLM[a] = HLM[b]; HLM[b] = j
    j = HTX[a]; HTX[a] = HTX[b]; HTX[b] = j; j = HHD[a]; HHD[a] = HHD[b]; HHD[b] = j }
  hs = ""; for (j = 1; j <= nh; j++) hs = hs "\t" HLN[j] "\t" HHD[j] "\t" HTX[j]
  HITS[fi] = hs; NCO[fi] = nco
  for (k = 1; k <= K; k++) if (ws[k] + wsh[k] > 0) { W[fi, k] = ws[k]; WS[fi, k] = wsh[k]; df[k]++; D[fi]++ }
  n = 0
}
BEGIN {
  for (i = 1; i < 128; i++) { c = sprintf("%c", i); if (c !~ /[A-Za-z0-9_]/) nw[c] = 1 }
  nw["\342"] = 1; nw["\302"] = 1 # UTF-8 lead bytes of U+2000-U+2FFF (quotes, dashes, arrows) and U+0080-U+00BF (NBSP): boundaries
  for (i = 128; i <= 191; i++) cont[sprintf("%c", i)] = 1
  while ((getline ln < kws) > 0) {
    split(ln, a, "\t"); K++; kw[K] = a[1]; md[K] = a[2]; kn[K] = length(a[1])
    lw[K] = !(substr(a[1], 1, 1) in nw); rw[K] = !(substr(a[1], kn[K], 1) in nw)
  }
  close(kws)
  if (K < 1) { print "knowledge-lookup: internal: empty keyword spec" > "/dev/stderr"; bad = 1; exit 2 }
  GERMAN = "(^|[^A-Za-z0-9_])(der|die|das|den|dem|des|und|ist|nicht|von|f\303\274r|wird|ein|eine|einen|im|zu|zum|zur|auf|bei|nach|wenn|oder|auch|aber|sind)([^A-Za-z0-9_]|$)"
  K1 = 1.2; BB = 0.75; WB = 3; WF = 3; WH = 2; CO = 0.3; XB = 1.0; LOGW = 0.5
}
FNR == 1 { endfile(); cur = FILENAME }
{ L[++n] = $0 }
END {
  if (bad) exit 2
  endfile()
  if (fi == 0) exit 0
  avg = totb / fi; if (nfiles < fi) nfiles = fi
  for (k = 1; k <= K; k++) idf[k] = log((nfiles - df[k] + 0.5) / (df[k] + 0.5) + 1)
  for (f = 1; f <= fi; f++) {
    if (D[f] == 0) continue
    sc = 0
    for (k = 1; k <= K; k++) if ((f, k) in W) { t = WS[f, k] + W[f, k] / (1 - BB + BB * BYTES[f] / avg); sc += idf[k] * t * (K1 + 1) / (t + K1) }
    for (k = 1; k <= K; k++) if ((f, k) in XACT) sc += XB * idf[k]
    for (j = 1; j <= NCO[f]; j++) { m = split(COS[f, j], a, " "); s = 0; for (i = 1; i <= m; i++) s += idf[a[i]]; sc += CO * s }
    if (substr(PATH[f], 1, 8) == "logbook/") sc *= LOGW
    printf "%d\t%.6f\t%s\t%d\t%s\t%s\t%s%s\n", D[f], sc, PATH[f], BYTES[f], STAT[f], SUP[f], DESC[f], HITS[f]
  }
}
AWK
}

# kl_rank <kw.spec> <out.tsv>: scan FILES, sort (distinct desc, score desc, path). The superseded
# reordering (kl_supersede) is applied by the caller, after any fusion of several keyword sets.
kl_rank() {
  local TAB; TAB=$(printf '\t')
  kl_scan_prog > "$WORK/scan.awk"
  awk -v mp="$MIRROR/" -v kws="$1" -v nfiles="${#FILES[@]}" -v pf="$PREFIX" -f "$WORK/scan.awk" "${FILES[@]}" \
    | LC_ALL=C sort -t "$TAB" -k1,1nr -k2,2nr -k3,3 > "$2"
}
