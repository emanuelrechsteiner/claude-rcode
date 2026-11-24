#!/usr/bin/env bash
# publish-strip-regression.sh — regression suite for the private-layer
# neutralization in the publish chain (defect sweep 2026-11-06).
#
# Pins three properties:
#   A. Overlay prose is absent from scripts/publish.sh and rcode/README.md
#      (docs/adr/0003-vault-and-gate.md: references to the private layer are
#      removed, not tokenized).
#   B. Transform 70 (publish-transforms.d/70-neutralize-private-layer-prose.sh)
#      normalizes a committed PUBLISH_DISABLED=0 to =1 in the staging copy,
#      unconditionally, not only inside the branch its German-marker gate can
#      skip.
#   C. Transform 70 gates both staged targets on `vault.sh check --stdin --as`
#      and fails closed: a finding aborts, a crash aborts, a missing vault or
#      missing tooling aborts. Only a clean check passes.
#
# Sections B and C run the REAL transform file, copied into a scratch fake
# repo (publish-transforms.d/ + scripts/vault/ stubs). The transform derives
# its REPO_ROOT from its own location, exactly as in production, so the stub
# vault tooling is resolved through the same path code — no environment
# override exists. Staging trees are `git archive HEAD` with the working-tree
# copies of the files under test overlaid.
#
# Usage: bash scripts/tests/publish-strip-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
T70_SRC="$REPO_ROOT/publish-transforms.d/70-neutralize-private-layer-prose.sh"
T70_NAME="70-neutralize-private-layer-prose.sh"

# Private-layer terms, split so this file never contains them contiguously
# (same technique as transform 70 itself).
PRIV_A="mirror""-layer"
PRIV_B="local""\\.md"
PRIV_C="_mir""ror"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; echo "       $2"; }

for req in "$T70_SRC" "$REPO_ROOT/scripts/publish.sh" "$REPO_ROOT/rcode/README.md"; do
  [[ -f "$req" ]] || { echo "ERROR: required file not found: $req" >&2; exit 1; }
done
command -v perl >/dev/null 2>&1 || { echo "ERROR: perl is required" >&2; exit 1; }
command -v git  >/dev/null 2>&1 || { echo "ERROR: git is required" >&2; exit 1; }

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/publish-strip-regr.XXXXXX")"
[[ -n "$SCRATCH" && -d "$SCRATCH" ]] || { echo "FATAL: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$SCRATCH"' EXIT

# make_staging <dest> — HEAD archive (never .git), then the working-tree
# copies of the two files under test, so the suite sees the edits in progress.
make_staging() {
  mkdir -p "$1"
  ( cd "$REPO_ROOT" && git archive HEAD ) | tar -x -C "$1"
  cp "$REPO_ROOT/scripts/publish.sh" "$1/scripts/publish.sh"
  cp "$REPO_ROOT/rcode/README.md" "$1/rcode/README.md"
}

# make_fake <dir> <mode> — fake repo holding a copy of transform 70 plus vault
# stubs. Modes: clean | finding | finding-readme | crash | absent | nosh.
#   clean          lib: vault present; vault.sh exits 0 for every target
#   finding        vault.sh exits 2 (findings) for every target
#   finding-readme vault.sh exits 2 only for rcode/README.md
#   crash          vault.sh exits 1 (infrastructure error)
#   absent         lib: vault_exists false (no vault on this machine)
#   nosh           no vault.sh file at all
# Every stub call appends its argument list to <dir>/vault-calls.log.
make_fake() {
  local d="$1" mode="$2"
  mkdir -p "$d/publish-transforms.d" "$d/scripts/vault"
  cp "$T70_SRC" "$d/publish-transforms.d/$T70_NAME"
  if [[ "$mode" == "absent" ]]; then
    printf 'vault_dir() { printf %%s /stub/vault; }\nvault_exists() { return 1; }\n' > "$d/scripts/vault/lib.sh"
  else
    printf 'vault_dir() { printf %%s /stub/vault; }\nvault_exists() { return 0; }\n' > "$d/scripts/vault/lib.sh"
  fi
  [[ "$mode" == "nosh" ]] && return 0
  {
    echo '#!/usr/bin/env bash'
    echo 'LOG="$(cd "$(dirname "$0")/../.." && pwd)/vault-calls.log"'
    echo 'echo "$*" >> "$LOG"'
    echo 'cat >/dev/null'
    echo "case \"$mode\" in"
    echo '  finding) echo "stub: finding" >&2; exit 2 ;;'
    echo '  finding-readme) if [[ "${4:-}" == "rcode/README.md" ]]; then echo "stub: finding" >&2; exit 2; fi; exit 0 ;;'
    echo '  crash) echo "stub: vault exploded" >&2; exit 1 ;;'
    echo '  *) exit 0 ;;'
    echo 'esac'
  } > "$d/scripts/vault/vault.sh"
}

# run_t70 <transform> <staging> — sets T70_RC and T70_OUT (stdout+stderr).
run_t70() {
  T70_OUT="$(bash "$1" "$2" 2>&1)"
  T70_RC=$?
}

# ---------------------------------------------------------------------------
echo "-- A. overlay prose removed from publish.sh and rcode/README.md (ADR 0003) --"
for f in scripts/publish.sh rcode/README.md; do
  hits="$(grep -nE -e "$PRIV_A" -e "$PRIV_B" -e "$PRIV_C" "$REPO_ROOT/$f" || true)"
  if [[ -z "$hits" ]]; then
    ok "A: no private-layer prose in $f"
  else
    bad "A: no private-layer prose in $f" "remaining hits: $hits"
  fi
done

if bash -n "$REPO_ROOT/scripts/publish.sh" 2>/dev/null \
   && grep -qxF 'PUBLISH_DISABLED=1' "$REPO_ROOT/scripts/publish.sh"; then
  ok "A: publish.sh is valid bash and still hard-disabled (PUBLISH_DISABLED=1)"
else
  bad "A: publish.sh is valid bash and still hard-disabled" \
      "bash -n failed or the PUBLISH_DISABLED=1 line is missing"
fi

# ---------------------------------------------------------------------------
echo "-- B. committed PUBLISH_DISABLED=0 is forced to 1 in the public copy --"
F="$SCRATCH/fake-b"
make_fake "$F" clean
S="$SCRATCH/b-release"
make_staging "$S"
perl -pi -e 's/^PUBLISH_DISABLED=1\b/PUBLISH_DISABLED=0/' "$S/scripts/publish.sh"
if [[ "$(grep -c '^PUBLISH_DISABLED=0$' "$S/scripts/publish.sh")" -ne 1 ]]; then
  bad "B: setup — scratch copy has PUBLISH_DISABLED=0" "perl did not set the line"
fi
run_t70 "$F/publish-transforms.d/$T70_NAME" "$S"
line="$(grep '^PUBLISH_DISABLED=' "$S/scripts/publish.sh" || true)"
if [[ "$T70_RC" -eq 0 && "$line" == "PUBLISH_DISABLED=1" ]]; then
  ok "B: =0 in staging is normalized to PUBLISH_DISABLED=1 (transform rc=0)"
else
  bad "B: =0 in staging is normalized to PUBLISH_DISABLED=1" \
      "transform rc=$T70_RC, staging line is '$line' — output: $T70_OUT"
fi

S="$SCRATCH/b-control"
make_staging "$S"
run_t70 "$F/publish-transforms.d/$T70_NAME" "$S"
line="$(grep '^PUBLISH_DISABLED=' "$S/scripts/publish.sh" || true)"
if [[ "$T70_RC" -eq 0 && "$line" == "PUBLISH_DISABLED=1" ]]; then
  ok "B-control: already-disabled tree passes transform 70 unchanged (rc=0)"
else
  bad "B-control: already-disabled tree passes transform 70 unchanged" \
      "rc=$T70_RC line='$line' output: $T70_OUT"
fi

# ---------------------------------------------------------------------------
echo "-- C. transform 70 gates both targets on vault.sh check (fail closed) --"

F="$SCRATCH/fake-c-finding"
make_fake "$F" finding
S="$SCRATCH/c-finding"
make_staging "$S"
run_t70 "$F/publish-transforms.d/$T70_NAME" "$S"
if [[ "$T70_RC" -ne 0 ]] && grep -q 'FAIL' <<<"$T70_OUT" && grep -q 'scripts/publish.sh' <<<"$T70_OUT"; then
  ok "C: a vault finding on scripts/publish.sh aborts transform 70 and names the file"
else
  bad "C: a vault finding on scripts/publish.sh aborts transform 70 and names the file" \
      "rc=$T70_RC output: $T70_OUT"
fi

F="$SCRATCH/fake-c-readme"
make_fake "$F" finding-readme
S="$SCRATCH/c-readme"
make_staging "$S"
run_t70 "$F/publish-transforms.d/$T70_NAME" "$S"
if [[ "$T70_RC" -ne 0 ]] && grep -q 'FAIL' <<<"$T70_OUT" && grep -q 'rcode/README.md' <<<"$T70_OUT"; then
  ok "C: a vault finding in rcode/README.md aborts transform 70 and names the file"
else
  bad "C: a vault finding in rcode/README.md aborts transform 70 and names the file" \
      "rc=$T70_RC output: $T70_OUT"
fi

F="$SCRATCH/fake-c-crash"
make_fake "$F" crash
S="$SCRATCH/c-crash"
make_staging "$S"
run_t70 "$F/publish-transforms.d/$T70_NAME" "$S"
if [[ "$T70_RC" -ne 0 ]] && grep -q 'infrastructure error' <<<"$T70_OUT"; then
  ok "C: a vault crash (exit 1) aborts transform 70 as an infrastructure error"
else
  bad "C: a vault crash (exit 1) aborts transform 70 as an infrastructure error" \
      "rc=$T70_RC output: $T70_OUT"
fi

F="$SCRATCH/fake-c-absent"
make_fake "$F" absent
S="$SCRATCH/c-absent"
make_staging "$S"
run_t70 "$F/publish-transforms.d/$T70_NAME" "$S"
if [[ "$T70_RC" -ne 0 ]] && grep -q 'needs the vault' <<<"$T70_OUT"; then
  ok "C: an absent vault aborts transform 70 with a message that the check needs the vault"
else
  bad "C: an absent vault aborts transform 70 with a message that the check needs the vault" \
      "rc=$T70_RC output: $T70_OUT"
fi

F="$SCRATCH/fake-c-nosh"
make_fake "$F" nosh
S="$SCRATCH/c-nosh"
make_staging "$S"
run_t70 "$F/publish-transforms.d/$T70_NAME" "$S"
if [[ "$T70_RC" -ne 0 ]] && grep -q 'vault tooling' <<<"$T70_OUT"; then
  ok "C: missing vault.sh aborts transform 70 (fail closed)"
else
  bad "C: missing vault.sh aborts transform 70 (fail closed)" "rc=$T70_RC output: $T70_OUT"
fi

F="$SCRATCH/fake-c-clean"
make_fake "$F" clean
S="$SCRATCH/c-clean"
make_staging "$S"
run_t70 "$F/publish-transforms.d/$T70_NAME" "$S"
calls="$(cat "$F/vault-calls.log" 2>/dev/null || true)"
if [[ "$T70_RC" -eq 0 ]] \
   && grep -qxF -- 'check --stdin --as scripts/publish.sh' <<<"$calls" \
   && grep -qxF -- 'check --stdin --as rcode/README.md' <<<"$calls"; then
  ok "C-control: clean vault check passes transform 70 (rc=0) and both targets were checked"
else
  bad "C-control: clean vault check passes transform 70 with both targets checked" \
      "rc=$T70_RC calls='$calls' output: $T70_OUT"
fi

# ---------------------------------------------------------------------------
echo ""
echo "publish-strip-regression: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
