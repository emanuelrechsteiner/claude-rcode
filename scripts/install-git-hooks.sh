#!/usr/bin/env bash
# install-git-hooks.sh — wire scripts/scrub-check.sh (pre-push) and
# scripts/git-hooks/pre-commit (pre-commit AND pre-merge-commit, IMP-219)
# into this repo's local git hooks under .git/hooks/. Run once after cloning:
#
#   bash scripts/install-git-hooks.sh
#
# Idempotent when re-run against hooks this script installed: overwrites
# them with the current template version, no backup needed (it's already
# our own generated content). If a hook exists that this script did NOT
# install (no marker comment — e.g. a hook from another tool, or
# hand-written), the script ABORTS rather than clobbering it silently — and
# does so BEFORE writing anything, checking all in-scope hooks first, so a
# foreign pre-commit can never be masked by a pre-push (or pre-merge-commit)
# that already got written.
# Use:
#
#   bash scripts/install-git-hooks.sh --force
#
# to intentionally replace a foreign hook — this backs up the foreign hook
# to a numbered file first, then installs. --force applies uniformly to
# whichever of the in-scope hooks turns out to be foreign.
#
#   bash scripts/install-git-hooks.sh --uninstall
#
# removes only hooks THIS script installed (marker match); a foreign hook
# at any of the paths is reported and left untouched.
#
#   bash scripts/install-git-hooks.sh --only pre-commit
#   bash scripts/install-git-hooks.sh --only pre-push
#   bash scripts/install-git-hooks.sh --uninstall --only pre-commit
#
# restricts install/--uninstall to one GROUP of the two gates (IMP-219,
# 2026-09-25; group widened same day, plan §"Auftrag" item 2): `--only
# pre-commit` installs/removes BOTH .git/hooks/pre-commit AND
# .git/hooks/pre-merge-commit together (they run the identical versioned
# scripts/git-hooks/pre-commit logic — see that file's own header, and the
# PRE_MERGE_COMMIT_CONTENT heredoc below, for why a merge needs its own
# entry point); `--only pre-push` still means pre-push alone. Whichever
# group is NOT selected is left exactly as it was — not written, not checked
# for a foreign conflict, not removed. Use in a repo that should only ever
# run one of the two gates (e.g. a private working repo wants only the
# commit-time group; the pre-push scrub gate belongs to the public-facing
# contribution path — see CONTRIBUTING.md / .github/workflows/scrub-check.yml).
# Without --only, all three hooks are installed/removed together, as before.
# An unrecognized --only value aborts (exit 1) before touching anything.
#
# WHY pre-merge-commit EXISTS AT ALL (plan §"Auftrag" item 2, "M7"): git
# invokes pre-commit only for an explicit `git commit`. When `git merge` (or
# a `git pull` that performs a merge) succeeds AUTOMATICALLY — no conflict,
# so git itself creates the merge commit — git instead invokes the separate
# pre-merge-commit hook; pre-commit is never called for that path. Confirmed
# empirically in a disposable temp repo (git 2.51.0, this task, no assumption
# taken from documentation alone): `git merge --no-ff` with no conflicts
# fired ONLY pre-merge-commit, never pre-commit. A CONFLICTED merge is
# unaffected by any of this — the user resolves it and runs a plain `git
# commit`, which already goes through the existing pre-commit hook unchanged.
#
# WHAT REMAINS UNCOVERED — checked empirically, not fixed here (git 2.51.0,
# disposable temp repos, this task): a conflict-free `git cherry-pick` and a
# conflict-free `git rebase` (default/sequencer backend) fire NEITHER
# pre-commit NOR pre-merge-commit — git's replay-and-commit step for both
# bypasses the commit-hook machinery entirely when nothing needs manual
# resolution. Resuming after a CONFLICT differs between the two and is worth
# recording precisely: `git cherry-pick --continue` DOES fire pre-commit (its
# continuation routes through a real `git commit`), but `git rebase
# --continue` does NOT (confirmed by direct comparison in the same session —
# this is not the same code path as cherry-pick's continuation, despite the
# similar CLI surface). Net effect: a leak introduced only via cherry-pick or
# rebase — clean or conflicted — currently reaches the repository with no
# gate from this script's hooks. Git provides no per-replayed-commit hook for
# either command (the existing `pre-rebase` hook fires once, before replay
# starts, with no view of the eventual diff) — closing this gap is out of
# scope for the current task and is not attempted here; flagged for the next
# review wave instead of silently claimed as covered.
#
# Refuses to run at all (exit 1) unless the repo it resolved to has
# scripts/vault/lib.sh — the framework-repo marker from
# plans/vault-by-design-2026-09-25.md §7.6. This is a safety floor, not a
# feature check: without it, a caller that lands here with an empty or
# unset working-directory variable (bash's `cd ""` is a silent, successful
# no-op, NOT an error — it leaves you in whatever directory you already
# were) would have this script resolve REPO_ROOT from ITS OWN cwd and
# install real hooks into whatever repo that happens to be. The marker check
# cannot fix a caller that passes a bad path, but it makes this script
# refuse to act as an accidental installer into an unrelated repo.
#
# core.hooksPath is NEVER set by this script (corrected 2026-09-25, IMP-219
# — an earlier draft of this task briefly used `git config core.hooksPath`
# instead of this direct-write mechanism; that draft is not what shipped).
# Setting core.hooksPath makes git ignore .git/hooks/ ENTIRELY, which would
# silently disable both the pre-existing pre-push gate and any other tool's
# hooks in that directory — this script aborts instead the moment it
# detects core.hooksPath already set, rather than writing hooks nothing
# would ever run.
#
# Referenced by CONTRIBUTING.md, .github/workflows/scrub-check.yml, and
# scripts/scrub-check.sh's own header comment — keep behavior compatible
# with what those describe.
#
# Safe to run from any subdirectory of the repo.
set -euo pipefail

FORCE=0
UNINSTALL=0
ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        --only)
            shift
            if [ $# -eq 0 ]; then
                echo "install-git-hooks: --only requires a value: pre-commit (also covers" >&2
                echo "  pre-merge-commit) or pre-push" >&2
                exit 1
            fi
            ONLY="$1"
            shift
            ;;
        *)
            echo "install-git-hooks: unrecognized argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ -n "$ONLY" ]; then
    case "$ONLY" in
        pre-commit|pre-push) ;;
        *)
            echo "install-git-hooks: --only must be 'pre-commit' or 'pre-push', got: '$ONLY'" >&2
            exit 1
            ;;
    esac
fi

# should_process <name> — true (0) iff --only was not given, or --only names
# the GROUP this hook belongs to. Two groups: "pre-commit" covers both
# .git/hooks/pre-commit and .git/hooks/pre-merge-commit (same versioned
# logic, same commit-time gate — see the header comment); "pre-push" covers
# only itself. Every place below that touches a specific hook checks this
# first, so --only pre-commit never so much as inspects pre-push (no
# foreign-hook check, no backup, no write, no removal, no summary line) —
# and --only pre-push never touches pre-merge-commit either.
should_process() {
    local name="$1"
    [ -n "$ONLY" ] || return 0
    case "$ONLY" in
        pre-commit) [ "$name" = "pre-commit" ] || [ "$name" = "pre-merge-commit" ] ;;
        pre-push) [ "$name" = "pre-push" ] ;;
    esac
}

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
    echo "install-git-hooks: not inside a git repository — aborting" >&2
    exit 1
fi
cd "$REPO_ROOT"

# Framework-repo marker (plans/vault-by-design-2026-09-25.md §7.6): refuse to
# touch ANY repo's .git/hooks/ unless the resolved REPO_ROOT is (a clone of)
# this framework repo. See the header comment for why this matters — it is
# the defense-in-depth half of the fix for a caller landing here with an
# empty/unset working-directory variable.
if [ ! -f "$REPO_ROOT/scripts/vault/lib.sh" ]; then
    echo "install-git-hooks: refusing to run — '$REPO_ROOT' does not look like" >&2
    echo "  the claude-code-config framework repo (scripts/vault/lib.sh is missing" >&2
    echo "  there). This is a safety check, not a bug: it exists so that this" >&2
    echo "  script can never install or remove hooks in an unrelated repo just" >&2
    echo "  because it happened to be invoked from inside one." >&2
    exit 1
fi

if [ "$UNINSTALL" -ne 1 ]; then
    EXISTING_HOOKSPATH="$(git config --local --get core.hooksPath 2>/dev/null || true)"
    if [ -n "$EXISTING_HOOKSPATH" ]; then
        echo "install-git-hooks: core.hooksPath is set to '$EXISTING_HOOKSPATH' — git" >&2
        echo "  would never read .git/hooks/, so installing there would be silently" >&2
        echo "  inert. Aborting rather than writing hooks nothing will ever run." >&2
        echo "  Fix: unset it (git config --local --unset core.hooksPath) if that" >&2
        echo "  value is stale, or install your hooks into '$EXISTING_HOOKSPATH' instead." >&2
        exit 1
    fi
fi

HOOKS_DIR="$(git rev-parse --git-path hooks)"
mkdir -p "$HOOKS_DIR"

# Marker string embedded in every hook this script generates (see the
# heredocs below). Used to tell "a hook we installed, safe to overwrite"
# apart from "a foreign hook, do not touch without --force".
HOOK_MARKER="Installed by scripts/install-git-hooks.sh"

# is_foreign <name> — true (0) iff $HOOKS_DIR/<name> exists and does NOT
# carry our marker.
is_foreign() {
    local target="$HOOKS_DIR/$1"
    [ -f "$target" ] || return 1
    grep -qF "$HOOK_MARKER" "$target" 2>/dev/null && return 1
    return 0
}

uninstall_hook() { # <name> — removes ONLY if it carries our marker.
    # NOTE: bash 3.2 does NOT make an earlier name in a multi-assignment
    # `local` statement visible to a later one in THAT SAME statement (it
    # errors "unbound variable" under set -u) — each assignment must be its
    # own statement whenever a later one depends on an earlier one.
    local name="$1"
    local target="$HOOKS_DIR/$name"
    if [ ! -f "$target" ]; then
        echo "install-git-hooks: $name — nothing installed, nothing to remove"
        return 0
    fi
    if is_foreign "$name"; then
        echo "install-git-hooks: $name — left untouched (foreign hook, not ours to remove)"
    else
        rm -f "$target"
        echo "install-git-hooks: $name — removed (was ours)"
    fi
}

if [ "$UNINSTALL" -eq 1 ]; then
    should_process "pre-push" && uninstall_hook "pre-push"
    should_process "pre-commit" && uninstall_hook "pre-commit"
    should_process "pre-merge-commit" && uninstall_hook "pre-merge-commit"
    exit 0
fi

# ── Pass 1: check all in-scope hooks for a foreign, unforced conflict
#    BEFORE writing anything — a strict abort must mean nothing partial
#    happened, not "pre-push already got overwritten before we noticed
#    pre-commit was foreign". Under --only, a hook NOT in the selected
#    group is skipped here too — it is not being touched this run, so a
#    foreign hook sitting at that path is none of this run's business. ───
for name in pre-push pre-commit pre-merge-commit; do
    should_process "$name" || continue
    if is_foreign "$name" && [ "$FORCE" -ne 1 ]; then
        echo "install-git-hooks: an existing $name hook at $HOOKS_DIR/$name was NOT" >&2
        echo "  installed by this script (no marker comment found) — aborting to" >&2
        echo "  avoid silently overwriting it." >&2
        echo "" >&2
        echo "  Re-run with --force to replace it (a numbered backup of the" >&2
        echo "  existing hook is written first): bash scripts/install-git-hooks.sh --force" >&2
        exit 1
    fi
done

# ── Pass 2: back up any foreign hook (only reachable here under --force). ──
backup_if_foreign() { # <name>
    local name="$1"
    local target="$HOOKS_DIR/$name"
    is_foreign "$name" || return 0
    local n=1 backup="$target.foreign-backup.1"
    while [ -e "$backup" ]; do
        n=$((n + 1))
        backup="$target.foreign-backup.$n"
    done
    cp "$target" "$backup"
    echo "install-git-hooks: --force given — existing foreign $name hook backed up to $backup"
}
should_process "pre-push" && backup_if_foreign "pre-push"
should_process "pre-commit" && backup_if_foreign "pre-commit"
should_process "pre-merge-commit" && backup_if_foreign "pre-merge-commit"

# ── Pass 3: write all in-scope hooks. ───────────────────────────────────
# Logged override for the "gate script missing" branches below (IMP-240): the
# generated hooks never recommend --no-verify; a deliberate skip needs a reason,
# which is appended to <git-common-dir>/vault-bypass.log before the hook exits 0.
BYPASS_SNIPPET=$(cat <<'SNIP'
if [ -n "$(printf '%s' "${VAULT_PRECOMMIT_BYPASS:-}" | tr -d '[:space:]')" ]; then
  printf '%s\t__NAME__\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$VAULT_PRECOMMIT_BYPASS" >> "$(cd "$(git rev-parse --git-common-dir)" && pwd)/vault-bypass.log" || exit 1
  echo "__NAME__: gate script missing, BYPASSED via VAULT_PRECOMMIT_BYPASS (logged)" >&2
  exit 0
fi
SNIP
)

PRE_PUSH_CONTENT=$(cat <<HOOK
#!/usr/bin/env bash
# ${HOOK_MARKER} — do not edit by hand, re-run
# that script to update. Blocks the push if scripts/scrub-check.sh finds a
# secret, personal-data fragment, or pre-rebrand name leftover.
set -euo pipefail
REPO_ROOT="\$(git rev-parse --show-toplevel)"
if [ -x "\$REPO_ROOT/scripts/scrub-check.sh" ]; then
  "\$REPO_ROOT/scripts/scrub-check.sh" || {
    echo "" >&2
    echo "pre-push: BLOCKED by scripts/scrub-check.sh — fix the findings above, or" >&2
    echo "  add a reviewed exemption to scripts/scrub-allowlist.txt, then push again." >&2
    exit 1
  }
else
${BYPASS_SNIPPET//__NAME__/pre-push}
  echo "pre-push: BLOCKED — scripts/scrub-check.sh not found or not executable." >&2
  echo "  Restore it (git checkout -- scripts/scrub-check.sh), or for a deliberate, logged skip:" >&2
  echo "  VAULT_PRECOMMIT_BYPASS=\"<reason>\" git push ..." >&2
  exit 1
fi
HOOK
)

PRE_COMMIT_CONTENT=$(cat <<HOOK
#!/usr/bin/env bash
# ${HOOK_MARKER} — do not edit by hand, re-run
# that script to update. A THIN caller: the actual vault + scrub-check gate
# for staged content is the versioned scripts/git-hooks/pre-commit
# (IMP-219, plans/vault-by-design-2026-09-25.md §4.3) — kept there, not
# duplicated here, so a future change to the gate reaches every clone on
# its next 'git pull' with no re-run of this installer required.
set -euo pipefail
REPO_ROOT="\$(git rev-parse --show-toplevel)"
if [ -x "\$REPO_ROOT/scripts/git-hooks/pre-commit" ]; then
  exec "\$REPO_ROOT/scripts/git-hooks/pre-commit"
else
${BYPASS_SNIPPET//__NAME__/pre-commit}
  echo "" >&2
  echo "pre-commit: BLOCKED — scripts/git-hooks/pre-commit not found or not executable." >&2
  echo "  Restore it (git checkout -- scripts/git-hooks/pre-commit), or for a deliberate, logged skip:" >&2
  echo "  VAULT_PRECOMMIT_BYPASS=\"<reason>\" git commit ..." >&2
  exit 1
fi
HOOK
)

PRE_MERGE_COMMIT_CONTENT=$(cat <<HOOK
#!/usr/bin/env bash
# ${HOOK_MARKER} — do not edit by hand, re-run
# that script to update. A THIN caller, same pattern as pre-commit above:
# runs the SAME versioned scripts/git-hooks/pre-commit logic (IMP-219, plan
# item "M7"). git invokes THIS hook — not pre-commit — when 'git merge' (or
# a 'git pull' that performs a merge) succeeds automatically with no
# conflicts; a conflicted merge instead ends with a manual 'git commit',
# which the pre-commit hook above already covers unchanged.
set -euo pipefail
REPO_ROOT="\$(git rev-parse --show-toplevel)"
if [ -x "\$REPO_ROOT/scripts/git-hooks/pre-commit" ]; then
  exec "\$REPO_ROOT/scripts/git-hooks/pre-commit"
else
${BYPASS_SNIPPET//__NAME__/pre-merge-commit}
  echo "" >&2
  echo "pre-merge-commit: BLOCKED — scripts/git-hooks/pre-commit not found or not executable." >&2
  echo "  Restore it (git checkout -- scripts/git-hooks/pre-commit), or for a deliberate, logged skip:" >&2
  echo "  VAULT_PRECOMMIT_BYPASS=\"<reason>\" git merge ..." >&2
  exit 1
fi
HOOK
)

write_hook() { # <name> <content>
    local name="$1" content="$2" target="$HOOKS_DIR/$1"
    printf '%s\n' "$content" >"$target"
    chmod +x "$target"
    echo "install-git-hooks: $name hook installed at $target"
}
should_process "pre-push" && write_hook "pre-push" "$PRE_PUSH_CONTENT"
should_process "pre-commit" && write_hook "pre-commit" "$PRE_COMMIT_CONTENT"
should_process "pre-merge-commit" && write_hook "pre-merge-commit" "$PRE_MERGE_COMMIT_CONTENT"

should_process "pre-push" && echo "install-git-hooks: every 'git push' from this clone now runs scripts/scrub-check.sh first"
should_process "pre-commit" && echo "install-git-hooks: every 'git commit' from this clone now runs scripts/git-hooks/pre-commit first"
should_process "pre-merge-commit" && echo "install-git-hooks: every conflict-free 'git merge' from this clone now runs scripts/git-hooks/pre-commit first too"

# Explicit exit 0: without it, the script's own exit status would be
# whichever of the three guarded lines above ran LAST — under --only
# pre-push, that is the (correctly skipped) pre-merge-commit line, whose
# `should_process` returns false, which would make a fully successful
# install report exit 1.
exit 0
