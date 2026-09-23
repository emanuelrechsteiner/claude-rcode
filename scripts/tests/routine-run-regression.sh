#!/usr/bin/env bash
# Regressionssuite fuer scripts/routine-run.sh — der stdin-Fix fuer den
# claude-Aufruf.
#
# Warum es diese Suite gibt: Alle drei launchd-Routinen (daily-docs,
# nightly-observation, weekly-improve) sind seit ihrem allerersten Lauf am
# 2026-08-23 mit "claude exited 1" gescheitert. Ursache: der Prompt (der
# komplette SKILL.md-Inhalt, beginnend mit dem YAML-Frontmatter "---") wurde
# als POSITIONSARGUMENT uebergeben. claude's eigener Optionsparser liest ein
# Positionsargument, das mit "--" beginnt, als unbekannte Option:
#   claude -p "$(printf -- '---\nname: x\n---\nSag OK')" --model X
#   -> error: unknown option '---
# Der Fix uebergibt den Prompt stattdessen per STDIN
# (`claude -p --model sonnet ... < "$SKILL_FILE"`), was den Optionsparser gar
# nicht erst erreicht. Reproduziert gegen die echte Binary (claude 2.1.266,
# 2026-09-09):
#   claude -p "$(printf -- '---\n...')" --model definitiv-kein-modell
#     -> exit 1, "error: unknown option '---"
#   printf -- '---\n...' | claude -p --model definitiv-kein-modell
#     -> exit 1, aber NUR wegen des ungueltigen Modellnamens — kein
#        "unknown option" im stderr. Fall D unten wiederholt genau das.
#
# Diese Suite arbeitet AUSSCHLIESSLICH mit Scratch-Verzeichnissen
# (CLAUDE_ROUTINE_CLAUDE_DIR / CLAUDE_ROUTINE_LOG_DIR) und einer Stub-Binary
# (CLAUDE_BIN) — sie schreibt nichts unter ~/.claude/global-observation/ und
# loest nie einen echten claude-Lauf mit gueltigem Modell aus.
#
# Aufruf: bash scripts/tests/routine-run-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../routine-run.sh"
[ -f "$RUNNER" ] || { echo "routine-run.sh nicht gefunden: $RUNNER" >&2; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf '  [%s] %s\n' "$1" "$2"; }
check(){ # check <name> <erwartet> <bekommen>
  if [ "$2" = "$3" ]; then ok; else bad "$1" "erwartet='$2' bekommen='$3'"; fi
}

ROOT=$(mktemp -d)

# ── Stub-claude: schreibt argv + stdin in Dateien, ruft NIE die echte Binary
#    auf. Exit-Code steuerbar ueber STUB_EXIT_CODE (Default 0). ─────────────
STUB="$ROOT/claude-stub.sh"
cat > "$STUB" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$@" > "$STUB_ARGV_FILE"
cat > "$STUB_STDIN_FILE"
exit "${STUB_EXIT_CODE:-0}"
STUBEOF
chmod +x "$STUB"

# setup_task <task> -> legt ein Scratch-CLAUDE_DIR mit SKILL.md fuer <task>
# an und setzt CDIR/SKILL fuer den Aufrufer.
setup_task() {
  local task="$1"
  CDIR="$ROOT/claude-home-$task"
  mkdir -p "$CDIR/scheduled-tasks/$task"
  SKILL="$CDIR/scheduled-tasks/$task/SKILL.md"
  printf -- '---\nname: %s\ndescription: Testroutine\n---\nSag OK und stoppe.\n' "$task" > "$SKILL"
}

# ── A) Stub-claude bekommt die SKILL.md byteexakt ueber stdin; argv enthaelt
#      KEINEN Prompt-Text und beginnt nicht mit "---" ──────────────────────
setup_task daily-docs
ARGV_A="$ROOT/argv-a.txt"; STDIN_A="$ROOT/stdin-a.txt"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_A" STUB_STDIN_FILE="$STDIN_A" STUB_EXIT_CODE=0 \
  bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "stdinform/exit0" 0 "$RC"
if [ -f "$STDIN_A" ] && cmp -s "$SKILL" "$STDIN_A"; then ok; else
  bad "stdinform/stdin-byteexakt" "STDIN unterscheidet sich von $SKILL (oder fehlt)"
fi
check "stdinform/argv-exakt" \
  "$(printf '%s\n' -p --model sonnet --dangerously-skip-permissions)" \
  "$([ -f "$ARGV_A" ] && cat "$ARGV_A")"
check "stdinform/argv-beginnt-nicht-mit-dashdashdash" 0 \
  "$([ -f "$ARGV_A" ] && head -1 "$ARGV_A" | grep -c '^---')"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-daily-docs" 2>/dev/null

# ── B) Stub-claude endet mit Exit 1 -> Runner schreibt die Fehlerzeile ins
#      Run-Log und endet selbst mit 1 (bestehendes Verhalten) ──────────────
setup_task nightly-observation
LOG_DIR_B="$ROOT/logs-b"
ARGV_B="$ROOT/argv-b.txt"; STDIN_B="$ROOT/stdin-b.txt"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_B" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_B" STUB_STDIN_FILE="$STDIN_B" STUB_EXIT_CODE=1 \
  bash "$RUNNER" nightly-observation >/dev/null 2>&1
RC=$?
check "claudefail/exit1" 1 "$RC"
check "claudefail/log-zeile" 1 \
  "$(jq -sr '[.[] | select(.note == "runner: claude exited 1 for nightly-observation")] | length' \
     "$LOG_DIR_B/nightly-obs-log.jsonl" 2>/dev/null)"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-nightly-observation" 2>/dev/null

# ── C) Lock bereits gehalten -> Runner bricht ab, OHNE claude aufzurufen
#      (bestehendes Verhalten, unveraendert durch den stdin-Fix) ───────────
setup_task weekly-improve
LOG_DIR_C="$ROOT/logs-c"
LOCK_DIR_C="${TMPDIR:-/tmp}/claude-routine-lock-weekly-improve"
mkdir -p "$LOCK_DIR_C"
ARGV_C="$ROOT/argv-c.txt"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_C" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_C" STUB_STDIN_FILE="$ROOT/stdin-c.txt" STUB_EXIT_CODE=0 \
  bash "$RUNNER" weekly-improve >/dev/null 2>&1
RC=$?
check "lockheld/exit1" 1 "$RC"
check "lockheld/claude-nicht-aufgerufen" 0 "$([ -f "$ARGV_C" ] && echo 1 || echo 0)"
rm -rf "$CDIR"; rmdir "$LOCK_DIR_C" 2>/dev/null

# ── D) Parser-Beweis gegen die ECHTE claude-Binary (nur wenn vorhanden):
#      stdin-Form + garantiert ungueltiges Modell -> kein "unknown option"
#      im stderr. Kein echter Lauf: das ungueltige Modell verhindert das. ──
if command -v claude >/dev/null 2>&1; then
  REAL_CLAUDE="$(command -v claude)"
  PROBE_SKILL="$ROOT/probe-skill.md"
  printf -- '---\nname: probe\n---\nSag OK\n' > "$PROBE_SKILL"
  REALOUT=$(timeout 20 "$REAL_CLAUDE" -p --model definitiv-kein-modell < "$PROBE_SKILL" 2>&1)
  check "echtebinary/kein-unknown-option" 0 "$(printf '%s' "$REALOUT" | grep -c 'unknown option')"
else
  echo "  [uebersprungen] Fall D: keine echte claude-Binary auf PATH gefunden"
fi

# ── E) --dry-run fuehrt den Parser-Beweis (IMP-190) aus: die Stub-Binary
#      wird TATSAECHLICH mit --model claude-dry-run-proof-invalid aufgerufen
#      (kein echter Lauf, das ist gerade der Witz) und meldet PASS, wenn
#      stderr kein "unknown option" enthaelt — der einfache Stub oben gibt
#      auf stderr nie etwas aus, also muss die Beweiszeile hier PASS sagen. ──
setup_task daily-docs
ARGV_E="$ROOT/argv-e.txt"; STDIN_E="$ROOT/stdin-e.txt"
DRYOUT_E=$(CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_E" STUB_STDIN_FILE="$STDIN_E" STUB_EXIT_CODE=1 \
  bash "$RUNNER" daily-docs --dry-run 2>&1)
RC=$?
check "dryrun-proof/exit0" 0 "$RC"
check "dryrun-proof/enthaelt-parserproof-abschnitt" 1 \
  "$(printf '%s\n' "$DRYOUT_E" | grep -c 'parser_proof:')"
check "dryrun-proof/meldet-PASS" 1 \
  "$(printf '%s\n' "$DRYOUT_E" | grep -c 'PASS — CLI parser accepted')"
check "dryrun-proof/stub-tatsaechlich-mit-ungueltigem-modell-aufgerufen" 1 \
  "$([ -f "$ARGV_E" ] && grep -c 'claude-dry-run-proof-invalid' "$ARGV_E")"
rm -rf "$CDIR"

# ── F) Wenn die (Stub-)Binary bei JEDEM Aufruf "unknown option" auf stderr
#      ausgibt, muss der Parser-Beweis das als FAIL melden statt es zu
#      verschlucken — und --dry-run bleibt trotzdem bei Exit 0 (Beweis ist
#      advisory, kein Gate). ──
setup_task nightly-observation
STUB_F="$ROOT/claude-stub-unknownopt.sh"
cat > "$STUB_F" <<'STUBEOF'
#!/bin/bash
echo "error: unknown option '---" >&2
exit 1
STUBEOF
chmod +x "$STUB_F"
DRYOUT_F=$(CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_BIN="$STUB_F" \
  bash "$RUNNER" nightly-observation --dry-run 2>&1)
RC=$?
check "dryrun-proof-fail/exit0-trotz-FAIL" 0 "$RC"
check "dryrun-proof-fail/meldet-FAIL" 1 \
  "$(printf '%s\n' "$DRYOUT_F" | grep -c 'FAIL — invocation shape')"
rm -rf "$CDIR"

rm -rf "$ROOT"

printf '── routine-run-regression: %d bestanden, %d fehlgeschlagen ──\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
