#!/usr/bin/env bash
# Regression suite for scripts/deploy-to-live.sh — the runtime-preference pull-back.
#
# Why this suite exists: the deploy tool resets tracked files in the LIVE
# INSTALL to the commit state (git checkout -- .). A bug in it deletes real
# work. It is therefore tested against two dummy repos in a
# temp directory; the real ~/.claude is never touched.
#
# Usage:  bash scripts/tests/deploy-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$SCRIPT_DIR/../deploy-to-live.sh"
[ -f "$DEPLOY" ] || { echo "deploy-to-live.sh not found: $DEPLOY" >&2; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf '  [%s] %s\n' "$1" "$2"; }
check(){ # check <name> <expected> <got>
  if [ "$2" = "$3" ]; then ok; else bad "$1" "expected='$2' got='$3'"; fi
}

G() { git -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }

# A settings.json with a STABLE key order: model comes first,
# effortLevel last — exactly like the real file, so the suite would also
# catch a reordering by jq. permissions.defaultMode and
# theme are included (like in the real file), so that a plain
# runtime-key pull-back does NOT trigger a full rewrite on them.
make_settings() { # make_settings <model> <effort>
  cat <<EOF
{
  "model": "$1",
  "theme": "light-daltonized",
  "hooks": {
    "SessionStart": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "echo hello" } ] }
    ]
  },
  "permissions": { "allow": [ "Read" ], "defaultMode": "dontAsk" },
  "env": { "MAX_THINKING_TOKENS": "30000" },
  "effortLevel": "$2"
}
EOF
}

setup() { # setup -> sets WS and LIVE
  ROOT=$(mktemp -d)
  WS="$ROOT/workshop/claude-code-config"
  LIVE="$ROOT/live"
  mkdir -p "$WS/plugins"          # do NOT create LIVE — git clone wants an empty target

  make_settings sonnet low > "$WS/settings.json"
  echo "Rule A" > "$WS/rules-a.md"
  echo '{"state":"old"}' > "$WS/plugins/installed_plugins.json"
  G -C "$WS" init -q -b main
  G -C "$WS" add -A && G -C "$WS" commit -q -m "Initial state"

  G clone -q "$WS" "$LIVE"
  G -C "$LIVE" remote add workshop "$WS"
  G -C "$LIVE" config user.name Test
  G -C "$LIVE" config user.email test@example.invalid
}

teardown() { rm -rf "$ROOT"; }

run_deploy() { # -> returns exit code, output in $OUT
  OUT=$(CLAUDE_WORKSHOP_ROOT="$ROOT/workshop" CLAUDE_LIVE_CONFIG="$LIVE" \
        bash "$DEPLOY" config 2>&1)
  return $?
}

# ── A) Both sides clean: fast-forward goes through ─────────────────────────────
setup
echo "Rule B" > "$WS/rules-b.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Rule B"
run_deploy; RC=$?
check "clean/exit0"           0 "$RC"
check "clean/rule-arrived"    1 "$([ -f "$LIVE/rules-b.md" ] && echo 1 || echo 0)"
teardown

# ── B) Live install has runtime drift: values get pulled back into the workshop ──
setup
make_settings "opus[1m]" high > "$LIVE/settings.json"     # like /model + /config do
echo "Rule C" > "$WS/rules-c.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Rule C"
run_deploy; RC=$?
check "drift/exit0"                0 "$RC"
check "drift/live-clean"           "" "$(G -C "$LIVE" status --porcelain --untracked-files=no)"
check "drift/live-keeps-model"     "opus[1m]" "$(jq -r .model "$LIVE/settings.json")"
check "drift/live-keeps-effort"    "high"     "$(jq -r .effortLevel "$LIVE/settings.json")"
check "drift/workshop-pulled-back" "opus[1m]" "$(jq -r .model "$WS/settings.json")"
check "drift/own-commit"           1 "$(G -C "$WS" log --oneline -1 | grep -c 'runtime preferences')"
check "drift/rule-arrived"         1 "$([ -f "$LIVE/rules-c.md" ] && echo 1 || echo 0)"
# key order must be preserved: model first, effortLevel last
check "drift/order-preserved" "model effortLevel" \
      "$(jq -r 'keys_unsorted | [first, last] | join(" ")' "$WS/settings.json")"
check "drift/hooks-untouched"      1 "$(jq '.hooks | has("SessionStart")' "$WS/settings.json" | grep -c true)"
teardown

# ── C) Live install was manually changed on a NON-runtime key → abort ──────────
setup
jq '.permissions.allow += ["Bash(rm *)"]' "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
run_deploy; RC=$?
check "handedit/aborts"          1 "$RC"
check "handedit/names-reason"    1 "$(echo "$OUT" | grep -c 'OUTSIDE the runtime keys')"
check "handedit/nothing-discarded" 1 "$(jq '[.permissions.allow[] | select(. == "Bash(rm *)")] | length' "$LIVE/settings.json")"
teardown

# ── D) Live install was changed on a different tracked file → abort ────────────
setup
echo "manually changed in the live install" > "$LIVE/rules-a.md"
run_deploy; RC=$?
check "foreignfile/aborts"           1 "$RC"
check "foreignfile/nothing-discarded" "manually changed in the live install" "$(cat "$LIVE/rules-a.md")"
teardown

# ── E) Runtime churn survives the deploy ────────────────────────────────────────
setup
echo '{"state":"current-in-live"}' > "$LIVE/plugins/installed_plugins.json"
G -C "$WS" rm -q --cached plugins/installed_plugins.json
printf 'plugins/installed_plugins.json\n' >> "$WS/.gitignore"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Unversion plugin state"
run_deploy; RC=$?
check "churn/exit0"          0 "$RC"
check "churn/content-kept"   '{"state":"current-in-live"}' "$(cat "$LIVE/plugins/installed_plugins.json" 2>/dev/null)"
teardown

# ── F) Workshop dirty → abort (unchanged legacy behavior) ──────────────────────
setup
echo "unfinished" > "$WS/rules-d.md"
run_deploy; RC=$?
check "workshop-dirty/aborts" 1 "$RC"
check "workshop-dirty/reason" 1 "$(echo "$OUT" | grep -c 'uncommitted changes')"
teardown

# ── G) Live install diverges ONLY in theme → pull-back (nested-path extension,
#      here top-level, but covers the same code path as permissions.defaultMode) ─
setup
jq '.theme = "dark-daltonized"' "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
echo "Rule G" > "$WS/rules-g.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Rule G"
run_deploy; RC=$?
check "theme/exit0"              0 "$RC"
check "theme/live-keeps-value"  "dark-daltonized" "$(jq -r .theme "$LIVE/settings.json")"
check "theme/workshop-pulled-back" "dark-daltonized" "$(jq -r .theme "$WS/settings.json")"
check "theme/own-commit"         1 "$(G -C "$WS" log --oneline -1 | grep -c 'runtime preferences')"
check "theme/rule-arrived"       1 "$([ -f "$LIVE/rules-g.md" ] && echo 1 || echo 0)"
teardown

# ── H) Live install diverges ONLY in permissions.defaultMode (nested path)
#      → pull-back, permissions.allow stays untouched in the process ───────────
setup
jq '.permissions.defaultMode = "auto"' "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
echo "Rule H" > "$WS/rules-h.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Rule H"
run_deploy; RC=$?
check "defaultmode/exit0"              0 "$RC"
check "defaultmode/live-keeps-value"  "auto" "$(jq -r .permissions.defaultMode "$LIVE/settings.json")"
check "defaultmode/workshop-pulled-back" "auto" "$(jq -r .permissions.defaultMode "$WS/settings.json")"
check "defaultmode/allow-untouched"    '["Read"]' "$(jq -c .permissions.allow "$WS/settings.json")"
check "defaultmode/own-commit"         1 "$(G -C "$WS" log --oneline -1 | grep -c 'runtime preferences')"
teardown

# ── I) The protection that must NOT weaken: permissions.defaultMode AND
#      permissions.allow changed at the same time → still ABORTS. The
#      defaultMode exception must not drag its permissions neighbor along. ─────
setup
jq '.permissions.defaultMode = "auto" | .permissions.allow += ["Bash(rm *)"]' \
   "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
run_deploy; RC=$?
check "permissions-neighbor-protected/aborts"          1 "$RC"
check "permissions-neighbor-protected/names-reason"    1 "$(echo "$OUT" | grep -c 'OUTSIDE the runtime keys')"
check "permissions-neighbor-protected/nothing-discarded" 1 "$(jq '[.permissions.allow[] | select(. == "Bash(rm *)")] | length' "$LIVE/settings.json")"
teardown

# ── J) Live install has an autoMode block → stays live-install-only (IMP-219,
#      vault-by-design): NEVER moves to the workshop, triggers NO abort, AND
#      survives reset+fast-forward (without extract_haus_only/restore_haus_only
#      `git checkout -- .` would delete the unversioned block before the
#      fast-forward pulls in a workshop state without autoMode) ────────────────
setup
jq '.autoMode = {"environment": ["FOO=bar"]}' "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
echo "Rule J" > "$WS/rules-j.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Rule J"
run_deploy; RC=$?
check "automode/exit0"                 0 "$RC"
check "automode/live-keeps-block"     '{"environment":["FOO=bar"]}' "$(jq -cS .autoMode "$LIVE/settings.json")"
check "automode/workshop-gets-nothing" "null" "$(jq -c '.autoMode // null' "$WS/settings.json")"
check "automode/no-preferences-commit" 0 "$(G -C "$WS" log --oneline -1 | grep -c 'runtime preferences')"
check "automode/rule-arrived"          1 "$([ -f "$LIVE/rules-j.md" ] && echo 1 || echo 0)"
teardown

# ── K) Invariant pin: live install diverges on a NOT-listed key
#      (hooks) → still ABORTS with a diff, no matter how many runtime paths exist ─
setup
jq '.hooks.SessionStart[0].hooks[0].command = "echo changed"' \
   "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
run_deploy; RC=$?
check "hooks-unlisted/aborts"       1 "$RC"
check "hooks-unlisted/names-reason" 1 "$(echo "$OUT" | grep -c 'OUTSIDE the runtime keys')"
check "hooks-unlisted/shows-diff"   1 "$(echo "$OUT" | grep -c 'echo changed')"
check "hooks-unlisted/nothing-discarded" "echo changed" \
      "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$LIVE/settings.json")"
teardown

# ── L) Deploy with real commits writes pending-verification.md with the
#      commit subjects as a checklist + standard line (IMP-147) ────────────────
setup
echo "Rule L" > "$WS/rules-l.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Rule L: new check"
run_deploy; RC=$?
check "pending/checklist-and-standard-line" 1 "$([ -f "$LIVE/pending-verification.md" ] \
      && grep -qF -- '- [ ] Rule L: new check' "$LIVE/pending-verification.md" \
      && grep -q 'Verification steps per the session acceptance protocol' "$LIVE/pending-verification.md" \
      && echo 1 || echo 0)"
teardown

# ── M) A second deploy overwrites the checklist — the old check is
#      obsolete with the new deploy ─────────────────────────────────────────
setup
echo "Rule M1" > "$WS/rules-m1.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Rule M1: first check"
run_deploy
echo "Rule M2" > "$WS/rules-m2.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Rule M2: second check"
run_deploy; RC=$?
check "pending-overwrite/old-gone-new-there" 1 "$(! grep -q 'Rule M1: first check' "$LIVE/pending-verification.md" \
      && grep -q 'Rule M2: second check' "$LIVE/pending-verification.md" \
      && echo 1 || echo 0)"
teardown

# ── N) Live install has a new modelSettings block (per-model effort level — written
#      by /model + /effort, observed with claude 2.1.266) → pull-back
#      like autoMode. Found 2026-09-09: the deploy aborted on exactly this. ──────
setup
jq '.modelSettings = {"claude-sonnet-5": {"effortLevel": "xhigh"}}' \
   "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
echo "Rule N" > "$WS/rules-n.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Rule N"
run_deploy; RC=$?
check "modelsettings/exit0"              0 "$RC"
check "modelsettings/live-keeps-block" '{"claude-sonnet-5":{"effortLevel":"xhigh"}}' "$(jq -cS .modelSettings "$LIVE/settings.json")"
check "modelsettings/workshop-pulled-back" '{"claude-sonnet-5":{"effortLevel":"xhigh"}}' "$(jq -cS .modelSettings "$WS/settings.json")"
check "modelsettings/own-commit"     1 "$(G -C "$WS" log --oneline -1 | grep -c 'runtime preferences')"
check "modelsettings/rule-arrived"   1 "$([ -f "$LIVE/rules-n.md" ] && echo 1 || echo 0)"
teardown

# ── O) Neither an environment variable nor ~/.claude/env.local.sh knows the
#      workshop root (HOME points to a fresh temp directory without .claude/) →
#      abort that names the template instead of guessing a path (IMP-219) ──────
FAKE_HOME=$(mktemp -d)
OUT=$(env -u CLAUDE_WORKSHOP_ROOT -u CLAUDE_BAUHOF_ROOT -u CLAUDE_LIVE_CONFIG -u CLAUDE_LIVE_COCKPIT \
      HOME="$FAKE_HOME" bash "$DEPLOY" config 2>&1); RC=$?
check "no-machine-paths/aborts"       1 "$RC"
check "no-machine-paths/names-template" 1 "$(echo "$OUT" | grep -c 'env.local.sh.template')"
rm -rf "$FAKE_HOME"

# ── P) restore_haus_only fails (jq error simulated ONLY for the restore
#      call, via a PATH shim that passes all other jq calls through unchanged
#      to the real jq) → the backup file survives with the value
#      intact AND the error message names its path, instead of losing the
#      value with nothing to replace it (found 2026-09-25, before this fix: the
#      script aborted under set -e with no path anywhere to the last-
#      saved value) ──────────────────────────────────────────────────────────
setup
jq '.autoMode = {"environment": ["FOO=bar"]}' "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
echo "Rule P" > "$WS/rules-p.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Rule P"
BACKUP_TMPDIR="$ROOT/backup-tmp"; mkdir -p "$BACKUP_TMPDIR"
JQFAIL_SHIM="$ROOT/bin-jqfail"; mkdir -p "$JQFAIL_SHIM"
REALJQ="$(command -v jq)"
cat > "$JQFAIL_SHIM/jq" <<SHIMEOF
#!/bin/sh
case "\$*" in
  *'setpath(\$e.path; \$e.value)'*) echo "jq: simulated restore failure (test)" >&2; exit 5 ;;
esac
exec "$REALJQ" "\$@"
SHIMEOF
chmod +x "$JQFAIL_SHIM/jq"
OUT=$(TMPDIR="$BACKUP_TMPDIR" PATH="$JQFAIL_SHIM:$PATH" CLAUDE_WORKSHOP_ROOT="$ROOT/workshop" CLAUDE_LIVE_CONFIG="$LIVE" \
      bash "$DEPLOY" config 2>&1); RC=$?
check "restore-fails/aborts" 1 "$([ "$RC" -ne 0 ] && echo 1 || echo 0)"
BACKUP_FILES=("$BACKUP_TMPDIR"/deploy-haus-only-backup.*)
check "restore-fails/file-survives" 1 "$([ -f "${BACKUP_FILES[0]}" ] && echo 1 || echo 0)"
check "restore-fails/file-contains-value" 1 "$(grep -c 'FOO=bar' "${BACKUP_FILES[0]}" 2>/dev/null || echo 0)"
check "restore-fails/message-names-path" 1 \
      "$(echo "$OUT" | grep -qF -- "${BACKUP_FILES[0]}" && echo 1 || echo 0)"
check "restore-fails/file-is-0600" "600" \
      "$(stat -f '%Lp' "${BACKUP_FILES[0]}" 2>/dev/null || stat -c '%a' "${BACKUP_FILES[0]}" 2>/dev/null)"
teardown

# ── Q) Success case with a live-install-only value (autoMode) → the backup file
#      from P no longer exists at the end (same TMPDIR, this time without
#      the failure shim: the real jq runs through) ─────────────────────────────
setup
jq '.autoMode = {"environment": ["FOO=bar"]}' "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
echo "Rule Q" > "$WS/rules-q.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Rule Q"
BACKUP_TMPDIR_Q="$ROOT/backup-tmp-q"; mkdir -p "$BACKUP_TMPDIR_Q"
OUT=$(TMPDIR="$BACKUP_TMPDIR_Q" CLAUDE_WORKSHOP_ROOT="$ROOT/workshop" CLAUDE_LIVE_CONFIG="$LIVE" \
      bash "$DEPLOY" config 2>&1); RC=$?
check "restore-success/exit0" 0 "$RC"
check "restore-success/live-keeps-automode" '{"environment":["FOO=bar"]}' "$(jq -cS .autoMode "$LIVE/settings.json")"
shopt -s nullglob
LEFTOVER_Q=("$BACKUP_TMPDIR_Q"/deploy-haus-only-backup.*)
shopt -u nullglob
check "restore-success/no-backup-file-left" 0 "${#LEFTOVER_Q[@]}"
teardown

# ── Cockpit with new commits: dependencies must be synced ──────────────────────
# Found 2026-09-24: `[ "$name" = "config" ] && write_pending_verification …`
# was the LAST line of deploy(); for the cockpit the test is wrong, the
# function returned 1, set -e aborted before `npm install`. Every real
# cockpit deploy ended in exit 1 without a dependency sync; only the
# second run ("already up to date") got through. npm here is a stub that
# logs its call — the suite needs no network.
ROOT=$(mktemp -d)
CWS="$ROOT/workshop/cockpit"; CLIVE="$ROOT/live-cockpit"; SHIM="$ROOT/bin"
mkdir -p "$CWS" "$SHIM" "$ROOT/workshop/claude-code-config"
printf '#!/bin/sh\necho "npm $*" >> "%s/npm-calls.log"\n' "$ROOT" > "$SHIM/npm"; chmod +x "$SHIM/npm"
echo '{"name":"cockpit-stub","private":true}' > "$CWS/package.json"
G -C "$CWS" init -q -b main && G -C "$CWS" add -A && G -C "$CWS" commit -q -m "Initial state"
G clone -q "$CWS" "$CLIVE"; G -C "$CLIVE" remote add workshop "$CWS"
echo "new" > "$CWS/new.txt"; G -C "$CWS" add -A && G -C "$CWS" commit -q -m "new state"
OUT=$(PATH="$SHIM:$PATH" CLAUDE_WORKSHOP_ROOT="$ROOT/workshop" CLAUDE_LIVE_COCKPIT="$CLIVE" \
      bash "$DEPLOY" cockpit 2>&1); RC=$?
check "cockpit-new/exit0"            0 "$RC"
check "cockpit-new/state-arrived"    1 "$([ -f "$CLIVE/new.txt" ] && echo 1 || echo 0)"
check "cockpit-new/npm-synced"       1 "$(grep -c '^npm install' "$ROOT/npm-calls.log" 2>/dev/null || echo 0)"
check "cockpit-new/completion-message" 1 "$(echo "$OUT" | grep -c 'Deploy complete')"
rm -rf "$ROOT"

printf '── deploy-regression: %d passed, %d failed ──\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
