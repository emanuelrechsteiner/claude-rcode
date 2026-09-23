#!/usr/bin/env bash
# run-log v1.0 — Lauf-Beleg fuer die daily-docs-Routine (Paragraph C der SKILL.md).
#
# ZWECK: Die Zeile in daily-docs-log.jsonl ist der EINZIGE Beweis, dass ein Lauf
# stattgefunden hat (IMP-075). Sie war bisher der LETZTE Schritt und hatte selbst
# kein Artefakt — jeder Abbruch nach Paragraph A/B erzeugte Artefakte OHNE Beleg.
# Real aufgetreten 2026-07-31 (Lauf fuer 2026-07-30): Logbuch geschrieben, Notion
# aktualisiert, dann `[Request interrupted by user]` 11 Sekunden nach Beginn von
# Paragraph C — Datumsreihe sprang 2026-07-29 -> 2026-07-31, jede Abdeckungspruefung
# meldete FALSCH-NEGATIV "nie gelaufen".
#
# VERTRAG (zweiphasig, EINE Zeile pro Datum, Upgrade in-place):
#   1. `start`  — ALLERERSTE dauerhafte Aktion des Laufs, vor Zaehlung/Logbuch/Notion.
#                 Schreibt status:"partial". Ab hier ist ein Abbruch SICHTBAR.
#   2. `finish` — nach Paragraph A+B. Hebt dieselbe Zeile auf status:"ok" an.
#      `fail`   — bei Skript-ABORT o.ae. Setzt status:"fail" + reason, OHNE Zahlen.
#
# Warum Skript und nicht Prosa: dieselbe Lehre wie bei der Zaehlung (2026-07-18,
# logbook-count.sh ersetzte die Agenten-Schaetzung). Ein Agent, der abbricht, fuehrt
# keine Prosa-Anweisung mehr aus; ein Aufruf, der als erstes passiert, ist dagegen
# schon passiert. Zusaetzlich verhindert der jq-Aufbau aus count.json das Abtippen
# der Zertifikatsfelder (historische Fehlerquelle: "85 Commits" statt 83).
set -euo pipefail

LOG_DEFAULT="/Users/your-username/.claude/global-observation/daily-docs-log.jsonl"
# Hardcoded mit Absicht — dieselbe Begruendung wie beim Logbuch-Pfad in der SKILL.md:
# eine Pflicht-Env-Variable, die der Scheduler nicht setzt, ist der Ur-Defekt in neuer
# Gestalt (${LOGBOOK_DIR} expandierte still zu leer). Override nur fuer Tests/Backfill.
LOG="${DAILY_DOCS_LOG:-$LOG_DEFAULT}"

die() { echo "ABORT: $*" >&2; exit 1; }
usage() {
  cat >&2 <<'EOF'
Aufruf:
  run-log.sh start  <YYYY-MM-DD>
  run-log.sh finish <YYYY-MM-DD> --count-json <pfad> --logbook <pfad>
                    [--notion-page-id <id>] [--notion-modus <text>]
                    [--status ok|partial] [--reason <text>] [--extra '<json-objekt>']
  run-log.sh fail   <YYYY-MM-DD> --reason <text>
  run-log.sh check  [<YYYY-MM-DD>]     # Selbstpruefung / Luecken-Scan
EOF
  exit 1
}

[ $# -ge 1 ] || usage
CMD="$1"; shift || true

[ -f "$LOG" ] || die "Run-Log fehlt: $LOG (NICHT anlegen — falscher Pfad ist wahrscheinlicher als eine fehlende Datei)"
[ -w "$LOG" ] || die "Run-Log nicht schreibbar: $LOG"
command -v jq >/dev/null 2>&1 || die "jq fehlt"

valid_date() { printf '%s' "$1" | /usr/bin/grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; }

# Ersetzt/fuegt die Zeile fuer $1 ein, Inhalt aus stdin. Datumssortierung bleibt
# erhalten, genau EINE Zeile pro Datum. Atomar via temp + mv im selben Verzeichnis.
splice() {
  local d="$1" tmp new_line
  new_line="$(cat)"
  printf '%s' "$new_line" | jq -e . >/dev/null 2>&1 || die "erzeugte Zeile ist kein gueltiges JSON"
  tmp="$(mktemp "${LOG}.tmp.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN

  jq -r .date "$LOG" > "${tmp}.dates" || die "Datumsspalte nicht lesbar — Run-Log beschaedigt?"
  printf '%s\n' "$new_line" > "${tmp}.line"

  awk -v newfile="${tmp}.line" -v target="$d" '
    FNR==NR { dd[FNR]=$0; next }
    {
      if (dd[FNR] == target) { next }                       # alte Zeile desselben Tages faellt weg
      if (!ins && (dd[FNR] > target)) {
        while ((getline l < newfile) > 0) print l; close(newfile); ins=1
      }
      print
    }
    END { if (!ins) { while ((getline l < newfile) > 0) print l; close(newfile) } }
  ' "${tmp}.dates" "$LOG" > "$tmp" || die "Splice fehlgeschlagen"

  # Pflichtpruefungen VOR dem Ersetzen — nie ein unverifiziertes Log installieren.
  jq -e . "$tmp" >/dev/null || die "Ergebnis enthaelt ungueltige JSON-Zeile"
  jq -r .date "$tmp" | sort -c || die "Datumsreihe nicht mehr aufsteigend"
  [ "$(jq -r --arg d "$d" 'select(.date==$d) | .date' "$tmp" | wc -l | tr -d ' ')" -eq 1 ] \
    || die "nicht genau eine Zeile fuer $d"

  rm -f "${tmp}.dates" "${tmp}.line"
  mv "$tmp" "$LOG" || die "Installation fehlgeschlagen"
  trap - RETURN
}

existing_status() { jq -r --arg d "$1" 'select(.date==$d) | .status' "$LOG" | head -1; }

case "$CMD" in
  start)
    D="${1:-}"; valid_date "${D:-}" || die "Tag fehlt/ungueltig (YYYY-MM-DD)"
    prev="$(existing_status "$D")"
    if [ -n "$prev" ]; then
      # Idempotent: ein wiederaufgenommener Lauf darf nicht duplizieren, und ein
      # bereits abgeschlossener Tag darf nicht auf "partial" zurueckfallen.
      echo "HINWEIS: Zeile fuer $D existiert bereits (status=$prev) — start uebersprungen." >&2
      exit 0
    fi
    jq -cn --arg d "$D" --argjson ts "$(date +%s)" '{
      date: $d, ts: $ts, status: "partial",
      phase: "begonnen",
      reason: "Lauf begonnen, Paragraph A/B/C noch nicht abgeschlossen. Bleibt diese Zeile partial, ist der Lauf abgebrochen — kein Falsch-Negativ mehr, sondern ein sichtbarer Teil-Lauf."
    }' | splice "$D"
    echo "run-log: $D als partial angelegt (Lauf ist ab jetzt belegt)." >&2
    ;;

  finish)
    D="${1:-}"; shift || true
    valid_date "${D:-}" || die "Tag fehlt/ungueltig (YYYY-MM-DD)"
    COUNT_JSON=""; LOGBOOK=""; NOTION_ID=""; NOTION_MODUS=""; ST="ok"; REASON=""; EXTRA="{}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --count-json) COUNT_JSON="${2:?--count-json braucht einen Pfad}"; shift 2;;
        --logbook) LOGBOOK="${2:?--logbook braucht einen Pfad}"; shift 2;;
        --notion-page-id) NOTION_ID="${2:-}"; shift 2;;
        --notion-modus) NOTION_MODUS="${2:-}"; shift 2;;
        --status) ST="${2:?--status braucht ok|partial}"; shift 2;;
        --reason) REASON="${2:-}"; shift 2;;
        --extra) EXTRA="${2:?--extra braucht ein JSON-Objekt}"; shift 2;;
        *) die "unbekannte Option: $1";;
      esac
    done
    [ -n "$COUNT_JSON" ] || die "--count-json fehlt (Zahlen kommen NUR aus logbook-count.sh)"
    [ -r "$COUNT_JSON" ] || die "count-json nicht lesbar: $COUNT_JSON"
    [ -n "$LOGBOOK" ] || die "--logbook fehlt"
    [ -f "$LOGBOOK" ] || die "Logbuch-Datei existiert nicht: $LOGBOOK (status ok ohne Artefakt ist unzulaessig)"
    case "$ST" in ok|partial) :;; *) die "--status muss ok oder partial sein (fail => Unterbefehl 'fail')";; esac
    [ "$ST" = "ok" ] || [ -n "$REASON" ] || die "status=partial verlangt --reason (SKILL.md Paragraph C)"
    printf '%s' "$EXTRA" | jq -e 'type=="object"' >/dev/null 2>&1 || die "--extra ist kein JSON-Objekt"
    jq -e 'has("items_total") and has("count_basis") and has("evidence_tier") and has("quellen_epochen") and has("sources")' \
      "$COUNT_JSON" >/dev/null 2>&1 || die "count-json erfuellt den Skriptvertrag nicht (items_total/count_basis/evidence_tier/quellen_epochen/sources)"
    JD="$(jq -r .day "$COUNT_JSON")"
    [ "$JD" = "$D" ] || die "count-json gehoert zu $JD, nicht zu $D"

    prev="$(existing_status "$D")"
    [ -n "$prev" ] || echo "WARNUNG: kein 'start' fuer $D vorhanden — Zeile wird trotzdem geschrieben, aber der Lauf war zwischenzeitlich unbelegt." >&2

    jq -c \
      --arg d "$D" --argjson ts "$(date +%s)" --arg st "$ST" \
      --arg lb "$LOGBOOK" --arg nid "$NOTION_ID" --arg nmod "$NOTION_MODUS" \
      --arg reason "$REASON" --argjson extra "$EXTRA" \
      --arg startfehlt "$([ -n "$prev" ] && echo false || echo true)" '
      {
        date: $d, ts: $ts, status: $st,
        logbook_path: $lb,
        items_total, count_basis, evidence_tier, evidence_tier_grund,
        quellen_epochen, sources,
        vcs_operationen: (.vcs_operationen | if type=="array" then length else . end),
        git_ambiguous_nicht_gezaehlt, items_sha256
      }
      + (if $nid  != "" then {notion_page_id: $nid} else {} end)
      + (if $nmod != "" then {notion_modus: $nmod} else {} end)
      + (if $reason != "" then {reason: $reason} else {} end)
      + (if $startfehlt == "true" then {start_zeile_fehlte: true} else {} end)
      + $extra
    ' "$COUNT_JSON" | splice "$D"
    echo "run-log: $D auf status=$ST angehoben." >&2
    ;;

  fail)
    D="${1:-}"; shift || true
    valid_date "${D:-}" || die "Tag fehlt/ungueltig (YYYY-MM-DD)"
    REASON=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --reason) REASON="${2:?--reason braucht Text}"; shift 2;;
        *) die "unbekannte Option: $1";;
      esac
    done
    [ -n "$REASON" ] || die "--reason ist PFLICHT bei fail (SKILL.md Fail-Loud-Kontrakt)"
    # KEINE Zahlenfelder — Fail-Loud-Kontrakt: bei Exit != 0 kein items_total, auch nicht null.
    jq -cn --arg d "$D" --argjson ts "$(date +%s)" --arg r "$REASON" \
      '{date:$d, ts:$ts, status:"fail", reason:$r}' | splice "$D"
    echo "run-log: $D als fail vermerkt." >&2
    ;;

  check)
    D="${1:-}"
    if [ -n "$D" ]; then
      valid_date "$D" || die "ungueltiges Datum"
      line="$(jq -c --arg d "$D" 'select(.date==$d)' "$LOG")"
      [ -n "$line" ] || { echo "FEHLT: keine Zeile fuer $D"; exit 2; }
      printf '%s\n' "$line" | jq -r '"\(.date) status=\(.status) items_total=\(.items_total // "-")"'
      exit 0
    fi
    jq -e . "$LOG" >/dev/null || die "Run-Log enthaelt ungueltiges JSON"
    jq -r .date "$LOG" | sort -c || die "Run-Log nicht datumssortiert"
    dup="$(jq -r .date "$LOG" | uniq -d)"
    [ -z "$dup" ] || die "doppelte Datumszeilen: $dup"
    echo "Run-Log strukturell in Ordnung ($(wc -l < "$LOG" | tr -d ' ') Zeilen)."
    echo "Offene Teil-Laeufe (status != ok):"
    jq -r 'select(.status != "ok") | "  \(.date) status=\(.status) reason=\((.reason // "-")[0:80])"' "$LOG"
    ;;

  *) usage;;
esac
