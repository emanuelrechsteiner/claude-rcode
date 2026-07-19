#!/bin/bash
# Framework Inventory — disk-truth counts for the ~/.claude framework
# ──────────────────────────────────────────────────────────────────────────
# Emits the ACTUAL component counts from the filesystem so docs (CLAUDE.md,
# HARNESS.md) can reference instead of duplicate them (IMP-083: hand-counted
# numbers in docs drift; this script is the single source of truth).
#
# Counts:
#   rules             — non-.bak *.md directly in rules/ (archive/ excluded)
#   commands          — commands/*.md
#   skills            — skills/*/SKILL.md
#   hooks_disk        — non-.bak *.sh directly in hooks/ (tests/ excluded)
#   hooks_registered  — unique *.sh script paths wired in settings.json hooks
#   agents            — non-.bak *.md directly in agents/ (archived subdir excluded)
#   scheduled_tasks   — scheduled-tasks/*/SKILL.md (live definitions)  # was routines/*.yaml|*.yml templates
#
# Usage:
#   bash ~/.claude/scripts/framework-inventory.sh            # table + JSON
#   bash ~/.claude/scripts/framework-inventory.sh --json     # JSON only
#   bash ~/.claude/scripts/framework-inventory.sh --check rules=31 skills=41
#       # audit mode: exit 1 if any given expected count mismatches disk truth
#
# Exit codes:
#   0 — success (and, in --check mode, all expectations matched)
#   1 — --check mode found at least one mismatch
#   2 — script error (missing directory / missing jq)
set -uo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

# ── Preconditions (fail loud, per fail-loud.md) ───────────────────────────
if [[ ! -d "$CLAUDE_DIR" ]]; then
    echo "ERROR: CLAUDE_DIR not found: $CLAUDE_DIR" >&2
    exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required (hooks_registered is extracted from settings.json via jq)" >&2
    exit 2
fi
for d in rules commands skills hooks agents; do
    if [[ ! -d "$CLAUDE_DIR/$d" ]]; then
        echo "ERROR: expected directory missing: $CLAUDE_DIR/$d" >&2
        exit 2
    fi
done

# ── Counters (disk truth) ─────────────────────────────────────────────────
count_rules() {
    find "$CLAUDE_DIR/rules" -maxdepth 1 -type f -name '*.md' ! -name '*.bak*' | wc -l | tr -d ' '
}

count_commands() {
    find "$CLAUDE_DIR/commands" -maxdepth 1 -type f -name '*.md' ! -name '*.bak*' | wc -l | tr -d ' '
}

count_skills() {
    find "$CLAUDE_DIR/skills" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' | wc -l | tr -d ' '
}

count_hooks_disk() {
    # -maxdepth 1 keeps hooks/tests/ out of the count
    find "$CLAUDE_DIR/hooks" -maxdepth 1 -type f -name '*.sh' ! -name '*.bak*' | wc -l | tr -d ' '
}

count_hooks_registered() {
    # Unique *.sh script paths referenced by any hook command in settings.json.
    # Inline `echo ...` hook commands carry no .sh path and are excluded.
    if [[ ! -f "$SETTINGS" ]]; then
        echo "ERROR: settings.json not found: $SETTINGS" >&2
        return 2
    fi
    jq -r '.hooks // {} | to_entries[] | .value[] | .hooks[]? | .command // empty' "$SETTINGS" \
        | grep -oE '[~/][^ "'"'"']*\.sh' \
        | sort -u | wc -l | tr -d ' '
}

count_agents() {
    # -maxdepth 1 keeps agents/archived-replaced-by-skills/ out of the count
    find "$CLAUDE_DIR/agents" -maxdepth 1 -type f -name '*.md' ! -name '*.bak*' | wc -l | tr -d ' '
}

count_scheduled_tasks() {
    # IMP-087: source of truth is scheduled-tasks/*/SKILL.md (the live definitions
    # the scheduler reads at fire time). The routines/*.yaml templates were removed
    # 2026-07-03 — they were a stale duplicate source (see routines/README.md).
    if [[ -d "$CLAUDE_DIR/scheduled-tasks" ]]; then
        find "$CLAUDE_DIR/scheduled-tasks" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' | wc -l | tr -d ' '
    else
        echo 0
    fi
}

RULES=$(count_rules)
COMMANDS=$(count_commands)
SKILLS=$(count_skills)
HOOKS_DISK=$(count_hooks_disk)
HOOKS_REGISTERED=$(count_hooks_registered) || exit 2
AGENTS=$(count_agents)
SCHEDULED_TASKS=$(count_scheduled_tasks)
GENERATED_AT=$(date '+%Y-%m-%dT%H:%M:%S%z')

value_of() {
    case "$1" in
        rules)            echo "$RULES" ;;
        commands)         echo "$COMMANDS" ;;
        skills)           echo "$SKILLS" ;;
        hooks_disk)       echo "$HOOKS_DISK" ;;
        hooks_registered) echo "$HOOKS_REGISTERED" ;;
        agents)           echo "$AGENTS" ;;
        scheduled_tasks)  echo "$SCHEDULED_TASKS" ;;
        *)                echo "" ;;
    esac
}

emit_json() {
    cat <<EOF
{
  "generated_at": "$GENERATED_AT",
  "claude_dir": "$CLAUDE_DIR",
  "rules": $RULES,
  "commands": $COMMANDS,
  "skills": $SKILLS,
  "hooks_disk": $HOOKS_DISK,
  "hooks_registered": $HOOKS_REGISTERED,
  "agents": $AGENTS,
  "scheduled_tasks": $SCHEDULED_TASKS
}
EOF
}

emit_table() {
    cat <<EOF
Framework Inventory — disk truth for $CLAUDE_DIR ($GENERATED_AT)

  Component          Count   Source
  ─────────────────  ─────   ─────────────────────────────────────────────
  rules              $(printf '%5s' "$RULES")   rules/*.md (non-.bak, archive/ excluded)
  commands           $(printf '%5s' "$COMMANDS")   commands/*.md
  skills             $(printf '%5s' "$SKILLS")   skills/*/SKILL.md
  hooks (disk)       $(printf '%5s' "$HOOKS_DISK")   hooks/*.sh (non-.bak, tests/ excluded)
  hooks (registered) $(printf '%5s' "$HOOKS_REGISTERED")   unique *.sh paths in settings.json hooks
  agents             $(printf '%5s' "$AGENTS")   agents/*.md (top-level only)
  scheduled tasks    $(printf '%5s' "$SCHEDULED_TASKS")   scheduled-tasks/*/SKILL.md
EOF
}

# ── Modes ─────────────────────────────────────────────────────────────────
MODE="full"
if [[ "${1:-}" == "--json" ]]; then
    MODE="json"
elif [[ "${1:-}" == "--check" ]]; then
    MODE="check"
    shift
fi

case "$MODE" in
    json)
        emit_json
        ;;
    check)
        if [[ $# -eq 0 ]]; then
            echo "ERROR: --check requires at least one key=expected pair, e.g. --check rules=$RULES skills=$SKILLS" >&2
            echo "       valid keys: rules commands skills hooks_disk hooks_registered agents scheduled_tasks" >&2
            exit 2
        fi
        MISMATCH=0
        for pair in "$@"; do
            key="${pair%%=*}"
            expected="${pair#*=}"
            actual=$(value_of "$key")
            if [[ -z "$actual" ]]; then
                echo "ERROR: unknown key '$key' (valid: rules commands skills hooks_disk hooks_registered agents scheduled_tasks)" >&2
                exit 2
            fi
            if [[ ! "$expected" =~ ^[0-9]+$ ]]; then
                echo "ERROR: expected count for '$key' is not a number: '$expected'" >&2
                exit 2
            fi
            if [[ "$actual" -eq "$expected" ]]; then
                echo "OK       $key = $actual"
            else
                echo "MISMATCH $key: expected $expected, disk truth is $actual"
                MISMATCH=1
            fi
        done
        exit "$MISMATCH"
        ;;
    full)
        emit_table
        echo ""
        emit_json
        ;;
esac
