#!/usr/bin/env bash
# Regressionssuite fuer die vier tracker-agnostischen GATHER-Skripte des
# R.Code-Umbaus "Plan folgt Praxis" (rcode-umbau-spec.md §9 A2/A3):
#   rcode-units.sh — der EINE Parser (github via `gh issue list`, plan via
#     A2-Grammatik ueber BRAINSTORM.md)
#   status-metrics.sh, phase-gate-check.sh, resume-state.sh — rufen
#     rcode-units.sh fuer Unit-Daten auf, statt selbst zu parsen
#     (rules/testing-quality.md "Verify via the same code path").
#
# Warum es diese Suite gibt: vor M14 war GitHub eine harte Voraussetzung in
# allen drei Verbrauchsskripten, obwohl 2 von 5 realen R.Code-Projekten
# keinen Issue-Tracker haben (eines davon gemessen bei 0/28 Commits, die
# irgendetwas referenzieren, kein Remote). Die Fixtures unten decken BEIDE Tabellenformen
# aus A2 ab (Checkbox- und Tabellenform, mit UND ohne Status-Spalte), den
# Nie-fabrizieren-Fall (keine IDs gefunden), die p-NNN-Branch-Konvention und
# den github-Pfad ueber eine Stub-`gh`-Binary — alles ohne Netzwerk.
#
# Aufruf:  bash scripts/tests/gather-scripts-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RCU="$SCRIPTS_DIR/rcode-units.sh"
SM="$SCRIPTS_DIR/status-metrics.sh"
PGC="$SCRIPTS_DIR/phase-gate-check.sh"
RS="$SCRIPTS_DIR/resume-state.sh"

for f in "$RCU" "$SM" "$PGC" "$RS"; do
  [ -f "$f" ] || { echo "fehlt: $f" >&2; exit 1; }
done

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf '  [%s] %s\n' "$1" "$2"; }
check(){ # check <name> <erwartet> <bekommen>
  if [ "$2" = "$3" ]; then ok; else bad "$1" "erwartet='$2' bekommen='$3'"; fi
}
check_gt(){ # check_gt <name> <bekommen> <schwelle> -- bekommen > schwelle
  if [ "${2:-0}" -gt "${3:-0}" ] 2>/dev/null; then ok; else bad "$1" "erwartet '>${3}' bekommen='${2:-}'"; fi
}

G() { git -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }

# ── Syntaxvorpruefung — bricht sofort mit einer klaren Meldung ab, statt
#    kryptisch mitten in einer Fixture zu scheitern. ─────────────────────
for f in "$RCU" "$SM" "$PGC" "$RS"; do
  if bash -n "$f" 2>/tmp/gsr-syntax-err.$$; then ok; else
    bad "syntax/$(basename "$f")" "$(cat /tmp/gsr-syntax-err.$$)"
  fi
  rm -f /tmp/gsr-syntax-err.$$
done

# ── Stub-gh: liest die erwartete Antwort aus einer Datei, deren Pfad ueber
#    GH_STUB_MAP_FILE uebergeben wird (Zeilen "ARGV<TAB>ANTWORTDATEI"),
#    exit 1 mit einer Meldung auf stderr bei unbekannten Argumenten — nie
#    stillschweigend leer, damit ein Fixture-Tippfehler laut scheitert. ──
make_stub_gh() { # make_stub_gh <bindir>
  local bindir="$1"
  mkdir -p "$bindir"
  cat > "$bindir/gh" <<'STUBEOF'
#!/usr/bin/env bash
map="${GH_STUB_MAP_FILE:?GH_STUB_MAP_FILE not set}"
argv="$*"
while IFS=$'\t' read -r pattern replyfile; do
  [ -z "$pattern" ] && continue
  if [ "$argv" = "$pattern" ]; then
    cat "$replyfile"
    exit 0
  fi
done < "$map"
echo "gh-stub: unhandled args: $argv" >&2
exit 1
STUBEOF
  chmod +x "$bindir/gh"
}

STUBROOT=$(mktemp -d)
STUBBIN="$STUBROOT/bin"
make_stub_gh "$STUBBIN"

# ─────────────────────────────────────────────────────────────────────────
# A) Plan-Tracker, Checkbox-Grammatik (A2a): gemischt offen/geschlossen,
#    zwei Phasen ueber Ueberschriften, kein Status/State-Vergleich noetig
#    (Checkboxen sind immer bestimmt — nie "unknown").
# ─────────────────────────────────────────────────────────────────────────
REPO_A=$(mktemp -d)
G -C "$REPO_A" init -q -b main
cat > "$REPO_A/BRAINSTORM.md" <<'EOF'
# Plan

### Phase 1 — Foundation

- [x] P-001 — Scaffold repo `infra` `build`
- [ ] P-002 — Add CI `infra` `build` `parallel-safe`

### Phase 2 — Core

- [x] P-003 — Core loop `feat` `core`
EOF
G -C "$REPO_A" add -A && G -C "$REPO_A" commit -q -m "seed"

OUT=$(bash "$RCU" "$REPO_A" 2>&1); RC=$?
check "checkbox/rcu-exit0" 0 "$RC"
check "checkbox/tracker" "plan" "$(jq -r .tracker <<<"$OUT")"
check "checkbox/source" "BRAINSTORM.md" "$(jq -r .source <<<"$OUT")"
check "checkbox/total-units" 3 "$(jq '.units|length' <<<"$OUT")"
check "checkbox/p001-closed" "closed" "$(jq -r '.units[] | select(.id=="P-001") | .state' <<<"$OUT")"
check "checkbox/p002-open" "open" "$(jq -r '.units[] | select(.id=="P-002") | .state' <<<"$OUT")"
check "checkbox/p001-phase" "1" "$(jq -r '.units[] | select(.id=="P-001") | .phase' <<<"$OUT")"
check "checkbox/p003-phase" "2" "$(jq -r '.units[] | select(.id=="P-003") | .phase' <<<"$OUT")"
check "checkbox/no-unknown-finding" "" "$(jq -r '.findings[] | select(test("completion not recorded"))' <<<"$OUT")"
check "checkbox/p001-phase-name" "Foundation" "$(jq -r '.units[] | select(.id=="P-001") | .phase_name' <<<"$OUT")"
check "checkbox/p003-phase-name" "Core" "$(jq -r '.units[] | select(.id=="P-003") | .phase_name' <<<"$OUT")"

OUT=$(bash "$SM" "$REPO_A" 2>&1)
check "checkbox/sm-tracker" "plan" "$(jq -r .tracker <<<"$OUT")"
# K-B (2026-09-23): milestones[].title carries the heading's <Name> suffix
# ("Phase N — <Name>"), sourced from rcode-units.sh's phase_name field.
check "checkbox/sm-phase1-title-has-name" "Phase 1 — Foundation" "$(jq -r '.milestones[] | select(.total==2) | .title' <<<"$OUT")"
check "checkbox/sm-phase2-title-has-name" "Phase 2 — Core" "$(jq -r '.milestones[] | select(.total==1) | .title' <<<"$OUT")"
check "checkbox/sm-phase1-total" 2 "$(jq -r '.milestones[] | select(.title=="Phase 1 — Foundation") | .total' <<<"$OUT")"
check "checkbox/sm-phase1-closed" 1 "$(jq -r '.milestones[] | select(.title=="Phase 1 — Foundation") | .closed' <<<"$OUT")"
check "checkbox/sm-phase2-percent" 100 "$(jq -r '.milestones[] | select(.title=="Phase 2 — Core") | .percent' <<<"$OUT")"
check "checkbox/sm-stale-empty" 0 "$(jq '.stale_issues|length' <<<"$OUT")"

OUT=$(bash "$PGC" 1 "$REPO_A" 2>&1)
check "checkbox/pgc-tracker" "plan" "$(jq -r .tracker <<<"$OUT")"
check "checkbox/pgc-issues-total" 2 "$(jq -r '.counts.issues_total' <<<"$OUT")"
check "checkbox/pgc-issues-closed" 1 "$(jq -r '.counts.issues_closed' <<<"$OUT")"
check "checkbox/pgc-verdict-block" "BLOCK" "$(jq -r .verdict <<<"$OUT")"

rm -rf "$REPO_A"

# ─────────────────────────────────────────────────────────────────────────
# B) Plan-Tracker, Tabellenform MIT Status-Spalte (A2b) — Vollstaendigkeit
#    ist bestimmt, niemals "unknown".
# ─────────────────────────────────────────────────────────────────────────
REPO_B=$(mktemp -d)
G -C "$REPO_B" init -q -b main
cat > "$REPO_B/BRAINSTORM.md" <<'EOF'
## Phase 3 — Battle

| ID | Title | Type | Area | Status |
|---|---|---|---|---|
| P-010 | [Phase 3] Do the thing | feat | core | Done |
| P-011 | [Phase 3] Do another | feat | core | open |
| P-012 | [Phase 3] Third | feat | core | ✅ |
EOF
G -C "$REPO_B" add -A && G -C "$REPO_B" commit -q -m "seed"

OUT=$(bash "$RCU" "$REPO_B" 2>&1)
check "table-status/total" 3 "$(jq '.units|length' <<<"$OUT")"
check "table-status/p010-closed" "closed" "$(jq -r '.units[] | select(.id=="P-010") | .state' <<<"$OUT")"
check "table-status/p011-open" "open" "$(jq -r '.units[] | select(.id=="P-011") | .state' <<<"$OUT")"
check "table-status/p012-checkmark-closed" "closed" "$(jq -r '.units[] | select(.id=="P-012") | .state' <<<"$OUT")"
check "table-status/no-unknown-finding" "" "$(jq -r '.findings[] | select(test("completion not recorded"))' <<<"$OUT")"

OUT=$(bash "$SM" "$REPO_B" 2>&1)
check "table-status/sm-phase3-closed" 2 "$(jq -r '.milestones[] | select(.title=="Phase 3 — Battle") | .closed' <<<"$OUT")"
check "table-status/sm-phase3-percent-not-null" "false" "$(jq -r '.milestones[] | select(.title=="Phase 3 — Battle") | (.percent == null)' <<<"$OUT")"

OUT=$(bash "$PGC" 3 "$REPO_B" 2>&1)
check "table-status/pgc-issues-closed" 2 "$(jq -r '.counts.issues_closed' <<<"$OUT")"
check "table-status/pgc-verdict-block" "BLOCK" "$(jq -r .verdict <<<"$OUT")"

rm -rf "$REPO_B"

# ─────────────────────────────────────────────────────────────────────────
# C) Plan-Tracker, Tabellenform OHNE Status-Spalte — "unknown", niemals
#    ein erfundenes offen/geschlossen (fail-loud.md). Genau die Form, die
#    eine echte BRAINSTORM.md real verwendet (dort gemessen: 312 Einheiten).
# ─────────────────────────────────────────────────────────────────────────
REPO_C=$(mktemp -d)
G -C "$REPO_C" init -q -b main
cat > "$REPO_C/BRAINSTORM.md" <<'EOF'
### Phase 1 — Foundation

| ID | Title | Type | Area | Serves | ∥ | Blockers | Acceptance |
|---|---|---|---|---|---|---|---|
| P-001 | [Phase 1] DECISION: something | decision | content | F001 | Y | — | criterion text |
| P-002 | [Phase 1] Another unit | feat | ui | F013 | Y | — | criterion text |
EOF
G -C "$REPO_C" add -A && G -C "$REPO_C" commit -q -m "seed"

OUT=$(bash "$RCU" "$REPO_C" 2>&1)
check "table-nostatus/total" 2 "$(jq '.units|length' <<<"$OUT")"
check "table-nostatus/p001-unknown" "unknown" "$(jq -r '.units[] | select(.id=="P-001") | .state' <<<"$OUT")"
check "table-nostatus/finding-present" 1 "$(jq '[.findings[] | select(test("completion not recorded for 2 units"))] | length' <<<"$OUT")"

OUT=$(bash "$SM" "$REPO_C" 2>&1)
check "table-nostatus/sm-closed-null" "null" "$(jq -c '.milestones[] | select(.title=="Phase 1 — Foundation") | .closed' <<<"$OUT")"
check "table-nostatus/sm-percent-null" "null" "$(jq -c '.milestones[] | select(.title=="Phase 1 — Foundation") | .percent' <<<"$OUT")"
# N18 (2026-09-23): ALL units in this fixture are "unknown" — counts.
# issues_open/issues_closed must be null (never a fabricated 0), and
# issues_unknown must equal the total.
check "table-nostatus/sm-issues-open-null" "null" "$(jq -c '.counts.issues_open' <<<"$OUT")"
check "table-nostatus/sm-issues-closed-null" "null" "$(jq -c '.counts.issues_closed' <<<"$OUT")"
check "table-nostatus/sm-issues-unknown" 2 "$(jq -r '.counts.issues_unknown' <<<"$OUT")"
check "table-nostatus/sm-unknown-finding" 1 "$(jq '[.findings[] | select(test("completion not recorded for any"))] | length' <<<"$OUT")"

OUT=$(bash "$PGC" 1 "$REPO_C" 2>&1)
check "table-nostatus/pgc-verdict-not-block" "true" "$(jq -r '.verdict != "BLOCK"' <<<"$OUT")"
check "table-nostatus/pgc-verdict-not-pass" "true" "$(jq -r '.verdict != "PASS"' <<<"$OUT")"
check "table-nostatus/pgc-finding" 1 "$(jq '[.findings[] | select(test("cannot fully verify closure"))] | length' <<<"$OUT")"
# N18: phase-gate-check.sh's own counts get the same null-when-fully-
# unknown rule for issues_closed (it has no issues_open field).
check "table-nostatus/pgc-issues-closed-null" "null" "$(jq -c '.counts.issues_closed' <<<"$OUT")"
check "table-nostatus/pgc-issues-unknown" 2 "$(jq -r '.counts.issues_unknown' <<<"$OUT")"

rm -rf "$REPO_C"

# ─────────────────────────────────────────────────────────────────────────
# D) Plan-Tracker, KEINE P-NNN-IDs ueberhaupt (real beobachteter Fall) —
#    total:0 + Fund, niemals eine still-leere Antwort.
# ─────────────────────────────────────────────────────────────────────────
REPO_D=$(mktemp -d)
G -C "$REPO_D" init -q -b main
cat > "$REPO_D/BRAINSTORM.md" <<'EOF'
# Plan

## Core Features

| ID | Feature | Pillar |
|---|---|---|
| F001 | Something | Battle |
EOF
G -C "$REPO_D" add -A && G -C "$REPO_D" commit -q -m "seed"

OUT=$(bash "$RCU" "$REPO_D" 2>&1); RC=$?
check "no-id/rcu-exit0" 0 "$RC"
check "no-id/total-zero" 0 "$(jq '.units|length' <<<"$OUT")"
check "no-id/finding" 1 "$(jq '[.findings[] | select(test("no plan units found"))] | length' <<<"$OUT")"

OUT=$(bash "$PGC" 1 "$REPO_D" 2>&1); RC=$?
check "no-id/pgc-exit1" 1 "$RC"
check "no-id/pgc-errors" 1 "$(jq '[.errors[] | select(test("no plan units found for Phase 1"))] | length' <<<"$OUT")"
check "no-id/pgc-ok-false" "false" "$(jq -r .ok <<<"$OUT")"

rm -rf "$REPO_D"

# ─────────────────────────────────────────────────────────────────────────
# E) resume-state.sh: p-NNN-Branch-Konvention (case-insensitive), Konflikt
#    mit einer anderen agent-log-Erwaehnung, "**Last step:** 6", und ein
#    Commit mit Bereichs-/Komma-Refs ("refs P-051..P-105", "refs P-085,
#    P-100") — reine Szenenechtheit, aber auch ein Beweis, dass
#    last_commit.subject solche Botschaften unverfaelscht durchreicht.
# ─────────────────────────────────────────────────────────────────────────
REPO_E=$(mktemp -d)
G -C "$REPO_E" init -q -b main
cat > "$REPO_E/BRAINSTORM.md" <<'EOF'
### Phase 1 — Foundation

- [ ] P-012 — Some unit `feat` `core`
EOF
mkdir -p "$REPO_E/.rcode"
cat > "$REPO_E/.rcode/agent-log.md" <<'EOF'
## Session: earlier

**Date:** 2026-09-20
**Actions:** worked on P-006

---

## Session: latest

**Date:** 2026-09-23
**Last step:** 6

**Actions:** worked on P-012
EOF
G -C "$REPO_E" add -A && G -C "$REPO_E" commit -q -m "seed refs P-051..P-105"
G -C "$REPO_E" checkout -q -b "feat/P-012-some-unit"
echo "x" > "$REPO_E/x.txt"
G -C "$REPO_E" add -A && G -C "$REPO_E" commit -q -m "wip: touch x - refs P-085, P-100"

OUT=$(bash "$RS" "$REPO_E" 2>&1); RC=$?
check "resume/exit0" 0 "$RC"
check "resume/tracker" "plan" "$(jq -r .tracker <<<"$OUT")"
check "resume/in-progress-unit" "P-012" "$(jq -r .in_progress_unit <<<"$OUT")"
check "resume/last-logged-step" 6 "$(jq -r .last_logged_step <<<"$OUT")"
check "resume/last-commit-subject" "wip: touch x - refs P-085, P-100" "$(jq -r .last_commit.subject <<<"$OUT")"
check "resume/detected-project-phase-alias" "$(jq -r .detected_phase <<<"$OUT")" "$(jq -r .detected_project_phase <<<"$OUT")"
# No "**Agent:**" line anywhere in this fixture's agent-log.md -> null.
check "resume/last-entry-agent-null" "null" "$(jq -c .last_entry_agent <<<"$OUT")"

rm -rf "$REPO_E"

# ─────────────────────────────────────────────────────────────────────────
# F) resume-state.sh: p-NNN-Branch widerspricht der agent-log-Erwaehnung ->
#    ambiguous:true, Branch gewinnt (gleiche Regel wie in_progress_issue).
# ─────────────────────────────────────────────────────────────────────────
REPO_F=$(mktemp -d)
G -C "$REPO_F" init -q -b main
mkdir -p "$REPO_F/.rcode"
cat > "$REPO_F/.rcode/agent-log.md" <<'EOF'
## Session: x

**Date:** 2026-09-20
**Actions:** worked on P-007
EOF
G -C "$REPO_F" add -A && G -C "$REPO_F" commit -q -m "seed"
G -C "$REPO_F" checkout -q -b "fix/p-099-conflict"
echo "y" > "$REPO_F/y.txt"
G -C "$REPO_F" add -A && G -C "$REPO_F" commit -q -m "wip"

OUT=$(bash "$RS" "$REPO_F" 2>&1)
check "resume-conflict/in-progress-unit" "P-099" "$(jq -r .in_progress_unit <<<"$OUT")"
check "resume-conflict/ambiguous" "true" "$(jq -r .ambiguous <<<"$OUT")"
check "resume-conflict/finding" 1 "$(jq '[.findings[] | select(test("conflicting in-progress-unit evidence"))] | length' <<<"$OUT")"

rm -rf "$REPO_F"

# ─────────────────────────────────────────────────────────────────────────
# G) github-Modus ueber eine Stub-gh-Binaerdatei zuerst im PATH — Tracker-
#    Inferenz (Remote + gh auth + >=1 issue) UND explizit gesetzter
#    Tracker, quer durch alle vier Skripte. Keine Netzwerkverbindung.
# ─────────────────────────────────────────────────────────────────────────
REPO_G=$(mktemp -d)
G -C "$REPO_G" init -q -b main
G -C "$REPO_G" commit -q --allow-empty -m "seed"
G -C "$REPO_G" remote add origin https://example.invalid/o/r.git
G -C "$REPO_G" checkout -q -b "feat/issue-7-add-thing"
echo "z" > "$REPO_G/z.txt"
G -C "$REPO_G" add -A && G -C "$REPO_G" commit -q -m "wip"

GH_MAP="$REPO_G/.gh-map.tsv"
REPLY_PROBE="$REPO_G/.reply-probe.json"
REPLY_UNITS_RCU="$REPO_G/.reply-units-rcu.json"
REPLY_UNITS_SM="$REPO_G/.reply-units-sm.json"
REPLY_MILESTONES="$REPO_G/.reply-milestones.json"
REPLY_UNITS_MS="$REPO_G/.reply-units-milestone.json"
echo '[{"number":7}]' > "$REPLY_PROBE"
echo '[{"number":7,"title":"Add thing","state":"OPEN","milestone":{"title":"Phase 5: Something"},"labels":[]},{"number":8,"title":"Fixed","state":"CLOSED","milestone":{"title":"Phase 5: Something"},"labels":[]}]' > "$REPLY_UNITS_RCU"
echo '[{"number":7,"title":"Add thing","state":"OPEN","milestone":{"title":"Phase 5: Something"},"labels":[{"name":"blocked"}],"updatedAt":"2020-01-01T00:00:00Z"},{"number":8,"title":"Fixed","state":"CLOSED","milestone":{"title":"Phase 5: Something"},"labels":[],"updatedAt":"2026-09-20T00:00:00Z"}]' > "$REPLY_UNITS_SM"
echo '[{"title":"Phase 5: Something"}]' > "$REPLY_MILESTONES"
echo '[{"number":7,"state":"OPEN"},{"number":8,"state":"CLOSED"}]' > "$REPLY_UNITS_MS"

# Nur `gh`-Aufrufe laufen ueber diese Karte — die Remote-Erkennung selbst
# ruft das echte `git remote` (REPO_G hat via `git remote add origin ...`
# oben ein echtes Remote), nicht `gh`.
cat > "$GH_MAP" <<EOF
auth status	/dev/null
issue list --limit 1 --json number	${REPLY_PROBE}
issue list --state all --json number,title,state,milestone,labels --limit 1000	${REPLY_UNITS_RCU}
issue list --state all --json number,title,state,milestone,labels,updatedAt --limit 500	${REPLY_UNITS_SM}
api repos/{owner}/{repo}/milestones?state=all&per_page=100 --paginate	${REPLY_MILESTONES}
issue list --milestone Phase 5: Something --state all --json number,state --limit 500	${REPLY_UNITS_MS}
EOF

OUT=$(PATH="$STUBBIN:$PATH" GH_STUB_MAP_FILE="$GH_MAP" bash "$RCU" "$REPO_G" 2>&1); RC=$?
check "github/rcu-exit0" 0 "$RC"
check "github/rcu-tracker-inferred" "github" "$(jq -r .tracker <<<"$OUT")"
check "github/rcu-units-count" 2 "$(jq '.units|length' <<<"$OUT")"
check "github/rcu-unit7-phase" 5 "$(jq -r '.units[] | select(.id=="#7") | .phase' <<<"$OUT")"
check "github/rcu-unit7-state" "open" "$(jq -r '.units[] | select(.id=="#7") | .state' <<<"$OUT")"
check "github/rcu-inferred-finding" 1 "$(jq '[.findings[] | select(test("inferred github"))] | length' <<<"$OUT")"

OUT=$(PATH="$STUBBIN:$PATH" GH_STUB_MAP_FILE="$GH_MAP" bash "$SM" "$REPO_G" 2>&1)
check "github/sm-tracker" "github" "$(jq -r .tracker <<<"$OUT")"
check "github/sm-milestone-title-exact" "Phase 5: Something" "$(jq -r '.milestones[0].title' <<<"$OUT")"
check "github/sm-blocked-count" 1 "$(jq -r '.counts.issues_blocked' <<<"$OUT")"
check "github/sm-stale-count" 1 "$(jq '.stale_issues|length' <<<"$OUT")"

OUT=$(PATH="$STUBBIN:$PATH" GH_STUB_MAP_FILE="$GH_MAP" bash "$PGC" 5 "$REPO_G" 2>&1)
check "github/pgc-tracker" "github" "$(jq -r .tracker <<<"$OUT")"
check "github/pgc-issues-total" 2 "$(jq -r '.counts.issues_total' <<<"$OUT")"
check "github/pgc-verdict-block" "BLOCK" "$(jq -r .verdict <<<"$OUT")"

OUT=$(PATH="$STUBBIN:$PATH" GH_STUB_MAP_FILE="$GH_MAP" bash "$RS" "$REPO_G" 2>&1)
check "github/rs-tracker" "github" "$(jq -r .tracker <<<"$OUT")"
check "github/rs-in-progress-unit" "#7" "$(jq -r .in_progress_unit <<<"$OUT")"
check "github/rs-in-progress-issue-unchanged" 7 "$(jq -r .in_progress_issue <<<"$OUT")"

# ── explicit tracker="github" in .rcode/config.json overrides inference ──
mkdir -p "$REPO_G/.rcode"
echo '{"tracker":"github"}' > "$REPO_G/.rcode/config.json"
OUT=$(PATH="$STUBBIN:$PATH" GH_STUB_MAP_FILE="$GH_MAP" bash "$RCU" "$REPO_G" 2>&1)
check "github/explicit-tracker-no-infer-finding" "" "$(jq -r '.findings[] | select(test("inferred"))' <<<"$OUT")"
check "github/explicit-tracker-still-github" "github" "$(jq -r .tracker <<<"$OUT")"

rm -rf "$REPO_G"

# ─────────────────────────────────────────────────────────────────────────
# H) github-Modus, aber `gh` fehlt auf dem PATH -> ok:false, kein
#    Freikarten-Ruecksturz auf plan (fail-loud.md: fehlende Voraussetzung
#    bleibt ein Fehler, niemals ein stiller Modus-Wechsel).
# ─────────────────────────────────────────────────────────────────────────
REPO_H=$(mktemp -d)
G -C "$REPO_H" init -q -b main
G -C "$REPO_H" commit -q --allow-empty -m "seed"
mkdir -p "$REPO_H/.rcode"
echo '{"tracker":"github"}' > "$REPO_H/.rcode/config.json"

EMPTYBIN=$(mktemp -d)
NOSTUB_PATH="$EMPTYBIN:/usr/bin:/bin"
OUT=$(PATH="$NOSTUB_PATH" bash "$RCU" "$REPO_H" 2>&1); RC=$?
check "no-gh/rcu-exit1" 1 "$RC"
check "no-gh/rcu-ok-false" "false" "$(jq -r .ok <<<"$OUT")"
check "no-gh/rcu-tracker-still-github" "github" "$(jq -r .tracker <<<"$OUT")"
check "no-gh/rcu-error" 1 "$(jq '[.errors[] | select(test("gh CLI not found"))] | length' <<<"$OUT")"

rm -rf "$REPO_H" "$EMPTYBIN"

# ─────────────────────────────────────────────────────────────────────────
# I) status-metrics.sh / phase-gate-check.sh ohne rcode-units.sh daneben ->
#    ok:false statt eines stillen Absturzes (die Verbrauchsskripte pruefen
#    das Vorhandensein vor dem Aufruf).
# ─────────────────────────────────────────────────────────────────────────
ISOLATED=$(mktemp -d)
cp "$SM" "$ISOLATED/status-metrics.sh"
cp "$PGC" "$ISOLATED/phase-gate-check.sh"
REPO_I=$(mktemp -d)
G -C "$REPO_I" init -q -b main
G -C "$REPO_I" commit -q --allow-empty -m "seed"

OUT=$(bash "$ISOLATED/status-metrics.sh" "$REPO_I" 2>&1); RC=$?
check "isolated/sm-exit1" 1 "$RC"
check "isolated/sm-error" 1 "$(jq '[.errors[] | select(test("rcode-units.sh not found"))] | length' <<<"$OUT")"

OUT=$(bash "$ISOLATED/phase-gate-check.sh" 1 "$REPO_I" 2>&1); RC=$?
check "isolated/pgc-exit1" 1 "$RC"
check "isolated/pgc-error" 1 "$(jq '[.errors[] | select(test("rcode-units.sh not found"))] | length' <<<"$OUT")"

rm -rf "$ISOLATED" "$REPO_I"

# ─────────────────────────────────────────────────────────────────────────
# K) K-A (C14) — LOCAL-NUMBER table grammar: header's first cell is "#",
#    row's first cell a bare integer (a real project's shape). No Status
#    column -> "unknown" completion, never a fabricated open/closed. A
#    P-NNN row inside the SAME table still wins (checked first).
# ─────────────────────────────────────────────────────────────────────────
REPO_K=$(mktemp -d)
G -C "$REPO_K" init -q -b main
cat > "$REPO_K/BRAINSTORM.md" <<'EOF'
### Phase 1 — Setup

| # | Titel | Typ | Bereich | Parallel-safe | Blockiert durch | Referenz |
|---|---|---|---|---|---|---|
| 1 | Schema.sql finalisieren | infra | db | Y | — | ref |
| 2 | CI aufsetzen | infra | build | Y | — | ref |
| P-050 | Zusatzeinheit | feat | core | Y | — | ref |
EOF
G -C "$REPO_K" add -A && G -C "$REPO_K" commit -q -m "seed"

OUT=$(bash "$RCU" "$REPO_K" 2>&1); RC=$?
check "local-num/rcu-exit0" 0 "$RC"
check "local-num/total-units" 3 "$(jq '.units|length' <<<"$OUT")"
check "local-num/hash1-id" "#1" "$(jq -r '.units[] | select(.title=="Schema.sql finalisieren") | .id' <<<"$OUT")"
check "local-num/hash1-state-unknown" "unknown" "$(jq -r '.units[] | select(.id=="#1") | .state' <<<"$OUT")"
check "local-num/hash1-phase" "1" "$(jq -r '.units[] | select(.id=="#1") | .phase' <<<"$OUT")"
check "local-num/hash1-phase-name" "Setup" "$(jq -r '.units[] | select(.id=="#1") | .phase_name' <<<"$OUT")"
check "local-num/hash2-id" "#2" "$(jq -r '.units[] | select(.title=="CI aufsetzen") | .id' <<<"$OUT")"
check "local-num/p-nnn-still-works" "P-050" "$(jq -r '.units[] | select(.title=="Zusatzeinheit") | .id' <<<"$OUT")"
check "local-num/finding-present" 1 "$(jq '[.findings[] | select(test("completion not recorded for 3 units"))] | length' <<<"$OUT")"

OUT=$(bash "$SM" "$REPO_K" 2>&1)
check "local-num/sm-title-has-name" "Phase 1 — Setup" "$(jq -r '.milestones[0].title' <<<"$OUT")"
check "local-num/sm-closed-null" "null" "$(jq -c '.milestones[0].closed' <<<"$OUT")"
# N18: all 3 units project-wide are "unknown" here too.
check "local-num/sm-issues-closed-null" "null" "$(jq -c '.counts.issues_closed' <<<"$OUT")"
check "local-num/sm-issues-unknown" 3 "$(jq -r '.counts.issues_unknown' <<<"$OUT")"

rm -rf "$REPO_K"

# ─────────────────────────────────────────────────────────────────────────
# L) K-B (C6) — a Phase heading with NO name suffix (bare "### Phase N")
#    falls back to the bare "Phase N" milestone title, never a dangling
#    "Phase N — " or a fabricated name.
# ─────────────────────────────────────────────────────────────────────────
REPO_L=$(mktemp -d)
G -C "$REPO_L" init -q -b main
cat > "$REPO_L/BRAINSTORM.md" <<'EOF'
### Phase 9

- [x] P-090 — Something with no phase name
EOF
G -C "$REPO_L" add -A && G -C "$REPO_L" commit -q -m "seed"

OUT=$(bash "$RCU" "$REPO_L" 2>&1)
check "no-phase-name/phase-name-null" "null" "$(jq -c '.units[] | select(.id=="P-090") | .phase_name' <<<"$OUT")"

OUT=$(bash "$SM" "$REPO_L" 2>&1)
check "no-phase-name/sm-title-bare" "Phase 9" "$(jq -r '.milestones[0].title' <<<"$OUT")"

rm -rf "$REPO_L"

# ─────────────────────────────────────────────────────────────────────────
# M) K-C/C2 — resume-state.sh scopes EVERY agent-log-derived field to the
#    NEWEST "## Session:" block only: an older block's "**Last step:** 6"
#    must NOT leak into last_logged_step once a newer, non-/issue entry
#    (here: a team-lead entry with no Last step) was appended. Also
#    exercises last_entry_agent (K-C, new field) and the C18/C34
#    work/<date>-<slug> wave-branch finding.
# ─────────────────────────────────────────────────────────────────────────
REPO_M=$(mktemp -d)
G -C "$REPO_M" init -q -b main
cat > "$REPO_M/BRAINSTORM.md" <<'EOF'
### Phase 1 — Foundation

- [ ] P-012 — Some unit
EOF
mkdir -p "$REPO_M/.rcode"
cat > "$REPO_M/.rcode/agent-log.md" <<'EOF'
## Session: 2026-09-20 10:00 — issue-worker

**Date:** 2026-09-20
**Agent:** issue-worker
**Last step:** 6
**Actions:** worked on P-006

---

## Session: 2026-09-23 09:00 — team-lead

**Date:** 2026-09-23
**Agent:** team-lead
**Actions:** dispatched a wave for P-012, P-013
EOF
G -C "$REPO_M" add -A && G -C "$REPO_M" commit -q -m "seed"
G -C "$REPO_M" checkout -q -b "work/2026-09-23-fix-findings"
echo "x" > "$REPO_M/x.txt"
G -C "$REPO_M" add -A && G -C "$REPO_M" commit -q -m "wip"

OUT=$(bash "$RS" "$REPO_M" 2>&1); RC=$?
check "newest-block/exit0" 0 "$RC"
check "newest-block/last-step-not-stale" "null" "$(jq -c .last_logged_step <<<"$OUT")"
check "newest-block/last-entry-agent" "team-lead" "$(jq -r .last_entry_agent <<<"$OUT")"
check "newest-block/no-last-step-finding" 1 "$(jq '[.findings[] | select(test("line found in the newest .rcode/agent-log.md entry"))] | length' <<<"$OUT")"
check "newest-block/wave-branch-finding" 1 "$(jq '[.findings[] | select(test("team-lead wave branch"))] | length' <<<"$OUT")"

rm -rf "$REPO_M"

# ─────────────────────────────────────────────────────────────────────────
# N) C15 — phase-gate-check.sh github mode with ZERO GitHub milestones:
#    falls back to the "phase-N" label (via rcode-units.sh's own
#    milestone-or-label phase resolution — the same code path); when
#    NEITHER a milestone NOR the label exists either, a single clear
#    finding names the actual gap instead of an opaque per-run error.
# ─────────────────────────────────────────────────────────────────────────
REPO_N1=$(mktemp -d)
G -C "$REPO_N1" init -q -b main
G -C "$REPO_N1" commit -q --allow-empty -m "seed"
G -C "$REPO_N1" remote add origin https://example.invalid/o/r.git

GH_MAP_N1="$REPO_N1/.gh-map.tsv"
echo '[{"number":7}]' > "$REPO_N1/.probe.json"
echo '[{"number":7,"title":"A","state":"OPEN","milestone":null,"labels":[{"name":"phase-1"}]},{"number":8,"title":"B","state":"CLOSED","milestone":null,"labels":[{"name":"phase-1"}]}]' > "$REPO_N1/.units-rcu.json"
echo '[]' > "$REPO_N1/.milestones.json"
cat > "$GH_MAP_N1" <<EOF
auth status	/dev/null
issue list --limit 1 --json number	${REPO_N1}/.probe.json
issue list --state all --json number,title,state,milestone,labels --limit 1000	${REPO_N1}/.units-rcu.json
api repos/{owner}/{repo}/milestones?state=all&per_page=100 --paginate	${REPO_N1}/.milestones.json
EOF

OUT=$(PATH="$STUBBIN:$PATH" GH_STUB_MAP_FILE="$GH_MAP_N1" bash "$PGC" 1 "$REPO_N1" 2>&1); RC=$?
check "phase-label-fallback/exit0" 0 "$RC"
check "phase-label-fallback/tracker" "github" "$(jq -r .tracker <<<"$OUT")"
check "phase-label-fallback/issues-total" 2 "$(jq -r '.counts.issues_total' <<<"$OUT")"
check "phase-label-fallback/issues-closed" 1 "$(jq -r '.counts.issues_closed' <<<"$OUT")"
check "phase-label-fallback/verdict-block" "BLOCK" "$(jq -r .verdict <<<"$OUT")"
check "phase-label-fallback/finding" 1 "$(jq '[.findings[] | select(test("counted via the .phase-1. label instead"))] | length' <<<"$OUT")"

rm -rf "$REPO_N1"

REPO_N2=$(mktemp -d)
G -C "$REPO_N2" init -q -b main
G -C "$REPO_N2" commit -q --allow-empty -m "seed"
G -C "$REPO_N2" remote add origin https://example.invalid/o/r.git

GH_MAP_N2="$REPO_N2/.gh-map.tsv"
echo '[{"number":7}]' > "$REPO_N2/.probe.json"
echo '[{"number":7,"title":"A","state":"OPEN","milestone":null,"labels":[]}]' > "$REPO_N2/.units-rcu.json"
echo '[]' > "$REPO_N2/.milestones.json"
cat > "$GH_MAP_N2" <<EOF
auth status	/dev/null
issue list --limit 1 --json number	${REPO_N2}/.probe.json
issue list --state all --json number,title,state,milestone,labels --limit 1000	${REPO_N2}/.units-rcu.json
api repos/{owner}/{repo}/milestones?state=all&per_page=100 --paginate	${REPO_N2}/.milestones.json
EOF

OUT=$(PATH="$STUBBIN:$PATH" GH_STUB_MAP_FILE="$GH_MAP_N2" bash "$PGC" 1 "$REPO_N2" 2>&1); RC=$?
check "phase-label-fallback-none/exit1" 1 "$RC"
check "phase-label-fallback-none/ok-false" "false" "$(jq -r .ok <<<"$OUT")"
check "phase-label-fallback-none/clear-error" 1 "$(jq '[.errors[] | select(test("never organized into Phase milestones or phase-1 labels"))] | length' <<<"$OUT")"

rm -rf "$REPO_N2"

# ─────────────────────────────────────────────────────────────────────────
# O) C16 — the monorepo probe: no package.json at the project root, but
#    web/package.json one level down (trivial `true`-command scripts so
#    the test exercises the REAL npm/npx subprocess path, no fixtures/
#    reporters needed) alongside worker/pyproject.toml (deliberately NOT
#    picked up — it has no package.json of its own). Findings/counts come
#    back per-dir-prefixed and summed via the SAME check logic as a
#    single-root project.
# ─────────────────────────────────────────────────────────────────────────
if command -v npm >/dev/null 2>&1; then
  REPO_O=$(mktemp -d)
  G -C "$REPO_O" init -q -b main
  mkdir -p "$REPO_O/web/node_modules" "$REPO_O/worker"
  cat > "$REPO_O/web/package.json" <<'EOF'
{"name":"web","version":"0.0.0","scripts":{"test":"true","build":"true"}}
EOF
  cat > "$REPO_O/worker/pyproject.toml" <<'EOF'
[project]
name = "worker"
EOF
  cat > "$REPO_O/BRAINSTORM.md" <<'EOF'
### Phase 1 — Root

- [x] P-001 — Done thing
EOF
  G -C "$REPO_O" add -A && G -C "$REPO_O" commit -q -m "seed"

  OUT=$(bash "$PGC" 1 "$REPO_O" 2>&1); RC=$?
  check "monorepo/exit0" 0 "$RC"
  check "monorepo/ok-true" "true" "$(jq -r .ok <<<"$OUT")"
  check "monorepo/verdict-not-block" "true" "$(jq -r '.verdict != "BLOCK"' <<<"$OUT")"
  check "monorepo/web-test-finding" 1 "$(jq '[.findings[] | select(test("^\\[web\\] npm test passed"))] | length' <<<"$OUT")"
  check "monorepo/web-build-finding" 1 "$(jq '[.findings[] | select(test("^\\[web\\] npm run build: PASS"))] | length' <<<"$OUT")"
  check "monorepo/no-not-npm-finding" "" "$(jq -r '.findings[] | select(test("not an npm project"))' <<<"$OUT")"
  check "monorepo/tsc-errors-null" "null" "$(jq -c '.counts.tsc_errors' <<<"$OUT")"

  rm -rf "$REPO_O"
else
  echo "  [monorepo] uebersprungen: npm nicht auf PATH" >&2
fi

# ─────────────────────────────────────────────────────────────────────────
# P) N12 — resume-state.sh: a team-lead entry's structured "**Units:**"
#    line is now the SOURCE for in-progress-unit detection, not a
#    whole-block last-match regex. The newest block's "**Directive:**" and
#    "**Next action:**" lines here deliberately mention a DIFFERENT unit
#    (P-099) than the FIRST non-closed unit in "**Units:**" (P-012, since
#    P-013 is listed closed first) — before the N12 fix, the whole-block
#    last-match regex would have picked up P-099 instead.
# ─────────────────────────────────────────────────────────────────────────
REPO_P=$(mktemp -d)
G -C "$REPO_P" init -q -b main
cat > "$REPO_P/BRAINSTORM.md" <<'EOF'
### Phase 1 — Foundation

- [ ] P-012 — Some unit
- [ ] P-013 — Another unit
EOF
mkdir -p "$REPO_P/.rcode"
cat > "$REPO_P/.rcode/agent-log.md" <<'EOF'
## Session: 2026-09-23 09:00 — team-lead

**Date:** 2026-09-23
**Agent:** team-lead
**Stage:** Develop
**Directive:** "fix problem P-099 across the framework"
**Branch:** work/2026-09-23-fix-things
**Units:** P-013 (closed), P-012 (open)
**Decisions:** none
**Next action:** dispatch a worker for P-099 next
EOF
G -C "$REPO_P" add -A && G -C "$REPO_P" commit -q -m "seed"

OUT=$(bash "$RS" "$REPO_P" 2>&1); RC=$?
check "units-line/exit0" 0 "$RC"
check "units-line/in-progress-unit" "P-012" "$(jq -r .in_progress_unit <<<"$OUT")"
check "units-line/finding" 1 "$(jq '[.findings[] | select(test("structured .\\*\\*Units:\\*\\*. line"))] | length' <<<"$OUT")"

rm -rf "$REPO_P"

# ─────────────────────────────────────────────────────────────────────────
# P2) N12 edge case — an EMPTY "**Units:**" value (label present, nothing
#    after it) must not crash under bash 3.2's `set -u` (a truly empty
#    `read -ra` array throws "unbound variable" on `${arr[@]}" without the
#    `${arr[@]+"${arr[@]}"}` guard — see first_unit_not_closed's header
#    comment). Exit must stay 0 and in_progress_unit must be null, not a
#    stray whole-block regex match.
# ─────────────────────────────────────────────────────────────────────────
REPO_P2=$(mktemp -d)
G -C "$REPO_P2" init -q -b main
mkdir -p "$REPO_P2/.rcode"
cat > "$REPO_P2/.rcode/agent-log.md" <<'EOF'
## Session: 2026-09-23 09:00 — team-lead

**Date:** 2026-09-23
**Agent:** team-lead
**Units:**
**Next action:** none
EOF
G -C "$REPO_P2" add -A && G -C "$REPO_P2" commit -q -m "seed"

OUT=$(bash "$RS" "$REPO_P2" 2>&1); RC=$?
check "units-line-empty/exit0" 0 "$RC"
check "units-line-empty/ok-true" "true" "$(jq -r .ok <<<"$OUT")"
check "units-line-empty/in-progress-unit-null" "null" "$(jq -c .in_progress_unit <<<"$OUT")"

rm -rf "$REPO_P2"

# ─────────────────────────────────────────────────────────────────────────
# Q) N1 — resume-state.sh: the free-text "**Directive:**" line must be
#    excluded before phase/issue/plan-unit extraction runs. This entry is
#    NOT from team-lead (so the N12 Units-line path never fires), and its
#    directive mentions "Phase 4" and "issue #42" — neither is real
#    evidence for THIS entry (nothing else in the block mentions a phase
#    or an issue, and there is no PROJECT-STATUS.md/branch convention to
#    cross-check against), so detected_phase and in_progress_issue must
#    both stay null rather than being silently populated from the
#    directive's prose.
# ─────────────────────────────────────────────────────────────────────────
REPO_Q=$(mktemp -d)
G -C "$REPO_Q" init -q -b main
mkdir -p "$REPO_Q/.rcode"
cat > "$REPO_Q/.rcode/agent-log.md" <<'EOF'
## Session: 2026-09-23 09:00 — worker

**Date:** 2026-09-23
**Agent:** worker
**Directive:** "please also look at Phase 4 and issue #42 while you are in there"
**Actions:** investigated something unrelated
EOF
G -C "$REPO_Q" add -A && G -C "$REPO_Q" commit -q -m "seed"

OUT=$(bash "$RS" "$REPO_Q" 2>&1); RC=$?
check "directive-noise/exit0" 0 "$RC"
check "directive-noise/detected-phase-null" "null" "$(jq -c .detected_phase <<<"$OUT")"
check "directive-noise/in-progress-issue-null" "null" "$(jq -c .in_progress_issue <<<"$OUT")"

rm -rf "$REPO_Q"

# ─────────────────────────────────────────────────────────────────────────
# R) N0/N17 — the script's own directory must resolve BEFORE `cd
#    "$PROJECT_DIR"`, so a RELATIVE invocation of a script (relative to
#    the CALLER's original cwd, e.g. `bash scripts/phase-gate-check.sh 1
#    <dir>` from this repo's own root — exactly the shape this suite
#    itself uses everywhere else, absolute-pathed via $PGC/$SM/$RS) still
#    finds rcode-units.sh correctly, even against a target project that
#    has NO "scripts/" subdirectory of its own. Before the fix, this exact
#    combination made the inner `cd "scripts"` resolve against the NEW cwd
#    (the project dir, after the script's own `cd "$PROJECT_DIR"`) instead
#    of the caller's original cwd, and under `set -euo pipefail` that
#    failing `cd` aborted the whole script with a bare shell error and NO
#    JSON on stdout at all.
# ─────────────────────────────────────────────────────────────────────────
REPO_R=$(mktemp -d)
G -C "$REPO_R" init -q -b main
G -C "$REPO_R" commit -q --allow-empty -m "seed"
# deliberately no "$REPO_R/scripts/" subdirectory

is_valid_json() { jq -e . >/dev/null 2>&1 <<<"$1" && echo true || echo false; }

OUT=$(cd "$SCRIPTS_DIR/.." && bash "scripts/phase-gate-check.sh" 1 "$REPO_R" 2>&1)
check "relative-self/pgc-valid-json" "true" "$(is_valid_json "$OUT")"
check "relative-self/pgc-tracker" "plan" "$(jq -r '.tracker // empty' <<<"$OUT" 2>/dev/null)"

OUT=$(cd "$SCRIPTS_DIR/.." && bash "scripts/status-metrics.sh" "$REPO_R" 2>&1)
check "relative-self/sm-valid-json" "true" "$(is_valid_json "$OUT")"
check "relative-self/sm-tracker" "plan" "$(jq -r '.tracker // empty' <<<"$OUT" 2>/dev/null)"

OUT=$(cd "$SCRIPTS_DIR/.." && bash "scripts/resume-state.sh" "$REPO_R" 2>&1); RC=$?
check "relative-self/rs-valid-json" "true" "$(is_valid_json "$OUT")"
check "relative-self/rs-exit0" 0 "$RC"

# R2) final-check fix — a RELATIVE project-dir argument (relative to the
#     caller's cwd) must be canonicalized before the script's own cd, so the
#     later rcode-units.sh call does not resolve it a second time against the
#     already-changed cwd ("project directory does not exist").
R_PARENT=$(dirname "$REPO_R"); R_BASE=$(basename "$REPO_R")
OUT=$(cd "$R_PARENT" && bash "$PGC" 1 "$R_BASE" 2>&1)
check "relative-projdir/pgc-tracker" "plan" "$(jq -r '.tracker // empty' <<<"$OUT" 2>/dev/null)"
check "relative-projdir/pgc-no-missing-dir" "" "$(jq -r '.errors[]? | select(test("does not exist"))' <<<"$OUT" 2>/dev/null)"
OUT=$(cd "$R_PARENT" && bash "$SM" "$R_BASE" 2>&1)
check "relative-projdir/sm-tracker" "plan" "$(jq -r '.tracker // empty' <<<"$OUT" 2>/dev/null)"
OUT=$(cd "$R_PARENT" && bash "$RS" "$R_BASE" 2>&1)
check "relative-projdir/rs-tracker" "plan" "$(jq -r '.tracker // empty' <<<"$OUT" 2>/dev/null)"

rm -rf "$REPO_R"

# ─────────────────────────────────────────────────────────────────────────
# S) N18 — PARTIAL unknown-completion count (some units known, some not,
#    within the SAME phase — two consecutive tables under one heading: the
#    first carries a Status column, the second does not). counts.
#    issues_open/issues_closed must stay NUMERIC and cover only the KNOWN
#    units; counts.issues_unknown must be >0 but < issues_total; a finding
#    names the gap. (The ALL-unknown case is covered by the REPO_C/REPO_K
#    extensions above — this fixture is the partial case specifically.)
# ─────────────────────────────────────────────────────────────────────────
REPO_S=$(mktemp -d)
G -C "$REPO_S" init -q -b main
cat > "$REPO_S/BRAINSTORM.md" <<'EOF'
### Phase 1 — Mixed

| ID | Title | Status |
|---|---|---|
| P-001 | Known closed | Done |
| P-002 | Known open | open |

| ID | Title | Type |
|---|---|---|
| P-003 | Unknown one | feat |
EOF
G -C "$REPO_S" add -A && G -C "$REPO_S" commit -q -m "seed"

OUT=$(bash "$SM" "$REPO_S" 2>&1)
check "partial-unknown/sm-issues-total" 3 "$(jq -r '.counts.issues_total' <<<"$OUT")"
check "partial-unknown/sm-issues-open" 1 "$(jq -r '.counts.issues_open' <<<"$OUT")"
check "partial-unknown/sm-issues-closed" 1 "$(jq -r '.counts.issues_closed' <<<"$OUT")"
check "partial-unknown/sm-issues-unknown" 1 "$(jq -r '.counts.issues_unknown' <<<"$OUT")"
check "partial-unknown/sm-partial-finding" 1 "$(jq '[.findings[] | select(test("completion not recorded for 1 of 3"))] | length' <<<"$OUT")"

OUT=$(bash "$PGC" 1 "$REPO_S" 2>&1)
check "partial-unknown/pgc-issues-total" 3 "$(jq -r '.counts.issues_total' <<<"$OUT")"
check "partial-unknown/pgc-issues-closed" 1 "$(jq -r '.counts.issues_closed' <<<"$OUT")"
check "partial-unknown/pgc-issues-unknown" 1 "$(jq -r '.counts.issues_unknown' <<<"$OUT")"
check "partial-unknown/pgc-verdict-block" "BLOCK" "$(jq -r .verdict <<<"$OUT")"

rm -rf "$REPO_S"

# ─────────────────────────────────────────────────────────────────────────
# J) --help auf allen vieren: exit 0, kein Absturz.
# ─────────────────────────────────────────────────────────────────────────
for s in "$RCU" "$SM" "$PGC" "$RS"; do
  bash "$s" --help >/dev/null 2>&1
  check "help/$(basename "$s")-exit0" 0 "$?"
done

rm -rf "$STUBROOT"

printf '── gather-scripts-regression: %d bestanden, %d fehlgeschlagen ──\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
