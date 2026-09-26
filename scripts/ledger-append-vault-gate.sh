#!/bin/bash
# ledger-append-vault-gate.sh — pseudonymization gate for ledger-append-proposed.sh.
# ─────────────────────────────────────────────────────────────────────────────
# IMP-219 (2026-09-25, Welle 2 / Gewerk C). Every text field of every ledger
# entry ledger-append-proposed.sh is about to write (title, category,
# riskLevel, notes/recommendation, evidence, source) is first run through
# `scripts/vault/vault.sh tokenize` (only when a vault exists at
# ~/.claude/vault — see vault_require in scripts/vault/lib.sh) and then
# through `vault.sh check --structural-only --stdin`, which needs NO vault
# and always runs (structural patterns — /Users/, emails, UUIDs, session/
# trigger/notion ids — apply on every machine, per
# plans/vault-by-design-2026-09-25.md §3). A structural finding remaining in
# ANY field of ANY entry blocks the WHOLE batch: nothing is written, matching
# ledger-append-proposed.sh's existing "validation failed -> NOTHING written"
# contract (not even the other, clean entries of the same run).
#
# `sourceProposal` (the idempotency dedup key, "<proposal-basename>#<finding
# id>") — REVISED in Welle 3 (2026-09-25, §7-Nachtrag point 2): the caller
# (ledger-append-proposed.sh) now gates the PROPOSAL-BASENAME half through
# this exact same lvg_gate_value primitive, ONCE, at script start, before
# building the dedup lookup — see that script's header for the full
# rationale (dedup still matches a re-run, because tokenization is a pure,
# deterministic function of the secret + basename on this machine, and
# Gewerk W3-L tokenizes the ledger's EXISTING sourceProposal keys the same
# way in the same wave). This was previously left deliberately UNCHANGED
# (see git history for the original round-2 rationale) because tokenizing
# it risked breaking dedup against an untokenized existing ledger — that
# risk is now retired by W3-L's parallel rewrite.
#
# The FINDING-ID half of sourceProposal (the part after "#") — REVISED AGAIN
# in Welle 4 (2026-09-25, security-review finding M1): a caller-supplied
# finding id used to reach the ledger with only a non-empty check (any text
# at all) and a non-blocking, non-tokenizing "advisory" structural scan that
# counted but never stopped a hit. That let a caller pass free text —
# including a real path/email/session-id, or a registered vault term — as
# ".finding" and have it land, byte-for-byte, in the versioned ledger. Fixed
# in two layers, neither of which lives in this file alone:
#   1. ledger-append-proposed.sh's OWN stdin validation now rejects any
#      entry whose ".finding" is not a short, safe-charset id
#      (^[A-Za-z0-9._-]{1,64}$, e.g. "F-001") BEFORE dedup/entry-building
#      even starts — closing the free-text/structural-pattern risk (no "/",
#      "@", or whitespace can ever reach this file via that field).
#   2. THIS file's lvg_check_source_proposal (below) replaces
#      lvg_advisory_scan_source_proposal: a BLOCKING (never tokenizing) FULL
#      `vault.sh check` (vault-term matching + structural — no
#      --structural-only) on the fully assembled sourceProposal
#      ("<already-tokenized-proposal-basename>#<finding-id>"), closing the
#      remaining risk that a charset-safe finding id nonetheless COINCIDES
#      with a real registered vault term (a project/account name can itself
#      be a bare alnum word — Case 1's "SynthCorpAlpha" fixture is exactly
#      that shape). A hit in either half of the assembled string raises
#      LVG_BLOCKED, same batch-wide convention as every other field below —
#      it is reported by KIND ONLY, referencing the entry's OWN freshly
#      assigned ledger id, never the caller-supplied finding text itself
#      (which, having just matched, is precisely the value this gate exists
#      to keep out of any observable output).
#
# This file is SOURCED by scripts/ledger-append-proposed.sh only — it is not
# standalone and does not set its own `set -e` (the caller already has one;
# see rules/testing-quality.md style already used by scripts/vault/lib.sh).
# bash 3.2 (stock macOS): no mapfile, no associative arrays, no ${var,,}.
# ─────────────────────────────────────────────────────────────────────────────

LVG_BLOCKED=0
LVG_WARNED=0

# lvg_init <script_dir> — locates vault.sh RELATIVE TO THE CALLER's own
# location (never a hardcoded absolute path — Bauhof/Haus portability, same
# convention vault.sh itself uses for lib.sh).
lvg_init() {
  LVG_VAULT_SH="$1/vault/vault.sh"
  if [[ ! -f "$LVG_VAULT_SH" ]]; then
    echo "[ledger-append-proposed] FATAL: vault.sh not found at $LVG_VAULT_SH — the pseudonymization gate is required, not optional (plans/vault-by-design-2026-09-25.md)" >&2
    return 1
  fi
  return 0
}

# lvg_gate_value <finding_id> <field_label> <value> — sets LVG_OUT to the
# value to use (tokenized when a vault exists; unchanged otherwise — a
# missing vault is fail-loud, not fail-closed, per vault.sh's own contract).
# Prints BLOCKED/WARNING/FATAL lines to stderr; NEVER prints the real value.
# Returns: 0 clean, 2 structural finding recorded (LVG_BLOCKED also set),
# 3 vault.sh check itself errored unexpectedly (caller must abort).
lvg_gate_value() {
  local fid="$1" field="$2" value="$3" out rc findings kinds
  if [[ -z "$value" ]]; then
    LVG_OUT=""
    return 0
  fi
  set +e
  out="$(printf '%s' "$value" | "$LVG_VAULT_SH" tokenize 2>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    out="$value"
    if [[ "$LVG_WARNED" -eq 0 ]]; then
      echo "[ledger-append-proposed] WARNING — no vault present; tokenization skipped this run, structural check stays mandatory (run: scripts/vault/vault.sh init)" >&2
      LVG_WARNED=1
    fi
  fi
  set +e
  findings="$(printf '%s' "$out" | "$LVG_VAULT_SH" check --structural-only --stdin 2>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 2 ]]; then
    kinds="$(printf '%s\n' "$findings" | awk -F'\t' '{print $3}' | sort -u | paste -sd, -)"
    echo "[ledger-append-proposed] BLOCKED — structural finding: finding=$fid field=$field kind=$kinds" >&2
    LVG_OUT="$out"
    return 2
  fi
  if [[ "$rc" -ne 0 ]]; then
    echo "[ledger-append-proposed] FATAL: vault.sh check failed unexpectedly (exit $rc) validating field '$field' of $fid" >&2
    LVG_OUT="$out"
    return 3
  fi
  LVG_OUT="$out"
  return 0
}

# lvg_gate_field <finding_id> <field_label> <value> — wraps lvg_gate_value so
# callers always get the value via $LVG_GATED and never branch on a raw exit
# code. A structural finding (rc=2) only raises LVG_BLOCKED and continues —
# so every offending field across the whole run gets reported before the
# caller aborts. Only a genuine infra error (rc=3) returns non-zero here.
lvg_gate_field() {
  local fid="$1" field="$2" value="$3" rc=0
  lvg_gate_value "$fid" "$field" "$value" || rc=$?
  case "$rc" in
    0) ;;
    2) LVG_BLOCKED=1 ;;
    *)
      echo "[ledger-append-proposed] FATAL: aborting — vault gate infra error on field '$field' of $fid" >&2
      return 1
      ;;
  esac
  LVG_GATED="$LVG_OUT"
  return 0
}

# lvg_check_source_proposal <entry_id> <sourceProposal_value> — BLOCKING,
# non-tokenizing FULL check (vault-term matching + structural — no
# --structural-only) on the FULLY ASSEMBLED sourceProposal dedup key
# ("<already-tokenized-proposal-basename>#<finding-id>"). Replaces the old
# lvg_advisory_scan_source_proposal (Welle 4, IMP-219 finding M1 — see file
# header). Deliberately NEVER tokenizes/rewrites the value it's given — the
# dedup key must stay byte-stable across a re-run of the same proposal (file
# header, and Case 9b in the regression suite is the proof) — a hit means
# "refuse to write", never "silently substitute a token and proceed".
#
# Full (not structural-only) is intentional: the finding-id half, though
# already constrained by the CALLER's own charset/length gate
# (ledger-append-proposed.sh: ^[A-Za-z0-9._-]{1,64}$, enforced before this
# function ever runs) can still COINCIDE with a real registered vault term —
# a project/account name can itself be a bare alnum word (Case 1's
# "SynthCorpAlpha" fixture). The charset gate already closed the free-text/
# structural-pattern route (no "/", "@", whitespace); this closes the
# remaining vault-term route.
#
# On a hit (rc=2), raises LVG_BLOCKED and returns 0 — batch-wide reporting,
# same convention as lvg_gate_field, so every offending entry in the run is
# still surfaced before the caller aborts (checked once, after all entries).
# The BLOCKED line names the entry by its OWN freshly assigned ledger id
# (safe: sequential, content-free) and the finding KIND ONLY — never the
# caller-supplied finding text, which is exactly the value that just
# matched and is therefore precisely what must not be echoed back.
#
# Returns 1 ONLY on a genuine vault.sh infra error (mirrors lvg_gate_field's
# own rc=3 handling) — the caller must treat that as fatal, not batched.
lvg_check_source_proposal() {
  local entry_id="$1" value="$2" rc findings kinds
  [[ -n "$value" ]] || return 0
  set +e
  findings="$(printf '%s' "$value" | "$LVG_VAULT_SH" check --stdin 2>/dev/null)"
  rc=$?
  set -e
  case "$rc" in
    0) return 0 ;;
    2)
      kinds="$(printf '%s\n' "$findings" | awk -F'\t' '{print $3}' | sort -u | paste -sd, -)"
      echo "[ledger-append-proposed] BLOCKED — structural finding: entry=$entry_id field=sourceProposal kind=$kinds" >&2
      LVG_BLOCKED=1
      return 0
      ;;
    *)
      echo "[ledger-append-proposed] FATAL: aborting — vault gate infra error while full-checking sourceProposal of entry=$entry_id" >&2
      return 1
      ;;
  esac
}

# lvg_gate_entries_file <in_json_array_file> <out_json_array_file> — the
# entrypoint. Rewrites title/category/riskLevel/notes/evidence/source with
# their gated values on every entry of the input JSON array; leaves
# id/status/proposedAt/implementedAt/sourceProposal/verification untouched,
# and strips the scratch `_findingId` field the caller adds only for error
# reporting here. Sets LVG_BLOCKED as a side effect (also via
# lvg_check_source_proposal — see there for the sourceProposal full check).
# Returns 1 only on an infra error (see lvg_gate_field) — the caller must
# treat that as fatal; a structural finding alone still returns 0 (the
# caller checks LVG_BLOCKED separately, once, after all entries are done).
lvg_gate_entries_file() {
  local in_file="$1" out_file="$2"
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/ledger-gate.XXXXXX")"
  : > "$tmp"
  local entry fid entry_id title category riskLevel notes evidence source_txt src_proposal
  local g_title g_category g_riskLevel g_notes g_evidence g_source
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    fid="$(printf '%s' "$entry" | jq -r '._findingId // "?"')"
    entry_id="$(printf '%s' "$entry" | jq -r '.id // "?"')"
    src_proposal="$(printf '%s' "$entry" | jq -r '.sourceProposal // ""')"
    title="$(printf '%s' "$entry" | jq -r '.title // ""')"
    category="$(printf '%s' "$entry" | jq -r '.category // ""')"
    riskLevel="$(printf '%s' "$entry" | jq -r '.riskLevel // ""')"
    notes="$(printf '%s' "$entry" | jq -r '.notes // ""')"
    evidence="$(printf '%s' "$entry" | jq -r '.evidence // ""')"
    source_txt="$(printf '%s' "$entry" | jq -r '.source // ""')"

    lvg_gate_field "$fid" title "$title" || return 1
    g_title="$LVG_GATED"
    lvg_gate_field "$fid" category "$category" || return 1
    g_category="$LVG_GATED"
    lvg_gate_field "$fid" riskLevel "$riskLevel" || return 1
    g_riskLevel="$LVG_GATED"
    lvg_gate_field "$fid" recommendation "$notes" || return 1
    g_notes="$LVG_GATED"
    lvg_gate_field "$fid" evidence "$evidence" || return 1
    g_evidence="$LVG_GATED"
    lvg_gate_field "$fid" source "$source_txt" || return 1
    g_source="$LVG_GATED"

    lvg_check_source_proposal "$entry_id" "$src_proposal" || return 1

    printf '%s' "$entry" | jq -c \
      --arg title "$g_title" --arg category "$g_category" --arg riskLevel "$g_riskLevel" \
      --arg notes "$g_notes" --arg evidence "$g_evidence" --arg source "$g_source" \
      'del(._findingId) | .title=$title | .category=$category | .riskLevel=$riskLevel | .notes=$notes | .evidence=$evidence | .source=$source' \
      >> "$tmp"
  done < <(jq -c '.[]' "$in_file")
  jq -s '.' "$tmp" > "$out_file"
  rm -f "$tmp"
  return 0
}
