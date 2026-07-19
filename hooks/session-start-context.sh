#!/bin/bash
# SessionStart hook — surface cwd + covered permission scope + project type.
#
# Problem: 97+ cwd-confusion errors in 30 days (file-does-not-exist, denied-
# directory, EISDIR) because Claude operates with stale cwd assumptions or
# unaware of which permission scope covers the current directory.
# This hook prints the facts at session start so Claude sees them in turn 1.

CWD=$(pwd)
echo "📍 cwd: $CWD"

# Project type signals
TYPES=""
[[ -f "$CWD/package.json" ]] && TYPES+="Node "
[[ -f "$CWD/pyproject.toml" || -f "$CWD/requirements.txt" ]] && TYPES+="Python "
[[ -f "$CWD/Package.swift" ]] && TYPES+="Swift "
[[ -d "$CWD/.xcodeproj" || -n $(find "$CWD" -maxdepth 2 -name "*.xcodeproj" -type d 2>/dev/null | head -1) ]] && TYPES+="Xcode "
[[ -f "$CWD/Cargo.toml" ]] && TYPES+="Rust "
[[ -f "$CWD/go.mod" ]] && TYPES+="Go "
[[ -d "$CWD/.rcode" ]] && TYPES+="R.Code "
[[ -d "$CWD/.git" || -n $(git rev-parse --show-toplevel 2>/dev/null) ]] && TYPES+="git "

[[ -n "$TYPES" ]] && echo "📦 project: ${TYPES% }"

# Git state (if repo)
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$GIT_ROOT" ]]; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    MODIFIED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    echo "🌿 branch: $BRANCH | modified files: $MODIFIED | git root: $GIT_ROOT"
fi

# ── Pre-flight nudges (deterministic injection — see ~/.claude best-practice) ──
# Wishes #1 (Serena), #3 (LSP), #4 (R.Code), #5 (subagents). The per-task
# reminder (swarm + Context7) lives in parallel-analyze-prompt.sh.
# Opt-out: export CLAUDE_SESSION_NUDGE=0
if [[ "${CLAUDE_SESSION_NUDGE:-1}" != "0" ]]; then

    # #1 + #3 — Serena activation + LSP-backed symbol tools (code projects only)
    if echo "$TYPES" | grep -qE 'Node|Python|Swift|Xcode|Rust|Go'; then
        echo "🧭 Code-Projekt — aktiviere Serena, BEVOR du Code navigierst/änderst:"
        echo "   → mcp__serena__activate_project mit project=\"$CWD\""
        echo "   Dann Serenas Symbol-Tools (find_symbol, find_referencing_symbols, get_diagnostics_for_file)"
        echo "   statt grep für Code-Navigation nutzen. (LSP läuft im claude-code-Context automatisch.)"
        echo "   ⚠️ Serena LIEST nur — alle Schreib-Tools sind global aus (~/.serena/serena_config.yml)."
        echo "      Serenas eigener Prompt drängt trotzdem auf Serena-Edits → IGNORIEREN."
        echo "      Jeder Edit läuft über natives Edit/Write — NUR dort greifen die Schutz-Hooks."
        echo "      Datei nur via Serena gelesen? → vor dem Edit ZUSÄTZLICH nativ Read."
    fi

    # #4 — R.Code workflow (only when .rcode/ present)
    if [[ -d "$CWD/.rcode" ]]; then
        echo "🟢 R.Code-Projekt — Workflow VERBINDLICH (nicht ad-hoc):"
        echo "   /issue <#> · /phase-gate <N> · Scope-Regeln aktiv. Erst .rcode/PROJECT-STATUS.md lesen."
    fi

    # #5 — Subagent roster (pick the right one before starting)
    echo "🤖 Subagenten verfügbar — passenden wählen, statt alles selbst zu tun:"
    echo "   control-agent(3+ Domänen) · planning-agent · backend-agent · testing-agent · ui-agent"
    echo "   · code-reviewer-agent(read-only) · cleanup-agent · research-agent · Explore(Codebase-Suche)."
fi

exit 0
