#!/bin/bash
# vault-check: fixtures (synthetic values only — invented stand-ins for structural/vault matching, never a real term)
#
# git-hooks-regression.sh — regression suite for scripts/git-hooks/pre-commit
# + scripts/install-git-hooks.sh (IMP-219, Welle 2 unit B,
# plans/vault-by-design-2026-09-25.md §4.3; installer mechanism corrected
# 2026-09-25 to extend the pre-existing direct .git/hooks/ installer rather
# than `git config core.hooksPath` — see scripts/install-git-hooks.sh's own
# header comment for why).
#
# Runs ENTIRELY inside throwaway temp git repos, each with its own throwaway
# CLAUDE_VAULT_DIR — never this repo's own git config, and never the real
# ~/.claude/vault. The fixture marker above MUST close its parenthetical on
# the SAME line (plans/vault-by-design-2026-09-25.md §7.2).
#
# Safety guards (added 2026-09-25, IMP-219, after a same-day incident where
# real pre-commit + pre-push hooks were found installed in THIS repo's own
# .git/hooks/ with nobody having knowingly run the installer against it):
# every `Tn="$(new_temp_repo)"` assignment is immediately checked by
# require_temp_repo() (empty/invalid → loud FATAL abort of the whole suite,
# not a silent continue), new_temp_repo()'s own internal mktemp is
# self-checked before it does anything with the result, and the suite's
# outer SCRATCH dir is checked the same way. A before/after snapshot of the
# REAL repo's .git/hooks/ brackets the entire run (see snapshot_real_hooks())
# as an independent second layer. Root cause: bash's `cd ""` is a SILENT,
# successful no-op (not an error) — see require_temp_repo()'s own comment
# for the full chain.
#
# Also covers scripts/install-git-hooks.sh's `--only <pre-commit|pre-push>`
# flag and its "refuse to run outside a framework repo" marker check (same
# task) — both exercised below, alongside the pre-existing cases.
#
# Extended 2026-09-25 (same day, plan §"Auftrag"):
#   M3 — the gitignore exception is now two-case, not a blanket skip: a
#     staged path that is ignored AND absent from HEAD (force-added, new)
#     is BLOCKED outright; a staged path that is ignored but was ALREADY in
#     HEAD (a later .gitignore edit now matches an existing tracked file) is
#     still fully content-checked, never skipped. Both cases are exercised
#     below (the old "skipped even if force-added" case is now inverted).
#   M7 — install-git-hooks.sh now also installs .git/hooks/pre-merge-commit
#     (git's hook for a conflict-free, automatic `git merge`/`git pull`,
#     which pre-commit is never invoked for) as part of the SAME "pre-commit"
#     --only group as .git/hooks/pre-commit; both run the identical versioned
#     scripts/git-hooks/pre-commit. Exercised below via a clean-merge-blocked
#     case, a clean-merge-succeeds case, and updated --only/--uninstall
#     assertions. Separately (documented in install-git-hooks.sh's own header,
#     not re-tested here as a suite assertion): a conflict-free `git
#     cherry-pick` or `git rebase` fires NEITHER pre-commit NOR
#     pre-merge-commit on this machine's git (2.51.0) — a known, unclosed gap,
#     not something this task's scope covers fixing.
#   IMP-219 rebrand --staged fix (same day) — scripts/scrub-check.sh's §6
#     ("Rebrand regression"), which pre-commit calls as its own second,
#     independent scan, used to grep the WHOLE staged blob of every selected
#     file: any of this repo's reviewed pre-existing pre-rebrand mentions
#     (CHANGELOG.md, the improvement ledger, ...) re-blocked any unrelated
#     staged edit to those files. Fixed so --staged only counts a finding on
#     a line the staged diff itself ADDS. The end-to-end case below seeds HEAD
#     with a pre-existing old-name line (via --no-verify, since a brand-new
#     seed file containing it would itself trip the very fix under test), then
#     shows a neutral append now SUCCEEDS through the real, installed hook
#     while a genuinely NEW old-name line is still BLOCKED. Per-case unit
#     coverage (added-line detection, edited-debt-line detection, rename
#     handling, full-tree contrast) lives in scrub-check-regression.sh; this
#     is the one pieces-fit-together check at the pre-commit-hook level.
#
# Usage: bash scripts/tests/git-hooks-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/install-git-hooks.sh"
PRECOMMIT_SRC="$REPO_ROOT/scripts/git-hooks/pre-commit"

[[ -f "$INSTALLER" ]] || { echo "ERROR: installer not found: $INSTALLER" >&2; exit 1; }
[[ -f "$PRECOMMIT_SRC" ]] || { echo "ERROR: pre-commit not found: $PRECOMMIT_SRC" >&2; exit 1; }

# ── Tripwire sensor (armed BEFORE anything else runs, read again at the very
#    end of this file): a deterministic snapshot of the REAL repo's own
#    .git/hooks/ (non-.sample files only, name + mtime + content checksum).
#    This suite must NEVER change that directory — every installer
#    invocation below targets a throwaway temp repo. If it ever does change
#    (e.g. because a temp-repo path variable was silently empty and
#    `cd "$Tn"` no-op'd into this repo's own working directory instead — see
#    require_temp_repo() below for why that is exactly the failure mode this
#    guards against), the before/after comparison at the end of this file
#    turns that into a loud FAIL rather than a silent pass.
REAL_HOOKS_DIR="$REPO_ROOT/.git/hooks"
snapshot_real_hooks() {
    local f name m lines
    lines=""
    if [ -d "$REAL_HOOKS_DIR" ]; then
        for f in "$REAL_HOOKS_DIR"/*; do
            [ -e "$f" ] || continue
            [ -f "$f" ] || continue
            name="$(basename "$f")"
            case "$name" in
                *.sample) continue ;;
            esac
            m="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo unknown)"
            lines="${lines}${name}:${m}:$(cksum <"$f")
"
        done
    fi
    if [ -z "$lines" ]; then
        echo "EMPTY"
    else
        printf '%s' "$lines" | sort
    fi
}
REAL_HOOKS_BEFORE="$(snapshot_real_hooks)"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  \xe2\x9c\x85 %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  \xe2\x9d\x8c %s\n     %s\n' "$1" "$2"; }
check_exit() { # label expected actual
    [[ "$3" == "$2" ]] && ok "$1" || bad "$1" "expected exit $2, got $3"
}

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/git-hooks-regr.XXXXXX")"
if [ -z "$SCRATCH" ] || [ ! -d "$SCRATCH" ]; then
    echo "git-hooks-regression: FATAL — mktemp failed to create the suite's own" >&2
    echo "  scratch dir (got: '$SCRATCH'). Aborting before creating any temp repo:" >&2
    echo "  every per-repo mktemp below is rooted under this path, so if THIS one" >&2
    echo "  is empty, every one of those would be too." >&2
    exit 1
fi
trap 'rm -rf "$SCRATCH"' EXIT

# An EMPTY (never-initialized) vault dir, used as the default CLAUDE_VAULT_DIR
# for every commit below EXCEPT the one test that deliberately populates its
# own — this suite must never read or depend on this machine's real
# ~/.claude/vault.
EMPTY_VAULT="$SCRATCH/empty-vault"
export CLAUDE_VAULT_DIR="$EMPTY_VAULT"

# require_temp_repo <varname> — safety tripwire, called immediately after
# EVERY assignment of a temp-repo path in this suite (new_temp_repo() output
# or a manually mktemp+git-init'd path). Aborts the ENTIRE suite loudly if
# the named variable is empty or is not a real git repo.
#
# Why this exists (confirmed empirically during this task, IMP-219): bash's
# `cd ""` is a SILENT, successful no-op — it does NOT raise "No such file or
# directory" and does NOT set a nonzero exit status; it simply leaves you in
# whatever directory you already were. Every installer call in this suite
# is shaped `(cd "$Tn" && bash "$INSTALLER" ...)`. If $Tn is empty — which
# happens if the `mktemp -d` inside new_temp_repo() fails, since
# `t="$(mktemp -d ...)"` under `set -uo pipefail` (note: NO `-e` in this
# file) leaves `t` bound-but-empty rather than halting or raising "unbound
# variable" — that `cd` silently does nothing, and `bash "$INSTALLER"` then
# runs with the CALLER's cwd, i.e. wherever this suite itself was invoked
# from. Run from inside (or below) the real repo, `git rev-parse
# --show-toplevel` inside the installer would resolve to the REAL repo, and
# it would install real hook files into $REPO_ROOT/.git/hooks — with no
# uncaught error anywhere in the chain. This guard closes that gap at every
# call site; the tripwire at the end of this file is the second, independent
# layer in case a future call site forgets to call this.
require_temp_repo() {
    local name="$1" val
    eval "val=\"\${${name}:-}\""
    if [ -n "$val" ] && [ -d "$val/.git" ]; then
        return 0
    fi
    echo "" >&2
    echo "git-hooks-regression: FATAL SAFETY ABORT — \$$name is empty or not a git" >&2
    echo "  repo (got: '$val'). Refusing to continue: see require_temp_repo()'s" >&2
    echo "  header comment for why this is not a normal test failure — it is the" >&2
    echo "  guard for the installer running against the wrong repo entirely." >&2
    FAIL=$((FAIL + 1))
    echo ""
    echo "git-hooks-regression: $PASS passed, $FAIL failed (ABORTED EARLY)"
    exit 1
}

# new_temp_repo — a bare repo tree with the real vault.sh/lib.sh/scrub-check.sh
# and the versioned scripts/git-hooks/pre-commit copied in (the installed
# .git/hooks/pre-commit wrapper calls this file by its repo-relative path),
# but WITHOUT running the installer — callers install explicitly, so tests
# that need a foreign pre-existing hook can create one first.
new_temp_repo() { # -> prints the repo's absolute path on stdout
    local t
    t="$(mktemp -d "$SCRATCH/repo.XXXXXX")"
    if [ -z "$t" ] || [ ! -d "$t" ]; then
        echo "git-hooks-regression: FATAL — mktemp failed to create a temp repo dir" >&2
        echo "  under '$SCRATCH' (got: '$t'). Aborting before git-init/mkdir/cp can" >&2
        echo "  run against an empty path." >&2
        exit 1
    fi
    git init -q "$t"
    git -C "$t" config user.email "test@example.com"
    git -C "$t" config user.name "Test User"
    mkdir -p "$t/scripts/vault" "$t/scripts/git-hooks"
    cp "$REPO_ROOT/scripts/vault/vault.sh" "$t/scripts/vault/vault.sh"
    cp "$REPO_ROOT/scripts/vault/lib.sh" "$t/scripts/vault/lib.sh"
    cp "$REPO_ROOT/scripts/scrub-check.sh" "$t/scripts/scrub-check.sh"
    chmod +x "$t/scripts/vault/vault.sh" "$t/scripts/scrub-check.sh"
    cp "$PRECOMMIT_SRC" "$t/scripts/git-hooks/pre-commit"
    chmod +x "$t/scripts/git-hooks/pre-commit"
    printf '%s' "$t"
}

echo "== installer: installs pre-commit + pre-push + pre-merge-commit, idempotent =="
T1="$(new_temp_repo)"
require_temp_repo T1
(cd "$T1" && bash "$INSTALLER" >/dev/null 2>&1)
check_exit "installer: 1st run exits 0" 0 "$?"
HOOKS_DIR_T1="$(git -C "$T1" rev-parse --git-path hooks)"
[[ -x "$T1/$HOOKS_DIR_T1/pre-commit" ]] && ok "installer writes an executable .git/hooks/pre-commit" || bad "pre-commit installed" "missing/not executable"
[[ -x "$T1/$HOOKS_DIR_T1/pre-push" ]] && ok "installer writes an executable .git/hooks/pre-push" || bad "pre-push installed" "missing/not executable"
[[ -x "$T1/$HOOKS_DIR_T1/pre-merge-commit" ]] && ok "installer writes an executable .git/hooks/pre-merge-commit" || bad "pre-merge-commit installed" "missing/not executable"
grep -qF "Installed by scripts/install-git-hooks.sh" "$T1/$HOOKS_DIR_T1/pre-commit" && ok "installed pre-commit carries the marker" || bad "pre-commit marker" "missing"
grep -qF "Installed by scripts/install-git-hooks.sh" "$T1/$HOOKS_DIR_T1/pre-merge-commit" && ok "installed pre-merge-commit carries the marker" || bad "pre-merge-commit marker" "missing"
CKSUM_BEFORE="$(cat "$T1/$HOOKS_DIR_T1/pre-push" "$T1/$HOOKS_DIR_T1/pre-commit" "$T1/$HOOKS_DIR_T1/pre-merge-commit" | cksum)"
(cd "$T1" && bash "$INSTALLER" >/dev/null 2>&1)
check_exit "installer: 2nd run exits 0 (idempotent)" 0 "$?"
CKSUM_AFTER="$(cat "$T1/$HOOKS_DIR_T1/pre-push" "$T1/$HOOKS_DIR_T1/pre-commit" "$T1/$HOOKS_DIR_T1/pre-merge-commit" | cksum)"
[[ "$CKSUM_BEFORE" == "$CKSUM_AFTER" ]] && ok "installer: hook content unchanged after 2nd run" || bad "installer idempotent content" "checksum changed"
HP="$(git -C "$T1" config --local --get core.hooksPath 2>/dev/null || true)"
[[ -z "$HP" ]] && ok "installer NEVER sets core.hooksPath" || bad "core.hooksPath" "unexpectedly set to '$HP'"

echo "== pre-commit: clean commit goes through =="
printf 'hello, harmless content\n' >"$T1/clean.txt"
git -C "$T1" add clean.txt
git -C "$T1" commit -q -m "add clean file" >/dev/null 2>"$SCRATCH/err1"
check_exit "clean commit succeeds" 0 "$?"

echo "== pre-commit: synthetic vault term blocks the commit =="
T2="$(new_temp_repo)"
require_temp_repo T2
(cd "$T2" && bash "$INSTALLER" >/dev/null 2>&1)
VDIR="$(mktemp -d "$SCRATCH/vault.XXXXXX")"
CLAUDE_VAULT_DIR="$VDIR" bash "$T2/scripts/vault/vault.sh" init >/dev/null 2>&1
CLAUDE_VAULT_DIR="$VDIR" bash "$T2/scripts/vault/vault.sh" add project "SynthGitHookProbeCorp" --group ghprobe >/dev/null 2>&1
printf 'const owner = "SynthGitHookProbeCorp";\n' >"$T2/leak.txt"
git -C "$T2" add leak.txt
ERR2="$(CLAUDE_VAULT_DIR="$VDIR" git -C "$T2" commit -m "add leak" 2>&1)"
RC2=$?
check_exit "commit with a vault-registered synthetic term is blocked" 1 "$RC2"
echo "$ERR2" | grep -q "BLOCKED" && ok "blocked commit prints a BLOCKED message" || bad "blocked commit message" "$ERR2"

echo "== pre-commit: structural pattern (no vault needed) blocks the commit =="
T3="$(new_temp_repo)"
require_temp_repo T3
(cd "$T3" && bash "$INSTALLER" >/dev/null 2>&1)
printf 'the path is /Users/synthfaketester/project\n' >"$T3/structural.txt"
git -C "$T3" add structural.txt
git -C "$T3" commit -q -m "add structural leak" >/dev/null 2>"$SCRATCH/err3"
check_exit "commit with a structural /Users/ pattern is blocked" 1 "$?"

echo "== pre-commit: renamed file with injected content is blocked (diff-filter includes R) =="
T9="$(new_temp_repo)"
require_temp_repo T9
(cd "$T9" && bash "$INSTALLER" >/dev/null 2>&1)
VDIR9="$(mktemp -d "$SCRATCH/vault.XXXXXX")"
CLAUDE_VAULT_DIR="$VDIR9" bash "$T9/scripts/vault/vault.sh" init >/dev/null 2>&1
CLAUDE_VAULT_DIR="$VDIR9" bash "$T9/scripts/vault/vault.sh" add project "SynthRenameProbeCorp" --group renameprobe >/dev/null 2>&1
printf 'harmless original content\nline two\nline three\nline four\nline five\n' >"$T9/orig.txt"
git -C "$T9" add orig.txt
git -C "$T9" commit -q -m "seed" >/dev/null 2>&1
git -C "$T9" mv orig.txt renamed.txt
printf 'harmless original content\nline two\nline three\nline four\nline five\nconst owner = "SynthRenameProbeCorp";\n' >"$T9/renamed.txt"
git -C "$T9" add renamed.txt
ERR9="$(CLAUDE_VAULT_DIR="$VDIR9" git -C "$T9" commit -m "rename + leak" 2>&1)"
RC9=$?
check_exit "commit renaming a file (git mv) while injecting a vault-registered term is blocked" 1 "$RC9"
echo "$ERR9" | grep -q "BLOCKED" && ok "blocked rename-commit prints a BLOCKED message" || bad "blocked rename-commit message" "$ERR9"

# Empirically: without an explicit -C/--find-copies (neither is passed, and no
# config scope on this machine sets diff.renames=copies), a copy that keeps
# its source path untouched is reported as plain status A, not C — so this
# case was ALREADY blocked before the AM -> AMRC fix too (verified via a
# throwaway probe repo during this task). It stays in the suite as a
# regression pin for the copy path, not as a before/after differential like
# the rename case above.
echo "== pre-commit: copied file with injected content is blocked (diff-filter includes C) =="
T10="$(new_temp_repo)"
require_temp_repo T10
(cd "$T10" && bash "$INSTALLER" >/dev/null 2>&1)
VDIR10="$(mktemp -d "$SCRATCH/vault.XXXXXX")"
CLAUDE_VAULT_DIR="$VDIR10" bash "$T10/scripts/vault/vault.sh" init >/dev/null 2>&1
CLAUDE_VAULT_DIR="$VDIR10" bash "$T10/scripts/vault/vault.sh" add project "SynthCopyProbeCorp" --group copyprobe >/dev/null 2>&1
printf 'harmless original content\nline two\nline three\nline four\nline five\n' >"$T10/source.txt"
git -C "$T10" add source.txt
git -C "$T10" commit -q -m "seed" >/dev/null 2>&1
cp "$T10/source.txt" "$T10/copy.txt"
printf 'harmless original content\nline two\nline three\nline four\nline five\nconst owner = "SynthCopyProbeCorp";\n' >"$T10/copy.txt"
git -C "$T10" add copy.txt
ERR10="$(CLAUDE_VAULT_DIR="$VDIR10" git -C "$T10" commit -m "copy + leak" 2>&1)"
RC10=$?
check_exit "commit copying a file (source untouched) while injecting a vault-registered term is blocked" 1 "$RC10"
echo "$ERR10" | grep -q "BLOCKED" && ok "blocked copy-commit prints a BLOCKED message" || bad "blocked copy-commit message" "$ERR10"

echo "== pre-commit: a NEWLY force-added gitignored file is BLOCKED, never silently committed (M3a) =="
# Inverted 2026-09-25 (IMP-219, plan §"Auftrag" item 1): this case used to
# assert the OPPOSITE — that a force-added ignored file was skipped and the
# commit succeeded. That let an unreviewed gitignored path (e.g. a private
# *.local.md overlay) reach version control with zero content inspection.
# The fix treats "ignored AND absent from HEAD" as inherently suspicious
# (git already refuses a plain, non-forced `git add` on such a path) and
# blocks it outright, regardless of its content.
T4="$(new_temp_repo)"
require_temp_repo T4
(cd "$T4" && bash "$INSTALLER" >/dev/null 2>&1)
printf 'ignored.txt\n' >"$T4/.gitignore"
git -C "$T4" add .gitignore
git -C "$T4" commit -q -m "add gitignore" >/dev/null 2>"$SCRATCH/err4a"
check_exit "setup: add .gitignore commit succeeds" 0 "$?"
printf 'const owner = "SynthGitHookProbeCorp";\n' >"$T4/ignored.txt"
git -C "$T4" add -f ignored.txt
ERR4B="$(CLAUDE_VAULT_DIR="$EMPTY_VAULT" git -C "$T4" commit -m "add force-added ignored file" 2>&1)"
RC4B=$?
check_exit "force-added NEW ignored file is blocked, not silently committed" 1 "$RC4B"
echo "$ERR4B" | grep -qi "gitignor" && ok "block message names the gitignore-new-path case" || bad "gitignore-new-path block message" "$ERR4B"

echo "== pre-commit: an already-tracked file a LATER .gitignore pattern matches is still checked (M3b) =="
T16="$(new_temp_repo)"
require_temp_repo T16
(cd "$T16" && bash "$INSTALLER" >/dev/null 2>&1)
VDIR16="$(mktemp -d "$SCRATCH/vault.XXXXXX")"
CLAUDE_VAULT_DIR="$VDIR16" bash "$T16/scripts/vault/vault.sh" init >/dev/null 2>&1
CLAUDE_VAULT_DIR="$VDIR16" bash "$T16/scripts/vault/vault.sh" add project "SynthTrackedLaterIgnoredCorp" --group trackedlaterignored >/dev/null 2>&1
printf 'harmless tracked content\n' >"$T16/tracked.txt"
git -C "$T16" add tracked.txt
git -C "$T16" commit -q -m "seed tracked file" >/dev/null 2>&1
printf 'tracked.txt\n' >"$T16/.gitignore"
git -C "$T16" add .gitignore
git -C "$T16" commit -q -m "add gitignore pattern matching an already-tracked file" >/dev/null 2>&1
# --no-index required for this sanity assertion too: plain `check-ignore`
# never reports a match for an already-tracked path (see pre-commit's own
# comment on this) — this is the same reason the hook itself uses --no-index.
git -C "$T16" check-ignore --no-index -q tracked.txt
check_exit "setup: .gitignore now matches the already-tracked file" 0 "$?"
printf 'harmless tracked content\nconst owner = "SynthTrackedLaterIgnoredCorp";\n' >"$T16/tracked.txt"
git -C "$T16" add tracked.txt
ERR16="$(CLAUDE_VAULT_DIR="$VDIR16" git -C "$T16" commit -m "edit already-tracked, now-ignored file with a leak" 2>&1)"
RC16=$?
check_exit "editing an already-tracked, now-ignored file is still vault-checked (blocked)" 1 "$RC16"
echo "$ERR16" | grep -q "BLOCKED" && ok "blocked already-tracked-now-ignored commit prints a BLOCKED message" || bad "already-tracked-now-ignored block message" "$ERR16"

echo "== pre-commit: a pre-existing old-name line in HEAD does not block a neutral append, but a NEW old-name line still blocks (IMP-219 rebrand --staged fix) =="
T19="$(new_temp_repo)"
require_temp_repo T19
(cd "$T19" && bash "$INSTALLER" >/dev/null 2>&1)
_rebrand19="tor""valdsen"
printf 'line one harmless\nline two mentions %s (pre-existing, accepted debt)\nline three harmless\n' "$_rebrand19" >"$T19/debt.txt"
git -C "$T19" add debt.txt
# Seeded with --no-verify on purpose (same technique as the pre-push test
# below): a BRAND NEW file/line containing the old name would itself be
# blocked by the very fix under test, so "a pre-existing debt line already in
# HEAD" has to be planted directly, the same way this repo's own accepted
# pre-rebrand mentions got into CHANGELOG.md/the improvement ledger (predating
# this gate, or via a reviewed bypass) — never through the gate itself.
git -C "$T19" -c commit.gpgsign=false commit -q --no-verify -m "seed pre-existing debt line (bypass, test setup)" >/dev/null 2>&1

printf 'line one harmless\nline two mentions %s (pre-existing, accepted debt)\nline three harmless\nline four is a brand new neutral line\n' "$_rebrand19" >"$T19/debt.txt"
git -C "$T19" add debt.txt
git -C "$T19" commit -q -m "append a neutral line" >/dev/null 2>"$SCRATCH/err19a"
check_exit "neutral append to a file with pre-existing debt SUCCEEDS through the real pre-commit hook" 0 "$?"

printf 'line one harmless\nline two mentions %s (pre-existing, accepted debt)\nline three harmless\nline four is a brand new neutral line\nline five is a NEW leak: %s\n' "$_rebrand19" "$_rebrand19" >"$T19/debt.txt"
git -C "$T19" add debt.txt
ERR19B="$(git -C "$T19" commit -m "add a new leak line" 2>&1)"
RC19B=$?
check_exit "committing a NEW old-name line is still BLOCKED by the real pre-commit hook" 1 "$RC19B"
echo "$ERR19B" | grep -q "BLOCKED" && ok "blocked new-leak commit prints a BLOCKED message" || bad "blocked new-leak commit message" "$ERR19B"

echo "== pre-push: preserved scrub-check-before-push behavior (byte-identical mechanism) =="
T5="$(new_temp_repo)"
require_temp_repo T5
(cd "$T5" && bash "$INSTALLER" >/dev/null 2>&1)
BARE="$SCRATCH/bare-remote.git"
git init -q --bare "$BARE"
git -C "$T5" remote add origin "$BARE"
printf 'clean, harmless content\n' >"$T5/f.txt"
git -C "$T5" add f.txt
git -C "$T5" commit -q -m "seed" >/dev/null 2>&1
git -C "$T5" push -q origin HEAD >/dev/null 2>"$SCRATCH/push1"
check_exit "clean push through the (unmodified-mechanism) pre-push hook succeeds" 0 "$?"

# A leak committed with --no-verify (bypassing pre-commit) must still be
# caught at PUSH time — scrub-check.sh (unlike pre-commit's --staged loop)
# scans the FULL tracked tree, catching anything already sitting in history
# by the time a push is attempted.
printf 'leftover pre-rebrand name: tor""valdsen\n' | tr -d '"' >"$T5/leftover.txt"
git -C "$T5" add leftover.txt
git -C "$T5" commit -q --no-verify -m "bypass pre-commit on purpose (test)" >/dev/null 2>&1
git -C "$T5" push -q origin HEAD >/dev/null 2>"$SCRATCH/push2"
check_exit "push of a --no-verify-committed rebrand-term leak is blocked by pre-push" 1 "$?"
grep -q "BLOCKED" "$SCRATCH/push2" && ok "blocked push prints a BLOCKED message" || bad "blocked push message" "$(cat "$SCRATCH/push2")"

echo "== pre-merge-commit: a conflict-free merge injecting a vault-registered term is blocked (M7) =="
# git invokes pre-merge-commit, NOT pre-commit, for a merge that succeeds
# automatically with no conflict (confirmed empirically for this task, see
# install-git-hooks.sh's own header) — this is the gap M7 closes. --no-ff
# forces a real merge commit even though this merge would otherwise
# fast-forward, so pre-merge-commit is guaranteed to fire.
T17="$(new_temp_repo)"
require_temp_repo T17
(cd "$T17" && bash "$INSTALLER" >/dev/null 2>&1)
DEFBR17="$(git -C "$T17" symbolic-ref --short HEAD)"
VDIR17="$(mktemp -d "$SCRATCH/vault.XXXXXX")"
CLAUDE_VAULT_DIR="$VDIR17" bash "$T17/scripts/vault/vault.sh" init >/dev/null 2>&1
CLAUDE_VAULT_DIR="$VDIR17" bash "$T17/scripts/vault/vault.sh" add project "SynthMergeProbeCorp" --group mergeprobe >/dev/null 2>&1
printf 'base content\n' >"$T17/base.txt"
git -C "$T17" add base.txt
git -C "$T17" commit -q -m "base" >/dev/null 2>&1
git -C "$T17" checkout -q -b topic
printf 'const owner = "SynthMergeProbeCorp";\n' >"$T17/topic-file.txt"
git -C "$T17" add topic-file.txt
git -C "$T17" commit -q -m "topic change with a leak" >/dev/null 2>&1
git -C "$T17" checkout -q "$DEFBR17"
printf 'main-only content\n' >"$T17/main-only.txt"
git -C "$T17" add main-only.txt
git -C "$T17" commit -q -m "main change" >/dev/null 2>&1
ERR17="$(CLAUDE_VAULT_DIR="$VDIR17" git -C "$T17" merge --no-ff -m "merge topic" topic 2>&1)"
RC17=$?
check_exit "conflict-free merge injecting a vault-registered term is blocked by pre-merge-commit" 1 "$RC17"
echo "$ERR17" | grep -q "BLOCKED" && ok "blocked merge prints a BLOCKED message" || bad "blocked merge message" "$ERR17"

echo "== pre-merge-commit: a conflict-free merge with no leaks succeeds (M7 positive control) =="
T18="$(new_temp_repo)"
require_temp_repo T18
(cd "$T18" && bash "$INSTALLER" >/dev/null 2>&1)
DEFBR18="$(git -C "$T18" symbolic-ref --short HEAD)"
printf 'base content\n' >"$T18/base.txt"
git -C "$T18" add base.txt
git -C "$T18" commit -q -m "base" >/dev/null 2>&1
git -C "$T18" checkout -q -b topic
printf 'harmless topic content\n' >"$T18/topic-file.txt"
git -C "$T18" add topic-file.txt
git -C "$T18" commit -q -m "topic change" >/dev/null 2>&1
git -C "$T18" checkout -q "$DEFBR18"
printf 'main-only content\n' >"$T18/main-only.txt"
git -C "$T18" add main-only.txt
git -C "$T18" commit -q -m "main change" >/dev/null 2>&1
git -C "$T18" merge --no-ff -m "merge topic" topic >/dev/null 2>"$SCRATCH/err18"
check_exit "clean merge with no leaks succeeds through pre-merge-commit" 0 "$?"

echo "== installer: a foreign pre-commit is NOT overwritten without --force (whole run aborts) =="
T6="$(new_temp_repo)"
require_temp_repo T6
HOOKS_DIR_T6="$(git -C "$T6" rev-parse --git-path hooks)"
mkdir -p "$T6/$HOOKS_DIR_T6"
printf '#!/usr/bin/env bash\necho "foreign pre-commit"\n' >"$T6/$HOOKS_DIR_T6/pre-commit"
chmod +x "$T6/$HOOKS_DIR_T6/pre-commit"
FOREIGN_BEFORE="$(cat "$T6/$HOOKS_DIR_T6/pre-commit")"
(cd "$T6" && bash "$INSTALLER" >/dev/null 2>"$SCRATCH/err6")
check_exit "installer without --force aborts on a foreign pre-commit" 1 "$?"
grep -q "aborting" "$SCRATCH/err6" && ok "abort message explains why" || bad "abort message" "$(cat "$SCRATCH/err6")"
FOREIGN_AFTER="$(cat "$T6/$HOOKS_DIR_T6/pre-commit")"
[[ "$FOREIGN_BEFORE" == "$FOREIGN_AFTER" ]] && ok "foreign pre-commit content is untouched after the aborted run" || bad "foreign pre-commit" "was overwritten despite the abort"
[[ ! -f "$T6/$HOOKS_DIR_T6/pre-push" ]] && ok "pre-push was NOT written either (abort happens before pass 3, no partial install)" || bad "pre-push" "unexpectedly written despite the abort on pre-commit"
[[ ! -f "$T6/$HOOKS_DIR_T6/pre-merge-commit" ]] && ok "pre-merge-commit was NOT written either (abort happens before pass 3, no partial install)" || bad "pre-merge-commit" "unexpectedly written despite the abort on pre-commit"

echo "== installer --force: foreign pre-commit is backed up (numbered) and replaced =="
(cd "$T6" && bash "$INSTALLER" --force >/dev/null 2>"$SCRATCH/err6force")
check_exit "installer --force succeeds despite the foreign pre-commit" 0 "$?"
[[ -f "$T6/$HOOKS_DIR_T6/pre-commit.foreign-backup.1" ]] && ok "foreign pre-commit backed up to a numbered file" || bad "foreign backup" "not found"
BACKUP_CONTENT="$(cat "$T6/$HOOKS_DIR_T6/pre-commit.foreign-backup.1")"
[[ "$BACKUP_CONTENT" == "$FOREIGN_BEFORE" ]] && ok "the backup preserves the foreign hook's original content" || bad "backup content" "mismatch"
grep -qF "Installed by scripts/install-git-hooks.sh" "$T6/$HOOKS_DIR_T6/pre-commit" && ok "pre-commit now carries our marker after --force" || bad "post-force pre-commit" "marker missing"
[[ -x "$T6/$HOOKS_DIR_T6/pre-merge-commit" ]] && ok "pre-merge-commit installed too after --force (no --only given, same group as pre-commit)" || bad "post-force pre-merge-commit" "missing"

echo "== installer: aborts if core.hooksPath is already set =="
T7="$(new_temp_repo)"
require_temp_repo T7
git -C "$T7" config --local core.hooksPath "some/other/dir"
(cd "$T7" && bash "$INSTALLER" >/dev/null 2>"$SCRATCH/err7")
check_exit "installer aborts when core.hooksPath is already set" 1 "$?"
grep -q "core.hooksPath" "$SCRATCH/err7" && ok "abort message names core.hooksPath" || bad "hooksPath abort message" "$(cat "$SCRATCH/err7")"
HOOKS_DIR_T7="$(git -C "$T7" rev-parse --git-path hooks)"
[[ ! -f "$T7/$HOOKS_DIR_T7/pre-commit" ]] && ok "nothing written to .git/hooks/ when core.hooksPath blocks the install" || bad "hooksPath-blocked install" "pre-commit was written anyway"
[[ ! -f "$T7/$HOOKS_DIR_T7/pre-merge-commit" ]] && ok "pre-merge-commit also not written when core.hooksPath blocks the install" || bad "hooksPath-blocked install" "pre-merge-commit was written anyway"

echo "== installer --uninstall: removes only OUR hooks, never a foreign one =="
T8="$(new_temp_repo)"
require_temp_repo T8
(cd "$T8" && bash "$INSTALLER" >/dev/null 2>&1)
HOOKS_DIR_T8="$(git -C "$T8" rev-parse --git-path hooks)"
printf '#!/usr/bin/env bash\necho "foreign pre-push, installed by hand"\n' >"$T8/$HOOKS_DIR_T8/pre-push"
chmod +x "$T8/$HOOKS_DIR_T8/pre-push"
(cd "$T8" && bash "$INSTALLER" --uninstall >/dev/null 2>&1)
check_exit "--uninstall exits 0" 0 "$?"
[[ ! -f "$T8/$HOOKS_DIR_T8/pre-commit" ]] && ok "--uninstall removed our pre-commit" || bad "uninstall pre-commit" "still present"
[[ ! -f "$T8/$HOOKS_DIR_T8/pre-merge-commit" ]] && ok "--uninstall removed our pre-merge-commit" || bad "uninstall pre-merge-commit" "still present"
[[ -f "$T8/$HOOKS_DIR_T8/pre-push" ]] && ok "--uninstall left the (now-foreign) pre-push untouched" || bad "uninstall pre-push" "foreign hook was removed"

echo "== installer --only pre-commit: installs pre-commit + pre-merge-commit, pre-push stays absent =="
T11="$(new_temp_repo)"
require_temp_repo T11
(cd "$T11" && bash "$INSTALLER" --only pre-commit >/dev/null 2>&1)
check_exit "installer --only pre-commit exits 0" 0 "$?"
HOOKS_DIR_T11="$(git -C "$T11" rev-parse --git-path hooks)"
[[ -x "$T11/$HOOKS_DIR_T11/pre-commit" ]] && ok "--only pre-commit installs an executable pre-commit" || bad "--only pre-commit install" "pre-commit missing/not executable"
[[ -x "$T11/$HOOKS_DIR_T11/pre-merge-commit" ]] && ok "--only pre-commit ALSO installs an executable pre-merge-commit" || bad "--only pre-commit install" "pre-merge-commit missing/not executable"
[[ ! -e "$T11/$HOOKS_DIR_T11/pre-push" ]] && ok "--only pre-commit leaves pre-push absent" || bad "--only pre-commit scope" "pre-push was written too"

echo "== installer --only pre-push: installs pre-push only, pre-commit + pre-merge-commit stay absent =="
T12="$(new_temp_repo)"
require_temp_repo T12
(cd "$T12" && bash "$INSTALLER" --only pre-push >/dev/null 2>&1)
check_exit "installer --only pre-push exits 0" 0 "$?"
HOOKS_DIR_T12="$(git -C "$T12" rev-parse --git-path hooks)"
[[ -x "$T12/$HOOKS_DIR_T12/pre-push" ]] && ok "--only pre-push installs an executable pre-push" || bad "--only pre-push install" "pre-push missing/not executable"
[[ ! -e "$T12/$HOOKS_DIR_T12/pre-commit" ]] && ok "--only pre-push leaves pre-commit absent" || bad "--only pre-push scope" "pre-commit was written too"
[[ ! -e "$T12/$HOOKS_DIR_T12/pre-merge-commit" ]] && ok "--only pre-push leaves pre-merge-commit absent" || bad "--only pre-push scope" "pre-merge-commit was written too"

echo "== installer --uninstall --only pre-commit: removes pre-commit + pre-merge-commit, pre-push stays installed =="
T13="$(new_temp_repo)"
require_temp_repo T13
(cd "$T13" && bash "$INSTALLER" >/dev/null 2>&1)
HOOKS_DIR_T13="$(git -C "$T13" rev-parse --git-path hooks)"
(cd "$T13" && bash "$INSTALLER" --uninstall --only pre-commit >/dev/null 2>&1)
check_exit "installer --uninstall --only pre-commit exits 0" 0 "$?"
[[ ! -f "$T13/$HOOKS_DIR_T13/pre-commit" ]] && ok "--uninstall --only pre-commit removed pre-commit" || bad "--uninstall --only pre-commit" "pre-commit still present"
[[ ! -f "$T13/$HOOKS_DIR_T13/pre-merge-commit" ]] && ok "--uninstall --only pre-commit ALSO removed pre-merge-commit" || bad "--uninstall --only pre-commit" "pre-merge-commit still present"
[[ -x "$T13/$HOOKS_DIR_T13/pre-push" ]] && ok "--uninstall --only pre-commit left pre-push installed" || bad "--uninstall --only pre-commit scope" "pre-push was removed too"

echo "== installer: unrecognized --only value is rejected, nothing written =="
T14="$(new_temp_repo)"
require_temp_repo T14
(cd "$T14" && bash "$INSTALLER" --only bogus-hook >/dev/null 2>"$SCRATCH/err14")
check_exit "installer --only bogus-hook exits 1" 1 "$?"
grep -qi -- "--only" "$SCRATCH/err14" && ok "unrecognized --only value error message names --only" || bad "unrecognized --only message" "$(cat "$SCRATCH/err14")"
HOOKS_DIR_T14="$(git -C "$T14" rev-parse --git-path hooks)"
[[ ! -e "$T14/$HOOKS_DIR_T14/pre-commit" ]] && ok "unrecognized --only value writes no pre-commit" || bad "unrecognized --only value" "pre-commit was written anyway"
[[ ! -e "$T14/$HOOKS_DIR_T14/pre-push" ]] && ok "unrecognized --only value writes no pre-push" || bad "unrecognized --only value" "pre-push was written anyway"
[[ ! -e "$T14/$HOOKS_DIR_T14/pre-merge-commit" ]] && ok "unrecognized --only value writes no pre-merge-commit" || bad "unrecognized --only value" "pre-merge-commit was written anyway"

echo "== installer: refuses to run in a repo without the scripts/vault/lib.sh marker =="
T15="$(mktemp -d "$SCRATCH/repo.XXXXXX")"
if [ -z "$T15" ] || [ ! -d "$T15" ]; then
    echo "git-hooks-regression: FATAL — mktemp failed to create T15's dir (got: '$T15')." >&2
    exit 1
fi
git init -q "$T15"
git -C "$T15" config user.email "test@example.com"
git -C "$T15" config user.name "Test User"
require_temp_repo T15
(cd "$T15" && bash "$INSTALLER" >/dev/null 2>"$SCRATCH/err15")
check_exit "installer aborts in a repo without scripts/vault/lib.sh" 1 "$?"
grep -qi "vault/lib.sh" "$SCRATCH/err15" && ok "no-marker abort message names scripts/vault/lib.sh" || bad "no-marker abort message" "$(cat "$SCRATCH/err15")"
HOOKS_DIR_T15="$(git -C "$T15" rev-parse --git-path hooks)"
[[ ! -e "$T15/$HOOKS_DIR_T15/pre-commit" ]] && ok "no-marker repo gets no pre-commit written" || bad "no-marker install" "pre-commit was written anyway"
[[ ! -e "$T15/$HOOKS_DIR_T15/pre-push" ]] && ok "no-marker repo gets no pre-push written" || bad "no-marker install" "pre-push was written anyway"
[[ ! -e "$T15/$HOOKS_DIR_T15/pre-merge-commit" ]] && ok "no-marker repo gets no pre-merge-commit written" || bad "no-marker install" "pre-merge-commit was written anyway"

echo "== tripwire: this suite must never touch the REAL repo's .git/hooks/ =="
REAL_HOOKS_AFTER="$(snapshot_real_hooks)"
if [ "$REAL_HOOKS_BEFORE" = "$REAL_HOOKS_AFTER" ]; then
    ok "real repo's .git/hooks/ (non-.sample, name+mtime+content) is unchanged by this entire suite"
else
    bad "real repo's .git/hooks/ unchanged" "BEFORE=[$REAL_HOOKS_BEFORE] AFTER=[$REAL_HOOKS_AFTER] — THIS SUITE WROTE INTO THE REAL REPO'S HOOKS DIR"
fi

echo ""
echo "git-hooks-regression: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
