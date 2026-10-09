#!/usr/bin/env bash
# shellcheck disable=SC2034 # KINDS PROJ PREFIX WORK MIRROR FILES are read by the sourced lib/knowledge-lookup-*.sh
# knowledge-lookup.sh - the agent's reach into the library: search the read-only
# knowledge mirror ($CLAUDE_KNOWLEDGE_DIR/mirror, built by knowledge-mirror.sh)
# for keywords, so cross-project memory, rules and logbook entries are found on
# demand instead of being loaded into every session (IMP-248, stage 2; v3 ranking).
# Reads the mirror; writes a private temp dir and one local usage log line (--no-log).
# Scoring/selection: lib/knowledge-lookup-rank.sh; output/log: lib/knowledge-lookup-fields.sh.
set -euo pipefail
case "${BASH_SOURCE[0]}" in */*) SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)" ;; *) SCRIPT_DIR="$(pwd)" ;; esac # no dirname: tests hide tools
for _lib in rank fields; do
  [ -r "$SCRIPT_DIR/lib/knowledge-lookup-$_lib.sh" ] || { echo "knowledge-lookup: missing $SCRIPT_DIR/lib/knowledge-lookup-$_lib.sh" >&2; exit 1; }
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/lib/knowledge-lookup-$_lib.sh"
done

usage() {
  cat <<'EOF'
Usage: bash knowledge-lookup.sh [--max N] [--kind K] [--project P] [--prefix] [--stack [DIR]]
                                [--alt "KEYWORDS"]... [--fuse best|rrf] [--no-log] [--help] [--] [KEYWORD ...]

Searches the knowledge mirror (BM25F-lite ranking). A KEYWORD matches a whole word,
case-insensitively; a quoted argument is ONE literal phrase. At least one keyword, --alt or
--stack is required.
  --max N         show the top N files (default 8)
  --kind K        only these kinds: memory rule evidence adr doc imp logbook plan index
                  (repeatable or comma-separated). Default: all but "index" (ledger.md)
  --project P     only memory notes whose project folder name contains P (case-insensitive)
  --prefix        a keyword also matches as a word prefix (hook finds hooks, zsh finds .zshrc)
  --stack [DIR]   derive up to 25 keywords from the project in DIR (default: the current
                  directory), printed as "keywords: ..." on stderr. DIR is the next argument
                  when it is an existing directory or has a "/"; --stack=DIR also works.
                  Reads package.json, Package.swift, requirements.txt, pyproject.toml,
                  Cargo.toml and go.mod.
  --alt "K1 K2"   one more keyword set (repeatable; split on whitespace, no phrases). All sets run in
                  one call and are fused (best rank in any set first); KEYWORD may then be empty
  --fuse M        best (default): order by best rank in any set, RRF sum breaks ties; rrf: pure reciprocal rank fusion
  --no-log        do not append to the usage log (also: KNOWLEDGE_LOOKUP_LOG=0)
  --help          this text
Scope: *.md under mirror/memory, rules, logbook, plans, evidence, adr, docs, ledger/.
Kind tag from the first path folder (rules -> rule, docs -> doc, plans -> plan, ledger/ ->
imp); the file ledger.md is tagged "index". Frontmatter: only name: and description: are
searched (x3, like the file name); kind:/origin:/ids and knowledge-mirror provenance lines
never match; text from a "## Mentions" line to the end is ignored. Headings count x2.
Collisions (lib/knowledge-lookup-collisions.tsv): "zustand" is case-sensitive, "immer" only
matches in code spans, fenced code and import lines. Applies to --stack keywords too.
Ranking: distinct keywords matched, then score; logbook x0.5; a superseded note follows
its successor. Output: "knowledge-lookup: <F> files match (<K> keywords) in <mirror>" (with --alt:
"(<K> keywords in <M> sets)"), per file "== <path>  [<matched>/<K>]  (<kind>)  ~<n> tok" (n =
bytes/4; best set; "sets=<m>" if m sets match), "   » <description>", up to 3 "   L<n> § <heading>:
<text>" lines (cut at 160 chars), then "... <M> more files (raise --max)". Exit codes: 0 ok (also
zero hits), 1 library not available, 2 usage error. Config: CLAUDE_KNOWLEDGE_DIR from the
environment, else from ~/.claude/env.local.sh. Usage log: <K>/eval/lookup-log.tsv (timestamp,
query = keywords + " || <alt set>" each, top3); a failed write only prints a NOTE.
Retrieval protocol: run 2-4 keyword sets in ONE call (first set positional, the rest --alt):
  the question's own words, its translation (German/English), the technical terms behind it.
  Judge by the "»" description lines;
  open only the top note's section (L<n>), not the whole file.
EOF
}

die_usage() { echo "knowledge-lookup: $1" >&2; usage >&2; exit 2; }
tilde() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }
dir_like() { [ -d "$1" ] || case "$1" in */*) return 0 ;; *) return 1 ;; esac; }

MAX=8; STACK=0; SDIR="."; EXPL=""; KINDS=""; PROJ=""; PREFIX=0; LOG=1; ALTS=""; NALT=0; FUSE=best
[ "${KNOWLEDGE_LOOKUP_LOG:-1}" != 0 ] || LOG=0
add_kw() { [ -n "$1" ] || die_usage "empty keyword"
  case "$1" in *$'\t'*|*$'\n'*) die_usage "a keyword may not contain a tab or newline" ;; esac; EXPL="$EXPL$1"$'\n'; }
add_alt() { local w; [ -n "$1" ] || die_usage "--alt needs a value"
  read -r -a w <<< "$1" # whitespace split, no globbing; tab/newline separate words too
  [ "${#w[@]}" -gt 0 ] || die_usage "--alt needs at least one keyword"
  ALTS="$ALTS${w[*]}"$'\n'; NALT=$((NALT + 1)); }
add_kind() { local k; [ -n "$1" ] || die_usage "--kind needs a value"
  for k in $(printf '%s' "$1" | tr ',' ' '); do
    case "$k" in memory|rule|evidence|adr|doc|imp|logbook|plan|index) KINDS="$KINDS,$k" ;; *) die_usage "unknown kind: $k" ;; esac
  done; }
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --max) [ $# -ge 2 ] || die_usage "--max needs a value"; MAX=$2; shift 2 ;;
    --max=*) MAX=${1#--max=}; shift ;;
    --kind) [ $# -ge 2 ] || die_usage "--kind needs a value"; add_kind "$2"; shift 2 ;;
    --kind=*) add_kind "${1#--kind=}"; shift ;;
    --project) [ $# -ge 2 ] || die_usage "--project needs a value"; PROJ=$2; shift 2 ;;
    --project=*) PROJ=${1#--project=}; shift ;;
    --alt) [ $# -ge 2 ] || die_usage "--alt needs a value"; add_alt "$2"; shift 2 ;;
    --alt=*) add_alt "${1#--alt=}"; shift ;;
    --fuse) [ $# -ge 2 ] || die_usage "--fuse needs a value"; FUSE=$2; shift 2 ;;
    --fuse=*) FUSE=${1#--fuse=}; shift ;;
    --prefix) PREFIX=1; shift ;;
    --no-log) LOG=0; shift ;;
    --stack=*) STACK=1; SDIR=${1#--stack=}; shift ;;
    --stack) STACK=1; shift
      if [ $# -gt 0 ] && dir_like "$1"; then SDIR=$1; shift; fi ;;
    --) shift; for a in "$@"; do add_kw "$a"; done; break ;;
    -*) die_usage "unknown option: $1" ;;
    *) add_kw "$1"; shift ;;
  esac
done
KINDS="${KINDS#,}"
case "$FUSE" in best|rrf) ;; *) die_usage "--fuse needs best or rrf" ;; esac
case "$MAX" in ''|*[!0-9]*) die_usage "--max needs a positive integer" ;; esac
MAX=$((10#$MAX)); [ "$MAX" -ge 1 ] || die_usage "--max needs a positive integer"
[ -n "$EXPL" ] || [ "$STACK" -eq 1 ] || [ "$NALT" -gt 0 ] || die_usage "at least one keyword, --alt or --stack is required"

# Config precedence: environment first, then ~/.claude/env.local.sh (subshell, -u/-e off).
KDIR=${CLAUDE_KNOWLEDGE_DIR:-}
if [ -z "$KDIR" ] && [ -f "$HOME/.claude/env.local.sh" ]; then
  # shellcheck disable=SC1091 # env.local.sh is machine-local, absent at lint time
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
    [ -n "$EXPL" ] || [ "$NALT" -gt 0 ] || exit 2
  fi
fi

# ---- search: one scan per keyword set (primary = positional + stack; then each --alt), fused ----
kl_collect
RK=(); NSET_KW=""; M=0; NS=0
: > "$WORK/allkw.txt"
run_set() { # <raw keyword file>: dedupe, spec, scan -> ranked.<i>.tsv; skips an empty set
  local i=$NS
  awk '{ k = tolower($0) } !s[k]++ { print k }' "$1" > "$WORK/kw.$i.txt"
  [ -s "$WORK/kw.$i.txt" ] || return 0
  kl_kwspec "$WORK/kw.$i.txt" "$SCRIPT_DIR/lib/knowledge-lookup-collisions.tsv" "$WORK/kw.$i.spec"
  : > "$WORK/ranked.$i.tsv"
  if [ "${#FILES[@]}" -gt 0 ]; then kl_rank "$WORK/kw.$i.spec" "$WORK/ranked.$i.tsv"; fi
  cat "$WORK/kw.$i.txt" >> "$WORK/allkw.txt"
  NSET_KW="$NSET_KW$(wc -l < "$WORK/kw.$i.txt" | tr -d ' ') "; RK+=("$WORK/ranked.$i.tsv"); M=$((M + 1))
}
run_set "$WORK/kw.raw"
while IFS= read -r alt; do
  [ -n "$alt" ] || continue
  NS=$((NS + 1)); printf '%s\n' "$alt" | tr ' ' '\n' > "$WORK/alt.$NS.raw"; run_set "$WORK/alt.$NS.raw"
done <<< "$ALTS"
K=$(sort -u "$WORK/allkw.txt" | wc -l | tr -d ' ')
FUSED="$WORK/fused.tsv"; : > "$FUSED"
if [ "$M" -gt 1 ]; then kl_fuse "$FUSE" "$NSET_KW" "${RK[@]}" > "$FUSED"; elif [ "$M" -eq 1 ]; then FUSED=${RK[0]}; fi
kl_supersede < "$FUSED" > "$WORK/ranked.tsv"

F=$(wc -l < "$WORK/ranked.tsv" | tr -d ' ')
if [ "$NALT" -gt 0 ]; then KDESC="$K keywords in $M sets"; else KDESC="$K keywords"; fi
echo "knowledge-lookup: $F files match ($KDESC) in $(tilde "$MIRROR")"
if [ "$F" -gt 0 ]; then
  head -n "$MAX" "$WORK/ranked.tsv" | kl_format "$K"
  if [ "$F" -gt "$MAX" ]; then echo "... $((F - MAX)) more files (raise --max)"; fi
fi
if [ "$LOG" -eq 1 ]; then
  LQ=$(tr '\n' ' ' < "$WORK/kw.raw"); LQ=${LQ% }
  while IFS= read -r alt; do [ -z "$alt" ] || LQ="$LQ || $alt"; done <<< "$ALTS"
  kl_log "$KDIR/eval" "$LQ" "$WORK/ranked.tsv"
fi
