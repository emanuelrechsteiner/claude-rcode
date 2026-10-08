#!/bin/bash
# vault-check: fixtures (synthetic values only — invented stand-ins for structural/vault/secret matching, never a real term)
#
# scrub-check-regression.sh — regression suite for scripts/scrub-check.sh's
# public-CI-safe layer (IMP-219, plans/vault-by-design-2026-09-25.md;
# closes Befund H1 + H2 — see scripts/scrub-check.sh's own "PUBLIC-CI
# REDACTION" header comment for the finding numbers this pins).
#
# H1: a structural (vault-less) `path`-kind finding from `vault.sh check`
# used to be invisible to scrub-check.sh's own PII section (a kind
# whitelist there excluded "path"), and the file-NAME section skipped
# structural checks entirely whenever no vault was present — exactly the
# public-CI-without-a-vault scenario this gate exists to cover. Fixed by
# iterating every row `vault.sh check` returns, no second kind list.
#
# H2: scrub-check.sh used to print the FULL matched line (the actual
# secret/PII/rebrand VALUE) to stdout — a public GitHub Actions runner
# would turn one finding into a second, public copy of that value. Fixed
# with a redacted print format ("[<label>] <file>:<line> (<kind>)", never
# content/term/value) plus an independent GitHub Actions `::add-mask::`
# directive per found value inside real CI.
#
# ADDED-LINES-ONLY under --staged (2026-09-25, IMP-219, same task): §6's
# --staged branch used to grep the WHOLE staged blob of every selected file,
# so any of this repo's 47 reviewed pre-existing pre-rebrand mentions (in
# CHANGELOG.md, the improvement ledger, ...) re-blocked any unrelated staged
# edit to those files, forcing a routine `git commit --no-verify` that also
# disabled the same hook's separate vault check. Fixed so --staged only
# counts a finding on a line the staged diff itself ADDS (full-tree mode is
# untouched — see scrub-check.sh's own comment on this). The tests below (T9
# onward) exercise: a neutral append to a debt-carrying file staying clean, a
# genuinely new leak line still blocking, an EDITED pre-existing debt line
# still blocking (editing counts as adding), full-tree mode still catching an
# untouched pre-existing line, and a renamed+edited file being reported under
# its new path (the §2 file-selection fix, --diff-filter=ACM -> AMRC, needed
# for the rename case to be seen by --staged at all).
#
# NACHBESSERUNG (2026-09-25, same day, IMP-219, lead review round 2): the
# --staged rewrite above shipped with two further defects plus one latent
# hardening gap, all in the same block, fixed together:
#   Symptom 1 (bug) — an ADDED content line that itself starts with a second
#     literal '+' (e.g. actual content "++x") appears in the diff as "+++x"
#     and was misread as the file's own "+++ b/<path>" header: the finding
#     was silently missed AND the new-side line counter fell one short for
#     every following line in the hunk (same misclassification, harmlessly,
#     for a removed line starting with "--"). Fixed with a per-file
#     "have we seen the first @@ hunk yet" flag: before it, a lone
#     '+'-prefixed line is the header; after it, every '+'-prefixed line is
#     content, whatever it starts with.
#   Symptom 2 (performance) — the fix's own first cut forked a `printf | grep`
#     process PER ADDED LINE. Replaced with fork-free `[[ =~ ]]` plus a
#     narrowly-scoped, non-eval `nocasematch` toggle (restored to the
#     caller's original on/off state afterward), never wrapped around the
#     exclusion-path equality check (nocasematch affects plain `[[ == ]]`
#     too, not just `=~`).
#   Hardening 3 (latent) — §2's two file-listing commands had no
#     `-c core.quotePath=false`, so a non-ASCII tracked filename would come
#     back quoted+octal-escaped and silently fail to match anything
#     downstream. 0 such tracked paths exist in this repo today; fixed
#     before it can matter.
# T15-T17 below exercise these three; T9-T14 above already cover the
# baseline added-lines-only behavior and keep passing unchanged.
#
# NACHBESSERUNG 2 (2026-09-25, same day, IMP-219, lead review round 3): a
# commit whose staged files are ALL on an exclusion list (SELF_EXCLUDE:
# scripts/scrub-check.sh, scripts/scrub-allowlist.txt; REBRAND_CARVEOUT:
# MIGRATION.md, commands/rcode-upgrade.md) left `_rb_files_to_scan` empty,
# and bash 3.2 (stock /bin/bash) treats `"${arr[@]}"` of an EMPTY array as an
# unbound-variable error under `set -u` — crashing scrub-check.sh with
# "_rb_files_to_scan[@]: unbound variable" and BLOCKING the commit with no
# finding shown. Real-world impact: committing ONLY a new
# scripts/scrub-allowlist.txt entry — the exact remedy this hook's own
# message recommends — would itself be blocked. Fixed with an explicit
# `${#_rb_files_to_scan[@]} -gt 0` length guard around the whole
# nocasematch-toggle + scan loop (length checks on an empty array are safe
# under set -u even on bash 3.2; only `[@]`/`[*]` element expansion is not).
# T18-T21 below exercise: staging only an excluded file (two variants) stays
# clean, and a mixed commit (one excluded file + one normal file with a new
# leak) still blocks and reports only the normal file.
#
# SAFETY — this suite runs ENTIRELY inside throwaway temp git repos with
# their own throwaway CLAUDE_VAULT_DIR, explicitly set on EVERY single
# invocation below — never omitted, since an unset CLAUDE_VAULT_DIR falls
# back to the REAL ~/.claude/vault (scripts/vault/lib.sh's vault_dir()). A
# tripwire at the bottom re-checks the real vault's map.tsv/secret mtimes
# against a snapshot taken before the first test, so an accidental
# omission turns into a loud FAIL rather than a silent, undetected real-
# vault touch. Only the SPECIFIC fixture file(s) each group creates are
# staged/committed (never `git add -A`) — the temp repos also carry a copy
# of scripts/vault/lib.sh (needed for scrub-check.sh to source it) whose
# own regex-definition lines are structurally path/email/id-shaped by
# necessity; leaving that file untracked keeps each test's tracked-file set
# limited to exactly the fixture(s) it is asserting about. The fixture
# marker above MUST close its parenthetical on the SAME line
# (plans/vault-by-design-2026-09-25.md §7.2 — an earlier suite in this repo
# got this wrong once and was scanned like any other tracked file).
#
# NOTE on the fake secret / rebrand-term literals below: this suite's own
# source text must not itself contain a contiguous secret-shaped or
# rebrand-name-shaped string (scripts/scrub-check.sh's own header comment
# explains why: hooks/security-audit.sh's PreToolUse hook would flag this
# very file the moment it is written/edited). Both are assembled from
# adjacent quoted fragments — the same technique scrub-check.sh and
# scripts/tests/git-hooks-regression.sh already use.
#
# Usage: bash scripts/tests/scrub-check-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRUB_SRC="$REPO_ROOT/scripts/scrub-check.sh"
VAULT_SRC="$REPO_ROOT/scripts/vault/vault.sh"
LIB_SRC="$REPO_ROOT/scripts/vault/lib.sh"
ALLOWLIST_SRC="$REPO_ROOT/scripts/scrub-allowlist.txt"
for _f in "$SCRUB_SRC" "$VAULT_SRC" "$LIB_SRC" "$ALLOWLIST_SRC"; do
  [[ -f "$_f" ]] || { echo "ERROR: required source not found: $_f" >&2; exit 1; }
done

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \xe2\x9c\x85 %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \xe2\x9d\x8c %s\n     %s\n' "$1" "$2"; }
check_exit() {  # check_exit <label> <expected> <actual>
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then ok "$label"; else bad "$label" "expected exit $expected, got $actual"; fi
}
must_not_contain() {  # must_not_contain <label> <haystack> <needle>
  local label="$1" haystack="$2" needle="$3"
  if printf '%s\n' "$haystack" | grep -qF -- "$needle"; then
    bad "$label" "unexpectedly found in output"
  else
    ok "$label"
  fi
}
must_contain() {  # must_contain <label> <haystack> <needle>
  local label="$1" haystack="$2" needle="$3"
  if printf '%s\n' "$haystack" | grep -qF -- "$needle"; then
    ok "$label"
  else
    bad "$label" "not found in output"
  fi
}

# ---------------------------------------------------------------------------
# Real-vault tripwire (armed before anything else runs, read again at the
# very end): this suite must NEVER change the real ~/.claude/vault. Every
# invocation below sets CLAUDE_VAULT_DIR explicitly to a throwaway path —
# this is a second, independent detector in case one ever doesn't.
# ---------------------------------------------------------------------------
REAL_VAULT_DIR="${HOME}/.claude/vault"
snapshot_real_vault() {
  local m1="" m2=""
  [[ -f "$REAL_VAULT_DIR/map.tsv" ]] && m1="$(stat -f '%m' "$REAL_VAULT_DIR/map.tsv" 2>/dev/null || stat -c '%Y' "$REAL_VAULT_DIR/map.tsv" 2>/dev/null)"
  [[ -f "$REAL_VAULT_DIR/secret" ]] && m2="$(stat -f '%m' "$REAL_VAULT_DIR/secret" 2>/dev/null || stat -c '%Y' "$REAL_VAULT_DIR/secret" 2>/dev/null)"
  printf 'map=%s secret=%s' "$m1" "$m2"
}
REAL_VAULT_BEFORE="$(snapshot_real_vault)"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/scrub-check-regr.XXXXXX")"
[[ -n "$SCRATCH" && -d "$SCRATCH" ]] || { echo "FATAL: mktemp failed to create a scratch dir" >&2; exit 1; }
trap 'rm -rf "$SCRATCH"' EXIT

# new_temp_repo — a bare repo tree with the real scrub-check.sh + vault.sh +
# lib.sh + scrub-allowlist.txt copied in (never a symlink back to this
# repo, so a test can never scan or write to the real tree).
new_temp_repo() {  # -> prints the repo's absolute path on stdout
  local t
  t="$(mktemp -d "$SCRATCH/repo.XXXXXX")"
  if [[ -z "$t" || ! -d "$t" ]]; then
    echo "scrub-check-regression: FATAL — mktemp failed to create a temp repo dir under '$SCRATCH'" >&2
    exit 1
  fi
  git init -q "$t"
  git -C "$t" config user.email "test@example.com"
  git -C "$t" config user.name "Test User"
  mkdir -p "$t/scripts/vault"
  cp "$VAULT_SRC" "$t/scripts/vault/vault.sh"
  cp "$LIB_SRC" "$t/scripts/vault/lib.sh"
  cp "$SCRUB_SRC" "$t/scripts/scrub-check.sh"
  cp "$ALLOWLIST_SRC" "$t/scripts/scrub-allowlist.txt"
  chmod +x "$t/scripts/vault/vault.sh" "$t/scripts/scrub-check.sh"
  printf '%s' "$t"
}

commit_files() {  # commit_files <repo> <message> <file>...
  local repo="$1" msg="$2"
  shift 2
  git -C "$repo" add "$@"
  git -C "$repo" -c commit.gpgsign=false commit -q -m "$msg" >/dev/null
}

# run_scrub <repo> <vault-dir> [extra scrub-check.sh args...] — runs
# against an EXPLICIT, throwaway vault dir every single time (never unset).
run_scrub() {
  local repo="$1" vdir="$2"
  shift 2
  ( cd "$repo" && env -u GITHUB_ACTIONS -u CI CLAUDE_VAULT_DIR="$vdir" bash scripts/scrub-check.sh "$@" 2>&1 )
}
run_scrub_ci() {  # same, but with GITHUB_ACTIONS=true (the automatic trigger)
  local repo="$1" vdir="$2"
  shift 2
  ( cd "$repo" && env -u CI GITHUB_ACTIONS=true CLAUDE_VAULT_DIR="$vdir" bash scripts/scrub-check.sh "$@" 2>&1 )
}

NOVAULT="$SCRATCH/no-such-vault"   # deliberately never created -> "no vault"

echo "== clean tree: clean + exit 0 =="
T1="$(new_temp_repo)"
printf 'hello, harmless content\n' > "$T1/clean.txt"
commit_files "$T1" "seed" clean.txt
OUT1="$(run_scrub "$T1" "$NOVAULT")"; RC1=$?
check_exit "clean tree: scrub-check exits 0" 0 "$RC1"
must_contain "clean tree: prints 'scrub-check: clean'" "$OUT1" "scrub-check: clean"

echo "== synthetic structural path -> BLOCKED (Befund H1) =="
T2="$(new_temp_repo)"
printf 'Pfad: /Users/synthscrubfaketester/projekt\n' > "$T2/path-leak.txt"
commit_files "$T2" "add path leak" path-leak.txt
OUT2="$(run_scrub "$T2" "$NOVAULT")"; RC2=$?
check_exit "structural path: scrub-check exits 1 (BLOCKED)" 1 "$RC2"
must_contain "structural path: reported as kind=path" "$OUT2" "kind=path"
must_contain "structural path: names the leaked path locally" "$OUT2" "/Users/synthscrubfaketester/projekt"

echo "== synthetic structural email -> BLOCKED =="
T3="$(new_temp_repo)"
printf 'contact synthscrubprobe@synthmailtest.dev for details\n' > "$T3/email-leak.txt"
commit_files "$T3" "add email leak" email-leak.txt
OUT3="$(run_scrub "$T3" "$NOVAULT")"; RC3=$?
check_exit "structural email: scrub-check exits 1 (BLOCKED)" 1 "$RC3"
must_contain "structural email: reported as kind=email" "$OUT3" "kind=email"

echo "== synthetic vault-registered term -> BLOCKED =="
T4="$(new_temp_repo)"
VDIR4="$SCRATCH/vault4"
CLAUDE_VAULT_DIR="$VDIR4" bash "$T4/scripts/vault/vault.sh" init >/dev/null 2>&1
CLAUDE_VAULT_DIR="$VDIR4" bash "$T4/scripts/vault/vault.sh" add project "SynthScrubProbeCorp" --group scrubprobe4 >/dev/null 2>&1
printf 'owner: SynthScrubProbeCorp\n' > "$T4/term-leak.txt"
commit_files "$T4" "add vault-term leak" term-leak.txt
OUT4="$(run_scrub "$T4" "$VDIR4")"; RC4=$?
check_exit "vault term: scrub-check exits 1 (BLOCKED)" 1 "$RC4"
must_contain "vault term: reported as kind=project with a token" "$OUT4" "kind=project term=SynthScrubProbeCorp token=proj-"

echo "== --require-pseudonym-list without a vault -> FATAL =="
OUT5="$(run_scrub "$T1" "$NOVAULT" --require-pseudonym-list)"; RC5=$?
check_exit "no vault + --require-pseudonym-list: exit 1 (fatal)" 1 "$RC5"
must_contain "no vault + --require-pseudonym-list: FATAL message shown" "$OUT5" "FATAL"

echo "== allowlisted finding is suppressed; an un-allowlisted sibling still fires =="
T6="$(new_temp_repo)"
printf 'structural test 36a42419d96e81c68821e55df6608222 end\n' > "$T6/allow-me.txt"
printf 'contact synthscrubkeep@synthmailtest.dev stays a finding\n' > "$T6/keep-me.txt"
commit_files "$T6" "add allowlist fixtures" allow-me.txt keep-me.txt
PRE6="$(run_scrub "$T6" "$NOVAULT")"
must_contain "allowlist: BEFORE allowlisting, allow-me.txt is reported" "$PRE6" "allow-me.txt"
printf 'allow-me.txt:1:structural test\n' >> "$T6/scripts/scrub-allowlist.txt"
POST6="$(run_scrub "$T6" "$NOVAULT")"; RC6=$?
must_not_contain "allowlist: AFTER allowlisting, allow-me.txt is no longer reported" "$POST6" "allow-me.txt"
must_contain "allowlist: the un-allowlisted sibling (keep-me.txt) still fires" "$POST6" "keep-me.txt"
check_exit "allowlist: sibling finding still blocks the run" 1 "$RC6"

echo "== GITHUB_ACTIONS=true: redacted output, no raw values, but ::add-mask:: present (Befund H2) =="
T7="$(new_temp_repo)"
VDIR7="$SCRATCH/vault7"
CLAUDE_VAULT_DIR="$VDIR7" bash "$T7/scripts/vault/vault.sh" init >/dev/null 2>&1
CLAUDE_VAULT_DIR="$VDIR7" bash "$T7/scripts/vault/vault.sh" add project "SynthScrubCiProbeCorp" --group scrubprobe7 >/dev/null 2>&1
printf 'Pfad: /Users/synthscrubcitester/projekt\n' > "$T7/path-leak.txt"
printf 'contact synthscrubci@synthmailtest.dev for details\n' > "$T7/email-leak.txt"
printf 'owner: SynthScrubCiProbeCorp\n' > "$T7/term-leak.txt"
_fake_ghp="gh""p_A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q7R8"
printf 'const token = "%s";\n' "$_fake_ghp" > "$T7/secret-leak.txt"
commit_files "$T7" "add combined leak fixtures" path-leak.txt email-leak.txt term-leak.txt secret-leak.txt
OUT7_CI="$(run_scrub_ci "$T7" "$VDIR7")"; RC7=$?
check_exit "CI redaction: scrub-check still exits 1 (BLOCKED)" 1 "$RC7"
# The value MUST be absent from the human-visible surface — every line
# EXCEPT the ::add-mask:: directive lines, whose own payload necessarily
# contains the value (that is how GitHub Actions is told what to hide — a
# real Actions runner consumes/strips that line entirely before a human
# ever sees it; a plain grep -F over raw captured stdout, run outside an
# actual runner as this suite does, would otherwise always "see" the value
# inside its own mask directive and misreport a leak a real CI viewer would
# never show).
VISIBLE7="$(printf '%s\n' "$OUT7_CI" | grep -v '^::add-mask::')"
must_not_contain "CI redaction: visible output has no raw path" "$VISIBLE7" "/Users/synthscrubcitester/projekt"
must_not_contain "CI redaction: visible output has no raw vault term" "$VISIBLE7" "SynthScrubCiProbeCorp"
must_not_contain "CI redaction: visible output has no raw email" "$VISIBLE7" "synthscrubci@synthmailtest.dev"
must_not_contain "CI redaction: visible output has no raw secret" "$VISIBLE7" "$_fake_ghp"
must_contain "CI redaction: reduced format shows (path)" "$VISIBLE7" "(path)"
must_contain "CI redaction: reduced format shows (project)" "$VISIBLE7" "(project)"
must_contain "CI redaction: reduced format shows (email)" "$VISIBLE7" "(email)"
must_contain "CI redaction: reduced format shows (secret)" "$VISIBLE7" "(secret)"
PII_COUNT7="$(printf '%s\n' "$VISIBLE7" | grep -c '^  \[PII\]')"
[[ "$PII_COUNT7" -eq 3 ]] \
  && ok "CI redaction: exactly 3 [PII] findings counted (path+email+project)" \
  || bad "CI redaction: [PII] count" "expected 3, got $PII_COUNT7"
MASK_COUNT7="$(printf '%s\n' "$OUT7_CI" | grep -c '^::add-mask::')"
[[ "$MASK_COUNT7" -ge 4 ]] \
  && ok "CI redaction: at least 4 ::add-mask:: directives emitted (got $MASK_COUNT7)" \
  || bad "CI redaction: mask count" "expected >=4, got $MASK_COUNT7"
must_contain "CI redaction: the secret's own mask directive carries the exact value (2nd, independent safeguard)" "$OUT7_CI" "::add-mask::$_fake_ghp"

echo "== CI=true (not GITHUB_ACTIONS) triggers the same redaction+mask =="
OUT7_CI2="$( cd "$T7" && env -u GITHUB_ACTIONS CI=true CLAUDE_VAULT_DIR="$VDIR7" bash scripts/scrub-check.sh 2>&1 )"
must_contain "CI=true: also emits ::add-mask::" "$OUT7_CI2" "::add-mask::"

echo "== without any CI variable: full, verbose output names the finding =="
OUT7_LOCAL="$(run_scrub "$T7" "$VDIR7")"
must_contain "local (no CI): names the vault term in the clear" "$OUT7_LOCAL" "term=SynthScrubCiProbeCorp"
must_not_contain "local (no CI): no ::add-mask:: outside CI" "$OUT7_LOCAL" "::add-mask::"

echo "== --redact flag alone (no CI vars): reduced format, but no ::add-mask:: =="
OUT7_REDACT="$(run_scrub "$T7" "$VDIR7" --redact)"
must_not_contain "--redact alone: vault term is hidden" "$OUT7_REDACT" "SynthScrubCiProbeCorp"
must_contain "--redact alone: reduced (kind) format is used" "$OUT7_REDACT" "(project)"
must_not_contain "--redact alone: no ::add-mask:: outside real CI (by design, see scrub-check.sh header)" "$OUT7_REDACT" "::add-mask::"

echo "== REBRAND finding is also redacted under CI (Befund H2 names REBRAND explicitly) =="
T8="$(new_temp_repo)"
_rebrand="tor""valdsen"
printf 'leftover pre-rebrand name: %s\n' "$_rebrand" > "$T8/leftover.txt"
commit_files "$T8" "add rebrand leftover" leftover.txt
OUT8_LOCAL="$(run_scrub "$T8" "$NOVAULT")"
must_contain "rebrand local: names the term in the clear" "$OUT8_LOCAL" "$_rebrand"
OUT8_CI="$(run_scrub_ci "$T8" "$NOVAULT")"
VISIBLE8="$(printf '%s\n' "$OUT8_CI" | grep -v '^::add-mask::')"
must_not_contain "rebrand CI: visible output has no raw term" "$VISIBLE8" "$_rebrand"
must_contain "rebrand CI: reduced format shows (rebrand)" "$VISIBLE8" "(rebrand)"
must_contain "rebrand CI: mask directive carries the term" "$OUT8_CI" "::add-mask::$_rebrand"

# ---------------------------------------------------------------------------
# IMP-219 rebrand --staged fix (2026-09-25, same task as this comment block):
# T9-T14 below exercise the added-lines-only rewrite of §6's --staged branch,
# plus the §2 file-selection fix (--diff-filter=ACM -> AMRC) it depends on for
# the rename case. Full-tree mode (T13) stays on the pre-existing whole-blob
# `git grep` path and is included here only as the explicit before/after
# contrast, not because its own behavior changed.
# ---------------------------------------------------------------------------
_rebrand2="tor""valdsen"

echo "== --staged: a neutral appended line to a file with a pre-existing debt line -> clean =="
T9="$(new_temp_repo)"
printf 'line one harmless\nline two mentions %s (pre-existing, accepted debt)\nline three harmless\n' "$_rebrand2" > "$T9/debt.txt"
commit_files "$T9" "seed debt file" debt.txt
printf 'line one harmless\nline two mentions %s (pre-existing, accepted debt)\nline three harmless\nline four is a brand new neutral line\n' "$_rebrand2" > "$T9/debt.txt"
git -C "$T9" add debt.txt
OUT9="$(run_scrub "$T9" "$NOVAULT" --staged)"; RC9=$?
check_exit "staged: neutral append to a debt-carrying file exits 0" 0 "$RC9"
must_contain "staged: neutral append prints 'scrub-check: clean'" "$OUT9" "scrub-check: clean"
must_not_contain "staged: neutral append never names REBRAND" "$OUT9" "REBRAND"

echo "== --staged: a NEW line added to a previously clean file, naming the old name -> BLOCKED =="
T10="$(new_temp_repo)"
printf 'clean line one\nclean line two\n' > "$T10/plain.txt"
commit_files "$T10" "seed plain file" plain.txt
printf 'clean line one\nclean line two\nnewly added line names %s\n' "$_rebrand2" > "$T10/plain.txt"
git -C "$T10" add plain.txt
OUT10="$(run_scrub "$T10" "$NOVAULT" --staged)"; RC10=$?
check_exit "staged: newly added leak line exits 1 (BLOCKED)" 1 "$RC10"
must_contain "staged: newly added leak line reported at its new-side line number" "$OUT10" "[REBRAND] plain.txt:3:"

echo "== --staged: EDITING a pre-existing debt line counts as adding it -> BLOCKED =="
T11="$(new_temp_repo)"
printf 'line one\nline two mentions %s (pre-existing, accepted debt)\nline three\n' "$_rebrand2" > "$T11/debt2.txt"
commit_files "$T11" "seed debt file" debt2.txt
printf 'line one\nline two EDITED still mentions %s\nline three\n' "$_rebrand2" > "$T11/debt2.txt"
git -C "$T11" add debt2.txt
OUT11="$(run_scrub "$T11" "$NOVAULT" --staged)"; RC11=$?
check_exit "staged: editing a pre-existing debt line exits 1 (BLOCKED)" 1 "$RC11"
must_contain "staged: edited debt line reported at line 2 with its new content" "$OUT11" "[REBRAND] debt2.txt:2:line two EDITED still mentions $_rebrand2"

echo "== --staged: a brand-new file containing the old name -> BLOCKED =="
T12="$(new_temp_repo)"
printf 'harmless seed\n' > "$T12/seed2.txt"
commit_files "$T12" "seed" seed2.txt
printf 'brand new file mentions %s\n' "$_rebrand2" > "$T12/newfile2.txt"
git -C "$T12" add newfile2.txt
OUT12="$(run_scrub "$T12" "$NOVAULT" --staged)"; RC12=$?
check_exit "staged: new file with the old name exits 1 (BLOCKED)" 1 "$RC12"
must_contain "staged: new file finding reported under its own path" "$OUT12" "[REBRAND] newfile2.txt:1:"

echo "== full-tree: a pre-existing debt line with nothing staged is still reported (criterion 3 contrast) =="
T13="$(new_temp_repo)"
printf 'line one harmless\nline two mentions %s (pre-existing, accepted debt)\nline three harmless\n' "$_rebrand2" > "$T13/debt3.txt"
commit_files "$T13" "seed debt file" debt3.txt
OUT13="$(run_scrub "$T13" "$NOVAULT")"; RC13=$?
check_exit "full-tree: pre-existing debt line exits 1 (BLOCKED, unchanged behavior)" 1 "$RC13"
must_contain "full-tree: reports the pre-existing debt line" "$OUT13" "[REBRAND] debt3.txt:2:line two mentions $_rebrand2"

echo "== --staged: a renamed+edited file with a NEW old-name line is reported under its NEW path =="
T14="$(new_temp_repo)"
printf 'harmless original content\nline two\nline three\nline four\nline five\n' > "$T14/orig-name.txt"
commit_files "$T14" "seed" orig-name.txt
git -C "$T14" mv orig-name.txt renamed-name.txt
printf 'harmless original content\nline two\nline three\nline four\nline five\nnew leak: %s\n' "$_rebrand2" > "$T14/renamed-name.txt"
git -C "$T14" add renamed-name.txt
OUT14="$(run_scrub "$T14" "$NOVAULT" --staged)"; RC14=$?
check_exit "staged: rename+edit with a new leak line exits 1 (BLOCKED)" 1 "$RC14"
must_contain "staged: rename+edit reported under the NEW path" "$OUT14" "[REBRAND] renamed-name.txt:6:"
must_not_contain "staged: rename+edit finding never names the OLD path" "$OUT14" "orig-name.txt:"

echo "== --staged: a content line starting with a second literal '+' (\"++x...\") is scanned as content, not misread as a diff header (Nachbesserung Symptom 1) =="
T15="$(new_temp_repo)"
printf 'line one\n' > "$T15/plusplus.txt"
commit_files "$T15" "seed" plusplus.txt
printf 'line one\n++x mentions %s\nharmless middle line\nthird added line mentions %s too\n' "$_rebrand2" "$_rebrand2" > "$T15/plusplus.txt"
git -C "$T15" add plusplus.txt
OUT15="$(run_scrub "$T15" "$NOVAULT" --staged)"; RC15=$?
check_exit "staged: '++'-prefixed leak line exits 1 (BLOCKED)" 1 "$RC15"
must_contain "staged: '++'-prefixed leak reported at its correct line (2), not skipped as a header" "$OUT15" "[REBRAND] plusplus.txt:2:++x mentions $_rebrand2"
must_contain "staged: a later leak in the same hunk keeps the correct line number (4), not shifted by the header misparse" "$OUT15" "[REBRAND] plusplus.txt:4:third added line mentions $_rebrand2 too"

echo "== --staged: a removed line starting with a second literal '-' (\"--x...\") never shifts the new-side line counter (Nachbesserung Symptom 1 companion) =="
T16="$(new_temp_repo)"
printf 'alpha\n--old removed line beta\ngamma\ndelta\n' > "$T16/minusminus.txt"
commit_files "$T16" "seed" minusminus.txt
printf 'alpha\ngamma\ndelta\nnew leak: %s\n' "$_rebrand2" > "$T16/minusminus.txt"
git -C "$T16" add minusminus.txt
OUT16="$(run_scrub "$T16" "$NOVAULT" --staged)"; RC16=$?
check_exit "staged: leak after a '--'-prefixed removed line exits 1 (BLOCKED)" 1 "$RC16"
must_contain "staged: leak line number correctly accounts for the earlier removal (line 4)" "$OUT16" "[REBRAND] minusminus.txt:4:new leak: $_rebrand2"

echo "== --staged: a new file with a non-ASCII (umlaut) name is scanned and reported under its readable name (Nachbesserung Hardening 3, core.quotePath) =="
T17="$(new_temp_repo)"
printf 'seed\n' > "$T17/seed3.txt"
commit_files "$T17" "seed" seed3.txt
UMLAUT_FILE17="$(printf '\xc3\x9cbersicht-leak.txt')"
printf 'contains %s here\n' "$_rebrand2" > "$T17/$UMLAUT_FILE17"
git -C "$T17" add -- "$UMLAUT_FILE17"
OUT17="$(run_scrub "$T17" "$NOVAULT" --staged)"; RC17=$?
check_exit "staged: umlaut-named new file with a leak exits 1 (BLOCKED)" 1 "$RC17"
must_contain "staged: reported under the readable (non-quoted-escaped) filename" "$OUT17" "[REBRAND] ${UMLAUT_FILE17}:1:"
must_not_contain "staged: never reports the octal-escaped/quoted form" "$OUT17" '\303\234'

echo "== --staged: ONLY an excluded file (scripts/scrub-check.sh itself) staged -> clean, no crash (Nachbesserung 2) =="
T18="$(new_temp_repo)"
printf 'seed\n' > "$T18/seed4.txt"
commit_files "$T18" "seed" seed4.txt
printf '\n# a harmless appended comment\n' >> "$T18/scripts/scrub-check.sh"
git -C "$T18" add scripts/scrub-check.sh
OUT18="$(run_scrub "$T18" "$NOVAULT" --staged)"; RC18=$?
check_exit "staged: only scripts/scrub-check.sh staged exits 0 (clean, not a crash)" 0 "$RC18"
must_contain "staged: only scripts/scrub-check.sh staged prints 'scrub-check: clean'" "$OUT18" "scrub-check: clean"
must_not_contain "staged: only scripts/scrub-check.sh staged never mentions the unbound-variable crash" "$OUT18" "unbound variable"

echo "== --staged: ONLY scripts/scrub-allowlist.txt staged -> clean, no crash (Nachbesserung 2, the exact real-world case) =="
T19="$(new_temp_repo)"
printf 'seed\n' > "$T19/seed5.txt"
commit_files "$T19" "seed" seed5.txt
printf '\nseed5.txt:1:structural test\n' >> "$T19/scripts/scrub-allowlist.txt"
git -C "$T19" add scripts/scrub-allowlist.txt
OUT19="$(run_scrub "$T19" "$NOVAULT" --staged)"; RC19=$?
check_exit "staged: only scripts/scrub-allowlist.txt staged exits 0 (clean, not a crash)" 0 "$RC19"
must_contain "staged: only scripts/scrub-allowlist.txt staged prints 'scrub-check: clean'" "$OUT19" "scrub-check: clean"
must_not_contain "staged: only scripts/scrub-allowlist.txt staged never mentions the unbound-variable crash" "$OUT19" "unbound variable"

echo "== --staged: ONLY MIGRATION.md staged -> clean, no crash (Nachbesserung 2) =="
T20="$(new_temp_repo)"
printf 'seed\n' > "$T20/seed6.txt"
commit_files "$T20" "seed" seed6.txt
printf 'This project used to be called something else. See history for details.\n' > "$T20/MIGRATION.md"
git -C "$T20" add MIGRATION.md
OUT20="$(run_scrub "$T20" "$NOVAULT" --staged)"; RC20=$?
check_exit "staged: only MIGRATION.md staged exits 0 (clean, not a crash)" 0 "$RC20"
must_contain "staged: only MIGRATION.md staged prints 'scrub-check: clean'" "$OUT20" "scrub-check: clean"
must_not_contain "staged: only MIGRATION.md staged never mentions the unbound-variable crash" "$OUT20" "unbound variable"

echo "== --staged: mixed commit (one excluded file + one normal file with a new leak) -> still blocked, reports ONLY the normal file (Nachbesserung 2) =="
T21="$(new_temp_repo)"
printf 'seed\n' > "$T21/normal.txt"
commit_files "$T21" "seed" normal.txt
printf '\n# a harmless appended comment\n' >> "$T21/scripts/scrub-check.sh"
printf 'seed\nnewly added leak: %s\n' "$_rebrand2" > "$T21/normal.txt"
git -C "$T21" add scripts/scrub-check.sh normal.txt
OUT21="$(run_scrub "$T21" "$NOVAULT" --staged)"; RC21=$?
check_exit "staged: mixed excluded+normal commit exits 1 (BLOCKED)" 1 "$RC21"
must_contain "staged: mixed commit reports the normal file's new leak" "$OUT21" "[REBRAND] normal.txt:2:newly added leak: $_rebrand2"
must_not_contain "staged: mixed commit never reports the excluded file" "$OUT21" "scrub-check.sh:"
must_not_contain "staged: mixed commit never mentions the unbound-variable crash" "$OUT21" "unbound variable"

echo "== chronicle carve-out (2026-10-01): the five chronicle files are skipped, every other file is not =="
T22="$(new_temp_repo)"
_chron=(CHANGELOG.md global-observation/improvement-ledger.json
        docs/superpowers/specs/2026-05-27-claude-config-portability-design.md
        ops/awesome-claude-code/HANDOFF-coding-agent.json
        ops/decisions/2026-08-13-publisher-stilllegung.md)
for _cf in "${_chron[@]}"; do
  mkdir -p "$T22/$(dirname "$_cf")"
  printf 'history line that mentions %s on purpose\n' "$_rebrand2" > "$T22/$_cf"
done
printf 'harmless\n' > "$T22/normal.txt"
commit_files "$T22" "seed chronicle" "${_chron[@]}" normal.txt
OUT22="$(run_scrub "$T22" "$NOVAULT")"; RC22=$?
check_exit "carve-out: old name only in the five chronicle files, full-tree exits 0 (clean)" 0 "$RC22"
must_not_contain "carve-out: no chronicle file is reported" "$OUT22" "[REBRAND]"

printf 'a live doc that still says %s\n' "$_rebrand2" > "$T22/notes.txt"
commit_files "$T22" "add a non-chronicle leak" notes.txt
OUT22B="$(run_scrub "$T22" "$NOVAULT")"; RC22B=$?
check_exit "carve-out: the same name in any other file still blocks (full-tree)" 1 "$RC22B"
must_contain "carve-out: the other file is reported" "$OUT22B" "[REBRAND] notes.txt:1:"
must_not_contain "carve-out: chronicle files stay unreported next to a real finding" "$OUT22B" "[REBRAND] CHANGELOG.md"

echo "== chronicle carve-out, accepted cost: a NEW mention in a chronicle file is not reported under --staged either =="
printf 'history line that mentions %s on purpose\nnew entry that mentions %s\n' "$_rebrand2" "$_rebrand2" > "$T22/CHANGELOG.md"
git -C "$T22" add CHANGELOG.md
OUT22C="$(run_scrub "$T22" "$NOVAULT" --staged)"; RC22C=$?
check_exit "carve-out cost: staged new mention in CHANGELOG.md exits 0 (documented, accepted)" 0 "$RC22C"
must_not_contain "carve-out cost: staged chronicle file is not reported" "$OUT22C" "[REBRAND] CHANGELOG.md"

echo ""
echo "scrub-check-regression: $PASS passed, $FAIL failed"

REAL_VAULT_AFTER="$(snapshot_real_vault)"
if [[ "$REAL_VAULT_BEFORE" != "$REAL_VAULT_AFTER" ]]; then
  echo "scrub-check-regression: TRIPWIRE FAILED — the REAL ~/.claude/vault changed during this run" >&2
  echo "  before: $REAL_VAULT_BEFORE" >&2
  echo "  after:  $REAL_VAULT_AFTER" >&2
  exit 1
fi

[[ "$FAIL" -eq 0 ]] && exit 0
exit 1
