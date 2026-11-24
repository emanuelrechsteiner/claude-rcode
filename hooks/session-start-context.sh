#!/bin/bash
# SessionStart hook — the path canon (workshop vs. live install), the pending
# acceptance check from the last deploy, a one-line R.Code pointer and the
# library hint. Working directory, project type and git branch are supplied by
# the harness and are not printed here.

CWD=$(pwd)

# ── Path canon: workshop vs. live install (IMP-162) ──
# 66 "File does not exist" errors over 37 sessions (August 2026 chat analysis,
# the largest single error class of the month) traced to two valid roots
# (workshop = working copy, everything happens here; live install = the
# installation Claude Code actually reads) plus two dead historical directory
# names the agent sometimes reconstructs from memory instead of reading.
# Typical fallout: "/Volumes/<VOLUME> 1/PROJECTS/Development/5_AI-APPS/…"
# (space instead of hyphen, underscore instead of hyphen). Emitted ONLY when
# this session's cwd is inside one of the two real roots, or is a git worktree of
# the workshop — silent in unrelated projects, so it never becomes noise there.
#
# Workshop-root resolution (IMP-219 — no hardcoded machine path in source):
#   1) CLAUDE_BAUHOF_ROOT already set in the environment (regression tests,
#      session env) wins outright.
#   2) else source ~/.claude/env.local.sh if present (machine-local,
#      gitignored — see templates/env.local.sh.template) and re-check.
#   3) still unset -> BAUHOF_RESOLVED=0. Print "Workshop: unknown" instead
#      of guessing — never fall back to a hardcoded default path
#      (rules/fail-loud.md).
# CLAUDE_HAUS_ROOT stays overridable via env for regression tests so the
# suite doesn't depend on this machine's real absolute paths.
BAUHOF_RESOLVED=1
# Remember the library dir as the ENVIRONMENT had it: sourcing env.local.sh below
# would overwrite it, and the environment must win (library hint, IMP-248).
KDIR_ENV="${CLAUDE_KNOWLEDGE_DIR:-}"
if [[ -z "${CLAUDE_BAUHOF_ROOT:-}" ]]; then
    # shellcheck disable=SC1091
    [[ -f "$HOME/.claude/env.local.sh" ]] && . "$HOME/.claude/env.local.sh"
fi
[[ -n "${CLAUDE_BAUHOF_ROOT:-}" ]] || BAUHOF_RESOLVED=0
BAUHOF_ROOT="${CLAUDE_BAUHOF_ROOT:-}"
HAUS_ROOT="${CLAUDE_HAUS_ROOT:-$HOME/.claude}"

IN_HAUS=0
[[ "$CWD" == "$HAUS_ROOT" || "$CWD" == "$HAUS_ROOT"/* ]] && IN_HAUS=1
# A git worktree of the workshop shares the workshop's common git directory.
# A directory that is not a repository, or a repository of another project, does not match.
is_bauhof_worktree() {
    local cwd_common bauhof_common
    cwd_common=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
    bauhof_common=$(git -C "$BAUHOF_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
    [[ -n "$cwd_common" && "$cwd_common" == "$bauhof_common" ]]
}

IN_BAUHOF=0
if [[ "$BAUHOF_RESOLVED" == "1" ]]; then
    [[ "$CWD" == "$BAUHOF_ROOT" || "$CWD" == "$BAUHOF_ROOT"/* ]] && IN_BAUHOF=1
    [[ "$IN_BAUHOF" == "0" ]] && is_bauhof_worktree && IN_BAUHOF=1
fi

if [[ "$IN_HAUS" == "1" || "$IN_BAUHOF" == "1" ]]; then
    echo ""
    echo "📌 Path canon (Two-Location Rule, IMP-162 — 66 file-does-not-exist errors/37 sessions in Aug 2026):"
    if [[ "$BAUHOF_RESOLVED" == "1" ]]; then
        echo "   Workshop (working copy, commit here):  $BAUHOF_ROOT"
    else
        echo "   Workshop: unknown — create ~/.claude/env.local.sh (template: templates/env.local.sh.template)"
    fi
    echo "   Live install (installation, do NOT edit by hand): $HAUS_ROOT"
    echo "   Historical names (pre-rebrand) — no longer exist."
fi

# ── Pending acceptance check from the last deploy (IMP-147) ──
# deploy-to-live.sh writes this file after a config deploy with real
# new commits. If it's missing, this block prints exactly nothing (fail-loud:
# no noise, no silent special case).
PENDING_VERIFICATION="$HOME/.claude/pending-verification.md"
if [[ -f "$PENDING_VERIFICATION" ]]; then
    echo ""
    echo "⏳ Pending acceptance check from the last deploy — delete the file once review passes: rm ~/.claude/pending-verification.md"
    PV_LINES=$(wc -l < "$PENDING_VERIFICATION" | tr -d ' ')
    if [[ "$PV_LINES" -gt 25 ]]; then
        head -25 "$PENDING_VERIFICATION"
        echo "… (truncated, $PV_LINES lines total — full file: $PENDING_VERIFICATION)"
    else
        cat "$PENDING_VERIFICATION"
    fi
fi

# ── R.Code pointer: one line, only when .rcode/ is present ──
# Opt-out: export CLAUDE_SESSION_NUDGE=0
if [[ "${CLAUDE_SESSION_NUDGE:-1}" != "0" && -d "$CWD/.rcode" ]]; then
    echo "🟢 R.Code project: start work through /team-lead; PROJECT-STATUS.md has the state."
fi

# ── Cross-project library hint (IMP-248): one line, ONLY when the mirror exists ──
# Deliberately OUTSIDE the CLAUDE_SESSION_NUDGE gate: the only condition is that
# the library exists. Fail-open by design: no CLAUDE_KNOWLEDGE_DIR / no
# mirror/README.md -> prints nothing, no error.
# CLAUDE_KNOWLEDGE_DIR: environment first, else ~/.claude/env.local.sh (subshell, -u/-e off).
KDIR="$KDIR_ENV"
if [[ -z "$KDIR" && -f "$HOME/.claude/env.local.sh" ]]; then
    # shellcheck disable=SC1091
    KDIR=$( set +u +e; . "$HOME/.claude/env.local.sh" >/dev/null 2>&1; printf '%s' "${CLAUDE_KNOWLEDGE_DIR:-}" )
fi
KDIR="${KDIR%/}"
if [[ -n "$KDIR" && -f "$KDIR/mirror/README.md" ]]; then
    KNOTES=$(find "$KDIR/mirror/memory" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    KDATE=$(sed -n 's/^.*Last run: \([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\).*$/\1/p' "$KDIR/mirror/README.md" | head -n 1)
    echo "📚 Library: $KNOTES cross-project memory notes mirrored ${KDATE:-(date unknown)}; before implementing in an unfamiliar area run: bash ~/.claude/scripts/knowledge-lookup.sh --stack  (or 2–4 keyword sets: --alt \"…\")"
fi

exit 0
