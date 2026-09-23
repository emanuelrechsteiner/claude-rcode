#!/usr/bin/env bash
# test_navigate.sh — smoke tests for navigate.sh primitives
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAV="$SCRIPT_DIR/../scripts/navigate.sh"

if [[ ! -x "$NAV" ]]; then
  echo "FAIL: navigate.sh not executable at $NAV"
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; exit 1; }

# --- Test 1: find-entry-point on node project ---
echo "[test] find-entry-point (node)"
mkdir -p "$TMP/node-proj/src"
cat > "$TMP/node-proj/package.json" <<'EOF'
{ "name": "demo", "main": "src/index.ts" }
EOF
touch "$TMP/node-proj/src/index.ts"
out=$(bash "$NAV" find-entry-point "$TMP/node-proj")
echo "$out" | grep -q 'package.json detected' && pass "detects package.json" || fail "no package.json detection"
echo "$out" | grep -q 'src/index.ts' && pass "lists src/index.ts" || fail "missing src/index.ts"

# --- Test 2: find-entry-point on python project ---
echo "[test] find-entry-point (python)"
mkdir -p "$TMP/py-proj"
touch "$TMP/py-proj/pyproject.toml" "$TMP/py-proj/main.py"
out=$(bash "$NAV" find-entry-point "$TMP/py-proj")
echo "$out" | grep -q 'pyproject.toml detected' && pass "detects pyproject.toml" || fail "no pyproject detection"
echo "$out" | grep -q 'main.py' && pass "lists main.py" || fail "missing main.py"

# --- Test 3: list-routes (Next.js) ---
echo "[test] list-routes (next.js)"
mkdir -p "$TMP/next-proj/app/dashboard"
touch "$TMP/next-proj/app/page.tsx" "$TMP/next-proj/app/dashboard/page.tsx"
out=$(bash "$NAV" list-routes "$TMP/next-proj")
echo "$out" | grep -q 'app/page.tsx' && pass "lists app/page.tsx" || fail "missing app/page.tsx"
echo "$out" | grep -q 'dashboard/page.tsx' && pass "lists nested route" || fail "missing nested route"

# --- Test 4: list-stores (zustand) ---
echo "[test] list-stores (zustand)"
mkdir -p "$TMP/store-proj/src"
cat > "$TMP/store-proj/src/userStore.ts" <<'EOF'
import { create } from 'zustand'
export const useUserStore = create((set) => ({ name: '' }))
EOF
out=$(bash "$NAV" list-stores "$TMP/store-proj")
echo "$out" | grep -q 'userStore.ts' && pass "finds zustand store" || fail "missed zustand store"

# --- Test 5: list-stores (react context) ---
echo "[test] list-stores (react context)"
mkdir -p "$TMP/ctx-proj"
cat > "$TMP/ctx-proj/ThemeContext.tsx" <<'EOF'
import { createContext } from 'react'
export const ThemeContext = createContext(null)
EOF
out=$(bash "$NAV" list-stores "$TMP/ctx-proj")
echo "$out" | grep -q 'ThemeContext.tsx' && pass "finds createContext" || fail "missed createContext"

# --- Test 6: hot-files on non-git dir ---
echo "[test] hot-files (no git)"
mkdir -p "$TMP/no-git"
out=$(bash "$NAV" hot-files "$TMP/no-git")
echo "$out" | grep -q 'not a git repository' && pass "handles non-git gracefully" || fail "non-git not handled"

# --- Test 7: hot-files on git repo ---
echo "[test] hot-files (git repo)"
mkdir -p "$TMP/git-proj"
( cd "$TMP/git-proj" && git init -q && git config user.email t@t && git config user.name t \
  && echo a > a.txt && git add a.txt && git commit -q -m one \
  && echo b >> a.txt && git add a.txt && git commit -q -m two )
out=$(bash "$NAV" hot-files "$TMP/git-proj")
echo "$out" | grep -q 'a.txt' && pass "lists committed file" || fail "missed git log output"

# --- Test 8: unknown subcommand ---
echo "[test] unknown subcommand"
if bash "$NAV" bogus "$TMP" 2>/dev/null; then
  fail "should reject unknown subcommand"
else
  pass "rejects unknown subcommand"
fi

echo
echo "ALL TESTS PASSED"
