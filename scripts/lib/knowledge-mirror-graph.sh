#!/usr/bin/env bash
# shellcheck shell=bash source-path=SCRIPTDIR
# shellcheck disable=SC2016 # awk and jq programs live in single-quoted strings on purpose
# knowledge-mirror-graph.sh - library for scripts/knowledge-mirror.sh (v2, the justification
# graph). Sourced by absolute path, never executed; expects err() from the caller. Works on
# COPIES in a scratch directory or on <K>/mirror; sources under ~/.claude are never touched.
#   km_render        kind:/origin: frontmatter + provenance + link rewrites for one copy
#   km_ledger_build  ledger.md index + one note per IMP id (scratch directory)
#   km_tsmap         timestamps of existing provenance comments (idempotence)
#   km_hash_rels     batched sha256 of listed mirror files
#   km_check_links   graph health report: total/resolved/ambiguous/dangling
# shellcheck disable=SC2088 # the tilde is a literal display string, never to be expanded
KM_LEDGER_DISP='~/.claude/global-observation/improvement-ledger.json'
KM_LEDGER_PROV="<!-- knowledge-mirror: rendered from $KM_LEDGER_DISP; read-only copy, edits are refused on the next run -->"

# Shared awk helpers for BSD awk 20200816 (macOS): no gensub, no intervals. This text
# lives in a shell single-quoted string: awk code and comments must never contain a single quote.
KM_AWK_COMMON='
function km_okname(n,    i) { # one path segment: non-empty, without / [ ] | # : (they would break a wikilink or a path)
  if (n == "") return 0
  for (i = 1; i <= 6; i++) if (index(n, substr("/[]|#:", i, 1)) > 0) return 0
  return 1
}
# repo-relative path -> mirror wikilink target, or "" (any file name, e.g. with spaces or non-ASCII)
function km_map(p,    n, L) {
  L = length(p)
  if (L < 4 || substr(p, L - 2) != ".md") return ""
  if (p == "CONTEXT.md") return "docs/CONTEXT"
  if (substr(p, 1, 6) == "rules/") { n = substr(p, 7, L - 9); return km_okname(n) ? "rules/" n : "" }
  if (substr(p, 1, 9) == "docs/adr/") { n = substr(p, 10, L - 12); return km_okname(n) ? "adr/" n : "" }
  if (substr(p, 1, 28) == "docs/archive/rules-evidence/") { n = substr(p, 29, L - 31); return km_okname(n) ? "evidence/" n : "" }
  if (substr(p, 1, 5) == "docs/") { n = substr(p, 6, L - 8); return km_okname(n) ? "docs/" n : "" }
  if (substr(p, 1, 9) == "projects/") return km_proj(p)
  return ""
}
# c = text inside backticks (or a ledger file entry); returns a wikilink or ""
function km_ref(c,    p, i, suf, t, pre, k) {
  p = c
  split("~/.claude/ $HOME/.claude/ ${HOME}/.claude/", pre, " ")
  for (k = 1; k <= 3; k++) if (index(p, pre[k]) == 1) { p = substr(p, length(pre[k]) + 1); break }
  suf = ""
  i = match(p, /[:#]/)
  if (i > 0) {
    suf = substr(p, i); p = substr(p, 1, i - 1)
    if (suf !~ /^:[0-9]+(-[0-9]+)?$/ && suf !~ /^#/) return ""
  }
  t = km_map(p)
  if (t == "" || !((t ".md") in T)) return ""
  return "[[" t "]]" suf
}
# ledger file entry = a path, optionally followed by a note ("rules/x.md: why", "rules/x.md (new)"):
# link the leading path (the first ".md" that ends a mapped file), keep the rest as text
function km_lead(c,    off, rest, pos, end, d, r) {
  off = 0; rest = c
  while ((pos = index(rest, ".md")) > 0) {
    end = off + pos + 2
    d = substr(c, end + 1, 1)
    if (d == "" || index(" :#(,;", d) > 0) {
      r = km_ref(substr(c, 1, end))
      if (r != "") return r substr(c, end + 1)
    }
    off = end; rest = substr(c, off + 1)
  }
  return ""
}
# bare tokens: [[name]], [[name#heading]], [[name|alias]] of an existing rule become [[rules/name...]]
function km_bare(s,    out, rest, a, r2, e, tok, k, i, nm, lk)  {
  out = ""; rest = s
  while ((a = index(rest, "[[")) > 0) {
    r2 = substr(rest, a + 2); e = index(r2, "]]")
    if (e == 0) break
    tok = substr(r2, 1, e - 1)
    k = index(tok, "[")
    if (k > 0) { out = out substr(rest, 1, a + 1) substr(r2, 1, k - 1); rest = substr(r2, k); continue }
    i = match(tok, /[|#]/)
    nm = (i > 0) ? substr(tok, 1, i - 1) : tok
    out = out km_imp(substr(rest, 1, a - 1))
    if (nm != "" && index(nm, "/") == 0 && (lk = km_memlink(tok, nm)) != "") out = out lk # an ambiguous fold stays bare: no fall-through to a rule
    else if (nm != "" && index(nm, "/") == 0 && (("rules/" nm ".md") in T)) out = out "[[rules/" tok "]]"
    else out = out "[[" tok "]]"
    rest = substr(r2, e + 2)
  }
  return out km_imp(rest)
}
# inline code spans on one line (CommonMark): a run of n backticks opens a span that the
# next run of exactly n backticks closes; an unmatched run is literal text.
# km_close(rest, a, n): offset where the closing run starts, counted after the opening run, or 0
function km_close(rest, a, n,    tail, off, b, m) {
  tail = substr(rest, a + n); off = 0
  while ((b = index(tail, "`")) > 0) {
    m = 1; while (substr(tail, b + m, 1) == "`") m++
    if (m == n) return off + b
    off += b + m - 1; tail = substr(tail, b + m)
  }
  return 0
}
# strip=0: link a single-backtick span that names a mirrored path, km_bare on the prose
# between spans; span content is otherwise copied byte for byte. strip=1: every span becomes
# a blank (link counting must not see tokens quoted as code).
function km_spans(s, strip,    out, rest, a, n, cl, r, pre) {
  out = ""; rest = s
  while ((a = index(rest, "`")) > 0) {
    n = 1; while (substr(rest, a + n, 1) == "`") n++
    cl = km_close(rest, a, n); pre = substr(rest, 1, a - 1); if (!strip) pre = km_bare(pre)
    if (!cl) { out = out pre substr(rest, a, n); rest = substr(rest, a + n); continue }
    r = strip ? " " : ((n == 1) ? km_ref(substr(rest, a + 1, cl - 1)) : "")
    if (r == "") r = substr(rest, a, 2 * n + cl - 1)
    out = out pre r; rest = substr(rest, a + 2 * n + cl - 1)
  }
  return out (strip ? rest : km_bare(rest))
}
function km_rewrite(s) { return km_spans(km_mdl(s), 0) }
function km_prose(s) { return km_spans(s, 1) }
# fence state after line x (st = state before): 0 = prose, N >= 3 = inside a fence opened
# with N backticks, closed only by a line of >= N (CommonMark); prose = both states 0.
function km_fence(x, st,    t, r) {
  t = x; sub(/^[ \t]+/, "", t)
  if (st) { r = t; sub(/[ \t\r]+$/, "", r); return (r ~ /^`+$/ && length(r) >= st) ? 0 : st }
  if (substr(t, 1, 3) == "```") { r = t; sub(/^`+/, "", r); if (index(r, "`") == 0) return length(t) - length(r) }
  return 0
}
function km_dq(v,    i, c, o) { # YAML double-quoted scalar: backslash and double quote escaped
  o = ""
  for (i = 1; i <= length(v); i++) { c = substr(v, i, 1); if (c == "\\" || c == "\"") o = o "\\"; o = o c }
  return "\"" o "\""
}
function km_ticks(n,    s) { s = ""; while (n-- > 0) s = s "`"; return s }
function km_load(file,    ln) {
  while ((getline ln < file) > 0) T[ln] = 1
  close(file)
}
'
. "${BASH_SOURCE[0]%/*}/knowledge-mirror-imp.sh" # appends km_imp to KM_AWK_COMMON
. "${BASH_SOURCE[0]%/*}/knowledge-mirror-links.sh" # v3: link hygiene, link report, Mentions, graph export, generated dated keys

# Generated frontmatter keys are kind:, origin: and the dated keys (km_meta). Existing source
# keys stay byte-identical. A source that itself owns a top-level kind, origin, dated,
# dated_from or origin_session key keeps it: the generated key is omitted (a duplicate would be
# invalid YAML) and the copy path is appended to $KM_COLLIDE, which the caller reports as a warning.
KM_AWK_RENDER='
BEGIN {
  km_load(ENVIRON["KM_TARGETS"])
  ts = ENVIRON["KM_TSMAP"]
  while (ts != "" && (getline ln < ts) > 0) { split(ln, kv, "\t"); TS[kv[1]] = kv[2] }
  ts = ENVIRON["KM_METAMAP"]
  while (ts != "" && (getline ln < ts) > 0) { k = index(ln, "\t"); MT[substr(ln, 1, k - 1)] = substr(ln, k + 1) }
}
{ n++; L[n] = $0 }
END {
  rel = ENVIRON["KM_REL"]; ty = ENVIRON["KM_KIND"]; ins = (ENVIRON["KM_INS"] == "1")
  tsv = ENVIRON["KM_NOW"]
  if (ENVIRON["KM_FORCE"] != "1" && (rel in TS)) tsv = TS[rel]
  sd = ENVIRON["KM_SRC"]; h = ENVIRON["KM_HOME"]
  if (h != "" && index(sd, h "/") == 1) sd = "~" substr(sd, length(h) + 1)
  prov = ins ? "<!-- knowledge-mirror: copied from " sd " at " tsv "; read-only copy, edits are refused on the next run -->" : ENVIRON["KM_PROV"]
  first = L[1]; sub(/\r$/, "", first); close_at = 0
  if (n >= 1 && first == "---") for (i = 2; i <= n; i++) { x = L[i]; sub(/\r$/, "", x); if (x == "---") { close_at = i; break } }
  start = 1
  if (close_at) {
    cr = (L[1] ~ /\r$/) ? "\r" : ""
    print L[1]
    if (ins) {
      for (i = 2; i < close_at; i++) if (match(L[i], /^["\047]?(kind|origin|dated|dated_from|origin_session)["\047]?[ \t]*:/)) {
        owk = substr(L[i], 1, RLENGTH - 1); gsub(/["\047 \t]/, "", owk); OWN[owk] = 1
      }
      if (!("kind" in OWN)) print "kind: " ty cr
      if (!("origin" in OWN)) print "origin: " km_dq(sd) cr
      km_meta(rel, cr)
      for (owk in OWN) { if (ENVIRON["KM_COLLIDE"] != "") print rel >> ENVIRON["KM_COLLIDE"]; break }
    }
    for (i = 2; i <= close_at; i++) print L[i]
    print prov
    start = close_at + 1
  } else {
    print "---"; print "kind: " ty; print "origin: " km_dq(sd); km_meta(rel, ""); print "---"; print prov
  }
  st = 0
  for (i = start; i <= n; i++) {
    x = L[i]; ns = km_fence(x, st)
    if (st || ns) print x; else { NOIMP = (rel ~ /^ledger\// && !hd && x ~ /^# /); if (NOIMP) hd = 1; print km_rewrite(x) }
    st = ns
  }
  if (rel ~ /^rules\//) {
    b = rel; sub(/^rules\//, "", b); sub(/\.md$/, "", b)
    if (("evidence/" b ".md") in T) { if (st) print km_ticks(st); print ""; print "## Evidence"; print ""; print "[[evidence/" b "]]" } # st: a copy that ends inside a fence is closed first
  }
}
'

# km_render <rel> <src> <kind> <ins:1|0> <force-now:1|0> -> stdout.
# ins=1: source copy (kind:/origin: inserted or created); ins=0: generated note that
# already carries its frontmatter. Env contract: KM_TARGETS, KM_TSMAP, KM_NOW, KM_HOME,
# optional KM_COLLIDE (file collecting copies whose source owns kind:/origin:).
km_render() {
  KM_REL=$1 KM_SRC=$2 KM_KIND=$3 KM_INS=$4 KM_FORCE=$5 KM_PROV=$KM_LEDGER_PROV \
    LC_ALL=C awk "$KM_AWK_COMMON$KM_AWK_RENDER" "$2"
}

KM_JQ_DEFS='
def scoped: to_entries[] | if .key == "improvementQueue"
  then (.value | objects | to_entries[] | select(.key | startswith("priority_")) | .value | arrays | .[])
  else (.value | objects | .entries? | arrays | .[]) end;
def entries: [scoped | objects | select((.id | type) == "string" and (.id | startswith("IMP-")))]
  | reduce .[] as $e ({}; .[$e.id] = $e) | [.[]]
  | map(if (.id | test("^IMP-[A-Za-z0-9_-]+$")) then . else error("unsafe ledger id: \(.id)") end)
  | sort_by([((.id | ltrimstr("IMP-") | tonumber?) // 0), .id]);
def clean: if type == "string" then gsub("[\u001d\u001e\u001f]"; "") else . end;
def s: if . == null then "" elif type == "string" then . else tojson end | clean;
def one: s | gsub("[\r\n]+"; " ");
def yv: one | if test("^[A-Za-z0-9_./~+-][A-Za-z0-9_./:~+@-]*$") then . else tojson end;
def st: ((.status // "") | one) as $v | if $v == "" then "unknown" else $v end;
def kv($k; $v): if ($v | one) == "" then "" else "\($k): \($v | yv)\n" end;
def files: [(.filesModified, .filesCreated) | arrays | .[] | strings | one | select(. != "") | "\u001f\(.)\n"] | join("");
def verif: [(.verification | objects) as $v | ("kpi", "baseline", "target", "measured", "measuredAt", "note") as $k
  | select((($v[$k] | s) != "") and ($k != "note" or $keepnote == "0" or (($v[$k] | s | startswith("proposed entries carry no measurement")) | not)))
  | "- \($k): \($v[$k] | one)\n"] | join("");
'

KM_JQ_INDEX='
(.lastUpdated // "unknown") as $u | entries as $l
| "---", "kind: imp", "origin: \($src | tojson)", "---",
  $prov, "# Improvement ledger: \($l | length) entries, source lastUpdated \($u)", "",
  ($l[] | "- [[ledger/\(.id)]] · \(st) · \(.title | one)")
'

# measured: true only for a real value; null, false, "" and empty containers are "not measured"
KM_JQ_NOTES='
def has_value: . != null and . != false and . != "" and . != [] and . != {};
entries[]
| ([.verification | objects | .measured] | first | has_value) as $meas
| (.title | one) as $ti | verif as $vf
| "\u001e\(.id)\n---\nkind: imp\nid: \(.id | yv)\nledger_status: \(st | yv)\n"
  + kv("category"; .category) + kv("riskLevel"; .riskLevel) + "measured: \($meas)\n"
  + kv("proposedAt"; .proposedAt) + kv("implementedAt"; .implementedAt) + "origin: \($src | tojson)\n---\n"
  + "# \(.id)\(if $ti == "" then "" else " — " + $ti end)\n\n"
  + (if (.notes | s | gsub("\\s"; "") == "") then "" else "## Notes\n\n\(.notes | s)\n\u001d\n\n" end)
  + (if (.evidence | s | gsub("\\s"; "") == "") then "" else "## Evidence\n\n\(.evidence | s)\n\u001d\n\n" end)
  + (if files == "" then "" else "## Files\n\n\(files)\n" end)
  + (if $vf == "" then "" else "## Verification\n\n\($vf)" end)
'

KM_AWK_SPLIT='
BEGIN { km_load(ENVIRON["KM_TARGETS"]); dir = ENVIRON["KM_DIR"]; ids = ENVIRON["KM_IDS"] }
substr($0, 1, 1) == "\036" { if (f != "") close(f); id = substr($0, 2); f = dir "/" id ".md"; print id >> ids; fst = 0; next }
substr($0, 1, 1) == "\037" { p = substr($0, 2); r = km_lead(p); if (r != "") print "- " r > f; else print "- `" p "`" > f; next }
substr($0, 1, 1) == "\035" { if (fst) print km_ticks(fst > 10 ? fst : 10) > f; fst = 0; next } # end of notes/evidence: close a fence they left open
{ fst = km_fence($0, fst); print > f }
'

# km_ledger_build <ledger.json> <workdir> <targets-file>: writes <workdir>/ledger.md,
# <workdir>/ledger/<ID>.md and <workdir>/ledger-ids.txt (ids in index order).
# targets-file lists the mirror paths that will exist (Files links resolve against it).
km_ledger_build() {
  local json=$1 w=$2 targets=$3
  mkdir -p "$w/ledger"; : > "$w/ledger-ids.txt"
  if ! jq -r --arg keepnote "${KM_V3L:-1}" --arg prov "$KM_LEDGER_PROV" --arg src "$KM_LEDGER_DISP" "$KM_JQ_DEFS$KM_JQ_INDEX" "$json" > "$w/ledger.md" 2> "$w/jq.err"; then
    err "ledger JSON unreadable: $(tilde "$json"): $(head -n 1 "$w/jq.err")"
  fi
  if ! jq -j --arg keepnote "${KM_V3L:-1}" --arg src "$KM_LEDGER_DISP" "$KM_JQ_DEFS$KM_JQ_NOTES" "$json" 2> "$w/jq.err" \
    | KM_TARGETS=$targets KM_DIR=$w/ledger KM_IDS=$w/ledger-ids.txt LC_ALL=C awk "$KM_AWK_COMMON$KM_AWK_SPLIT"; then
    err "ledger notes could not be rendered: $(head -n 1 "$w/jq.err")"
  fi
}

# km_tsmap <mirror> <outfile>: "<rel>\t<timestamp>" per existing copy provenance comment.
km_tsmap() {
  : > "$2"
  [ -d "$1" ] || return 0
  ( cd "$1" && find . -type f -name '*.md' ! -path './.state/*' -print0 | xargs -0 -r awk '
      FNR <= 400 && !(FILENAME in seen) && /^<!-- knowledge-mirror: copied from .* at [0-9TZ:-]+; read-only copy/ {
        seen[FILENAME] = 1; ts = $0; sub(/^.* at /, "", ts); sub(/;.*$/, "", ts)
        f = FILENAME; sub(/^\.\//, "", f); print f "\t" ts }' ) > "$2"
}

# km_hash_rels <mirror> <listfile>: "<rel>\t<sha256>" per listed file (batched, one shasum per ~200 files).
km_hash_rels() {
  [ -s "$2" ] || return 0
  ( cd "$1" && tr '\n' '\0' < "$2" | xargs -0 shasum -a 256 ) | awk '{ h = $1; sub(/^[0-9a-f]+  \*?/, ""); print $0 "\t" h }'
}
