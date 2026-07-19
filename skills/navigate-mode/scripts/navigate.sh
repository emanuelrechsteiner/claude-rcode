#!/usr/bin/env bash
# navigate-mode — codebase navigation primitives
# Usage: navigate.sh <subcommand> [path]
#   subcommands: find-entry-point | list-routes | list-stores | hot-files

set -u

SUB="${1:-}"
ROOT="${2:-.}"

if [[ -z "$SUB" ]]; then
  echo "usage: $0 {find-entry-point|list-routes|list-stores|hot-files} [path]" >&2
  exit 2
fi

if [[ ! -d "$ROOT" ]]; then
  echo "error: '$ROOT' is not a directory" >&2
  exit 2
fi

cd "$ROOT" || exit 2

cmd_find_entry_point() {
  echo "== Entry Point Detection =="
  echo "Path: $(pwd)"
  echo

  local found=0

  if [[ -f package.json ]]; then
    found=1
    echo "[node/js] package.json detected"
    local main
    main=$(grep -E '"main"\s*:' package.json | head -1 | sed -E 's/.*"main"\s*:\s*"([^"]+)".*/\1/')
    local mod
    mod=$(grep -E '"module"\s*:' package.json | head -1 | sed -E 's/.*"module"\s*:\s*"([^"]+)".*/\1/')
    [[ -n "$main" ]] && echo "  main:   $main"
    [[ -n "$mod"  ]] && echo "  module: $mod"
    for cand in src/index.ts src/index.tsx src/index.js src/main.ts src/main.tsx app/page.tsx app/layout.tsx pages/index.tsx pages/_app.tsx index.ts index.js; do
      [[ -f "$cand" ]] && echo "  likely: $cand"
    done
  fi

  if [[ -f pyproject.toml ]]; then
    found=1
    echo "[python] pyproject.toml detected"
    for cand in src/main.py main.py app/main.py app.py __main__.py manage.py; do
      [[ -f "$cand" ]] && echo "  likely: $cand"
    done
  fi

  if [[ -f Package.swift ]]; then
    found=1
    echo "[swift] Package.swift detected"
    for cand in Sources/*/main.swift Sources/App/App.swift Sources/*/App.swift; do
      [[ -f "$cand" ]] && echo "  likely: $cand"
    done
  fi

  if [[ -f Cargo.toml ]]; then
    found=1
    echo "[rust] Cargo.toml detected"
    for cand in src/main.rs src/lib.rs src/bin/*.rs; do
      [[ -f "$cand" ]] && echo "  likely: $cand"
    done
  fi

  if [[ -f go.mod ]]; then
    found=1
    echo "[go] go.mod detected"
    for cand in main.go cmd/*/main.go; do
      [[ -f "$cand" ]] && echo "  likely: $cand"
    done
  fi

  if [[ $found -eq 0 ]]; then
    echo "No recognized manifest. Top-level files:"
    ls -1 2>/dev/null | head -20 | sed 's/^/  /'
  fi
}

cmd_list_routes() {
  echo "== Routes =="
  echo "Path: $(pwd)"
  echo

  if [[ -d app ]] || [[ -d pages ]]; then
    echo "[next.js] route files:"
    for d in app pages; do
      if [[ -d "$d" ]]; then
        find "$d" -type f \( -name "page.*" -o -name "route.*" -o -name "layout.*" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.ts" -o -name "*.js" \) 2>/dev/null | head -50 | sed 's/^/  /'
      fi
    done
    echo
  fi

  echo "[react-router] <Route ...> usages:"
  grep -rIn --include='*.tsx' --include='*.jsx' --include='*.ts' --include='*.js' '<Route ' . 2>/dev/null | head -30 | sed 's/^/  /' || true
  echo

  echo "[vue-router] routes: arrays:"
  grep -rIn --include='*.ts' --include='*.js' --include='*.vue' 'routes:\s*\[' . 2>/dev/null | head -30 | sed 's/^/  /' || true
}

cmd_list_stores() {
  echo "== State Stores =="
  echo "Path: $(pwd)"
  echo

  echo "[zustand] create( calls:"
  grep -rIn --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' -E '\bcreate(<[^>]+>)?\(' . 2>/dev/null | grep -iE 'zustand|store' | head -20 | sed 's/^/  /' || true
  echo

  echo "[redux] createSlice( calls:"
  grep -rIn --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' 'createSlice(' . 2>/dev/null | head -20 | sed 's/^/  /' || true
  echo

  echo "[pinia] defineStore( calls:"
  grep -rIn --include='*.ts' --include='*.js' --include='*.vue' 'defineStore(' . 2>/dev/null | head -20 | sed 's/^/  /' || true
  echo

  echo "[react] createContext( calls:"
  grep -rIn --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' 'createContext(' . 2>/dev/null | head -20 | sed 's/^/  /' || true
}

cmd_hot_files() {
  echo "== Hot Files (last 30 days, top 20) =="
  echo "Path: $(pwd)"
  echo

  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "  (not a git repository)"
    return 0
  fi

  git log --since='30 days ago' --pretty=format: --name-only 2>/dev/null \
    | grep -v '^$' \
    | sort \
    | uniq -c \
    | sort -rn \
    | head -20 \
    | sed 's/^/  /'
}

case "$SUB" in
  find-entry-point) cmd_find_entry_point ;;
  list-routes)      cmd_list_routes ;;
  list-stores)      cmd_list_stores ;;
  hot-files)        cmd_hot_files ;;
  *)
    echo "unknown subcommand: $SUB" >&2
    echo "usage: $0 {find-entry-point|list-routes|list-stores|hot-files} [path]" >&2
    exit 2
    ;;
esac
