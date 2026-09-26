#!/usr/bin/env bash
# lib.sh — the ONE matcher for the vault. Sourced (never executed) by
# scripts/vault/vault.sh, scripts/scrub-check.sh (§7), and
# publish-transforms.d/{30-placeholder-scan,50-pseudonymize}.sh. Welle 2 adds
# hooks/vault-write-gate.sh and scripts/git-hooks/pre-commit as further
# sourcers — no second matcher is written anywhere (rules/testing-quality.md
# "Verify Via the Same Code Path"). Design: plans/vault-by-design-2026-09-25.md
# §2/§3.
#
# bash 3.2 (stock macOS): no mapfile, no associative arrays, no ${var,,}.
# Every public function is prefixed vault_.

# Captured at SOURCE time (top level, not inside a function) so it reflects
# THIS file's own directory regardless of which script later sources it and
# from which cwd — the standard pattern already used by scrub-check.sh's
# SCRIPT_DIR.
_VAULT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
vault_dir() { printf '%s' "${CLAUDE_VAULT_DIR:-$HOME/.claude/vault}"; }
vault_secret_file() { printf '%s/secret' "$(vault_dir)"; }
vault_map_file() { printf '%s/map.tsv' "$(vault_dir)"; }
vault_public_names_file() { printf '%s/public-names.txt' "$_VAULT_LIB_DIR"; }
vault_lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# vault_is_public_name <term> — true iff term EXACTLY matches (case-
# insensitive) one of the framework's own public identities
# (scripts/vault/public-names.txt, plans/vault-by-design-2026-09-25.md
# §7.1). A longer name that merely CONTAINS a public name (e.g. a directory
# named "<public-name>-extra") is NOT a match — this is deliberately exact,
# not substring, so real private terms are never accidentally exempted by
# sharing a public name as a prefix/suffix.
# Single awk process regardless of public-names.txt size — the previous
# bash while-loop spawned a `tr` subprocess (via vault_lc) PER LINE of
# public-names.txt, on top of one for the term itself (2026-09-25 rework
# round 4, performance). For a single ad-hoc lookup (e.g. inside `add`)
# this alone is a small saving; the real cost lived in the per-map-row
# callers below, which is why THIS function no longer gets called in a
# loop for those (vault_strip_public_terms loads the list itself now).
# Same semantics as before: exact whole-line match, case-insensitive via
# tolower(), blank lines and '#' comments in public-names.txt ignored;
# LC_ALL=C for deterministic byte-wise case-folding regardless of the
# caller's locale.
vault_is_public_name() {
  local term="$1"
  local f; f="$(vault_public_names_file)"
  [[ -f "$f" ]] || return 1
  LC_ALL=C awk -v term="$term" '
    BEGIN { needle = tolower(term); found = 0 }
    $0 == "" { next }
    /^#/ { next }
    tolower($0) == needle { found = 1; exit }
    END { exit (found ? 0 : 1) }
  ' "$f"
}

vault_exists() { [[ -f "$(vault_secret_file)" && -f "$(vault_map_file)" ]]; }

# One loud, single-line stderr warning — fail loud, not fail closed. A fresh
# clone / public CI has no vault by design; structural checks must still run.
vault_warn_missing() {
  echo "vault: WARNING — no vault at $(vault_dir) (run: scripts/vault/vault.sh init). Vault-sourced rules skipped; structural patterns still run." >&2
}

vault_require() {
  vault_exists && return 0
  echo "vault: ABORT — no vault at $(vault_dir). Run: scripts/vault/vault.sh init" >&2
  return 1
}

# ---------------------------------------------------------------------------
# HMAC token derivation (perl Digest::SHA, in-process — 2026-09-25 hardening)
# ---------------------------------------------------------------------------
# _vault_write_hmac_pl <out> — writes a perl helper that computes an
# HMAC-SHA256 hex digest with the secret read IN-PROCESS from a file path
# handed via the VAULT_SECRET_FILE env var. The secret's VALUE never
# appears as a command-line argument (visible to `ps` for the whole life
# of the process) — only the FILE PATH does, and only as an env var. The
# prior implementation passed the secret itself as `openssl ... -hmac
# "$secret"`, a plain argv element.
#
# Key-byte semantics are UNCHANGED: the secret file holds 64 ASCII hex
# characters (openssl rand -hex 32 > file) plus a trailing newline;
# `openssl -hmac "$secret"` HMACs with the BYTES OF THAT STRING (the ASCII
# hex TEXT), not the 32 decoded raw bytes — verified live before landing
# (see handback report: openssl and this perl helper produce the
# byte-identical digest for the same string key, both inline and via a
# real secret file). Trailing newline(s) are stripped exactly like bash
# command substitution `secret="$(cat file)"` strips them (`s/\n+\z//`),
# so the key bytes match the previous implementation's byte-for-byte.
# Input data travels via STDIN, exactly as before (never argv either).
# openssl is no longer a dependency of this derivation (still used
# elsewhere by cmd_init to GENERATE a fresh secret — unrelated: that call
# never places an EXISTING secret value on argv).
_vault_write_hmac_pl() {
  cat > "$1" <<'PERLEOF'
use strict; use warnings;
use Digest::SHA qw(hmac_sha256_hex);

my $secret_file = $ENV{VAULT_SECRET_FILE} or die "VAULT_SECRET_FILE required\n";
open(my $sh, '<', $secret_file) or die "vault-hmac: cannot open secret file: $!\n";
my $secret = do { local $/; <$sh> };
close $sh;
$secret = '' unless defined $secret;
$secret =~ s/\n+\z//;

my $data = do { local $/; <STDIN> };
$data = '' unless defined $data;
print hmac_sha256_hex($data, $secret);
PERLEOF
}

vault_hmac_hex6() {
  local data="$1" pl full
  pl="$(mktemp "${TMPDIR:-/tmp}/vault-hmac.XXXXXX")"
  _vault_write_hmac_pl "$pl"
  full="$(printf '%s' "$data" | VAULT_SECRET_FILE="$(vault_secret_file)" perl "$pl")"
  rm -f "$pl"
  printf '%s' "$full" | cut -c1-6
}

# vault_default_token <kind> <group> — token `add` uses absent an explicit
# --token. id/phrase have no sensible default (§2 table: "kein HMAC") and
# fail: callers MUST pass --token for those two kinds.
vault_default_token() {
  local kind="$1" group="$2" hex6
  case "$kind" in
    project) hex6="$(vault_hmac_hex6 "project:${group}")"; printf 'proj-%s' "$hex6" ;;
    account) hex6="$(vault_hmac_hex6 "account:${group}")"; printf 'acct-%s' "$hex6" ;;
    path)    hex6="$(vault_hmac_hex6 "project:${group}")"; printf '<proj-%s>' "$hex6" ;;
    volume)  printf '<VOLUME>' ;;
    email)   printf '<email>' ;;
    user)    printf '<user>' ;;
    *)       return 1 ;;
  esac
}

# vault_hmac_token_for <kind> <value> — the standalone `vault.sh token`
# subcommand's derivation (round 3, finding #8): the SAME underlying
# derivation primitive as vault_default_token (vault_hmac_hex6 — there is
# only ever one HMAC computation in this file, rules/testing-quality.md
# "same code path"), but with token's OWN allowed-kind set: project,
# account, and — new here — id as "id-<hex6>". Deliberately NOT folded
# into vault_default_token itself: that function is add's own
# no-explicit-token DEFAULT, and id has no such default there by design
# (§2's kind=id row — an id term's real placeholder varies per specific
# instance and needs a human-chosen one, e.g. "<session-id>", not a
# generic hash). This is an ADDITIVE, separate capability for callers that
# explicitly want a generic HMAC-derived key for a kind of id-shaped
# runtime identifier (e.g. folding a session id into a ledger provenance
# key) without ever storing that identifier in the vault.
vault_hmac_token_for() {
  local kind="$1" value="$2" hex6
  case "$kind" in
    project) hex6="$(vault_hmac_hex6 "project:${value}")"; printf 'proj-%s' "$hex6" ;;
    account) hex6="$(vault_hmac_hex6 "account:${value}")"; printf 'acct-%s' "$hex6" ;;
    id)      hex6="$(vault_hmac_hex6 "id:${value}")"; printf 'id-%s' "$hex6" ;;
    *)       return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Storage: map.tsv rows are `kind<TAB>term<TAB>token<TAB>group`
# ---------------------------------------------------------------------------
# vault_add_row <kind> <term> <token> <group> — Exit 1 if term already
# belongs to a different group (case-insensitive), Exit 3 if term is a
# public framework identity (scripts/vault/public-names.txt, §7.1 — a
# distinct code from the plain "1" conflict so callers can tell "this is
# forbidden by design" apart from "this collides with existing data" and
# react differently: `add` refuses either way, but a bulk import counts a
# public-name hit as a skip, not a conflict). Idempotent: an identical row
# already present is a silent no-op success.
vault_add_row() {
  local kind="$1" term="$2" token="$3" group="$4"
  case "$kind" in
    project|account|path|user|volume|email|id|phrase) ;;
    *) echo "vault: ABORT — unknown kind '$kind'" >&2; return 1 ;;
  esac
  if [[ -z "$term" || -z "$token" || -z "$group" ]]; then
    echo "vault: ABORT — kind/term/token/group must all be non-empty" >&2
    return 1
  fi
  if vault_is_public_name "$term"; then
    echo "vault: REFUSED — '$term' is a public framework identity (scripts/vault/public-names.txt), never a vault term" >&2
    return 3
  fi
  local term_lc; term_lc="$(vault_lc "$term")"
  local l_kind l_term l_token l_group found_same=0
  if [[ -f "$(vault_map_file)" ]]; then
    while IFS=$'\t' read -r l_kind l_term l_token l_group; do
      [[ -z "$l_kind" || "$l_kind" == \#* ]] && continue
      if [[ "$(vault_lc "$l_term")" == "$term_lc" ]]; then
        if [[ "$l_group" != "$group" ]]; then
          echo "vault: ABORT — term already registered under a different group" >&2
          return 1
        fi
        [[ "$l_kind" == "$kind" && "$l_term" == "$term" && "$l_token" == "$token" ]] && found_same=1
      fi
    done < "$(vault_map_file)"
  fi
  [[ "$found_same" -eq 1 ]] && return 0
  printf '%s\t%s\t%s\t%s\n' "$kind" "$term" "$token" "$group" >> "$(vault_map_file)"
}

# vault_status_summary — counts per kind + secret/mtime, to STDERR. Never a term.
vault_status_summary() {
  if ! vault_exists; then
    echo "vault: no vault at $(vault_dir)" >&2
    return 0
  fi
  local mtime
  mtime="$(stat -f '%Sm' "$(vault_map_file)" 2>/dev/null || stat -c '%y' "$(vault_map_file)" 2>/dev/null || echo unknown)"
  echo "vault: dir=$(vault_dir) secret=yes map_mtime=$mtime" >&2
  local k
  for k in project account path user volume email id phrase; do
    local c; c=$(awk -F'\t' -v k="$k" '$1==k{n++} END{print n+0}' "$(vault_map_file)")
    echo "vault:   $k: $c" >&2
  done
}

# vault_terms_for_kinds "<space-separated kinds>" — one TERM per line for
# every map.tsv row whose kind is in the given list. Used by consumers that
# build their OWN pattern from vault terms (e.g. scrub-check.sh §2) rather
# than running the full matcher. Caller must have already checked
# vault_exists; an absent vault just yields no output (no error here — the
# loud warning is the caller's job, per its own context/wording).
# vault_strip_public_terms <term_field_num> — stdin|stdout filter, drops
# any line whose tab-separated field <term_field_num> is a public framework
# identity (§7.1). Defense-in-depth: the matcher must never report/use a
# public name even if one somehow ended up in map.tsv despite
# vault_add_row refusing it at write time (e.g. a hand-edited map.tsv, or
# data imported before public-names.txt existed) — "der Matcher meldet sie
# nie" is enforced HERE, not only at add-time, so every consumer of
# map.tsv-derived data gets this for free by routing through one of the
# three functions below rather than reading map.tsv raw.
#
# ONE awk process regardless of input size (2026-09-25 rework round 4,
# performance): the previous version was a bash while-loop calling `cut`
# AND vault_is_public_name (itself a per-public-names-line `tr` loop) once
# PER INPUT LINE — against the real ~200-row vault this measured ~2.65s
# for a single "check" call, called on every hook-gated edit. public-
# names.txt is loaded ONCE into an awk array in BEGIN (tolower'd, same
# blank-line/'#'-comment skip as before), then every input line is
# filtered in the same single pass. Same semantics, not a cache — the
# filtering RULE is unchanged, only how many processes it costs.
vault_strip_public_terms() {
  local field="$1"
  local pubfile; pubfile="$(vault_public_names_file)"
  LC_ALL=C awk -F'\t' -v field="$field" -v pubfile="$pubfile" '
    BEGIN {
      if (pubfile != "") {
        while ((getline pline < pubfile) > 0) {
          if (pline == "" || pline ~ /^#/) continue
          pub[tolower(pline)] = 1
        }
        close(pubfile)
      }
    }
    { if (!(tolower($field) in pub)) print }
  '
}

vault_terms_for_kinds() {
  local kinds=" $1 "
  [[ -f "$(vault_map_file)" ]] || return 0
  awk -F'\t' -v kinds="$kinds" '$1 !~ /^#/ && index(kinds, " " $1 " ") { print $2 }' "$(vault_map_file)" | vault_strip_public_terms 1
}

# vault_term_token_pairs_for_kinds "<space-separated kinds>" — one
# "term<TAB>token" pair per line, for consumers that need BOTH (e.g.
# publish-transforms.d/30-placeholder-scan.sh's user/volume rules, which
# both search for a term AND need a replacement value).
vault_term_token_pairs_for_kinds() {
  local kinds=" $1 "
  [[ -f "$(vault_map_file)" ]] || return 0
  awk -F'\t' -v kinds="$kinds" '$1 !~ /^#/ && index(kinds, " " $1 " ") { print $2 "\t" $3 }' "$(vault_map_file)" | vault_strip_public_terms 1
}


# vault_build_rules_file <out> — map.tsv rows re-ordered into the 3
# mandatory stages (§3): 1) path longest-first, 2) project/account
# longest-first, 3) the rest longest-first. Skips header/comments and any
# public-framework-identity row (vault_strip_public_terms, field 2 = term
# in this 4-column kind/term/token/group output).
vault_build_rules_file() {
  local out="$1" stage
  : > "$out"
  for stage in path 'project account' 'user volume email id phrase'; do
    awk -F'\t' -v kinds=" $stage " '
      $1 !~ /^#/ && index(kinds, " " $1 " ") { print length($2) "\t" $0 }
    ' "$(vault_map_file)" | sort -t "$(printf '\t')" -k1,1rn | cut -f2- | vault_strip_public_terms 2 >> "$out"
  done
}

# ---------------------------------------------------------------------------
# Import: legacy pseudonym tsv (real<TAB>placeholder)
# ---------------------------------------------------------------------------
# vault_classify_legacy_placeholder <placeholder> — §2 heuristic, in order.
vault_classify_legacy_placeholder() {
  local ph="$1"
  if [[ "$ph" =~ ^Projekt\ [A-Z]$ || "$ph" == "ProjectHub" || "$ph" == "config-repo" || "$ph" =~ ^projekt-[a-z]$ ]]; then
    echo project; return
  fi
  if [[ "$ph" == Example* || "$ph" == example-* ]]; then
    echo account; return
  fi
  if [[ "$ph" =~ ^\<.*-id\>$ || "$ph" =~ ^aaaa[0-9]{4}$ ]]; then
    echo id; return
  fi
  if [[ "$ph" == "UTC" || "$ph" == *' '* ]]; then
    echo phrase; return
  fi
  echo project
}

vault_import_legacy() {
  local tsv="$1"
  [[ -f "$tsv" ]] || { echo "vault: ABORT — legacy list not found: $tsv" >&2; return 1; }
  local terms=() phs=() term ph
  while IFS=$'\t' read -r term ph; do
    [[ -z "$term" || "$term" == \#* ]] && continue
    [[ -z "${ph:-}" ]] && continue
    terms+=("$term"); phs+=("$ph")
  done < "$tsv"
  local n=${#terms[@]}
  if [[ "$n" -eq 0 ]]; then
    echo "vault: import-legacy — $tsv present but empty, nothing imported" >&2
    return 0
  fi
  local distinct=() i j is_new d
  i=0
  while [[ $i -lt $n ]]; do
    is_new=1; j=0
    while [[ $j -lt ${#distinct[@]} ]]; do [[ "${distinct[$j]}" == "${phs[$i]}" ]] && { is_new=0; break; }; j=$((j+1)); done
    [[ "$is_new" -eq 1 ]] && distinct+=("${phs[$i]}")
    i=$((i+1))
  done
  local imported=0 conflicts=0 skipped_public=0 kind token group glen tl rc
  for d in "${distinct[@]}"; do
    group=""; glen=0
    i=0
    while [[ $i -lt $n ]]; do
      if [[ "${phs[$i]}" == "$d" ]]; then
        tl=${#terms[$i]}
        [[ $tl -gt $glen ]] && { glen=$tl; group="${terms[$i]}"; }
      fi
      i=$((i+1))
    done
    kind="$(vault_classify_legacy_placeholder "$d")"
    case "$kind" in
      id|phrase) token="$d" ;;
      *) token="$(vault_default_token "$kind" "$group")" ;;
    esac
    i=0
    while [[ $i -lt $n ]]; do
      if [[ "${phs[$i]}" == "$d" ]]; then
        rc=0
        vault_add_row "$kind" "${terms[$i]}" "$token" "$group" >/dev/null 2>&1 || rc=$?
        if [[ "$rc" -eq 0 ]]; then
          imported=$((imported+1))
        elif [[ "$rc" -eq 3 ]]; then
          skipped_public=$((skipped_public+1))
        else
          conflicts=$((conflicts+1))
        fi
      fi
      i=$((i+1))
    done
  done
  echo "vault: import-legacy — ${#distinct[@]} group(s), ${imported} row(s) imported, ${conflicts} conflict(s), ${skipped_public} skipped (public framework identity, §7.1)" >&2
}

# _vault_add_and_tally <kind> <term> <token> <group> — calls vault_add_row
# and bumps the CALLER's own $imported/$conflicts/$skipped_public counters
# (bash's dynamic scoping: a `local` in the caller is visible to a function
# it calls, verified before landing — see handback report). Shared by
# vault_import_registry's four call sites to avoid repeating the same
# three-way exit-code branch (0=imported, 3=public-skip, else=conflict).
_vault_add_and_tally() {
  local rc=0
  vault_add_row "$@" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) imported=$((imported+1)) ;;
    3) skipped_public=$((skipped_public+1)) ;;
    *) conflicts=$((conflicts+1)) ;;
  esac
}

# ---------------------------------------------------------------------------
# Import: project registry JSONL (name/pfad/git/id fields — see
# skills/meta-intelligence/SKILL.md for the field list)
# ---------------------------------------------------------------------------
vault_import_registry() {
  local jsonl="$1"
  [[ -f "$jsonl" ]] || { echo "vault: ABORT — registry not found: $jsonl" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "vault: ABORT — jq is required for --from-registry" >&2; return 1; }
  local imported=0 conflicts=0 skipped_public=0 non_string_git=0
  local line name pfad rid git_type git_val acct repo tok
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    rid="$(printf '%s' "$line" | jq -r '.id // empty')"
    [[ -z "$rid" ]] && continue
    name="$(printf '%s' "$line" | jq -r '.name // empty')"
    pfad="$(printf '%s' "$line" | jq -r '.pfad // empty')"
    if [[ -n "$name" ]]; then
      tok="$(vault_default_token project "$rid")"
      _vault_add_and_tally project "$name" "$tok" "$rid"
    fi
    if [[ -n "$pfad" ]]; then
      tok="$(vault_default_token path "$rid")"
      _vault_add_and_tally path "$pfad" "$tok" "$rid"
    fi
    git_type="$(printf '%s' "$line" | jq -r '.git | type')"
    if [[ "$git_type" == "string" ]]; then
      git_val="$(printf '%s' "$line" | jq -r '.git')"
      acct=""; repo=""
      if [[ "$git_val" =~ ^git@[^:]+:([^/]+)/(.+)\.git$ ]]; then
        acct="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
      elif [[ "$git_val" =~ ^https?://[^/]+/([^/]+)/([^/.]+)(\.git)?/?$ ]]; then
        acct="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
      fi
      if [[ -n "$acct" ]]; then
        tok="$(vault_default_token account "$acct")"
        _vault_add_and_tally account "$acct" "$tok" "$acct"
      fi
      if [[ -n "$repo" && "$repo" != "$name" ]]; then
        tok="$(vault_default_token project "$rid")"
        _vault_add_and_tally project "$repo" "$tok" "$rid"
      fi
    else
      non_string_git=$((non_string_git+1))
    fi
  done < "$jsonl"
  echo "vault: import-registry — ${imported} row(s) imported, ${conflicts} conflict(s), ${skipped_public} skipped (public framework identity, §7.1), ${non_string_git} entr(y/ies) with non-string 'git' field (this registry's 'git' field is a boolean, not a remote URL — account/repo-alias extraction skipped for those, deviation from the original plan text, see handback report)" >&2
}

# ---------------------------------------------------------------------------
# The matcher core (perl — ships on stock macOS). ONE script, mode-switched,
# used by check/tokenize/resolve alike (rules/testing-quality.md).
# ---------------------------------------------------------------------------
_vault_write_matcher_pl() {
  cat > "$1" <<'PERLEOF'
use strict; use warnings;
use Encode qw(decode encode FB_CROAK);
use Unicode::Normalize qw(NFC NFD);

my $mode       = $ENV{VAULT_MODE} or die "VAULT_MODE required\n";
my $file       = $ENV{VAULT_CURRENT_FILE} // '-';
my $structural = ($ENV{VAULT_STRUCTURAL} // '0') eq '1';
my $dryrun     = ($ENV{VAULT_DRYRUN} // '0') eq '1';
my $rules_path = $ENV{VAULT_RULES} // '';
my $allow_path = $ENV{VAULT_ALLOWLIST} // '';

# Zero-width / soft-break characters that must be IGNORED when they sit
# BETWEEN the letters of a vault term (2026-09-25 Unicode hardening,
# plans/vault-by-design-2026-09-25.md): a reader who inserts one of these
# mid-word defeats a naive literal match while the rendered text still
# reads as the real term. Listed as UTF-8 BYTE sequences (not \x{...}
# codepoint escapes) because this whole matcher works at the BYTE level
# throughout (no `use utf8` anywhere in this file) — see fuzzy_term_pattern
# below for why matching stays byte-level rather than decoding every input
# line.
my $invisible_bytes_alt = join('|', map { quotemeta(encode('UTF-8', chr($_))) }
  (0x200B, 0x200C, 0x200D, 0xFEFF, 0x00AD));
my $invisible_run = '(?:' . $invisible_bytes_alt . ')*';

# fuzzy_term_pattern <term_bytes> — a BYTE-level regex-pattern STRING that
# matches <term_bytes> either exactly as stored, or with any per-character
# substitution between its NFC-composed and NFD-decomposed forms (an
# umlaut written as one precomposed codepoint vs. base+combining-mark), and
# tolerates a run of the invisible characters above BETWEEN any two
# adjacent term characters (never before the first or after the last — the
# reported evasion is a character INSERTED INSIDE a term, not padding
# around it; allowing it at the edges would risk a match reaching into
# unrelated neighboring text).
#
# Decoding happens ONLY here, ONCE per rule at rules-file load time (see
# the @rules loading loop below) — never on the input line itself. This
# means: (a) a non-UTF-8 input file can never make the check crash — there
# is nothing to decode on that side, matching stays purely byte-level as
# before; (b) the O(lines) cost of this matcher is unchanged by the
# hardening, since the per-character NFC/NFD alternation work happens
# O(rules) times total (at load time), not O(rules * lines) (measured:
# 222 real-vault-shaped terms build all their patterns in ~16ms — see
# handback report).
#
# If the STORED TERM itself is not valid UTF-8 (should not happen — vault
# terms are added as ordinary shell arguments — but defended anyway), fall
# back to a plain literal byte match for that one rule rather than dying.
# This narrow fallback is reported to STDERR (fail-loud.md: a graceful
# degradation must be observable, not silent) — WITHOUT the term itself,
# consistent with this whole file never printing a stored term outside a
# genuine match report.
#
# Returns a 2-element list: (fuzzy_pattern_string, nfc_bytes). The second
# value is the term's own NFC-composed form, re-encoded to UTF-8 bytes —
# used ONLY as the needle for the compact_nfc_bytes() prefilter below, not
# for matching itself (2026-09-25 perf hardening round, see
# find_vault_matches's own comment for why a prefilter was added there).
sub fuzzy_term_pattern {
  my ($term_bytes) = @_;
  my $decoded = eval { decode('UTF-8', $term_bytes, FB_CROAK) };
  if (!defined $decoded) {
    warn "vault-matcher: WARNING — a vault term is not valid UTF-8; falling back to a plain literal match for that one rule (no NFC/NFD or invisible-character tolerance for it)\n";
    return (quotemeta($term_bytes), $term_bytes);
  }
  my $nfc_term = NFC($decoded);
  my $nfc_bytes = encode('UTF-8', $nfc_term);
  my @alts;
  for my $c (split //, $nfc_term) {
    my $nfc_c = encode('UTF-8', $c);
    my $nfd_c = encode('UTF-8', NFD($c));
    push @alts, ($nfc_c eq $nfd_c)
      ? quotemeta($nfc_c)
      : '(?:' . quotemeta($nfc_c) . '|' . quotemeta($nfd_c) . ')';
  }
  return (join($invisible_run, @alts), $nfc_bytes);
}

# compact_nfc_bytes <line_bytes> — NFC-normalizes the line and strips the
# same 5 invisible characters $invisible_run tolerates, re-encoded to
# UTF-8 bytes. ONLY used as a cheap index()-prefilter TARGET on the
# non-ASCII (fuzzy) path in find_vault_matches — never for reporting a
# span or rewriting output; the real match (with exact original-byte
# offsets) still runs against the UNMODIFIED line via the fuzzy regex, so
# an approximate mapping here costs nothing in correctness. Sound as a
# prefilter because: whatever the fuzzy regex would match in the original
# line becomes, after this SAME transform (compose to NFC, drop the
# tolerated invisible characters), exactly the term's own NFC bytes as a
# contiguous substring — so "term's NFC bytes absent from the compact
# line" PROVES "the fuzzy regex cannot match", which is all a prefilter
# needs (a false negative here would be a correctness bug — there isn't
# one; a false positive only costs one wasted, but still correct, regex
# attempt). Returns undef when the line itself is not valid UTF-8 (rare —
# already established the line has a byte >= 0x80, but that byte sequence
# need not be well-formed UTF-8); callers MUST treat undef as "prefilter
# unavailable, run the real regex unconditionally", never as "no match".
sub compact_nfc_bytes {
  my ($line_bytes) = @_;
  my $decoded = eval { decode('UTF-8', $line_bytes, FB_CROAK) };
  return undef if !defined $decoded;
  my $nfc = NFC($decoded);
  $nfc =~ s/[\x{200B}\x{200C}\x{200D}\x{FEFF}\x{00AD}]//g;
  return encode('UTF-8', $nfc);
}

my @rules;
if ($rules_path && -f $rules_path) {
  open(my $rh, '<', $rules_path) or die "vault-matcher: cannot open rules: $!\n";
  while (my $l = <$rh>) {
    chomp $l;
    next if $l eq '' || $l =~ /^#/;
    my ($kind, $term, $token, $group) = split(/\t/, $l, 4);
    next unless defined $term && length($term);
    # Fuzzy pattern, the lower-cased term, the term's NFC-bytes form, and
    # its lower-cased copy are ALL precomputed ONCE per rule HERE, not per
    # input line — find_vault_matches runs once PER INPUT LINE, and none
    # of these change across lines within one matcher invocation
    # (2026-09-25 perf hardening round: all four back the index()
    # prefilters in find_vault_matches — see its own comment).
    my ($fuzzy, $nfc_bytes) = fuzzy_term_pattern($term);
    push @rules, [$kind, $term, $token // '', $group // '', $fuzzy, lc($term), $nfc_bytes, lc($nfc_bytes)];
  }
  close $rh;
}

my @allow;
if ($allow_path && -f $allow_path) {
  open(my $ah, '<', $allow_path) or die "vault-matcher: cannot open allowlist: $!\n";
  while (my $l = <$ah>) {
    chomp $l;
    next if $l eq '' || $l =~ /^#/;
    my ($p, undef, $sig) = split(/:/, $l, 3);
    next unless defined $sig && length($sig);
    push @allow, [$p, $sig];
  }
  close $ah;
}

sub is_allowlisted {
  my ($f, $line_content) = @_;
  for my $a (@allow) {
    my ($p, $sig) = @$a;
    next unless $f eq $p;
    return 1 if index($line_content, $sig) >= 0;
  }
  return 0;
}

# NOTE: qr~...~ (not qr{...} and not qr!...!) is deliberate below. Perl
# scans a qr's own delimiter characters RAW (respecting backslash-escapes of
# the delimiter itself, but with no understanding of regex semantics like
# character classes) — a paired delimiter like {} is closed early by the
# first bare "}" inside a class such as [^}], and "!" is closed early by the
# "!" inside a negative lookahead "(?!...)". "~" appears nowhere in any of
# these patterns, so it is a safe, unambiguous delimiter throughout. Proven
# with a standalone `perl -e` before landing (see handback report).
# Placeholder segment (plans/vault-by-design-2026-09-25.md §7.3): both the
# bare form ($VAR, ${VAR}) and the backslash-escaped form (\$VAR, \${VAR})
# count — source code (shell heredocs, markdown showing shell snippets)
# routinely contains the escaped form literally, as raw text, and that text
# is exactly as much a placeholder as the unescaped one. "user" added
# (2026-09-25 rework round 5, finding #5a) — "/home/user/…", "/Users/user/…"
# are generic documentation placeholders, same class as "you"/"example".
my $ph = qr~(?:<[^>]*>|\\?\$\{[^}]*\}|\\?\$[A-Za-z_][A-Za-z0-9_]*|USERNAME|username|user|you|me|example|\.\.\.|\x{2026}|\*)~;
# A placeholder segment must be followed by "/", end-of-line, whitespace, or
# a sentence-/quote-closing character — not just "/" or end-of-line as
# before, which wrongly flagged forms like /Users/<user>", or /Users/$USER)
# (§7.3: the placeholder is still a placeholder when a trailing comma,
# quote, or bracket follows it in prose or source code).
my $ph_boundary = qr~(?:[/\s,.;:)\]}"'`]|$)~;
my @structural_patterns = (
  # The first character after the prefix must start a real segment
  # ([A-Za-z0-9_]) — otherwise a bare trailing prefix followed only by
  # punctuation (e.g. "/Users/," in prose, "/Users/." at a sentence end)
  # was matching as if it were a path (2026-09-25 rework round 3, finding
  # #7). The rest of the segment stays the permissive "any non-whitespace/
  # quote/paren" class, unchanged.
  ['path',  qr~(?:/Users/|/home/|/Volumes/)(?!$ph$ph_boundary)[A-Za-z0-9_][^\s"'`)]*~],
  # (?<!:) (round 5, finding #5b): a local-part immediately preceded by ":"
  # is URL userinfo syntax ("https://user:pass@host/...") — the ":pass"
  # portion is a credential placeholder, not an email mailbox. Verified
  # standalone before landing (see handback report) that a bare "user@host"
  # WITHOUT a preceding colon is unaffected.
  ['email', qr~(?<!:)\b[A-Za-z0-9._%+-]+\@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b~],
  # Generalized (round 5, finding #4 in scrub-check.sh's own migration): a
  # bare 32-hex-character blob, or the 8-4-4-4-12 dashed grouping with NO
  # version/variant constraint, catches ID shapes like a Notion page id
  # that are not necessarily valid UUIDv4 — on top of the still-present
  # UUIDv4-specific and notion.so-URL-specific alternatives (harmless
  # overlap: the overlap-claim logic in find_structural_matches already
  # dedupes any span two alternatives both match).
  ['id',    qr~\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b|\b[0-9A-Fa-f]{32}\b|session_[A-Za-z0-9]{24,}|trig_[A-Za-z0-9]{20,}|notion\.so/[^\s"'`]*[0-9a-f]{32}~],
);
my $tz_pattern = qr~(?:Europe|America|Asia|Africa|Australia|Pacific)/[A-Z][A-Za-z_]+~;

sub email_exempt {
  my ($m) = @_;
  return 1 if lc($m) eq 'noreply@anthropic.com';
  return 1 if $m =~ /\@example\.(?:com|org|net)$/i;
  return 1 if $m =~ /\@users\.noreply\.github\.com$/i;
  # git@<host> is the SSH remote-URL syntax (git@github.com:owner/repo.git),
  # not an email address (§7.4) — the local-part "git" here never denotes a
  # mailbox.
  return 1 if $m =~ /^git\@/i;
  # A match whose domain's LAST label is a common file extension is a
  # reference to a filename (e.g. some identifier immediately followed by
  # "@" and a script's filename, as prose sometimes writes it), not an
  # email — the email regex's own "[A-Za-z]{2,}" TLD requirement happens to
  # also accept these (2026-09-25 rework round 3, finding #4).
  return 1 if $m =~ /\.(?:sh|md|json|py|js|ts|tsx|jsx|yml|yaml|txt|log|toml|plist|lock|cfg|ini|conf)$/i;
  # Reserved test/documentation TLDs, RFC 2606 §2 + RFC 6761: .example,
  # .invalid, .test, .localhost are never real addresses, on top of the
  # example.com/org/net SECOND-LEVEL-domain form already exempted above
  # (2026-09-25 rework round 3, finding #5).
  return 1 if $m =~ /\.(?:example|invalid|test|localhost)$/i;
  return 0;
}

# email_spans_in <line> — every REAL (non-exempt) email-shaped span in the
# line, as [start, end] pairs. Used to widen a vault-term match that falls
# entirely inside one (see find_vault_matches below).
sub email_spans_in {
  my ($line) = @_;
  my ($email_kind, $email_pattern) = @{ (grep { $_->[0] eq 'email' } @structural_patterns)[0] };
  my @spans;
  while ($line =~ /$email_pattern/g) {
    my ($s, $e, $m) = ($-[0], $+[0], $&);
    next if email_exempt($m);
    push @spans, [$s, $e];
  }
  return @spans;
}

sub find_vault_matches {
  my ($line) = @_;
  my (@matches, @claimed);
  my @email_spans = email_spans_in($line);

  # Perf hardening (2026-09-25, follow-up to the Unicode hardening round):
  # a line with NO byte >= 0x80 cannot POSSIBLY contain an NFD-decomposed
  # character (every NFD decomposition of a term character that differs
  # from its NFC form is itself non-ASCII — a combining mark is never a
  # 7-bit byte) or one of the 5 invisible characters (all 5 are multi-byte
  # UTF-8 sequences whose lead byte is >= 0x80 too). So on an ASCII-only
  # line, the plain literal pattern (quotemeta($term), exactly what this
  # matcher used BEFORE the Unicode hardening) is PROVABLY equivalent to
  # the fuzzy pattern — there is nothing non-ASCII for the fuzzy
  # alternation to tolerate. Skipping the fuzzy pattern here restores the
  # original per-rule match cost for the ~93-94% of real-world lines that
  # are pure ASCII (measured on this repo's own ledger/CLAUDE.md), while
  # non-ASCII lines still get full NFC/NFD/invisible-character tolerance
  # via $fuzzy, unchanged.
  my $is_ascii_line = ($line !~ /[\x80-\xff]/);
  my $lc_line;             # lazily computed at most once per line
  my $compact_line;        # lazily computed at most once per NON-ASCII line
  my $compact_line_lc;
  my $compact_line_tried = 0;

  for my $r (@rules) {
    my ($kind, $term, $token, $group, $fuzzy, $term_lc, $nfc_bytes, $nfc_bytes_lc) = @$r;
    my $is_word_kind = ($kind eq 'project' || $kind eq 'account');

    # index()-prefilter (perf hardening): a plain byte-substring search is
    # orders of magnitude cheaper than compiling/running a regex, and is a
    # NECESSARY condition for either pattern below to match — if the
    # term's own literal bytes (case-folded for project/account, which
    # match case-insensitively; exact for every other kind) are nowhere in
    # the line, no regex attempt can succeed either, so skip immediately
    # without ever invoking the regex engine for this rule.
    if ($is_ascii_line) {
      # ASCII line: the term's OWN literal bytes are the exact necessary
      # condition (see the $is_ascii_line comment above for why the fuzzy
      # tolerance is provably irrelevant here).
      if ($is_word_kind) {
        $lc_line = lc($line) unless defined $lc_line;
        next if index($lc_line, $term_lc) == -1;
      } else {
        next if index($line, $term) == -1;
      }
    } else {
      # Non-ASCII line: check against the COMPACT (NFC-composed,
      # invisible-characters-stripped) copy of the line instead of the raw
      # line — see compact_nfc_bytes()'s own comment for why this is a
      # sound necessary condition for the fuzzy pattern. Computed at most
      # ONCE per line (not per rule); left undef (prefilter skipped
      # entirely, every rule falls through to the real regex) if the line
      # itself is not valid UTF-8.
      unless ($compact_line_tried) {
        $compact_line = compact_nfc_bytes($line);
        $compact_line_lc = defined $compact_line ? lc($compact_line) : undef;
        $compact_line_tried = 1;
      }
      if (defined $compact_line) {
        if ($is_word_kind) {
          next if index($compact_line_lc, $nfc_bytes_lc) == -1;
        } else {
          next if index($compact_line, $nfc_bytes) == -1;
        }
      }
    }

    my $pattern_src = $is_ascii_line ? quotemeta($term) : $fuzzy;
    my $pattern = $is_word_kind
      ? qr{(?<![[:alnum:]])$pattern_src(?![[:alnum:]])}i
      : qr{$pattern_src};
    while ($line =~ /$pattern/g) {
      my ($s, $e) = ($-[0], $+[0]);
      next if $s == $e;
      my $overlap = 0;
      for my $c (@claimed) { if ($s < $c->[1] && $e > $c->[0]) { $overlap = 1; last; } }
      next if $overlap;
      # Widen to the WHOLE email address when this term match sits inside
      # one (round 5, finding #5c): tokenizing just the inner term would
      # leave a NEW, still address-shaped string behind (e.g.
      # "contact@<token>.com") — check must report the address (kind
      # email), and tokenize must replace the address wholesale with the
      # same literal "<email>" vault_default_token's email kind already
      # uses, not a hash fragment glued into a leftover "@...".
      my ($fs, $fe, $fkind, $fterm, $ftoken) = ($s, $e, $kind, $term, $token);
      for my $es (@email_spans) {
        if ($es->[0] <= $s && $e <= $es->[1]) {
          ($fs, $fe) = @$es;
          $fkind = 'email';
          $fterm = substr($line, $fs, $fe - $fs);
          $ftoken = '<email>';
          last;
        }
      }
      my $overlap2 = 0;
      for my $c (@claimed) { if ($fs < $c->[1] && $fe > $c->[0]) { $overlap2 = 1; last; } }
      next if $overlap2;
      push @claimed, [$fs, $fe];
      push @matches, { start=>$fs, end=>$fe, kind=>$fkind, term=>$fterm, token=>$ftoken, group=>$group };
    }
  }
  return sort { $a->{start} <=> $b->{start} } @matches;
}

sub find_structural_matches {
  my ($line, @claimed_ranges) = @_;
  my @matches;
  for my $sp (@structural_patterns) {
    my ($kind, $pattern) = @$sp;
    while ($line =~ /$pattern/g) {
      my ($s, $e, $m) = ($-[0], $+[0], $&);
      next if $kind eq 'email' && email_exempt($m);
      my $overlap = 0;
      for my $c (@claimed_ranges) { if ($s < $c->[1] && $e > $c->[0]) { $overlap = 1; last; } }
      next if $overlap;
      push @matches, { start=>$s, end=>$e, kind=>$kind, term=>$m, token=>'' };
    }
  }
  return @matches;
}

# Buffer the whole input before processing (rather than a streaming
# while-(<STDIN>) loop) so the fixture-marker check below can look at the
# first 5 lines up front — the marker's effect applies to EVERY line,
# including lines 1-5 themselves, so it must be known before those lines
# are processed, not discovered only once the stream reaches them.
#
# EOF-newline preservation (2026-09-25 rework round 5, sink-verification
# finding #2): the previous version unconditionally `chomp`ed every line
# and printed "$out\n" for every output line, which meant a file with NO
# trailing newline on its last line got one silently ADDED by tokenize —
# ten files in the real publish sink verification changed for exactly this
# reason despite having zero actual replacements. Track whether the FINAL
# record read from STDIN ended in "\n" or not, and reproduce that exactly.
my @input_lines;
my $last_had_newline = 1;
while (my $line = <STDIN>) {
  if ($line =~ /\n\z/) {
    chomp $line;
    push @input_lines, $line;
    $last_had_newline = 1;
  } else {
    push @input_lines, $line;
    $last_had_newline = 0;
  }
}
my $total_lines = scalar(@input_lines);

# Fixture exemption (§3 exception b; narrowed 2026-09-25 rework round 3,
# finding #1): applies ONLY to files under */tests/* whose first 5 lines
# carry the literal marker, and even then ONLY to STRUCTURAL findings
# (kind path/email/id with NO vault token) — never to a real vault-term
# match. A vault term (non-empty token) found inside a fixture file is
# still reported: a fixture is for synthetic STRUCTURAL shapes (fake
# UUIDs, fake paths), not a license to smuggle in a real, tracked term
# "as an example" (exactly how a real project name once leaked into this
# suite's own word-boundary test). check mode only — tokenize/resolve
# never consulted this marker.
my $is_fixture = 0;
if ($mode eq 'check' && $file =~ m{/tests/}) {
  for my $i (0 .. 4) {
    last if $i > $#input_lines;
    if ($input_lines[$i] =~ /vault-check: fixtures \(.+\)/) { $is_fixture = 1; last; }
  }
}

# emit_line <text> <is_last_line> — prints with a trailing "\n" UNLESS this
# is the final line AND the original input's final line had none (EOF-
# newline preservation, see the input-buffering comment above).
sub emit_line {
  my ($text, $is_last) = @_;
  if ($is_last && !$last_had_newline) {
    print $text;
  } else {
    print "$text\n";
  }
}

my $found = 0;
my $lineno = 0;
for my $raw (@input_lines) {
  $lineno++;
  my $is_last_line = ($lineno == $total_lines);

  if ($mode eq 'check') {
    my @vmatches = find_vault_matches($raw);
    my @claimed = map { [$_->{start}, $_->{end}] } @vmatches;
    my @smatches = $structural ? find_structural_matches($raw, @claimed) : ();
    for my $m (@vmatches, @smatches) {
      next if is_allowlisted($file, $raw);
      next if $is_fixture && $m->{token} eq '';
      print join("\t", $file, $lineno, $m->{kind}, $m->{term}, $m->{token}), "\n";
      $found = 1;
    }
    if ($structural && $raw =~ /$tz_pattern/) {
      print STDERR "vault: WARNING — $file:$lineno: IANA timezone literal ($&) — informational only, not blocked\n";
    }
    next;
  }

  if ($mode eq 'tokenize') {
    # Allowlist consultation (2026-09-25 rework round 5, finding #1): check
    # already skipped a REPORT on an allowlisted line via is_allowlisted
    # above, but tokenize never consulted it at all — an allowlisted
    # attribution line (LICENSE:3, README.md:238) still got REWRITTEN by
    # tokenize even though check would never have flagged it, which is
    # exactly backwards for a WRITE tool. Same function as check
    # (rules/testing-quality.md "same code path"), no second mechanism: an
    # allowlisted line gets treated as if it had zero vault matches.
    my $line_allowlisted = is_allowlisted($file, $raw);
    my @vmatches = $line_allowlisted ? () : find_vault_matches($raw);
    if ($dryrun) {
      for my $m (@vmatches) {
        print join(':', $file, $lineno, $m->{kind}, $m->{token}), "\n";
      }
      next;
    }
    my $out = '';
    my $pos = 0;
    for my $m (@vmatches) {
      my $prefix_len = $m->{start} - $pos;
      # kind=user, home-directory-prefixed form: tokenizes to "~", replacing
      # the WHOLE "prefix+term" span — not just appending "~" after a
      # still-copied prefix (§2 token-derivation table: "~" when the term
      # follows the OS home-directory prefix, else the stored token).
      my $is_users_prefixed = $m->{kind} eq 'user' && $prefix_len >= 7
        && substr($raw, $m->{start} - 7, 7) eq '/Users/';
      if ($is_users_prefixed) {
        $out .= substr($raw, $pos, $prefix_len - 7);
        $out .= '~';
      } else {
        $out .= substr($raw, $pos, $prefix_len);
        $out .= $m->{token};
      }
      $pos = $m->{end};
    }
    $out .= substr($raw, $pos);
    emit_line($out, $is_last_line);
    next;
  }

  if ($mode eq 'resolve') {
    my $out = $raw;
    # token -> term, longest token first, first-seen-in-rules wins per token.
    my %seen; my @tok_term;
    for my $r (@rules) {
      my ($kind, $term, $token, $group) = @$r;
      next unless length($token);
      next if $seen{$token}++;
      push @tok_term, [$token, $term];
    }
    @tok_term = sort { length($b->[0]) <=> length($a->[0]) } @tok_term;
    for my $tt (@tok_term) {
      my ($token, $term) = @$tt;
      my $qtok = quotemeta($token);
      $out =~ s/$qtok/$term/g;
    }
    emit_line($out, $is_last_line);
    next;
  }

  die "vault-matcher: unknown VAULT_MODE '$mode'\n";
}

exit(($mode eq 'check' && $found) ? 2 : 0);
PERLEOF
}

# vault_matcher_run <mode> <structural:0|1> <file_label> <rules_file_or_empty> <allowlist_or_empty> [dryrun:0|1]
# Reads stdin, writes stdout (tokenize/resolve: transformed text, or — with
# dryrun=1 — a "file:line:kind:token" listing; check: finding rows).
# Returns perl's exit code (0 clean/no findings, 2 = check found something).
# "use vault or not" is expressed by passing an empty rules file, not by a
# separate flag — no vault rules means no vault matches.
vault_matcher_run() {
  local mode="$1" structural="$2" file_label="$3" rules="$4" allowlist="$5" dryrun="${6:-0}"
  # BSD/macOS mktemp only substitutes a trailing run of X's — a template
  # with a static suffix AFTER the X's (e.g. "....XXXXXX.pl") is returned
  # UNCHANGED (literal, unsubstituted), so every call would race on the
  # same filename. Keep the X's at the very end; perl does not care about
  # the file's extension when invoked as `perl "$file"`.
  local pl; pl="$(mktemp "${TMPDIR:-/tmp}/vault-matcher.XXXXXX")"
  _vault_write_matcher_pl "$pl"
  local rc
  VAULT_MODE="$mode" VAULT_CURRENT_FILE="$file_label" VAULT_STRUCTURAL="$structural" \
    VAULT_DRYRUN="$dryrun" VAULT_RULES="$rules" VAULT_ALLOWLIST="$allowlist" perl "$pl"
  rc=$?
  rm -f "$pl"
  return "$rc"
}

