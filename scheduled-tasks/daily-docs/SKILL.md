---
name: daily-docs
description: Daily logbook entry — Item-Zählung läuft ausschliesslich über ein Referenzskript (nie manuell/aus dem Gefühl), aggregiert Signals/Git/Memory für die Prosa, schreibt Markdown + synced zu Notion.
---

<!-- Erwartetes cwd: ~/.claude · Zeitgeber: launchd com.your-username.claude-routine-daily-docs (seit 2026-08-22, IMP-135; davor unversionierte Cloud-Bindung an ein 2026-08-02 umbenanntes Verzeichnis — 20 Tage stiller Ausfall). -->

Run the documentation-agent in Mode B (Daily-Docs Routine).

## Date window
Process activity from yesterday (00:00 to 23:59 local).
`yesterday=$(date -v-1d +%Y-%m-%d)`

## Lauf-Reihenfolge — DER BELEG KOMMT ZUERST

**Allererste dauerhafte Aktion jedes Laufs — vor der Zählung, vor dem Logbuch,
vor Notion:**

```bash
bash ~/.claude/scheduled-tasks/daily-docs/bin/run-log.sh start "$yesterday"
```

Verbindliche Reihenfolge: **C-start → Zählung → A → B → C-finish**.
Nicht mehr A → B → C. Der Beleg wird ANGELEGT bevor es Artefakte gibt und am
Ende nur noch ANGEHOBEN (`finish`), nie erstmalig geschrieben.

### Warum umgedreht (gemessen 2026-07-31, Lauf für den 2026-07-30)

Der Lauf feuerte pünktlich um 07:10, schrieb §A (`logbook/2026-07-30.md`),
aktualisierte §B (Notion-Sub-Page `<notion-subpage-id>`) — und
starb 11 Sekunden nach Beginn von §C an `[Request interrupted by user]`
(letzte Aktion: `grep -rn 'daily-docs-log'`, Transkript
`<session-id>`). Ergebnis: beide Artefakte vorhanden,
Datumsreihe sprang 2026-07-29 → 2026-07-31, jede Abdeckungsprüfung meldete
**FALSCH-NEGATIV „nie gelaufen"**. Backfill der Zeile: 2026-08-01.

Das ist die Umkehrung des IMP-075-Falls und strukturell garantiert, solange §C
zuletzt steht: **§A und §B hinterlassen je ein Artefakt, §C IST das Artefakt.**
Jeder Abbruch dazwischen — Interrupt, Absturz, Kontextende, Token-Budget,
Scheduler-Timeout — erzeugt Artefakte ohne Beweis. Mit `start` zuerst bleibt im
selben Fall eine `status:"partial"`-Zeile stehen: ein sichtbarer Teil-Lauf statt
einer unsichtbaren Lücke.

Nebenbefund desselben Laufs: seine letzte Handlung war die Recherche, ob
Konsumenten `items` oder `items_total` lesen — eine Frage, die nur entstand, weil
das §C-Template unten jahrelang `"items": N` zeigte, während der Rest dieser Spec
`items_total` vorschreibt. Die Drift ist mit dem Backfill behoben; Zahlenfelder
werden ohnehin nicht mehr von Hand getippt (siehe `finish` unten).

> Warum ein Skript und keine Prosa-Anweisung: dieselbe Lehre wie bei der Zählung
> (2026-07-18 — `logbook-count.sh` ersetzte die Agenten-Schätzung). Ein Agent,
> der abbricht, führt keine Prosa-Anweisung mehr aus. Ein Aufruf, der als erstes
> passiert, ist dagegen schon passiert.

## Tageszählung — VERBINDLICHES VERFAHREN

Du zählst NICHT selbst. Du führst das Referenzskript aus und übernimmst dessen JSON
unverändert. Eine selbst geschätzte oder aus `git log` nachgerechnete Zahl ist ein
Verfahrensfehler.

**Skript:** `~/.claude/scheduled-tasks/daily-docs/bin/logbook-count.sh <YYYY-MM-DD>`
(separat gepflegt — diese Spec referenziert nur den Aufruf und die Vertragsbedingungen,
nicht die interne Logik).

### Zählbasis — ein Satz
Ein Item ist eine eindeutige Datei nach Repo-Identität (`<repo_id>::<relpfad>`, sonst
`fs::<pfad>` ausserhalb jedes Repos), deren Inhalt am Zieltag durch einen belegten
Schreibvorgang verändert wurde. Merge-materialisierte Dateien zählen NICHT als Items
— sie erscheinen unter `vcs_operationen` (siehe Outputs A), nie addiert zu `items_total`.

### Ablauf
1. `bash ~/.claude/scheduled-tasks/daily-docs/bin/logbook-count.sh "$yesterday"`
2. **Exit ≠ 0 → kein Logbucheintrag mit Zahl.** Siehe Fail-Loud-Kontrakt unten.
3. **Exit = 0 →** übernimm aus dem JSON unverändert die folgenden Felder. Die Namen sind
   am 2026-07-18 gegen die echte Skriptausgabe geprüft — benutze GENAU diese, rate nicht:

   | Feld im JSON | Bedeutung |
   |---|---|
   | `items_total` | die Tageszahl (NICHT `items` — dieses Feld existiert nicht) |
   | `count_basis` | immer `files_touched_v3` |
   | `evidence_tier` + `evidence_tier_grund` | Beweisstufe und ihre Begründung |
   | `quellen_epochen` | ab wann jede Quelle existiert (ersetzt das frühere `aera`) |
   | `sources` | Gelesenheits-Zertifikat je Quelle (Objekt, kein Array) |
   | `vcs_operationen` + `vcs_zaehler` | Merges etc., eigener Absatz |
   | `nicht_erfassbar` | Pflichtabschnitt des Eintrags |
   | `status` | `OK` oder `DEGRADED` |

   Alle diese Felder sind PFLICHT in jedem Eintrag — auch an einem `items_total:0`-Tag.
   **Findest du ein Feld nicht: NICHT improvisieren, nicht auf ein ähnliches ausweichen.**
   Dann hat sich der Skriptvertrag geändert → `status:"fail"`, `reason` = fehlendes Feld.

### Was du NIE tun darfst
- `items_total` und `vcs_operationen` addieren — zwei eigenständige Grössen, keine Summanden.
- **In der Prosa selbst gerechnete Zahlen nennen.** Kein „85 Commits", kein „39 Items auf der
  Transkript-Achse", keine Teilsummen. Die EINZIGE gültige Zahl im Eintrag ist `items_total`
  aus dem Skript. Belege werden AUFGEZÄHLT (SHAs, Pfade), nicht summiert.
  *Gemessen beim Backfill 2026-07-18: Zahlen aus belegten Einzelteilen fühlen sich belegt an,
  reproduzieren aber nicht — real aufgetreten „85 Commits" (tatsächlich 83) und „54 Commits"
  (tatsächlich 53). Eine Summe ist nur belegt, wenn auch die Rechnung reproduzierbar ist.*
- **Aus Dateinamen auf Technologie schliessen.** „BootScene.ts, MenuScene.ts" belegt kein
  Framework. Entweder den Beleg finden und zitieren (`package.json`-Eintrag) oder die
  Behauptung weglassen.
- **Ein Verzeichnis als „Repo" bezeichnen, ohne `.git` geprüft zu haben.**
- Bei Exit ≠ 0 irgendeine Zahl schreiben (auch keine „ungefähre" oder eine selbst aus
  `git log` gezählte).
- Den Abschnitt „Für diesen Tag nicht erfassbar" weglassen — er ist Pflicht in jedem
  Eintrag, auch einem vollständigen.
- `evidence_tier`/`quellen_epochen` selbst herleiten — beide kommen nur aus dem Skript.

### Fail-Loud-Kontrakt
Bricht das Skript mit einem ABORT-Code ab: Run-Log-Zeile `"status":"fail"`,
`"reason"` = die ABORT-Meldung wörtlich. KEINE Zahl erfinden, KEINE alternative
Zählung improvisieren, kein `mkdir`/Workaround. Exit ≠ 0 bedeutet: kein `items_total`-Feld
im Eintrag — weder im Logbuch noch im Run-Log.
Mechanik: `bash bin/run-log.sh fail "$yesterday" --reason "<ABORT-Meldung wörtlich>"` —
das Skript lässt die Zahlenfelder weg, statt sie auf `null` zu setzen.

### ABORT-Codes (Skript-Exit ≠ 0 — jeder ist ein Verfahrensstopp, kein Warnhinweis)
| Exit | Bedeutung |
|---|---|
| 1 | Tagesargument fehlt |
| 2 | Fenstergrenzen leer/ungültig/nicht aufsteigend |
| 3 | Suchwurzel fehlt oder Sentinel unlesbar (Volume nicht gemountet) |
| 4 | 0 Transkripte gefunden — Messfehler, kein Leertag |
| 5 | signals fehlt oder abgeschnitten |
| 7 | `items_total=0`, obwohl andere Quellen liefern |
| 9 | Ausgabe nicht geschrieben oder leer trotz Eingabe |
| 10 | Arbeitsverzeichnis nicht frisch |
| 11 | Canary/Zweitzähler weicht ab |
| 12 | Fehlschlag-Filter kollabiert bei 0 Mustern |
| 13 | Q_T=0 trotz unabhängiger Zeugen |
| 14 | `items_total` < 50% der Referenzachse |
| 15/16 | Transkript-/Desktop-Scan unvollständig |
| 17 | signals `empty_verified`, aber Ereigniszeilen im Fenster |
| 18 | Zertifikatspflicht verletzt (kein `state=`) |
| 19 | Symlink im Scanbaum oder Root über Symlink |
| 20 | gepinntes Werkzeug (`/usr/bin/find`/`/usr/bin/grep`) fehlt |
| 21 | S12/Q_V nicht auswertbar |

`evidence_tier` (1–4) plus `evidence_tier_grund` liefert das Skript ebenfalls, dazu
`quellen_epochen` — die Startdaten der Quellen (`signals:2026-06-19`,
`transkripte:2026-03-18`, `desktop:2026-02-04`). Für Tagesläufe (immer „gestern")
existieren alle Quellen, die Epochen sind dann nur Kontext. Gemessen am 2026-07-18:
ein Tageslauf liefert `evidence_tier:2` / `status:DEGRADED`, weil der Handarbeits-Zweig
(`manifest`) rückwirkend nie existiert — das ist der NORMALZUSTAND, kein Fehler und
kein Grund, den Eintrag zurückzuhalten. Stufe 1 ist derzeit für keinen Tag erreichbar.

## Ergänzende Quellen für Prosa (NICHT für die Zählung)

Diese liefern INHALT für Features/Bugs/Decisions — nicht die Item-Zahl (die kommt
ausschliesslich aus dem Skript oben). Jede Prosa-Aussage muss auf eine SHA oder einen
Item-Pfad aus dem Skript-JSON rückführbar sein — keine Vermutungen.

**Quellen-Hinweis (Nutzer-Direktive 2026-08-23, siehe `skills/meta-observer/SKILL.md`
§ Quellen-Doktrin):** die ERZÄHLUNG des Tages — Entscheidungen, Blocker, Kurswechsel —
stammt aus den Session-Transkripten des Tages; `git log` liefert nur die Faktenliste der
Commits, nicht den Weg dorthin. Diese Gewichtung gilt für die Prosa unter „Activity" und
„Research / Decisions" unten; an der Zählmechanik (Skript, `items_total`) ändert sie
nichts.

1. **Commit-Messages** (Kontext, keine Zählquelle):
   ```bash
   yesterday=$(date -v-1d +%Y-%m-%d)
   ROOTS=("/Volumes/YourExternalVolume/ProjectHub" "/Volumes/YourExternalVolume/1-PROJECTS" "$HOME/ProjectHub" "$HOME/.claude")
   for r in "${ROOTS[@]}"; do
     [ -d "$r" ] || { echo "WARN: root missing (drive unmounted?): $r" >&2; continue; }
     find "$r" -maxdepth 5 -type d -name .git -not -path '*/node_modules/*' 2>/dev/null
   done | while read -r gitdir; do
     repo=$(dirname "$gitdir"); email=$(git -C "$repo" config user.email)
     git -C "$repo" log --all --author="$email" \
         --pretty=tformat:'%H%x09%ad%x09%cd%x09%s' --date=format:'%Y-%m-%d' \
       | awk -F'\t' -v d="$yesterday" '$2==d || $3==d { printf "%s\t%s\n", substr($1,1,9), $4 }'
   done | awk -F'\t' '!seen[$1]++'   # SHA-Dedupe, siehe Fußnote
   ```
   *Fußnote — vier reale Fehlschläge, deshalb so geschrieben:* Roots statt Ableitung
   aus `~/.claude/projects/`-Verzeichnisnamen (das Encoding kollabiert „/" und „_"
   verlustbehaftet zu „-"); `--all` statt current-branch (verpasste sonst Commits auf
   `claude/*`-Worktree-Branches); author-date ODER committer-date (ein reiner
   `--since/--until`-Filter auf Committer-Date verpasst Commits nach einem nächtlichen
   Rebase); SHA-Dedupe (zwei Klone desselben Remotes — z.B.
   `ProjectHub/config-repo` und `$HOME/.claude` — emittieren jeden Commit
   doppelt; am 2026-07-17 real beobachtet: 2 Commits erschienen als 4 Zeilen).
2. **Signals:** `~/.claude/global-observation/signals.jsonl` (aktuell) +
   `~/.claude/global-observation/archives/signals-<yesterday>.jsonl.gz` (rotiert) —
   Einträge mit `date == $yesterday`. *Der alte Pfad `~/.claude/signals.jsonl` war der
   dritte Ur-Defekt: die Datei existiert dort nicht, lieferte still 0 Treffer und wurde
   fälschlich als „rotated away" erklärt.*
3. **Memory-Updates:** Positivprobe nach INHALT, nie mtime (IMP-195 — Datei-mtime unter
   `~/.claude/projects/` ist nachweislich kein Aktivitätssignal; ein nicht identifizierter
   Prozess fasst Dateien in diesem Baum an, ohne den Inhalt zu ändern — 99 von 603
   Transkriptdateien trugen im Lauf vom 2026-09-09 exakt `10:30` als mtime bei
   wochenaltem Inhalt. Gleiches Muster wie `logbook-count.sh` § S1a, "nie mtime").
   Prüfe je Datei in `~/.claude/projects/-Users-your-username/memory/*.md` das
   Frontmatter-Feld `modified:` gegen `$yesterday`:
   ```bash
   grep -l "modified: ${yesterday}" ~/.claude/projects/-Users-your-username/memory/*.md 2>/dev/null
   ```
   Nicht jede Memory-Datei trägt `modified:` im Frontmatter (ältere Dateien fehlt das
   Feld ganz). Eine Datei ohne dieses Feld ist eine PROSA-QUELLE OHNE DATUMSBELEG — sie
   darf zitiert, aber nicht als "gestern geändert" behauptet werden; mtime ersetzt den
   fehlenden Beleg nicht.
4. **Session-Metriken:** `~/.claude/session-env/*` von gestern

## Kategorisierung
Nur aus belegten Fakten (Commit-Message, Item-Pfad, Transcript-Titel) — kein
Ausschmücken:
- Features Shipped
- Bugs Fixed
- Refactors / Cleanup
- Research / Decisions (mit Begründung)
- Blockers Encountered
- Plans for Today

## Outputs

### A) Local Markdown logbook
Path: `/Users/your-username/.claude/logbook/YYYY-MM-DD.md` (YYYY-MM-DD = gestern)

**Hardcoded mit Absicht (2026-07-18) — hier keine Variable wieder einführen.** Der
alte Pfad las `${LOGBOOK_DIR}`, nie in `settings.json`/`settings.local.json` gesetzt.
Unset expandierte er zu leer → der Pfad wurde `/YYYY-MM-DD.md` (Filesystem-Root). Läufe
reparierten sich still, indem sie das Verzeichnis aus einer früheren Zeile in
`daily-docs-log.jsonl` erschlossen — ein stiller Fallback (`rules/fail-loud.md`
verboten), der wochenlang den unset-Bug maskierte. `settings.local.json` wäre KEINE
dauerhafte Lösung (gitignored, `*.local.json`) — der Pfad ist maschinenstabil und
nicht geheim, er gehört in die Spec selbst.

**Pre-flight-Guard — fail loud, kein Workaround:**
```bash
LOGBOOK_DIR_RESOLVED="/Users/your-username/.claude/logbook"
[ -n "$LOGBOOK_DIR_RESOLVED" ] && [ -d "$LOGBOOK_DIR_RESOLVED" ] || {
  echo "FAIL: logbook dir empty or missing: '${LOGBOOK_DIR_RESOLVED:-<empty>}'" >&2
  exit 1
}
```
Trippt der Guard: §C-Zeile `"status":"fail"` + `"reason"` mit dem unresolved Pfad,
dann Stopp. NIE: Verzeichnis anlegen, Pfad aus früheren Log-Zeilen erschliessen, auf
`/` schreiben.

Format:
```markdown
# YYYY-MM-DD — Daily Logbook

## Zähl-Status
- items_total: N — count_basis: files_touched_v3 — evidence_tier: T (Grund: …) — status: OK|DEGRADED
- quellen_epochen: [wörtlich aus dem Skript-JSON]
- sources: [Zertifikate wörtlich aus dem Skript-JSON]

## VCS-Operationen
[eigener Absatz, NIE in `items_total` eingerechnet — z.B. "3 Merges, 40 Dateien
materialisiert, davon 13 ausschliesslich merge-hergeleitet und nicht in items_total
enthalten"; bei 0 Operationen: "keine"]

## Summary
[2-3 Sätze]

## Activity
### Features Shipped
### Bugs Fixed
### Refactors / Cleanup
### Research / Decisions
### Blockers

## Für diesen Tag nicht erfassbar
- [wörtlich aus `nicht_erfassbar[]`; nie leer lassen — auch ein vollständiger Tag
  hat diese Sektion]

## Plans for Today
```

### B) Notion sync
- Parent page: `<your-notion-page-id>` — die "📔 Claude Code
  Logbuch"-Page.

**Hardcoded mit Absicht (2026-08-04) — hier keine Variable wieder einführen.**
Dieselbe Lehre wie beim Logbuch-Pfad in §A, nur eine Runde später gezogen: Der Wert
stand als `${NOTION_PARENT_PAGE_ID}` in `~/.claude/settings.local.json` — einer Datei,
die Claude Code auf Nutzerebene **nicht liest** (die lokale Einstellungsebene existiert
nur pro Projekt). Die Variable war also nie gesetzt, der Notion-Schritt fiel jeden Tag
still aus, und der Lauf meldete `status:partial`. Das Ledger verbuchte den Punkt am
2026-07-03 als „RESOLUTION: set in settings.local.json" — gelöst war er nicht, nur
unsichtbar geworden. Der Wert ist maschinenstabil und **kein Zugangsmittel** (der
Zugriff kommt aus der Notion-Anmeldung, nicht aus der Seiten-Kennung), er gehört
deshalb in die Spec selbst.

**Pre-flight-Guard — fail loud, kein Workaround:**
```bash
NOTION_PARENT_RESOLVED="<your-notion-page-id>"
[ -n "$NOTION_PARENT_RESOLVED" ] || {
  echo "FAIL: Notion parent page id empty" >&2
  exit 1
}
```
Trippt der Guard oder schlägt der Notion-Aufruf fehl: §C-Zeile `"status":"partial"`
**mit** `"reason"`. NIE: den Schritt still überspringen — genau das hat den Ausfall
wochenlang verdeckt (`rules/fail-loud.md`).
- **IDEMPOTENT (2026-07-03):** erst `notion-fetch` auf den Parent, prüfen ob eine
  Sub-Page namens `YYYY-MM-DD` bereits existiert (eine Alt-Routine, Trigger
  `<routine-trigger-id>`, legt evtl. noch welche um 07:00 an, bis der User
  sie unter claude.ai/code/routines löscht). Existiert sie: UPDATE
  (`notion-update-page`) — nie einen doppelten Sibling anlegen. Nur bei Abwesenheit
  neu erstellen.
- Inhalt = dasselbe Markdown aus §A.
- Tools: `notion-create-pages` / `notion-update-page`.

### C) Run log — zweiphasig, EINE Zeile pro Datum

Ziel: `~/.claude/global-observation/daily-docs-log.jsonl`.
**Die Zeile wird NIE von Hand geschrieben oder per `echo >>` angehängt.**
Ausschliesslich über `bin/run-log.sh` — es baut die Zahlen- und Zertifikatsfelder
per `jq` direkt aus dem `count.json` von `logbook-count.sh` und schneidet damit die
historische Fehlerquelle „abgetippte Zahl" ab (real: „85 Commits" statt 83).

**Phase 1 — `start`, bereits ganz oben im Lauf erledigt** (siehe „Lauf-Reihenfolge"):
schreibt `{"date":…,"ts":…,"status":"partial","phase":"begonnen","reason":…}`.

**Phase 2 — nach §A und §B:**
```bash
bash ~/.claude/scheduled-tasks/daily-docs/bin/run-log.sh finish "$yesterday" \
  --count-json "$J" \
  --logbook "/Users/your-username/.claude/logbook/$yesterday.md" \
  --notion-page-id "<id>" --notion-modus "<neue_subpage|update_bestehende_subpage>"
```
Bei Skript-ABORT statt `finish`:
```bash
bash ~/.claude/scheduled-tasks/daily-docs/bin/run-log.sh fail "$yesterday" --reason "<ABORT-Meldung wörtlich>"
```
Notion fehlgeschlagen, Logbuch aber geschrieben: `finish … --status partial --reason "<Grund>"`.

Resultierende Zeile (Feldnamen VERBINDLICH — `items` gibt es nicht, `aera` ist durch
`quellen_epochen` ersetzt; beide standen bis 2026-08-01 fälschlich in diesem Template):
```json
{"date":"YYYY-MM-DD","ts":<unix>,"status":"ok|partial|fail","logbook_path":"…","notion_page_id":"…","items_total":N,"count_basis":"files_touched_v3","evidence_tier":T,"evidence_tier_grund":"…","quellen_epochen":{…},"sources":{…},"vcs_operationen":N,"git_ambiguous_nicht_gezaehlt":N,"items_sha256":"…","notion_modus":"…","reason":"…"}
```

Das Skript erzwingt (Exit ≠ 0, keine stille Reparatur):
- `reason` PFLICHT bei `partial`/`fail`, entfällt bei `ok`.
- `fail`-Zeilen enthalten **keine** Zahlenfelder — nicht als `null`, sondern gar nicht
  (Fail-Loud-Kontrakt).
- `finish` verlangt eine existierende Logbuch-Datei — `status:"ok"` ohne Artefakt ist
  unzulässig; und ein `count.json`, dessen `day` zum Datum passt.
- Datumssortierung und Eindeutigkeit bleiben erhalten (Lückenerkennung hängt daran);
  Installation atomar via temp + `mv`, vorher vollständig verifiziert.
- Fehlt die `start`-Zeile, wird `finish` trotzdem geschrieben, aber mit
  `"start_zeile_fehlte": true` markiert — der Prozessverstoss bleibt sichtbar.

**Selbstprüfung** (Struktur, Duplikate, offene Teil-Läufe):
```bash
bash ~/.claude/scheduled-tasks/daily-docs/bin/run-log.sh check
```
Eine `status:"partial"`-Zeile, die stehen bleibt, ist genau der Abbruchfall — sie
gehört nachgearbeitet, nicht weggeräumt.

## Failure modes
- **Lauf bricht mitten drin ab** (Interrupt, Absturz, Kontextende, Token-Budget,
  Scheduler-Timeout): Es bleibt die `status:"partial"`-Zeile aus `run-log.sh start`
  stehen. Das ist der GEWOLLTE Endzustand — ein sichtbarer Teil-Lauf. Nicht
  aufräumen, nicht auf `ok` heben, ohne dass §A und §B tatsächlich existieren.
  Nacharbeit: fehlende Schritte nachziehen, dann `finish`. `run-log.sh check`
  listet alle offenen Teil-Läufe.
- **Skript-ABORT:** siehe Fail-Loud-Kontrakt oben — `status:"fail"`, `reason` =
  ABORT-Meldung wörtlich, kein `items_total`-Feld, keine improvisierte Zahl.
- **Logbook-Dir leer/fehlt:** `status:"fail"` mit explizitem `reason` (Pre-flight
  Guard §A). Nie aus alten Log-Zeilen erschliessen, nie `mkdir`, nie auf `/` schreiben.
- **Root für Prosa-Git-Log fehlt** (externes Volume nicht gemountet): `WARN` loggen,
  mit den vorhandenen Roots weiterarbeiten, den fehlenden Root explizit unter „Für
  diesen Tag nicht erfassbar" nennen. Das ändert NICHT den `status` — der hängt am
  Skript-Exit, nicht an der Prosa-Vollständigkeit.
- **Ruhiger Tag** (Skript liefert `items_total` korrekt, auch niedrig oder 0): trotzdem
  vollständigen Eintrag schreiben und syncen. Nie überspringen.
- **Notion-Auth-Fehler:** Markdown lokal schreiben, `status:"partial"` loggen,
  zurückkehren.
- **Notion-Konflikt** (Seite existiert, Version weicht ab): aktuellen Stand holen,
  mergen, pushen. Bei unklarem Merge: lokal schreiben + für manuelle Prüfung markieren.
