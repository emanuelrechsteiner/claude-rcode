#!/bin/bash
# Vault Write Gate — PreToolUse on Write/Edit/MultiEdit (IMP-219, Welle 2 unit B)
# ─────────────────────────────────────────────────────────────────────────────
# WHY: the user's own instruction (2026-09-25,
# plans/vault-by-design-2026-09-25.md §0/§1): a real project/account name, a
# machine-specific path, or a personal ID must NEVER land in a versioned file
# of a Framework-repo clone (Bauhof, Haus, or a public clone) — such values
# are "P2 data" and belong ONLY in the per-machine vault
# (scripts/vault/, ${CLAUDE_VAULT_DIR:-~/.claude/vault}, gitignored). The
# writer here is a language model, so this is enforced mechanically, not by
# instruction alone (rules/slop-prevention.md).
#
# SCOPE: only the INCOMING text of a Write/Edit/MultiEdit call is inspected
# (tool_input.content / .new_string / .edits[].new_string, detected by INPUT
# SHAPE so a MultiEdit call is handled correctly regardless of what the
# settings.json matcher string actually dispatches on) — the file's EXISTING
# on-disk content is a separate concern (plan §4.2 point 3; the one-time
# rewrite of the existing tree is Welle 3).
#
# DELEGATION: no matcher is re-implemented here. This hook shells out to
# THIS REPO'S OWN scripts/vault/vault.sh, found RELATIVE TO THIS SCRIPT'S OWN
# LOCATION (not the target file's repo) — the hook is a single, globally
# registered PreToolUse hook (~/.claude/hooks/…) that can fire against any
# project on the machine, so it always uses its own co-located vault CLI
# (whichever copy of this repo the hook itself was deployed from), which in
# turn defaults to the ONE machine-global vault
# (rules/testing-quality.md "Verify Via the Same Code Path" — one matcher,
# not two).
#
# HYGIENE GATE, NOT THE CRITICAL FLOOR: infrastructure failures (jq missing,
# vault.sh missing/non-executable, garbage stdin, vault.sh internal error)
# fail OPEN with a loud stderr NOTE — this gate must never be the reason a
# legitimate write is blocked when it cannot actually check anything
# (rules/fail-loud.md: "fail loud, not fail closed").
#
# Bypass: CLAUDE_VAULT_GATE_OFF=1 — logged (file + timestamp, never the
# term), and only once scope is already established (not on every unrelated
# write while the flag happens to be set — the log line means "a check that
# would have run was skipped", not noise).
#
# Exit contract (PreToolUse): 0 = allow, 2 = block (stderr explains why).
set -u

INPUT=$(cat)

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT_SH="$HOOKS_DIR/../scripts/vault/vault.sh"
LOG="${CLAUDE_VAULT_GATE_LOG:-$HOME/.claude/global-observation/vault-gate.log}"
BYPASS=0
[ "${CLAUDE_VAULT_GATE_OFF:-0}" = "1" ] && BYPASS=1

# log_line <decision> [kind] [token] — NEVER pass a term. Only decisions that
# mean something ("block", "bypass") are persisted; a clean allow is not
# logged (it would flood the log on every ordinary write).
log_line() {
    mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
    printf '[%s] decision=%s file=%s kind=%s token=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${REL_FILE:-${FILE_PATH:-unknown}}" "${2:-}" "${3:-}" \
        >>"$LOG" 2>/dev/null || true
}

# infra_repeat_count <fired:0|1> — persistent counter of CONSECUTIVE
# infrastructure-NOTE occurrences ACROSS INVOCATIONS of this hook (a fresh
# process every call, so this cannot live in a shell variable) — same
# file-counter pattern as hooks/session-end-check.sh's alarm_repeat_count
# (rules/fail-loud.md, "Repetition Without Escalation Is Also Silence",
# IMP-164). fired=1 increments (creates the file at 1 if absent); fired=0 —
# a REAL vault.sh check ran to completion (RC 0 or 2), i.e. an inspection
# actually happened, whatever it found — deletes the file, so the next NOTE
# starts fresh at 1. Scope-exclusion exits (not a framework repo, gitignored
# + untracked, empty content, the CLAUDE_VAULT_GATE_OFF bypass) touch
# neither branch: they are not an inspection attempt, so not part of this
# alarm. Path overridable for regression tests.
INFRA_COUNTER_FILE="${CLAUDE_VAULT_GATE_INFRA_COUNTER:-$HOME/.claude/global-observation/.vault-gate-infra-repeat.txt}"
infra_repeat_count() {
    local fired="$1" prev=0 next
    mkdir -p "$(dirname "$INFRA_COUNTER_FILE")" 2>/dev/null || true
    if [ -f "$INFRA_COUNTER_FILE" ]; then
        prev=$(tr -d '[:space:]' <"$INFRA_COUNTER_FILE" 2>/dev/null)
        case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
    fi
    if [ "$fired" = "1" ]; then
        next=$((prev + 1))
        printf '%s\n' "$next" >"$INFRA_COUNTER_FILE" 2>/dev/null || true
        printf '%s' "$next"
    else
        rm -f "$INFRA_COUNTER_FILE" 2>/dev/null || true
        printf '%s' 0
    fi
}

# note_allow <message> — loud, non-blocking. This is a hygiene gate, not the
# CRITICAL floor (rules/agency-bands.md): a check that cannot run must not
# block a legitimate write. From the 3rd CONSECUTIVE infra-NOTE onward the
# message escalates instead of repeating unchanged (IMP-164) — an
# unresolved condition reported identically every time habituates the
# reader exactly like the staleness alarm in session-end-check.sh did
# before that fix.
note_allow() {
    local n
    n=$(infra_repeat_count 1)
    if [ "$n" -ge 3 ]; then
        echo "vault-write-gate: ESKALATION: Schreib-Tor seit $n Aufrufen ohne Prüfung — bash ~/.claude/scripts/vault/vault.sh doctor ausführen. Grund: $1." >&2
    else
        echo "vault-write-gate: NOTE — $1. Allowing (fail-open, hygiene gate)." >&2
    fi
    exit 0
}

command -v jq >/dev/null 2>&1 || note_allow "jq not found, cannot inspect content"
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || note_allow "stdin is not parseable JSON"

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE_PATH" ] || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
case "$FILE_PATH" in
    /*) : ;;
    *) [ -n "$CWD" ] && FILE_PATH="${CWD%/}/$FILE_PATH" ;;
esac

# MultiEdit is detected by SHAPE (an `edits` array), not by tool_name — the
# settings.json "Write|Edit" matcher string is not this hook's to change
# (out of scope for this task), and shape-detection works regardless of
# whatever tool_name actually reaches this script.
EDITS_TYPE=$(printf '%s' "$INPUT" | jq -r '(.tool_input.edits | type)' 2>/dev/null)
if [ "$EDITS_TYPE" = "array" ]; then
    CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.edits[]?.new_string // empty' 2>/dev/null)
else
    CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
fi
[ -n "$CONTENT" ] || exit 0

# ── 1) Framework-repo marker (plans/vault-by-design-2026-09-25.md §7.6,
#    superseding §4.2 step 1's original publish-manifest.txt marker):
#    <git-root-of-the-TARGET-file>/scripts/vault/lib.sh must exist. The
#    target file may not exist yet (a Write creating a new file) — walk up
#    to the nearest EXISTING ancestor directory before asking git for its
#    root, so this depends only on the TARGET's own location, never on this
#    hook process's own cwd (which could coincidentally be inside a
#    framework repo, e.g. under a test harness).
find_existing_dir() {
    local d="$1"
    while [ ! -d "$d" ] && [ "$d" != "/" ] && [ -n "$d" ]; do
        d="$(dirname "$d")"
    done
    [ -n "$d" ] && printf '%s' "$d" || printf '/'
}

# find_marked_git_root <start-dir> — the INNERMOST git root of <start-dir>
# may itself lack the marker while an ANCESTOR directory is a git root that
# HAS it (a nested/embedded/accidental `git init` below the real framework
# root — a submodule, or a stray repo — would otherwise leave everything
# under it invisible to this gate). Walk git roots upward: if the current
# root lacks the marker, jump to ITS PARENT directory and ask git again,
# until a marked root is found or / is reached. Prints the effective
# GIT_ROOT and returns 0, or returns 1 (prints nothing) if none is found.
find_marked_git_root() {
    local d="$1" root
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        root=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)
        if [ -n "$root" ] && [ -f "$root/scripts/vault/lib.sh" ]; then
            printf '%s' "$root"
            return 0
        fi
        if [ -n "$root" ]; then
            d=$(dirname "$root")
        else
            d=$(dirname "$d")
        fi
    done
    return 1
}

TARGET_DIR=$(dirname "$FILE_PATH")
EXISTING_DIR=$(find_existing_dir "$TARGET_DIR")
GIT_ROOT=$(find_marked_git_root "$EXISTING_DIR") || exit 0

if [ "${FILE_PATH:0:${#GIT_ROOT}}" = "$GIT_ROOT" ]; then
    REL_FILE="${FILE_PATH:$((${#GIT_ROOT} + 1))}"
else
    REL_FILE="$FILE_PATH"
fi

# ── 2) gitignored target → allow, UNLESS it is already tracked (git
#    ls-files --error-unmatch succeeds). A NEW .gitignore pattern does not
#    stop git from continuing to track/commit changes to a file already in
#    the index — check-ignore alone would silently exempt exactly that file
#    from this gate from then on, even though it keeps landing in every
#    future commit. A not-yet-existing file (a Write creating something
#    new) can never be tracked, so a genuinely new ignored file is
#    unaffected.
if git -C "$GIT_ROOT" check-ignore -q -- "$FILE_PATH" 2>/dev/null; then
    git -C "$GIT_ROOT" ls-files --error-unmatch -- "$REL_FILE" >/dev/null 2>&1 || exit 0
fi

# ── Bypass, checked only now that scope is established — the log line means
#    "a real check was skipped", not noise from every unrelated write.
if [ "$BYPASS" = "1" ]; then
    log_line "bypass"
    echo "vault-write-gate: BYPASSED via CLAUDE_VAULT_GATE_OFF=1 for $REL_FILE (logged)." >&2
    exit 0
fi

[ -x "$VAULT_SH" ] || note_allow "scripts/vault/vault.sh not found/executable at $VAULT_SH"

# ── 3) the ONE matcher — structural checks always run; vault-sourced checks
#    run when a vault is present (vault.sh's own fail-loud/not-fail-closed
#    behavior on a missing vault is unchanged here: it still checks
#    structurally and warns once on stderr, which we relay below).
#
#    --as "$REL_FILE" (scripts/vault/vault.sh, IMP-219 Gewerk A3): labels the
#    checked content with the REAL repo-relative path, so vault.sh's
#    allowlist/fixture-marker logic applies by path instead of the "-"
#    label a bare --stdin call always used. Confirmed end-to-end (see this
#    task's handback report): a */tests/*-path + fixture marker still
#    exempts STRUCTURAL findings, but per the narrowed policy no longer
#    exempts vault-sourced (Tresor) terms — a real name is reported even in
#    a marked test fixture. Not relevant to THIS gate's own inputs (it
#    checks in-flight new_string/content, not a real file's first 5 lines),
#    but load-bearing for scripts/git-hooks/pre-commit's per-file loop.
ERR_TMP=$(mktemp "${TMPDIR:-/tmp}/vault-gate-err.XXXXXX")
FINDINGS=$(printf '%s\n' "$CONTENT" | "$VAULT_SH" check --stdin --as "$REL_FILE" 2>"$ERR_TMP")
RC=$?
GATE_ERR=$(cat "$ERR_TMP" 2>/dev/null || true)
rm -f "$ERR_TMP"

case "$RC" in
    0)
        infra_repeat_count 0 >/dev/null
        [ -n "$GATE_ERR" ] && printf '%s\n' "$GATE_ERR" >&2
        exit 0
        ;;
    2)
        infra_repeat_count 0 >/dev/null
        [ -n "$GATE_ERR" ] && printf '%s\n' "$GATE_ERR" >&2
        echo "vault-write-gate: BLOCKED — real value(s) detected in text going into a tracked file of a framework repo: $REL_FILE" >&2
        while IFS=$'\t' read -r _lbl _ln kind term token; do
            [ -z "$kind" ] && continue
            if [ -n "$token" ]; then
                echo "  $kind: $term → $token" >&2
            else
                echo "  $kind: $term → Platzhalter verwenden" >&2
            fi
            log_line "block" "$kind" "$token"
        done <<<"$FINDINGS"
        echo "vault-write-gate: use a placeholder/vault token instead. A legitimate pattern definition can be exempted via scripts/scrub-allowlist.txt. Session bypass: CLAUDE_VAULT_GATE_OFF=1 (logged)." >&2
        exit 2
        ;;
    *)
        note_allow "vault.sh check reported an internal error (exit $RC)${GATE_ERR:+: $GATE_ERR}"
        ;;
esac
