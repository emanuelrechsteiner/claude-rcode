#!/bin/bash
# vault-check: fixtures (synthetic values only — invented stand-ins, never a real term)
#
# See rules/testing-quality.md and this task's brief: no real term ever
# appears below, only invented stand-ins like "SyntheticAcme"/"Widget Corp".
# The fixture marker above MUST close its parenthetical on the SAME line
# (plans/vault-by-design-2026-09-25.md §7.2) — an earlier version of this
# comment opened the paren here and closed it two lines down, which meant
# the marker never actually matched and this whole file was scanned like
# any other tracked file (caught by a real `vault.sh check` run against it,
# 2026-09-25 rework).
#
# vault-regression.sh — regression suite for scripts/vault/vault.sh +
# scripts/vault/lib.sh (IMP-219, plans/vault-by-design-2026-09-25.md).
#
# Runs ENTIRELY against a fresh CLAUDE_VAULT_DIR under mktemp per test group
# — NEVER the real ~/.claude/vault. Usage: bash scripts/tests/vault-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VAULT="${CLAUDE_VAULT_SCRIPT:-$REPO_ROOT/scripts/vault/vault.sh}"
[[ -f "$VAULT" ]] || { echo "ERROR: vault.sh not found: $VAULT" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \xe2\x9c\x85 %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \xe2\x9d\x8c %s\n     %s\n' "$1" "$2"; }

fresh_vault() {
  CLAUDE_VAULT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vault-regr.XXXXXX")"
  export CLAUDE_VAULT_DIR
}

check_exit() {  # check_exit <label> <expected> <actual>
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then ok "$label"; else bad "$label" "expected exit $expected, got $actual"; fi
}

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/vault-regr-scratch.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

echo "== init =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
[[ -f "$CLAUDE_VAULT_DIR/secret" ]] && ok "init creates secret" || bad "init creates secret" "missing"
[[ -f "$CLAUDE_VAULT_DIR/map.tsv" ]] && ok "init creates map.tsv" || bad "init creates map.tsv" "missing"
PERM="$(stat -f '%Lp' "$CLAUDE_VAULT_DIR" 2>/dev/null || stat -c '%a' "$CLAUDE_VAULT_DIR" 2>/dev/null)"
[[ "$PERM" == "700" ]] && ok "vault dir is 0700" || bad "vault dir is 0700" "got $PERM"
PERM_S="$(stat -f '%Lp' "$CLAUDE_VAULT_DIR/secret" 2>/dev/null || stat -c '%a' "$CLAUDE_VAULT_DIR/secret" 2>/dev/null)"
[[ "$PERM_S" == "600" ]] && ok "secret file is 0600" || bad "secret file is 0600" "got $PERM_S"

S1="$(cat "$CLAUDE_VAULT_DIR/secret")"
bash "$VAULT" init >/dev/null 2>&1
S2="$(cat "$CLAUDE_VAULT_DIR/secret")"
[[ "$S1" == "$S2" ]] && ok "init idempotent: secret byte-identical after 2nd run" || bad "init idempotent" "secret changed"

echo "== add: duplicate-term-foreign-group rejection + idempotency =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
bash "$VAULT" add project "SyntheticAcme" --group g1 >/dev/null 2>&1
bash "$VAULT" add project "SyntheticAcme" --group g2 >/dev/null 2>&1
check_exit "add rejects term already under a different group" 1 "$?"
bash "$VAULT" add project "SyntheticAcme" --group g1 >/dev/null 2>&1
check_exit "add is idempotent for identical (kind,term,token,group)" 0 "$?"
bash "$VAULT" add id "abc123" --group idgrp >/dev/null 2>&1
check_exit "add rejects kind=id with no --token (no sane default)" 1 "$?"
bash "$VAULT" add id "abc123" --group idgrp --token "<session-id>" >/dev/null 2>&1
check_exit "add accepts kind=id WITH explicit --token" 0 "$?"

ALIAS_OUT="$(bash "$VAULT" add project "SynthAliasMain" --group aliasgrp --alias "SynthAliasOne" --alias "SynthAliasTwo" 2>&1)"
echo "$ALIAS_OUT" | grep -q "3 row(s) added" && ok "add --alias: main + 2 aliases -> 3 rows added" || bad "add --alias: row count" "$ALIAS_OUT"
ALIAS_MAP="$CLAUDE_VAULT_DIR/map.tsv"
ALIAS_TOKENS="$(awk -F'\t' '$4=="aliasgrp"{print $3}' "$ALIAS_MAP" | sort -u | wc -l | tr -d ' ')"
[[ "$ALIAS_TOKENS" == "1" ]] && ok "add --alias: main term and both aliases share exactly one token" || bad "add --alias: token sharing" "distinct tokens: $ALIAS_TOKENS"

echo "== import-legacy: grouping + §2 classification heuristic =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
LEGACY="$SCRATCH/legacy.tsv"
cat > "$LEGACY" <<'EOF'
Synthetic Widget Corp	Projekt A
synthwidgetcorp	Projekt A
Synthetic Example LLC	Example Org
synthexample-llc	Example Org
<synthetic-trigger-id>	<trig-id>
UTC	UTC
a made-up joke name	a described workflow
EOF
OUT="$(bash "$VAULT" init --import-legacy "$LEGACY" 2>&1)"
echo "$OUT" | grep -q "5 group(s), 7 row(s) imported, 0 conflict(s)" \
  && ok "import-legacy: 5 groups / 7 rows / 0 conflicts" \
  || bad "import-legacy: counts" "$OUT"
MAP="$CLAUDE_VAULT_DIR/map.tsv"
grep -qE '^project	Synthetic Widget Corp	proj-[0-9a-f]{6}	Synthetic Widget Corp$' "$MAP" \
  && ok "import-legacy: 'Projekt A' placeholder -> kind=project, group=longest term" \
  || bad "import-legacy: project classification" "$(grep 'Widget Corp' "$MAP")"
grep -qE '^project	synthwidgetcorp	proj-[0-9a-f]{6}	Synthetic Widget Corp$' "$MAP" \
  && ok "import-legacy: alias shares the group's token" \
  || bad "import-legacy: alias token sharing" "$(grep synthwidgetcorp "$MAP")"
grep -qE '^account	Synthetic Example LLC	acct-[0-9a-f]{6}	Synthetic Example LLC$' "$MAP" \
  && ok "import-legacy: 'Example Org' placeholder -> kind=account" \
  || bad "import-legacy: account classification" "$(grep 'Example LLC' "$MAP")"
grep -qE '^id	<synthetic-trigger-id>	<trig-id>	<synthetic-trigger-id>$' "$MAP" \
  && ok "import-legacy: '<...-id>' placeholder -> kind=id, token=old placeholder verbatim" \
  || bad "import-legacy: id classification" "$(grep synthetic-trigger-id "$MAP")"
grep -qE '^phrase	UTC	UTC	UTC$' "$MAP" \
  && ok "import-legacy: 'UTC' placeholder -> kind=phrase" \
  || bad "import-legacy: UTC classification" "$(grep -w UTC "$MAP")"
grep -qE '^phrase	a made-up joke name	a described workflow	a made-up joke name$' "$MAP" \
  && ok "import-legacy: multi-word placeholder -> kind=phrase (Satz-Phrasen heuristic)" \
  || bad "import-legacy: phrase classification" "$(grep 'made-up joke' "$MAP")"

echo "== import-legacy: re-running is idempotent (no duplicate rows, no conflicts) =="
OUT2="$(bash "$VAULT" init --import-legacy "$LEGACY" 2>&1)"
echo "$OUT2" | grep -q "0 conflict(s)" \
  && ok "import-legacy: re-run has 0 conflicts" \
  || bad "import-legacy: re-run conflicts" "$OUT2"

echo "== from-registry: name/pfad/git import (synthetic JSONL) =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
REGISTRY="$SCRATCH/registry.jsonl"
cat > "$REGISTRY" <<'EOF'
{"id":"synthproj-one","name":"Synthetic Registry Project","pfad":"cat/synthetic-registry-project","git":"git@github.com:synthacct/synthrepo.git"}
{"id":"synthproj-two","name":"Synthetic Bool Git Project","pfad":"cat/synthetic-bool-git","git":true}
EOF
OUT3="$(bash "$VAULT" init --from-registry "$REGISTRY" 2>&1)"
MAP2="$CLAUDE_VAULT_DIR/map.tsv"
grep -q "Synthetic Registry Project" "$MAP2" \
  && ok "from-registry: 'name' field imported as kind=project" \
  || bad "from-registry: name import" "$(cat "$MAP2")"
grep -q "cat/synthetic-registry-project" "$MAP2" \
  && ok "from-registry: 'pfad' field imported as kind=path" \
  || bad "from-registry: pfad import" "$(cat "$MAP2")"
grep -q "synthacct" "$MAP2" \
  && ok "from-registry: account extracted from a string 'git' URL" \
  || bad "from-registry: git-URL account extraction" "$(cat "$MAP2")"
grep -q "synthrepo" "$MAP2" \
  && ok "from-registry: repo-name alias extracted from a string 'git' URL" \
  || bad "from-registry: git-URL repo alias" "$(cat "$MAP2")"
echo "$OUT3" | grep -q "1 entr(y/ies) with non-string 'git' field" \
  && ok "from-registry: boolean 'git' field (real-world shape) skipped gracefully, counted, not fatal" \
  || bad "from-registry: non-string git handling" "$OUT3"
grep -q "Synthetic Bool Git Project" "$MAP2" \
  && ok "from-registry: name/pfad still imported even when 'git' is non-string" \
  || bad "from-registry: partial import on bool git" "$(cat "$MAP2")"

echo "== status / init summary never print a term =="
STATUS_OUT="$(bash "$VAULT" status 2>&1)"
for term in "Synthetic Registry Project" "synthacct" "synthrepo" "cat/synthetic-registry-project"; do
  if echo "$STATUS_OUT" | grep -qF -- "$term"; then
    bad "status output contains no term" "found '$term' in status output"
  else
    ok "status output does not leak term '$term'"
  fi
done
if echo "$OUT3" | grep -qF -- "Synthetic Registry Project"; then
  bad "init --from-registry summary contains no term" "leaked a term"
else
  ok "init --from-registry summary contains no term"
fi

echo "== check: structural patterns (no vault needed) MUST trigger =="
fresh_vault   # empty vault on purpose — structural-only path
declare -a hit_cases=(
  "path is /Users/x/foo"
  "path is /home/x/foo"
  "path is /Volumes/x/foo"
  "contact someone@example-real.tld"
  "id is 3fa2c1de-1234-4abc-8def-0123456789ab"
  "token session_abcdefghijklmnopqrstuvwx1234"
  "token trig_abcdefghijklmnopqrstuvwxabcd"
)
for c in "${hit_cases[@]}"; do
  printf '%s\n' "$c" | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
  check_exit "structural MUST-trigger: $c" 2 "$?"
done

echo "== check: structural placeholder forms MUST pass =="
declare -a pass_cases=(
  "path is /Users/<user>/foo"
  "path is /Users/\$USER/foo"
  "path is /Users/\${HOME}/foo"
  "path is /Users/USERNAME/foo"
  "path is /Users/.../f.ts"
  "contact noreply@anthropic.com"
  # Round 3, finding #7: an empty segment right after the prefix (only
  # punctuation follows) is not a path at all.
  "a comment mentioning /Users/, and more"
  "a comment mentioning /Users/. end of sentence"
  # Round 3, finding #4: word@filename.ext where .ext is a common source
  # file extension is a file reference, not an email.
  "see hooks/guard-unsafe.sh, or ping someone@guard-unsafe.sh for context"
  "config at settings@settings.json today"
  # Round 3, finding #5: RFC 2606/6761 reserved test/documentation TLDs.
  "contact user@example.invalid please"
  "contact user@t.test please"
  "contact user@email.example please"
  "contact user@login.example please"
)
for c in "${pass_cases[@]}"; do
  printf '%s\n' "$c" | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
  check_exit "structural MUST-pass: $c" 0 "$?"
done

echo "== check: timezone is a stderr warning only, exit 0 =="
TZ_ERR="$(printf 'zone is Europe/Berlin\n' | bash "$VAULT" check --stdin 2>&1 >/dev/null)"
printf 'zone is Europe/Berlin\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "timezone literal: exit 0" 0 "$?"
echo "$TZ_ERR" | grep -q "WARNING" && ok "timezone literal: stderr warning present" || bad "timezone warning" "$TZ_ERR"

echo "== check: without a vault — one loud line, structural keeps running =="
NOVAULT_ERR="$(printf 'path is /Users/x/foo\n' | bash "$VAULT" check --stdin 2>&1 >/dev/null)"
echo "$NOVAULT_ERR" | grep -qi "WARNING" && ok "check without vault: loud stderr line present" || bad "check without vault: loud line" "$NOVAULT_ERR"
printf 'path is /Users/x/foo\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "check without vault: structural pattern still fires" 2 "$?"

echo "== check: with vault — word boundary, case-insensitivity, longest-first =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
bash "$VAULT" add project "zynthor" --group zynthorgrp >/dev/null 2>&1
printf 'this is zynthoric reasoning\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "word boundary: 'zynthor' does not match inside 'zynthoric'" 0 "$?"
printf 'this is a ZYNTHOR here\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "case-insensitivity: 'ZYNTHOR' matches term 'zynthor'" 2 "$?"

bash "$VAULT" add project "SynthLongTerm" --group longgrp >/dev/null 2>&1
bash "$VAULT" add account "SynthLong" --group shortgrp >/dev/null 2>&1
TOKENIZED="$(printf 'x SynthLongTerm y\n' | bash "$VAULT" tokenize)"
if echo "$TOKENIZED" | grep -qE '^x proj-[0-9a-f]{6} y$'; then
  ok "longest-first: 'SynthLongTerm' consumed whole by the longer project rule, not corrupted by the shorter account rule"
else
  bad "longest-first tokenize" "$TOKENIZED"
fi

echo "== check: allowlist snippet suppresses regardless of line number =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
bash "$VAULT" add project "SynthAllow" --group allowgrp >/dev/null 2>&1
ALLOWFILE="$SCRATCH/scrub-allowlist.txt"
cat > "$ALLOWFILE" <<'EOF'
some/file.md:1:SynthAllow
EOF
source "$REPO_ROOT/scripts/vault/lib.sh"
RULES="$(mktemp "${TMPDIR:-/tmp}/vault-regr-rules.XXXXXX")"
vault_build_rules_file "$RULES"
printf 'line one\nline two\nSynthAllow appears here on line 3\n' \
  | vault_matcher_run check 1 "some/file.md" "$RULES" "$ALLOWFILE" >/dev/null 2>/dev/null
check_exit "allowlist: suppressed even though recorded line (1) != actual line (3)" 0 "$?"
rm -f "$RULES"

echo "== check: vault-check: fixtures marker exempts ONLY structural findings, under */tests/* =="
mkdir -p "$SCRATCH/proj/tests" "$SCRATCH/proj/nottests"
cat > "$SCRATCH/proj/tests/fixture.txt" <<'EOF'
vault-check: fixtures (synthetic secrets for regression only)
line2
line3
line4
/Users/realbadpath/should/not/matter
EOF
cp "$SCRATCH/proj/tests/fixture.txt" "$SCRATCH/proj/nottests/fixture.txt"
bash "$VAULT" check "$SCRATCH/proj/tests/fixture.txt" >/dev/null 2>/dev/null
check_exit "fixture marker under */tests/*: structural-only finding suppressed (exit 0)" 0 "$?"
bash "$VAULT" check "$SCRATCH/proj/nottests/fixture.txt" >/dev/null 2>/dev/null
check_exit "identical content OUTSIDE */tests/*: marker has no effect (exit 2)" 2 "$?"

# Round 3, finding #1: the marker must NOT exempt a real vault-term match
# (a finding WITH a token) — only structural, no-token findings. Reuses
# "SynthAllow" (added in the previous section's vault, still current here).
cat > "$SCRATCH/proj/tests/fixture-with-vaultterm.txt" <<'EOF'
vault-check: fixtures (synthetic secrets for regression only)
line2
line3
line4
mentions SynthAllow here
EOF
bash "$VAULT" check "$SCRATCH/proj/tests/fixture-with-vaultterm.txt" >/dev/null 2>/dev/null
check_exit "fixture marker: a real vault-term match is STILL reported (exit 2)" 2 "$?"

echo "== check --stdin --as <path>: file label, allowlist, and fixture marker all key off it (round 3, finding #2) =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
bash "$VAULT" add project "SynthAsTerm" --group asgrp >/dev/null 2>&1

bash "$VAULT" check --as some/path.md 2>/dev/null
check_exit "--as without --stdin is refused" 1 "$?"

AS_OUT="$(printf 'path is /Users/x/foo\n' | bash "$VAULT" check --stdin --as some/tests/fake.md 2>/dev/null)"
echo "$AS_OUT" | grep -q '^some/tests/fake\.md	' \
  && ok "--as: reported 'file' column is the given path, not '-'" \
  || bad "--as: file column" "$AS_OUT"

printf 'vault-check: fixtures (synthetic)\nline2\nline3\nline4\n/Users/x/foo\n' \
  | bash "$VAULT" check --stdin --as some/tests/fixture-fake.md >/dev/null 2>/dev/null
check_exit "--as: fixture marker applies via the given path (structural suppressed)" 0 "$?"

printf 'path is /Users/x/foo\n' | bash "$VAULT" check --stdin --as some/nottests/fake.md >/dev/null 2>/dev/null
check_exit "--as: path NOT under */tests/* gets no fixture exemption" 2 "$?"

printf 'hello SynthAsTerm world\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "--as: without it, --stdin still reports as '-' (unchanged default)" 2 "$?"
NOAS_OUT="$(printf 'hello SynthAsTerm world\n' | bash "$VAULT" check --stdin 2>/dev/null)"
echo "$NOAS_OUT" | grep -q '^-	' \
  && ok "--as: without it, file column is still '-'" \
  || bad "--as: default file column" "$NOAS_OUT"

# --as absolute-path normalization: inside a real git repo -> repo-relative;
# outside any repo -> left unchanged (both against paths that need not
# exist on disk — --as never requires the target file to be real).
INSIDE_ABS="$REPO_ROOT/scripts/tests/synthetic-nonexistent-$$.md"
INSIDE_OUT="$(printf 'hello SynthAsTerm world\n' | bash "$VAULT" check --stdin --as "$INSIDE_ABS" 2>/dev/null)"
echo "$INSIDE_OUT" | grep -q '^scripts/tests/synthetic-nonexistent-'"$$"'\.md	' \
  && ok "--as: absolute path inside a git repo normalizes to repo-relative" \
  || bad "--as: absolute-path normalization (inside repo)" "$INSIDE_OUT"

OUTSIDE_ABS="/private/tmp/synthetic-outside-any-repo-$$.md"
OUTSIDE_OUT="$(printf 'hello SynthAsTerm world\n' | bash "$VAULT" check --stdin --as "$OUTSIDE_ABS" 2>/dev/null)"
echo "$OUTSIDE_OUT" | grep -qF "$OUTSIDE_ABS"$'\t' \
  && ok "--as: absolute path outside any git repo is left unchanged" \
  || bad "--as: absolute-path fallback (outside repo)" "$OUTSIDE_OUT"

echo "== tokenize: stage order path -> project/account -> rest =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
bash "$VAULT" add project "SynthOrderProj" --group ordergrp >/dev/null 2>&1
bash "$VAULT" add path "synth/order-path" --group ordergrp >/dev/null 2>&1
OUT_TOK="$(printf 'x SynthOrderProj y synth/order-path z\n' | bash "$VAULT" tokenize)"
if echo "$OUT_TOK" | grep -qE 'proj-[0-9a-f]{6}' && echo "$OUT_TOK" | grep -qE '<proj-[0-9a-f]{6}>'; then
  ok "tokenize: project and its path alias both resolve to the shared token shape"
else
  bad "tokenize: stage order / token sharing" "$OUT_TOK"
fi

echo "== tokenize: --dry-run writes nothing, lists file:line:kind:token (no term) =="
DRYFILE="$SCRATCH/dryrun.txt"
printf 'hello SynthOrderProj world\n' > "$DRYFILE"
BEFORE_MTIME="$(stat -f '%m' "$DRYFILE" 2>/dev/null || stat -c '%Y' "$DRYFILE")"
BEFORE_CONTENT="$(cat "$DRYFILE")"
DRY_OUT="$(bash "$VAULT" tokenize --dry-run "$DRYFILE")"
AFTER_MTIME="$(stat -f '%m' "$DRYFILE" 2>/dev/null || stat -c '%Y' "$DRYFILE")"
AFTER_CONTENT="$(cat "$DRYFILE")"
[[ "$BEFORE_CONTENT" == "$AFTER_CONTENT" ]] && ok "tokenize --dry-run: file content unchanged" || bad "tokenize --dry-run content" "changed"
[[ "$BEFORE_MTIME" == "$AFTER_MTIME" ]] && ok "tokenize --dry-run: file mtime unchanged" || bad "tokenize --dry-run mtime" "changed"
echo "$DRY_OUT" | grep -qE ":1:project:proj-[0-9a-f]{6}$" && ok "tokenize --dry-run: lists file:line:kind:token" || bad "tokenize --dry-run format" "$DRY_OUT"
echo "$DRY_OUT" | grep -qF "SynthOrderProj" && bad "tokenize --dry-run: must NOT print the term" "leaked term" || ok "tokenize --dry-run: does not print the term"

echo "== tokenize: --in-place actually writes =="
INPLACE_FILE="$SCRATCH/inplace.txt"
printf 'hello SynthOrderProj world\n' > "$INPLACE_FILE"
bash "$VAULT" tokenize --in-place "$INPLACE_FILE"
grep -q "SynthOrderProj" "$INPLACE_FILE" && bad "tokenize --in-place: term must be gone" "still present" || ok "tokenize --in-place: term replaced on disk"
grep -qE 'proj-[0-9a-f]{6}' "$INPLACE_FILE" && ok "tokenize --in-place: token present on disk" || bad "tokenize --in-place: token" "missing"

echo "== resolve: inverse of tokenize (roundtrip) =="
ROUNDTRIP_SRC="hello SynthOrderProj and synth/order-path together"
ROUNDTRIP_OUT="$(printf '%s\n' "$ROUNDTRIP_SRC" | bash "$VAULT" tokenize | bash "$VAULT" resolve)"
[[ "$ROUNDTRIP_OUT" == "$ROUNDTRIP_SRC" ]] \
  && ok "resolve(tokenize(x)) == x (roundtrip on synthetic text)" \
  || bad "resolve roundtrip" "got: $ROUNDTRIP_OUT"

echo "== public identity (§7.1): init skips, add refuses, prune-public removes+idempotent, matcher never reports =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1

bash "$VAULT" add project "claude-rcode" --group pubgrp1 >/dev/null 2>&1
check_exit "add REFUSES an exact public name" 1 "$?"
bash "$VAULT" add project "CLAUDE-RCODE" --group pubgrp2 >/dev/null 2>&1
check_exit "add refusal is case-insensitive" 1 "$?"
bash "$VAULT" add project "claude-rcode-extra" --group longgrp >/dev/null 2>&1
check_exit "add ALLOWS a longer name that only contains a public name" 0 "$?"

# Round 3, nachtrag finding #6: third-party product names the framework
# works with (Cowork) are the SECOND public-names.txt category, and the
# case-insensitive match is explicit/intentional (owner decision).
bash "$VAULT" add project "Cowork" --group cowgrp1 >/dev/null 2>&1
check_exit "add refuses 'Cowork' (third-party product name category)" 1 "$?"
bash "$VAULT" add project "COWORK" --group cowgrp2 >/dev/null 2>&1
check_exit "add refuses 'COWORK' (case-insensitive, intentional per owner decision)" 1 "$?"

PUB_LEGACY="$(mktemp "${TMPDIR:-/tmp}/vault-regr-pub-legacy.XXXXXX")"
cat > "$PUB_LEGACY" <<'EOF'
claude-code-config	Projekt Z
SynthPublicSkipTest	Projekt Z
EOF
PUB_IMPORT_OUT="$(bash "$VAULT" init --import-legacy "$PUB_LEGACY" 2>&1)"
echo "$PUB_IMPORT_OUT" | grep -q "1 row(s) imported" && ok "init --import-legacy: the non-public alias in the group still imports" || bad "init --import-legacy public-skip: import count" "$PUB_IMPORT_OUT"
echo "$PUB_IMPORT_OUT" | grep -q "1 skipped (public framework identity" && ok "init --import-legacy: the public name is SKIPPED, not a conflict" || bad "init --import-legacy public-skip: skip count" "$PUB_IMPORT_OUT"
rm -f "$PUB_LEGACY"
grep -qi "claude-code-config" "$CLAUDE_VAULT_DIR/map.tsv" && bad "init --import-legacy: public name must not land in map.tsv" "found it" || ok "init --import-legacy: public name absent from map.tsv"

PUB_REGISTRY="$(mktemp "${TMPDIR:-/tmp}/vault-regr-pub-registry.XXXXXX")"
cat > "$PUB_REGISTRY" <<'EOF'
{"id":"pubregtest","name":"R.Code","pfad":"cat/synth-pub-reg-path","git":false}
EOF
PUB_REG_OUT="$(bash "$VAULT" init --from-registry "$PUB_REGISTRY" 2>&1)"
echo "$PUB_REG_OUT" | grep -q "1 skipped (public framework identity" && ok "init --from-registry: 'name'==public identity is skipped" || bad "init --from-registry public-skip" "$PUB_REG_OUT"
grep -q "cat/synth-pub-reg-path" "$CLAUDE_VAULT_DIR/map.tsv" && ok "init --from-registry: the non-public 'pfad' sibling still imports" || bad "init --from-registry: pfad import alongside public-name skip" "missing"
rm -f "$PUB_REGISTRY"

# Simulate a public-name row that predates public-names.txt (hand-edited
# map.tsv, or data imported before the file existed) — the matcher must
# still never report or rewrite it (defense-in-depth, not just prevention
# at add-time).
printf 'project\tR.Code\tproj-deadbe\tmanual-inject\n' >> "$CLAUDE_VAULT_DIR/map.tsv"
printf 'this mentions R.Code in prose\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "matcher (check) never reports a public name even if manually present in map.tsv" 0 "$?"
TOK_PUB_OUT="$(printf 'this mentions R.Code in prose\n' | bash "$VAULT" tokenize)"
[[ "$TOK_PUB_OUT" == "this mentions R.Code in prose" ]] \
  && ok "matcher (tokenize) never rewrites a public name even if manually present in map.tsv" \
  || bad "tokenize public-name defense-in-depth" "got: $TOK_PUB_OUT"

PRUNE_OUT1="$(bash "$VAULT" prune-public 2>&1)"
echo "$PRUNE_OUT1" | grep -q "removed 1 row(s)" && ok "prune-public: removes the manually-injected public-name row" || bad "prune-public: removal count" "$PRUNE_OUT1"
grep -qi "R\.Code" "$CLAUDE_VAULT_DIR/map.tsv" && bad "prune-public: row must be gone from map.tsv" "still present" || ok "prune-public: row gone from map.tsv"
PRUNE_OUT2="$(bash "$VAULT" prune-public 2>&1)"
echo "$PRUNE_OUT2" | grep -q "removed 0 row(s)" && ok "prune-public: idempotent (2nd run removes 0)" || bad "prune-public: idempotency" "$PRUNE_OUT2"

echo "== token <kind> <value>: derives without storing (round 3, finding #8) =="
CLAUDE_VAULT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vault-regr-nosecret.XXXXXX")/nonexistent" \
  bash "$VAULT" token project SynthTokenValue >/dev/null 2>/dev/null
check_exit "token: no secret -> Exit 1" 1 "$?"

fresh_vault
bash "$VAULT" init >/dev/null 2>&1
MAP_CKSUM_BEFORE="$(cksum "$CLAUDE_VAULT_DIR/map.tsv")"

TOK_A1="$(bash "$VAULT" token project SynthTokenValue 2>/dev/null)"
TOK_A2="$(bash "$VAULT" token project SynthTokenValue 2>/dev/null)"
[[ -n "$TOK_A1" && "$TOK_A1" == "$TOK_A2" ]] && ok "token: stable across two calls with the same value" || bad "token: stability" "A1=$TOK_A1 A2=$TOK_A2"
echo "$TOK_A1" | grep -qE '^proj-[0-9a-f]{6}$' && ok "token: kind=project shape is proj-<hex6>" || bad "token: project shape" "$TOK_A1"

TOK_ACCT="$(bash "$VAULT" token account SynthTokenValue 2>/dev/null)"
echo "$TOK_ACCT" | grep -qE '^acct-[0-9a-f]{6}$' && ok "token: kind=account shape is acct-<hex6>" || bad "token: account shape" "$TOK_ACCT"

TOK_ID="$(bash "$VAULT" token id SynthTokenValue 2>/dev/null)"
echo "$TOK_ID" | grep -qE '^id-[0-9a-f]{6}$' && ok "token: kind=id shape is id-<hex6> (new, additive)" || bad "token: id shape" "$TOK_ID"

bash "$VAULT" token phrase SynthTokenValue >/dev/null 2>&1
check_exit "token: kind without HMAC derivation (phrase) is refused" 1 "$?"
bash "$VAULT" token path SynthTokenValue >/dev/null 2>&1
check_exit "token: kind=path is refused (not in the allowed set)" 1 "$?"

MAP_CKSUM_AFTER="$(cksum "$CLAUDE_VAULT_DIR/map.tsv")"
[[ "$MAP_CKSUM_BEFORE" == "$MAP_CKSUM_AFTER" ]] \
  && ok "token: map.tsv checksum unchanged — nothing was stored" \
  || bad "token: map.tsv must stay unchanged" "before=$MAP_CKSUM_BEFORE after=$MAP_CKSUM_AFTER"

fresh_vault
bash "$VAULT" init >/dev/null 2>&1
TOK_OTHER_SECRET="$(bash "$VAULT" token project SynthTokenValue 2>/dev/null)"
[[ "$TOK_OTHER_SECRET" != "$TOK_A1" ]] \
  && ok "token: depends on the secret — a different vault's secret yields a different token for the same value" \
  || bad "token: secret-dependence" "expected different, both were $TOK_A1"

echo "== performance tripwire (round 4): a process-per-map-row regression must fail this loudly =="
# Not a precise benchmark (the real /usr/bin/time -p numbers against the
# real ~200-row vault go in the handback report) — a generous ceiling so a
# slow CI runner never flakes, while a REGRESSION back to the old
# process-per-row vault_strip_public_terms/vault_is_public_name (which
# measured ~2.65s against a ~200-row vault before this rework) would still
# clear 1.5s many times over on a 300-row synthetic vault and get caught.
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
{
  i=0
  while [[ $i -lt 300 ]]; do
    printf 'project\tSynthPerfTerm%d\tproj-%06x\tperfgrp%d\n' "$i" "$i" "$i"
    i=$((i + 1))
  done
} >> "$CLAUDE_VAULT_DIR/map.tsv"
PERF_START="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
printf 'a short line\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
PERF_END="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
# LC_ALL=C on both awk calls: macOS's stock /usr/bin/awk formats/parses
# "%.3f" using the CALLER's locale decimal separator (verified live: a
# de_DE locale prints "0,042" not "0.042") — without forcing C here, the
# elapsed-time string and the "< 1.5" numeric comparison below would both
# silently misparse under any comma-decimal locale.
PERF_ELAPSED="$(LC_ALL=C awk -v s="$PERF_START" -v e="$PERF_END" 'BEGIN{printf "%.3f", e-s}')"
if LC_ALL=C awk -v e="$PERF_ELAPSED" 'BEGIN{exit !(e+0 < 1.5)}'; then
  ok "performance tripwire: check --stdin against a 300-row temp vault took ${PERF_ELAPSED}s (< 1.5s)"
else
  bad "performance tripwire" "took ${PERF_ELAPSED}s, expected < 1.5s — likely a process-per-row regression in vault_strip_public_terms/vault_is_public_name"
fi

echo "== performance tripwire (round 6, 2026-09-25 Unicode-hardening perf fix): many lines, realistic non-ASCII density =="
# The round 4 tripwire above uses a SINGLE short line — it did NOT catch
# the real regression this test targets: after the Unicode-hardening round
# (NFC/NFD + invisible-character tolerance in find_vault_matches), a
# MULTI-LINE file where SOME lines carry a non-ASCII byte (very common —
# em-dashes, umlauts) became far slower, because every such line ran the
# full fuzzy pattern for every rule with no prefilter (measured live
# against this repo's own real ~222-row vault: a 4474-line file with ~6.5%
# non-ASCII lines went from 5.96s at HEAD to 33.26s with the unprefiltered
# fuzzy matcher). Calibrated live against three implementations on this
# EXACT scenario (300-row vault, 2000 lines, 10% carrying an em-dash — at
# or above the real-world density measured on this repo's own files):
# the fully unoptimized fuzzy matcher measured ~17.3s, an ASCII-only-fast-
# path fix WITHOUT a prefilter for the non-ASCII/fuzzy path measured
# ~1.89s, and the shipped fix (adds compact_nfc_bytes() as an index()
# prefilter target for the fuzzy path too) measures ~0.22s — the 1.5s
# ceiling below is chosen to fail against EITHER regression, not just the
# unoptimized one, while staying a comfortable ~6-7x above the shipped
# implementation's own measured time.
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
{
  i=0
  while [[ $i -lt 300 ]]; do
    printf 'project\tSynthPerfTermR6-%d\tproj-%06x\tperfgrpr6-%d\n' "$i" "$i" "$i"
    i=$((i + 1))
  done
} >> "$CLAUDE_VAULT_DIR/map.tsv"
MANYLINES="$SCRATCH/perf-r6-manylines.txt"
{
  i=0
  while [[ $i -lt 2000 ]]; do
    if [[ $((i % 10)) -eq 0 ]]; then
      printf 'line %d has an em-dash \xe2\x80\x94 and no vault term\n' "$i"
    else
      printf 'line %d is plain ascii prose with no vault term\n' "$i"
    fi
    i=$((i + 1))
  done
} > "$MANYLINES"
PERF6_START="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
bash "$VAULT" check "$MANYLINES" >/dev/null 2>/dev/null
PERF6_END="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
PERF6_ELAPSED="$(LC_ALL=C awk -v s="$PERF6_START" -v e="$PERF6_END" 'BEGIN{printf "%.3f", e-s}')"
if LC_ALL=C awk -v e="$PERF6_ELAPSED" 'BEGIN{exit !(e+0 < 1.5)}'; then
  ok "performance tripwire (round 6): 2000 lines (10% non-ASCII) against a 300-row vault took ${PERF6_ELAPSED}s (< 1.5s)"
else
  bad "performance tripwire (round 6)" "took ${PERF6_ELAPSED}s, expected < 1.5s — likely a missing/broken prefilter on the fuzzy (non-ASCII-line) path in find_vault_matches"
fi
rm -f "$MANYLINES"

echo "== round 5: tokenize honors the allowlist (finding #1, same function as check) =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
bash "$VAULT" add project "SynthR5Allow" --group r5allowgrp >/dev/null 2>&1
source "$REPO_ROOT/scripts/vault/lib.sh"
R5_RULES="$(mktemp "${TMPDIR:-/tmp}/vault-regr-r5-rules.XXXXXX")"
vault_build_rules_file "$R5_RULES"
R5_ALLOWFILE="$(mktemp "${TMPDIR:-/tmp}/vault-regr-r5-allow.XXXXXX")"
cat > "$R5_ALLOWFILE" <<'EOF'
some/path.md:1:SynthR5Allow
EOF
R5_TOK_OUT="$(printf 'mentions SynthR5Allow here\n' | vault_matcher_run tokenize 0 "some/path.md" "$R5_RULES" "$R5_ALLOWFILE" 0)"
[[ "$R5_TOK_OUT" == "mentions SynthR5Allow here" ]] \
  && ok "tokenize: allowlisted line left completely unchanged" \
  || bad "tokenize allowlist" "got: $R5_TOK_OUT"
R5_TOK_OUT2="$(printf 'mentions SynthR5Allow here\n' | vault_matcher_run tokenize 0 "some/OTHER-path.md" "$R5_RULES" "$R5_ALLOWFILE" 0)"
echo "$R5_TOK_OUT2" | grep -qE 'proj-[0-9a-f]{6}' \
  && ok "tokenize: the SAME line at a non-allowlisted path IS tokenized" \
  || bad "tokenize allowlist path-specificity" "got: $R5_TOK_OUT2"
rm -f "$R5_RULES" "$R5_ALLOWFILE"

echo "== round 5: EOF-newline preservation (finding #2) =="
R5_NOEOF="$(mktemp "${TMPDIR:-/tmp}/vault-regr-r5-noeof.XXXXXX")"
printf 'no trailing newline: SynthR5Allow' > "$R5_NOEOF"
bash "$VAULT" tokenize --in-place "$R5_NOEOF"
R5_LASTBYTE="$(tail -c1 "$R5_NOEOF" | od -An -tx1 | tr -d ' \n')"
[[ "$R5_LASTBYTE" != "0a" ]] \
  && ok "tokenize --in-place: no trailing newline added when the source had none" \
  || bad "EOF preservation" "a trailing 0a byte was added"
rm -f "$R5_NOEOF"

R5_WITHEOF="$(mktemp "${TMPDIR:-/tmp}/vault-regr-r5-witheof.XXXXXX")"
printf 'has trailing newline: SynthR5Allow\n' > "$R5_WITHEOF"
bash "$VAULT" tokenize --in-place "$R5_WITHEOF"
R5_LASTBYTE2="$(tail -c1 "$R5_WITHEOF" | od -An -tx1 | tr -d ' \n')"
[[ "$R5_LASTBYTE2" == "0a" ]] \
  && ok "tokenize --in-place: trailing newline preserved when the source had one" \
  || bad "EOF preservation (with newline)" "trailing newline was lost"
rm -f "$R5_WITHEOF"

echo "== round 5: --in-place writes only on change, preserves file mode (finding #2) =="
R5_NOOP="$(mktemp "${TMPDIR:-/tmp}/vault-regr-r5-noop.XXXXXX")"
printf 'nothing to replace here\n' > "$R5_NOOP"
chmod 755 "$R5_NOOP"
R5_MTIME_BEFORE="$(stat -f %m "$R5_NOOP" 2>/dev/null || stat -c %Y "$R5_NOOP")"
bash "$VAULT" tokenize --in-place "$R5_NOOP"
R5_MTIME_AFTER="$(stat -f %m "$R5_NOOP" 2>/dev/null || stat -c %Y "$R5_NOOP")"
[[ "$R5_MTIME_BEFORE" == "$R5_MTIME_AFTER" ]] \
  && ok "--in-place: file with no replacement is not rewritten (mtime unchanged)" \
  || bad "--in-place no-op" "mtime changed despite no replacement"
rm -f "$R5_NOOP"

R5_EXEC="$(mktemp "${TMPDIR:-/tmp}/vault-regr-r5-exec.XXXXXX")"
printf '#!/bin/bash\necho SynthR5Allow\n' > "$R5_EXEC"
chmod 755 "$R5_EXEC"
bash "$VAULT" tokenize --in-place "$R5_EXEC"
R5_MODE="$(stat -f '%Lp' "$R5_EXEC" 2>/dev/null || stat -c '%a' "$R5_EXEC")"
[[ "$R5_MODE" == "755" ]] \
  && ok "--in-place: executable file keeps mode 755 after a real replacement" \
  || bad "--in-place mode preservation" "mode is $R5_MODE, expected 755"
grep -qE 'proj-[0-9a-f]{6}' "$R5_EXEC" && ok "--in-place: the replacement itself did happen" || bad "--in-place replacement" "term still present"
rm -f "$R5_EXEC"

echo "== round 5: email widening — a vault term inside an email address (finding #5c) =="
printf 'contact info@SynthR5Allow.com please\n' | bash "$VAULT" check --stdin > "$SCRATCH/r5email.out" 2>/dev/null
grep -qE $'\temail\tinfo@SynthR5Allow\\.com\t<email>$' "$SCRATCH/r5email.out" \
  && ok "check: reports the WHOLE email address as kind=email, token=<email>" \
  || bad "check email widening" "$(cat "$SCRATCH/r5email.out")"
R5_EMAIL_TOK="$(printf 'contact info@SynthR5Allow.com please\n' | bash "$VAULT" tokenize)"
[[ "$R5_EMAIL_TOK" == "contact <email> please" ]] \
  && ok "tokenize: replaces the WHOLE address with <email>, not a hash glued into '@...'" \
  || bad "tokenize email widening" "got: $R5_EMAIL_TOK"

echo "== round 5: 'user' is a placeholder segment (finding #5a) =="
printf 'path is /home/user/foo\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "'/home/user/...' passes (generic placeholder, not a real segment)" 0 "$?"
printf 'path is /Users/user/foo\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "'/Users/user/...' passes too" 0 "$?"

echo "== round 5: user:pass@host is not an email (finding #5b) =="
printf 'visit https://user:pass@host.example.com/path\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "URL userinfo (user:pass@host) is not flagged as an email" 0 "$?"
printf 'contact real@example-real.tld\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "a real email (no preceding colon) still triggers" 2 "$?"

echo "== round 5: generalized id structural pattern (finding #4, scrub-check migration) =="
printf 'page id 36a42419d96e81c68821e55df6608222 end\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "bare 32 hex chars triggers (id shape, no UUID variant needed)" 2 "$?"
printf 'page id 36a42419-d96e-81c6-8821-e55df6608222 end\n' | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "dashed 8-4-4-4-12, non-v4 variant, triggers" 2 "$?"

echo "== HMAC hardening: old (openssl argv) method equals new (perl in-process) method (synthetic) =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
source "$REPO_ROOT/scripts/vault/lib.sh"
OLD_SECRET="$(cat "$CLAUDE_VAULT_DIR/secret")"
# Old method reimplemented ONCE, HERE ONLY, purely to prove the new
# derivation agrees with it byte-for-byte — the shipped code no longer
# contains this line (rules/testing-quality.md "same code path": this is
# a test asserting the NEW path agrees with the OLD one, not a second
# production matcher).
old_hmac_hex6() {
  printf '%s' "$1" | openssl dgst -sha256 -hmac "$OLD_SECRET" | awk '{print $NF}' | cut -c1-6
}
NEW_HEX="$(vault_hmac_hex6 "project:synthetic-hmac-check-group")"
OLD_HEX="$(old_hmac_hex6 "project:synthetic-hmac-check-group")"
[[ -n "$NEW_HEX" && "$NEW_HEX" == "$OLD_HEX" ]] \
  && ok "HMAC: new perl-in-process derivation byte-identical to old openssl-argv derivation" \
  || bad "HMAC old-vs-new" "new=$NEW_HEX old=$OLD_HEX"

HMAC_PL_SRC="$(mktemp "${TMPDIR:-/tmp}/vault-regr-hmacpl.XXXXXX")"
_vault_write_hmac_pl "$HMAC_PL_SRC"
grep -q "VAULT_SECRET_FILE" "$HMAC_PL_SRC" \
  && ok "HMAC helper reads the secret via an env-var PATH, not a literal" \
  || bad "HMAC helper" "VAULT_SECRET_FILE reference missing"
# Checks for an actual openssl INVOCATION, not the substring "-hmac" (which
# also occurs harmlessly inside this very file's "vault-hmac: cannot open
# secret file" die-message label).
grep -qi 'openssl' "$HMAC_PL_SRC" \
  && bad "HMAC helper must not shell out to openssl" "found 'openssl' in generated perl script" \
  || ok "HMAC helper never mentions openssl — pure in-process Digest::SHA"
rm -f "$HMAC_PL_SRC"
# Excludes comment lines: lib.sh's own doc-comment legitimately QUOTES the
# old "openssl ... -hmac \"\$secret\"" invocation shape as prose explaining
# why the new derivation's key bytes still match it — that is documentation,
# not a live code path. The check is for the pattern surviving in
# EXECUTABLE (non-comment) code.
grep -v '^[[:space:]]*#' "$REPO_ROOT/scripts/vault/lib.sh" | grep -qF -- '-hmac "$secret"' \
  && bad "lib.sh must not pass the secret via -hmac argv in executable code" "found it" \
  || ok "lib.sh: no -hmac \"\$secret\" argv pattern remains in executable code"

echo "== Unicode hardening: NFC vs NFD umlaut variant both match the same vault term =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
UMLAUT_TERM="$(printf 'SynthZ\xc3\xbcric')"
bash "$VAULT" add project "$UMLAUT_TERM" --group synthumlautgrp >/dev/null 2>&1

NFC_LINE="$(printf 'hello SynthZ\xc3\xbcric world')"
printf '%s\n' "$NFC_LINE" | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "NFC form (as stored) is found" 2 "$?"

NFD_LINE="$(printf 'hello SynthZ\x75\xcc\x88ric world')"
printf '%s\n' "$NFD_LINE" | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "NFD form (decomposed u + combining diaeresis) is ALSO found" 2 "$?"

NFD_TOK="$(printf '%s\n' "$NFD_LINE" | bash "$VAULT" tokenize)"
echo "$NFD_TOK" | grep -qE '^hello proj-[0-9a-f]{6} world$' \
  && ok "tokenize: NFD-form occurrence replaced wholesale by the token, rest of line intact" \
  || bad "tokenize NFD" "got: $NFD_TOK"

echo "== Unicode hardening: zero-width space embedded inside a term is still found and consumed whole =="
bash "$VAULT" add project "SynthZeroWidthTerm" --group synthzwgrp >/dev/null 2>&1
ZW_LINE="$(printf 'x SynthZero\xe2\x80\x8bWidthTerm y')"
printf '%s\n' "$ZW_LINE" | bash "$VAULT" check --stdin >/dev/null 2>/dev/null
check_exit "term with an embedded U+200B (zero-width space) is still found" 2 "$?"

ZW_TOK="$(printf '%s\n' "$ZW_LINE" | bash "$VAULT" tokenize)"
echo "$ZW_TOK" | grep -qE '^x proj-[0-9a-f]{6} y$' \
  && ok "tokenize: the WHOLE span (term + embedded ZWSP) is replaced, no stray ZWSP left behind" \
  || bad "tokenize ZWSP" "got: $ZW_TOK"

echo "== Unicode hardening: fund position (line number) correct; untouched lines stay byte-identical =="
ML_INPUT="$(printf 'line one untouched\nSynthZeroWidthTerm here on line two\nline three untouched\n')"
ML_CHECK_OUT="$(printf '%s' "$ML_INPUT" | bash "$VAULT" check --stdin 2>/dev/null)"
echo "$ML_CHECK_OUT" | grep -qE $'^-\t2\tproject\t' \
  && ok "check: line number of a matched vault term is still correct (line 2)" \
  || bad "check line number" "$ML_CHECK_OUT"
ML_TOK="$(printf '%s' "$ML_INPUT" | bash "$VAULT" tokenize)"
ML_FIRST="$(echo "$ML_TOK" | sed -n '1p')"
ML_THIRD="$(echo "$ML_TOK" | sed -n '3p')"
[[ "$ML_FIRST" == "line one untouched" && "$ML_THIRD" == "line three untouched" ]] \
  && ok "tokenize: lines NOT containing a match stay byte-identical" \
  || bad "tokenize byte-exactness outside match" "line1=[$ML_FIRST] line3=[$ML_THIRD]"

echo "== doctor: healthy vault -> exit 0; malformed map.tsv -> exit 1, line-number-only reporting =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
bash "$VAULT" doctor >/dev/null 2>/dev/null
check_exit "doctor: freshly initialized vault is healthy" 0 "$?"

chmod 644 "$CLAUDE_VAULT_DIR/secret"
DOCTOR_PERM_OUT="$(bash "$VAULT" doctor 2>&1 >/dev/null)"
bash "$VAULT" doctor >/dev/null 2>/dev/null
check_exit "doctor: secret file mode 644 (not 0600) is flagged, exit 1" 1 "$?"
echo "$DOCTOR_PERM_OUT" | grep -q "secret file is mode 644" \
  && ok "doctor: reports the actual observed mode" \
  || bad "doctor: mode report" "$DOCTOR_PERM_OUT"
chmod 600 "$CLAUDE_VAULT_DIR/secret"

printf 'project\tSynthDoctorBadFieldCount\tproj-abc123\n' >> "$CLAUDE_VAULT_DIR/map.tsv"
BAD_LINE_NO="$(wc -l < "$CLAUDE_VAULT_DIR/map.tsv" | tr -d ' ')"
DOCTOR_BAD_OUT="$(bash "$VAULT" doctor 2>&1 >/dev/null)"
bash "$VAULT" doctor >/dev/null 2>/dev/null
check_exit "doctor: malformed map.tsv row (wrong field count) -> exit 1" 1 "$?"
echo "$DOCTOR_BAD_OUT" | grep -qF "map.tsv:$BAD_LINE_NO" \
  && ok "doctor: reports the correct line number for the malformed row" \
  || bad "doctor: line number" "$DOCTOR_BAD_OUT"
echo "$DOCTOR_BAD_OUT" | grep -qF "SynthDoctorBadFieldCount" \
  && bad "doctor: must NEVER print the offending row's content" "leaked term" \
  || ok "doctor: does not leak the malformed row's term"

fresh_vault
bash "$VAULT" init >/dev/null 2>&1
printf 'notakind\tSynthDoctorTerm\tproj-abc123\tsynthgrp\n' >> "$CLAUDE_VAULT_DIR/map.tsv"
bash "$VAULT" doctor >/dev/null 2>/dev/null
check_exit "doctor: unknown kind -> exit 1" 1 "$?"
DOCTOR_KIND_OUT="$(bash "$VAULT" doctor 2>&1 >/dev/null)"
echo "$DOCTOR_KIND_OUT" | grep -q "unknown kind" && ok "doctor: reports 'unknown kind'" || bad "doctor: unknown-kind report" "$DOCTOR_KIND_OUT"
echo "$DOCTOR_KIND_OUT" | grep -qF "notakind" \
  && bad "doctor: must not print the bad kind value itself" "leaked kind value" \
  || ok "doctor: does not leak the unknown kind's literal value"
echo "$DOCTOR_KIND_OUT" | grep -qF "SynthDoctorTerm" \
  && bad "doctor: must not print the row's term either" "leaked term" \
  || ok "doctor: does not leak the row's term for an unknown-kind finding"

fresh_vault
bash "$VAULT" init >/dev/null 2>&1
printf 'project\t\tproj-abc123\tsynthgrp2\n' >> "$CLAUDE_VAULT_DIR/map.tsv"
bash "$VAULT" doctor >/dev/null 2>/dev/null
check_exit "doctor: empty term field -> exit 1" 1 "$?"
DOCTOR_EMPTYTERM_OUT="$(bash "$VAULT" doctor 2>&1 >/dev/null)"
echo "$DOCTOR_EMPTYTERM_OUT" | grep -q "empty term" && ok "doctor: reports 'empty term'" || bad "doctor: empty-term report" "$DOCTOR_EMPTYTERM_OUT"

fresh_vault
bash "$VAULT" init >/dev/null 2>&1
printf 'project\tSynthDoctorEmptyToken\t\tsynthgrp3\n' >> "$CLAUDE_VAULT_DIR/map.tsv"
bash "$VAULT" doctor >/dev/null 2>/dev/null
check_exit "doctor: empty token field -> exit 1" 1 "$?"
DOCTOR_EMPTYTOK_OUT="$(bash "$VAULT" doctor 2>&1 >/dev/null)"
echo "$DOCTOR_EMPTYTOK_OUT" | grep -q "empty token" && ok "doctor: reports 'empty token'" || bad "doctor: empty-token report" "$DOCTOR_EMPTYTOK_OUT"

echo ""
echo "vault-regression: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
