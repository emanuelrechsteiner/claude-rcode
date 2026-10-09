#!/usr/bin/env bash
# knowledge-lint.sh — read-only lint report over the knowledge mirror (plan O6, O4 item 4, O12, O8).
# A building inspection: it counts and names, it never edits. Exits 0 for every report, even with
# FAILs; exits 1 only for usage errors, an unreadable mirror, or a missing graph export when a
# graph query was requested. Needs CLAUDE_KNOWLEDGE_DIR (the library root holding mirror/).
set -uo pipefail

KL_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/knowledge-lint-checks.sh
. "$KL_SELF/lib/knowledge-lint-checks.sh"
# shellcheck source=lib/knowledge-lint-graph.sh
. "$KL_SELF/lib/knowledge-lint-graph.sh"

kl_help() {
  cat <<'EOF'
knowledge-lint.sh [--summary] [--contradictions] [--refs] [--orphans] [--superseded]
                  [--rules-without-evidence] [--help]
Read-only report over $CLAUDE_KNOWLEDGE_DIR/mirror. Env: CLAUDE_KNOWLEDGE_DIR (required).
Exit 0 for every report; exit 1 for usage/IO errors, a missing graph export or a failed step (LINT error).

Default: per-note lines "FAIL|WARN <code> <path>" (sorted by path), then LINT summary lines.
  --summary                only the LINT summary lines
Codes (memory copies; MEMORY.md indexes only get dangling; type = source frontmatter type:):
  desc      FAIL  no description:
  claim     WARN  first body line starts with a date, Status/Stand/State, or a narrative marker
  why       FAIL  no **Why:** (required for feedback and project; reference and user exempt)
  how       FAIL  no **How to apply:** (same exemption)
  date      FAIL  no ISO date in body/description/frontmatter (generated modified:/backfilled: ignored)
  size      FAIL  file over 8192 bytes
  dangling  FAIL  [[link]] outside code that matches no mirror file (ambiguous = WARN)
  status    FAIL  status: not active|superseded|archived, or superseded_by: names no mirror file
  status-form WARN superseded_by not a canonical mirror-relative path with .md (lookup normalises)
  type      WARN  no/unknown type: (treated as project)
  frontmatter FAIL missing or unclosed frontmatter; unreadable FAIL file not readable
Modes:
  --contradictions  CONTRADICTION <rule> <path-a> <path-b> <evidence>; rules: status (pending
                    vs done, same subject), dup-basename, abandoned (a lives in a folder b
                    declares abandoned), overtaken (a is called outdated by b)
  --refs            REFS kind=<k> (rule|doc|plan|imp|evidence|adr|logbook|memory) external=<n> dead=<n>
                    for backtick paths resolved against
                    ~/.claude, REFS dead <path> in <note>, REFS session present|missing|noid
                    (transcript existence only, contents never read)
  --orphans                 nodes without an inbound edge, grouped by kind (needs graph export);
                            mentions/same-day edges are not inbound; mentions_only = orphans that have such edges
  --superseded              nodes with status superseded and their superseded_by
  --rules-without-evidence  rules/*.md nodes with no outbound evidence edge
Graph queries read mirror/graph/nodes.tsv and edges.tsv (built by knowledge-mirror.sh v3).
EOF
}

kl_die() { echo "knowledge-lint: $*" >&2; exit 1; }
# kl_fail <mode>: a report step failed after it may have printed part of its output; never end in exit 0
kl_fail() { echo "LINT error $1 failed (partial or empty report above)" >&2; exit 1; }

# kl_refs <scratch>: classify backtick paths per kind against ~/.claude, then count sessions.
KL_AWK_REFS='
BEGIN {
  KMAP["rules"] = "rule"; KMAP["docs"] = "doc"; KMAP["plans"] = "plan"; KMAP["ledger"] = "imp" # folder -> graph kind
  while ((getline f < ENVIRON["KL_ALL"]) > 0) {
    nl = slurp(ENVIRON["KL_MIRROR"] "/" f); if (nl < 0) { print "knowledge-lint: unreadable " f > "/dev/stderr"; continue }
    kind = f; if (index(kind, "/") > 0) sub(/\/.*$/, "", kind); else sub(/\.md$/, "", kind)
    if (kind in KMAP) kind = KMAP[kind]
    fs = 0
    for (i = 1; i <= nl; i++) {
      ns = fence(L[i], fs); pr = (!fs && !ns); fs = ns; if (!pr) continue
      x = L[i]
      while ((a = index(x, "`")) > 0) {
        x = substr(x, a + 1); b = index(x, "`"); if (b == 0) break
        tok = substr(x, 1, b - 1); x = substr(x, b + 1); sub(/[ \t].*$/, "", tok)
        while (tok ~ /[.,:;)]$/) tok = substr(tok, 1, length(tok) - 1)
        if (tok ~ /^~\/\.claude\/[A-Za-z0-9._\/-]+$/) sub(/^~\/\.claude\//, "", tok)
        else if (tok !~ /^(rules|hooks|scripts|docs|commands|skills|templates)\/[A-Za-z0-9._\/-]+$/) continue
        print kind "\t" tok "\t" f
      }
    }
  }
}
'
kl_refs() {
  local s=$1 kind rel note sid p found present=0 missing=0 total home=${HOME:-}
  [ -n "$home" ] || kl_die "HOME is not set; --refs resolves paths against ~/.claude"
  LC_ALL=C awk "$KL_AWK_COMMON$KL_AWK_REFS" < /dev/null | LC_ALL=C sort -u > "$s/refs.tok" || return 1
  while IFS="$(printf '\t')" read -r kind rel note; do
    if [ -e "$home/.claude/$rel" ]; then printf '%s\t%s\t%s\texternal\n' "$kind" "$rel" "$note"
    else printf '%s\t%s\t%s\tdead\n' "$kind" "$rel" "$note"; fi
  done < "$s/refs.tok" > "$s/refs.cls" || return 1
  awk -F '\t' '!(($1 SUBSEP $2) in seen) { seen[$1 SUBSEP $2] = 1; c[$1 SUBSEP $4]++; k[$1] = 1 }
    $4 == "dead" { print "D\t" $2 "\t" $3 }
    END { for (x in k) printf "K\t%s\t%d\t%d\n", x, c[x SUBSEP "external"], c[x SUBSEP "dead"] }' "$s/refs.cls" \
    | LC_ALL=C sort > "$s/refs.agg" || return 1
  awk -F '\t' '$1 == "K" { printf "REFS kind=%s external=%d dead=%d\n", $2, $3, $4 }' "$s/refs.agg"
  awk -F '\t' '$1 == "D" { print "REFS dead " $2 " in " $3 }' "$s/refs.agg"
  # sessions: existence of ~/.claude/projects/*/<uuid>.jsonl by [ -e ]; transcript contents are never read
  grep -v '/MEMORY\.md$' "$KL_TODO" > "$s/notes.list"; total=$(wc -l < "$s/notes.list" | tr -d ' ')
  ( cd "$KL_MIRROR" && tr '\n' '\0' < "$s/notes.list" | xargs -0 awk '
      FNR == 1 { st = 0; got = 0 }
      /^---[ \t]*$/ { st++; next }
      st == 1 && !got && /^[ \t]*originSessionId:/ { v = $0; sub(/^[^:]*:[ \t]*/, "", v); gsub(/["\047 \t\r]/, "", v); print v; got = 1 }' ) > "$s/sess.ids" || return 1
  while IFS= read -r sid; do
    case "$sid" in ????????-????-????-????-????????????) ;; *) continue ;; esac
    found=0
    for p in "$home"/.claude/projects/*/"$sid".jsonl; do if [ -e "$p" ]; then found=1; break; fi; done
    if [ "$found" -eq 1 ]; then present=$((present + 1)); else missing=$((missing + 1)); fi
  done < "$s/sess.ids"
  echo "REFS session present=$present missing=$missing"
  echo "REFS session noid=$((total - present - missing)) of=$total"
}

SUMMARY=0; MODES=""
for arg in "$@"; do
  case "$arg" in
    --help|-h) kl_help; exit 0 ;;
    --summary) SUMMARY=1 ;;
    --contradictions|--refs) MODES="$MODES $arg" ;;
    --orphans|--superseded|--rules-without-evidence) MODES="$MODES $arg"; GRAPH=1 ;;
    *) echo "knowledge-lint: unknown argument: $arg (see --help)" >&2; exit 1 ;;
  esac
done
GRAPH=${GRAPH:-0}

[ -n "${CLAUDE_KNOWLEDGE_DIR:-}" ] || kl_die "CLAUDE_KNOWLEDGE_DIR is not set"
KL_MIRROR="${CLAUDE_KNOWLEDGE_DIR%/}/mirror"
[ -d "$KL_MIRROR" ] || kl_die "no mirror at $KL_MIRROR (run knowledge-mirror.sh first)"
[ -r "$KL_MIRROR" ] || kl_die "mirror not readable: $KL_MIRROR"
if [ "$GRAPH" -eq 1 ]; then kl_graph_require "$KL_MIRROR" || exit 1; fi

KL_SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/klint.XXXXXX") || kl_die "mktemp failed"
trap 'rm -rf "$KL_SCRATCH"' EXIT
( cd "$KL_MIRROR" && find . -type f -name '*.md' ! -path './.state/*' ) > "$KL_SCRATCH/raw.list" 2> "$KL_SCRATCH/find.err" \
  || kl_die "mirror unreadable: $(head -n 1 "$KL_SCRATCH/find.err")"
sed 's|^\./||' "$KL_SCRATCH/raw.list" | LC_ALL=C sort > "$KL_SCRATCH/all.list"
awk '/^memory\/[^\/]+\/[^\/]+\.md$/' "$KL_SCRATCH/all.list" > "$KL_SCRATCH/memory.list"
[ -s "$KL_SCRATCH/memory.list" ] || kl_die "no memory notes under $KL_MIRROR/memory"
export KL_MIRROR KL_ALL="$KL_SCRATCH/all.list" KL_TODO="$KL_SCRATCH/memory.list"

if [ -z "$MODES" ] || [ "$SUMMARY" -eq 1 ]; then kl_notes "$KL_SCRATCH" "$SUMMARY" || kl_fail "notes report"; fi
for mode in $MODES; do
  case "$mode" in
    --contradictions) kl_contradictions "$KL_SCRATCH" || kl_fail "$mode" ;;
    --refs) kl_refs "$KL_SCRATCH" || kl_fail "$mode" ;;
    --orphans) kl_graph_orphans "$KL_MIRROR" || kl_fail "$mode" ;;
    --superseded) kl_graph_superseded "$KL_MIRROR" || kl_fail "$mode" ;;
    --rules-without-evidence) kl_graph_rules_no_evidence "$KL_MIRROR" || kl_fail "$mode" ;;
  esac
done
exit 0
