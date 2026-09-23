# 0001 — Serena-Schreibwerkzeuge hinter einem delegierenden, fail-closed Torwächter reaktivieren

- Status: accepted
- Date: 2026-08-05

## Context

Die Schutz-Hooks in `settings.json` binden an Werkzeug-**Namen** (`Write|Edit`).
Serenas Schreibwerkzeuge heißen `mcp__serena__*` — kein Name passt, jeder
Serena-Edit lief an allen 10 Write|Edit-Hooks vorbei (inkl. `security-audit.sh`
und `observation-capture.sh`). Deshalb wurden 2026-07-17 alle 11 Schreibwerkzeuge
global abgeschaltet (IMP-104/105, „read-only by design"). Das damalige
3:0-Gutachten verwarf einen Adapter: alle Prüfer sind fail-open (Exit 0 bei
fehlendem `file_path`/`content`) — ein halber Adapter hätte grün gemeldet, ohne
zu prüfen.

Der Preis: Serenas referenzbewusste Werkzeuge (`rename_symbol`,
`safe_delete_symbol`) und die tokensparenden Symbol-Edits entfielen ersatzlos.
Der Nutzer bewertete diesen Verlust 2026-08-05 als zu hoch: Serena ist auf
effizientes Code-Arbeiten spezialisiert; ein Weg zur Nutzung ohne
Kompromittierung des Schutzsystems war gefordert.

## Decision

Ein delegierender, fail-closed PreToolUse-Hook (`hooks/serena-write-gate.sh`,
Matcher `mcp__serena__.*|mcp__plugin_serena_serena__.*`) übersetzt jeden
Serena-Schreibaufruf in das native `(file_path, new_string)`-Formular und ruft
**dieselben Prüfskripte** auf wie der native Pfad (keine driftfähigen Kopien):
`parallel-lock-check` → `file-protection` → `security-audit` →
`config-protection` (dessen recoverable *ask* bewusst zuletzt). Fail-closed
heißt: unbekanntes Werkzeug, fehlender Vertragsparameter (Param-Drift),
unparsebare Eingabe oder fehlendes Prüferskript → **deny**, niemals
durchwinken; es existiert kein Bypass-Env. `rename_symbol`/`safe_delete_symbol`
erhalten statt stillem Allow eine Rückfrage (der Sprachserver schreibt N nicht
benannte Referenzdateien). `replace_in_files` bleibt doppelt gesperrt.
Notiz-Namen mit Pfadanteilen werden verweigert. Ein PostToolUse-Zwilling
(`serena-post-tool.sh`) speist die native Nachlaufkette und den Read-Tracker.
Damit schrumpft `excluded_tools` in `~/.serena/serena_config.yml` auf
`replace_in_files`; Aktivierung zwingend **nach** Deploy + neuer Session.

## Consequences

Leichter wird: Symbol-Edits und referenzbewusste Refactorings mit Serenas
Spezialwerkzeugen, unter identischem Schutzniveau wie native Edits;
signals.jsonl sieht Serena-Edits erstmals. Schwerer wird: jede Erweiterung von
Serenas Werkzeugsatz erfordert eine bewusste Vertragserweiterung im Gate samt
Regressionsfall (fail-closed macht Neues erst einmal zu). Bekannte Restlücken,
dokumentiert statt versteckt: `gateguard`/`pretool-auto-read` und
`controller-first-mutation-gate` werden nicht delegiert; die N−1
Referenzdateien eines bestätigten `rename_symbol` werden nicht einzeln
inspiziert. Beweis der Live-Wirkung steht aus, bis `claude-deploy` + neue
Session den Dreifach-Nachweis erlauben (Secret-Block, signals-Zeile,
rename-Rückfrage) — Regressionsstand: 35/35
(`hooks/tests/serena-gate-regression.sh`). Supersedes das Adapter-Verdikt aus
IMP-104; Ledger: IMP-130.

## Update 2026-08-05 — Live-Nachweis erbracht, dabei ein Fund

Die erste Sitzung nach `claude-deploy` erlaubte den oben angekündigten
Dreifach-Nachweis, geführt gegen ein absichtlich außerhalb dieses Repos
aktiviertes Serena-Scratch-Projekt:

1. **Secret-Block** — ein `replace_content`-Aufruf mit einem AWS-Schlüsselmuster
   (`AKIA...`) wurde von `security-audit.sh` blockiert. Bestanden.
2. **Signals-Zeile** — ein sauberer Serena-Edit erschien in `signals.jsonl` und
   `serena-gate-log.jsonl` — zunächst mit einer **falschen Pfadangabe** (Fund,
   siehe unten; nach dem Fix korrekt).
3. **Rename-Rückfrage** — der Wächter löste korrekt `"decision":"ask"` aus. Ob
   daraus eine echte Unterbrechung wird, hängt vom Freigabemodus der Sitzung
   ab: im automatischen Freigabemodus (`--dangerously-skip-permissions`/YOLO)
   wird `ask` automatisch aufgelöst, ohne dass eine Rückfrage sichtbar wird.
   Kein Defekt des Gates — eine Grenze dieses spezifischen Nachweises, nicht
   der Vorkehrung selbst.

**Fund:** `resolve_path()` in `serena-write-gate.sh` (und `serena-post-tool.sh`)
baute die absolute Adresse aus `$CWD` — dem Arbeitsverzeichnis der
Claude-Code-Sitzung — statt aus Serenas tatsächlicher aktiver Projektwurzel.
Beide sind nur identisch, wenn genau ein Projekt pro Sitzung aktiv ist; ein
Bash-Hook kann Serenas laufenden Prozesszustand nicht synchron abfragen, kann
diese Divergenz also nicht auflösen. Bei Abweichung prüften die
nachgeschalteten Schutzskripte (`file-protection.sh` u. a.) eine erfundene,
nicht existierende Adresse statt der echten Zieldatei, und das Bautagebuch
protokollierte denselben falschen Pfad — eine stille, sicherheitsrelevante
Fehlfunktion, keine kosmetische.

**Fix:** Die sechs Werkzeuge, die zwingend eine bereits existierende Datei
bearbeiten (`replace_content`, `replace_symbol_body`, `insert_after_symbol`,
`insert_before_symbol`, `rename_symbol`, `safe_delete_symbol`), verweigern
jetzt (`deny`), wenn die zusammengebaute Adresse auf der Platte nicht
existiert — fail-closed statt stiller Prüfung gegen eine Fiktion, auch vor
dem multi-file-`ask` von `rename_symbol`/`safe_delete_symbol`. Die
Regressionsvorrichtung legt jetzt echte Fixture-Dateien an (vorher wurden nur
Pfadnamen benannt, nie Dateien erzeugt — der Fehler war für die alte
Vorrichtung strukturell unsichtbar) und enthält zwei neue Fälle, die die
Divergenz über ein zweites, unabhängiges Verzeichnis nachstellen.
Regressionsstand: **37/37**. Bekannte Restlücke, unverändert: eine unter der
falschen Adresse zufällig gleichnamige, unabhängige Datei würde weiterhin
(fälschlich) gegen sich selbst geprüft; Gedächtnis-Werkzeuge bleiben ohne
Existenzprüfung, weil sie legitim neue Dateien anlegen dürfen. Ledger:
IMP-131.
