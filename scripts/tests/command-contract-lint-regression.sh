#!/usr/bin/env bash
# Regression suite for scripts/command-contract-lint.sh — the M20/§5/A4
# extended-scope checks added 2026-09-23 (R.Code rework "Plan folgt Praxis",
# unit U9).
#
# What this covers:
#   - Checks M,1-5 (pre-2026-09-23) are untouched: the "default invocation
#     still works" case proves a --root-less call ignores C6-C9 violations
#     entirely, byte-identical to the pre-rework script.
#   - The new checks: C4 (extended scope), C6, C7, C8, C9 — >=1 positive and
#     >=1 negative fixture each, per §5/A4.
#   - The same-line escape comment `<!-- lint:allow -->` (A4; exempts C6-C9
#     only, not check4/M/1-5).
#   - An OPTIONAL final case, "given --root <dir> the tree passes", run ONLY
#     when LINT_REGRESSION_TREE_ROOT is set in the environment. This suite
#     deliberately does NOT default that env var to the Bauhof itself: other
#     R.Code-rework units may still be mid-edit when U9 runs, and this suite
#     must not fail (or falsely pass) on their in-progress state. Per A4 the
#     MAIN LOOP runs this case against the Bauhof after every unit finishes.
#
# Fixtures live entirely under mktemp -d trees; nothing under this repo or
# ~/.claude is read or written except the lint script itself (and, for the
# optional tree-passes case, whatever LINT_REGRESSION_TREE_ROOT points at —
# read-only).
#
# Usage: bash scripts/tests/command-contract-lint-regression.sh
#        LINT_REGRESSION_TREE_ROOT=<repo-root> bash scripts/tests/command-contract-lint-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/../command-contract-lint.sh"
[ -f "$LINT" ] || { echo "command-contract-lint.sh not found: $LINT" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf '  [FAIL] %s: %s\n' "$1" "$2"; }

# check_exit <name> <expected-rc> <actual-rc> <actual-output>
# On mismatch, prints the lint output too (short — these are tiny fixtures)
# so a failure is diagnosable without re-running by hand.
check_exit() {
  local name="$1" expected="$2" actual="$3" out="$4"
  if [ "$expected" = "$actual" ]; then
    ok
  else
    bad "$name" "expected exit=$expected got exit=$actual — output:
$out"
  fi
}

# check_contains <name> <needle> <haystack>
check_contains() {
  local name="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    ok
  else
    bad "$name" "expected output to contain '$needle' — got:
$haystack"
  fi
}

ROOT=$(mktemp -d)
CMDS="$ROOT/commands"
mkdir -p "$CMDS"

# A minimal command file that passes checks M,1-5 (exempt marker, no deny
# terms, no bogus agent refs) — kept present for the whole suite so CHECKED
# never drops to 0 (which would make the script exit 1 for an unrelated
# reason: "no *.md files found").
cat > "$CMDS/baseline.md" <<'EOF'
---
description: regression fixture — always compliant
---
<!-- controller-contract:v1 exempt="regression fixture, no dispatch" -->
Benign fixture content. No deny-terms, no agent references, no C6-C9 bait.
EOF

# reset_ext — wipes and recreates the rcode/skills scaffold that the
# extended-scope (C4-ext/C6-C9) fixtures write into, so each test case
# starts from a clean slate (no leftover violations from the previous case).
reset_ext() {
  rm -rf "$ROOT/rcode" "$ROOT/skills"
  mkdir -p "$ROOT/rcode/rules" "$ROOT/rcode/stages" \
           "$ROOT/skills/rcode-onboard" "$ROOT/skills/rcode-ios" \
           "$ROOT/skills/scope-check"
}

run_default() { OUT=$(bash "$LINT" "$CMDS" 2>&1); RC=$?; }
run_root()    { OUT=$(bash "$LINT" --root "$ROOT" "$CMDS" 2>&1); RC=$?; }

# ── 1) Sanity: clean tree passes both invocation forms ─────────────────────
reset_ext
run_default
check_exit "sanity/default-pass" 0 "$RC" "$OUT"
run_root
check_exit "sanity/root-pass" 0 "$RC" "$OUT"

# ── 2) C4 extended — positive: deny-term in skills/rcode-*/SKILL.md, no
#      archived-marker exemption wording ─────────────────────────────────
reset_ext
printf 'Route UI work to frontend-agent.\n' > "$ROOT/skills/rcode-ios/SKILL.md"
run_root
check_exit "c4ext-positive/exit1" 1 "$RC" "$OUT"
check_contains "c4ext-positive/check4-tag" "check4:" "$OUT"
check_contains "c4ext-positive/file" "rcode-ios/SKILL.md" "$OUT"

# ── 3) C4 extended — negative: same deny-term, but with the archived-marker
#      exemption wording on the same line ──────────────────────────────────
reset_ext
printf 'frontend-agent was archived 2026-06, replaced by ui-agent.\n' > "$ROOT/skills/rcode-ios/SKILL.md"
run_root
check_exit "c4ext-negative/exit0" 0 "$RC" "$OUT"

# ── 4) C6 — positive: repo-relative gather-script call, nested rcode/stages
#      (proves the recursive rcode/**/*.md sweep, not just top-level) ──────
reset_ext
printf 'Run `bash scripts/resume-state.sh` first.\n' > "$ROOT/rcode/stages/x.md"
run_root
check_exit "c6-positive/exit1" 1 "$RC" "$OUT"
check_contains "c6-positive/check6-tag" "check6:" "$OUT"

# ── 5) C6 — negative: properly qualified with ~/.claude/ ────────────────────
reset_ext
printf 'Run `bash ~/.claude/scripts/resume-state.sh "$PWD"` first.\n' > "$ROOT/rcode/stages/x.md"
run_root
check_exit "c6-negative/exit0" 0 "$RC" "$OUT"

# ── 6) C7 — positive: bare /review, skills/rcode-onboard/SKILL.md (proves
#      the skills/rcode-*/SKILL.md glob) ────────────────────────────────────
reset_ext
printf 'Only `/rcode-review` should be invoked, not the bare /review command.\n' > "$ROOT/skills/rcode-onboard/SKILL.md"
run_root
check_exit "c7-positive/exit1" 1 "$RC" "$OUT"
check_contains "c7-positive/check7-tag" "check7:" "$OUT"

# ── 7) C7 — negative: /rcode-review only, no bare /review ───────────────────
reset_ext
printf 'Only `/rcode-review` should be invoked.\n' > "$ROOT/skills/rcode-onboard/SKILL.md"
run_root
check_exit "c7-negative/exit0" 0 "$RC" "$OUT"

# ── 8) C8 — positive: unbraced "$var: followed directly by a letter
#      (skills/scope-check/SKILL.md — proves that single fixed file too) ───
reset_ext
printf 'Resolve via "$sha:rcode/VERSION" — the zsh modifier trap.\n' > "$ROOT/skills/scope-check/SKILL.md"
run_root
check_exit "c8-positive/exit1" 1 "$RC" "$OUT"
check_contains "c8-positive/check8-tag" "check8:" "$OUT"

# ── 9) C8 — negative: braced ${var}: form, AND $var: followed by a space
#      (not a letter) — neither must be flagged ─────────────────────────────
reset_ext
printf 'Resolve via "${sha}:rcode/VERSION" and "$name: some text".\n' > "$ROOT/skills/scope-check/SKILL.md"
run_root
check_exit "c8-negative/exit0" 0 "$RC" "$OUT"

# ── 10) C9 — positive: backtick-quoted commands/... with no ~/.claude/
#       prefix, nested rcode/stages ─────────────────────────────────────────
reset_ext
printf 'Read `commands/issue.md` for the protocol.\n' > "$ROOT/rcode/stages/y.md"
run_root
check_exit "c9-positive/exit1" 1 "$RC" "$OUT"
check_contains "c9-positive/check9-tag" "check9:" "$OUT"

# ── 11) C9 — negative: properly qualified ~/.claude/..., AND a project's own
#       leading-dot .claude/rules/... reference must NOT be a false positive ─
reset_ext
printf 'Read `~/.claude/commands/issue.md`. Project rules live at `.claude/rules/rcode-workflow.md`.\n' > "$ROOT/rcode/stages/y.md"
run_root
check_exit "c9-negative/exit0" 0 "$RC" "$OUT"

# ── 12) Escape comment: a C7-triggering line carrying <!-- lint:allow -->
#       on the SAME line must be exempted ───────────────────────────────────
reset_ext
printf 'This repo used to reference the bare /review command. <!-- lint:allow -->\n' > "$ROOT/rcode/rules/case.md"
run_root
check_exit "escape-comment/exit0" 0 "$RC" "$OUT"

# ── 13) Escape comment does NOT exempt check4 (deny-grep) — the marker is
#        documented as C6-C9-only, not a blanket bypass ─────────────────────
reset_ext
printf 'frontend-agent stays referenced. <!-- lint:allow -->\n' > "$ROOT/skills/rcode-ios/SKILL.md"
run_root
check_exit "escape-comment-scope/check4-still-fires" 1 "$RC" "$OUT"
check_contains "escape-comment-scope/check4-tag" "check4:" "$OUT"

# ── 14) Default invocation still works: a commands/*.md file itself carries
#        C6+C7 violations. Without --root the script must PASS (checks C6-9
#        never run); with --root it must FAIL on both. This is the
#        byte-identical-default-behavior guarantee from the script header. ──
reset_ext
cat > "$CMDS/has-violation.md" <<'EOF'
---
description: regression fixture — carries C6+C7 bait, passes M,1-5 via exempt
---
<!-- controller-contract:v1 exempt="regression fixture" -->
Mentions the bare /review command and calls `bash scripts/resume-state.sh` directly.
EOF
run_default
check_exit "default-invocation/ignores-new-checks" 0 "$RC" "$OUT"
run_root
check_exit "default-invocation/root-catches-same-file" 1 "$RC" "$OUT"
check_contains "default-invocation/root-check6" "check6:" "$OUT"
check_contains "default-invocation/root-check7" "check7:" "$OUT"
rm -f "$CMDS/has-violation.md"

rm -rf "$ROOT"

# ── 15) OPTIONAL: "given --root <dir> the tree passes" — only when
#        LINT_REGRESSION_TREE_ROOT is set (per A4; the main loop runs this
#        against the Bauhof after all units finish, not this suite by
#        default). Not counted as pass/fail when skipped. ──────────────────
if [ -n "${LINT_REGRESSION_TREE_ROOT:-}" ]; then
  TREE_ROOT="$LINT_REGRESSION_TREE_ROOT"
  if [ -d "$TREE_ROOT/commands" ]; then
    TREE_OUT=$(bash "$LINT" --root "$TREE_ROOT" "$TREE_ROOT/commands" 2>&1)
    TREE_RC=$?
    check_exit "tree-passes/exit0" 0 "$TREE_RC" "$TREE_OUT"
  else
    bad "tree-passes/missing-commands-dir" "LINT_REGRESSION_TREE_ROOT=$TREE_ROOT has no commands/ dir"
  fi
else
  echo "  [skipped] tree-passes case: LINT_REGRESSION_TREE_ROOT not set"
fi

TOTAL=$((PASS + FAIL))
printf '%d/%d passed\n' "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ]
