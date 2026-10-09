#!/usr/bin/env bash
# knowledge-mirror.sh - copy an ALLOWLISTED set of distilled-knowledge Markdown
# files from the live install (~/.claude) into a machine-local knowledge folder
# <K> (= $CLAUDE_KNOWLEDGE_DIR), so <K> can be opened in Obsidian without
# Obsidian ever writing into a file the framework reads (IMP-248, stage 2a).
#
# v2 (justification graph): claims (rules, memory, ADRs) link to their grounds
# (evidence, ledger entries, files changed) and every copy declares its kind. All
# structure is generated INTO the copies before hashing, so drift detection keeps
# working; sources are never modified. Graph logic: scripts/lib/knowledge-mirror-graph.sh.
# --help (scripts/lib/knowledge-mirror-help.sh) has the contract: sources, refusals, exit codes and
# the synced-folder warning (<K> must NOT sit under a synced folder; NOT checked here).
# Writes only under <K>/mirror/ plus an empty <K>/notes/.
set -euo pipefail

LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
LIB="$LIBDIR/knowledge-mirror-graph.sh"
usage() { # the text lives in lib/knowledge-mirror-help.sh, loaded on demand
  [ -r "$LIBDIR/knowledge-mirror-help.sh" ] || { echo "knowledge-mirror: help library unavailable: $LIBDIR/knowledge-mirror-help.sh" >&2; return 1; }
  # shellcheck disable=SC1091 # computed path, checked above
  . "$LIBDIR/knowledge-mirror-help.sh"; km_usage
}
DRY=0; CHECK=0; export KM_V3L=1
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --check-links) CHECK=1 ;;
    --no-v3-links) KM_V3L=0 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "knowledge-mirror: unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

err() { echo "knowledge-mirror: $1" >&2; exit 1; }
refuse() { echo "knowledge-mirror: refuse: $1" >&2; exit 1; }
tilde() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }
strip_slash() { local p=$1; while [ "${p%/}" != "$p" ] && [ -n "${p%/}" ]; do p=${p%/}; done; printf '%s' "$p"; }

# Config precedence (same pattern as deploy-to-live.sh): environment first, then
# ~/.claude/env.local.sh, then fail loud. The file is sourced in a subshell with
# -u/-e off, so it can neither abort this script nor override an already-set value.
BAUHOF=${CLAUDE_BAUHOF_ROOT:-}; KENV=${CLAUDE_KNOWLEDGE_DIR:-}; ENVNOTE=""
if { [ -z "$KENV" ] || [ -z "$BAUHOF" ]; } && [ -f "$HOME/.claude/env.local.sh" ]; then
  # shellcheck disable=SC1091 # env.local.sh is machine-local, absent at lint time
  ENVOUT=$( set +u +e
    . "$HOME/.claude/env.local.sh" >/dev/null 2>&1; rc=$?
    printf '%s\n%s\n%s\nEND\n' "$rc" "${CLAUDE_KNOWLEDGE_DIR:-}" "${CLAUDE_BAUHOF_ROOT:-}" ) || ENVOUT=""
  eo() { printf '%s\n' "$ENVOUT" | sed -n "${1}p"; }
  if [ "$(eo 1)" != 0 ] || [ "$(eo 4)" != END ]; then ENVNOTE="note: could not source ~/.claude/env.local.sh"; fi
  if [ -z "$KENV" ]; then KENV=$(eo 2); fi
  if [ -z "$BAUHOF" ]; then BAUHOF=$(eo 3); fi
fi
physical() { # symlink-resolved form of an absolute path (deepest existing dir resolved)
  local p=$1 rest="" r
  while [ ! -d "$p" ] && [ "$p" != "/" ]; do rest="/$(basename "$p")$rest"; p=$(dirname "$p"); done
  r=$(cd "$p" && pwd -P)
  if [ "$r" = "/" ]; then r=""; fi
  printf '%s%s' "$r" "$rest"
}
inside() { local b=${2%/}; case "$1/" in "$b"/*) return 0 ;; esac; return 1; } # $1 equal to or below $2
K=$(strip_slash "$KENV")
[ -n "$K" ] || refuse "CLAUDE_KNOWLEDGE_DIR is unset or empty (set it in the environment or in ~/.claude/env.local.sh)${ENVNOTE:+; $ENVNOTE}"
case "$K" in /*) ;; *) refuse "CLAUDE_KNOWLEDGE_DIR is not an absolute path: $K" ;; esac
case "/$K/" in */../*|*/./*) refuse "CLAUDE_KNOWLEDGE_DIR contains a '.' or '..' component: $K" ;; esac
KP=$(physical "$K")
[ "$(basename "$K")" != "vault" ] && [ "$(basename "$KP")" != "vault" ] \
  || refuse "target is named 'vault' (that name is the PII pseudonym store): $K"
for root in "$HOME/.claude" "$BAUHOF"; do
  [ -n "$root" ] || continue
  root=$(strip_slash "$root"); rp=$(physical "$root")
  if inside "$K" "$root" || inside "$KP" "$root" || inside "$K" "$rp" || inside "$KP" "$rp"; then
    refuse "target is equal to or inside a protected root ($(tilde "$root")): $K"
  fi
  if inside "$root" "$K" || inside "$root" "$KP" || inside "$rp" "$K" || inside "$rp" "$KP"; then
    # shellcheck disable=SC2088 # the tilde is a literal display label, never to be expanded
    if [ "$root" = "$HOME/.claude" ]; then lbl='~/.claude'; else lbl=workshop; fi
    refuse "target contains a protected root ($lbl)"
  fi
done
MIRROR="$K/mirror"
STATE="$MIRROR/.state/hashes.tsv"
[ ! -L "$MIRROR" ] || refuse "$MIRROR is a symlink"
nolink() { [ ! -L "$1" ] || refuse "symlink inside mirror/: $1"; } # a link would redirect our writes
if [ "$CHECK" -eq 0 ] && [ -d "$MIRROR" ]; then # also in --dry-run: any link under mirror/ is refused before any write (--check-links writes nothing and never follows links)
  LINKS=$(find "$MIRROR" -type l)
  [ -z "$LINKS" ] || refuse "symlink inside mirror/: ${LINKS%%$'\n'*}"
fi
[ -r "$LIB" ] || err "library unavailable: $LIB"
# shellcheck disable=SC1090 # $LIB is a computed path (checked separately as its own file)
. "$LIB"
SRC="$HOME/.claude"
TAB=$(printf '\t')
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/knowledge-mirror.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
if [ "$CHECK" -eq 1 ]; then km_check_links "$MIRROR" 1 "$WORK" || exit 1; exit 0; fi
command -v jq >/dev/null || err "jq is required but not installed."
command -v shasum >/dev/null || err "shasum is required but not installed."
PLAN="$WORK/plan.tsv"; : > "$PLAN"
# ---- plan: allowlist globbing, then hard excludes ---------------------------
# Notes are buffered and printed after a successful run (a refusal is always the first stderr line). Excluded paths are counted, never named.
pending() { echo "knowledge-mirror: $1" >> "$WORK/notes.txt"; }
if [ -n "$ENVNOTE" ]; then pending "$ENVNOTE"; fi
if [ -z "$BAUHOF" ]; then pending "note: CLAUDE_BAUHOF_ROOT is not set, workshop refusal check skipped"; fi
EXCL=0
consider() { # rel-target src kind
  local rel=$1 src=$2 within=${2#"$SRC"/}
  case "/$within" in *.local.md|*.jsonl|*/vault/*) EXCL=$((EXCL + 1)); return 0 ;; esac
  if [ -L "$src" ]; then pending "skip symlink: $within"; return 0; fi
  printf '%s\t%s\tcopy\t%s\n' "$rel" "$src" "$3" >> "$PLAN" # columns: target, source, mode (copy|ledger|lnote), kind
}
need_dir() { [ -d "$SRC/$1" ] || { pending "skip: source dir missing: ~/.claude/$1"; return 1; }; }
# plan_glob <source dir> <glob> <target prefix> <kind>: flat *.md directory -> mirror folder
plan_glob() { local f; for f in "$SRC/$1"/$2; do [ -f "$f" ] && consider "$3${f##*/}" "$f" "$4"; done; return 0; }

if need_dir logbook; then plan_glob logbook '*.md' logbook/ logbook; fi
if need_dir projects; then
  for d in "$SRC"/projects/*/memory; do
    [ -d "$d" ] || continue
    proj=$(basename "$(dirname "$d")")
    for f in "$d"/*.md; do
      if [ -f "$f" ]; then consider "memory/$proj/${f##*/}" "$f" memory; fi # no `[ ] && cmd`: a false test must not become the loop status (bash 3.2 + set -e)
    done
  done
fi
if need_dir plans; then plan_glob plans 'meta-proposal-*.md' plans/ plan; fi
if need_dir rules; then plan_glob rules '*.md' rules/ rule; fi
if need_dir docs/archive/rules-evidence; then plan_glob docs/archive/rules-evidence '*.md' evidence/ evidence; fi
if need_dir docs/adr; then plan_glob docs/adr '*.md' adr/ adr; fi
if need_dir docs; then
  if [ -f "$SRC/CONTEXT.md" ] && [ -f "$SRC/docs/CONTEXT.md" ]; then
    pending "note: both CONTEXT.md and docs/CONTEXT.md exist; CONTEXT.md wins the target docs/CONTEXT.md"
    ctx_dup=1
  fi
  for f in "$SRC"/docs/*.md; do
    [ -f "$f" ] || continue
    if [ "${ctx_dup:-0}" = 1 ] && [ "${f##*/}" = CONTEXT.md ]; then continue; fi
    consider "docs/${f##*/}" "$f" doc
  done
fi
if [ -f "$SRC/CONTEXT.md" ]; then consider docs/CONTEXT.md "$SRC/CONTEXT.md" doc
else pending "skip: source missing: ~/.claude/CONTEXT.md"; fi
cut -f 1 "$PLAN" > "$WORK/targets.txt"
LEDGER="$SRC/global-observation/improvement-ledger.json"
if [ -f "$LEDGER" ]; then
  # IMP-* entries of <batch>.entries and improvementQueue.priority_* only (a nested
  # reference object never counts); last occurrence in document order wins.
  km_ledger_build "$LEDGER" "$WORK" "$WORK/targets.txt"
  printf 'ledger.md\t%s\tledger\timp\n' "$LEDGER" >> "$PLAN"
  while IFS= read -r id; do printf 'ledger/%s.md\t%s\tlnote\timp\n' "$id" "$LEDGER" >> "$PLAN"; done < "$WORK/ledger-ids.txt"
else pending "skip: source missing: ~/.claude/global-observation/improvement-ledger.json"; fi
cut -f 1 "$PLAN" > "$WORK/targets.txt"
COLLIDE="$WORK/collide.txt"; : > "$COLLIDE"
export KM_TARGETS="$WORK/targets.txt" KM_TSMAP="$WORK/tsmap.tsv" KM_NOW="$NOW" KM_HOME="$HOME" KM_COLLIDE="$COLLIDE"

# ---- drift check: ALL recorded hashes before ANY write -----------------------
DRIFT="$WORK/drift.txt"; : > "$DRIFT"
if [ -f "$STATE" ]; then
  while IFS="$TAB" read -r rel _; do # recorded copies that still exist (hashed in batches below)
    [ -n "$rel" ] || continue
    case "/$rel/" in /*/../*|//*) err "corrupt state file (bad path '$rel'): $STATE" ;; esac
    if [ -f "$MIRROR/$rel" ]; then echo "$rel"; fi
  done < "$STATE" > "$WORK/state-rels.txt"
  km_hash_rels "$MIRROR" "$WORK/state-rels.txt" > "$WORK/state-cur.tsv" || err "could not hash existing mirror copies"
  M="$MIRROR" awk -F "$TAB" 'NR == FNR { cur[$1] = $2; next } ($1 in cur) && cur[$1] != $2 { print ENVIRON["M"] "/" $1 }' \
    "$WORK/state-cur.tsv" "$STATE" > "$DRIFT"
fi
if [ -s "$DRIFT" ]; then
  { echo "knowledge-mirror: refuse: hand-edited copy:"; cat "$DRIFT"
    echo "hint: if the previous run was interrupted, delete $STATE and rerun (hand edits are then overwritten)"; } >&2
  exit 3
fi

# ---- render + compare + write ------------------------------------------------
km_tsmap "$MIRROR" "$KM_TSMAP" # timestamps of existing provenance comments: an unchanged copy keeps its stamp
km_meta_build "$PLAN" "$WORK" "$SRC"; km_stage "$PLAN" "$WORK" # dated keys, then one render into a stage (Mentions come from its edges)

[ "$DRY" -eq 1 ] || { mkdir -p "$MIRROR/.state" "$K/notes"; }
TOTAL=0; CHANGED=0; NEWSTATE="$WORK/state.tsv"; : > "$NEWSTATE"
while IFS="$TAB" read -r rel src mode kind; do
  dst="$MIRROR/$rel"; out="$WORK/out.tmp"; TOTAL=$((TOTAL + 1)); fnow=0
  if [ ! -f "$dst" ]; then fnow=1; fi # new copy: one render (in the stage), stamped now
  km_one "$rel" "$src" "$kind" 0 > "$out"
  if [ "$fnow" -eq 0 ] && cmp -s "$out" "$dst"; then :
  else
    CHANGED=$((CHANGED + 1))
    if [ "$mode" = copy ] && [ "$fnow" -eq 0 ]; then km_one "$rel" "$src" "$kind" 1 > "$out"; fi # content changed: stamp now
    if [ "$DRY" -eq 0 ]; then
      nolink "$dst"; nolink "$dst.tmp"
      [ -d "${dst%/*}" ] || mkdir -p "${dst%/*}"
      cp "$out" "$dst.tmp" || err "could not write the mirror copy: $rel"
      mv "$dst.tmp" "$dst" || err "could not replace the mirror copy: $rel"
    fi
  fi
  if [ "$DRY" -eq 1 ]; then
    case "$src" in "$HOME"/*) shown="~${src#"$HOME"}" ;; *) shown=$src ;; esac
    echo "mirror/$rel <- $shown"
  fi
done < "$PLAN"
if [ "$DRY" -eq 0 ]; then
  km_hash_rels "$MIRROR" "$WORK/targets.txt" > "$NEWSTATE" || err "could not hash the written mirror copies"
fi

# ---- stale copies: listed, never removed ------------------------------------
cut -f 1 "$PLAN" | sort > "$WORK/planned.txt"
STALE="$WORK/stale.txt"; : > "$STALE"
if [ -d "$MIRROR" ]; then
  find "$MIRROR" -type f -name '*.md' ! -path "$MIRROR/.state/*" ! -path "$MIRROR/README.md" \
    | sed "s|^$MIRROR/||" | sort | comm -23 - "$WORK/planned.txt" > "$STALE"
  while IFS= read -r rel; do echo "stale: $rel" >&2; done < "$STALE"
fi

if [ "$DRY" -eq 0 ]; then
  if [ -f "$STATE" ] && [ -s "$STALE" ]; then # keep recorded hashes of stale copies so edits stay detected
    awk -F "$TAB" 'NR == FNR { s[$0] = 1; next } ($1 in s)' "$STALE" "$STATE" >> "$NEWSTATE"
  fi
  nolink "$STATE"; nolink "$STATE.tmp"; nolink "$MIRROR/README.md"
  sort "$NEWSTATE" > "$STATE.tmp" || err "could not write the state file: $STATE.tmp"
  mv "$STATE.tmp" "$STATE" || err "could not replace the state file: $STATE"
  cnt() { awk -F "$TAB" -v p="$1" 'index($1, p) == 1 { n++ } END { print n + 0 }' "$PLAN"; }
  cat > "$MIRROR/README.md" <<EOF
# Knowledge mirror

Read-only copies of distilled knowledge from the Claude Code install, written by
scripts/knowledge-mirror.sh. Last run: $NOW (UTC).

- logbook: $(cnt logbook/) files
- memory: $(cnt memory/) files
- plans (meta-proposals): $(cnt plans/) files
- rules (tracked only): $(cnt rules/) files
- evidence: $(cnt evidence/) files
- adr: $(cnt adr/) files
- docs: $(cnt docs/) files
- ledger notes: $(cnt ledger/) files
- ledger.md: $(cnt ledger.md) file

Do not edit under mirror/: the next run refuses to overwrite hand-edited copies
and the script owns this folder. Your notes go in ../notes/.
EOF
fi
# a source owning a generated key (kind, origin, dated, dated_from, origin_session) keeps it; the generated one is omitted: loud, not fatal
sort -u "$COLLIDE" | while IFS= read -r rel; do pending "warning: source owns a generated key (the source key is kept, the generated one is omitted): $rel"; done
[ "$EXCL" -eq 0 ] || pending "hard-excluded $EXCL path(s) (see --help)"
[ ! -f "$WORK/notes.txt" ] || cat "$WORK/notes.txt" >&2
echo "TOTAL $TOTAL"
echo "CHANGED $CHANGED"
if [ "$DRY" -eq 0 ]; then km_check_links "$MIRROR" 0 "$WORK"; km_graph_export "$MIRROR" "$WORK"; fi # fail-loud signal: the graph decays
