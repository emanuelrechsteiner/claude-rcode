#!/usr/bin/env bash
# Regression suite for the live-drift report of scripts/deploy-to-live.sh (P-IMP-263).
#
# Why this suite exists: untracked paths that external installers write into the live
# install under governed directories were invisible to every deploy check. The report
# must (a) list such paths, (b) honour live-only-manifest.txt, (c) ignore everything
# outside the governed set, (d) escalate on the 3rd consecutive run (IMP-164),
# (e) never fail a deploy, (f) never read a classifier failure as "not governed", and
# (g) skip nested git repos (untracked dirs holding their own .git): listed in a sub-list,
# never counted, never escalated, never in the state file.
#
# Everything runs in temp directories. The drift check is read-only against the live
# install; the state file is written only inside the temp live install.
#
# Usage:  bash scripts/tests/live-drift-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY="$REPO/scripts/deploy-to-live.sh"
[ -f "$DEPLOY" ] || { echo "deploy-to-live.sh not found: $DEPLOY" >&2; exit 1; }
[ -f "$REPO/hooks/lib/governing-path-classify.py" ] || { echo "classifier not found in $REPO" >&2; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf '  [%s] %s\n' "$1" "$2"; }
check(){ # check <name> <expected> <got>
  if [ "$2" = "$3" ]; then ok; else bad "$1" "expected='$2' got='$3'"; fi
}
has()  { # has <name> <needle> <haystack> - fixed string must be present
  if printf '%s' "$3" | grep -qF -- "$2"; then ok; else bad "$1" "missing '$2' in: $3"; fi
}
hasnot(){ # hasnot <name> <needle> <haystack> - fixed string must be absent
  if printf '%s' "$3" | grep -qF -- "$2"; then bad "$1" "unexpected '$2' in: $3"; else ok; fi
}

G() { git -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }

BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT

# new_case <manifest-text|-> : a live git repo with governed content tracked, and a
# workshop stand-in holding this checkout's classifier (symlink) and the manifest.
# "-" = no manifest file at all. Sets LIVE, WS, STATE.
new_case() {
  local root; root=$(mktemp -d "$BASE/case.XXXXXX")
  LIVE="$root/live"; WS="$root/workshop"
  STATE="$LIVE/global-observation/live-drift-state.tsv"
  mkdir -p "$LIVE/rules" "$LIVE/skills/own" "$WS/hooks/lib"
  ln -s "$REPO/hooks/lib/governing-path-classify.py" "$WS/hooks/lib/governing-path-classify.py"
  printf 'Rule A\n' > "$LIVE/rules/a.md"
  printf 'own skill\n' > "$LIVE/skills/own/SKILL.md"
  G -C "$LIVE" init -q -b main
  G -C "$LIVE" add -A && G -C "$LIVE" commit -q -m "live baseline"
  if [ "$1" != "-" ]; then printf '%s\n' "$1" > "$WS/live-only-manifest.txt"; fi
}

# drift [state-file] : runs --drift-check against LIVE/WS; sets OUT and RC.
drift() {
  OUT=$(CLAUDE_WORKSHOP_ROOT="$BASE" bash "$DEPLOY" --drift-check "$LIVE" "$WS" "$@" 2>&1); RC=$?
}
mkskill() { mkdir -p "$LIVE/skills/$1" && printf 'x\n' > "$LIVE/skills/$1/SKILL.md"; }

# A) Nothing untracked -> one quiet line
new_case "# empty manifest"
drift
check "none/exit0" 0 "$RC"
check "none/line" "live drift: none" "$OUT"

# B) Installer-written governed path, not in the manifest -> reported with the hint
new_case "# empty manifest"
mkskill new-thing
drift
check "unlisted/exit0" 0 "$RC"
check "unlisted/header" 1 "$(printf '%s\n' "$OUT" | grep -c '^live drift: 1 untracked path(s) under governed dirs$')"
has   "unlisted/line" "  skills/new-thing - adopt (copy into the workshop + THIRD-PARTY notice) or list in live-only-manifest.txt" "$OUT"

# C) Same path listed exactly (trailing slash) -> not reported
new_case "skills/new-thing/"
mkskill new-thing
drift
check "listed-exact/none" "live drift: none" "$OUT"

# D) Glob entry, '#' comment and surrounding whitespace -> not reported
new_case "# globs
   skills/new-*   "
mkskill new-thing
drift
check "listed-glob/none" "live drift: none" "$OUT"

# E) Untracked paths outside the governed set -> not reported
new_case "# empty manifest"
mkdir -p "$LIVE/plugins/store" "$LIVE/state"
printf 'x\n' > "$LIVE/plugins/store/p.json"
printf 'x\n' > "$LIVE/state/s.json"
printf 'x\n' > "$LIVE/loose-note.txt"
drift
check "outside/none" "live drift: none" "$OUT"

# F) rules/: *.md is governed, *.local.md is not; top-level CLAUDE.md is governed
new_case "# empty manifest"
printf 'x\n' > "$LIVE/rules/new.md"
printf 'x\n' > "$LIVE/rules/private.local.md"
printf 'x\n' > "$LIVE/CLAUDE.md"
drift
check "rules/count" "live drift: 2 untracked path(s) under governed dirs" "$(printf '%s\n' "$OUT" | head -1)"
has   "rules/md-reported" "  rules/new.md - adopt" "$OUT"
has   "rules/claude-md-reported" "  CLAUDE.md - adopt" "$OUT"
hasnot "rules/local-md-not-reported" "private.local.md" "$OUT"

# G) A path with a space is reported intact
new_case "# empty manifest"
mkdir -p "$LIVE/skills/with space" && printf 'x\n' > "$LIVE/skills/with space/SKILL.md"
drift
has "space/reported" "  skills/with space - adopt" "$OUT"

# H) Escalation: the same unlisted path on 3 consecutive runs -> ESCALATION on the 3rd
new_case "# empty manifest"
mkskill new-thing
drift "$STATE"; OUT1=$OUT
drift "$STATE"; OUT2=$OUT
drift "$STATE"; OUT3=$OUT
hasnot "escalation/run1-quiet" "ESCALATION" "$OUT1"
hasnot "escalation/run2-quiet" "ESCALATION" "$OUT2"
has    "escalation/run3-line" "  ESCALATION: skills/new-thing - unlisted for 3 consecutive deploys (IMP-164)" "$OUT3"
check  "escalation/run3-header" 1 "$(printf '%s\n' "$OUT3" | grep -c '^ESCALATION: live drift: 1 untracked')"
check  "escalation/state-count" "$(printf '3\tskills/new-thing')" "$(cat "$STATE")"

# I) A clean run resets the count; the same path afterwards restarts at 1
new_case "# empty manifest"
mkskill new-thing
drift "$STATE"; drift "$STATE"
rm -rf "$LIVE/skills/new-thing"
drift "$STATE"
check "reset/clean-run" "live drift: none" "$OUT"
check "reset/state-emptied" "" "$(cat "$STATE")"
mkskill new-thing
drift "$STATE"
hasnot "reset/restart-quiet" "ESCALATION" "$OUT"

# J) Classifier that fails -> UNCHECKED, never "none", never a non-zero exit
new_case "# empty manifest"
mkskill new-thing
rm "$WS/hooks/lib/governing-path-classify.py"
printf 'raise SystemExit(3)\n' > "$WS/hooks/lib/governing-path-classify.py"
drift
check "classifier-fails/exit0" 0 "$RC"
has   "classifier-fails/unchecked" "live drift: UNCHECKED" "$OUT"
hasnot "classifier-fails/not-silent-none" "live drift: none" "$OUT"

# K) Missing classifier -> UNCHECKED, exit 0
new_case "# empty manifest"
mkskill new-thing
rm "$WS/hooks/lib/governing-path-classify.py"
drift
check "classifier-missing/exit0" 0 "$RC"
has   "classifier-missing/unchecked" "UNCHECKED - classifier not found" "$OUT"

# L) Missing manifest -> warned, and nothing is exempt
new_case "-"
mkskill new-thing
drift
has "no-manifest/warned" "no live-only-manifest.txt" "$OUT"
has "no-manifest/reported" "  skills/new-thing - adopt" "$OUT"

# M) The seeded real manifest: installer-owned paths exempt, reverse-engineer-anything NOT
new_case "-"
mkskill synced
mkskill reverse-engineer-anything
mkdir -p "$LIVE/plugins/synced" && printf 'x\n' > "$LIVE/plugins/synced/p.json"
OUT=$(CLAUDE_WORKSHOP_ROOT="$BASE" bash "$DEPLOY" --drift-check "$LIVE" "$REPO" 2>&1); RC=$?
check "real-manifest/exit0" 0 "$RC"
check "real-manifest/count" "live drift: 1 untracked path(s) under governed dirs" "$(printf '%s\n' "$OUT" | head -1)"
has   "real-manifest/reverse-engineer-reported" "  skills/reverse-engineer-anything - adopt" "$OUT"
hasnot "real-manifest/synced-exempt" "skills/synced" "$OUT"

# N) Usage error on --drift-check -> exit 1 with a usage line
OUT=$(CLAUDE_WORKSHOP_ROOT="$BASE" bash "$DEPLOY" --drift-check "$BASE" 2>&1); RC=$?
check "usage/exit1" 1 "$RC"
has   "usage/message" "usage: deploy-to-live.sh --drift-check" "$OUT"

# O) Deploy level: a config deploy with drift still succeeds, reports it, records state
ROOT=$(mktemp -d "$BASE/deploy.XXXXXX")
DWS="$ROOT/workshop/claude-code-config"; DLIVE="$ROOT/live"
mkdir -p "$DWS/hooks/lib" "$DWS/rules" "$DWS/skills/own"
cp "$REPO/hooks/lib/governing-path-classify.py" "$DWS/hooks/lib/"
printf '# drift\nskills/synced/\n' > "$DWS/live-only-manifest.txt"
printf 'Rule A\n' > "$DWS/rules/a.md"
printf 'own skill\n' > "$DWS/skills/own/SKILL.md"   # tracked skills/ like the real live install
G -C "$DWS" init -q -b main
G -C "$DWS" add -A && G -C "$DWS" commit -q -m "Initial state"
G clone -q "$DWS" "$DLIVE"
G -C "$DLIVE" remote add workshop "$DWS"
mkdir -p "$DLIVE/skills/new-thing" && printf 'x\n' > "$DLIVE/skills/new-thing/SKILL.md"
printf 'Rule B\n' > "$DWS/rules/b.md"
G -C "$DWS" add -A && G -C "$DWS" commit -q -m "Rule B"
OUT=$(CLAUDE_DEPLOY_SKIP_TESTS=1 CLAUDE_DEPLOY_SKIP_REASON="live-drift-regression: dummy workshop has no runner" \
      CLAUDE_WORKSHOP_ROOT="$ROOT/workshop" CLAUDE_LIVE_CONFIG="$DLIVE" bash "$DEPLOY" config 2>&1); RC=$?
check "deploy/exit0" 0 "$RC"
check "deploy/rule-arrived" 1 "$([ -f "$DLIVE/rules/b.md" ] && echo 1 || echo 0)"
has   "deploy/drift-reported" "  skills/new-thing - adopt" "$OUT"
check "deploy/state-written" "$(printf '1\tskills/new-thing')" "$(cat "$DLIVE/global-observation/live-drift-state.tsv" 2>/dev/null)"

# P) Untracked governed dir holding its own .git (valid repo) -> sub-list line, not counted,
#    no state entry, never escalated over 3 runs
new_case "# empty manifest"
git init -q "$LIVE/skills/vendored" && printf 'x\n' > "$LIVE/skills/vendored/SKILL.md"
drift "$STATE"; drift "$STATE"; drift "$STATE"
check  "nested-dir/none" "live drift: none" "$(printf '%s\n' "$OUT" | head -1)"
has    "nested-dir/skipped-line" "  skills/vendored - nested git repo, skipped (separate deploy target)" "$OUT"
hasnot "nested-dir/not-counted" "untracked path(s)" "$OUT"
hasnot "nested-dir/no-escalation" "ESCALATION" "$OUT"
check  "nested-dir/state-empty" "" "$(cat "$STATE")"

# Q) .git as a file (worktree/submodule style) counts as a nested repo too
new_case "# empty manifest"
ELSE=$(mktemp -d "$BASE/elsewhere.XXXXXX") && git init -q "$ELSE"
mkdir -p "$LIVE/skills/worktree" && printf 'gitdir: %s/.git\n' "$ELSE" > "$LIVE/skills/worktree/.git"
printf 'x\n' > "$LIVE/skills/worktree/SKILL.md"
drift
has    "nested-file/skipped-line" "  skills/worktree - nested git repo, skipped (separate deploy target)" "$OUT"
hasnot "nested-file/not-counted" "untracked path(s)" "$OUT"

# R) Mixed: a plain untracked dir (no .git) is still reported; the nested one is only skipped
new_case "# empty manifest"
mkskill new-thing
git init -q "$LIVE/skills/vendored" && printf 'x\n' > "$LIVE/skills/vendored/SKILL.md"
drift
check  "mixed/count" "live drift: 1 untracked path(s) under governed dirs" "$(printf '%s\n' "$OUT" | head -1)"
has    "mixed/plain-reported" "  skills/new-thing - adopt" "$OUT"
has    "mixed/nested-skipped" "  skills/vendored - nested git repo, skipped" "$OUT"
hasnot "mixed/nested-not-adopt" "skills/vendored - adopt" "$OUT"

# S) A nested repo in an ungoverned dir is not reported at all
new_case "# empty manifest"
git init -q "$LIVE/state/tool"
drift
check  "nested-ungoverned/none" "live drift: none" "$OUT"
hasnot "nested-ungoverned/no-line" "nested git repo" "$OUT"

# T) The shipped manifest carries no cockpit entry (only comment lines may mention it)
check "manifest/no-cockpit-entry" 0 "$(grep -v '^[[:space:]]*#' "$REPO/live-only-manifest.txt" | grep -c 'cockpit')"

# U) Real-layout mirror: the shipped manifest, reverse-engineer-anything untracked, a Cockpit
#    nested repo -> one counted path and one skipped nested repo (no state entry for cockpit)
new_case "-"
cp "$REPO/live-only-manifest.txt" "$WS/live-only-manifest.txt"
mkskill reverse-engineer-anything
git init -q "$LIVE/cockpit" && mkdir -p "$LIVE/cockpit/src" && printf 'x\n' > "$LIVE/cockpit/src/app.ts"
drift "$STATE"
check  "real-layout/exit0" 0 "$RC"
check  "real-layout/count" "live drift: 1 untracked path(s) under governed dirs" "$(printf '%s\n' "$OUT" | head -1)"
has    "real-layout/reverse-engineer-reported" "  skills/reverse-engineer-anything - adopt" "$OUT"
has    "real-layout/cockpit-skipped" "  cockpit - nested git repo, skipped (separate deploy target)" "$OUT"
check  "real-layout/state-only-reverse" "$(printf '1\tskills/reverse-engineer-anything')" "$(cat "$STATE")"

printf '── live-drift-regression: %d passed, %d failed ──\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
