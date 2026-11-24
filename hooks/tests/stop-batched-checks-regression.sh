#!/usr/bin/env bash
# stop-batched-checks-regression.sh — regression suite for the per-project loop in
# stop-batched-checks.sh (the Stop hook's tsc / eslint / ruff pass).
#
# Pins the GROUPS bug: the loop variable list was assigned to GROUPS, a bash special
# variable (the user's supplementary group ids). The assignment was ignored, the loop
# never saw a project root, and a session with type errors ended with no finding.
#
# Fixtures: TypeScript projects under a mktemp dir — one with a deliberate type error,
# one clean. The real typescript is not pinned in the test environment, so tsc is a
# stub at node_modules/.bin/tsc (npx --no-install resolves it locally). The stub prints
# the same "error TS" line shape real tsc prints. ruff/eslint are not exercised here.
# HOME is isolated, so the hook's refactor-queue never touches the live install.
#
# Usage:  bash ~/.claude/hooks/tests/stop-batched-checks-regression.sh
# Exit:   0 = all assertions pass, 1 = failures (listed on stdout)

set -u
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/stop-batched-checks.sh"
WORK="$(mktemp -d)"
TESTHOME="$WORK/home"
SID_PREFIX="stopbatch-regr-$$"
mkdir -p "$TESTHOME/.claude/global-observation"
# The hook keeps its queue and rate-limit files in /tmp keyed by session_id; remove ours.
trap 'rm -rf "$WORK"; rm -f /tmp/claude-edit-queue-"$SID_PREFIX"-* /tmp/claude-stop-batch-last-"$SID_PREFIX"-*' EXIT

PASS=0; FAIL=0; FAILURES=""
HOOK_OUT=""; HOOK_RC=0

pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); FAILURES="${FAILURES}  $1\n"; }

make_ts_project() {  # $1 = project dir, $2 = "broken" | "clean" | "crash"
  local dir="$1" kind="$2"
  mkdir -p "$dir/src" "$dir/node_modules/.bin"
  printf '{"name":"fixture-%s","private":true}\n' "$kind" > "$dir/package.json"
  printf '{"compilerOptions":{"strict":true,"noEmit":true}}\n' > "$dir/tsconfig.json"
  printf 'export const ok: number = 1;\n' > "$dir/src/index.ts"
  if [ "$kind" = "broken" ]; then
    printf 'export const n: number = "not a number";\n' > "$dir/src/broken.ts"
  fi
  if [ "$kind" = "crash" ]; then
    # (g) tsc exits 1 with a message that is NOT an "error TS" diagnostic.
    printf '#!/bin/bash\necho "Cannot find module typescript"\nexit 1\n' > "$dir/node_modules/.bin/tsc"
  else
    cat > "$dir/node_modules/.bin/tsc" <<'STUB'
#!/bin/bash
# Test stub for tsc: fails with a real-shaped "error TS" line when src/broken.ts exists.
if [ -f src/broken.ts ]; then
  echo "src/broken.ts(1,7): error TS2322: Type 'string' is not assignable to type 'number'."
  echo "Found 1 error in src/broken.ts:1"
  exit 1
fi
exit 0
STUB
  fi
  chmod +x "$dir/node_modules/.bin/tsc"
}

queue_files() {  # $1 = session id, rest = edited file paths (the accumulator's queue)
  local sid="$1"; shift
  : > "/tmp/claude-edit-queue-$sid.txt"
  printf '%s\n' "$@" >> "/tmp/claude-edit-queue-$sid.txt"
}

run_stop() {  # $1 = session id -> HOOK_OUT (stdout) and HOOK_RC (exit code)
  HOOK_OUT=$(printf '{"session_id":"%s"}' "$1" | HOME="$TESTHOME" bash "$HOOK" 2>"$WORK/stderr.txt")
  HOOK_RC=$?
}

finding_has() {  # $1 = jq boolean over $ctx (the hook's additionalContext string)
  printf '%s' "$HOOK_OUT" | jq -e '.hookSpecificOutput.additionalContext as $ctx | '"$1" >/dev/null 2>&1
}

# ── (a) deliberate type error is reported ──────────────────────────────────────────
BROKEN="$WORK/broken-app"; make_ts_project "$BROKEN" broken
SID="${SID_PREFIX}-broken"; queue_files "$SID" "$BROKEN/src/broken.ts"
run_stop "$SID"
if [ "$HOOK_RC" -eq 0 ] && finding_has '$ctx | contains("TypeScript errors") and contains("error TS2322") and contains("broken-app")'; then
  pass
else
  fail "(a) broken project: expected exit 0 + TypeScript-errors finding naming broken-app, got rc=$HOOK_RC out=<$HOOK_OUT> stderr=<$(cat "$WORK/stderr.txt")>"
fi

# ── (b) clean project is silent ────────────────────────────────────────────────────
CLEAN="$WORK/clean-app"; make_ts_project "$CLEAN" clean
SID="${SID_PREFIX}-clean"; queue_files "$SID" "$CLEAN/src/index.ts"
run_stop "$SID"
if [ "$HOOK_RC" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
  pass
else
  fail "(b) clean project: expected exit 0 and no output, got rc=$HOOK_RC out=<$HOOK_OUT>"
fi

# ── (c) mixed session: broken project sorts LAST, so the loop must reach past group 1 ─
MIX_CLEAN="$WORK/a-clean-app"; MIX_BROKEN="$WORK/z-broken-app"
make_ts_project "$MIX_CLEAN" clean; make_ts_project "$MIX_BROKEN" broken
SID="${SID_PREFIX}-mixed"
queue_files "$SID" "$MIX_CLEAN/src/index.ts" "$MIX_BROKEN/src/broken.ts"
run_stop "$SID"
if [ "$HOOK_RC" -eq 0 ] && finding_has '$ctx | contains("z-broken-app") and (contains("a-clean-app") | not)'; then
  pass
else
  fail "(c) mixed session: expected finding for z-broken-app only, got rc=$HOOK_RC out=<$HOOK_OUT>"
fi

# ── (d) project path containing a space still iterates as one group ────────────────
SPACED="$WORK/with space/broken-app"; make_ts_project "$SPACED" broken
SID="${SID_PREFIX}-spaced"; queue_files "$SID" "$SPACED/src/broken.ts"
run_stop "$SID"
if [ "$HOOK_RC" -eq 0 ] && finding_has '$ctx | contains("TypeScript errors") and contains("with space/broken-app")'; then
  pass
else
  fail "(d) spaced path: expected finding naming 'with space/broken-app', got rc=$HOOK_RC out=<$HOOK_OUT>"
fi

# ── (e) no project root above the edited file: empty group list must not invent a group
NOROOT="$WORK/no-project"; mkdir -p "$NOROOT"; printf 'notes\n' > "$NOROOT/notes.ts"
SID="${SID_PREFIX}-noroot"; queue_files "$SID" "$NOROOT/notes.ts"
run_stop "$SID"
if [ "$HOOK_RC" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
  pass
else
  fail "(e) no-root file: expected exit 0 and no output, got rc=$HOOK_RC out=<$HOOK_OUT>"
fi

# ── (f) neither timeout nor gtimeout available: a visible line, never empty output ──
# PATH keeps npx's directory (node) and the core tools, but no timeout tool. Preconditions
# are checked first, so the case cannot pass for the wrong reason.
NPX_BIN="$(command -v npx 2>/dev/null)"
NOTIMEOUT_PATH="$(dirname "${NPX_BIN:-/nonexistent/npx}"):/usr/bin:/bin"
NOTIMEOUT="$WORK/no-timeout-app"; make_ts_project "$NOTIMEOUT" broken
SID="${SID_PREFIX}-notimeout"; queue_files "$SID" "$NOTIMEOUT/src/broken.ts"
if [ -z "$NPX_BIN" ]; then
  fail "(f) precondition: npx not found on PATH, case cannot run"
elif PATH="$NOTIMEOUT_PATH" bash -c 'command -v timeout || command -v gtimeout' >/dev/null 2>&1; then
  fail "(f) precondition: a timeout tool is still reachable on $NOTIMEOUT_PATH"
else
  HOOK_OUT=$(printf '{"session_id":"%s"}' "$SID" | env PATH="$NOTIMEOUT_PATH" HOME="$TESTHOME" bash "$HOOK" 2>"$WORK/stderr.txt")
  HOOK_RC=$?
  if [ "$HOOK_RC" -eq 0 ] && finding_has '$ctx | contains("tsc did not run") and contains("neither timeout nor gtimeout") and (contains("TypeScript errors") | not)'; then
    pass
  else
    fail "(f) no timeout tool: expected exit 0 + visible 'tsc did not run' line, got rc=$HOOK_RC out=<$HOOK_OUT> stderr=<$(cat "$WORK/stderr.txt")>"
  fi
fi

# ── (g) tsc exits 1 with an unrelated message: "did not run", not silence ─────────
CRASH="$WORK/crash-app"; make_ts_project "$CRASH" crash
SID="${SID_PREFIX}-crash"; queue_files "$SID" "$CRASH/src/index.ts"
run_stop "$SID"
if [ "$HOOK_RC" -eq 0 ] && finding_has '$ctx | contains("tsc did not run") and contains("Cannot find module typescript") and (contains("TypeScript errors") | not)'; then
  pass
else
  fail "(g) unrelated tsc failure: expected exit 0 + 'tsc did not run' finding, got rc=$HOOK_RC out=<$HOOK_OUT> stderr=<$(cat "$WORK/stderr.txt")>"
fi

# ── (i) jq missing: one visible finding, never silence ─────────────────────────────
# PATH = symlinks to every /bin and /usr/bin tool except jq (the hook's other commands
# still resolve). Precondition: jq must not be reachable on that PATH.
NOJQ_BIN="$WORK/nojq-bin"; mkdir -p "$NOJQ_BIN"
for f in /bin/* /usr/bin/*; do [ "$(basename "$f")" = jq ] || ln -sf "$f" "$NOJQ_BIN/"; done
NOJQ="$WORK/nojq-app"; make_ts_project "$NOJQ" broken
SID="${SID_PREFIX}-nojq"; queue_files "$SID" "$NOJQ/src/broken.ts"
if PATH="$NOJQ_BIN" bash -c 'command -v jq' >/dev/null 2>&1; then
  fail "(i) precondition: jq is still reachable on $NOJQ_BIN"
else
  HOOK_OUT=$(printf '{"session_id":"%s"}' "$SID" | env PATH="$NOJQ_BIN" HOME="$TESTHOME" bash "$HOOK" 2>"$WORK/stderr.txt")
  HOOK_RC=$?
  if [ "$HOOK_RC" -eq 0 ] && finding_has '$ctx | contains("did not run") and contains("jq is missing")'; then
    pass
  else
    fail "(i) jq missing: expected exit 0 + visible 'jq is missing' finding (valid JSON), got rc=$HOOK_RC out=<$HOOK_OUT> stderr=<$(cat "$WORK/stderr.txt")>"
  fi
fi

# ── (j) empty session id: exit 0 but visible, because the edits were never checked ──
run_stop ""
if [ "$HOOK_RC" -eq 0 ] && finding_has '$ctx | contains("did not run") and contains("no readable session_id")'; then
  pass
else
  fail "(j) empty session_id: expected exit 0 + visible 'no readable session_id' finding, got rc=$HOOK_RC out=<$HOOK_OUT>"
fi

# ── (k)+(l) file lists reach eslint/ruff as one argument each, after `--` ──────────
# Stub eslint (fixture node_modules/.bin, which npx resolves locally) and stub ruff (first
# on PATH) log their argv one per line. One run feeds both cases.
LINT="$WORK/lint-app"; mkdir -p "$LINT/src" "$LINT/py" "$LINT/node_modules/.bin" "$WORK/stubs"
printf '{"name":"fixture-lint","private":true}\n' > "$LINT/package.json"
printf '{"root":true}\n' > "$LINT/.eslintrc.json"
printf '[project]\nname = "fixture"\n' > "$LINT/pyproject.toml"
printf 'const a = 1;\n' > "$LINT/src/--rulesdir=x.js"
printf 'x = 1\n' > "$LINT/py/with space.py"
cat > "$LINT/node_modules/.bin/eslint" <<STUB
#!/bin/bash
printf '%s\n' "\$@" > "$WORK/argv-eslint.txt"
STUB
cat > "$WORK/stubs/ruff" <<STUB
#!/bin/bash
printf '%s\n' "\$@" > "$WORK/argv-ruff.txt"
STUB
chmod +x "$LINT/node_modules/.bin/eslint" "$WORK/stubs/ruff"
SID="${SID_PREFIX}-lint"; queue_files "$SID" "$LINT/src/--rulesdir=x.js" "$LINT/py/with space.py"
HOOK_OUT=$(printf '{"session_id":"%s"}' "$SID" | env PATH="$WORK/stubs:$PATH" HOME="$TESTHOME" bash "$HOOK" 2>"$WORK/stderr.txt")
HOOK_RC=$?

# (k) eslint: the option-shaped file name arrives after `--`, and nothing option-shaped precedes it
ESLINT_ARGV="$WORK/argv-eslint.txt"
if [ "$HOOK_RC" -eq 0 ] && [ -f "$ESLINT_ARGV" ] \
   && awk '/^--$/{f=1; next} f' "$ESLINT_ARGV" | grep -q '/src/--rulesdir=x\.js$' \
   && ! awk '/^--$/{exit} {print}' "$ESLINT_ARGV" | grep -q '^--rulesdir'; then
  pass
else
  fail "(k) eslint argv: expected '--' then the option-shaped path, rc=$HOOK_RC argv=<$(tr '\n' ' ' < "$ESLINT_ARGV" 2>/dev/null)>"
fi

# (l) ruff: the spaced .py name is ONE argument, after `--`
RUFF_ARGV="$WORK/argv-ruff.txt"
if [ "$HOOK_RC" -eq 0 ] && [ -f "$RUFF_ARGV" ] \
   && [ "$(awk '/^--$/{f=1; next} f' "$RUFF_ARGV" | wc -l | tr -d ' ')" -eq 1 ] \
   && awk '/^--$/{f=1; next} f' "$RUFF_ARGV" | grep -q '/py/with space\.py$'; then
  pass
else
  fail "(l) ruff argv: expected '--' then one line ending '/py/with space.py', rc=$HOOK_RC argv=<$(tr '\n' ' ' < "$RUFF_ARGV" 2>/dev/null)>"
fi

echo "── stop-batched-checks-regression: $PASS passed, $FAIL failed ──"
if [ "$FAIL" -gt 0 ]; then
  printf "%b" "$FAILURES"
  exit 1
fi
exit 0
