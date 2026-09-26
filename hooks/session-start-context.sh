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

# ── Pfad-Kanon: Bauhof vs. Haus (IMP-162) ──
# 66 "File does not exist" errors over 37 sessions (August 2026 chat analysis,
# the largest single error class of the month) traced to two valid roots
# (Bauhof = working copy, everything happens here; Haus = installation, what
# Claude Code actually reads) plus two dead historical directory names the
# agent sometimes reconstructs from memory instead of reading. Typical
# fallout: "/Volumes/<VOLUME> 1/PROJECTS/Development/5_AI-APPS/…" (space
# instead of hyphen, underscore instead of hyphen). Emitted ONLY when this
# session's cwd is actually inside one of the two real roots — silent in
# unrelated projects, so it never becomes noise there.
#
# Bauhof-root resolution (IMP-219 — no hardcoded machine path in source):
#   1) CLAUDE_BAUHOF_ROOT already set in the environment (regression tests,
#      session env) wins outright.
#   2) else source ~/.claude/env.local.sh if present (machine-local,
#      gitignored — see templates/env.local.sh.template) and re-check.
#   3) still unset -> BAUHOF_RESOLVED=0. Print "Bauhof: unbekannt" instead
#      of guessing — never fall back to a hardcoded default path
#      (rules/fail-loud.md).
# CLAUDE_HAUS_ROOT stays overridable via env for regression tests so the
# suite doesn't depend on this machine's real absolute paths.
BAUHOF_RESOLVED=1
if [[ -z "${CLAUDE_BAUHOF_ROOT:-}" ]]; then
    # shellcheck disable=SC1091
    [[ -f "$HOME/.claude/env.local.sh" ]] && . "$HOME/.claude/env.local.sh"
fi
[[ -n "${CLAUDE_BAUHOF_ROOT:-}" ]] || BAUHOF_RESOLVED=0
BAUHOF_ROOT="${CLAUDE_BAUHOF_ROOT:-}"
HAUS_ROOT="${CLAUDE_HAUS_ROOT:-$HOME/.claude}"

IN_HAUS=0
[[ "$CWD" == "$HAUS_ROOT" || "$CWD" == "$HAUS_ROOT"/* ]] && IN_HAUS=1
IN_BAUHOF=0
if [[ "$BAUHOF_RESOLVED" == "1" ]]; then
    [[ "$CWD" == "$BAUHOF_ROOT" || "$CWD" == "$BAUHOF_ROOT"/* ]] && IN_BAUHOF=1
fi

if [[ "$IN_HAUS" == "1" || "$IN_BAUHOF" == "1" ]]; then
    echo ""
    echo "📌 Pfad-Kanon (Zwei-Orte-Steuer, IMP-162 — 66 File-does-not-exist-Fehler/37 Sessions im Aug. 2026):"
    if [[ "$BAUHOF_RESOLVED" == "1" ]]; then
        echo "   Bauhof (Arbeitskopie, hier committen):  $BAUHOF_ROOT"
    else
        echo "   Bauhof: unbekannt — ~/.claude/env.local.sh anlegen (Vorlage: templates/env.local.sh.template)"
    fi
    echo "   Haus (Installation, NICHT von Hand ändern): $HAUS_ROOT"
    echo "   Historische Namen (vor dem Rebrand) — existieren NICHT mehr."
fi

# ── Offene Abnahme aus der letzten Übergabe (IMP-147) ──
# deploy-to-live.sh schreibt diese Datei nach einer config-Übergabe mit echten
# neuen Commits. Fehlt sie, gibt dieser Block exakt nichts aus (fail-loud: kein
# Rauschen, kein stiller Sonderfall).
PENDING_VERIFICATION="$HOME/.claude/pending-verification.md"
if [[ -f "$PENDING_VERIFICATION" ]]; then
    echo ""
    echo "⏳ Offene Abnahme aus letzter Übergabe — nach bestandener Prüfung Datei löschen: rm ~/.claude/pending-verification.md"
    PV_LINES=$(wc -l < "$PENDING_VERIFICATION" | tr -d ' ')
    if [[ "$PV_LINES" -gt 25 ]]; then
        head -25 "$PENDING_VERIFICATION"
        echo "… (gekürzt, $PV_LINES Zeilen insgesamt — vollständig: $PENDING_VERIFICATION)"
    else
        cat "$PENDING_VERIFICATION"
    fi
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
