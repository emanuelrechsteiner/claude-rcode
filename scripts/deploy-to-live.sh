#!/usr/bin/env bash
# Übergabe vom Bauhof (SSD-Arbeitskopie) ins bewohnte Haus (~/.claude).
#
# Warum es diesen Schritt gibt: Änderungen an Regeln/Hooks/Skills wirken in
# ~/.claude sofort — man saniert die Elektrik, während der Strom anliegt.
# Entwickelt wird deshalb im Bauhof; dieses Skript ist die bewusste Abnahme.
#
# Laufzeitpräferenzen (seit 2026-08-04):
#   Claude Code schreibt einige Werte im Betrieb selbst nach ~/.claude/settings.json
#   (etwa beim Umschalten des Modells). Das machte das Haus "schmutzig" und blockierte
#   jede Übergabe, bis jemand die Werte von Hand in den Bauhof nachtrug.
#   Dieses Skript zieht sie jetzt selbst zurück: Werte aus dem Haus -> Bauhof,
#   dort ein eigener Commit, danach ist das Haus wieder ein sauberer Spiegel.
#   Der Umweg ueber eine ~/.claude/settings.local.json funktioniert NICHT — auf
#   Nutzerebene liest Claude Code diese Datei nicht (geprueft 2026-08-04).
#
# Aufruf:  deploy-to-live.sh [config|cockpit|all]   (Vorgabe: all)
set -euo pipefail

WORKSHOP_ROOT="${CLAUDE_WORKSHOP_ROOT:-/Volumes/YourExternalVolume/1-PROJECTS/Development/5-AI-APPS}"
LIVE_CONFIG="${CLAUDE_LIVE_CONFIG:-$HOME/.claude}"
LIVE_COCKPIT="${CLAUDE_LIVE_COCKPIT:-$LIVE_CONFIG/cockpit}"
TARGET="${1:-all}"

# Laufzeitschluessel, die dem HAUS gehoeren: Claude Code schreibt sie im Betrieb
# selbst nach ~/.claude/settings.json. Jeder Eintrag ist ein jq-PFAD (Array von
# Feldnamen, getpath/setpath/delpaths-kompatibel) — ["model"] fuer einen
# Top-Level-Schluessel, ["permissions","defaultMode"] fuer einen verschachtelten.
# Bewusst kurz gehalten — jeder Eintrag hier schaltet eine Schutzpruefung fuer
# GENAU diesen Pfad ab; verschachtelte Geschwister (z.B. permissions.allow/deny/ask
# neben permissions.defaultMode) bleiben geschuetzt. Weicht das Haus in einem NICHT
# gelisteten Pfad ab, bricht die Uebergabe weiterhin ab (fail-loud.md). Erweitern
# nur mit Beleg, dass Claude Code den Wert selbst schreibt.
#
#   ["model"]                      — /model-Umschalter (seit 2026-08-04, IMP-127)
#   ["effortLevel"]                — /config-Effort-Umschalter (seit 2026-08-04, IMP-127)
#   ["theme"]                      — der /config-Themenwahl-Umschalter schreibt die
#                                     Theme-Wahl direkt nach settings.json (beobachtet:
#                                     "light-daltonized" -> "dark-daltonized")
#   ["permissions","defaultMode"]  — der Berechtigungsmodus-Umschalter schreibt
#                                     permissions.defaultMode (beobachtet:
#                                     "dontAsk" -> "auto"). NUR dieser Unterschluessel
#                                     ist Laufzeitschutt — permissions.allow/deny/ask
#                                     bleiben geschuetzt und loesen bei Abweichung
#                                     weiterhin ABBRUCH aus.
#   ["autoMode"]                   — die Auto-Modus-Einrichtung legt einen neuen
#                                     autoMode-Block mit environment-Array an.
#                                     ACHTUNG VEROEFFENTLICHUNG: autoMode.environment
#                                     kann private Projektangaben tragen. settings.json
#                                     ist publish-gebunden — vor einer
#                                     Publisher-Reaktivierung muss ein Transform in
#                                     publish-transforms.d/ den autoMode-Block strippen;
#                                     bis dahin faengt scrub-check die Pfad-Muster
#                                     (fail-loud).
RUNTIME_KEYS_JSON='[["model"],["effortLevel"],["theme"],["permissions","defaultMode"],["autoMode"],["modelSettings"]]'

# Reiner Betriebsschutt im Haus: von Claude Code staendig neu geschrieben, seit
# 2026-08-04 nicht mehr versioniert. Wird ueber die Uebergabe hinweg gerettet.
VOLATILE_FILES=(plugins/installed_plugins.json plugins/known_marketplaces.json)

fail() { printf '\033[31mABBRUCH: %s\033[0m\n' "$1" >&2; exit 1; }
note() { printf '\033[36m▸ %s\033[0m\n' "$1"; }
warn() { printf '\033[33m! %s\033[0m\n' "$1"; }

[ -d "$WORKSHOP_ROOT" ] || fail "Bauhof nicht erreichbar: $WORKSHOP_ROOT (SSD eingehängt?)"
command -v jq >/dev/null || fail "jq wird gebraucht, ist aber nicht installiert."

# Alles ausser den Laufzeitschluesseln — der Teil, der uebereinstimmen MUSS.
# $k ist bereits eine Liste von Pfaden (Arrays), delpaths nimmt sie direkt.
strip_runtime_keys() {
  jq -S --argjson k "$RUNTIME_KEYS_JSON" 'delpaths($k)' "$1"
}

# Zieht die im Haus verstellten Laufzeitwerte in den Bauhof zurueck.
# Bricht ab, wenn das Haus AUSSERHALB dieser Schluessel abweicht.
sync_runtime_prefs() {
  local workshop="$1" live="$2"
  local ws_settings="$workshop/settings.json" live_settings="$live/settings.json"

  [ -f "$live_settings" ] || return 0
  git -C "$live" diff --quiet -- settings.json && return 0   # unveraendert, nichts zu tun

  note "config — Laufzeitpräferenzen aus dem Haus prüfen"

  local head_settings; head_settings=$(mktemp)
  git -C "$live" show HEAD:settings.json > "$head_settings" 2>/dev/null \
    || fail "config: settings.json ist im Haus nicht versioniert — bitte von Hand klären."

  if ! diff -q <(strip_runtime_keys "$head_settings") <(strip_runtime_keys "$live_settings") >/dev/null; then
    rm -f "$head_settings"
    git -C "$live" diff -- settings.json
    fail "config: Das Haus weicht in settings.json AUSSERHALB der Laufzeitschlüssel ab ($(jq -r '[.[] | join(".")] | join(", ")' <<<"$RUNTIME_KEYS_JSON")).
      Das ist eine Änderung von Hand am bewohnten Haus — sie gehört in den Bauhof.
      Entweder dort nachbauen und hier verwerfen (git -C '$live' checkout -- settings.json),
      oder — wenn Claude Code den Wert nachweislich selbst schreibt — den Schlüssel in
      RUNTIME_KEYS_JSON in diesem Skript ergänzen."
  fi
  rm -f "$head_settings"

  # Werte uebernehmen: Haus gewinnt fuer genau diese Schluessel.
  # OHNE -S: die Schlüsselreihenfolge der Datei muss erhalten bleiben, sonst
  # erzeugt die erste Übergabe statt zwei geänderter Zeilen einen Komplettumbau.
  # "has" gibt es fuer Pfade nicht direkt — getpath()!=null steht stellvertretend
  # dafuer (kein Laufzeitschluessel hier traegt legitim den Wert null).
  local merged; merged=$(mktemp)
  jq --argjson k "$RUNTIME_KEYS_JSON" --slurpfile live "$live_settings" \
     'reduce $k[] as $path (.; if (($live[0] | getpath($path)) != null) then setpath($path; $live[0] | getpath($path)) else . end)' \
     "$ws_settings" > "$merged" || { rm -f "$merged"; fail "config: Zusammenführen der settings.json fehlgeschlagen."; }

  if diff -q <(jq -S . "$ws_settings") <(jq -S . "$merged") >/dev/null; then
    rm -f "$merged"
    note "config: Laufzeitpräferenzen im Bauhof bereits aktuell"
    return 0
  fi

  local changed; changed=$(jq -rn --argjson k "$RUNTIME_KEYS_JSON" \
    --slurpfile live "$live_settings" --slurpfile ws "$ws_settings" \
    '[$k[] | . as $path
       | (($live[0] | getpath($path)) // null) as $lv
       | (($ws[0]   | getpath($path)) // null) as $wv
       | select($lv != $wv)
       | "\($path | join(".")): \($wv // "—") → \($lv // "—")"] | join(", ")')

  # Erst prüfen, dann überschreiben — eine kaputte settings.json startet Claude Code
  # still ohne Hooks und ohne Berechtigungen.
  jq -e 'has("hooks") and has("permissions")' "$merged" >/dev/null \
    || { rm -f "$merged"; fail "config: erzeugte settings.json ist unvollständig (hooks/permissions fehlen) — nichts geschrieben."; }

  # Keine Sicherungskopie daneben: die Datei ist an dieser Stelle unverändert
  # committet, also ist der Bauhof-Commit selbst die Sicherung. Sollte das
  # Schreiben abbrechen, stellt `git -C <bauhof> checkout -- settings.json` sie her.
  # (Eine Kopie im Arbeitsverzeichnis liesse die folgende Sauberkeitsprüfung
  #  durchfallen — genau daran ist die erste Fassung gescheitert.)
  cat "$merged" > "$ws_settings"
  rm -f "$merged"

  note "config: Laufzeitpräferenzen in den Bauhof zurückgezogen ($changed)"
  git -C "$workshop" add settings.json
  git -C "$workshop" commit -q -m "chore(config): Laufzeitpräferenzen aus dem Haus nachgezogen ($changed)"
  note "config: Bauhof-Commit $(git -C "$workshop" rev-parse --short HEAD)"
}

# Schreibt die Abnahmeliste fuer die naechste Sitzung (IMP-147). Nur fuer
# "config" aufgerufen — nur dort landen Hook-/Regel-/Skill-Aenderungen, die
# eine Verifikation IN einer neuen Claude-Code-Sitzung brauchen; Cockpit-
# Aenderungen prueft der Cockpit-Bauhof selbst (npm test/typecheck).
# Ueberschreibt eine vorhandene Datei bewusst — die alte Pruefliste ist mit
# der neuen Uebergabe obsolet (fail-loud: kein Anhaengen, keine Altlast).
write_pending_verification() {
  local live="$1" before="$2" after="$3"
  local out="$live/pending-verification.md"
  local subjects; subjects=$(git -C "$live" log --format='- [ ] %s' "$before..$after")
  {
    printf '# Offene Abnahme — Übergabe %s\n\n' "$(date '+%Y-%m-%d %H:%M')"
    printf 'Commit-Bereich: %s..%s\n\n' "$before" "$after"
    printf '## Prüfschritte\n\n'
    printf '%s\n' "$subjects"
    printf '\nPrüfschritte laut Abnahmeprotokoll der Sitzung.\n'
  } > "$out"
  note "config: Abnahmeliste geschrieben → $out"
}

deploy() {
  local name="$1" workshop="$2" live="$3"
  [ -d "$workshop/.git" ] || fail "$name: kein Repo im Bauhof ($workshop)"
  [ -d "$live/.git" ]     || fail "$name: kein Repo im Haus ($live)"

  # Muss VOR der Bauhof-Prüfung laufen — der Rückzug erzeugt dort einen Commit.
  [ "$name" = "config" ] && sync_runtime_prefs "$workshop" "$live"

  note "$name — Bauhof prüfen"
  if [ -n "$(git -C "$workshop" status --porcelain)" ]; then
    git -C "$workshop" status --short
    fail "$name: Bauhof hat uneingecheckte Änderungen. Erst committen, dann übergeben."
  fi

  note "$name — Haus prüfen"
  local dirty tolerated=() remaining=()
  dirty=$(git -C "$live" diff --name-only HEAD --)
  if [ -n "$dirty" ]; then
    [ "$name" = "config" ] && tolerated=(settings.json "${VOLATILE_FILES[@]}")
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      local ok=0
      for t in ${tolerated[@]+"${tolerated[@]}"}; do [ "$f" = "$t" ] && ok=1; done
      [ "$ok" = 1 ] || remaining+=("$f")
    done <<< "$dirty"
  fi
  if [ ${#remaining[@]} -gt 0 ]; then
    printf '  %s\n' "${remaining[@]}"
    fail "$name: Das Haus hat lokale Änderungen an verfolgten Dateien (oben). Diese gehören in den Bauhof — dort nachbauen, hier verwerfen."
  fi

  # Betriebsschutt über die Übergabe hinweg retten: der Fast-Forward entfernt die
  # Dateien aus der Versionierung, Claude Code soll sie danach unverändert vorfinden.
  local stash; stash=$(mktemp -d)
  if [ "$name" = "config" ]; then
    for f in "${VOLATILE_FILES[@]}"; do
      [ -f "$live/$f" ] && { mkdir -p "$stash/$(dirname "$f")"; cp "$live/$f" "$stash/$f"; }
    done
  fi

  # Haus auf den Commit-Stand zurücksetzen — nur so ist ein Fast-Forward möglich.
  if [ -n "$dirty" ]; then
    note "$name — Haus auf den Commit-Stand zurücksetzen"
    git -C "$live" checkout -- . 2>/dev/null || true
  fi

  local before after
  before=$(git -C "$live" rev-parse --short HEAD)
  note "$name — übernehme aus dem Bauhof"
  git -C "$live" pull --ff-only workshop main
  after=$(git -C "$live" rev-parse --short HEAD)

  if [ "$name" = "config" ]; then
    for f in "${VOLATILE_FILES[@]}"; do
      if [ -f "$stash/$f" ]; then
        mkdir -p "$live/$(dirname "$f")"
        cp "$stash/$f" "$live/$f"
      fi
    done
  fi
  rm -rf "$stash"

  if [ "$before" = "$after" ]; then
    note "$name: bereits aktuell ($after)"
  else
    note "$name: $before → $after"
    git -C "$live" log --oneline "$before..$after"
    # if/fi, NICHT `[ … ] && …`: als letzte Zeile der Funktion lieferte der
    # falsche Test beim Cockpit Exit 1, und set -e brach vor `npm install` ab
    # (Befund 2026-09-24, Regression "cockpit-neu" in deploy-regression.sh).
    if [ "$name" = "config" ]; then
      write_pending_verification "$live" "$before" "$after"
    fi
  fi
}

case "$TARGET" in
  config)  deploy "config"  "$WORKSHOP_ROOT/claude-code-config" "$LIVE_CONFIG" ;;
  cockpit) deploy "cockpit" "$WORKSHOP_ROOT/cockpit"            "$LIVE_COCKPIT" ;;
  all)     deploy "config"  "$WORKSHOP_ROOT/claude-code-config" "$LIVE_CONFIG"
           deploy "cockpit" "$WORKSHOP_ROOT/cockpit"            "$LIVE_COCKPIT" ;;
  *)       fail "unbekanntes Ziel: $TARGET (erlaubt: config, cockpit, all)" ;;
esac

if [ "$TARGET" = "cockpit" ] || [ "$TARGET" = "all" ]; then
  note "cockpit — Abhängigkeiten abgleichen"
  ( cd "$LIVE_COCKPIT" && npm install --no-fund --no-audit --silent )
fi

printf '\033[32m✔ Übergabe abgeschlossen.\033[0m Hook-/Regeländerungen greifen ab der NÄCHSTEN Claude-Sitzung.\n'
