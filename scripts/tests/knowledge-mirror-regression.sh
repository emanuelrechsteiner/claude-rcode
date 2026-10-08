#!/usr/bin/env bash
# knowledge-mirror-regression.sh — regression suite for scripts/knowledge-mirror.sh
# (IMP-248, docs/OBSIDIAN.md).
#
# Pins the two properties that matter most: (1) *.local.md overlays and /vault/
# paths NEVER reach the copy (*.jsonl is unreachable by the allowlist; that
# check is defense in depth, not a pin), (2) a hand-edited copy is refused
# (exit 3) BEFORE any write, never silently overwritten. Plus target refusals
# (incl. symlinks inside mirror/ and protected roots), provenance, ledger
# digest, state file, idempotence and notes/ safety.
#
# MECHANICS — builds a synthetic HOME under mktemp -d and calls the REAL script
# ("$REPO_ROOT/scripts/knowledge-mirror.sh") with HOME pointed at it; no
# reimplementation of the mirror logic (rules/testing-quality.md "Verify Via
# the Same Code Path"). Sinks are checked on disk (grep -r over the target
# tree), not via the script's own counters. Never touches the real ~/.claude.
# The sentinel is a fixture string, not real private content.
#
# bash 3.2 compatible. Usage: bash scripts/tests/knowledge-mirror-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
KM="$REPO_ROOT/scripts/knowledge-mirror.sh"
SENTINEL="PRIVATE-SENTINEL-MUST-NOT-LEAK"
VSENTINEL="VAULT-DECOY-MUST-NOT-LEAK"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \xe2\x9c\x85 %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \xe2\x9d\x8c %s\n     %s\n' "$1" "$2"; }
# check <label> <detail-on-fail> <command...> — passes when the command succeeds
check() { local l="$1" d="$2"; shift 2; if "$@"; then ok "$l"; else bad "$l" "$d"; fi; }

summary() {
  echo
  echo "knowledge-mirror-regression: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
}

if [ ! -f "$KM" ]; then
  bad "script under test exists" "script not found: $KM"
  summary
fi

T="$(mktemp -d "${TMPDIR:-/tmp}/km-regress.XXXXXX")" || { echo "ERROR: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
H="$T/home"; C="$H/.claude"; K="$T/know"

# ---- fixtures (invented values; frontmatter SHAPE only) ----------------------
mkdir -p "$C/logbook" "$C/projects/-proj-a/memory" "$C/projects/-proj-b/memory" \
         "$C/projects/vault/memory" "$C/plans" "$C/rules" "$C/vault" "$C/global-observation"
printf '# Log one\nbody\n' > "$C/logbook/2026-01-01.md"
printf '# Log two\nbody\n' > "$C/logbook/2026-01-02.md"
printf '{"a":1}\n' > "$C/logbook/noise.jsonl"
printf -- '---\nname: sample-memory\ndescription: invented description\nmetadata:\n  type: feedback\n---\nBody text.\n' \
  > "$C/projects/-proj-a/memory/sample.md"
printf -- '- [sample](sample.md) - index\n' > "$C/projects/-proj-a/memory/MEMORY.md"
printf -- '%s\n' "$SENTINEL" > "$C/projects/-proj-a/memory/secret.local.md"
printf '# Plan\n' > "$C/plans/meta-proposal-2026-01-01.md"
printf '# Other plan\n' > "$C/plans/not-a-proposal.md"
printf '# Rule A\n' > "$C/rules/a.md"
printf '# Rule B\n' > "$C/rules/b.md"
printf '%s\n' "$SENTINEL" > "$C/rules/zz-private.local.md"
# REACHABLE vault decoy: matches projects/*/memory/*.md, so only the /vault/
# hard exclude keeps it out. ($C/vault/decoy.md below is outside every glob and
# only a bystander.)
printf '%s\n' "$VSENTINEL" > "$C/projects/vault/memory/decoy.md"
printf '%s\n' "$VSENTINEL" > "$C/vault/decoy.md"
cat > "$C/global-observation/improvement-ledger.json" <<'EOF'
{
  "batchA": {"entries": [
    {"id": "IMP-001", "status": "proposed", "title": "Dup first"},
    {"id": "IMP-002", "status": "implemented", "title": "Second"}]},
  "batchB": {"entries": [
    {"id": "IMP-001", "status": "implemented", "title": "Dup last"}]},
  "improvementQueue": {"priority_high": [
    {"id": "IMP-900", "status": "queued", "title": "Queue item"}]}
}
EOF

# run <args...> — runs the real script; sets RC, OUT, ERR. Env: K as target.
run() {
  ( cd "$RUN_CWD" && env -u CLAUDE_BAUHOF_ROOT HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K" "${EXTRA_ENV[@]}" \
    bash "$KM" "$@" >"$T/out" 2>"$T/err" )
  RC=$?; OUT="$(cat "$T/out")"; ERR="$(cat "$T/err")"
}
EXTRA_ENV=(A=1)
RUN_CWD="$T"
tree_count() { find "$T" -mindepth 1 | grep -v -e '/out$' -e '/err$' | wc -l | tr -d ' '; }
first_err_ok() { printf '%s\n' "$ERR" | head -1 | grep -q '^knowledge-mirror: refuse:'; }
no_leak_names() { ! printf '%s\n%s\n' "$OUT" "$ERR" | grep -E '\.local\.md|vault/|\.jsonl' >/dev/null; }

echo "== help =="
run --help
check "--help exits 0" "rc=$RC" test "$RC" -eq 0

echo "== dry-run =="
run --dry-run
check "dry-run exits 0" "rc=$RC err=$ERR" test "$RC" -eq 0
for t in mirror/logbook/2026-01-01.md mirror/logbook/2026-01-02.md \
         mirror/memory/-proj-a/sample.md mirror/memory/-proj-a/MEMORY.md \
         mirror/plans/meta-proposal-2026-01-01.md mirror/rules/a.md mirror/rules/b.md mirror/ledger.md; do
  check "dry-run lists $t" "output: $OUT" grep -qF "$t" <<<"$OUT"
done
check "dry-run does not list non-allowlisted plan" "$OUT" bash -c '! grep -qF not-a-proposal <<<"$1"' _ "$OUT"
check "dry-run prints TOTAL 8" "$OUT" grep -qx 'TOTAL 8' <<<"$OUT"
check "dry-run prints CHANGED line" "$OUT" grep -qE '^CHANGED [0-9]+$' <<<"$OUT"
check "dry-run writes nothing (no mirror/, no notes/)" "$(ls -A "$K" 2>&1)" \
  bash -c '[ ! -e "$1/mirror" ] && [ ! -e "$1/notes" ]' _ "$K"
check "dry-run output has no .local.md / vault/ / .jsonl" "$OUT $ERR" no_leak_names

echo "== real run =="
run
check "real run exits 0" "rc=$RC err=$ERR" test "$RC" -eq 0
check "real run output has no .local.md / vault/ / .jsonl" "$OUT $ERR" no_leak_names
check "real run prints TOTAL 8 and CHANGED > 0" "$OUT" \
  bash -c 'grep -qx "TOTAL 8" <<<"$1" && grep -qE "^CHANGED [1-9][0-9]*$" <<<"$1"' _ "$OUT"
check "grep -r sentinel in target finds nothing" "$(grep -rl "$SENTINEL" "$K" 2>/dev/null)" \
  bash -c '! grep -rq "$1" "$2"' _ "$SENTINEL" "$K"
check "reachable vault decoy (projects/vault/memory) content absent from target" "$(grep -rl "$VSENTINEL" "$K" 2>/dev/null)" \
  bash -c '! grep -rq "$1" "$2"' _ "$VSENTINEL" "$K"
check "no mirror/memory/vault dir" "present" test ! -e "$K/mirror/memory/vault"
check "no *.local.md / vault path in target tree" "$(find "$K" 2>/dev/null | grep -E 'local\.md|vault')" \
  bash -c '! find "$1" | grep -qE "local\.md|vault"' _ "$K"
check "no .jsonl in target: unreachable by allowlist (defense in depth)" "$(find "$K" -name '*.jsonl' 2>/dev/null)" \
  bash -c '[ -z "$(find "$1" -name "*.jsonl")" ]' _ "$K"
check "mirror/rules/a.md exists" "missing" test -f "$K/mirror/rules/a.md"
check "mirror/rules/b.md exists" "missing" test -f "$K/mirror/rules/b.md"
check "mirror/rules has no zz-private copy" "present" test ! -e "$K/mirror/rules/zz-private.local.md"
check "memory .local.md absent from copy" "present" test ! -e "$K/mirror/memory/-proj-a/secret.local.md"
check "empty memory dir yields no copy dir content" "$(ls -A "$K/mirror/memory/-proj-b" 2>&1)" \
  bash -c '[ -z "$(ls -A "$1/mirror/memory/-proj-b" 2>/dev/null)" ]' _ "$K"
check "non-allowlisted plan not copied" "present" test ! -e "$K/mirror/plans/not-a-proposal.md"

SM="$K/mirror/memory/-proj-a/sample.md"
check "frontmatter copy starts with --- on line 1" "$(head -1 "$SM" 2>&1)" \
  bash -c '[ "$(head -1 "$1")" = "---" ]' _ "$SM"
check "frontmatter copy: provenance comment right after closing ---" "$(cat "$SM" 2>&1)" \
  bash -c 'awk '"'"'/^---$/{n++; if(n==2){getline l; exit !(l ~ /^<!-- knowledge-mirror: copied from ~\//)}} END{if(n<2)exit 1}'"'"' "$1"' _ "$SM"
check "frontmatter copy keeps body" "body lost" grep -q 'Body text.' "$SM"
MM="$K/mirror/memory/-proj-a/MEMORY.md"
check "MEMORY.md copy: provenance comment on line 1" "$(head -1 "$MM" 2>&1)" \
  bash -c 'head -1 "$1" | grep -q "^<!-- knowledge-mirror: copied from ~/"' _ "$MM"

LG="$K/mirror/ledger.md"
check "ledger lists duplicate id exactly once" "count=$(grep -c 'IMP-001' "$LG" 2>/dev/null)" \
  bash -c '[ "$(grep -c "IMP-001" "$1")" = 1 ]' _ "$LG"
check "ledger duplicate id carries LAST status (implemented)" "$(grep IMP-001 "$LG" 2>&1)" \
  bash -c 'grep "IMP-001" "$1" | grep -q implemented && ! grep "IMP-001" "$1" | grep -q proposed' _ "$LG"
check "ledger includes priority-queue id IMP-900" "$(cat "$LG" 2>&1)" grep -q 'IMP-900' "$LG"
check "ledger lists 3 unique ids" "$(grep -c 'IMP-' "$LG")" \
  bash -c '[ "$(grep -c "^- IMP-" "$1")" = 3 ]' _ "$LG"

HT="$K/mirror/.state/hashes.tsv"
check "hashes.tsv has one line per copied file (8)" "$(cat "$HT" 2>&1)" \
  bash -c '[ "$(grep -vc "README" "$1")" = 8 ]' _ "$HT"
check "hashes.tsv rows are <path><TAB><sha256>" "$(head -2 "$HT" 2>&1)" \
  bash -c '! grep -vE "^[^	]+	[0-9a-f]{64}$" "$1" | grep -q .' _ "$HT"
check "mirror/README.md exists" "missing" test -f "$K/mirror/README.md"
check "notes/ exists and is empty" "$(ls -A "$K/notes" 2>&1)" \
  bash -c '[ -d "$1/notes" ] && [ -z "$(ls -A "$1/notes")" ]' _ "$K"

echo "== idempotence and notes safety =="
printf 'mine\n' > "$K/notes/keep.md"
run
check "second run exits 0" "rc=$RC err=$ERR" test "$RC" -eq 0
check "second run prints CHANGED 0" "$OUT" grep -qx 'CHANGED 0' <<<"$OUT"
check "notes/keep.md survives rerun" "gone" test -f "$K/notes/keep.md"

echo "== hand-edit refusal (drift check precedes every write) =="
# Source of b.md changes AND the copy of a.md is hand-edited: the run must
# refuse for a.md and must not have refreshed b.md meanwhile.
printf '# Rule B changed\nSOURCE-CHANGED-B\n' > "$C/rules/b.md"
printf 'HAND-EDITED-IN-OBSIDIAN\n' >> "$K/mirror/rules/a.md"
run
check "hand-edited copy: exit 3" "rc=$RC err=$ERR" test "$RC" -eq 3
check "hand-edit refusal: other changed copy NOT written (b.md keeps OLD content)" "$(cat "$K/mirror/rules/b.md")" \
  bash -c 'grep -q "# Rule B" "$1" && ! grep -q SOURCE-CHANGED-B "$1"' _ "$K/mirror/rules/b.md"
check "hand-edit refusal stderr has a hint: line" "$ERR" grep -q 'hint:' <<<"$ERR"
check "hand-edit refusal stderr starts with prefix" "$ERR" \
  bash -c 'head -1 <<<"$1" | grep -q "^knowledge-mirror: refuse: hand-edited copy:"' _ "$ERR"
check "hand-edit refusal names the edited file" "$ERR" grep -q 'rules/a.md' <<<"$ERR"
check "edited content still present (not overwritten)" "lost" grep -q HAND-EDITED-IN-OBSIDIAN "$K/mirror/rules/a.md"
check "hand-edit refusal does not name untouched file" "$ERR" bash -c '! grep -q "rules/b.md" <<<"$1"' _ "$ERR"

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
  bash -c '[ -z "$(ls -A "$1")" ]' _ "$T/cwd"
RUN_CWD="$T"
K="";                   refuse "empty target" ""
# Protected roots CONTAINED in the target (target is an ancestor of the root).
K="$H";                 refuse "target contains ~/.claude (target = HOME)" "" "target contains a protected root"
run_bh() { # run_bh <bauhof-root>; uses current K
  ( cd "$T" && env HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K" CLAUDE_BAUHOF_ROOT="$1" bash "$KM" >"$T/out" 2>"$T/err" )
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
  bash -c 'head -1 <<<"$1" | grep -q "^knowledge-mirror: refuse: symlink inside mirror/:"' _ "$ERR"
check "symlink in mirror/: elsewhere stays empty" "$(ls -A "$T/elsewhere")" \
  bash -c '[ -z "$(ls -A "$1")" ]' _ "$T/elsewhere"
run --dry-run
check "symlink in mirror/ + --dry-run: exit 1" "rc=$RC err=$ERR" test "$RC" -eq 1
check "symlink in mirror/ + --dry-run: elsewhere stays empty" "$(ls -A "$T/elsewhere")" \
  bash -c '[ -z "$(ls -A "$1")" ]' _ "$T/elsewhere"
rm -f "$K/mirror/rules"

echo "== unset CLAUDE_KNOWLEDGE_DIR =="
b="$(tree_count)"
env -u CLAUDE_KNOWLEDGE_DIR -u CLAUDE_BAUHOF_ROOT HOME="$H" bash "$KM" >"$T/out" 2>"$T/err"; RC=$?
ERR="$(cat "$T/err")"; a="$(tree_count)"
check "unset target: exit 1" "rc=$RC err=$ERR" test "$RC" -eq 1
check "unset target: refuse prefix on stderr" "$ERR" first_err_ok
check "unset target: nothing created" "$b -> $a" test "$b" = "$a"

summary
