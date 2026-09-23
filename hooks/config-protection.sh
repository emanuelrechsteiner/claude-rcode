#!/bin/bash
# Config Protection — Layer 1.5 (2026-05-26; downgraded 2026-06-09 per IMP-044/IMP-045)
# ─────────────────────────────────────────────────────────────────────
# PreToolUse hook on Edit|Write. Guards edits to existing linter/formatter
# configuration files, because agents (and humans!) frequently weaken
# these to make checks pass instead of fixing the actual code.
#
# DOWNGRADE (IMP-044/IMP-045): the previous hard `exit 2` made every edit
# to a protected config an opaque tool-error the agent could not recover
# from — even legitimate maintenance (adding a real opt-in rule, fixing a
# typo in a glob) was blocked outright. We now emit a RECOVERABLE JSON
# `ask` decision: Claude Code surfaces a y/n to the user and the agent
# keeps a clear, actionable reason in-context. Legitimate maintenance
# proceeds after the agent asserts (and the user confirms) it is NOT
# weakening or disabling a check.
#
# Allows ENOENT (file doesn't exist yet) so bootstrap of a new config
# is fine. Fails OPEN on parse-failure (other hooks remain the floor).
#
# Adapted from ECC's config-protection.js. Pairs with security-audit.sh
# (which prevents secrets in code) — same protective-edit family.
#
# Bypass: CLAUDE_CONFIG_PROTECT_OFF=1
set -u

[ "${CLAUDE_CONFIG_PROTECT_OFF:-0}" = "1" ] && exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || exit 0
[ -n "$FILE_PATH" ] || exit 0

BN=$(basename "$FILE_PATH")
PROTECTED=0

case "$BN" in
    # ESLint
    .eslintrc|.eslintrc.json|.eslintrc.js|.eslintrc.cjs|.eslintrc.mjs|.eslintrc.yaml|.eslintrc.yml) PROTECTED=1 ;;
    eslint.config.js|eslint.config.mjs|eslint.config.cjs|eslint.config.ts) PROTECTED=1 ;;
    # Prettier
    .prettierrc|.prettierrc.json|.prettierrc.js|.prettierrc.cjs|.prettierrc.mjs|.prettierrc.yaml|.prettierrc.yml|prettier.config.js|prettier.config.cjs) PROTECTED=1 ;;
    # Biome
    biome.json|biome.jsonc) PROTECTED=1 ;;
    # Ruff
    .ruff.toml|ruff.toml) PROTECTED=1 ;;
    # Stylelint
    .stylelintrc|.stylelintrc.json|.stylelintrc.js|stylelint.config.js) PROTECTED=1 ;;
    # Markdownlint
    .markdownlint.json|.markdownlint.yaml|.markdownlint.yml|.markdownlintrc) PROTECTED=1 ;;
    # TypeScript strict-related (be careful — tsconfig can have legit edits)
    # Don't block tsconfig — too many legitimate reasons to edit.
esac

# pyproject.toml is excluded — too many legit reasons to edit (deps, build config)
# even though it can contain ruff config.

[ "$PROTECTED" = "1" ] || exit 0

# Check if file EXISTS — bootstrap (creating new) is allowed.
if [ ! -e "$FILE_PATH" ]; then
    exit 0
fi

# File exists and is a protected config. Emit a RECOVERABLE `ask` decision
# (exit 0 + stdout JSON) rather than a hard exit 2. The user gets a y/n; the
# agent gets an in-context reason that names the file and the assertion it must
# make. This preserves the protective intent (no silent weakening of a check)
# while letting legitimate maintenance proceed once intent is confirmed.
REL_PATH=$(echo "$FILE_PATH" | sed "s|$HOME|~|")
REASON="config-protection (Layer 1.5): editing protected linter/formatter config ${REL_PATH}. Agents frequently weaken these to make checks pass instead of fixing the underlying code. Before proceeding, confirm to the user that this edit does NOT disable, loosen, or remove a rule (e.g. adding an opt-in rule, fixing a glob, or a deps/build change is fine; downgrading error->warn, deleting rules, or relaxing strictness is NOT). The right pattern is usually: fix the code so the check passes with the current config. Approve only if the edit is non-weakening. Bypass for the session: CLAUDE_CONFIG_PROTECT_OFF=1."

# jq -Rs safely JSON-encodes the reason string (handles quotes, newlines).
REASON_JSON=$(printf '%s' "$REASON" | jq -Rs '.')

cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": ${REASON_JSON}
  },
  "systemMessage": ${REASON_JSON}
}
JSON
exit 0
