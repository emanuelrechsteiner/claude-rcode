#!/usr/bin/env bash
# scrub-check.sh — Secret & PII release gate for claude-rcode.
#
# Deterministic pre-publish scan: fails (exit 1) if a tracked file contains
# a credential-shaped secret, a real vault-registered term, or a leftover
# reference to the pre-rebrand project name. Exit 0 + "scrub-check: clean"
# otherwise.
#
# Usage:
#   scripts/scrub-check.sh              # scan the whole repo
#   scripts/scrub-check.sh --staged     # scan only staged files (pre-commit use)
#   scripts/scrub-check.sh --require-pseudonym-list   # vault is mandatory (publish gate)
#   scripts/scrub-check.sh --redact     # force the redacted, no-value output format
#                                        # (automatic when GITHUB_ACTIONS=true or CI=true)
#
# Wired in as a pre-push hook (scripts/install-git-hooks.sh) and as a
# GitHub Action (.github/workflows/scrub-check.yml) so the gate applies to
# every push and every contributor PR, not just this machine.
#
# LIMITATION — this scans the CURRENT tree only (working tree, or the
# staged index under --staged), never commit HISTORY. A secret or PII
# fragment that was committed and later removed from the tip would pass
# this gate clean while still being recoverable from `git log -p` / a
# stale ref. A release/publish process must therefore run a separate,
# history-wide scan (or a history squash) BEFORE the first push to a new
# public remote — this gate alone does not cover that case.
#
# VAULT-BY-DESIGN, ONE MATCHER (2026-09-25 rework round 5, IMP-219,
# finding #4): every real vault-registered term (project/account/user/
# email/phrase/id names) used to be found via THIS script's own
# `git grep -E` expression, built from fragment-assembled literals and
# later from vault-sourced terms — a SECOND matcher with its own,
# different word-boundary and allowlist rules from scripts/vault/lib.sh's
# actual matcher. That regex is gone. All vault-term and structural
# (path/email/id-shaped) detection below runs through `vault.sh check`
# exclusively (rules/testing-quality.md "Verify Via the Same Code Path") —
# same allowlist semantics, same word boundaries, same public-name
# exclusions as every other vault consumer (the write-gate hook, pre-commit,
# the publish transforms). Only two things remain genuinely separate here:
#   §1 SECRET_PATTERN — vendor credential SHAPES (a GitHub token, an AWS
#      key...) have nothing to do with the vault; a secret is dangerous
#      regardless of whether it's "registered" anywhere.
#   §6 Rebrand regression — a leftover reference to this project's own
#      pre-rebrand name is a documentation-consistency check, not a
#      privacy one.
#
# PUBLIC-CI REDACTION (2026-09-25 rework round 6, IMP-219, Befund H1+H2):
#   H1 — the PII section below used to filter vault.sh check's findings
#   through its OWN second kind-whitelist (user/email/phrase/project/
#   account/id), which omitted "path" entirely — a structural (vault-less)
#   path-shaped finding was therefore invisible on a fresh clone or public
#   CI runner even though `vault.sh check` itself correctly reported it
#   (kind=path, token empty by construction for any structural match).
#   Fixed by iterating every row `vault.sh check` returns with no kind
#   filter at all (rules/testing-quality.md "Verify Via the Same Code
#   Path") — the file-NAME check below had the same class of gap (it only
#   ran at all when a vault was present, so a public CI runner without one
#   never got a structural filename check either) and is fixed the same way.
#   H2 — this script used to print the FULL matched line, including the
#   actual secret/PII/rebrand value, to stdout — on a public GitHub Actions
#   runner that turns a single finding into a second, public copy of the
#   very value the finding exists to catch. When GITHUB_ACTIONS=true,
#   CI=true, or --redact is given, every finding below prints only
#   "[<label>] <file>:<line> (<kind>)" — never line content, term, or
#   value — and inside real CI (GITHUB_ACTIONS=true or CI=true) an
#   independent GitHub Actions `::add-mask::<value>` directive is emitted
#   for each found value BEFORE it would otherwise be printed, as a second,
#   independent safeguard (the runner's own log masking, not this script's
#   formatting choice, becomes the backstop). Local runs without either
#   signal or the flag keep today's full, term-naming output on purpose
#   (plans/vault-by-design-2026-09-25.md §3: locally the message may name
#   the term).
#
# NOTE on how §1 is written: this script's OWN job is to detect
# secret-shaped strings, so its literal source text must not itself
# satisfy the very patterns it's checking for (or every release-gate run
# would flag itself, and this file would trip the PreToolUse
# secret-scanning hook the moment it's written/edited). SECRET_PATTERN
# therefore assembles every self-referential literal from adjacent quoted
# string fragments (`"foo""bar"`) rather than spelling it out as one
# contiguous literal — the fragments concatenate at bash-eval time, but the
# on-disk bytes never contain the flagged substring contiguously.
#
# NOTE on prefix-only vs. shaped matching: secret patterns require the
# actual secret SHAPE (vendor prefix + its real value length), not just the
# bare vendor prefix. A bare-prefix match (e.g. plain "github_pat_") would
# flag every legitimate mention of that pattern name in this repo's own
# security docs and hooks (hooks/security-audit.sh, CLAUDE.md, HARNESS.md,
# docs/RETENTION-POLICY.md, skills/create-hook, skills/create-rule, ...) —
# permanent false positives that would make "exit 0 on a clean repo"
# unreachable. Shaped matching mirrors hooks/security-audit.sh's own
# quantifiers and still catches every category wave1-secret-scan.md
# checked for.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWLIST="$SCRIPT_DIR/scrub-allowlist.txt"
VAULT_SH="$SCRIPT_DIR/vault/vault.sh"
VAULT_LIB="$SCRIPT_DIR/vault/lib.sh"

MODE="${1:-full}"
REQUIRE_PSEUDONYM_LIST=0
REDACT_FLAG=0
for _pn_arg in "$@"; do
  case "$_pn_arg" in
    --require-pseudonym-list) REQUIRE_PSEUDONYM_LIST=1 ;;
    --redact) REDACT_FLAG=1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Public-CI redaction (2026-09-25 rework round 6, IMP-219, Befund H2). Three
# independent triggers OR together into REDACT (the print-FORMAT switch:
# every finding below prints "[<label>] <file>:<line> (<kind>)" instead of
# its content/term/value). ADD_MASK (the GitHub Actions `::add-mask::`
# side-channel — see mask_value() below) is deliberately NARROWER: real CI
# signals only, never --redact alone, because a mask directive is
# meaningless noise outside an actual Actions log, and --redact exists
# precisely so the reduced print format can be exercised locally (including
# by scripts/tests/scrub-check-regression.sh) without also emitting it.
# ---------------------------------------------------------------------------
CI_ENV=0
[[ "${GITHUB_ACTIONS:-}" == "true" || "${CI:-}" == "true" ]] && CI_ENV=1
REDACT=0
[[ "$CI_ENV" -eq 1 || "$REDACT_FLAG" -eq 1 ]] && REDACT=1
ADD_MASK="$CI_ENV"

# mask_value <value> — emits a GitHub Actions log-masking directive for a
# found value, ONLY inside real CI (ADD_MASK) and only when non-empty (an
# empty mask directive is pointless and GitHub Actions may warn on it).
# This is the "zweite unabhaengige Absicherung" from the task brief: the
# Actions runner scans all SUBSEQUENT log output for an exact match on
# <value> and renders it as "***" in the displayed log from this point
# forward in the job, independent of whether this script's own formatting
# happens to print that value afterward (it never deliberately does, but a
# masked value also protects against some OTHER step in the same job
# printing it later). Every call site below invokes this BEFORE the finding
# line it protects — a mask directive has no retroactive effect on log
# lines already emitted.
mask_value() {
  local val="$1"
  [[ -z "$val" ]] && return 0
  [[ "$ADD_MASK" -eq 1 ]] && printf '::add-mask::%s\n' "$val"
  return 0
}

# ---------------------------------------------------------------------------
# 1. Secret pattern — credential-shaped strings (assembled from fragments;
#    see the note above).
# ---------------------------------------------------------------------------
_gh_fine="git""hub_pat_[A-Za-z0-9_]{82}"
_gh_ghp="gh""p_[A-Za-z0-9]{36}"
_gh_gho="gh""o_[A-Za-z0-9]{36}"
_gh_ghs="gh""s_[A-Za-z0-9]{36}"
_aws_akia="AK""IA[0-9A-Z]{16}"
_aws_asia="AS""IA[0-9A-Z]{16}"
_ai_sk_ant="sk-""ant-[A-Za-z0-9_-]{20,}"
_ai_sk_proj="sk-""proj-[A-Za-z0-9_-]{20,}"
_google_aiza="AI""za[A-Za-z0-9_-]{35}"
_slack_xox="xox""[bpars]-[A-Za-z0-9-]{10,}"
_pem_header="-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----"
_jwt="eyJ[A-Za-z0-9_-]{20,}\."

SECRET_PATTERN="(${_gh_fine}|${_gh_ghp}|${_gh_gho}|${_gh_ghs}|${_aws_akia}|${_aws_asia}|${_ai_sk_ant}|${_ai_sk_proj}|${_google_aiza}|${_slack_xox}|${_pem_header}|${_jwt})"

# ---------------------------------------------------------------------------
# 2. File selection
# ---------------------------------------------------------------------------
# Note: intentionally not using `mapfile` (bash 4+) — stock macOS ships
# bash 3.2, and this script must run there without requiring homebrew bash.
#
# --diff-filter=AMRC (not just ACM, corrected 2026-09-25, IMP-219 rebrand
# --staged fix): matches scripts/git-hooks/pre-commit's own filter, for the
# identical reason documented there — this repo's git enables rename
# detection by default, so a `git mv old new` plus an edit to `new` is
# classified status R, not A/M. A filter without R silently skipped that path
# from EVERY check below (secrets, vault/PII, tracked file names, rebrand),
# not only the rebrand one.
#
# -c core.quotePath=false (2026-09-25, IMP-219 Nachbesserung, hardening):
# without it, git's DEFAULT quoting (core.quotePath=true) prints a non-ASCII
# filename as a double-quoted, octal-escaped literal (e.g. a filename
# containing an umlaut becomes the 24-character STRING
# `"\303\234bersicht.txt"`, quote marks and backslashes included) instead of
# the raw bytes — verified empirically before writing this. That escaped
# string then goes straight into $FILES and is later used as a `-- "$f"`
# pathspec argument that matches no real file, so every check below silently
# skips the path entirely. 0 such tracked paths exist in this repo today (no
# behavior change now), but the fix costs nothing and closes the gap before
# it ever matters.
FILES=()
if [[ "$MODE" == "--staged" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES+=("$f")
  done < <(git -c core.quotePath=false diff --cached --name-only --diff-filter=AMRC)
else
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES+=("$f")
  done < <(git -c core.quotePath=false ls-files)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "scrub-check: no tracked files to scan"
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Self-referential files excluded from the SECRET-adjacent self-scan
#    concern (§1 already handles itself via fragment-assembly; this list is
#    for the REBRAND scan's self-reference in §6, and for scrub-allowlist.txt
#    quoting its own D7 coordinates without becoming a rebrand hit).
# ---------------------------------------------------------------------------
SELF_EXCLUDE=(
  ':!scripts/scrub-check.sh'
  ':!scripts/scrub-allowlist.txt'
)

# ---------------------------------------------------------------------------
# 4. Allowlist — exact "path:line:signature" triples (see
#    scripts/scrub-allowlist.txt). Used directly by §1 (SECRET_PATTERN) and
#    §6 (rebrand) below; vault.sh check (§5/§7) consults the SAME file
#    itself, via scripts/vault/lib.sh's own allowlist logic — not this bash
#    function — so there is still only one allowlist FILE, read by two
#    matchers that each apply it in their own domain (secret-shape /
#    rebrand-term here, vault-term / structural there).
# ---------------------------------------------------------------------------
is_allowlisted() {
  local file="$1" lineno="$2" content="$3"
  [[ -f "$ALLOWLIST" ]] || return 1
  local aw_file aw_line aw_sig
  while IFS=: read -r aw_file aw_line aw_sig; do
    [[ -z "$aw_file" || "$aw_file" == \#* ]] && continue
    if [[ -z "$aw_sig" ]]; then
      echo "scrub-check: WARNING — malformed allowlist entry (empty signature) at $ALLOWLIST: ${aw_file}:${aw_line}: — ignoring, not treating as a match" >&2
      continue
    fi
    if [[ "$aw_file" == "$file" && "$aw_line" == "$lineno" && "$content" == *"$aw_sig"* ]]; then
      return 0
    fi
  done < "$ALLOWLIST"
  return 1
}

# ---------------------------------------------------------------------------
# 5. Scan
# ---------------------------------------------------------------------------
FOUND=0

scan_pattern() {
  local pattern="$1" label="$2"
  shift 2
  local out
  if [[ $# -gt 0 ]]; then
    local excludes=("$@")
    if [[ "$MODE" == "--staged" ]]; then
      out=$(git grep --cached -nIE "$pattern" -- "${FILES[@]}" "${excludes[@]}" 2>/dev/null || true)
    else
      out=$(git grep -nIE "$pattern" -- . "${excludes[@]}" 2>/dev/null || true)
    fi
  else
    if [[ "$MODE" == "--staged" ]]; then
      out=$(git grep --cached -nIE "$pattern" -- "${FILES[@]}" 2>/dev/null || true)
    else
      out=$(git grep -nIE "$pattern" 2>/dev/null || true)
    fi
  fi
  [[ -z "$out" ]] && return 0
  local match file lineno content
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    file="${match%%:*}"
    rest="${match#*:}"
    lineno="${rest%%:*}"
    content="${rest#*:}"
    if is_allowlisted "$file" "$lineno" "$content"; then
      continue
    fi
    if [[ "$REDACT" -eq 1 ]]; then
      local _secret_val=""
      _secret_val="$(printf '%s' "$content" | grep -oE "$pattern" 2>/dev/null | head -1)" || true
      mask_value "$_secret_val"
      echo "  [$label] $file:$lineno (secret)"
    else
      echo "  [$label] $file:$lineno: $content"
    fi
    FOUND=1
  done <<< "$out"
}

echo "scrub-check: scanning ${#FILES[@]} tracked file(s)..."
echo "scrub-check: NOTE — this checks the current tree only, not commit history;"
echo "  a release/publish workflow needs a separate history-wide scan or squash."
echo ""
echo "Secret patterns:"
scan_pattern "$SECRET_PATTERN" "SECRET"

# ---------------------------------------------------------------------------
# 6. Vault-sourced scan (§2/§7's shared data source) — ONE `vault.sh check`
#    pass, reused below for the "PII" section, the tracked-FILE-NAME check,
#    and the "private leak" section. --staged reads the INDEX content via
#    `git show :<path>` + `check --stdin --as <path>` per file (vault.sh
#    check itself always reads disk content, which would be wrong for
#    --staged if the working tree has further unstaged changes); the
#    default (full-tree) mode passes every file to ONE `vault.sh check`
#    call, which loops internally without rebuilding its rules file per
#    file.
# ---------------------------------------------------------------------------
HAVE_VAULT=0
if [[ -f "$VAULT_LIB" ]]; then
  # shellcheck source=./vault/lib.sh
  . "$VAULT_LIB"
  vault_exists && HAVE_VAULT=1
fi

if [[ "$HAVE_VAULT" -eq 0 ]]; then
  echo "scrub-check: WARNING — no vault at $(vault_dir 2>/dev/null || echo '~/.claude/vault'); vault-sourced PII/leak checks (§ PII, § private leak) are skipped this run. Structural patterns (path/email/id shapes) inside vault.sh check still run regardless. Run: scripts/vault/vault.sh init" >&2
fi

VAULT_RAW=""
if [[ -f "$VAULT_SH" ]]; then
  if [[ "$MODE" == "--staged" ]]; then
    for _vf in "${FILES[@]}"; do
      _vf_out="$(git show ":$_vf" 2>/dev/null | bash "$VAULT_SH" check --stdin --as "$_vf" 2>/dev/null)" || true
      [[ -n "$_vf_out" ]] && VAULT_RAW="${VAULT_RAW}${_vf_out}"$'\n'
    done
  else
    VAULT_RAW="$(bash "$VAULT_SH" check "${FILES[@]}" 2>/dev/null)" || true
  fi
else
  echo "scrub-check: WARNING — $VAULT_SH not found; vault-sourced PII/leak checks are skipped this run." >&2
fi

echo "PII / personal-data patterns:"
_pii_found=0
if [[ -n "$VAULT_RAW" ]]; then
  # 2026-09-25 rework round 6, IMP-219, Befund H1: NO second kind-list here
  # on purpose (rules/testing-quality.md "Verify Via the Same Code Path") —
  # every row vault.sh check returns for this content is a finding, full
  # stop. The previous case/esac whitelist (user|email|phrase|project|
  # account|id) silently dropped "path" — the one kind missing from it —
  # which made a structural (vault-less) path-shaped leak invisible on a
  # fresh clone or public CI runner even though `vault.sh check` itself
  # correctly reported it (kind=path, token empty by construction).
  while IFS=$'\t' read -r _f _ln _kind _term _tok; do
    [[ -z "$_f" ]] && continue
    if [[ "$REDACT" -eq 1 ]]; then
      mask_value "$_term"
      echo "  [PII] $_f:$_ln ($_kind)"
    else
      echo "  [PII] $_f:$_ln: kind=$_kind term=$_term${_tok:+ token=$_tok}"
    fi
    _pii_found=1
    FOUND=1
  done <<< "$VAULT_RAW"
fi
[[ "$_pii_found" -eq 0 ]] && echo "  clean"

# ---------------------------------------------------------------------------
# 6b. PII in tracked FILE NAMES, not just file CONTENT (added 2026-09-23).
#
# vault.sh check only ever inspects file CONTENT — it structurally cannot
# see a real term sitting in a file's own NAME. This was a real, shipped
# leak: 3 launchd .plist files carried the real machine username in their
# on-disk filename while their INTERNAL content had already been correctly
# redacted (Wave 3 fixed those specific files; the check itself stays as a
# standing guard against a future recurrence of the same shape).
#
# STILL "ein Matcher" (round 5, finding #4): rather than building a second,
# separately-written regex from vault terms, every tracked file's OWN PATH
# is written as one line of a synthetic multi-line "document" and piped
# through the SAME `vault.sh check --stdin` ONE time — the matcher itself
# never knows the difference between "a line of real file content" and "a
# line that happens to be a file path"; a match on line N maps back to
# ${FILES[N-1]}.
# ---------------------------------------------------------------------------
echo "PII / personal-data patterns in tracked FILE NAMES (not just content):"
_name_found=0
# 2026-09-25 rework round 6, IMP-219, Befund H1 companion: this used to be
# gated on "$HAVE_VAULT" -eq 1, so a fresh clone / public CI runner WITHOUT
# a vault never ran this check at all — the same "structural finding
# invisible exactly where it matters most" gap as the PII section above,
# just via a different code path (a missing vault, not a missing kind).
# `vault.sh check` already degrades gracefully with no vault (structural
# patterns only, rules=""), so the only real precondition is vault.sh
# itself being present. Every row is now a finding regardless of token
# emptiness too, for the same "no second filter list" reason — a
# structural id/email shape sitting inside a tracked file NAME is exactly
# as real a leak as one sitting inside a file's content.
#
# The matched PATH itself stays visible even under --redact/CI: unlike a
# term found on a content line, the path here IS the location, not a
# separately-printed value distinct from it — and it is already fully
# public via the checked-out tree (`git ls-files`) on the very same runner,
# so repeating it in this log adds no new exposure. The embedded term is
# still add-mask'd for defense in depth: the CI runner's own log renderer
# then hides it inside the printed path too, even though this script's own
# text is unredacted here (same rationale a normal secret scanner uses when
# it shows "path:line" but masks only the payload).
if [[ -f "$VAULT_SH" ]]; then
  _names_out="$(printf '%s\n' "${FILES[@]}" | bash "$VAULT_SH" check --stdin --as "<tracked-file-names>" 2>/dev/null)" || true
  if [[ -n "$_names_out" ]]; then
    while IFS=$'\t' read -r _nf _nln _nkind _nterm _ntok; do
      [[ -z "$_nf" ]] && continue
      _matched_path="${FILES[$((_nln - 1))]}"
      mask_value "$_nterm"
      echo "  [NAME-PATH] $_matched_path"
      FOUND=1
      _name_found=1
    done <<< "$_names_out"
  fi
fi
[[ "$_name_found" -eq 0 ]] && echo "  clean (no tracked file name matched)"

echo "Rebrand regression (leftover pre-rebrand project name):"
_rebrand_term="tor""valdsen"
rebrand_out=""
# Two files legitimately carry the old name: MIGRATION.md explains the rename
# to users coming from the predecessor, and commands/rcode-upgrade.md must
# match the literal legacy file names it migrates (torvaldsen-*.md,
# torvaldsen/VERSION) — the old name IS its detection logic, not prose.
# Owner decision 2026-09-23 (the name has been public in MIGRATION.md since
# v1.0.0); same carve-out class, no new class.
REBRAND_CARVEOUT=(':!MIGRATION.md' ':!commands/rcode-upgrade.md')
#
# --staged counts ADDED LINES ONLY (2026-09-25, IMP-219). The `else` branch
# below (full-tree mode, used by CI and scripts/publish.sh's staging-tree
# scan) is UNCHANGED — it still greps the WHOLE current blob of every tracked
# file in one `git grep`, because a release/CI scan must catch pre-existing
# debt wherever it still lives. --staged must not: this repo carries 47
# reviewed, accepted pre-rebrand mentions sitting in files nearly every
# commit touches (CHANGELOG.md, global-observation/improvement-ledger.json,
# three others) — a whole-blob scan there would re-flag that same accepted
# debt on any unrelated staged edit to those files, forcing a routine `git
# commit --no-verify`, which ALSO disables this hook's separate vault check
# (scripts/git-hooks/pre-commit runs both checks in one invocation). So under
# --staged, a finding only counts if it sits on a line the staged diff ADDS —
# a file whose only occurrences sit on untouched pre-existing lines reports
# clean; editing a pre-existing debt line still counts as adding it (it lands
# on the "+" side of the diff), so touching that line means fixing or
# allowlisting it, not silently carrying it forward under a new guise.
if [[ "$MODE" == "--staged" ]]; then
  _rb_excluded_paths=()
  for _rb_ex in "${REBRAND_CARVEOUT[@]}" "${SELF_EXCLUDE[@]}"; do
    _rb_excluded_paths+=("${_rb_ex#:!}")
  done
  _rb_is_excluded() {
    local f="$1" ex
    for ex in "${_rb_excluded_paths[@]}"; do
      [[ "$f" == "$ex" ]] && return 0
    done
    return 1
  }
  # Exclusion is fully resolved HERE, before nocasematch (below) is ever
  # turned on — this case-SENSITIVE path-equality check must never be
  # affected by it (nocasematch also governs plain `[[ == ]]`, not just
  # `=~`; two differently-cased tracked paths are two different files on a
  # case-sensitive filesystem).
  _rb_files_to_scan=()
  for _rb_f in "${FILES[@]}"; do
    _rb_is_excluded "$_rb_f" || _rb_files_to_scan+=("$_rb_f")
  done

  # Fork-free matching (2026-09-25, IMP-219 Nachbesserung): the previous
  # `printf '%s' "$_rb_content" | grep -qiE "$_rebrand_term"` forked a
  # process per ADDED LINE — a staged 3,000-line new file forked 3,000
  # times. `[[ =~ ]]` is a bash builtin; `nocasematch` gives it case
  # insensitivity without a process. Scoped narrowly around just the scan
  # loop below (never around _rb_is_excluded, see above) and restored
  # WITHOUT eval immediately after, so a caller that already had
  # nocasematch on — or off — is left exactly as found.
  #
  # Empty-list guard (2026-09-25, IMP-219 Nachbesserung 2): bash 3.2 (stock
  # /bin/bash) treats "${arr[@]}" of an EMPTY array as an unbound-variable
  # error under `set -u` (bash >=4.4 does not) — confirmed empirically.
  # _rb_files_to_scan IS legitimately empty whenever every staged file is on
  # an exclusion list — e.g. a commit that ONLY adds an entry to
  # scripts/scrub-allowlist.txt, or ONLY edits scripts/scrub-check.sh itself
  # (exactly the remedy this hook's own BLOCKED message recommends), used to
  # crash this script with "_rb_files_to_scan[@]: unbound variable" instead
  # of reporting clean. `${#arr[@]}` (length) IS safe on an empty array under
  # set -u, even on bash 3.2 (also verified) — used here rather than the
  # `${arr[@]+"${arr[@]}"}` alternate-value idiom for consistency with this
  # file's own pre-existing `${#FILES[@]} -eq 0` guard in §2. The guard wraps
  # the WHOLE nocasematch toggle, not just the loop, so the empty case never
  # touches nocasematch at all — nothing to restore, because nothing changed.
  if [[ ${#_rb_files_to_scan[@]} -gt 0 ]]; then
  _rb_nocasematch_was_on=0
  shopt -q nocasematch && _rb_nocasematch_was_on=1
  shopt -s nocasematch

  for _rb_f in "${_rb_files_to_scan[@]}"; do
    # Pathspec-restricted to a single file: a genuinely renamed path (see §2)
    # cannot be paired here with the old name git excludes from this
    # pathspec, so git reports the new path as a full addition — every line
    # of a renamed file counts as "added" (same as a brand-new file), never
    # fewer. Verified empirically (git 2.51.0) before writing this.
    _rb_diff="$(git diff --cached --no-color -U0 -- "$_rb_f" 2>/dev/null || true)"
    [[ -z "$_rb_diff" ]] && continue
    _rb_newln=0
    _rb_seen_hunk=0
    while IFS= read -r _rb_dline; do
      case "$_rb_dline" in
        '@@ '*)
          # "@@ -old[,cnt] +new[,cnt] @@[ heading]" — only the new-side start
          # matters; -U0 means every hunk begins right at its first changed
          # line, no leading context to offset by.
          _rb_seen_hunk=1
          _rb_hunk="${_rb_dline#@@ }"
          _rb_hunk="${_rb_hunk%% @@*}"
          _rb_newpart="${_rb_hunk#*+}"
          _rb_newln="${_rb_newpart%%,*}"
          ;;
        '+'*)
          # A single-file diff has AT MOST one '+'-prefixed line before the
          # first "@@": the "+++ b/<path>" file header. Every '+'-prefixed
          # line AFTER the first "@@" is real added content — including one
          # whose actual content starts with a second literal '+' (content
          # "++x" becomes "+++x" once diff-prefixed). A pattern that treats
          # any '+++'-looking line as a header (previous version of this
          # block) misclassified that case: the finding was silently missed
          # AND the line counter fell one short for every following line in
          # the hunk. Verified empirically (git 2.51.0) before writing this.
          if [[ "$_rb_seen_hunk" -eq 0 ]]; then
            : # pre-hunk "+++ b/<path>" header — not content, no counter bump
          else
            _rb_content="${_rb_dline#+}"
            [[ "$_rb_content" =~ $_rebrand_term ]] \
              && rebrand_out="${rebrand_out}${_rb_f}:${_rb_newln}:${_rb_content}"$'\n'
            _rb_newln=$((_rb_newln + 1))
          fi
          ;;
        '-'*) : ;;  # pre-hunk "--- a/<path>" header, OR any removed content
                    # line (incl. one starting with a second literal '-') —
                    # both are a no-op either way: a header is never content,
                    # and a removed line never occupies a new-side line
                    # number, so the two cases need no disambiguation.
        *) : ;;     # diff/index/mode/rename/similarity/no-newline chatter
      esac
    done <<< "$_rb_diff"
  done

  [[ "$_rb_nocasematch_was_on" -eq 0 ]] && shopt -u nocasematch
  fi
  rebrand_out="${rebrand_out%$'\n'}"
else
  rebrand_out=$(git grep -niI "$_rebrand_term" -- . "${REBRAND_CARVEOUT[@]}" "${SELF_EXCLUDE[@]}" 2>/dev/null || true)
fi
if [[ -n "$rebrand_out" ]]; then
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    if [[ "$REDACT" -eq 1 ]]; then
      _rb_file="${match%%:*}"
      _rb_rest="${match#*:}"
      _rb_line="${_rb_rest%%:*}"
      _rb_content="${_rb_rest#*:}"
      _rb_val=""
      _rb_val="$(printf '%s' "$_rb_content" | grep -oiE "$_rebrand_term" 2>/dev/null | head -1)" || true
      mask_value "$_rb_val"
      echo "  [REBRAND] $_rb_file:$_rb_line (rebrand)"
    else
      echo "  [REBRAND] $match"
    fi
    FOUND=1
  done <<< "$rebrand_out"
fi

# ---------------------------------------------------------------------------
# 7. Private leak check — every VAULT-REGISTERED term (any kind, i.e. a
#    non-empty token in the §6 capture above), reusing $VAULT_RAW rather
#    than a second scan. "Tresor Pflicht" (--require-pseudonym-list): a
#    missing vault, OR a vault whose private-layer group (§ mirror-marker
#    terms, kind=phrase group=private-layer) is empty, is FATAL — this is
#    the path that actually gates a real publish
#    (scripts/publish.sh --require-pseudonym-list); the private maintainer
#    always has both populated, so either being empty means something is
#    badly wrong, not that the check should be skipped.
# ---------------------------------------------------------------------------
echo ""
echo "Private pseudonym-list leak check:"
if [[ "$HAVE_VAULT" -eq 0 ]]; then
  if [[ "$REQUIRE_PSEUDONYM_LIST" -eq 1 ]]; then
    echo "  FATAL — --require-pseudonym-list was given but no vault is available" >&2
    echo "  at $(vault_dir 2>/dev/null || echo '~/.claude/vault'). This gate is meant to run" >&2
    echo "  against the private maintainer's own vault; its absence here means" >&2
    echo "  something is badly wrong, not that the check should be skipped. Fix:" >&2
    echo "  scripts/vault/vault.sh init (see docs/PUBLISHING.md \"Pseudonymization\")" >&2
    echo "  before publishing." >&2
    exit 1
  fi
  echo "  kein Tresor vorhanden — Pruefung uebersprungen (erwartet ausserhalb der"
  echo "  privaten Maschine dieses Betreuers; oeffentliche CI laeuft normal weiter."
  echo "  Lokal pruefen mit: scripts/scrub-check.sh --require-pseudonym-list)"
else
  _mirror_count=$(awk -F'\t' '$4=="private-layer"{c++} END{print c+0}' "$(vault_map_file)")
  if [[ "$REQUIRE_PSEUDONYM_LIST" -eq 1 && "$_mirror_count" -eq 0 ]]; then
    echo "  FATAL — --require-pseudonym-list was given but the vault's private-layer" >&2
    echo "  group (kind=phrase, group=private-layer) is empty. This gate is meant to" >&2
    echo "  also protect the private local overlay layer's own markers; an empty" >&2
    echo "  group here means that protection is not actually loaded, not that there" >&2
    echo "  is nothing to protect. Fix: re-add the private-layer terms to the vault" >&2
    echo "  before publishing." >&2
    exit 1
  fi
  _pn_found=0
  if [[ -n "$VAULT_RAW" ]]; then
    while IFS=$'\t' read -r _f _ln _kind _term _tok; do
      [[ -z "$_f" || -z "$_tok" ]] && continue
      if [[ "$REDACT" -eq 1 ]]; then
        mask_value "$_term"
        echo "  [NAME] $_f:$_ln ($_kind)"
      else
        echo "  [NAME] $_f:$_ln: $_term"
      fi
      _pn_found=1
      FOUND=1
    done <<< "$VAULT_RAW"
  fi
  [[ "$_pn_found" -eq 0 ]] && echo "  clean (0 real vault term(s) found)"
fi

echo ""
if [[ "$FOUND" -eq 1 ]]; then
  echo "scrub-check: BLOCKED — findings above must be fixed or added to scripts/scrub-allowlist.txt"
  exit 1
fi

echo "scrub-check: clean"
exit 0
