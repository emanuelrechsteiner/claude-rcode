#!/bin/bash
# Git state validation hook - prevents common git operation failures
# Run before git commit, push, merge, rebase operations
#
# Error patterns this hook prevents:
# 1. Stale .git/index.lock files blocking operations
# 2. Unresolved merge conflicts before commit
# 3. Operations on non-git directories
# 4. Uncommitted changes before dangerous operations

# Read JSON input from stdin (Claude Code standard).
# Previous version used "$1" which received the literal unexpanded "$tool_input"
# string — Claude Code does NOT substitute $tool_input in settings.json command.
# Fixed 2026-05-25 (hook audit).
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Early exit if not a git command
if [[ ! "$COMMAND" =~ ^git[[:space:]] ]]; then
    exit 0
fi

# Find git root
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ $? -ne 0 ]]; then
    # Not in a git repository - let git handle the error
    exit 0
fi

cd "$GIT_ROOT" || exit 0

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 1: Stale lock file detection
# ═══════════════════════════════════════════════════════════════════════════════
if [[ -f ".git/index.lock" ]]; then
    # Check if lock is stale (older than 5 minutes)
    if [[ "$(uname)" == "Darwin" ]]; then
        LOCK_AGE=$(( $(date +%s) - $(stat -f %m .git/index.lock 2>/dev/null || echo 0) ))
    else
        LOCK_AGE=$(( $(date +%s) - $(stat -c %Y .git/index.lock 2>/dev/null || echo 0) ))
    fi

    if [[ $LOCK_AGE -gt 300 ]]; then
        echo "⚠️  Stale git lock file detected (${LOCK_AGE}s old)" >&2
        echo "    Removing .git/index.lock..." >&2
        rm -f .git/index.lock
    else
        echo "❌ Git lock file exists (${LOCK_AGE}s old)" >&2
        echo "    Another git process may be running." >&2
        echo "    Wait or remove .git/index.lock manually if stuck." >&2
        exit 2
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 2: Merge conflict detection (before commit/push)
# ═══════════════════════════════════════════════════════════════════════════════
# ESCAPE HATCHES ARE NOT THE HAZARD (fixed 2026-08-02, live finding).
# --abort / --quit / --skip are how you LEAVE a conflicted state. The check below
# then finds the very conflicts an abort would clear, and blocks with exit 2 —
# trapping the user inside the situation this check exists to prevent. Observed
# live: `git rebase --abort` mid-conflict was blocked, twice, with no reason shown.
# --continue stays checked on purpose: continuing WITH unresolved conflicts is the
# real hazard, and that is exactly what the conflict scan below is for.
if [[ "$COMMAND" =~ (--abort|--quit|--skip)([[:space:]]|\"|\'|$) ]]; then
    exit 0
fi

if [[ "$COMMAND" =~ git\ (commit|push|rebase) ]]; then
    CONFLICT_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null)
    if [[ -n "$CONFLICT_FILES" ]]; then
        # All blocking output goes to STDERR: Claude Code surfaces stderr on exit 2.
        # On stdout the reason was swallowed and the user saw a bare
        # "No stderr output" — a veto without a stated cause (fail-loud.md).
        echo "❌ Unresolved merge conflicts detected:" >&2
        echo "$CONFLICT_FILES" | while read -r file; do
            echo "    - $file" >&2
        done
        echo "" >&2
        echo "    Resolve conflicts before proceeding." >&2
        echo "    To leave the conflicted state instead: git rebase --abort / git merge --abort" >&2
        exit 2
    fi

    # Also check for conflict markers in staged files
    MARKER_FILES=$(git diff --cached --name-only | xargs -I{} grep -l "^<<<<<<< \|^=======$\|^>>>>>>> " {} 2>/dev/null)
    if [[ -n "$MARKER_FILES" ]]; then
        echo "❌ Conflict markers found in staged files:" >&2
        echo "$MARKER_FILES" | while read -r file; do
            echo "    - $file" >&2
        done
        echo "" >&2
        echo "    Remove conflict markers before committing." >&2
        exit 2
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 3: Branch protection for dangerous operations
# ═══════════════════════════════════════════════════════════════════════════════
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)

if [[ "$COMMAND" =~ git\ (push\ --force|reset\ --hard|clean\ -fd) ]]; then
    if [[ "$CURRENT_BRANCH" =~ ^(main|master|production|release)$ ]]; then
        echo "⚠️  Dangerous operation on protected branch: $CURRENT_BRANCH" >&2
        echo "    Command: $COMMAND" >&2
        echo "    Please confirm this is intentional." >&2
        # Don't block - just warn (ask permission handles the rest)
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 4: Stash reminder before checkout/switch with changes
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$COMMAND" =~ git\ (checkout|switch) ]]; then
    UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ $UNCOMMITTED -gt 0 ]]; then
        echo "ℹ️  Note: $UNCOMMITTED uncommitted changes detected" >&2
        echo "    Consider stashing with: git stash push -m 'WIP'" >&2
        # Don't block - just inform
    fi
fi

# All checks passed
exit 0
