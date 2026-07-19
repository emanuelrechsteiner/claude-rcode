#!/bin/bash
# Stop-Batched Checks — Layer 2 of the Quality Trinity (2026-05-26)
# ─────────────────────────────────────────────────────────────────────
# Runs at Stop. Consolidates format + typecheck + lint + line-limit
# checks on all files edited in this session, instead of running them
# per-edit (which was burning ~5-30s × N edits in post-edit-validate.sh).
#
# Adapted from ECC's stop-format-typecheck.js + post-edit-accumulator.js
# pattern. Race-free because the only check fires sequentially at Stop.
#
# Architecture:
#   1. Read queue file written by observation-capture.sh accumulator
#   2. Dedupe + filter to existing files only
#   3. Group by project root (nearest tsconfig.json / package.json / pyproject.toml)
#   4. Skip if last batched run was < 60s ago (rate limit)
#   5. Run language-appropriate checks with bounded retries (max 3)
#   6. Emit findings as additionalContext via JSON output
#   7. Truncate queue file (start fresh for next turn)
#
# Bypass: CLAUDE_STOP_BATCH_OFF=1
# Force-run regardless of rate-limit: CLAUDE_STOP_BATCH_FORCE=1
set -u

[ "${CLAUDE_STOP_BATCH_OFF:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$SESSION_ID" ] || exit 0

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
# IMP-050: threshold lowered 400→250 (env-configurable via CLAUDE_LINE_LIMIT) +
# breaches recorded to a refactor-queue the Stop-nudge surfaces. NOTE: we deliberately
# do NOT auto-spawn a refactor agent — a Stop/PostToolUse hook cannot safely launch an
# unattended LLM session (that step is HELD per IMP-050). The queue below is the hook
# point a future opt-in launcher could drain.
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
        # IMP-082 dedupe: one queue record PER FILE with a breach counter, not one
        # per breach — the append-only form re-queued the same file up to 7x
        # (write-only backlog, 136 records / 78 files, nothing draining it).
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

# === Command-contract lint (IMP-089 closed-loop wiring, 2026-07-15) ===
# If this session touched any file under ~/.claude/commands/, run the
# deterministic command-contract-lint.sh over the whole commands/ dir and
# surface failures as a WARNING. Stop hooks report, they don't block — a
# failing lint here is a nudge to fix the marker/frontmatter, not a gate.
COMMANDS_DIR="$HOME/.claude/commands"
LINT_SCRIPT="$HOME/.claude/scripts/command-contract-lint.sh"
if grep -qF "$COMMANDS_DIR/" "$TMP_DEDUPED" 2>/dev/null && [ -f "$LINT_SCRIPT" ]; then
    lint_out=$(bash "$LINT_SCRIPT" "$COMMANDS_DIR" 2>&1)
    lint_status=$?
    if [ "$lint_status" -ne 0 ]; then
        printf "🟡 **command-contract-lint** — commands/*.md touched this session, linter FAILED:\n\`\`\`\n%s\n\`\`\`\n" "$lint_out" >> "$FINDINGS"
    fi
fi

# === Per-group typecheck + lint with bounded retries ===
if [ -f "$TMP_GROUPED" ]; then
    GROUPS=$(awk -F'|' '{print $1}' "$TMP_GROUPED" | sort -u)

    for group in $GROUPS; do
        # Time budget check — bail if we're close to the limit
        ELAPSED=$(( $(date +%s) - START_TIME ))
        if [ "$ELAPSED" -gt $((BUDGET_TOTAL - 30)) ]; then
            printf "⏱  **Budget exhausted** — skipped checks for remaining groups. Run /quality-review for thorough analysis.\n" >> "$FINDINGS"
            break
        fi

        # === TypeScript / JavaScript ===
        if [ -f "$group/tsconfig.json" ]; then
            tsc_out=$(cd "$group" && timeout $BUDGET_PER_GROUP npx -y --no-install tsc --noEmit 2>&1 | head -30 || echo "(tsc skipped — not installed)")
            if [ -n "$tsc_out" ] && echo "$tsc_out" | grep -qE "error TS"; then
                err_count=$(echo "$tsc_out" | grep -cE "error TS" || true)
                printf "🔴 **TypeScript errors** in %s (%d errors):\n\`\`\`\n%s\n\`\`\`\n" "$(echo "$group" | sed "s|$HOME|~|")" "$err_count" "$(echo "$tsc_out" | head -15)" >> "$FINDINGS"
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
                group_files=$(awk -F'|' -v g="$group" '$1==g {print $2}' "$TMP_GROUPED" | grep -E '\.(ts|tsx|js|jsx)$' | tr '\n' ' ')
                if [ -n "$group_files" ]; then
                    eslint_out=$(cd "$group" && timeout $BUDGET_PER_GROUP npx -y --no-install eslint $group_files --max-warnings 0 2>&1 | head -20 || echo "")
                    if [ -n "$eslint_out" ] && ! echo "$eslint_out" | grep -qiE "(not installed|no files)"; then
                        err_count=$(echo "$eslint_out" | grep -cE "(error|warning)" || true)
                        if [ "$err_count" -gt 0 ]; then
                            printf "🟡 **ESLint findings** in %s (%d issues):\n\`\`\`\n%s\n\`\`\`\n" "$(echo "$group" | sed "s|$HOME|~|")" "$err_count" "$(echo "$eslint_out" | head -10)" >> "$FINDINGS"
                        fi
                    fi
                fi
            fi
        fi

        # === Python ruff ===
        if [ -f "$group/pyproject.toml" ] || [ -f "$group/ruff.toml" ] || [ -f "$group/.ruff.toml" ]; then
            group_py=$(awk -F'|' -v g="$group" '$1==g {print $2}' "$TMP_GROUPED" | grep '\.py$' | tr '\n' ' ')
            if [ -n "$group_py" ] && command -v ruff >/dev/null 2>&1; then
                ruff_out=$(cd "$group" && timeout $BUDGET_PER_GROUP ruff check $group_py 2>&1 | head -20 || echo "")
                if [ -n "$ruff_out" ] && ! echo "$ruff_out" | grep -qE "^All checks passed"; then
                    printf "🟡 **Ruff findings** in %s:\n\`\`\`\n%s\n\`\`\`\n" "$(echo "$group" | sed "s|$HOME|~|")" "$(echo "$ruff_out" | head -10)" >> "$FINDINGS"
                fi
            fi
        fi
    done
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
