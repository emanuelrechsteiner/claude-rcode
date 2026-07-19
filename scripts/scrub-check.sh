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
_name_a="Rech""steiner"
_name_b="Gram""menos"
_names="${_name_a}|${_name_b}"

# _identity intentionally does NOT include the bare lowercase GitHub account
# slug for this repo's owner — this repo is *itself* published under that
# account (D7, wave2-plan.md §0/§4/§8), so that exact slug is required, by
# design, in install.sh's REPO_URL, every clone-URL example, and CI badge.
# Flagging it would make "exit 0 on a clean, fully-sanitized repo"
# permanently impossible — a self-defeating gate. What genuinely must never
# appear is the private email domain, the retired second identity, and the
# local machine username.
_email_domain="emanuelrech""steiner\.de"
_identity_b="emanuel""gram""menos"
_identity_c="emanuel""privat"
_identity="info@${_email_domain}|${_identity_b}|${_identity_c}"

_proj_a="Chim""perator"
_proj_b="Verkaufs""zahlen"
_proj_c="Pa""riva"
_proj_d="Job""Joy"
_proj_e="BERS""ERKER"
_proj_f="Ehegatten""splitting"
_proj_g="OG""_Keemo"
_proj_h="Family""-Time"
_projects="${_proj_a}|${_proj_b}|${_proj_c}|${_proj_d}|${_proj_e}|${_proj_f}|${_proj_g}|${_proj_h}"

_path_a="/Volumes/NvME""-Satechi"
_path_b="/Users/emanuel""privat"
_paths="${_path_a}|${_path_b}"

_notion_id="36a4[0-9a-f]{4}"
_context7_uuid="3cbb""343f"

PII_PATTERN="(${_names}|${_identity}|${_projects}|${_paths}|${_notion_id}|${_context7_uuid})"

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
# ---------------------------------------------------------------------------
SELF_EXCLUDE=(':!scripts/scrub-check.sh' ':!scripts/scrub-allowlist.txt')

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

echo "Rebrand regression (leftover pre-rebrand project name):"
_rebrand_term="tor""valdsen"
rebrand_out=""
if [[ "$MODE" == "--staged" ]]; then
  # --cached: same index-content rationale as scan_pattern() above.
  rebrand_out=$(git grep --cached -niI "$_rebrand_term" -- "${FILES[@]}" ':!MIGRATION.md' "${SELF_EXCLUDE[@]}" 2>/dev/null || true)
else
  rebrand_out=$(git grep -niI "$_rebrand_term" -- . ':!MIGRATION.md' "${SELF_EXCLUDE[@]}" 2>/dev/null || true)
fi
if [[ -n "$rebrand_out" ]]; then
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    echo "  [REBRAND] $match"
    FOUND=1
  done <<< "$rebrand_out"
fi

echo ""
if [[ "$FOUND" -eq 1 ]]; then
  echo "scrub-check: BLOCKED — findings above must be fixed or added to scripts/scrub-allowlist.txt"
  exit 1
fi

echo "scrub-check: clean"
exit 0
