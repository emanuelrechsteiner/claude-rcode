#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
# shellcheck disable=SC2034 # variables are assigned for the other files sourced into this shell, not read here
# knowledge-mirror-regression cases: hand-edit refusal, recovery, target and symlink refusals, unset target.
# Sourced by scripts/tests/knowledge-mirror-regression.sh (never run on its own); shares its
# helpers, fixtures and variables (T H C K run check ok bad ...) and its order of cases.

echo "== hand-edit refusal (drift check precedes every write) =="
# Source of b.md changes AND the copy of a.md is hand-edited: the run must
# refuse for a.md and must not have refreshed b.md meanwhile.
printf '# Rule B changed\nSOURCE-CHANGED-B\n' > "$C/rules/b.md"
printf 'HAND-EDITED-IN-OBSIDIAN\n' >> "$K/mirror/rules/a.md"
run
check "hand-edited copy: exit 3" "rc=$RC err=$ERR" test "$RC" -eq 3
check "hand-edit refusal: other changed copy NOT written (b.md keeps OLD content)" "$(cat "$K/mirror/rules/b.md")" \
  /bin/bash -c 'grep -q "# Rule B" "$1" && ! grep -q SOURCE-CHANGED-B "$1"' _ "$K/mirror/rules/b.md"
check "hand-edit refusal stderr has a hint: line" "$ERR" grep -q 'hint:' <<<"$ERR"
check "hand-edit refusal stderr starts with prefix" "$ERR" \
  /bin/bash -c 'head -1 <<<"$1" | grep -q "^knowledge-mirror: refuse: hand-edited copy:"' _ "$ERR"
check "hand-edit refusal names the edited file" "$ERR" grep -q 'rules/a.md' <<<"$ERR"
check "edited content still present (not overwritten)" "lost" grep -q HAND-EDITED-IN-OBSIDIAN "$K/mirror/rules/a.md"
check "hand-edit refusal does not name untouched file" "$ERR" /bin/bash -c '! grep -q "rules/b.md" <<<"$1"' _ "$ERR"
run --dry-run
check "dry-run also runs the drift check: exit 3 + hint" "rc=$RC err=$ERR" \
  /bin/bash -c '[ "$1" = 3 ] && grep -q "hint:" <<<"$2"' _ "$RC" "$ERR"

echo "== documented recovery: delete hashes.tsv, rerun =="
rm -f "$K/mirror/.state/hashes.tsv"
run
check "recovery run exits 0" "rc=$RC err=$ERR" test "$RC" -eq 0
check "recovery run refreshed b.md from source" "$(cat "$K/mirror/rules/b.md")" grep -q SOURCE-CHANGED-B "$K/mirror/rules/b.md"
check "recovery run restored state file" "missing" test -s "$K/mirror/.state/hashes.tsv"

echo "== target refusals =="
refuse() { # refuse <label> <expected-absent-path> [<stderr-substring>]; uses current K / EXTRA_ENV
  local before after; before="$(tree_count)"
  run
  after="$(tree_count)"
  check "$1: exit 1" "rc=$RC err=$ERR" test "$RC" -eq 1
  check "$1: stderr starts with 'knowledge-mirror: refuse:'" "$ERR" first_err_ok
  check "$1: nothing written" "tree $before -> $after" test "$before" = "$after"
  [ -n "${2:-}" ] && check "$1: target absent" "exists: $2" test ! -e "$2"
  [ -n "${3:-}" ] && check "$1: stderr contains '$3'" "$ERR" grep -qF -- "$3" <<<"$ERR"
  return 0
}
SAVE_K="$K"
K="$C/k";               refuse "target inside ~/.claude" "$C/k"
K="$C";                 refuse "target equal to ~/.claude" ""
K="$T/vault";           refuse "target basename vault" "$T/vault"
# Relative target: run from an EMPTY temp cwd; a regressed script would create
# relative/dir/... there (not under $T), so the cwd itself is the sink.
mkdir -p "$T/cwd"; RUN_CWD="$T/cwd"
K="relative/dir";       refuse "relative target" ""
check "relative target: nothing created in the caller's cwd" "$(ls -A "$T/cwd")" \
  /bin/bash -c '[ -z "$(ls -A "$1")" ]' _ "$T/cwd"
RUN_CWD="$T"
K="";                   refuse "empty target" ""
# Protected roots CONTAINED in the target (target is an ancestor of the root).
K="$H";                 refuse "target contains ~/.claude (target = HOME)" "" "target contains a protected root"
run_bh() { # run_bh <bauhof-root>; uses current K
  ( cd "$T" && env HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K" CLAUDE_BAUHOF_ROOT="$1" /bin/bash "$KM" >"$T/out" 2>"$T/err" )
  RC=$?; OUT="$(cat "$T/out")"; ERR="$(cat "$T/err")"
}
bh_case() { # bh_case <label> <bauhof-root> <stderr-substring>; uses current K
  local b a; b="$(tree_count)"; run_bh "$2"; a="$(tree_count)"
  check "$1: exit 1" "rc=$RC err=$ERR" test "$RC" -eq 1
  check "$1: refuse prefix" "$ERR" first_err_ok
  check "$1: nothing written" "$b -> $a" test "$b" = "$a"
  [ -z "${3:-}" ] || check "$1: stderr contains '$3'" "$ERR" grep -qF -- "$3" <<<"$ERR"
  return 0
}
BH="$T/bauhof"; mkdir -p "$BH"
K="$BH/sub";            bh_case "target inside CLAUDE_BAUHOF_ROOT" "$BH" ""
K="$H";                 bh_case "target = HOME, CLAUDE_BAUHOF_ROOT=HOME/ws" "$H/ws" "target contains a protected root"
# Isolating variant: the target here does NOT contain ~/.claude, so only the
# BAUHOF root can trigger the refusal (the case above would also fire on ~/.claude).
K="$T/outer";           bh_case "target contains CLAUDE_BAUHOF_ROOT (isolated)" "$T/outer/ws" "target contains a protected root"
K="$SAVE_K"

echo "== symlink inside mirror/ =="
# K is populated by the runs above; replace the real mirror/rules with a symlink
# to an empty dir elsewhere. A write through it would land outside mirror/.
rm -rf "$K/mirror/rules"; mkdir -p "$T/elsewhere"; ln -s "$T/elsewhere" "$K/mirror/rules"
run
check "symlink in mirror/: exit 1" "rc=$RC err=$ERR" test "$RC" -eq 1
check "symlink in mirror/: stderr starts 'knowledge-mirror: refuse: symlink inside mirror/:'" "$ERR" \
  /bin/bash -c 'head -1 <<<"$1" | grep -q "^knowledge-mirror: refuse: symlink inside mirror/:"' _ "$ERR"
check "symlink in mirror/: elsewhere stays empty" "$(ls -A "$T/elsewhere")" \
  /bin/bash -c '[ -z "$(ls -A "$1")" ]' _ "$T/elsewhere"
run --dry-run
check "symlink in mirror/ + --dry-run: exit 1" "rc=$RC err=$ERR" test "$RC" -eq 1
check "symlink in mirror/ + --dry-run: elsewhere stays empty" "$(ls -A "$T/elsewhere")" \
  /bin/bash -c '[ -z "$(ls -A "$1")" ]' _ "$T/elsewhere"
run --check-links
check "symlink in mirror/ + --check-links: read-only report, links are not followed (exit 0, LINKS line, elsewhere stays empty)" "rc=$RC err=$ERR" \
  /bin/bash -c '[ "$1" = 0 ] && grep -qE "^LINKS total=" <<<"$2" && [ -z "$(ls -A "$3")" ]' _ "$RC" "$OUT" "$T/elsewhere"
rm -f "$K/mirror/rules"
# the new ledger/ folder is subject to the same symlink refusal
rm -rf "$K/mirror/ledger"; mkdir -p "$T/elsewhere2"; ln -s "$T/elsewhere2" "$K/mirror/ledger"
run
check "symlinked mirror/ledger: exit 1" "rc=$RC err=$ERR" test "$RC" -eq 1
check "symlinked mirror/ledger: refuse prefix first" "$ERR" first_err_ok
check "symlinked mirror/ledger: elsewhere2 stays empty" "$(ls -A "$T/elsewhere2")" \
  /bin/bash -c '[ -z "$(ls -A "$1")" ]' _ "$T/elsewhere2"
rm -f "$K/mirror/ledger"

echo "== unset CLAUDE_KNOWLEDGE_DIR =="
b="$(tree_count)"
env -u CLAUDE_KNOWLEDGE_DIR -u CLAUDE_BAUHOF_ROOT HOME="$H" /bin/bash "$KM" >"$T/out" 2>"$T/err"; RC=$?
ERR="$(cat "$T/err")"; a="$(tree_count)"
check "unset target: exit 1" "rc=$RC err=$ERR" test "$RC" -eq 1
check "unset target: refuse prefix on stderr" "$ERR" first_err_ok
check "unset target: nothing created" "$b -> $a" test "$b" = "$a"
