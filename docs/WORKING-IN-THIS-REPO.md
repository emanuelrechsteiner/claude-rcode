<!--
Status: ACTIVE
Last Updated: 2026-08-22
Purpose: Baustellenordnung für Agenten und Menschen, die an diesem Repo arbeiten — Zwei-Orte-Modell, was selbst prüfbar ist, Abnahmeprotokoll
-->

# Baustellenordnung — Arbeiten an diesem Repo

Dieses Dokument gilt für **jeden**, der an `claude-code-config` arbeitet:
Menschen wie Agenten. Es beantwortet drei Fragen: Wo ändere ich? Was kann ich
selbst prüfen? Was muss der Nutzer prüfen?

## 1. Wo bin ich? (immer zuerst)

```bash
pwd
```

| Pfad | Ort | Regel |
|---|---|---|
| `…/claude-code-config` | **Bauhof** | Hier ändern, testen, committen. |
| `~/.claude` | **Haus** | Nicht von Hand ändern. Empfängt nur `claude-deploy`. |

Dasselbe Muster gilt für das Cockpit: Bauhof `…/cockpit` (Geschwisterordner),
Haus `~/.claude/cockpit`.

**Doppelladung im Bauhof (behoben 2026-09-24, IMP-217):** Eine Sitzung im Bauhof
lädt `CLAUDE.md` zweimal — einmal als Nutzeranweisung aus dem Haus
(`~/.claude/CLAUDE.md`), einmal als Projektanweisung aus dem Bauhof — Claude Code
vergleicht Inhalte nicht, nur Pfade. Der dokumentierte Schalter `claudeMdExcludes`
(`code.claude.com/docs/en/memory`, Pfadmuster gegen absolute Pfade) schließt die
**Bauhof-Kopie** aus, damit die Sitzung weiterhin den eingezogenen Stand liest:

```json
// .claude/settings.local.json im Bauhof (maschinenlokal, git-ignoriert)
{ "claudeMdExcludes": ["<BAUHOF>/CLAUDE.md"] }
```

Sichtbar beim nächsten Sitzungsstart: die Zeile „N instruction files add up to …"
zählt eine `CLAUDE.md` weniger. Die Gesamtgrenze von 150.000 Zeichen dahinter ist
übrigens **nur eine Warnung** — nichts wird gekappt (offiziell undokumentiert; Beleg:
Claude-Code-Issue #96506).

**Was passiert, wenn du es doch im Haus änderst:** Deine Änderung ist sofort
scharf (der nächste Werkzeugaufruf derselben Sitzung nutzt schon den neuen
Hook), und bei der nächsten Übergabe bricht `claude-deploy` ab, weil das Haus
uneingecheckte Änderungen an verfolgten Dateien hat. Du hast dann eine
Aufräumarbeit erzeugt, keine Verbesserung.

## 2. Die Selbstreferenz — warum du deine eigene Arbeit nicht abnehmen kannst

Claude Code liest Regeln, Hooks, Skills, Agents und `settings.json` **beim
Sitzungsstart** in den Speicher. Deine laufende Sitzung arbeitet also mit dem
Stand von vorhin — nicht mit dem, was du gerade geschrieben hast.

Daraus folgt hart:

- **Eine geänderte Regel wirkt NICHT in deiner Sitzung.** Du kannst nicht
  beobachten, ob sie greift.
- **Ein geänderter Hook, der im Haus liegt, wirkt dagegen SOFORT** — beim
  nächsten Werkzeugaufruf. Das ist kein Vorteil, sondern die Gefahr: Ein Fehler
  darin kann die laufende Sitzung lahmlegen (ein PreToolUse-Hook mit Exit-Code 2
  blockiert Werkzeugaufrufe). Genau deshalb wird im Bauhof gearbeitet.
- **Ein neuer Skill/Command taucht erst in einer neuen Sitzung im Menü auf.**

> **Formuliere Ergebnisse entsprechend.** Nicht: „Der Hook funktioniert jetzt."
> Sondern: „Der Hook besteht die direkten Aufrufe (siehe unten); ob er im
> Zusammenspiel greift, zeigt sich nach `claude-deploy` in einer neuen Sitzung —
> Prüfschritte siehe Abnahmeprotokoll."

## 3. Was du SELBST prüfen kannst und musst

Diese Prüfungen laufen ohne Übergabe, direkt im Bauhof. Führe sie aus, bevor du
fertig meldest — „ungeprüft" ist ein zulässiges Ergebnis, „vermutlich in Ordnung"
nicht.

### Hook-Skripte direkt aufrufen

Ein Hook ist ein gewöhnliches Shell-Skript, das JSON auf `stdin` bekommt und
über Exit-Code und Ausgabe antwortet. Das lässt sich vollständig ohne Claude
Code prüfen:

```bash
# Ein Gate mit einem harmlosen UND einem gefährlichen Befehl prüfen
# (verifiziert 2026-08-04: liefert 0 bzw. 2)
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  | CLAUDE_GATE_TESTMODE=1 bash hooks/excessive-agency-gate.sh; echo "harmlos → $?"
echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1"}}' \
  | bash hooks/excessive-agency-gate.sh; echo "gefährlich → $?"
```

Exit-Code 0 = durchgelassen, 2 = blockiert (Rückfrage an den Nutzer).
`CLAUDE_GATE_TESTMODE=1` verhindert, dass sich das Gate beim Selbsttest
selbst blockiert.

Prüfe dabei **immer beide Richtungen**: Der Fall, der durchgehen soll, und der
Fall, der blockieren soll. Ein Gate, das alles blockiert, besteht einen
einseitigen Test genauso wie ein korrektes.

### Vorhandene Regressionssuiten laufen lassen

Acht Suiten liegen unter `hooks/tests/`, eine unter `scripts/tests/` —
die vier größten:

```bash
bash hooks/tests/gate-regression.sh              # 73 Fälle
bash hooks/tests/web-fetch-gate-regression.sh    # 97 Fälle
bash scripts/tests/deploy-regression.sh          # 20 Fälle (Übergabe)
bash hooks/tests/parallel-lock-regression.sh     # 12 Fälle
ls hooks/tests/ scripts/tests/                   # vollständige Liste
```

Änderst du ein Gate, **erweitere die zugehörige Suite um den neuen Fall** —
sonst ist die Änderung dauerhaft ungeprüft.

> **Behoben (2026-08-22):** Der hier früher dokumentierte Dauerausfall von `hooks/tests/controller-first-regression.sh` (26/3 wegen des unter IMP-115 stillgelegten `q2-probe-dispatch-dump.sh`) ist repariert — die Suite läuft 35/35 grün. Der Warnhinweis stand 18 Tage länger hier als der Defekt existierte; wer eine Suite repariert, nimmt den Aushang im selben Commit mit.

### settings.json-Syntax

```bash
jq . settings.json > /dev/null && echo "JSON OK"
```

Ein Syntaxfehler hier ist besonders tückisch: Claude Code startet dann mit
Standardwerten — ohne Hooks, ohne Berechtigungen — und meldet das nur beiläufig.
**Nie ohne diese Prüfung committen.**

### Bestandsaufnahme statt Handzählung

```bash
./scripts/framework-inventory.sh          # Zahlen von der Platte
./scripts/framework-inventory.sh --json
```

Zahlen in Dokumenten **niemals von Hand** pflegen — sie sind dreimal gleichzeitig
auseinandergelaufen (IMP-083).

### Tresor-Prüfung

Tresor (`~/.claude/vault/`, gitignoriert) hält echte Namen/Pfade/Kennungen —
das Framework selbst darf keinen einzigen enthalten (`docs/adr/0003-tresor-und-tor.md`).

```bash
bash scripts/vault/vault.sh check <datei>                      # Exit 0 sauber, 2 Fund
CLAUDE_VAULT_DIR=/nonexistent bash scripts/vault/vault.sh check --structural-only <datei>  # CI-Simulation ohne Tresor
```

Jeder Schreibzugriff läuft zusätzlich durch `hooks/vault-write-gate.sh`
(PreToolUse Write|Edit|MultiEdit); Umgehung nur bewusst mit
`CLAUDE_VAULT_GATE_OFF=1` (geloggt, nie der Wert). Im Bauhof gehört nur der
pre-commit-Hook hin (`bash scripts/install-git-hooks.sh --only pre-commit`
— der pre-push bleibt dem öffentlichen Beitragsweg vorbehalten).

**Ersteinrichtung** (einmal je Rechner): `templates/env.local.sh.template`
nach `~/.claude/env.local.sh` kopieren/ausfüllen, dann `vault.sh init`.

**Grundregel:** Prosa → Token, Code → Env + fail-loud (nie ein Token als
Rückfallwert), Tests → synthetische Werte.

### Cockpit (eigenes Repo, eigener Bauhof)

```bash
cd "${CLAUDE_WORKSHOP_ROOT}/cockpit"   # aus ~/.claude/env.local.sh
npm test          # 25 Prüfungen
npm run typecheck

# Ereignis-Hook direkt prüfen (schreibt nach $COCKPIT_DIR)
echo '{"session_id":"probe","cwd":"/tmp"}' \
  | COCKPIT_DIR=/tmp bash hooks/cockpit-event.sh SessionStart; echo "exit=$?"
```

## 4. Übergabe und Abnahme

### Übergabe (nach dem Commit im Bauhof)

```bash
claude-deploy config     # oder: cockpit | all
```

Das Werkzeug macht ausschließlich Fast-Forward und bricht ab, wenn der Bauhof
uneingecheckte Änderungen hat.

**Laufzeitpräferenzen (seit IMP-127, 2026-08-04).** Zwei Dinge im Haus schreibt
Claude Code im Betrieb selbst und ließen deshalb früher jede Übergabe scheitern:

| Was | Wer schreibt es | Behandlung |
|---|---|---|
| `settings.json` → `model`, `effortLevel` | `/model`, `/config` | Wird ins Bauhof **zurückgezogen** und dort als eigener Commit verbucht. Das Haus behält den Wert. |
| `plugins/installed_plugins.json`, `plugins/known_marketplaces.json` | jedes Plugin-Update | Nicht mehr versioniert; wird über die Übergabe hinweg gerettet. |

Die Liste der zurückgezogenen Schlüssel steht als `RUNTIME_KEYS_JSON` oben im
Skript. **Sie ist bewusst kurz** — jeder Eintrag schaltet eine Schutzprüfung ab.
Weicht das Haus in einem *nicht* gelisteten Schlüssel oder in einer anderen
verfolgten Datei ab, bricht die Übergabe weiterhin ab und nennt die Stelle. Das
ist der Normalfall für „jemand hat am bewohnten Haus von Hand gearbeitet" — und
genau der soll auffallen.

> **Sackgasse, nicht noch einmal einbauen:** Eine `~/.claude/settings.local.json`
> löst das *nicht*. Auf **Nutzerebene** liest Claude Code diese Datei nicht — die
> lokale Ebene existiert laut `code.claude.com/docs/en/settings` nur pro Projekt
> (`.claude/settings.local.json` im Repo-Wurzelverzeichnis). Nachgemessen am
> 2026-08-04: Die dort eingetragene `NOTION_PARENT_PAGE_ID` ist in der
> Sitzungsumgebung nicht gesetzt. Per-Maschine-Umgebungswerte gehören auf diesem
> Rechner in `~/.zshrc` — von dort kommen sie nachweislich an.

### Abnahmeprotokoll — was der NUTZER prüft

Ein Agent schreibt am Ende seiner Arbeit eine Abnahmeliste in genau dieser Form,
damit die Prüfung nicht erraten werden muss:

```markdown
## Abnahme am laufenden Claude Code

Voraussetzung: `claude-deploy config`, danach eine NEUE Sitzung starten
(`/clear` genügt NICHT — Hooks und Regeln werden nur beim Prozessstart gelesen).

1. <Konkreter Handgriff> → erwartet: <konkret beobachtbares Ergebnis>
2. …

Falls Schritt N fehlschlägt: <was das bedeutet, wo der Fehler stünde>
Rücknahme: `cd ~/.claude && git reset --hard <commit-vor-der-Änderung>`
```

Jeder Schritt muss ein **beobachtbares** Ergebnis nennen — eine Ausgabe, eine
Datei, eine Zeile im Protokoll. „Sollte jetzt besser laufen" ist kein Prüfschritt.

Führt die Übergabe einen neuen Tresor-Begriff ein (ein neues `kind`, eine
neue Gruppe mit spürbarer Zahl), nennt die Abnahmeliste zusätzlich
`bash scripts/vault/vault.sh status` (reine Zahlen, nie ein Wert) als
Prüfschritt.

### Wichtige Feinheit: `/clear` reicht nicht

`/clear` leert den Gesprächsverlauf, startet aber **keinen neuen Prozess**.
Hooks, Regeln, Skills und `settings.json` bleiben auf dem Stand vom Prozessstart.
Für eine echte Abnahme braucht es ein neues Terminal bzw. einen neuen
`claude`-Aufruf.

## 5. Rücknahme

Beide Seiten sind versioniert, jede Übergabe ist umkehrbar:

```bash
cd ~/.claude && git log --oneline | head -5      # Stand vor der Übergabe finden
cd ~/.claude && git reset --hard <commit>        # zurücksetzen
```

Sicherungskopien der `settings.json` liegen ohnehin als
`settings.json.bak-*` im Haus.

## 6. Häufige Fehlgriffe

| Fehlgriff | Warum er schadet |
|---|---|
| Direkt in `~/.claude` editieren | Sofort scharf; blockiert die nächste Übergabe |
| „Getestet" melden, ohne einen Befehl ausgeführt zu haben | Die Selbstreferenz macht Beobachtung in der eigenen Sitzung unmöglich — die Behauptung ist dann frei erfunden |
| Gate ändern, ohne die Regressionssuite zu erweitern | Die Änderung bleibt dauerhaft ungeprüft |
| Zahlen in CLAUDE.md von Hand aktualisieren | Drift; `framework-inventory.sh` ist die einzige Wahrheit |
| `settings.json` ohne `jq`-Prüfung committen | Claude Code startet still ohne Hooks und Berechtigungen |
| Nur den Positivfall eines Gates testen | Ein Gate, das alles blockiert, besteht diesen Test ebenfalls |
| Nebenfunde während der Arbeit gleich mitbauen | Scope Drift — die Sitzung endet dann mit einer offenen Baustelle statt mit Commit + Übergabe |

## Nebenfunde: notieren statt mitbauen (IMP-148)

Eine Bau-Session endet mit Commit + Übergabe, nicht mit einem offenen
Baustellenrest. Fällt während der eigentlichen Aufgabe ein zusätzliches
Problem auf (ein weiterer verbesserungswürdiger Hook, eine drittel-fertige
Doku-Lücke, ein Refactoring-Wunsch) — das wird als `status: proposed` im
Ledger notiert, nicht in derselben Sitzung mitgebaut. Der Auftrag wächst
sonst unbemerkt über seinen Rahmen hinaus, und am Ende ist weder die
Kernaufgabe fertig übergeben noch der Nebenfund sauber verifiziert.

> **Belegt am eigenen Verhalten:** 2026-08-04 „Was Du gerade machst ist Scope
> Drift … Mehr nicht", 2026-08-05 „Keinen Scope Drift. Abschließen und
> deployen" — beide Male musste der Nutzer eine laufende Sitzung zurück auf
> die eigentliche Aufgabe holen.

## Verweise

- Zwei-Orte-Modell kompakt: Abschnitt „Zwei Orte: Bauhof und bewohntes Haus" in `CLAUDE.md`
- Übergabe-Werkzeug: `scripts/deploy-to-live.sh` (verlinkt als `claude-deploy`)
- Architektur des Frameworks: `HARNESS.md`
- Vollständiges Bestandsverzeichnis mit Chronik (Hook-Tabelle, Routinen-Status, IMP-Belege — seit 2026-09-24 nicht mehr in `CLAUDE.md`): `docs/FRAMEWORK-REFERENCE.md`; ausgelagerte Regel-Belege: `docs/archive/rules-evidence/`
