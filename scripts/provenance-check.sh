#!/usr/bin/env bash
# provenance-check.sh — third-party provenance gate (P-IMP-262; ledger id IMP-262,
# to be confirmed by the Lead).
#
# Why: upstream material adapted into this repo (mattpocock/skills, MIT, IMP-124)
# shipped in the public v1.8.0 release without its license text, and only the
# owner caught it (2026-10-27). IMP-259 fixed that one case; this gate turns the
# next such omission into a publish failure instead of a human finding.
#
# Usage:
#   scripts/provenance-check.sh [--root <dir>] [--notices <file>] [--all-files]
#
#   --root <dir>     tree to scan (default: this repo). A git work tree is scanned
#                    by its tracked files (git ls-files -z); any other directory is
#                    scanned by every regular file.
#   --notices <file> notices file (default: skills/THIRD-PARTY-NOTICES.md). A
#                    relative path resolves against --root.
#   --all-files      scan every regular file under --root even when --root is a git
#                    work tree. publish.sh passes it: the ephemeral staging index
#                    only holds files that were not git-ignored, so a git-ignored
#                    file tracked in HEAD would otherwise be skipped silently.
#
# Marker lines (a line with at least one of):
#   Origin:                      case-sensitive (lowercase origin: is a YAML key
#                                of the knowledge mirror, not provenance)
#   adapted from                 any case
#   a license in license shape   (MIT)  (MIT, Copyright  (MIT License  (BSD-3-Clause)
#                                (Apache License, (GPL-2.0, and bare Apache-2.0,
#                                BSD-3-Clause, GPLv2. Prose such as "(BSD grep" is not.
#
# Upstream name of a marker line, first rule that yields one:
#   1. the token after "Origin:" or "adapted from"; leading spaces and [ ` " are
#      skipped (so a markdown link [owner/repo](url) yields owner/repo); the token
#      is the run of [A-Za-z0-9._/-] with trailing . / - removed. A token that is a
#      local file name or a ledger id (IMP-n, P-IMP-n) is an internal reference: it
#      never names the upstream, and the rest of the line is still searched (2., 3.).
#      A line whose only name is internal, with no external name and no license, is
#      not a marker at all.
#   2. else the first owner/repo token on the line (host prefixes github.com,
#      gitlab.com, bitbucket.org, codeberg.org and www. are stripped; file-like
#      tokens are skipped)
#   3. else the word directly before the license marker
#   4. else "(unnamed)", which is always a miss
# License kind of a line: MIT, APACHE (Apache-2.0), OTHER (BSD/GPL/LGPL), NONE.
#
# Annotations (explicit, per marker line; purpose: a mention of a third-party tool or
# of the project's own former license is not an adoption, so it must not need a notice):
#   [provenance: not-adopted]   the named upstream is a candidate or a mention, nothing
#                               from it is in this repo
#   [provenance: own]           the marker names this project's own former license or work
# REGISTERED ONLY: an annotation counts only when its file is listed in the section
# "## Non-adoptions (provenance annotations)" of the notices file, one line per file and
# token (a file with two tokens needs two lines): "- <repo-relative path> — <token> —
# <one-line reason> — <date>". Any other annotated line is reported as
# "UNREGISTERED ANNOTATION <file>:<line>" (exit 2) and suppresses nothing. The registry
# lives in the notices file, which is not scanned for markers, so a file cannot register
# or hide its own marker.
# SAME-LINE ONLY: a registered marker line is skipped only when that very line carries
# the token. A token on the line before or after a marker does NOT apply (so a
# neighbouring annotation can never hide a real adoption). Skipped hits are not reported;
# they are counted as "N annotated (registered)" in the summary, so they stay visible. A
# registered token is a recorded human decision, not a waiver: anywhere a marker is an
# adoption, it must have a notice section instead.
#
# Coverage: an upstream is covered by a level-2 section ("## ...", running to the
# next "#" or "##" heading) that NAMES it: the upstream as a whole word in the
# heading or body (case-insensitive), or, for owner/repo, the repo part as a whole
# word in the heading. The section must contain a Copyright line, and then:
#   MIT on any marker line   -> "Permission is hereby granted"
#   APACHE on any marker line -> "Licensed under the Apache License"
#   otherwise                -> at least 10 non-empty body lines
# A level-1 section ("# ...") never covers; a hint is printed when one names it.
#
# Output: MISSING <upstream> ← <file>:<line>  (<reason>), one line per upstream;
#         UNREGISTERED ANNOTATION <file>:<line>  (<reason>), one line per such line.
# Exit: 0 clean; 2 at least one MISSING or UNREGISTERED ANNOTATION; 1 usage error or
# unreadable input.
#
# Not scanned: the notices file, CHANGELOG.md, global-observation/, docs/archive/,
# *.json, and this gate's own two files (their header and fixtures necessarily
# spell the markers).
#
# bash 3.2 / BSD awk compatible (no mapfile, no associative arrays, no gensub).
set -uo pipefail

die() { echo "provenance-check: $1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
NOTICES=""
ALL_FILES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)      [ $# -ge 2 ] || die "--root needs a directory"; ROOT="$2"; shift 2 ;;
    --notices)   [ $# -ge 2 ] || die "--notices needs a file"; NOTICES="$2"; shift 2 ;;
    --all-files) ALL_FILES=1; shift ;;
    -h|--help)   sed -n '2,/^set -uo/{/^set -uo/d;p;}' "$0"; exit 0 ;;
    *)           die "unknown argument: $1 (see --help)" ;;
  esac
done

[ -d "$ROOT" ] || die "root is not a directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd -P)"
case "$NOTICES" in
  "")  NOTICES_ABS="$ROOT/skills/THIRD-PARTY-NOTICES.md" ;;
  /*)  NOTICES_ABS="$NOTICES" ;;
  *)   NOTICES_ABS="$ROOT/$NOTICES" ;;
esac
NOTICES_REL=""
case "$NOTICES_ABS" in "$ROOT"/*) NOTICES_REL="${NOTICES_ABS#"$ROOT"/}" ;; esac

# Marker regex (grep -E). Licenses only count in license-shaped form: "(MIT)",
# "(MIT, Copyright", "(MIT License", "(BSD-3-Clause)". Prose such as "(BSD grep",
# "(BSD-only", "(BSD date" is not a license marker (measured 2026-10-31: 9 false hits).
MARKER_RE='Origin:|[Aa][Dd][Aa][Pp][Tt][Ee][Dd] [Ff][Rr][Oo][Mm]|[(](MIT|Apache|BSD|GPL|LGPL)([,)]|[ -]License)|Apache-2[.]0|BSD-[0-9]-Clause|L?GPL-?v?[0-9]'

# Annotation token (see header). Matched per file by grep -n, like MARKER_RE.
ANNOT_RE='\[provenance: (not-adopted|own)\]'

# Registry (see header): the only section of the notices file whose rows register
# annotations. Its heading must match exactly.
NOTICES_SECTION="## Non-adoptions (provenance annotations)"
# One TSV row per registration line: path <TAB> token. Other lines are ignored.
REGISTRY_PROG='
BEGIN { insec = 0 }
/^## / { insec = (index($0, SEC) == 1 && length($0) == length(SEC)); next }
/^# /  { insec = 0; next }
insec && /^- / {
  n = split(substr($0, 3), f, " — ")
  path = f[1]; tok = f[2]
  gsub(/^ +| +$/, "", path); gsub(/^ +| +$/, "", tok)
  if (n >= 4 && path != "" && (tok == "[provenance: not-adopted]" || tok == "[provenance: own]"))
    printf "%s\t%s\n", path, tok
}
'

# Extraction: one grep -n line per marker line in, one TSV row out:
# upstream <TAB> kind <TAB> file <TAB> line.
EXTRACT_PROG='
function token_at(s,   t) {
  sub(/^[ \t\[`"]+/, "", s)
  if (match(s, /^[A-Za-z0-9._\/-]+/) == 0) return ""
  t = substr(s, 1, RLENGTH)
  sub(/[.\/-]+$/, "", t)
  return t
}
# A name that points at a local file or a ledger id is an internal reference, not an
# upstream: "adapted from gateguard.sh" (own hook), "Origin: IMP-161" (own ledger).
function internal(t) {
  return (t ~ /^(P-)?IMP-[0-9]+$/ || t ~ /\.(sh|md|py|js|ts|mjs|json|txt|swift|ya?ml|plist|template|tsv|jsonl)$/)
}
function owner_repo(s,   t) {
  while (match(s, /[A-Za-z0-9._\/-]+/) > 0) {
    t = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
    sub(/^\/+/, "", t)
    sub(/^(www\.)?(github\.com|gitlab\.com|bitbucket\.org|codeberg\.org)\//, "", t)
    sub(/[.\/-]+$/, "", t)
    if (t ~ /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/ && !internal(t)) return t
  }
  return ""
}
function word_before(s) {
  sub(/[ \t:,(\[`"*]+$/, "", s)
  if (match(s, /[A-Za-z0-9._-]+$/) == 0) return ""
  return substr(s, RSTART, RLENGTH)
}
{
  cut = index($0, ":"); ln = substr($0, 1, cut - 1); txt = substr($0, cut + 1)
  lic = match(txt, /[(](MIT|Apache|BSD|GPL|LGPL)([,)]|[ -]License)|Apache-2[.]0|BSD-[0-9]-Clause|L?GPL-?v?[0-9]/)
  p = index(txt, "Origin:"); w = 7
  if (p == 0) { p = match(tolower(txt), /adapted from/); w = 12 }
  up = ""; from_internal = 0
  if (p > 0) {
    up = token_at(substr(txt, p + w))
    if (internal(up)) { from_internal = 1; up = "" }
  }
  if (up == "") up = owner_repo(txt)
  if (up == "" && lic > 0) {
    up = word_before(substr(txt, 1, lic - 1))
    if (from_internal && internal(up)) up = ""
  }
  if (up == "" && from_internal) next
  if (up == "") up = "(unnamed)"
  if (txt ~ /(^|[^A-Za-z])MIT([^A-Za-z]|$)/) k = "MIT"
  else if (txt ~ /Apache/) k = "APACHE"
  else if (txt ~ /(BSD|GPL|LGPL)/) k = "OTHER"
  else k = "NONE"
  printf "%s\t%s\t%s\t%s\n", up, k, REL, ln
}
'

# Coverage check: reads the TSV, parses the notices file in BEGIN, prints MISSING lines.
CHECK_PROG='
BEGIN {
  FS = "\t"; nsec = 0; cur = 0
  while ((getline line < NOTICES) > 0) {
    if (line ~ /^## /) { nsec++; lvl[nsec] = 2; head[nsec] = tolower(line); body[nsec] = ""; nlines[nsec] = 0; cur = nsec }
    else if (line ~ /^# /) { nsec++; lvl[nsec] = 1; head[nsec] = tolower(line); body[nsec] = ""; nlines[nsec] = 0; cur = nsec }
    else if (cur > 0) { body[cur] = body[cur] "\n" tolower(line); if (line ~ /[^ \t]/) nlines[cur]++ }
  }
  close(NOTICES)
}
function has_word(hay, w,   base, pos, at, rest, b, c, L) {
  L = length(w); if (L == 0) return 0
  base = 0; rest = hay
  while ((pos = index(rest, w)) > 0) {
    at = base + pos
    b = (at > 1) ? substr(hay, at - 1, 1) : ""
    c = substr(hay, at + L, 1)
    if (b !~ /[a-z0-9]/ && c !~ /[a-z0-9]/) return 1
    base = at; rest = substr(hay, base + 1)
  }
  return 0
}
function names(i, uL, repo) {
  if (has_word(head[i], uL) || has_word(body[i], uL)) return 1
  return (repo != "" && has_word(head[i], repo))
}
function section_fail(i, u,   b) {
  b = body[i]
  if (b !~ /copyright/) return "section has no Copyright line"
  if (mit[u] && index(b, "permission is hereby granted") == 0) return "section lacks the MIT license text"
  if (apa[u] && index(b, "licensed under the apache license") == 0) return "section lacks the Apache-2.0 license text"
  if (!mit[u] && !apa[u] && nlines[i] < 10) return "section has fewer than 10 body lines"
  return ""
}
function check_upstream(u,   uL, repo, i, r, reason, hint, p) {
  uL = tolower(u); repo = ""; p = index(uL, "/")
  if (p > 0) repo = substr(uL, p + 1)
  reason = ""; hint = ""
  for (i = 1; i <= nsec; i++) {
    if (!names(i, uL, repo)) continue
    if (lvl[i] != 2) { hint = "named only under a level-1 heading; a ## section is required"; continue }
    r = section_fail(i, u)
    if (r == "") return ""
    if (reason == "") reason = r
  }
  if (reason != "") return reason
  if (hint != "") return hint
  return "no ## section names it"
}
{
  u = $1
  if (!(u in seen)) { seen[u] = 1; order[++nup] = u; first[u] = $3 ":" $4; mit[u] = 0; apa[u] = 0 }
  if ($2 == "MIT") mit[u] = 1
  else if ($2 == "APACHE") apa[u] = 1
}
END {
  for (j = 1; j <= nup; j++) {
    u = order[j]
    if (u == "(unnamed)") { print "MISSING (unnamed) ← " first[u] "  (marker line names no upstream)"; continue }
    reason = check_upstream(u)
    if (reason != "") print "MISSING " u " ← " first[u] "  (" reason ")"
  }
}
'

excluded() { # excluded <rel> -> 0 when the file is outside the scan
  case "$1" in
    CHANGELOG.md|global-observation/*|docs/archive/*|*.json) return 0 ;;
    scripts/provenance-check.sh|scripts/tests/provenance-check-regression.sh) return 0 ;;
  esac
  [ -n "$NOTICES_REL" ] && [ "$1" = "$NOTICES_REL" ]
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/provenance-check.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$TMP"' EXIT

if [ "$ALL_FILES" = 0 ] && [ "$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" = "$ROOT" ]; then
  MODE="git ls-files"
  git -C "$ROOT" ls-files -z > "$TMP/files" || die "git ls-files failed in $ROOT"
else
  MODE="all files"
  find "$ROOT" -path "$ROOT/.git" -prune -o -type f -print0 > "$TMP/files" || die "find failed in $ROOT"
fi

[ -f "$NOTICES_ABS" ] || echo "provenance-check: WARN notices file not found: $NOTICES_ABS (every named upstream is then MISSING)" >&2

: > "$TMP/hits.tsv"
NFILES=0
ANNOTATED=0
NUNREG=0
: > "$TMP/registry.tsv"
if [ -f "$NOTICES_ABS" ]; then
  awk -v SEC="$NOTICES_SECTION" "$REGISTRY_PROG" "$NOTICES_ABS" > "$TMP/registry.tsv" \
    || die "cannot read the notices registry in $NOTICES_ABS"
fi
while IFS= read -r -d '' rel; do
  rel="${rel#"$ROOT"/}"
  if excluded "$rel"; then continue; fi
  if [ ! -f "$ROOT/$rel" ]; then
    echo "provenance-check: WARN listed but not on disk, not scanned: $rel" >&2
    continue
  fi
  NFILES=$((NFILES + 1))
  matches="$(grep -n -I -E -e "$MARKER_RE" -- "$ROOT/$rel")"; rc=$?
  [ "$rc" -le 1 ] || die "cannot read $rel (grep exit $rc)"
  ann_lines="$(grep -n -I -E -e "$ANNOT_RE" -- "$ROOT/$rel")"; ann_rc=$?
  [ "$ann_rc" -le 1 ] || die "cannot read annotations in $rel (grep exit $ann_rc)"
  # Annotated lines: a registered token suppresses its own marker line (same-line rule,
  # see header); an unregistered one is reported and suppresses nothing.
  suppressed=" "
  if [ -n "$ann_lines" ]; then
    reg_tokens="$(awk -F '\t' -v P="$rel" '$1 == P { print $2 }' "$TMP/registry.tsv")"
    while IFS= read -r ann; do
      ann_ln="${ann%%:*}"
      case "$ann" in
        *"[provenance: not-adopted]"*) ann_tok="[provenance: not-adopted]" ;;
        *) ann_tok="[provenance: own]" ;;
      esac
      case $'\n'"$reg_tokens"$'\n' in
        *$'\n'"$ann_tok"$'\n'*) suppressed="$suppressed$ann_ln " ;;
        *)
          echo "UNREGISTERED ANNOTATION $rel:$ann_ln  ($ann_tok is not registered for this file in the \"Non-adoptions (provenance annotations)\" section of $NOTICES_ABS)"
          NUNREG=$((NUNREG + 1))
          ;;
      esac
    done <<< "$ann_lines"
  fi
  [ "$rc" -eq 0 ] || continue
  kept=""
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    case "$suppressed" in
      *" ${hit%%:*} "*) ANNOTATED=$((ANNOTATED + 1)) ;;
      *) kept="$kept$hit"$'\n' ;;
    esac
  done <<< "$matches"
  printf '%s' "$kept" | awk -v REL="$rel" "$EXTRACT_PROG" >> "$TMP/hits.tsv" || die "marker extraction failed for $rel"
done < "$TMP/files"

NHITS="$(wc -l < "$TMP/hits.tsv" | tr -d ' ')"
NHITFILES="$(cut -f3 "$TMP/hits.tsv" | sort -u | wc -l | tr -d ' ')"
NUP="$(cut -f1 "$TMP/hits.tsv" | sort -u | wc -l | tr -d ' ')"

awk -F '\t' -v NOTICES="$NOTICES_ABS" "$CHECK_PROG" "$TMP/hits.tsv" > "$TMP/result.txt" || die "coverage check failed"
cat "$TMP/result.txt"
NMISS="$(grep -c '^MISSING ' "$TMP/result.txt")"

SUMMARY="$NFILES files scanned ($MODE), $NHITS marker lines in $NHITFILES files, $NUP upstream(s), $ANNOTATED annotated (registered)"
if [ "$NMISS" -gt 0 ] || [ "$NUNREG" -gt 0 ]; then
  echo "provenance-check: FAIL — $NMISS upstream(s) without a full notice section, $NUNREG unregistered annotation(s); $SUMMARY"
  exit 2
fi
echo "provenance-check: OK — every named upstream has a notice section; $SUMMARY"
exit 0
