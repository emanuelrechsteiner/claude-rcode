#!/usr/bin/env bash
# provenance-check-regression.sh — regression suite for scripts/provenance-check.sh
# (P-IMP-262; ledger id IMP-262, to be confirmed by the Lead).
#
# Pins the third-party provenance gate: a file with an origin marker must have a
# notice section that names the upstream and carries the full license text and a
# copyright line. Every case runs against throwaway fixture trees in a temp dir —
# never against the notices file of this repo. The one case that touches the real
# workshop requires a clean verdict (exit 0): a MISSING there means the workshop
# has an adopted upstream without a notice section, and the suite must stay red
# until that notice exists. Annotated mentions ([provenance: not-adopted] /
# [provenance: own]) are covered by cases 15, 16 and 20-23: an annotation counts only
# when registered in the notices file's "Non-adoptions" section.
#
# Fixtures spell the markers on purpose; this suite is excluded from the gate's own
# scan (provenance-check.sh excludes its two files by name).
#
# Usage: bash scripts/tests/provenance-check-regression.sh
# Exit: 0 = all cases passed, 1 = at least one failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$REPO_ROOT/scripts/provenance-check.sh"
PUBLISH="$REPO_ROOT/scripts/publish.sh"

[[ -f "$CHECK" ]] || { echo "ERROR: provenance-check.sh not found: $CHECK" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     %s\n' "$1" "$2"; }

TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/provenance-regression.XXXXXX")" || { echo "ERROR: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$TMP_BASE"' EXIT

# ── fixture helpers ────────────────────────────────────────────────────────
new_dir() { # new_dir <name> -> prints a fresh fixture root
  local d="$TMP_BASE/$1"
  mkdir -p "$d/skills" "$d/src"
  printf '%s\n' "$d"
}

mit_section() { # mit_section <heading> -> a ## section with copyright, MIT phrase, 12 body lines
  printf '%s\n\nMIT License\n\nCopyright (c) 2026 Fixture Author\n\n' "$1"
  printf 'Permission is hereby granted, free of charge, to any person obtaining a copy\n'
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf 'license body line %s\n' "$i"; done
  printf '\n'
}

plain_section() { # plain_section <heading> -> a ## section with copyright and 12 lines, no license phrase
  printf '%s\n\nCopyright (c) 2026 Fixture Author\n\n' "$1"
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf 'prose line %s\n' "$i"; done
  printf '\n'
}

notices_registry() { # notices_registry <path|token>... -> a notices file with one registry section
  printf '## Non-adoptions (provenance annotations)\n\n'
  local e
  for e in "$@"; do printf -- '- %s — %s — fixture reason — 2026-10-31\n' "${e%%|*}" "${e#*|}"; done
}

# run_check <args...> sets OUT and RC
run_check() {
  OUT="$(bash "$CHECK" "$@" 2>&1)"
  RC=$?
}

# ── Case 1: clean fixture passes ───────────────────────────────────────────
D="$(new_dir clean)"
mit_section "## License text for foo/bar" > "$D/skills/THIRD-PARTY-NOTICES.md"
printf '# Adapted from foo/bar (MIT) — the loop shape\necho hi\n' > "$D/src/a.sh"
printf 'no marker in this file\n' > "$D/src/plain.md"
run_check --root "$D"
if [[ "$RC" -eq 0 ]] && [[ "$OUT" != *MISSING* ]] && [[ "$OUT" == *"provenance-check: OK"* ]]; then
  ok "clean fixture (covered upstream, one marker, one plain file): exit 0 with OK line"
else
  bad "clean fixture must pass" "rc=$RC out=$OUT"
fi

# ── Case 2: marker without any notice is a miss ────────────────────────────
D="$(new_dir missing)"
mit_section "## License text for other/thing" > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Origin: foo/bar (MIT)\necho hi\n' > "$D/src/a.sh"
run_check --root "$D"
if [[ "$RC" -eq 2 ]] && [[ "$OUT" == *"MISSING foo/bar ← src/a.sh:1"* ]]; then
  ok "Origin: foo/bar (MIT) with no notice: exit 2, MISSING foo/bar ← src/a.sh:1"
else
  bad "unnoticed Origin marker must be a miss" "rc=$RC out=$OUT"
fi

# ── Case 3: notice section without the MIT phrase is a miss ────────────────
D="$(new_dir nophrase)"
plain_section "## License text for foo/bar" > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Origin: foo/bar (MIT)\n' > "$D/src/a.sh"
run_check --root "$D"
if [[ "$RC" -eq 2 ]] && [[ "$OUT" == *"MISSING foo/bar"* ]] && [[ "$OUT" == *"lacks the MIT license text"* ]]; then
  ok "section with copyright but no MIT text: exit 2, reason names the missing license text"
else
  bad "a section without the MIT phrase must not cover an MIT marker" "rc=$RC out=$OUT"
fi

# ── Case 4: the notices file itself is not reported ────────────────────────
D="$(new_dir notices-self)"
{ mit_section "## License text for foo/bar"; printf 'Origin: zed/zip (MIT)\n'; } > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Adapted from foo/bar (MIT)\n' > "$D/src/a.sh"
run_check --root "$D"
if [[ "$RC" -eq 0 ]] && [[ "$OUT" != *zed/zip* ]]; then
  ok "notices file's own marker line (zed/zip) is not reported; exit 0"
else
  bad "the notices file must be excluded from the scan" "rc=$RC out=$OUT"
fi

# ── Case 5: excluded paths are not scanned ─────────────────────────────────
D="$(new_dir excluded)"
mit_section "## License text for foo/bar" > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Adapted from foo/bar (MIT)\n' > "$D/src/a.sh"
mkdir -p "$D/global-observation" "$D/docs/archive"
printf 'Origin: zed/zip (MIT)\n' > "$D/global-observation/log.md"
printf 'adapted from quux/q (MIT)\n' > "$D/docs/archive/old.md"
printf '{"note": "Origin: jj/kk (MIT)"}\n' > "$D/data.json"
printf 'Origin: cc/ll (MIT)\n' > "$D/CHANGELOG.md"
run_check --root "$D"
if [[ "$RC" -eq 0 ]] && [[ "$OUT" != *zed/zip* && "$OUT" != *quux* && "$OUT" != *jj/kk* && "$OUT" != *cc/ll* ]]; then
  ok "global-observation/, docs/archive/, *.json and CHANGELOG.md are not scanned; exit 0"
else
  bad "excluded paths must not be reported" "rc=$RC out=$OUT"
fi

# ── Case 6: Apache-2.0 marker needs the Apache license text ────────────────
D="$(new_dir apache)"
plain_section "## License text for apa/che" > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Based on apa/che, Apache-2.0\n' > "$D/src/a.sh"
run_check --root "$D"
if [[ "$RC" -eq 2 ]] && [[ "$OUT" == *"MISSING apa/che"* ]] && [[ "$OUT" == *"Apache-2.0 license text"* ]]; then
  ok "Apache-2.0 marker, section without the Apache text: exit 2"
else
  bad "Apache marker must need the Apache license text" "rc=$RC out=$OUT"
fi
D="$(new_dir apache-ok)"
{ plain_section "## License text for apa/che"; printf 'Licensed under the Apache License, Version 2.0\n'; } > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Based on apa/che, Apache-2.0\n' > "$D/src/a.sh"
run_check --root "$D"
if [[ "$RC" -eq 0 ]]; then
  ok "Apache-2.0 marker, section with the Apache text and copyright: exit 0"
else
  bad "a complete Apache section must cover the marker" "rc=$RC out=$OUT"
fi

# ── Case 7: a level-1 heading does not cover ───────────────────────────────
D="$(new_dir level1)"
{ printf '# License text for lvl/one\n\n'; mit_section "## Unrelated"; } > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Origin: lvl/one (MIT)\n' > "$D/src/a.sh"
run_check --root "$D"
if [[ "$RC" -eq 2 ]] && [[ "$OUT" == *"MISSING lvl/one"* ]] && [[ "$OUT" == *"level-1 heading"* ]]; then
  ok "upstream named only under a # heading: exit 2 with the level-1 hint"
else
  bad "a level-1 heading must not cover an upstream" "rc=$RC out=$OUT"
fi

# ── Case 8: a license marker that names no upstream is always a miss ───────
D="$(new_dir unnamed)"
: > "$D/skills/THIRD-PARTY-NOTICES.md"
printf '(MIT)\n' > "$D/src/a.sh"
run_check --root "$D"
if [[ "$RC" -eq 2 ]] && [[ "$OUT" == *"MISSING (unnamed) ← src/a.sh:1"* ]]; then
  ok "bare (MIT) with no nameable upstream: exit 2, MISSING (unnamed)"
else
  bad "an unnamed license marker must fail loud" "rc=$RC out=$OUT"
fi

# ── Case 9: prose and internal references are not markers ──────────────────
D="$(new_dir prose)"
: > "$D/skills/THIRD-PARTY-NOTICES.md"
{
  printf '# SECOND-ATTEMPT — adapted from gateguard.sh, NOT directly\n'
  printf 'Origin: IMP-161, plans/meta-proposal.md\n'
  printf 'grep -E (BSD grep or ugrep, whichever is installed)\n'
  printf '# Set a file mtime to N days in the past (BSD touch -t, macOS).\n'
  printf '# BSD-only features; GPL-licensed code is out of scope here\n'
} > "$D/src/a.sh"
run_check --root "$D"
if [[ "$RC" -eq 0 ]] && [[ "$OUT" != *MISSING* ]]; then
  ok "local file name, ledger id and (BSD grep)/(BSD touch) prose are not reported; exit 0"
else
  bad "false positives in prose or internal references" "rc=$RC out=$OUT"
fi

# ── Case 10: git work tree scans tracked files; --all-files scans every file ─
D="$(new_dir gitmode)"
: > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Origin: tr/acked (MIT)\n' > "$D/src/t.sh"
printf 'Origin: un/tracked (MIT)\n' > "$D/src/u.sh"
git -C "$D" init -q && git -C "$D" add src/t.sh skills/THIRD-PARTY-NOTICES.md
run_check --root "$D"
TRACKED_OUT="$OUT"; TRACKED_RC=$RC
run_check --root "$D" --all-files
ALL_OUT="$OUT"; ALL_RC=$RC
if [[ "$TRACKED_RC" -eq 2 ]] && [[ "$TRACKED_OUT" == *tr/acked* ]] && [[ "$TRACKED_OUT" != *un/tracked* ]] \
   && [[ "$ALL_RC" -eq 2 ]] && [[ "$ALL_OUT" == *un/tracked* ]]; then
  ok "git work tree: tracked file scanned, untracked skipped; --all-files also scans the untracked file"
else
  bad "git-mode scope is wrong" "tracked rc=$TRACKED_RC out=$TRACKED_OUT | all rc=$ALL_RC out=$ALL_OUT"
fi

# ── Case 11: a custom --notices path resolves against --root ───────────────
D="$(new_dir custom-notice)"
mkdir -p "$D/legal"
mit_section "## License text for foo/bar" > "$D/legal/NOTICE.md"
printf 'Origin: foo/bar (MIT)\n' > "$D/src/a.sh"
run_check --root "$D" --notices legal/NOTICE.md
if [[ "$RC" -eq 0 ]]; then
  ok "--notices legal/NOTICE.md (relative to --root): covered upstream passes, exit 0"
else
  bad "--notices must resolve relative to --root" "rc=$RC out=$OUT"
fi

# ── Case 12: usage errors exit 1 ───────────────────────────────────────────
run_check --root "$TMP_BASE/does-not-exist"; RC_A=$RC
run_check --bogus; RC_B=$RC
run_check --root; RC_C=$RC
if [[ "$RC_A" -eq 1 ]] && [[ "$RC_B" -eq 1 ]] && [[ "$RC_C" -eq 1 ]]; then
  ok "missing --root directory, unknown argument, --root without value: exit 1 each"
else
  bad "usage errors must exit 1" "missing-root=$RC_A bogus=$RC_B no-value=$RC_C"
fi

# ── Case 13: the real workshop is clean (exit 0) ───────────────────────────
run_check --root "$REPO_ROOT"
if [[ "$RC" -eq 0 ]] && [[ "$OUT" == *"provenance-check: OK"* ]]; then
  ok "real workshop is clean (exit 0): $(printf '%s' "$OUT" | tail -1 | cut -c1-120)"
else
  bad "real workshop must pass the provenance gate (exit 0)" "rc=$RC out=$OUT"
fi

# ── Case 14: publish.sh runs the gate on the staging tree after scrub-check ─
CALL_LINE="$(grep -n -- '--root "\$STAGING" --all-files' "$PUBLISH" | head -1 | cut -d: -f1)"
SCRUB_LINE="$(grep -n 'scrub-check clean on staging tree' "$PUBLISH" | head -1 | cut -d: -f1)"
if [[ -n "$CALL_LINE" ]] && [[ -n "$SCRUB_LINE" ]] && [[ "$CALL_LINE" -gt "$SCRUB_LINE" ]]; then
  ok "publish.sh calls provenance-check.sh --root \"\$STAGING\" --all-files after the scrub-check (line $CALL_LINE > $SCRUB_LINE)"
else
  bad "publish.sh must run the provenance gate on the staging tree after scrub-check" "call=$CALL_LINE scrub=$SCRUB_LINE"
fi

# ── Case 15: [provenance: ...] annotation is SAME-LINE ONLY ────────────────
# A token on the marker's own line skips it (1 annotated). A token on the line AFTER a
# marker does NOT suppress that marker: baz/qux stays reported (inverse assertion).
D="$(new_dir annotated)"
notices_registry "src/a.sh|[provenance: not-adopted]" "src/b.md|[provenance: own]" > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Candidate tool: foo/bar (MIT) [provenance: not-adopted]\n' > "$D/src/a.sh"
printf 'Moved from baz/qux (MIT)\n[provenance: own]\n' > "$D/src/b.md"
run_check --root "$D"
if [[ "$RC" -eq 2 ]] && [[ "$OUT" != *"MISSING foo/bar"* ]] \
   && [[ "$OUT" == *"MISSING baz/qux ← src/b.md:1"* ]] && [[ "$OUT" == *"1 annotated"* ]]; then
  ok "same-line token skips its marker (1 annotated); token on the line after does NOT suppress (baz/qux reported, exit 2)"
else
  bad "annotation must be same-line only" "rc=$RC out=$OUT"
fi

# ── Case 16: the same marker without the token is reported; a token two lines away does not apply ─
D="$(new_dir unannotated)"
notices_registry "src/c.md|[provenance: own]" > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Candidate tool: foo/bar (MIT)\n' > "$D/src/a.sh"
printf 'Candidate tool: far/away (MIT)\n\n[provenance: own]\n' > "$D/src/c.md"
run_check --root "$D"
if [[ "$RC" -eq 2 ]] && [[ "$OUT" == *"MISSING foo/bar ← src/a.sh:1"* ]] \
   && [[ "$OUT" == *"MISSING far/away ← src/c.md:1"* ]] && [[ "$OUT" == *"0 annotated"* ]]; then
  ok "unannotated identical marker is reported (exit 2); token two lines away does not apply; summary '0 annotated'"
else
  bad "unannotated marker must be reported; annotation scope is the marker's own line only" "rc=$RC out=$OUT"
fi

# ── Case 17: an internal origin token does not drop the external upstream (finding 1) ─
D="$(new_dir internal-origin-miss)"
: > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Origin: IMP-124 (mattpocock/skills, MIT)\n' > "$D/src/a.md"
run_check --root "$D"
if [[ "$RC" -eq 2 ]] && [[ "$OUT" == *"MISSING mattpocock/skills ← src/a.md:1"* ]]; then
  ok "Origin: IMP-124 (mattpocock/skills, MIT) with no notice: exit 2, MISSING mattpocock/skills"
else
  bad "an internal origin token must not drop the external upstream on the same line" "rc=$RC out=$OUT"
fi

# ── Case 18: the same line passes once the upstream has a notice ───────────
D="$(new_dir internal-origin-ok)"
mit_section "## License text for mattpocock/skills" > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Origin: IMP-124 (mattpocock/skills, MIT)\n' > "$D/src/a.md"
run_check --root "$D"
if [[ "$RC" -eq 0 ]] && [[ "$OUT" != *MISSING* ]]; then
  ok "Origin: IMP-124 (mattpocock/skills, MIT) with a notice: exit 0"
else
  bad "the same line with a covering notice must pass" "rc=$RC out=$OUT"
fi

# ── Case 19: internal-only origin lines are not markers ────────────────────
D="$(new_dir internal-only)"
: > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Origin: IMP-161\n' > "$D/src/a.md"
printf 'Origin: IMP-124 (MIT)\n' > "$D/src/b.md"
run_check --root "$D"
if [[ "$RC" -eq 0 ]] && [[ "$OUT" == *"0 marker lines in 0 files"* ]]; then
  ok "Origin: IMP-161 and Origin: IMP-124 (MIT) name no external upstream: not markers, exit 0"
else
  bad "internal-only origin lines must not produce hits" "rc=$RC out=$OUT"
fi

# ── Case 20: an annotation in an unregistered file suppresses nothing ──────
D="$(new_dir unregistered)"
: > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Candidate tool: foo/bar (MIT) [provenance: not-adopted]\n' > "$D/src/a.sh"
run_check --root "$D"
if [[ "$RC" -eq 2 ]] && [[ "$OUT" == *"UNREGISTERED ANNOTATION src/a.sh:1"* ]] \
   && [[ "$OUT" == *"MISSING foo/bar ← src/a.sh:1"* ]] && [[ "$OUT" == *"0 annotated (registered)"* ]]; then
  ok "annotation in an unregistered file: UNREGISTERED ANNOTATION src/a.sh:1, exit 2; marker not suppressed"
else
  bad "an unregistered annotation must be reported and must not suppress its marker" "rc=$RC out=$OUT"
fi

# ── Case 21: a registered file with a different token does not register this one ─
D="$(new_dir token-mismatch)"
notices_registry "src/a.sh|[provenance: own]" > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Candidate tool: foo/bar (MIT) [provenance: not-adopted]\n' > "$D/src/a.sh"
run_check --root "$D"
if [[ "$RC" -eq 2 ]] && [[ "$OUT" == *"UNREGISTERED ANNOTATION src/a.sh:1"* ]]; then
  ok "file registered with [provenance: own] does not register [provenance: not-adopted]: exit 2"
else
  bad "registration must match the annotation token" "rc=$RC out=$OUT"
fi

# ── Case 22: only the Non-adoptions heading registers ──────────────────────
D="$(new_dir wrong-heading)"
{ printf '## Notes\n\n'; printf -- '- src/a.sh — [provenance: not-adopted] — fixture reason — 2026-10-31\n'; } > "$D/skills/THIRD-PARTY-NOTICES.md"
printf 'Candidate tool: foo/bar (MIT) [provenance: not-adopted]\n' > "$D/src/a.sh"
run_check --root "$D"
if [[ "$RC" -eq 2 ]] && [[ "$OUT" == *"UNREGISTERED ANNOTATION src/a.sh:1"* ]]; then
  ok "a registration line outside the Non-adoptions section does not count: exit 2"
else
  bad "only the Non-adoptions section may register annotations" "rc=$RC out=$OUT"
fi

# ── Case 23: the real workshop has exactly the 3 registered annotations ────
run_check --root "$REPO_ROOT"
if [[ "$RC" -eq 0 ]] && [[ "$OUT" == *"3 annotated (registered)"* ]] && [[ "$OUT" != *UNREGISTERED* ]]; then
  ok "real workshop: exit 0, 3 annotated (registered), no UNREGISTERED ANNOTATION"
else
  bad "real workshop must show 3 registered annotations and no unregistered ones" "rc=$RC out=$OUT"
fi

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
