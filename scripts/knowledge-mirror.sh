#!/usr/bin/env bash
# knowledge-mirror.sh - copy an ALLOWLISTED set of distilled-knowledge Markdown
# files from the live install (~/.claude) into a machine-local knowledge folder
# <K> (= $CLAUDE_KNOWLEDGE_DIR), so <K> can be opened in Obsidian without
# Obsidian ever writing into a file the framework reads (IMP-248, stage 2a).
#
# Contract in short (run with --help for the full usage block):
#   * Sources (nothing else): logbook/*.md, projects/*/memory/*.md,
#     plans/meta-proposal-*.md, rules/*.md without *.local.md, and the
#     improvement ledger rendered to one line per id. Hard excludes after
#     globbing: *.local.md, any /vault/ path, *.jsonl.
#   * Writes only under <K>/mirror/ (plus an empty <K>/notes/ for the owner).
#   * Refuses (exit 1) on an unsafe target (inside OR containing ~/.claude or the
#     workshop) and on any symlink under <K>/mirror; refuses (exit 3) to
#     overwrite a copy that was edited by hand. Never deletes anything.
#   * <K> must NOT sit under iCloud/Dropbox/Obsidian Sync or any synced folder
#     (memory files, private project names); NOT checked here, see --help.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash knowledge-mirror.sh [--dry-run] [--help]

Copies an allowlisted set of distilled-knowledge Markdown files from ~/.claude
into $CLAUDE_KNOWLEDGE_DIR (<K>) so <K> can be opened in Obsidian. The framework
never reads <K>; Obsidian never writes into ~/.claude.

Configuration: CLAUDE_KNOWLEDGE_DIR, an absolute path with no default. If unset,
~/.claude/env.local.sh is sourced when it exists. Optional CLAUDE_BAUHOF_ROOT
(the workshop) is only used for the refusal check.

<K> must be outside ~/.claude and the workshop (checked: refused if <K> equals,
sits inside, or contains either). <K> must NOT be under iCloud Drive, Dropbox,
Obsidian Sync or any other synced folder: the mirror holds memory files and
private project names, and a sync service would upload them. This script does
NOT check that; keeping <K> out of synced folders is your responsibility.

Mirrored (read from ~/.claude, never written):
  logbook/*.md                  -> <K>/mirror/logbook/
  projects/*/memory/*.md        -> <K>/mirror/memory/<project-dir>/
  plans/meta-proposal-*.md      -> <K>/mirror/plans/
  rules/*.md (no *.local.md)    -> <K>/mirror/rules/
  global-observation/improvement-ledger.json -> <K>/mirror/ledger.md
Hard excludes, applied after globbing: *.local.md, /vault/ paths, *.jsonl.

Each copy gets one HTML provenance comment (after a leading frontmatter block,
else as line 1). <K>/mirror/.state/hashes.tsv records each written copy's
sha256; a later run exits 3 and overwrites nothing if any recorded copy was
edited by hand. Your own notes go in <K>/notes/ (created, never touched).
Unchanged copies are not rewritten; stale copies are listed (stale:), not deleted.
ledger.md has its comment as line 1 and no timestamp (idempotent).

Refusals (exit 1, "knowledge-mirror: refuse:"): target unset/empty, not absolute,
equal to, inside or containing ~/.claude or CLAUDE_BAUHOF_ROOT, or named "vault";
any symlink under <K>/mirror.
--dry-run prints "<target> <- <source>" per file, then TOTAL and CHANGED, and
writes nothing. A real run prints TOTAL and CHANGED after writing.
Exit codes: 0 ok, 1 refusal or error, 2 bad usage, 3 hand-edited copy.
EOF
}

DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "knowledge-mirror: unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

err() { echo "knowledge-mirror: $1" >&2; exit 1; }
refuse() { echo "knowledge-mirror: refuse: $1" >&2; exit 1; }
tilde() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }
strip_slash() { local p=$1; while [ "${p%/}" != "$p" ] && [ -n "${p%/}" ]; do p=${p%/}; done; printf '%s' "$p"; }

command -v jq >/dev/null || err "jq is required but not installed."
command -v shasum >/dev/null || err "shasum is required but not installed."

# Config precedence (same pattern as deploy-to-live.sh): environment first, then
# ~/.claude/env.local.sh, then fail loud. The file is sourced in a subshell with
# -u/-e off, so it can neither abort this script nor override an already-set value.
BAUHOF=${CLAUDE_BAUHOF_ROOT:-}; KENV=${CLAUDE_KNOWLEDGE_DIR:-}; ENVNOTE=""
if { [ -z "$KENV" ] || [ -z "$BAUHOF" ]; } && [ -f "$HOME/.claude/env.local.sh" ]; then
  # shellcheck disable=SC1091
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
    # shellcheck disable=SC2088
    if [ "$root" = "$HOME/.claude" ]; then lbl='~/.claude'; else lbl=workshop; fi
    refuse "target contains a protected root ($lbl)"
  fi
done
MIRROR="$K/mirror"
STATE="$MIRROR/.state/hashes.tsv"
[ ! -L "$MIRROR" ] || refuse "$MIRROR is a symlink"
nolink() { [ ! -L "$1" ] || refuse "symlink inside mirror/: $1"; } # a link would redirect our writes
if [ -d "$MIRROR" ]; then # also in --dry-run: any link under mirror/ is refused before any write
  LINKS=$(find "$MIRROR" -type l)
  [ -z "$LINKS" ] || refuse "symlink inside mirror/: ${LINKS%%$'\n'*}"
fi
SRC="$HOME/.claude"
TAB=$(printf '\t')
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/knowledge-mirror.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
PLAN="$WORK/plan.tsv"; : > "$PLAN"
# ---- plan: allowlist globbing, then hard excludes ---------------------------
# Notes are buffered and printed after a successful run (a refusal is always the
# first stderr line). Excluded paths are counted, never named.
pending() { echo "knowledge-mirror: $1" >> "$WORK/notes.txt"; }
if [ -n "$ENVNOTE" ]; then pending "$ENVNOTE"; fi
if [ -z "$BAUHOF" ]; then pending "note: CLAUDE_BAUHOF_ROOT is not set, workshop refusal check skipped"; fi
EXCL=0
consider() { # rel-target src
  local rel=$1 src=$2 within=${2#"$SRC"/}
  case "/$within" in
    *.local.md|*.jsonl|*/vault/*) EXCL=$((EXCL + 1)); return 0 ;;
  esac
  if [ -L "$src" ]; then pending "skip symlink: $within"; return 0; fi
  printf '%s\t%s\tcopy\n' "$rel" "$src" >> "$PLAN"
}
need_dir() { [ -d "$SRC/$1" ] || { pending "skip: source dir missing: ~/.claude/$1"; return 1; }; }

if need_dir logbook; then
  for f in "$SRC"/logbook/*.md; do [ -f "$f" ] && consider "logbook/$(basename "$f")" "$f"; done
fi
if need_dir projects; then
  for d in "$SRC"/projects/*/memory; do
    [ -d "$d" ] || continue
    proj=$(basename "$(dirname "$d")")
    for f in "$d"/*.md; do [ -f "$f" ] && consider "memory/$proj/$(basename "$f")" "$f"; done
  done
fi
if need_dir plans; then
  for f in "$SRC"/plans/meta-proposal-*.md; do [ -f "$f" ] && consider "plans/$(basename "$f")" "$f"; done
fi
if need_dir rules; then
  for f in "$SRC"/rules/*.md; do [ -f "$f" ] && consider "rules/$(basename "$f")" "$f"; done
fi
LEDGER="$SRC/global-observation/improvement-ledger.json"
if [ -f "$LEDGER" ]; then
  # Every object with an IMP-* id, any depth; last occurrence in document order wins.
  if ! jq -r '(.lastUpdated // "unknown") as $u
    | [.. | objects | select((.id | type) == "string" and (.id | startswith("IMP-")))]
    | reduce .[] as $e ({}; .[$e.id] = $e) | [.[]]
    | sort_by([((.id | ltrimstr("IMP-") | tonumber?) // 0), .id]) as $l
    | "<!-- knowledge-mirror: rendered from ~/.claude/global-observation/improvement-ledger.json; read-only copy, edits are refused on the next run -->",
      "# Improvement ledger: \($l | length) entries, source lastUpdated \($u)", "",
      ($l[] | "- \(.id) · \(.status // "unknown") · \((.title // "") | tostring | gsub("[\r\n]+"; " "))")
  ' "$LEDGER" > "$WORK/ledger.md" 2> "$WORK/jq.err"; then
    err "ledger JSON unreadable: $(tilde "$LEDGER"): $(head -n 1 "$WORK/jq.err")"
  fi
  printf 'ledger.md\t%s\tledger\n' "$LEDGER" >> "$PLAN"
else
  pending "skip: source missing: ~/.claude/global-observation/improvement-ledger.json"
fi

# ---- drift check: ALL recorded hashes before ANY write -----------------------
sha() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
DRIFT="$WORK/drift.txt"; : > "$DRIFT"
if [ -f "$STATE" ]; then
  while IFS="$TAB" read -r rel hash; do
    [ -n "$rel" ] || continue
    case "/$rel/" in /*/../*|//*) err "corrupt state file (bad path '$rel'): $STATE" ;; esac
    if [ -f "$MIRROR/$rel" ] && [ "$(sha "$MIRROR/$rel")" != "$hash" ]; then
      echo "$MIRROR/$rel" >> "$DRIFT"
    fi
  done < "$STATE"
fi
if [ -s "$DRIFT" ]; then
  { echo "knowledge-mirror: refuse: hand-edited copy:"; cat "$DRIFT"
    echo "hint: if the previous run was interrupted, delete $STATE and rerun (hand edits are then overwritten)"; } >&2
  exit 3
fi

# ---- render + compare + write ------------------------------------------------
provenance() { printf '<!-- knowledge-mirror: copied from %s at %s; read-only copy, edits are refused on the next run -->' "$(tilde "$1")" "$2"; }
render() { # src ts -> stdout: copy with the provenance comment after any frontmatter
  local c; c=$(provenance "$1" "$2")
  if [ ! -s "$1" ]; then printf '%s\n' "$c"; return 0; fi
  C="$c" awk '
    FNR == NR { l = $0; sub(/\r$/, "", l); if (FNR == 1 && l == "---") fm = 1; else if (fm && !close_at && l == "---") close_at = FNR; next }
    FNR == 1 && !close_at { print ENVIRON["C"] }
    { print }
    FNR == close_at { print ENVIRON["C"] }
  ' "$1" "$1"
}
old_ts() { head -n 20 "$1" | sed -n 's/^.*<!-- knowledge-mirror: copied from .* at \([0-9TZ:-]*\); read-only copy.*$/\1/p' | head -n 1; }

[ "$DRY" -eq 1 ] || { mkdir -p "$MIRROR/.state" "$K/notes"; }
TOTAL=0; CHANGED=0; NEWSTATE="$WORK/state.tsv"; : > "$NEWSTATE"
while IFS="$TAB" read -r rel src kind; do
  dst="$MIRROR/$rel"; out="$WORK/out.tmp"; ts=$NOW; TOTAL=$((TOTAL + 1))
  if [ "$kind" = ledger ]; then cp "$WORK/ledger.md" "$out"
  else
    if [ -f "$dst" ] && [ -n "$(old_ts "$dst")" ]; then ts=$(old_ts "$dst"); fi
    render "$src" "$ts" > "$out"
  fi
  if [ -f "$dst" ] && cmp -s "$out" "$dst"; then :
  else
    CHANGED=$((CHANGED + 1))
    if [ "$kind" = copy ] && [ "$ts" != "$NOW" ]; then render "$src" "$NOW" > "$out"; fi
    if [ "$DRY" -eq 0 ]; then nolink "$dst"; nolink "$dst.tmp"; mkdir -p "$(dirname "$dst")"; cp "$out" "$dst.tmp" && mv "$dst.tmp" "$dst"; fi
  fi
  if [ "$DRY" -eq 1 ]; then echo "mirror/$rel <- $(tilde "$src")"; else printf '%s\t%s\n' "$rel" "$(sha "$dst")" >> "$NEWSTATE"; fi
done < "$PLAN"

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
  sort "$NEWSTATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
  cnt() { awk -F "$TAB" -v p="$1" 'index($1, p) == 1 { n++ } END { print n + 0 }' "$PLAN"; }
  cat > "$MIRROR/README.md" <<EOF
# Knowledge mirror

Read-only copies of distilled knowledge from the Claude Code install, written by
scripts/knowledge-mirror.sh. Last run: $NOW (UTC).

- logbook: $(cnt logbook/) files
- memory: $(cnt memory/) files
- plans (meta-proposals): $(cnt plans/) files
- rules (tracked only): $(cnt rules/) files
- ledger.md: $(cnt ledger.md) file

Do not edit under mirror/: the next run refuses to overwrite hand-edited copies
and the script owns this folder. Your notes go in ../notes/.
EOF
fi
[ "$EXCL" -eq 0 ] || pending "hard-excluded $EXCL path(s) (see --help)"
[ ! -f "$WORK/notes.txt" ] || cat "$WORK/notes.txt" >&2
echo "TOTAL $TOTAL"
echo "CHANGED $CHANGED"
