#!/usr/bin/env bash
# Regressionssuite fuer scripts/deploy-to-live.sh — der Laufzeitpraeferenz-Rueckzug.
#
# Warum es diese Suite gibt: Das Uebergabe-Werkzeug setzt im BEWOHNTEN Haus
# verfolgte Dateien auf den Commit-Stand zurueck (git checkout -- .). Ein Fehler
# darin loescht echte Arbeit. Geprueft wird deshalb an zwei Attrappen-Repos in
# einem Temporaerverzeichnis; das echte ~/.claude wird nie angefasst.
#
# Aufruf:  bash scripts/tests/deploy-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$SCRIPT_DIR/../deploy-to-live.sh"
[ -f "$DEPLOY" ] || { echo "deploy-to-live.sh nicht gefunden: $DEPLOY" >&2; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf '  [%s] %s\n' "$1" "$2"; }
check(){ # check <name> <erwartet> <bekommen>
  if [ "$2" = "$3" ]; then ok; else bad "$1" "erwartet='$2' bekommen='$3'"; fi
}

G() { git -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }

# Eine settings.json mit STABILER Schluesselreihenfolge: model steht vorne,
# effortLevel hinten — genau wie in der echten Datei, damit die Suite auch
# eine Umsortierung durch jq entlarven wuerde. permissions.defaultMode und
# theme sind mit drin (wie in der echten Datei), damit ein reiner
# Laufzeitschluessel-Rueckzug an ihnen NICHT zum Komplettumbau fuehrt.
make_settings() { # make_settings <model> <effort>
  cat <<EOF
{
  "model": "$1",
  "theme": "light-daltonized",
  "hooks": {
    "SessionStart": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "echo hallo" } ] }
    ]
  },
  "permissions": { "allow": [ "Read" ], "defaultMode": "dontAsk" },
  "env": { "MAX_THINKING_TOKENS": "30000" },
  "effortLevel": "$2"
}
EOF
}

setup() { # setup -> setzt WS und LIVE
  ROOT=$(mktemp -d)
  WS="$ROOT/workshop/claude-code-config"
  LIVE="$ROOT/live"
  mkdir -p "$WS/plugins"          # LIVE NICHT anlegen — git clone will ein leeres Ziel

  make_settings sonnet low > "$WS/settings.json"
  echo "Regel A" > "$WS/rules-a.md"
  echo '{"state":"alt"}' > "$WS/plugins/installed_plugins.json"
  G -C "$WS" init -q -b main
  G -C "$WS" add -A && G -C "$WS" commit -q -m "Grundstand"

  G clone -q "$WS" "$LIVE"
  G -C "$LIVE" remote add workshop "$WS"
  G -C "$LIVE" config user.name Test
  G -C "$LIVE" config user.email test@example.invalid
}

teardown() { rm -rf "$ROOT"; }

run_deploy() { # -> gibt Exit-Code zurueck, Ausgabe in $OUT
  OUT=$(CLAUDE_WORKSHOP_ROOT="$ROOT/workshop" CLAUDE_LIVE_CONFIG="$LIVE" \
        bash "$DEPLOY" config 2>&1)
  return $?
}

# ── A) Beide Seiten sauber: Fast-Forward geht durch ────────────────────────────
setup
echo "Regel B" > "$WS/rules-b.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Regel B"
run_deploy; RC=$?
check "sauber/exit0"            0 "$RC"
check "sauber/regel-angekommen" 1 "$([ -f "$LIVE/rules-b.md" ] && echo 1 || echo 0)"
teardown

# ── B) Haus hat Laufzeitdrift: Werte werden in den Bauhof zurueckgezogen ───────
setup
make_settings "opus[1m]" high > "$LIVE/settings.json"     # wie /model + /config es tun
echo "Regel C" > "$WS/rules-c.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Regel C"
run_deploy; RC=$?
check "drift/exit0"                0 "$RC"
check "drift/haus-sauber"          "" "$(G -C "$LIVE" status --porcelain --untracked-files=no)"
check "drift/haus-behaelt-modell"  "opus[1m]" "$(jq -r .model "$LIVE/settings.json")"
check "drift/haus-behaelt-effort"  "high"     "$(jq -r .effortLevel "$LIVE/settings.json")"
check "drift/bauhof-nachgezogen"   "opus[1m]" "$(jq -r .model "$WS/settings.json")"
check "drift/eigener-commit"       1 "$(G -C "$WS" log --oneline -1 | grep -c 'Laufzeitpräferenzen')"
check "drift/regel-angekommen"     1 "$([ -f "$LIVE/rules-c.md" ] && echo 1 || echo 0)"
# Reihenfolge muss erhalten bleiben: model zuerst, effortLevel zuletzt
check "drift/reihenfolge-erhalten" "model effortLevel" \
      "$(jq -r 'keys_unsorted | [first, last] | join(" ")' "$WS/settings.json")"
check "drift/hooks-unversehrt"     1 "$(jq '.hooks | has("SessionStart")' "$WS/settings.json" | grep -c true)"
teardown

# ── C) Haus wurde von Hand an einem NICHT-Laufzeitschluessel geaendert → Abbruch ─
setup
jq '.permissions.allow += ["Bash(rm *)"]' "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
run_deploy; RC=$?
check "handedit/bricht-ab"        1 "$RC"
check "handedit/nennt-den-grund"  1 "$(echo "$OUT" | grep -c 'AUSSERHALB der Laufzeitschlüssel')"
check "handedit/nichts-verworfen" 1 "$(jq '[.permissions.allow[] | select(. == "Bash(rm *)")] | length' "$LIVE/settings.json")"
teardown

# ── D) Haus wurde an einer anderen verfolgten Datei geaendert → Abbruch ────────
setup
echo "im Haus von Hand geaendert" > "$LIVE/rules-a.md"
run_deploy; RC=$?
check "fremddatei/bricht-ab"        1 "$RC"
check "fremddatei/nichts-verworfen" "im Haus von Hand geaendert" "$(cat "$LIVE/rules-a.md")"
teardown

# ── E) Betriebsschutt ueberlebt die Uebergabe ─────────────────────────────────
setup
echo '{"state":"aktuell-im-haus"}' > "$LIVE/plugins/installed_plugins.json"
G -C "$WS" rm -q --cached plugins/installed_plugins.json
printf 'plugins/installed_plugins.json\n' >> "$WS/.gitignore"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Plugin-Zustand entversioniert"
run_deploy; RC=$?
check "schutt/exit0"            0 "$RC"
check "schutt/inhalt-erhalten"  '{"state":"aktuell-im-haus"}' "$(cat "$LIVE/plugins/installed_plugins.json" 2>/dev/null)"
teardown

# ── F) Bauhof schmutzig → Abbruch (unveraendertes Altverhalten) ────────────────
setup
echo "unfertig" > "$WS/rules-d.md"
run_deploy; RC=$?
check "bauhof-schmutzig/bricht-ab" 1 "$RC"
check "bauhof-schmutzig/grund"     1 "$(echo "$OUT" | grep -c 'uneingecheckte Änderungen')"
teardown

# ── G) Haus weicht NUR im theme ab → Rueckzug (verschachtelte Pfad-Erweiterung,
#      hier top-level, deckt aber denselben Codepfad ab wie permissions.defaultMode) ─
setup
jq '.theme = "dark-daltonized"' "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
echo "Regel G" > "$WS/rules-g.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Regel G"
run_deploy; RC=$?
check "theme/exit0"              0 "$RC"
check "theme/haus-behaelt-wert"  "dark-daltonized" "$(jq -r .theme "$LIVE/settings.json")"
check "theme/bauhof-nachgezogen" "dark-daltonized" "$(jq -r .theme "$WS/settings.json")"
check "theme/eigener-commit"     1 "$(G -C "$WS" log --oneline -1 | grep -c 'Laufzeitpräferenzen')"
check "theme/regel-angekommen"   1 "$([ -f "$LIVE/rules-g.md" ] && echo 1 || echo 0)"
teardown

# ── H) Haus weicht NUR in permissions.defaultMode ab (verschachtelter Pfad)
#      → Rueckzug, permissions.allow bleibt dabei unangetastet ─────────────────
setup
jq '.permissions.defaultMode = "auto"' "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
echo "Regel H" > "$WS/rules-h.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Regel H"
run_deploy; RC=$?
check "defaultmode/exit0"              0 "$RC"
check "defaultmode/haus-behaelt-wert"  "auto" "$(jq -r .permissions.defaultMode "$LIVE/settings.json")"
check "defaultmode/bauhof-nachgezogen" "auto" "$(jq -r .permissions.defaultMode "$WS/settings.json")"
check "defaultmode/allow-unangetastet" '["Read"]' "$(jq -c .permissions.allow "$WS/settings.json")"
check "defaultmode/eigener-commit"     1 "$(G -C "$WS" log --oneline -1 | grep -c 'Laufzeitpräferenzen')"
teardown

# ── I) Der Schutz, der nicht aufweichen darf: permissions.defaultMode UND
#      permissions.allow gleichzeitig geaendert → weiterhin ABBRUCH. Die
#      Ausnahme fuer defaultMode darf ihren permissions-Nachbarn nicht mitreissen. ─
setup
jq '.permissions.defaultMode = "auto" | .permissions.allow += ["Bash(rm *)"]' \
   "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
run_deploy; RC=$?
check "permissions-nachbarn-geschuetzt/bricht-ab"        1 "$RC"
check "permissions-nachbarn-geschuetzt/nennt-den-grund"  1 "$(echo "$OUT" | grep -c 'AUSSERHALB der Laufzeitschlüssel')"
check "permissions-nachbarn-geschuetzt/nichts-verworfen" 1 "$(jq '[.permissions.allow[] | select(. == "Bash(rm *)")] | length' "$LIVE/settings.json")"
teardown

# ── J) Haus hat einen neuen autoMode-Block → Rueckzug (Pfad existiert im Bauhof
#      vorher gar nicht — prueft das Anlegen neuer Pfade per setpath) ──────────
setup
jq '.autoMode = {"environment": ["FOO=bar"]}' "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
echo "Regel J" > "$WS/rules-j.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Regel J"
run_deploy; RC=$?
check "automode/exit0"              0 "$RC"
check "automode/haus-behaelt-block"  '{"environment":["FOO=bar"]}' "$(jq -cS .autoMode "$LIVE/settings.json")"
check "automode/bauhof-nachgezogen"  '{"environment":["FOO=bar"]}' "$(jq -cS .autoMode "$WS/settings.json")"
check "automode/eigener-commit"      1 "$(G -C "$WS" log --oneline -1 | grep -c 'Laufzeitpräferenzen')"
check "automode/regel-angekommen"    1 "$([ -f "$LIVE/rules-j.md" ] && echo 1 || echo 0)"
teardown

# ── K) Bestandsschutz-Pin: Haus weicht in einem NICHT gelisteten Schluessel ab
#      (hooks) → weiterhin ABBRUCH mit Diff, egal wie viele Laufzeitpfade es gibt ─
setup
jq '.hooks.SessionStart[0].hooks[0].command = "echo veraendert"' \
   "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
run_deploy; RC=$?
check "hooks-ungelistet/bricht-ab"       1 "$RC"
check "hooks-ungelistet/nennt-den-grund" 1 "$(echo "$OUT" | grep -c 'AUSSERHALB der Laufzeitschlüssel')"
check "hooks-ungelistet/zeigt-diff"      1 "$(echo "$OUT" | grep -c 'echo veraendert')"
check "hooks-ungelistet/nichts-verworfen" "echo veraendert" \
      "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$LIVE/settings.json")"
teardown

# ── L) Übergabe mit echten Commits schreibt pending-verification.md mit den
#      Commit-Subjects als Checkliste + Standardzeile (IMP-147) ────────────────
setup
echo "Regel L" > "$WS/rules-l.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Regel L: neue Pruefung"
run_deploy; RC=$?
check "pending/checkliste-und-standardzeile" 1 "$([ -f "$LIVE/pending-verification.md" ] \
      && grep -qF -- '- [ ] Regel L: neue Pruefung' "$LIVE/pending-verification.md" \
      && grep -q 'Prüfschritte laut Abnahmeprotokoll der Sitzung' "$LIVE/pending-verification.md" \
      && echo 1 || echo 0)"
teardown

# ── M) Zweite Übergabe überschreibt die Abnahmeliste — die alte Prüfung ist
#      mit der neuen Übergabe obsolet ───────────────────────────────────────
setup
echo "Regel M1" > "$WS/rules-m1.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Regel M1: erste Pruefung"
run_deploy
echo "Regel M2" > "$WS/rules-m2.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Regel M2: zweite Pruefung"
run_deploy; RC=$?
check "pending-overwrite/alte-weg-neue-da" 1 "$(! grep -q 'Regel M1: erste Pruefung' "$LIVE/pending-verification.md" \
      && grep -q 'Regel M2: zweite Pruefung' "$LIVE/pending-verification.md" \
      && echo 1 || echo 0)"
teardown

# ── N) Haus hat einen neuen modelSettings-Block (Aufwandsstufe je Modell — von
#      /model + /effort geschrieben, beobachtet mit claude 2.1.266) → Rueckzug
#      wie autoMode. Belegt 2026-09-09: die Uebergabe brach genau daran ab. ──────
setup
jq '.modelSettings = {"claude-sonnet-5": {"effortLevel": "xhigh"}}' \
   "$LIVE/settings.json" > "$LIVE/s.tmp" && mv "$LIVE/s.tmp" "$LIVE/settings.json"
echo "Regel N" > "$WS/rules-n.md"
G -C "$WS" add -A && G -C "$WS" commit -q -m "Regel N"
run_deploy; RC=$?
check "modelsettings/exit0"              0 "$RC"
check "modelsettings/haus-behaelt-block" '{"claude-sonnet-5":{"effortLevel":"xhigh"}}' "$(jq -cS .modelSettings "$LIVE/settings.json")"
check "modelsettings/bauhof-nachgezogen" '{"claude-sonnet-5":{"effortLevel":"xhigh"}}' "$(jq -cS .modelSettings "$WS/settings.json")"
check "modelsettings/eigener-commit"     1 "$(G -C "$WS" log --oneline -1 | grep -c 'Laufzeitpräferenzen')"
check "modelsettings/regel-angekommen"   1 "$([ -f "$LIVE/rules-n.md" ] && echo 1 || echo 0)"
teardown

printf '── deploy-regression: %d bestanden, %d fehlgeschlagen ──\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
