#!/usr/bin/env bash
# imp-submit.sh — turn a filled-in IMP submission form, or a local ledger
# entry, into checked, ready-to-paste issue/PR text — WITHOUT ever sending
# anything over the network (IMP-219, Welle 4 / Gewerk G-script).
# See plans/vault-by-design-2026-09-25.md and
# templates/imp-submission.template.md for the design this implements.
#
# Two modes:
#
#   imp-submit.sh <filled-form.md>
#     Validates the six required fields (rejects a section that is empty or
#     byte-identical to the shipped template), then runs the SAME vault
#     matcher (scripts/vault/vault.sh — see its own header + scripts/
#     vault/lib.sh, "EIN Matcher, alle Verbraucher") against the whole
#     file: once with --structural-only (works on every clone, vault or
#     not) and once without (adds the submitter's own vault-registered
#     terms when a vault exists; relays vault.sh's own loud stderr line
#     when it does not — fail loud, not fail closed, matching vault.sh's
#     own contract). A finding blocks (exit 2) and is reported as kind +
#     token/"Platzhalter verwenden" ONLY — never the real value, not even
#     on this tool's own stderr. This is stricter than hooks/
#     vault-write-gate.sh's "term -> token" style: THIS tool's whole job
#     is to produce text meant to leave the machine, so nothing resembling
#     the real value may appear in any of its own output streams. A clean
#     file prints ready-to-paste text to stdout, headed by a
#     "checked with vault.sh <date>, 0 findings" line, with the internal
#     "Was NICHT hineingehört" instructions section stripped.
#
#   imp-submit.sh --from-ledger <IMP-ID> [--ledger <path>]
#     Reads ONE entry from a LOCAL ledger (default:
#     ~/.claude/global-observation/improvement-ledger.json, overridable via
#     --ledger or $CLAUDE_LEDGER_FILE), pre-fills as many of the template's
#     fields as the entry's shape supports, and prints the RESULT AS A FORM
#     (not final text — the submitter still runs it through the mode above
#     before actually posting anything). Requires a vault (exit 1 without
#     one: pre-filled text is copied out of a private ledger, so it MUST be
#     tokenized before being written anywhere, even to this script's own
#     stdout) — every value taken from the ledger is piped through
#     `vault.sh tokenize` before being placed into the form. The ledger
#     itself is opened read-only and is never modified.
#
# Deviation from the original task brief, measured 2026-09-25 (see this
# unit's handback report for the exact jq commands run): the brief assumed
# every ledger entry lives under `.activeImprovements` (an object keyed by
# id). Measured against the real local ledger, `.activeImprovements`
# entries carry the OLDER field shape (title/description/implementation/
# status/...) with no category/riskLevel/notes/evidence, while the NEWER
# shape ledger-append-proposed.sh actually writes (title/category/
# riskLevel/notes/evidence/...) lands under `.weeklyImproveProposals.
# entries[]` instead. --from-ledger looks the id up in BOTH locations
# rather than hardcoding the one that measurably does not hold the
# newer-shaped entries.
#
# bash 3.2 (stock macOS): no mapfile, no associative arrays, no ${var,,}.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/imp-submission.template.md"
VAULT_SH="$SCRIPT_DIR/vault/vault.sh"
VAULT_LIB="$SCRIPT_DIR/vault/lib.sh"

# The six required "## " headings, in template order — the SINGLE source of
# truth for which sections are load-bearing. Keep byte-identical to the
# headings in templates/imp-submission.template.md: a mismatch here makes
# validation see an "empty" section for that heading (fails safe — reported
# as missing, never silently accepted).
REQUIRED_FIELDS=(
  "Problemklasse"
  "Symptom"
  "Messwert / Beleg"
  "Vorgeschlagene Änderung"
  "Risiko / Band"
  "Rücknahme"
)
OPTIONAL_ID_FIELD="Lokale IMP-ID (optional — nur Referenz des Einreichers)"
FORBIDDEN_SECTION="Was NICHT hineingehört"

# Comma-joined string, not an array — bash 3.2 has no safe way to expand a
# possibly-EMPTY array under `set -u` without a guard at every call site;
# a plain string sidesteps that entirely. Tracks which --from-ledger fields
# could not be filled, or were filled with a value that still needs the
# submitter's own judgement (e.g. a riskLevel that needs translating into
# an agency-bands.md Band).
STILL_NEEDED=""

usage() {
  cat <<'EOF'
Usage:
  imp-submit.sh <filled-form.md>
  imp-submit.sh --from-ledger <IMP-ID> [--ledger <path>]

<filled-form.md>: a copy of templates/imp-submission.template.md with its
six required fields filled in. Checked against the local vault (if any)
and, always, against structural patterns (paths, emails, ids). Clean ->
ready-to-paste issue/PR text on stdout (exit 0). A missing/unfilled
required field -> exit 1, listing which. A real value found -> exit 2,
reporting kind + token only, never the value.

--from-ledger <IMP-ID>: pre-fills the template from one local ledger entry
(default ledger: ~/.claude/global-observation/improvement-ledger.json, or
$CLAUDE_LEDGER_FILE, or --ledger <path>). Requires a vault -- every value
taken from the ledger is tokenized before being printed. Prints the
pre-filled FORM (not final text) plus a hint of which fields still need
your own input. The ledger is read-only; never modified.

Exit codes: 0 clean, 1 missing field / usage / lookup error, 2 a real value
(or unresolved structural pattern) was found.
EOF
}

die() {  # die <message> [exit_code=1]
  local msg="$1" code="${2:-1}"
  echo "imp-submit: $msg" >&2
  exit "$code"
}

[[ -f "$VAULT_LIB" ]] || die "scripts/vault/lib.sh not found at $VAULT_LIB (internal error — repo layout changed?)"
# shellcheck source=./vault/lib.sh
. "$VAULT_LIB"

# ---------------------------------------------------------------------------
# Markdown section helpers — a "section" is everything strictly between one
# "## <heading>" line (exclusive) and the next "## " line or EOF (exclusive).
# Matching is EXACT-STRING on the whole line, never a regex — headings are
# fixed, known text, not user input.
# ---------------------------------------------------------------------------

_extract_section() {  # _extract_section <file> <heading> -> raw section body on stdout
  local file="$1" heading="$2"
  awk -v heading="## ${heading}" '
    $0 == heading { infield = 1; next }
    infield && /^## / { exit }
    infield { print }
  ' "$file"
}

_trim_block() {  # stdin -> stdout, strips leading/trailing whitespace/blank lines only
  perl -0777 -pe 's/\A\s+//; s/\s+\z//'
}

_replace_section() {  # _replace_section <infile> <heading> <valuefile> <outfile>
  # Prints <heading>, a blank line, then <valuefile>'s content verbatim
  # (multi-line safe), dropping everything the section used to contain up
  # to (not including) the next "## " heading or EOF. Every other line
  # passes through unchanged.
  local infile="$1" heading="$2" valuefile="$3" outfile="$4"
  awk -v heading="## ${heading}" -v valuefile="$valuefile" '
    BEGIN {
      first = 1
      while ((getline vline < valuefile) > 0) {
        if (first) { val = vline; first = 0 } else { val = val "\n" vline }
      }
      close(valuefile)
    }
    $0 == heading {
      print $0
      print ""
      print val
      print ""
      skipping = 1
      next
    }
    skipping && /^## / { skipping = 0 }
    skipping { next }
    { print }
  ' "$infile" > "$outfile"
}

_strip_forbidden_section() {  # _strip_forbidden_section <file> -> stdout
  # Drops the leading HTML-comment frontmatter and the
  # "Was NICHT hineingehört" section — both are instructions for the
  # FILLER, not content for readers of the eventual issue/PR.
  local file="$1"
  awk -v forbidden="## ${FORBIDDEN_SECTION}" '
    BEGIN { in_comment = 0; in_forbidden = 0 }
    /^<!--/ { in_comment = 1; next }
    in_comment && /-->/ { in_comment = 0; next }
    in_comment { next }
    $0 == forbidden { in_forbidden = 1; next }
    in_forbidden && /^## / { in_forbidden = 0 }
    in_forbidden { next }
    { print }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Vault plumbing
# ---------------------------------------------------------------------------

_run_vault_check() {  # _run_vault_check <extra_flag_or_empty>  (reads stdin)
  # Sets VC_OUT / VC_ERR / VC_RC. Always labels content "imp-submission.md"
  # (a fixed, generic name -- NEVER the submitter's real file path) so
  # vault.sh's path-scoped allowlist/fixture-marker logic can never
  # accidentally exempt real submitted content, and the submitter's own
  # filesystem layout never appears anywhere in this tool's output.
  local extra="$1" out err rc errfile
  errfile="$(mktemp "${TMPDIR:-/tmp}/imp-submit-vaulterr.XXXXXX")"
  set +e
  if [[ -n "$extra" ]]; then
    out="$("$VAULT_SH" check "$extra" --stdin --as imp-submission.md 2>"$errfile")"
  else
    out="$("$VAULT_SH" check --stdin --as imp-submission.md 2>"$errfile")"
  fi
  rc=$?
  set -e
  err="$(cat "$errfile" 2>/dev/null || true)"
  rm -f "$errfile"
  VC_OUT="$out"; VC_ERR="$err"; VC_RC="$rc"
}

_report_findings() {  # _report_findings <tsv findings> -- line/kind/token ONLY, NEVER the term column
  printf '%s\n' "$1" | while IFS=$'\t' read -r _label line kind _term token; do
    [[ -z "$kind" ]] && continue
    if [[ -n "$token" ]]; then
      echo "  line ${line}: [$kind] -> $token" >&2
    else
      echo "  line ${line}: [$kind] -> Platzhalter verwenden" >&2
    fi
  done
}

_tokenize_or_die() {  # _tokenize_or_die <value> -> tokenized value on stdout
  local value="$1" out rc
  if [[ -z "$value" ]]; then
    printf ''
    return 0
  fi
  set +e
  out="$(printf '%s' "$value" | "$VAULT_SH" tokenize 2>/dev/null)"
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || die "vault.sh tokenize failed unexpectedly (exit $rc) while pre-filling from the ledger" 1
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# Mode 1: check a filled form, emit ready-to-paste text
# ---------------------------------------------------------------------------

cmd_check_form() {
  local file="$1"
  [[ -f "$file" ]] || die "file not found: $file"
  [[ -f "$TEMPLATE" ]] || die "template not found: $TEMPLATE (internal error — repo layout changed?)"
  [[ -x "$VAULT_SH" ]] || die "scripts/vault/vault.sh not found/executable at $VAULT_SH (internal error)"

  local heading tpl_sec sub_sec
  local missing=()
  for heading in "${REQUIRED_FIELDS[@]}"; do
    tpl_sec="$(_extract_section "$TEMPLATE" "$heading" | _trim_block)"
    sub_sec="$(_extract_section "$file" "$heading" | _trim_block)"
    if [[ -z "$sub_sec" || "$sub_sec" == "$tpl_sec" ]]; then
      missing+=("$heading")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "imp-submit: missing or unfilled required field(s):" >&2
    local m
    for m in "${missing[@]}"; do echo "  - $m" >&2; done
    exit 1
  fi

  _run_vault_check "--structural-only" < "$file"
  local struct_out="$VC_OUT" struct_err="$VC_ERR" struct_rc="$VC_RC"

  _run_vault_check "" < "$file"
  local full_out="$VC_OUT" full_err="$VC_ERR" full_rc="$VC_RC"

  # vault.sh check's own contract is "0 clean, 2 findings, 1 error" -- an
  # rc outside {0,2} from either call is an infra failure. This tool's
  # entire purpose is to gate text before it leaves the machine, and there
  # is no downstream layer after it (a human may paste stdout straight into
  # a browser) -- so, unlike the PreToolUse/pre-commit hooks (which fail
  # OPEN as a hygiene gate per rules/fail-loud.md), this refuses to emit
  # anything on an infra error rather than risk an unchecked leak.
  if [[ "$full_rc" -ne 0 && "$full_rc" -ne 2 ]]; then
    die "vault.sh check failed unexpectedly (exit $full_rc)${full_err:+: $full_err} -- refusing to emit unchecked text" 2
  fi
  if [[ "$struct_rc" -ne 0 && "$struct_rc" -ne 2 ]]; then
    die "vault.sh check --structural-only failed unexpectedly (exit $struct_rc)${struct_err:+: $struct_err} -- refusing to emit unchecked text" 2
  fi

  if [[ "$full_rc" -eq 2 || "$struct_rc" -eq 2 ]]; then
    echo "imp-submit: BLOCKED -- real value(s) or an unresolved structural pattern were found. Use a placeholder, or register the term in your vault first." >&2
    if [[ "$full_rc" -eq 2 ]]; then
      _report_findings "$full_out" || true
    else
      _report_findings "$struct_out" || true
    fi
    exit 2
  fi

  # Clean. Relay any non-blocking vault.sh stderr (e.g. its own
  # "no vault present" warning) verbatim -- informational, not a finding.
  [[ -n "$full_err" ]] && printf '%s\n' "$full_err" >&2
  [[ -n "$struct_err" ]] && printf '%s\n' "$struct_err" >&2

  local body
  body="$(_strip_forbidden_section "$file")"
  printf 'geprüft mit vault.sh %s, 0 Funde\n\n%s\n' "$(date -u +%Y-%m-%d)" "$body"
}

# ---------------------------------------------------------------------------
# Mode 2: pre-fill a form from a local ledger entry
# ---------------------------------------------------------------------------

_note_still_needed() {  # _note_still_needed <label>
  if [[ -z "$STILL_NEEDED" ]]; then
    STILL_NEEDED="$1"
  else
    STILL_NEEDED="${STILL_NEEDED}, $1"
  fi
}

_maybe_fill() {  # _maybe_fill <cur_file> <heading> <value> -> new file path on stdout
  local cur="$1" heading="$2" value="$3" vf out
  if [[ -z "$value" ]]; then
    _note_still_needed "$heading"
    printf '%s' "$cur"
    return 0
  fi
  vf="$(mktemp "${TMPDIR:-/tmp}/imp-submit-val.XXXXXX")"
  printf '%s' "$value" > "$vf"
  out="$(mktemp "${TMPDIR:-/tmp}/imp-submit-doc.XXXXXX")"
  _replace_section "$cur" "$heading" "$vf" "$out"
  rm -f "$vf" "$cur"
  printf '%s' "$out"
}

cmd_from_ledger() {
  local id="$1"; shift
  local ledger="${CLAUDE_LEDGER_FILE:-$HOME/.claude/global-observation/improvement-ledger.json}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ledger) ledger="${2:?--ledger requires a path}"; shift 2 ;;
      *) die "--from-ledger: unrecognized argument: $1" ;;
    esac
  done

  vault_exists || die "no vault at $(vault_dir) -- cannot pseudonymize a ledger-derived submission without one. Run: scripts/vault/vault.sh init"
  command -v jq >/dev/null 2>&1 || die "jq not found"
  [[ -f "$ledger" ]] || die "ledger not found: $ledger"
  jq -e . "$ledger" >/dev/null 2>&1 || die "ledger is not valid JSON: $ledger"
  [[ -f "$TEMPLATE" ]] || die "template not found: $TEMPLATE (internal error — repo layout changed?)"

  # Look up the id in BOTH shapes the ledger is measured to carry it in --
  # see this file's header comment for why (both are checked, not just
  # .activeImprovements as the original task brief assumed).
  local shape="" entry=""
  entry="$(jq -c --arg id "$id" '.activeImprovements[$id] // empty' "$ledger" 2>/dev/null || true)"
  if [[ -n "$entry" && "$entry" != "null" ]]; then
    shape="active"
  else
    entry="$(jq -c --arg id "$id" '[(.weeklyImproveProposals.entries // [])[] | select(.id == $id)][0] // empty' "$ledger" 2>/dev/null || true)"
    [[ -n "$entry" && "$entry" != "null" ]] && shape="proposal"
  fi
  [[ -n "$shape" ]] || die "unknown IMP id in local ledger: $id"

  local raw_problemklasse raw_symptom raw_messwert raw_change raw_risk
  if [[ "$shape" == "active" ]]; then
    raw_problemklasse="$(printf '%s' "$entry" | jq -r '.title // ""')"
    raw_symptom="$raw_problemklasse"
    raw_change="$(printf '%s' "$entry" | jq -r '.implementation // .description // ""')"
    raw_messwert=""
    raw_risk=""
  else
    local raw_title raw_category raw_risklevel
    raw_title="$(printf '%s' "$entry" | jq -r '.title // ""')"
    raw_category="$(printf '%s' "$entry" | jq -r '.category // ""')"
    if [[ -n "$raw_category" && "$raw_category" != "uncategorized" ]]; then
      raw_problemklasse="${raw_category}: ${raw_title}"
    else
      raw_problemklasse="$raw_title"
    fi
    raw_symptom="$raw_title"
    raw_messwert="$(printf '%s' "$entry" | jq -r '.evidence // ""')"
    raw_change="$(printf '%s' "$entry" | jq -r '.notes // ""')"
    raw_risklevel="$(printf '%s' "$entry" | jq -r '.riskLevel // ""')"
    if [[ -n "$raw_risklevel" && "$raw_risklevel" != "unknown" ]]; then
      raw_risk="Ledger riskLevel '${raw_risklevel}' -- bitte in AUTO|SOFT-ACK|ESCALATE nach rules/agency-bands.md uebersetzen."
    else
      raw_risk=""
    fi
  fi

  local tok_problemklasse tok_symptom tok_messwert tok_change tok_risk
  tok_problemklasse="$(_tokenize_or_die "$raw_problemklasse")"
  tok_symptom="$(_tokenize_or_die "$raw_symptom")"
  tok_messwert="$(_tokenize_or_die "$raw_messwert")"
  tok_change="$(_tokenize_or_die "$raw_change")"
  tok_risk="$(_tokenize_or_die "$raw_risk")"

  local cur
  cur="$(mktemp "${TMPDIR:-/tmp}/imp-submit-doc.XXXXXX")"
  cp "$TEMPLATE" "$cur"

  cur="$(_maybe_fill "$cur" "Problemklasse" "$tok_problemklasse")"
  cur="$(_maybe_fill "$cur" "Symptom" "$tok_symptom")"
  cur="$(_maybe_fill "$cur" "Messwert / Beleg" "$tok_messwert")"
  cur="$(_maybe_fill "$cur" "Vorgeschlagene Änderung" "$tok_change")"
  cur="$(_maybe_fill "$cur" "Risiko / Band" "$tok_risk")"
  [[ -n "$tok_risk" ]] && _note_still_needed "Risiko / Band (Ledger-Wert übernommen, bitte in AUTO|SOFT-ACK|ESCALATE übersetzen/prüfen)"
  _note_still_needed "Rücknahme"  # never derivable from a ledger entry
  cur="$(_maybe_fill "$cur" "$OPTIONAL_ID_FIELD" "$id")"

  local hint
  hint="Vorausgefüllt aus ${id} am $(date -u +%Y-%m-%d) (Tresor: ja — jeder aus dem Ledger übernommene Wert wurde mit vault.sh tokenize ersetzt)."
  if [[ -n "$STILL_NEEDED" ]]; then
    hint="${hint} Bitte noch ausfüllen bzw. prüfen: ${STILL_NEEDED}."
  else
    hint="${hint} Alle Pflichtfelder wurden vorausgefüllt — bitte trotzdem inhaltlich prüfen, dann mit 'imp-submit.sh <datei>' checken."
  fi

  printf '%s\n\n' "$hint"
  cat "$cur"
  rm -f "$cur"
}

# ---------------------------------------------------------------------------
main() {
  [[ $# -ge 1 ]] || { usage >&2; exit 1; }
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --from-ledger)
      shift
      [[ $# -ge 1 ]] || die "--from-ledger requires an IMP id"
      cmd_from_ledger "$@"
      ;;
    --*) die "unrecognized option: $1" ;;
    *) cmd_check_form "$1" ;;
  esac
}

main "$@"
