#!/bin/bash
# vault-check: fixtures (synthetic values only — invented stand-ins for structural/vault matching, never a real term)
#
# Regression suite for hooks/vault-write-gate.sh (IMP-219, Welle 2 unit B,
# plans/vault-by-design-2026-09-25.md §4.2). Runs ENTIRELY against a
# throwaway temp git repo + a throwaway CLAUDE_VAULT_DIR — never the real
# ~/.claude/vault and never this repo's own git state.
#
# The fixture marker above MUST close its parenthetical on the SAME line
# (plans/vault-by-design-2026-09-25.md §7.2), so a future repo-wide
# `vault.sh check` sweep over */tests/* does not flag this file's own
# literal "should structurally match" test payloads below.
#
# Usage: bash hooks/tests/vault-write-gate-regression.sh
set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$HOOKS_DIR/.." && pwd)"
GATE="$HOOKS_DIR/vault-write-gate.sh"
VAULT_SH="$REPO_ROOT/scripts/vault/vault.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# Redirect EVERY gate invocation's log (and infra-NOTE counter) to a temp
# path — never the real ~/.claude/global-observation/{vault-gate.log,
# .vault-gate-infra-repeat.txt}, even for the plain t() assertions above and
# below that don't otherwise care about either. The two log-content
# assertions further down, and the dedicated M4 counter sequence, point
# their own env var at OWN distinct files (which takes precedence for that
# one call only).
export CLAUDE_VAULT_GATE_LOG="$T/vault-gate-default.log"
export CLAUDE_VAULT_GATE_INFRA_COUNTER="$T/vault-gate-infra-counter-default.txt"

PASS=0
FAIL=0
N=0

# ── Temp vault, populated with a synthetic term (never appears in any real
#    ~/.claude/vault on any machine — this term exists only inside $VDIR). ──
VDIR="$T/vault"
SYNTH_TERM="SynthVaultGateProbeCorp"
CLAUDE_VAULT_DIR="$VDIR" bash "$VAULT_SH" init >/dev/null 2>&1
CLAUDE_VAULT_DIR="$VDIR" bash "$VAULT_SH" add project "$SYNTH_TERM" --group synthgateprobe >/dev/null 2>&1

# ── A framework-repo temp clone: just needs the §7.6 marker FILE to exist —
#    the gate only checks for its presence, and always uses its OWN
#    co-located vault.sh (found relative to $GATE, i.e. the real one above)
#    for the actual content check, never a per-target-repo copy. ──
FWREPO="$T/fwrepo"
mkdir -p "$FWREPO/scripts/vault" "$FWREPO/src"
: >"$FWREPO/scripts/vault/lib.sh"
git init -q "$FWREPO"
printf 'ignored.txt\n' >"$FWREPO/.gitignore"
: >"$FWREPO/ignored.txt"

# ── A NON-framework temp git repo (no §7.6 marker) and a plain non-git dir. ──
OTHERGIT="$T/othergit"
mkdir -p "$OTHERGIT/src"
git init -q "$OTHERGIT"

PLAINDIR="$T/plaindir/nested"
mkdir -p "$PLAINDIR"

payload_edit() { # file_path new_string
    jq -cn --arg fp "$1" --arg ns "$2" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"x", new_string:$ns}, session_id:"vault-gate-test"}'
}
payload_write() { # file_path content
    jq -cn --arg fp "$1" --arg c "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$c}, session_id:"vault-gate-test"}'
}
payload_multiedit() { # file_path new_string1 new_string2
    jq -cn --arg fp "$1" --arg n1 "$2" --arg n2 "$3" \
        '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[{old_string:"a",new_string:$n1},{old_string:"b",new_string:$n2}]}, session_id:"vault-gate-test"}'
}

t() { # desc, expected_exit, payload   (CLAUDE_VAULT_DIR etc. via env prefix on the caller)
    N=$((N + 1))
    local desc="$1" expected="$2" payload="$3"
    local err code
    printf '%s' "$payload" | "$GATE" >/dev/null 2>"$T/stderr"
    code=$?
    err=$(cat "$T/stderr" 2>/dev/null || true)
    if [ "$code" -eq "$expected" ]; then
        PASS=$((PASS + 1))
        printf '  ok %2d — %s\n' "$N" "$desc"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %2d — %s\n     expected=%s got=%s\n     err=%s\n' "$N" "$desc" "$expected" "$code" "$err"
    fi
}

echo "── vault-write-gate regression ─────────────────────────────────────────"

CLAUDE_VAULT_DIR="$VDIR" t \
    "Edit with a vault-registered synthetic term → block" 2 \
    "$(payload_edit "$FWREPO/src/a.ts" "const owner = \"$SYNTH_TERM\";")"

t "Write with a non-exempt /Users/<name>/… segment → block" 2 \
    "$(payload_write "$FWREPO/src/new.ts" "the path is /Users/synthfaketester/project")"

t "Write with the exempt placeholder /Users/<user>/x → allow" 0 \
    "$(payload_write "$FWREPO/src/new.ts" "the path is /Users/<user>/x")"

t "MultiEdit: 1st edit clean, 2nd edit has a structural finding → block" 2 \
    "$(payload_multiedit "$FWREPO/src/a.ts" "clean text here" "contact me at synthfaketester@realmail-nonexempt.tld")"

t "Write into a not-yet-existing subdir still resolves the framework repo → block" 2 \
    "$(CLAUDE_VAULT_DIR="$VDIR" true; payload_write "$FWREPO/brandnew/deep/newfile.ts" "path is /Users/synthfaketester/x")"

t "File outside any git repo → allow (not a framework repo)" 0 \
    "$(payload_write "$PLAINDIR/x.ts" "path is /Users/synthfaketester/x")"

t "File in a git repo WITHOUT the §7.6 marker → allow (not a framework repo)" 0 \
    "$(payload_write "$OTHERGIT/src/x.ts" "path is /Users/synthfaketester/x")"

# ── M6 (Gegenprüfer finding): an embedded/nested git repo with NO marker of
#    its own, living inside a framework repo that DOES have one at its own
#    root, must still be recognized as framework-repo scope — the ancestor
#    walk in find_marked_git_root must reach past the inner (unmarked) root. ──
NESTED="$FWREPO/nested-embedded"
mkdir -p "$NESTED/src"
git init -q "$NESTED"

CLAUDE_VAULT_DIR="$VDIR" t \
    "Write inside a NESTED git repo with no marker of its own, under a marked ANCESTOR repo → block (M6)" 2 \
    "$(payload_write "$NESTED/src/a.ts" "const owner = \"$SYNTH_TERM\";")"

t "Gitignored target inside a framework repo → allow" 0 \
    "$(payload_write "$FWREPO/ignored.txt" "path is /Users/synthfaketester/x")"

# ── M1 (Gegenprüfer finding): a file already TRACKED in git must still be
#    checked even after a NEW .gitignore pattern starts matching it — a
#    later ignore line does not stop git from continuing to commit an
#    already-tracked file, so the exemption must require "ignored AND
#    untracked", never "ignored" alone. ──
TRACKED="$FWREPO/src/tracked-legacy.ts"
printf 'export const x = 1;\n' >"$TRACKED"
git -C "$FWREPO" add src/tracked-legacy.ts >/dev/null 2>&1
printf 'src/tracked-legacy.ts\n' >>"$FWREPO/.gitignore"

CLAUDE_VAULT_DIR="$VDIR" t \
    "Edit on an ALREADY-TRACKED file a NEW .gitignore pattern now matches → still block (M1)" 2 \
    "$(payload_edit "$TRACKED" "const owner = \"$SYNTH_TERM\";")"

CLAUDE_VAULT_DIR="$T/no-such-vault-dir" t \
    "no vault present: structural pattern still blocks (fail-loud, not fail-closed)" 2 \
    "$(payload_write "$FWREPO/src/a.ts" "path is /Users/synthfaketester/x")"

# ── Bypass: exit 0 + a log line ─────────────────────────────────────────────
LOGF="$T/vault-gate-bypass.log"
N=$((N + 1))
printf '%s' "$(payload_write "$FWREPO/src/a.ts" "$SYNTH_TERM")" |
    CLAUDE_VAULT_DIR="$VDIR" CLAUDE_VAULT_GATE_LOG="$LOGF" CLAUDE_VAULT_GATE_OFF=1 "$GATE" >/dev/null 2>"$T/stderr"
CODE=$?
if [ "$CODE" -eq 0 ] && [ -s "$LOGF" ] && grep -q "decision=bypass" "$LOGF"; then
    PASS=$((PASS + 1)); printf '  ok %2d — bypass: exit 0 and a bypass line is logged\n' "$N"
else
    FAIL=$((FAIL + 1)); printf 'FAIL %2d — bypass: code=%s log=%s\n' "$N" "$CODE" "$(cat "$LOGF" 2>/dev/null)"
fi

# ── Block is logged, and the log NEVER contains the term ────────────────────
LOGF2="$T/vault-gate-block.log"
N=$((N + 1))
printf '%s' "$(payload_write "$FWREPO/src/a.ts" "$SYNTH_TERM")" |
    CLAUDE_VAULT_DIR="$VDIR" CLAUDE_VAULT_GATE_LOG="$LOGF2" "$GATE" >/dev/null 2>/dev/null
if [ -s "$LOGF2" ] && grep -q "decision=block" "$LOGF2" && ! grep -qF "$SYNTH_TERM" "$LOGF2"; then
    PASS=$((PASS + 1)); printf '  ok %2d — block is logged, and the log NEVER contains the term\n' "$N"
else
    FAIL=$((FAIL + 1)); printf 'FAIL %2d — log content: %s\n' "$N" "$(cat "$LOGF2" 2>/dev/null)"
fi

# ── Missing vault.sh → allow + NOTE (isolated copy with no sibling scripts/vault/) ──
ISOL=$(mktemp -d)
cp "$GATE" "$ISOL/vault-write-gate.sh"
N=$((N + 1))
printf '%s' "$(payload_write "$FWREPO/src/a.ts" "$SYNTH_TERM")" | "$ISOL/vault-write-gate.sh" >/dev/null 2>"$T/stderr"
CODE=$?
ERR=$(cat "$T/stderr" 2>/dev/null || true)
if [ "$CODE" -eq 0 ] && printf '%s' "$ERR" | grep -q "NOTE"; then
    PASS=$((PASS + 1)); printf '  ok %2d — missing vault.sh → allow + NOTE\n' "$N"
else
    FAIL=$((FAIL + 1)); printf 'FAIL %2d — missing vault.sh: code=%s err=%s\n' "$N" "$CODE" "$ERR"
fi
rm -rf "$ISOL"

# ── Garbage stdin → allow + NOTE (infra error, not a security decision) ────
N=$((N + 1))
printf 'not json at all' | "$GATE" >/dev/null 2>"$T/stderr"
CODE=$?
ERR=$(cat "$T/stderr" 2>/dev/null || true)
if [ "$CODE" -eq 0 ] && printf '%s' "$ERR" | grep -q "NOTE"; then
    PASS=$((PASS + 1)); printf '  ok %2d — garbage stdin → allow + NOTE\n' "$N"
else
    FAIL=$((FAIL + 1)); printf 'FAIL %2d — garbage stdin: code=%s err=%s\n' "$N" "$CODE" "$ERR"
fi

# ── M4 (Gegenprüfer finding): infra-NOTE escalation counter (rules/
#    fail-loud.md, "Repetition Without Escalation Is Also Silence", IMP-164).
#    A DEDICATED counter file, isolated from the rest of this suite, so this
#    sequence is deterministic regardless of what ran earlier or later. Three
#    CONSECUTIVE infra-failures (missing vault.sh, via an isolated copy of
#    the gate with no sibling scripts/vault/) must escalate the message form
#    on the 3rd; a subsequent REAL check (RC 0, a clean write) must then
#    reset the counter file away entirely. ──
INFRA_ISOL=$(mktemp -d)
cp "$GATE" "$INFRA_ISOL/vault-write-gate.sh"
INFRA_CTR="$T/vault-gate-infra-counter-test.txt"
rm -f "$INFRA_CTR"

N=$((N + 1))
printf '%s' "$(payload_write "$FWREPO/src/a.ts" "$SYNTH_TERM")" |
    CLAUDE_VAULT_GATE_INFRA_COUNTER="$INFRA_CTR" "$INFRA_ISOL/vault-write-gate.sh" >/dev/null 2>"$T/stderr"
CODE=$?; ERR=$(cat "$T/stderr" 2>/dev/null || true); CTR=$(cat "$INFRA_CTR" 2>/dev/null || echo "?")
if [ "$CODE" -eq 0 ] && printf '%s' "$ERR" | grep -q "NOTE" && ! printf '%s' "$ERR" | grep -q "ESKALATION" && [ "$CTR" = "1" ]; then
    PASS=$((PASS + 1)); printf '  ok %2d — infra-NOTE 1/3: NOTE form, counter=%s\n' "$N" "$CTR"
else
    FAIL=$((FAIL + 1)); printf 'FAIL %2d — infra-NOTE 1/3: code=%s counter=%s err=%s\n' "$N" "$CODE" "$CTR" "$ERR"
fi

N=$((N + 1))
printf '%s' "$(payload_write "$FWREPO/src/a.ts" "$SYNTH_TERM")" |
    CLAUDE_VAULT_GATE_INFRA_COUNTER="$INFRA_CTR" "$INFRA_ISOL/vault-write-gate.sh" >/dev/null 2>"$T/stderr"
CODE=$?; ERR=$(cat "$T/stderr" 2>/dev/null || true); CTR=$(cat "$INFRA_CTR" 2>/dev/null || echo "?")
if [ "$CODE" -eq 0 ] && printf '%s' "$ERR" | grep -q "NOTE" && ! printf '%s' "$ERR" | grep -q "ESKALATION" && [ "$CTR" = "2" ]; then
    PASS=$((PASS + 1)); printf '  ok %2d — infra-NOTE 2/3: NOTE form, counter=%s\n' "$N" "$CTR"
else
    FAIL=$((FAIL + 1)); printf 'FAIL %2d — infra-NOTE 2/3: code=%s counter=%s err=%s\n' "$N" "$CODE" "$CTR" "$ERR"
fi

N=$((N + 1))
printf '%s' "$(payload_write "$FWREPO/src/a.ts" "$SYNTH_TERM")" |
    CLAUDE_VAULT_GATE_INFRA_COUNTER="$INFRA_CTR" "$INFRA_ISOL/vault-write-gate.sh" >/dev/null 2>"$T/stderr"
CODE=$?; ERR=$(cat "$T/stderr" 2>/dev/null || true); CTR=$(cat "$INFRA_CTR" 2>/dev/null || echo "?")
if [ "$CODE" -eq 0 ] && printf '%s' "$ERR" | grep -q "ESKALATION" && [ "$CTR" = "3" ]; then
    PASS=$((PASS + 1)); printf '  ok %2d — infra-NOTE 3/3: form switches to ESKALATION, counter=%s\n' "$N" "$CTR"
else
    FAIL=$((FAIL + 1)); printf 'FAIL %2d — infra-NOTE 3/3: code=%s counter=%s err=%s\n' "$N" "$CODE" "$CTR" "$ERR"
fi

N=$((N + 1))
printf '%s' "$(payload_write "$FWREPO/src/cleaninfra.ts" "nothing interesting here")" |
    CLAUDE_VAULT_DIR="$VDIR" CLAUDE_VAULT_GATE_INFRA_COUNTER="$INFRA_CTR" "$GATE" >/dev/null 2>"$T/stderr"
CODE=$?
if [ "$CODE" -eq 0 ] && [ ! -f "$INFRA_CTR" ]; then
    PASS=$((PASS + 1)); printf '  ok %2d — infra-NOTE: a REAL check afterward resets the counter (file removed)\n' "$N"
else
    FAIL=$((FAIL + 1)); printf 'FAIL %2d — infra-NOTE reset: code=%s counter-file-exists=%s\n' "$N" "$CODE" "$([ -f "$INFRA_CTR" ] && echo yes || echo no)"
fi
rm -rf "$INFRA_ISOL"

echo "──────────────────────────────────────────────────────────────────────"
echo "vault-write-gate regression: $PASS/$N passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
