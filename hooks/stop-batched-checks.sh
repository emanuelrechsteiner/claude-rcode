#!/bin/bash
# Stop-Batched Checks — Layer 2 of the Quality Trinity (2026-05-26)
# ─────────────────────────────────────────────────────────────────────
# Runs at Stop. Consolidates format + typecheck + lint + line-limit
# checks on all files edited in this session, instead of running them
# per-edit (which was burning ~5-30s × N edits in post-edit-validate.sh).
#
# Adapted from ECC's stop-format-typecheck.js + post-edit-accumulator.js (sequential at Stop).
# Flow: read queue → dedupe → group by project root → rate limit (60s) → checks → findings → truncate.
#
# Bypass: CLAUDE_STOP_BATCH_OFF=1
# Force-run regardless of rate-limit: CLAUDE_STOP_BATCH_FORCE=1
set -u

[ "${CLAUDE_STOP_BATCH_OFF:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
# Visible failure without jq: plain printf, so the finding needs no jq itself.
report_not_run() { printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"## Layer 2 — Batched Quality Report\\n\\n🔴 **Batched checks did not run** — %s."}}\n' "$1"; }
command -v jq >/dev/null 2>&1 || { report_not_run "jq is missing, so no tsc/eslint/ruff/line-limit check ran (install jq)"; exit 0; }
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$SESSION_ID" ] || { report_not_run "the Stop input has no readable session_id, so the edit queue cannot be found"; exit 0; }

QUEUE="/tmp/claude-edit-queue-${SESSION_ID}.txt"
[ -f "$QUEUE" ] || exit 0
[ -s "$QUEUE" ] || exit 0  # Empty queue → nothing to do

# Rate limit: 60s between batched runs to prevent thrash on long sessions
LAST_RUN_FILE="/tmp/claude-stop-batch-last-${SESSION_ID}"
NOW=$(date +%s)
if [ -f "$LAST_RUN_FILE" ] && [ "${CLAUDE_STOP_BATCH_FORCE:-0}" != "1" ]; then
    LAST=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo 0)
    SINCE=$((NOW - LAST))
    if [ "$SINCE" -lt 60 ]; then
        # Too soon — skip but DON'T truncate queue (accumulate for next run)
        exit 0
    fi
fi
echo "$NOW" > "$LAST_RUN_FILE"

# Dedupe + filter to existing files
TMP_DEDUPED=$(mktemp)
sort -u "$QUEUE" | while read -r path; do
    [ -n "$path" ] && [ -f "$path" ] && echo "$path"
done > "$TMP_DEDUPED"

# Truncate queue NOW so future edits accumulate fresh (but we still process current batch)
: > "$QUEUE"

if [ ! -s "$TMP_DEDUPED" ]; then
    rm -f "$TMP_DEDUPED"
    exit 0
fi

EDIT_COUNT=$(wc -l < "$TMP_DEDUPED" | tr -d ' ')

# Total time budget: 270s (well under 300s Stop timeout per ECC pattern)
BUDGET_TOTAL=270
BUDGET_PER_GROUP=90
START_TIME=$NOW

# Time bound: `timeout` or Homebrew `gtimeout`. Neither → NOT run unbounded (the Stop
# budget must hold); run_check reports "did not run" per project instead.
TIMEOUT_CMD=""
for c in timeout gtimeout; do command -v "$c" >/dev/null 2>&1 && { TIMEOUT_CMD="$c"; break; }; done

# run_check <label> <dir> <finding-regex> <skip-regex|""> <cmd...>
# Runs <cmd> in <dir> under the time bound with its REAL exit status (no pipe to head).
# Sets CHECK_STATE (clean|finding|skipped) and CHECK_OUT:
#   exit 0 → clean · non-zero + finding-regex → finding · skip-regex → skipped (silent, pre-existing)
#   anything else (timeout, crash, not found, no timeout tool) → one "did not run" line
run_check() {
    local label="$1" dir="$2" find_re="$3" skip_re="$4" rc first shown
    shift 4
    CHECK_OUT=""; CHECK_STATE="clean"
    shown=$(printf '%s' "$dir" | sed "s|$HOME|~|")
    if [ -z "$TIMEOUT_CMD" ]; then
        first="neither timeout nor gtimeout is installed (brew install coreutils); not run unbounded"
    else
        CHECK_OUT=$(cd "$dir" && "$TIMEOUT_CMD" "$BUDGET_PER_GROUP" "$@" 2>&1)
        rc=$?
        [ "$rc" -eq 0 ] && return 0
        if [ "$rc" -ne 124 ] && [ -n "$skip_re" ] && printf '%s\n' "$CHECK_OUT" | grep -qE "$skip_re"; then CHECK_STATE="skipped"; return 0; fi
        if [ "$rc" -ne 124 ] && printf '%s\n' "$CHECK_OUT" | grep -qE "$find_re"; then CHECK_STATE="finding"; return 0; fi
        first=$(printf '%s\n' "$CHECK_OUT" | grep -m1 . || true)
        [ "$rc" -eq 124 ] && first="timed out after ${BUDGET_PER_GROUP}s"
        first="${first:-exit $rc, no output}"
    fi
    printf "⏱ **%s did not run** in %s: %s\n" "$label" "$shown" "$first" >> "$FINDINGS"
    CHECK_STATE="skipped"
}

# === Group by project root ===
# Find nearest package.json / tsconfig.json / pyproject.toml going up from each file.
# Group key = absolute path to project root.
TMP_GROUPED=$(mktemp)
while read -r f; do
    dir=$(dirname "$f")
    root=""
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if [ -f "$dir/tsconfig.json" ] || [ -f "$dir/package.json" ] || [ -f "$dir/pyproject.toml" ] || [ -f "$dir/Cargo.toml" ] || [ -f "$dir/go.mod" ]; then
            root="$dir"
            break
        fi
        dir=$(dirname "$dir")
    done
    [ -n "$root" ] && echo "$root|$f" >> "$TMP_GROUPED"
done < "$TMP_DEDUPED"

# === Findings buffer ===
FINDINGS=$(mktemp)

# === Line-limit check (cheap, do for ALL files first) ===
# IMP-050: threshold 250 (CLAUDE_LINE_LIMIT); breaches go to a refactor-queue, no
# auto-spawned refactor agent (HELD per IMP-050: a Stop hook must not launch an LLM).
LIMIT=${CLAUDE_LINE_LIMIT:-250}
REFACTOR_QUEUE="$HOME/.claude/global-observation/refactor-queue.jsonl"
LONG_FILES=""
LONG_COUNT=0
while read -r f; do
    case "$f" in
        *.ts|*.tsx|*.js|*.jsx|*.py|*.swift|*.kt|*.rs|*.go|*.rb|*.java|*.cs|*.cpp|*.c|*.h|*.hpp) ;;
        *) continue ;;
    esac
    case "$f" in
        */node_modules/*|*/.next/*|*/dist/*|*/build/*|*/.venv/*) continue ;;
    esac
    lines=$(wc -l < "$f" 2>/dev/null || echo 0)
    if [ "$lines" -gt "$LIMIT" ]; then
        LONG_COUNT=$((LONG_COUNT + 1))
        # IMP-082 dedupe: one queue record per file with a breach counter.
        if [ -f "$REFACTOR_QUEUE" ] && grep -qF "\"file\":\"$f\"" "$REFACTOR_QUEUE" 2>/dev/null; then
            TMPQ=$(mktemp)
            jq -c --arg f "$f" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson l "$lines" \
                'if .file == $f then .breaches = ((.breaches // 1) + 1) | .lines = $l | .last_seen = $ts else . end' \
                "$REFACTOR_QUEUE" > "$TMPQ" 2>/dev/null && mv "$TMPQ" "$REFACTOR_QUEUE" || rm -f "$TMPQ"
        else
            printf '{"ts":"%s","file":"%s","lines":%s,"limit":%s,"session":"%s","breaches":1}\n' \
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$f" "$lines" "$LIMIT" "$SESSION_ID" \
                >> "$REFACTOR_QUEUE" 2>/dev/null || true
        fi
        # Cap inline display to the first 10 to avoid a wall of text at the 250 threshold.
        if [ "$LONG_COUNT" -le 10 ]; then
            LONG_FILES="${LONG_FILES}  - $f ($lines lines)\n"
        fi
    fi
done < "$TMP_DEDUPED"
if [ -n "$LONG_FILES" ]; then
    EXTRA=""
    [ "$LONG_COUNT" -gt 10 ] && EXTRA=$(printf "  …and %d more (see refactor-queue.jsonl)\n" "$((LONG_COUNT - 10))")
    printf "🟡 **Line-limit** — %d file(s) over %d lines (per code-quality.md); queued for refactor:\n%b%b\n" "$LONG_COUNT" "$LIMIT" "$LONG_FILES" "$EXTRA" >> "$FINDINGS"
fi

# === Command-contract lint (IMP-089; extended scope 2026-09-23) ===
# Runs when this session touched ~/.claude/commands/, rcode/ or the rcode-*/scope-check
# skills. Failures are a WARNING, never a block (Stop hooks report, they don't gate).
COMMANDS_DIR="$HOME/.claude/commands"
LINT_SCRIPT="$HOME/.claude/scripts/command-contract-lint.sh"
if { grep -qF "$COMMANDS_DIR/" "$TMP_DEDUPED" 2>/dev/null \
     || grep -qF "$HOME/.claude/rcode/" "$TMP_DEDUPED" 2>/dev/null \
     || grep -qF "$HOME/.claude/skills/rcode-" "$TMP_DEDUPED" 2>/dev/null \
     || grep -qF "$HOME/.claude/skills/scope-check/" "$TMP_DEDUPED" 2>/dev/null; } \
   && [ -f "$LINT_SCRIPT" ]; then
    # Time-bounded like the tsc/eslint/ruff calls below (the lint once took minutes).
    run_check command-contract-lint "$HOME/.claude" "." "" bash "$LINT_SCRIPT" --root "$HOME/.claude" "$COMMANDS_DIR"
    if [ "$CHECK_STATE" = "finding" ]; then
        printf "🟡 **command-contract-lint** — commands/rcode/skills touched this session, linter FAILED:\n\`\`\`\n%s\n\`\`\`\n" "$CHECK_OUT" >> "$FINDINGS"
    fi
fi

# === Per-group typecheck + lint with bounded retries ===
if [ -f "$TMP_GROUPED" ]; then
    # CHECK_GROUPS, not the old name: that is bash's built-in group-id array; assigning
    # to it is silently ignored, so the loop never saw the project roots.
    CHECK_GROUPS=$(awk -F'|' '{print $1}' "$TMP_GROUPED" | sort -u)

    # fd 3: line-by-line loop; word-splitting would break on spaces in project paths.
    while IFS= read -r group <&3; do
        [ -n "$group" ] || continue
        # Time budget check — bail if we're close to the limit
        ELAPSED=$(( $(date +%s) - START_TIME ))
        if [ "$ELAPSED" -gt $((BUDGET_TOTAL - 30)) ]; then
            printf "⏱  **Budget exhausted** — skipped checks for remaining groups. Run /quality-review for thorough analysis.\n" >> "$FINDINGS"
            break
        fi

        # === TypeScript / JavaScript ===
        if [ -f "$group/tsconfig.json" ]; then
            run_check tsc "$group" "error TS" "" npx -y --no-install tsc --noEmit
            if [ "$CHECK_STATE" = "finding" ]; then
                err_count=$(printf '%s\n' "$CHECK_OUT" | grep -cE "error TS" || true)
                printf "🔴 **TypeScript errors** in %s (%d errors):\n\`\`\`\n%s\n\`\`\`\n" "$(printf '%s' "$group" | sed "s|$HOME|~|")" "$err_count" "$(printf '%s\n' "$CHECK_OUT" | head -15)" >> "$FINDINGS"
            fi
        fi

        # === ESLint (only if config exists) ===
        if [ -f "$group/package.json" ]; then
            has_eslint=0
            for cfg in .eslintrc .eslintrc.json .eslintrc.js eslint.config.js eslint.config.mjs; do
                [ -f "$group/$cfg" ] && has_eslint=1 && break
            done
            if [ "$has_eslint" = "1" ]; then
                # Lint only the files actually edited (faster than whole project)
                # One array element per path (no word-splitting); `--` ends eslint's options.
                group_files=()
                while IFS= read -r f; do group_files+=("$f"); done < <(awk -F'|' -v g="$group" '$1==g {print $2}' "$TMP_GROUPED" | grep -E '\.(ts|tsx|js|jsx)$')
                if [ "${#group_files[@]}" -gt 0 ]; then
                    run_check ESLint "$group" "[0-9]+:[0-9]+ +(error|warning) |[0-9]+ problems?" "[Nn]o files" npx -y --no-install eslint --max-warnings 0 -- "${group_files[@]}"
                    if [ "$CHECK_STATE" = "finding" ]; then
                        err_count=$(printf '%s\n' "$CHECK_OUT" | grep -cE "(error|warning)" || true)
                        printf "🟡 **ESLint findings** in %s (%d issues):\n\`\`\`\n%s\n\`\`\`\n" "$(printf '%s' "$group" | sed "s|$HOME|~|")" "$err_count" "$(printf '%s\n' "$CHECK_OUT" | head -10)" >> "$FINDINGS"
                    fi
                fi
            fi
        fi

        # === Python ruff ===
        if [ -f "$group/pyproject.toml" ] || [ -f "$group/ruff.toml" ] || [ -f "$group/.ruff.toml" ]; then
            py_files=()
            while IFS= read -r f; do py_files+=("$f"); done < <(awk -F'|' -v g="$group" '$1==g {print $2}' "$TMP_GROUPED" | grep '\.py$')
            if [ "${#py_files[@]}" -gt 0 ]; then
                run_check ruff "$group" ":[0-9]+:[0-9]+: [A-Z]+[0-9]+ |Found [0-9]+ error" "" ruff check -- "${py_files[@]}"
                if [ "$CHECK_STATE" = "finding" ]; then
                    printf "🟡 **Ruff findings** in %s:\n\`\`\`\n%s\n\`\`\`\n" "$(printf '%s' "$group" | sed "s|$HOME|~|")" "$(printf '%s\n' "$CHECK_OUT" | head -10)" >> "$FINDINGS"
                fi
            fi
        fi
    done 3<<< "$CHECK_GROUPS"
fi

# === Emit findings as additionalContext ===
if [ -s "$FINDINGS" ]; then
    body=$(cat "$FINDINGS")
    # Use JSON output with hookSpecificOutput.additionalContext (Stop hook protocol)
    jq -n --arg body "$body" --arg count "$EDIT_COUNT" '{
        hookSpecificOutput: {
            hookEventName: "Stop",
            additionalContext: "## Layer 2 — Batched Quality Report\n\nProcessed \($count) edited files this turn.\n\n\($body)"
        }
    }'
fi

# Cleanup
rm -f "$TMP_DEDUPED" "$TMP_GROUPED" "$FINDINGS"
exit 0
