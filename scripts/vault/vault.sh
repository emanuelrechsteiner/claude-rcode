#!/usr/bin/env bash
# vault.sh — CLI for the pseudonymization vault. Real names/paths/accounts
# live ONLY here (${CLAUDE_VAULT_DIR:-~/.claude/vault}, gitignored, runtime
# data in the live install); the framework's own tracked files hold tokens instead.
# See plans/vault-by-design-2026-09-25.md for the design this implements.
#
# `doctor` (2026-09-25 hardening round) is a read-only diagnostic: checks
# dependencies (perl + its Digest::SHA/Unicode::Normalize modules, jq,
# git), vault directory/secret permissions, map.tsv's 4-column shape, and
# that public-names.txt is readable. It never prints a term/token/group —
# a malformed map.tsv row is reported by LINE NUMBER and problem CATEGORY
# only, never by the row's own content (the content of a malformed row is
# exactly the kind of thing that might be misplaced private data).
#
# Case-sensitivity per kind (finding N2 of the 2026-09-25 hardening round —
# documented here because it is otherwise only implicit in find_vault_matches
# in lib.sh): `project` and `account` match CASE-INSENSITIVELY, because
# prose and identifiers routinely vary the SAME name's capitalization
# (Title Case at a sentence start, kebab-case in a path, all-caps in a
# heading) — treating those as different terms would under-match the exact
# case the vault is meant to catch. `path`, `user`, `volume`, `email`,
# `id`, and `phrase` match CASE-SENSITIVELY: their stored terms are already
# exact literal strings taken verbatim from a real path, address, or
# identifier (or, for `phrase`, an exact quoted wording) — case is part of
# their identity, and folding it would risk matching an unrelated
# lowercase/uppercase word that only coincidentally shares letters.
#
# bash 3.2 (stock macOS) — no mapfile, no associative arrays, no ${var,,}.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  vault.sh init [--import-legacy <tsv>] [--from-registry <jsonl>]
  vault.sh add <kind> <term> --group <g> [--token <t>] [--alias <term>]...
  vault.sh check [--structural-only] [--stdin [--as <path>] | <file>...]
  vault.sh tokenize [--in-place] [--dry-run] [<file>...]
  vault.sh resolve
  vault.sh status
  vault.sh prune-public
  vault.sh token <kind> <value>
  vault.sh doctor

kind (add): project | account | path | user | volume | email | id | phrase
prune-public: removes any existing map.tsv row whose term exactly matches
a public framework identity (scripts/vault/public-names.txt) — idempotent.
--as <path>: only valid with --stdin. Names the target file for a --stdin
check whose content is not yet a file on disk (a write-gate hook staging
new content, a pre-commit hook checking the index). <path> may be
repo-relative (used as-is) or absolute (normalized to repo-relative via
`git -C "$(dirname <path>)" rev-parse --show-toplevel`, or left unchanged
if that fails). The reported "file" column, the allowlist match, and the
*/tests/* fixture-marker check all key off this path instead of "-".
Without --as, --stdin behaves exactly as before (file reported as "-",
no allowlist/fixture matching — both are path-based).
token <kind> <value>: prints the HMAC token for <value> WITHOUT storing it
in the vault — same derivation primitive as add's own default-token
derivation (vault_hmac_hex6), never a second computation. kind is one of
project | account | id (id yields "id-<hex6>"; every other kind has no
HMAC derivation and is refused). For runtime identifiers that need a
stable, secret-derived, but non-reversible key (e.g. a session id folded
into a ledger provenance key) without ever being written to map.tsv.
Requires only the vault's secret file to exist, not a full vault (no
map.tsv dependency) — a missing secret is Exit 1 with a clear message.
doctor: read-only diagnostic — dependencies (perl + Digest::SHA +
Unicode::Normalize, jq, git), vault dir (0700)/secret (0600) permissions,
map.tsv shape (every non-comment line exactly 4 tab-separated fields, a
known kind, non-empty term/token), public-names.txt readable. Never prints
a term/token/group; a malformed map.tsv row is reported by line number and
problem category only. Exit 0 healthy, 1 with one or more findings on
stderr.
Exit codes: init/add/status 0 ok, 1 error. check: 0 clean, 2 findings, 1
error. doctor: 0 healthy, 1 findings.
EOF
}

cmd_init() {
  local legacy="" registry=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --import-legacy) legacy="${2:?--import-legacy requires a path}"; shift 2 ;;
      --from-registry) registry="${2:?--from-registry requires a path}"; shift 2 ;;
      *) echo "vault: init — unrecognized argument: $1" >&2; return 1 ;;
    esac
  done
  local dir secret_file map_file
  dir="$(vault_dir)"; secret_file="$(vault_secret_file)"; map_file="$(vault_map_file)"
  mkdir -p "$dir"
  chmod 0700 "$dir"
  if [[ ! -f "$secret_file" ]]; then
    ( umask 077; openssl rand -hex 32 > "$secret_file" )
    chmod 0600 "$secret_file"
    echo "vault: init — generated a new secret at $secret_file" >&2
  else
    echo "vault: init — secret already present, left untouched (idempotent)" >&2
  fi
  [[ -f "$map_file" ]] || echo "# vault map v1" > "$map_file"
  [[ -n "$legacy" ]] && vault_import_legacy "$legacy"
  [[ -n "$registry" ]] && vault_import_registry "$registry"
  vault_status_summary
}

cmd_add() {
  vault_require || return 1
  [[ $# -ge 2 ]] || { echo "vault: add requires <kind> <term>" >&2; return 1; }
  local kind="$1" term="$2"; shift 2
  local group="" token=""
  local aliases=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --group) group="${2:?--group requires a value}"; shift 2 ;;
      --token) token="${2:?--token requires a value}"; shift 2 ;;
      --alias) aliases+=("${2:?--alias requires a value}"); shift 2 ;;
      *) echo "vault: add — unrecognized argument: $1" >&2; return 1 ;;
    esac
  done
  [[ -z "$group" ]] && group="$term"
  if [[ -z "$token" ]]; then
    if ! token="$(vault_default_token "$kind" "$group")"; then
      echo "vault: ABORT — kind '$kind' has no default token; pass --token explicitly" >&2
      return 1
    fi
  fi
  vault_add_row "$kind" "$term" "$token" "$group" || return 1
  local added=1 a
  for a in "${aliases[@]-}"; do
    [[ -z "$a" ]] && continue
    vault_add_row "$kind" "$a" "$token" "$group" || return 1
    added=$((added+1))
  done
  echo "vault: add — $added row(s) added under kind=$kind" >&2
}

# _vault_normalize_as_path <path> — resolves an --as argument to a
# repo-relative path: a relative input is used as-is (already assumed
# repo-relative by the caller's contract); an absolute input is normalized
# by finding its repo root (git -C "$(dirname <path>)" rev-parse
# --show-toplevel) and stripping that prefix. If git can't resolve a root
# (not inside a repo, or the parent directory doesn't exist yet), the path
# is used UNCHANGED — never an error, since "check" degrading to path-based
# gracefully is better than refusing to check at all.
_vault_normalize_as_path() {
  local p="$1"
  case "$p" in
    /*)
      local root
      root="$(git -C "$(dirname "$p")" rev-parse --show-toplevel 2>/dev/null)" || { printf '%s' "$p"; return 0; }
      case "$p" in
        "$root"/*) printf '%s' "${p#"$root"/}" ;;
        *) printf '%s' "$p" ;;
      esac
      ;;
    *) printf '%s' "$p" ;;
  esac
}

cmd_check() {
  local structural_only=0 use_stdin=0 as_path=""
  local files=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --structural-only) structural_only=1; shift ;;
      --stdin) use_stdin=1; shift ;;
      --as) as_path="${2:?--as requires a path}"; shift 2 ;;
      *) files+=("$1"); shift ;;
    esac
  done

  if [[ -n "$as_path" && "$use_stdin" -ne 1 ]]; then
    echo "vault: check — --as requires --stdin" >&2
    return 1
  fi

  local have_vault=0
  vault_exists && have_vault=1
  if [[ "$have_vault" -eq 0 && "$structural_only" -eq 0 ]]; then
    vault_warn_missing
  fi

  local rules=""
  if [[ "$have_vault" -eq 1 && "$structural_only" -eq 0 ]]; then
    rules="$(mktemp "${TMPDIR:-/tmp}/vault-rules.XXXXXX")"
    vault_build_rules_file "$rules"
  fi
  local allowlist="$SCRIPT_DIR/../scrub-allowlist.txt"
  [[ -f "$allowlist" ]] || allowlist=""

  local overall=0 rc

  if [[ "$use_stdin" -eq 1 ]]; then
    local stdin_label="-"
    [[ -n "$as_path" ]] && stdin_label="$(_vault_normalize_as_path "$as_path")"
    set +e
    vault_matcher_run check 1 "$stdin_label" "$rules" "$allowlist"
    rc=$?
    set -e
    [[ "$rc" -eq 2 ]] && overall=2
    [[ "$rc" -ne 0 && "$rc" -ne 2 ]] && overall=1
  else
    if [[ ${#files[@]} -eq 0 ]]; then
      echo "vault: check — no files given and --stdin not set" >&2
      overall=1
    fi
    local f
    for f in "${files[@]-}"; do
      [[ -z "$f" ]] && continue
      if [[ ! -f "$f" ]]; then
        echo "vault: check — cannot read file: $f" >&2
        overall=1
        continue
      fi
      set +e
      vault_matcher_run check 1 "$f" "$rules" "$allowlist" < "$f"
      rc=$?
      set -e
      if [[ "$rc" -eq 2 ]]; then
        [[ "$overall" -lt 2 ]] && overall=2
      elif [[ "$rc" -ne 0 ]]; then
        overall=1
      fi
    done
  fi

  [[ -n "$rules" ]] && rm -f "$rules"
  return "$overall"
}

cmd_tokenize() {
  vault_require || return 1
  local in_place=0 dry_run=0
  local files=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --in-place) in_place=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      *) files+=("$1"); shift ;;
    esac
  done
  local rules; rules="$(mktemp "${TMPDIR:-/tmp}/vault-rules.XXXXXX")"
  vault_build_rules_file "$rules"
  # Same allowlist path cmd_check uses — tokenize now honors it too (round
  # 5, finding #1): previously this was always passed as "" here, so an
  # allowlisted attribution line (LICENSE:3, README.md:238) still got
  # rewritten by tokenize even though check would never have flagged it.
  local allowlist="$SCRIPT_DIR/../scrub-allowlist.txt"
  [[ -f "$allowlist" ]] || allowlist=""

  if [[ ${#files[@]} -eq 0 ]]; then
    vault_matcher_run tokenize 0 "-" "$rules" "$allowlist" "$dry_run"
    rm -f "$rules"
    return 0
  fi

  local f
  for f in "${files[@]}"; do
    if [[ "$dry_run" -eq 1 ]]; then
      vault_matcher_run tokenize 0 "$f" "$rules" "$allowlist" 1 < "$f"
    elif [[ "$in_place" -eq 1 ]]; then
      # Write ONLY when something actually changed, and preserve the
      # original file's mode (round 5, finding #2): mktemp+mv previously
      # replaced the file's inode unconditionally, which (a) rewrote ten
      # files' EOF byte-for-byte identically otherwise — now moot, since
      # emit_line no longer adds a newline that wasn't there — and (b)
      # always left mktemp's 0600 behind, silently stripping an executable
      # script's mode bits (e.g. 0755 -> 0600). cmp -s decides "changed";
      # the ORIGINAL mode (captured BEFORE the swap) is re-applied after.
      local tmp_out; tmp_out="$(mktemp "${TMPDIR:-/tmp}/vault-tokout.XXXXXX")"
      vault_matcher_run tokenize 0 "$f" "$rules" "$allowlist" 0 < "$f" > "$tmp_out"
      if cmp -s "$f" "$tmp_out"; then
        rm -f "$tmp_out"
      else
        local orig_mode
        orig_mode="$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null)"
        mv "$tmp_out" "$f"
        [[ -n "$orig_mode" ]] && chmod "$orig_mode" "$f"
      fi
    else
      vault_matcher_run tokenize 0 "$f" "$rules" "$allowlist" 0 < "$f"
    fi
  done
  rm -f "$rules"
}

cmd_resolve() {
  vault_require || return 1
  local rules; rules="$(mktemp "${TMPDIR:-/tmp}/vault-rules.XXXXXX")"
  vault_build_rules_file "$rules"
  vault_matcher_run resolve 0 "-" "$rules" ""
  rm -f "$rules"
}

cmd_status() { vault_status_summary; }

# cmd_prune_public — removes any EXISTING map.tsv row whose term exactly
# matches a public framework identity (scripts/vault/public-names.txt,
# §7.1). Idempotent: a second run removes 0 rows. Header/comment lines pass
# through untouched. Reports counts only, never a term.
cmd_prune_public() {
  vault_require || return 1
  local map pubfile
  map="$(vault_map_file)"
  pubfile="$(vault_public_names_file)"
  if [[ ! -f "$pubfile" ]]; then
    echo "vault: prune-public — no public-names file at $pubfile, nothing to prune" >&2
    return 0
  fi
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/vault-prune.XXXXXX")"
  local removed=0 kept=0
  local line kind term token group
  while IFS= read -r line; do
    if [[ -z "$line" || "$line" == \#* ]]; then
      printf '%s\n' "$line" >> "$tmp"
      continue
    fi
    IFS=$'\t' read -r kind term token group <<< "$line"
    if vault_is_public_name "$term"; then
      removed=$((removed+1))
    else
      printf '%s\n' "$line" >> "$tmp"
      kept=$((kept+1))
    fi
  done < "$map"
  mv "$tmp" "$map"
  echo "vault: prune-public — removed ${removed} row(s), ${kept} row(s) kept" >&2
}

# cmd_token <kind> <value> — prints the HMAC token for <value> WITHOUT
# storing anything (round 3, finding #8). Only kinds with an HMAC
# derivation are accepted: project, account, id (as "id-<hex6>") — see
# vault_hmac_token_for's own header comment for why this is a separate,
# additive derivation from add's default and not a change to it. Requires
# only the secret (not the full map.tsv) — "kein Geheimwert" is the
# documented failure, not "no vault" generally.
cmd_token() {
  [[ $# -ge 2 ]] || { echo "vault: token requires <kind> <value>" >&2; return 1; }
  local kind="$1" value="$2"
  if [[ ! -f "$(vault_secret_file)" ]]; then
    echo "vault: ABORT — no secret at $(vault_secret_file). Run: scripts/vault/vault.sh init" >&2
    return 1
  fi
  local tok
  if ! tok="$(vault_hmac_token_for "$kind" "$value")"; then
    echo "vault: ABORT — kind '$kind' has no HMAC derivation (only project|account|id)" >&2
    return 1
  fi
  printf '%s\n' "$tok"
}

# cmd_doctor — read-only diagnostic (2026-09-25 hardening round). NEVER
# prints a term/token/group: a malformed map.tsv row is reported by LINE
# NUMBER and problem CATEGORY only (see vault.sh's own header comment for
# why). Checks, in order: 1) dependencies, 2) vault dir/secret
# permissions, 3) map.tsv shape, 4) public-names.txt readable.
cmd_doctor() {
  local exit_code=0

  # 1) Dependencies -------------------------------------------------------
  if command -v perl >/dev/null 2>&1; then
    perl -MDigest::SHA -e 1 >/dev/null 2>&1 \
      || { echo "vault: doctor — MISSING perl module Digest::SHA (in-process HMAC derivation)" >&2; exit_code=1; }
    perl -MUnicode::Normalize -e 1 >/dev/null 2>&1 \
      || { echo "vault: doctor — MISSING perl module Unicode::Normalize (NFC/NFD-aware matching)" >&2; exit_code=1; }
  else
    echo "vault: doctor — MISSING dependency: perl" >&2
    exit_code=1
  fi
  command -v jq  >/dev/null 2>&1 || { echo "vault: doctor — MISSING dependency: jq (init --from-registry)" >&2; exit_code=1; }
  command -v git >/dev/null 2>&1 || { echo "vault: doctor — MISSING dependency: git (check --stdin --as path normalization)" >&2; exit_code=1; }

  # 2) Permissions ----------------------------------------------------------
  local dir; dir="$(vault_dir)"
  if [[ -d "$dir" ]]; then
    local dmode; dmode="$(stat -f '%Lp' "$dir" 2>/dev/null || stat -c '%a' "$dir" 2>/dev/null || echo '')"
    [[ "$dmode" == "700" ]] || { echo "vault: doctor — vault dir is mode ${dmode:-unknown}, expected 0700 ($dir)" >&2; exit_code=1; }
  else
    echo "vault: doctor — no vault dir at $dir (run: scripts/vault/vault.sh init)" >&2
    exit_code=1
  fi
  if [[ -f "$(vault_secret_file)" ]]; then
    local smode; smode="$(stat -f '%Lp' "$(vault_secret_file)" 2>/dev/null || stat -c '%a' "$(vault_secret_file)" 2>/dev/null || echo '')"
    [[ "$smode" == "600" ]] || { echo "vault: doctor — secret file is mode ${smode:-unknown}, expected 0600" >&2; exit_code=1; }
  else
    echo "vault: doctor — no secret file at $(vault_secret_file)" >&2
    exit_code=1
  fi

  # 3) map.tsv format — exactly 4 tab-separated fields per non-comment,
  # non-blank line; kind must be one of the 8 known kinds; term/token
  # non-empty. ONE awk pass over the whole file (not a process-per-line
  # loop — same performance discipline as vault_strip_public_terms/
  # vault_build_rules_file elsewhere in this codebase). The awk output is
  # a fixed set of CATEGORY tags + line numbers + (for BADFIELDS only) a
  # numeric field count — never term/token/kind content, so the bash loop
  # below has nothing sensitive to accidentally echo either.
  local map; map="$(vault_map_file)"
  if [[ -f "$map" ]]; then
    local findings
    findings="$(awk -F'\t' '
      /^#/ { next }
      $0 == "" { next }
      {
        if (NF != 4) { printf("BADFIELDS\t%d\t%d\n", NR, NF); next }
        kind=$1; term=$2; token=$3
        known = (kind=="project" || kind=="account" || kind=="path" || kind=="user" || \
                 kind=="volume" || kind=="email" || kind=="id" || kind=="phrase")
        if (!known)     printf("BADKIND\t%d\n", NR)
        if (term == "") printf("EMPTYTERM\t%d\n", NR)
        if (token == "") printf("EMPTYTOKEN\t%d\n", NR)
      }
    ' "$map")"
    if [[ -n "$findings" ]]; then
      local ftype fline fextra
      while IFS=$'\t' read -r ftype fline fextra; do
        [[ -z "$ftype" ]] && continue
        case "$ftype" in
          BADFIELDS)  echo "vault: doctor — map.tsv:$fline — expected 4 tab-separated fields, found $fextra" >&2 ;;
          BADKIND)    echo "vault: doctor — map.tsv:$fline — unknown kind" >&2 ;;
          EMPTYTERM)  echo "vault: doctor — map.tsv:$fline — empty term" >&2 ;;
          EMPTYTOKEN) echo "vault: doctor — map.tsv:$fline — empty token" >&2 ;;
        esac
      done <<< "$findings"
      exit_code=1
    fi
  else
    echo "vault: doctor — no map.tsv at $map" >&2
    exit_code=1
  fi

  # 4) public-names.txt readable -------------------------------------------
  local pubfile; pubfile="$(vault_public_names_file)"
  [[ -r "$pubfile" ]] || { echo "vault: doctor — public-names file not readable: $pubfile" >&2; exit_code=1; }

  [[ "$exit_code" -eq 0 ]] && echo "vault: doctor — all checks passed ($dir)" >&2
  return "$exit_code"
}

main() {
  local cmd="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$cmd" in
    init)         cmd_init "$@" ;;
    add)          cmd_add "$@" ;;
    check)        cmd_check "$@" ;;
    tokenize)     cmd_tokenize "$@" ;;
    resolve)      cmd_resolve "$@" ;;
    status)       cmd_status "$@" ;;
    prune-public) cmd_prune_public "$@" ;;
    token)        cmd_token "$@" ;;
    doctor)       cmd_doctor "$@" ;;
    -h|--help|"") usage; [[ "$cmd" == "" ]] && exit 1; exit 0 ;;
    *) echo "vault: unknown command '$cmd'" >&2; usage >&2; exit 1 ;;
  esac
}

main "$@"
