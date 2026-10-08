#!/usr/bin/env bash
# knowledge-lookup.sh - the agent's reach into the library: search the read-only
# knowledge mirror ($CLAUDE_KNOWLEDGE_DIR/mirror, built by knowledge-mirror.sh)
# for keywords, so cross-project memory, rules and logbook entries are found on
# demand instead of being loaded into every session (IMP-248, stage 2).
# Read-only: writes nothing but a private temp dir. Run with --help for usage.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash knowledge-lookup.sh [--max N] [--stack [DIR]] [--help] [KEYWORD ...]

Searches the knowledge mirror for lines matching KEYWORDs (case-insensitive,
fixed-string, one grep per keyword). At least one keyword or --stack is required.

  --max N         show the top N files (default 12)
  --stack [DIR]   derive up to 25 keywords from the project in DIR (default: the
                  current directory) and print them as "keywords: ..." on stderr.
                  DIR is taken from the next argument when that is an existing
                  directory or contains a "/"; --stack=DIR also works. Reads
                  package.json (dependencies, devDependencies), Package.swift
                  (.package name/url/path, .product name/package), requirements.txt,
                  pyproject.toml ([project] dependencies), Cargo.toml
                  ([dependencies]) and go.mod (require, last path segment).
  --help          this text

Scope: *.md under mirror/memory, mirror/rules, mirror/logbook, mirror/plans, plus
mirror/ledger.md. Frontmatter and knowledge-mirror provenance lines never match.
Ranking: distinct keywords matched (desc), matching lines (desc), path (asc).

Output (stdout): "knowledge-lookup: <F> files match (<K> keywords) in <mirror>",
then per top file "== <path>  [<matched>/<K>]" and up to 3 "<line>: <text>" lines
(text cut at 160 chars), then "... <M> more files (raise --max)" if truncated.

Configuration: CLAUDE_KNOWLEDGE_DIR from the environment, else from
~/.claude/env.local.sh (sourced in a subshell; the environment wins).
Exit codes: 0 ok (also zero hits), 1 library not available, 2 usage error.
EOF
}

die_usage() { echo "knowledge-lookup: $1" >&2; usage >&2; exit 2; }
tilde() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }
dir_like() { [ -d "$1" ] || case "$1" in */*) return 0 ;; *) return 1 ;; esac; }

MAX=12; STACK=0; SDIR="."; EXPL=""
add_kw() { [ -n "$1" ] || die_usage "empty keyword"; EXPL="$EXPL$1"$'\n'; }
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --max) [ $# -ge 2 ] || die_usage "--max needs a value"; MAX=$2; shift 2 ;;
    --max=*) MAX=${1#--max=}; shift ;;
    --stack=*) STACK=1; SDIR=${1#--stack=}; shift ;;
    --stack) STACK=1; shift
      if [ $# -gt 0 ] && dir_like "$1"; then SDIR=$1; shift; fi ;;
    --) shift; for a in "$@"; do add_kw "$a"; done; break ;;
    -*) die_usage "unknown option: $1" ;;
    *) add_kw "$1"; shift ;;
  esac
done
case "$MAX" in ''|*[!0-9]*) die_usage "--max needs a positive integer" ;; esac
MAX=$((10#$MAX)); [ "$MAX" -ge 1 ] || die_usage "--max needs a positive integer"
[ -n "$EXPL" ] || [ "$STACK" -eq 1 ] || die_usage "at least one keyword or --stack is required"

# Config precedence: environment first, then ~/.claude/env.local.sh (subshell, -u/-e off).
KDIR=${CLAUDE_KNOWLEDGE_DIR:-}
if [ -z "$KDIR" ] && [ -f "$HOME/.claude/env.local.sh" ]; then
  # shellcheck disable=SC1091
  KDIR=$( set +u +e; . "$HOME/.claude/env.local.sh" >/dev/null 2>&1; printf '%s' "${CLAUDE_KNOWLEDGE_DIR:-}" ) || KDIR=""
fi
while [ "${KDIR%/}" != "$KDIR" ] && [ -n "${KDIR%/}" ]; do KDIR=${KDIR%/}; done
MIRROR="$KDIR/mirror"
if [ -z "$KDIR" ] || [ ! -d "$MIRROR" ]; then
  echo "knowledge-lookup: library not available (CLAUDE_KNOWLEDGE_DIR unset or ${KDIR:-<dir>}/mirror missing); run scripts/knowledge-mirror.sh first" >&2
  exit 1
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/knowledge-lookup.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# ---- stack detection: candidate names, one per line --------------------------
stack_names() {
  local d=$1 f
  f="$d/package.json"
  if [ -f "$f" ]; then
    if command -v jq >/dev/null 2>&1; then
      jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys_unsorted[]' "$f" \
        || echo "knowledge-lookup: warning: cannot parse $f" >&2
    else # no jq: scan the dependency objects with awk
      awk '{ l = $0
        while (1) {
          if (!inb) { if (!match(l, /"(dependencies|devDependencies)"[ \t]*:[ \t]*\{/)) break
                      l = substr(l, RSTART + RLENGTH); inb = 1 }
          e = index(l, "}"); s = (e ? substr(l, 1, e - 1) : l)
          while (match(s, /"[^"]*"[ \t]*:/)) { k = substr(s, RSTART + 1); sub(/".*/, "", k); print k; s = substr(s, RSTART + RLENGTH) }
          if (e) { inb = 0; l = substr(l, e + 1) } else break
        } }' "$f"
    fi
  fi
  f="$d/Package.swift"
  if [ -f "$f" ]; then
    sed 's|^[[:space:]]*//.*||' "$f" | tr '\n' ' ' | awk '
      function q(s, re,  t) { if (!match(s, re)) return ""; t = substr(s, RSTART, RLENGTH); sub(/^[^"]*"/, "", t); sub(/".*$/, "", t); return t } # re is a STRING (a /re/ literal would match $0)
      function seg(u) { if (u == "") return ""; sub(/\/+$/, "", u); sub(/\.git$/, "", u); n = split(u, a, "/"); return a[n] }
      function out(x) { if (x != "") print x }
      { s = $0
        while (match(s, /\.package\([^)]*/)) { d = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
          out(q(d, "name:[ \t]*\"[^\"]*\"")); out(seg(q(d, "url:[ \t]*\"[^\"]*\""))); out(seg(q(d, "path:[ \t]*\"[^\"]*\""))) }
        s = $0
        while (match(s, /\.product\([^)]*/)) { d = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
          out(q(d, "name:[ \t]*\"[^\"]*\"")); out(q(d, "package:[ \t]*\"[^\"]*\"")) } }'
  fi
  f="$d/requirements.txt"
  if [ -f "$f" ]; then
    awk '{ l = $0; sub(/\r$/, "", l); sub(/#.*/, "", l); sub(/^[ \t]+/, "", l)
      if (l == "" || l ~ /^-/ || l ~ /:\/\// || l ~ /\//) next   # options, URLs, local paths (./pkg, /abs, pkg @ ./x)
      sub(/[ \t;<>=!~@\[(].*$/, "", l); if (l != "") print l }' "$f"
  fi
  f="$d/pyproject.toml"
  if [ -f "$f" ]; then
    awk '/^\[/ { sec = $0; sub(/[ \t]*(#.*)?$/, "", sec); arr = 0 }
      sec == "[project]" { l = $0
        if (!arr) { if (l !~ /^dependencies[ \t]*=/) next; sub(/^dependencies[ \t]*=[ \t]*/, "", l); arr = 1 }
        while (match(l, /"[^"]*"/)) {
          if (substr(l, 1, RSTART - 1) ~ /\]/) { arr = 0; break }
          t = substr(l, RSTART + 1, RLENGTH - 2); sub(/[^A-Za-z0-9._-].*$/, "", t); if (t != "") print t
          l = substr(l, RSTART + RLENGTH) }
        if (arr && l ~ /\]/) arr = 0 }' "$f"
  fi
  f="$d/Cargo.toml"
  if [ -f "$f" ]; then
    awk '/^\[/ { sec = $0; sub(/[ \t]*(#.*)?$/, "", sec)
        if (sec ~ /^\[dependencies\./) { t = sec; sub(/^\[dependencies\./, "", t); sub(/\].*$/, "", t); print t } next }
      sec == "[dependencies]" && /^[A-Za-z0-9_-]+[ \t.]*[=.]/ { t = $0; sub(/[ \t.=].*$/, "", t); print t }' "$f"
  fi
  f="$d/go.mod"
  if [ -f "$f" ]; then
    awk '/^require[ \t]*\(/ { blk = 1; next } blk && /^\)/ { blk = 0; next }
      { m = ""; if (blk) m = $1; else if ($1 == "require") m = $2
        if (m == "" || m ~ /^\/\//) next
        sub(/\/v[0-9]+$/, "", m); n = split(m, a, "/"); print a[n] }' "$f"
  fi
}

# ---- keyword list: explicit first, then stack; deduplicated, lowercased stack ----
printf '%s' "$EXPL" > "$WORK/kw.raw"
if [ "$STACK" -eq 1 ]; then
  [ -d "$SDIR" ] || die_usage "--stack: not a directory: $SDIR"
  # 25 cap inside awk (drains its input): a trailing `head -n 25` could SIGPIPE under pipefail (141)
  stack_names "$SDIR" | tr '[:upper:]' '[:lower:]' | awk 'NF && !s[$0]++ { if (++n <= 25) print }' > "$WORK/stack.txt"
  if [ -s "$WORK/stack.txt" ]; then
    echo "keywords: $(tr '\n' ' ' < "$WORK/stack.txt" | sed 's/ $//')" >&2
    cat "$WORK/stack.txt" >> "$WORK/kw.raw"
  else
    echo "knowledge-lookup: no stack keywords found in $SDIR" >&2
    [ -n "$EXPL" ] || exit 2
  fi
fi
awk '{ k = tolower($0) } !s[k]++' "$WORK/kw.raw" > "$WORK/kw.txt"
K=$(wc -l < "$WORK/kw.txt" | tr -d ' ')

# ---- search: one grep per keyword over the in-scope files ----------------------
FILES=()
{ for sub in memory rules logbook plans; do
    if [ -d "$MIRROR/$sub" ]; then find "$MIRROR/$sub" -type f -name '*.md' -print0; fi
  done
  if [ -f "$MIRROR/ledger.md" ] && [ ! -L "$MIRROR/ledger.md" ]; then printf '%s\0' "$MIRROR/ledger.md"; fi
} > "$WORK/files0"
while IFS= read -r -d '' f; do FILES+=("$f"); done < "$WORK/files0"
: > "$WORK/ranked.tsv"
if [ "${#FILES[@]}" -gt 0 ]; then
  # frontmatter end line per file (only when it is closed): matches up to there are ignored
  awk 'FNR == 1 { fm = ($0 ~ /^---\r?$/) } fm && FNR > 1 && /^---\r?$/ { print FILENAME "\t" FNR; fm = 0 }' \
    "${FILES[@]}" > "$WORK/fm.tsv"
  mkdir "$WORK/m"; i=0
  while IFS= read -r kw; do
    i=$((i + 1)); rc=0
    grep -a -i -F -n -H -e "$kw" -- "${FILES[@]}" > "$WORK/m/$i" || rc=$?
    [ "$rc" -le 1 ] || { echo "knowledge-lookup: grep failed (exit $rc) for keyword '$kw'" >&2; exit 1; }
  done < "$WORK/kw.txt"
  TAB=$(printf '\t')
  awk -F "$TAB" -v mp="$MIRROR/" '
    FILENAME == ARGV[1] { fm[substr($1, length(mp) + 1)] = $2 + 0; next }
    { idx = FILENAME; sub(/^.*\//, "", idx)
      r = substr($0, length(mp) + 1)
      if (!match(r, /:[0-9]+:/)) next
      path = substr(r, 1, RSTART - 1); ln = substr(r, RSTART + 1, RLENGTH - 2) + 0; tx = substr(r, RSTART + RLENGTH)
      if (ln <= fm[path] || tx ~ /knowledge-mirror: (copied|rendered) from/) next
      if (!((path, idx) in kh)) { kh[path, idx] = 1; dist[path]++ }
      if ((path, ln) in seen) next
      seen[path, ln] = 1; cnt[path]++
      c = nt[path]
      if (c < 3) { c++; nt[path] = c; tl[path, c] = ln; tt[path, c] = tx; j = c }
      else if (ln < tl[path, 3]) { tl[path, 3] = ln; tt[path, 3] = tx; j = 3 } else next
      while (j > 1 && tl[path, j - 1] > tl[path, j]) {
        a = tl[path, j - 1]; tl[path, j - 1] = tl[path, j]; tl[path, j] = a
        a = tt[path, j - 1]; tt[path, j - 1] = tt[path, j]; tt[path, j] = a; j-- } }
    END { for (p in dist) { printf "%d\t%d\t%s", dist[p], cnt[p], p
        for (c = 1; c <= nt[p]; c++) { t = tt[p, c]; gsub(/[\t\r]/, " ", t); gsub(/^ +| +$/, "", t); printf "\t%d: %s", tl[p, c], t }
        printf "\n" } }' "$WORK/fm.tsv" "$WORK"/m/* | LC_ALL=C sort -t "$TAB" -k1,1nr -k2,2nr -k3,3 > "$WORK/ranked.tsv"
fi

F=$(wc -l < "$WORK/ranked.tsv" | tr -d ' ')
echo "knowledge-lookup: $F files match ($K keywords) in $(tilde "$MIRROR")"
if [ "$F" -gt 0 ]; then
  # The 160-character cut happens here, for the shown files only. awk may count BYTES
  # (macOS awk 20200816 does, whatever the locale): then walk lead bytes and keep
  # every continuation byte (0x80-0xBF) of the last kept character. No iconv: its -c
  # exits non-zero on a cut sequence and set -e/pipefail would kill the run.
  head -n "$MAX" "$WORK/ranked.tsv" | awk -F '\t' -v k="$K" '
    function cut(t,  i, n, len, c) {
      if (!bytemode) return substr(t, 1, 160)
      t = substr(t, 1, 640); len = length(t); n = 0
      for (i = 1; i <= len; i++) { c = substr(t, i, 1)
        if (!(c in cont)) { if (n == 160) break; n++ } }
      return substr(t, 1, i - 1) }
    BEGIN { bytemode = (length("\303\244") == 2)
            if (bytemode) for (i = 128; i <= 191; i++) cont[sprintf("%c", i)] = 1 }
    { printf "== %s  [%d/%d]\n", $3, $1, k
      for (i = 4; i <= NF; i++) { p = index($i, ": "); printf "%s%s\n", substr($i, 1, p + 1), cut(substr($i, p + 2)) } }'
  if [ "$F" -gt "$MAX" ]; then echo "... $((F - MAX)) more files (raise --max)"; fi
fi
