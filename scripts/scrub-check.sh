#!/usr/bin/env bash
# scrub-check.sh — Secret & PII release gate for claude-rcode.
#
# Deterministic pre-publish scan: fails (exit 1) if a tracked file contains
# a credential-shaped secret, a personal-data fragment from the original
# private config this repo was derived from, or a leftover reference to the
# pre-rebrand project name. Exit 0 + "scrub-check: clean" otherwise.
#
# Usage:
#   scripts/scrub-check.sh              # scan the whole repo
#   scripts/scrub-check.sh --staged     # scan only staged files (pre-commit use)
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
# NOTE on how the patterns below are written: this script's OWN job is to
# detect secret- and PII-shaped strings, so its literal source text must not
# itself satisfy the very patterns it's checking for (or every release-gate
# run would flag itself, and — more importantly — this file would trip the
# PreToolUse secret-scanning hook the moment it's written/edited). BOTH the
# secret-prefix section (§1) and the PII-literal section (§2) below
# therefore assemble every self-referential literal from adjacent quoted
# string fragments (`"foo""bar"`) rather than spelling it out as one
# contiguous literal — the fragments concatenate at bash-eval time, but the
# on-disk bytes never contain the flagged substring contiguously. This file
# and scrub-allowlist.txt are also excluded from the PII and rebrand scans
# below (§4/§6) — not from the SECRET scan — since fragmentation alone
# can't cover comment prose describing what's excluded and why.
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

MODE="${1:-full}"

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
# 2. PII / personal-data pattern — real names, private emails, historical
#    project codenames, machine paths, and third-party IDs that leaked into
#    the original private config this repo was scrubbed from. Every
#    contiguous literal is fragment-assembled per the note above so this
#    section doesn't trip its own scan (or the PreToolUse secret/PII hook).
# ---------------------------------------------------------------------------
# _names is deliberately case-sensitive (git grep -E, no -i): it matches
# the two real surnames (fragmented below) when they appear in PROSE, which
# is what D7's 2-entry allowlist (LICENSE + one README credit line) exists
# for.
_name_a="__PUBLIC_TEMPLATE_NO_REAL_TERM_1__"  # public template: real value lives only in the private repo
_name_b="__PUBLIC_TEMPLATE_NO_REAL_TERM_2__"  # public template: real value lives only in the private repo
_names="${_name_a}|${_name_b}"

# _identity intentionally does NOT include the bare lowercase GitHub account
# slug for this repo's owner — this repo is *itself* published under that
# account (D7, wave2-plan.md §0/§4/§8), so that exact slug is required, by
# design, in install.sh's REPO_URL, every clone-URL example, and CI badge.
# Flagging it would make "exit 0 on a clean, fully-sanitized repo"
# permanently impossible — a self-defeating gate. What genuinely must never
# appear is the private email domain, the retired second identity, and the
# local machine username.
_email_domain="__PUBLIC_TEMPLATE_NO_REAL_TERM_3__"  # public template: real value lives only in the private repo
_identity_b="__PUBLIC_TEMPLATE_NO_REAL_TERM_4__"  # public template: real value lives only in the private repo
_identity_c="__PUBLIC_TEMPLATE_NO_REAL_TERM_5__"  # public template: real value lives only in the private repo
_identity="info@${_email_domain}|${_identity_b}|${_identity_c}"

_proj_a="__PUBLIC_TEMPLATE_NO_REAL_TERM_6__"  # public template: real value lives only in the private repo
_proj_b="__PUBLIC_TEMPLATE_NO_REAL_TERM_7__"  # public template: real value lives only in the private repo
_proj_c="__PUBLIC_TEMPLATE_NO_REAL_TERM_8__"  # public template: real value lives only in the private repo
_proj_d="__PUBLIC_TEMPLATE_NO_REAL_TERM_9__"  # public template: real value lives only in the private repo
_proj_e="__PUBLIC_TEMPLATE_NO_REAL_TERM_10__"  # public template: real value lives only in the private repo
_proj_f="__PUBLIC_TEMPLATE_NO_REAL_TERM_11__"  # public template: real value lives only in the private repo
_proj_g="__PUBLIC_TEMPLATE_NO_REAL_TERM_12__"  # public template: real value lives only in the private repo
_proj_h="__PUBLIC_TEMPLATE_NO_REAL_TERM_13__"  # public template: real value lives only in the private repo
_projects="${_proj_a}|${_proj_b}|${_proj_c}|${_proj_d}|${_proj_e}|${_proj_f}|${_proj_g}|${_proj_h}"

_path_a="__PUBLIC_TEMPLATE_NO_REAL_TERM_14__"  # public template: real value lives only in the private repo
_path_b="__PUBLIC_TEMPLATE_NO_REAL_TERM_15__"  # public template: real value lives only in the private repo
_paths="${_path_a}|${_path_b}"

_notion_id="__PUBLIC_TEMPLATE_NO_REAL_TERM_19__"  # public template: real value lives only in the private repo
_context7_uuid="__PUBLIC_TEMPLATE_NO_REAL_TERM_20__"  # public template: real value lives only in the private repo

# Weitere maintainer-lokale Muster; die echten Werte existieren nur
# privat und werden hier durch inerte Platzhalter ersetzt (siehe
# publish-transforms.d/60-declaw-scrub-check-pii.sh).
_mirror_a="__PUBLIC_TEMPLATE_NO_REAL_TERM_16__"  # public template: real value lives only in the private repo
_mirror_b="__PUBLIC_TEMPLATE_NO_REAL_TERM_17__"  # public template: real value lives only in the private repo
_mirror_c="__PUBLIC_TEMPLATE_NO_REAL_TERM_18__"  # public template: real value lives only in the private repo
_mirror="${_mirror_a}|${_mirror_b}|${_mirror_c}"

PII_PATTERN="(${_names}|${_identity}|${_projects}|${_paths}|${_notion_id}|${_context7_uuid}|${_mirror})"

# ---------------------------------------------------------------------------
# 3. File selection
# ---------------------------------------------------------------------------
# Note: intentionally not using `mapfile` (bash 4+) — stock macOS ships
# bash 3.2, and this script must run there without requiring homebrew bash.
FILES=()
if [[ "$MODE" == "--staged" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES+=("$f")
  done < <(git diff --cached --name-only --diff-filter=ACM)
else
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES+=("$f")
  done < <(git ls-files)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "scrub-check: no tracked files to scan"
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Self-referential files excluded from the PII and rebrand scans only
#    (never from the SECRET scan). This file's own pattern-definition lines
#    and comment prose necessarily discuss the flagged names/paths/terms,
#    and scrub-allowlist.txt necessarily records the file:line:signature
#    coordinates of the two intentional LICENSE/README exemptions — both
#    are self-references, not leaks. Mirrors the existing MIGRATION.md
#    carve-out on the rebrand scan.
#
#    publish-transforms.d/60-declaw-scrub-check-pii.sh joins this list for
#    the same reason (2026-09-23): it is the transform that neutralizes
#    THIS file's §2 in staging by writing inert placeholder tokens this
#    scan's own PII_PATTERN is then built from once that transform has
#    run — so once §2 is declawed, this scan starts matching those
#    placeholder tokens wherever they legitimately appear, which is
#    exactly inside the one file whose job is to write them. No real
#    personal data is involved either way.
# ---------------------------------------------------------------------------
SELF_EXCLUDE=(
  ':!scripts/scrub-check.sh'
  ':!scripts/scrub-allowlist.txt'
  ':!publish-transforms.d/60-declaw-scrub-check-pii.sh'
)

# ---------------------------------------------------------------------------
# 5. Allowlist — exact "path:line:signature" triples (see
#    scripts/scrub-allowlist.txt). A match is only suppressed when BOTH the
#    file:line coordinate AND the recorded signature substring are still
#    present on that exact line — if the line moves or its wording changes
#    (e.g. a docs rewrite), the allowlist entry goes stale on purpose and
#    the finding re-surfaces until the allowlist is updated. Fail loud, per
#    rules/fail-loud.md, beats a silently-stale exemption.
# ---------------------------------------------------------------------------
is_allowlisted() {
  local file="$1" lineno="$2" content="$3"
  [[ -f "$ALLOWLIST" ]] || return 1
  local aw_file aw_line aw_sig
  while IFS=: read -r aw_file aw_line aw_sig; do
    [[ -z "$aw_file" || "$aw_file" == \#* ]] && continue
    # An empty/missing signature (a malformed "path:line:" entry with
    # nothing after the second colon) would make the `*"$aw_sig"*` glob
    # below match ANY content on that coordinate — i.e. it would silently
    # suppress every finding at that file:line, not just the intended one.
    # Fail loud instead: warn and skip the entry rather than let it act as
    # a wildcard exemption.
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
# 6. Scan
# ---------------------------------------------------------------------------
FOUND=0

scan_pattern() {
  local pattern="$1" label="$2"
  shift 2
  # Build the pathspec array conditionally: bash 3.2 (stock macOS) throws
  # "unbound variable" under `set -u` when expanding an EMPTY array with
  # "${arr[@]}", even though the array itself was declared — a known 3.2
  # quirk fixed in bash 4+. Guard on $# instead of relying on the array.
  local out
  if [[ $# -gt 0 ]]; then
    local excludes=("$@")
    if [[ "$MODE" == "--staged" ]]; then
      # --cached: scan the INDEX content, not the working tree. Without
      # this, a staged secret that was subsequently cleaned up in the
      # working copy would slip past --staged (see §3 note above).
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
    echo "  [$label] $file:$lineno: $content"
    FOUND=1
  done <<< "$out"
}

echo "scrub-check: scanning ${#FILES[@]} tracked file(s)..."
echo "scrub-check: NOTE — this checks the current tree only, not commit history;"
echo "  a release/publish workflow needs a separate history-wide scan or squash."
echo ""
echo "Secret patterns:"
scan_pattern "$SECRET_PATTERN" "SECRET"

echo "PII / personal-data patterns:"
scan_pattern "$PII_PATTERN" "PII" "${SELF_EXCLUDE[@]}"

# ---------------------------------------------------------------------------
# 6b. PII in tracked FILE NAMES, not just file CONTENT (added 2026-09-23).
#
# git grep (used by scan_pattern above) only ever inspects file CONTENTS —
# it structurally cannot see a PII fragment sitting in a file's own NAME.
# This was a real, shipped leak: 3 launchd .plist files carried the real
# machine username in their on-disk filename
# (com.<username>.claude-routine-*.plist) while their INTERNAL content had
# already been correctly redacted by the publish transforms — the content
# scan above reported clean while the filenames still leaked. Checking
# $FILES (the same tracked-file list §3 already built) against the same
# $PII_PATTERN closes that blind spot for this category and any future
# one shaped like it.
# ---------------------------------------------------------------------------
echo "PII / personal-data patterns in tracked FILE NAMES (not just content):"
_name_found=0
for _pf in "${FILES[@]}"; do
  case "$_pf" in
    scripts/scrub-check.sh|scripts/scrub-allowlist.txt) continue ;;
  esac
  if [[ "$_pf" =~ $PII_PATTERN ]]; then
    echo "  [NAME-PATH] $_pf"
    FOUND=1
    _name_found=1
  fi
done
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
if [[ "$MODE" == "--staged" ]]; then
  # --cached: same index-content rationale as scan_pattern() above.
  rebrand_out=$(git grep --cached -niI "$_rebrand_term" -- "${FILES[@]}" "${REBRAND_CARVEOUT[@]}" "${SELF_EXCLUDE[@]}" 2>/dev/null || true)
else
  rebrand_out=$(git grep -niI "$_rebrand_term" -- . "${REBRAND_CARVEOUT[@]}" "${SELF_EXCLUDE[@]}" 2>/dev/null || true)
fi
if [[ -n "$rebrand_out" ]]; then
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    echo "  [REBRAND] $match"
    FOUND=1
  done <<< "$rebrand_out"
fi

# ---------------------------------------------------------------------------
# 7. Private pseudonym-list leak check (optional; NEVER-VERSIONED input,
#    added 2026-09-23). Scans for real private project/location names that
#    publish-transforms.d/50-pseudonymize.sh is supposed to have already
#    replaced with neutral placeholders in the staging tree. The name list
#    itself (publish-pseudonyms.local.tsv, repo root) is git-ignored and
#    NEVER versioned or published — see docs/PUBLISHING.md
#    "Pseudonymization". Because the list is local-only, this check cannot
#    run unconditionally in public CI (a contributor's checkout has no such
#    file, and never should have one).
#
#    LOCATION OF THE LIST — this matters because of HOW this script runs
#    during a real publish: scripts/publish.sh executes scrub-check.sh FROM
#    INSIDE the STAGING tree, against an ephemeral `git init` it creates
#    there (see that script's Step 5 comment) — so `git rev-parse
#    --show-toplevel` inside THIS script resolves to the STAGING dir, not
#    the private repo, and $REPO_ROOT above is therefore the staging path
#    in that context. The private list obviously never lives in staging
#    (that's the whole point of it being git-ignored). So: prefer
#    $CLAUDE_SCRUB_PSEUDONYM_LIST (an absolute path, set by the caller) when
#    given, and fall back to "$REPO_ROOT/publish-pseudonyms.local.tsv" only
#    for the direct-invocation case (running this script by hand, or as a
#    pre-push hook, inside the actual private repo — there $REPO_ROOT
#    legitimately IS the private repo root). publish.sh's Step 5 call line
#    sets the env var explicitly for exactly this reason.
#
#    Two behaviors, chosen by the caller via a new switch,
#    --require-pseudonym-list, scanned out of "$@" below without disturbing
#    the existing $1-positional $MODE parsing above:
#      - default (no --require-pseudonym-list): if the list is missing,
#        print a LOUD note and continue — a skipped check must never look
#        like a passed one, but public CI must never hard-fail on a file
#        that structurally cannot exist there (rules/fail-loud.md).
#      - --require-pseudonym-list (used by scripts/publish.sh's local,
#        private run only): a missing list is FATAL. This is the path that
#        actually gates a publish — the private maintainer always has the
#        list; its absence there means something is badly wrong, not that
#        the check should be skipped.
#    When the list IS present (either mode), every term is checked exactly
#    the same way regardless of the switch — the switch only controls what
#    happens when the list is ABSENT. This section only ADDS a check; it
#    does not alter the SECRET, PII, or REBRAND patterns/behavior above.
# ---------------------------------------------------------------------------
REQUIRE_PSEUDONYM_LIST=0
for _pn_arg in "$@"; do
  [[ "$_pn_arg" == "--require-pseudonym-list" ]] && REQUIRE_PSEUDONYM_LIST=1
done

PSEUDONYM_LIST="${CLAUDE_SCRUB_PSEUDONYM_LIST:-$REPO_ROOT/publish-pseudonyms.local.tsv}"
PSEUDONYM_SELF_EXCLUDE=("${SELF_EXCLUDE[@]}" ':!publish-transforms.d/50-pseudonymize.sh')

echo ""
echo "Private pseudonym-list leak check:"
if [[ ! -f "$PSEUDONYM_LIST" ]]; then
  if [[ "$REQUIRE_PSEUDONYM_LIST" -eq 1 ]]; then
    echo "  FATAL — --require-pseudonym-list was given but $PSEUDONYM_LIST is missing." >&2
    echo "  This gate is meant to run against the private maintainer's own list; a" >&2
    echo "  missing file here means the list was deleted or moved, not that the" >&2
    echo "  check should be skipped. Fix: restore the file (see docs/PUBLISHING.md" >&2
    echo "  \"Pseudonymization\") before publishing." >&2
    exit 1
  fi
  echo "  private Begriffsliste nicht vorhanden — Pruefung uebersprungen"
  echo "  (erwartet ausserhalb der privaten Maschine dieses Betreuers; oeffentliche"
  echo "  CI laeuft normal weiter. Lokal gegen die private Liste pruefen mit:"
  echo "  scripts/scrub-check.sh --require-pseudonym-list)"
else
  _pn_terms=()
  while IFS=$'\t' read -r _pn_term _pn_placeholder; do
    [[ -z "$_pn_term" || "$_pn_term" == \#* ]] && continue
    [[ -z "${_pn_placeholder:-}" ]] && continue
    _pn_terms+=("$_pn_term")
  done < "$PSEUDONYM_LIST"

  if [[ ${#_pn_terms[@]} -eq 0 ]]; then
    echo "  $PSEUDONYM_LIST is present but empty (comments/blank only) — nothing to check"
  else
    _pn_found=0
    for _pn_term in "${_pn_terms[@]}"; do
      _pn_out=""
      if [[ "$MODE" == "--staged" ]]; then
        _pn_out=$(git grep --cached -nIF -- "$_pn_term" -- "${FILES[@]}" "${PSEUDONYM_SELF_EXCLUDE[@]}" 2>/dev/null || true)
      else
        _pn_out=$(git grep -nIF -- "$_pn_term" -- . "${PSEUDONYM_SELF_EXCLUDE[@]}" 2>/dev/null || true)
      fi
      [[ -z "$_pn_out" ]] && continue
      while IFS= read -r _pn_match; do
        [[ -z "$_pn_match" ]] && continue
        echo "  [NAME] $_pn_match"
        _pn_found=1
      done <<< "$_pn_out"
    done
    if [[ "$_pn_found" -eq 1 ]]; then
      FOUND=1
    else
      echo "  clean (0 of ${#_pn_terms[@]} private term(s) found)"
    fi
  fi
fi

echo ""
if [[ "$FOUND" -eq 1 ]]; then
  echo "scrub-check: BLOCKED — findings above must be fixed or added to scripts/scrub-allowlist.txt"
  exit 1
fi

echo "scrub-check: clean"
exit 0
