# 0002 — R.Code-Rework „Plan folgt Praxis": ein Entry-Point, Stages als Playbooks, zwei Tracker-Modi

- Status: accepted
- Date: 2026-09-23

## Context

Der R.Code-Workflow wurde 2026-07-26 als Plan entworfen (5 Team-Commands je einer
Projekt-Phase 1–5 zugeordnet, `/team-lead` als „phase-agnostic fallback",
GitHub-Issues als durchgängige Grundannahme, ein 5-Schritt-Exit-Contract, der bei
jedem Befehlsende lief). Gemessen an 471 Haupt-Transkripten + den 5 real
laufenden R.Code-Projekten (Projekt L, Projekt W, Projekt N, Projekt K,
Projekt M; gemessen 2026-09-23) driftete die Praxis früh und deutlich vom Plan
weg:

- `/team-lead` 67× genutzt (16 Projekte); `/plan-team` … `/launch-team` zusammen
  **0×**. Die fünf Team-Commands existierten nur auf dem Papier als „primary
  entry points" — tatsächlich lief jede Sitzung über den als „fallback"
  dokumentierten `/team-lead`.
- `/issue`, `/decompose`, `/phase-gate`, `/lessons`, `/continue`, `/rcode-review`,
  `/rcode-upgrade`, `/scope-check`, `/autonomous-overnight` je **0×**.
  `re-entry-brief.md` 0/5 Projekten, `phase-summaries/` leer in 3/5,
  `escalation-queue.md` in 2/5, `scope_changes[]` in 2/5 (nur dort genutzt, wo
  es genutzt wurde: Projekt W 4×, Projekt N 7×). `agent-log.md` dagegen in 5/5
  Projekten lebendig — das ist das Artefakt, das tatsächlich trägt.
- Projekt N hat **keinen** Git-Remote (0/28 Commits referenzieren irgendetwas);
  Projekt M nutzt eigene Plan-IDs `refs P-NNN` statt GitHub-Issues (IMP-150).
  GitHub war in Commands/Templates dennoch eine harte Voraussetzung.
- Unter `/team-lead` committeten 16 Subagenten in 4 Wellen auf EINEN geteilten
  Branch (`overnight/2026-09-21-foundation`, Projekt M) — `/issue` als
  „bindendes Protokoll" für Worker wurde nie im dort dokumentierten Sinn
  aufgerufen (Branch pro Unit, PR pro Unit).
- 24 weitere konkrete Defekte wurden mit Datei:Zeile-Beleg verifiziert (M1–M24,
  vollständige Liste + Fundstellen: `CHANGELOG.md` Eintrag 2026-09-23, sowie der
  Bauplan, aus dem dieser Rework hervorging).

Auslöser war die wörtliche Nutzerdirektive: „Ganz klar der Plan folgt der Praxis.
Ich möchte, dass DU all Mängel beseitigst und das Framework optimierst, bevor ich
mit meinen Input komme."

**Erwogene Alternativen, verworfen:**

1. **Fünf vollständige Team-Prozeduren beibehalten, nur Bugs fixen.** Verworfen:
   das hätte die 70 %-identische 5×-Duplikation (die IMP-083-Drift-Klasse)
   zementiert, statt die Ursache — die Prozedur lebt 5× statt 1× — zu beheben.
2. **`.gitattributes merge=union` für `.rcode/agent-log.md`** (ursprünglich als
   M21-Fix geplant). Verworfen nach adversarialer Kritik: zeilenbasierte Merges
   können mehrzeilige Log-Einträge verschachteln und ein korrupt gemergtes Log
   ist schwerer zu erkennen als ein Konflikt. Ersetzt durch eine Single-Writer-
   Regel (A12): `.rcode/agent-log.md` und `PROJECT-STATUS.md` werden nur vom
   Lead/Main-Thread geschrieben, nie von einem dispatchten Worker.
3. **GitHub-Issues als einzige unterstützte Tracker-Form beibehalten.** Verworfen:
   2 von 5 realen Projekten können das nicht erfüllen (kein Remote; eigene
   Plan-IDs) — ein „Pflicht"-Feature, das 40 % der eigenen Nutzerbasis nicht
   erfüllen kann, ist keine Pflicht, sondern ein blinder Fleck.
4. **`/rcode-upgrade` committet weiterhin nie** (die ursprüngliche Invariante).
   Verworfen: uncommittete Stempel verrotteten in 3 von 5 Projekten — die
   Invariante schützte vor nichts, sie erzeugte nur stillen Datenverlust.
   Ersetzt durch A9: ein Commit nach genau einem expliziten y/n.

## Decision

Der Workflow wird umgebaut, damit die Architektur der gemessenen Praxis folgt,
nicht umgekehrt:

1. **Ein Entry-Point.** `/team-lead "<directive>"` ist der dokumentierte
   Haupteingang für jede R.Code-Projektarbeit. `/plan-team` … `/launch-team`
   bleiben installiert, aber nur noch als dünne Aliase (`/team-lead` mit
   erzwungener Stage) — Türen, keine eigenen Prozeduren, weil Nutzer ihre Namen
   als Stichworte eintippen.
2. **Stages statt Team-Phasen, als globale Playbooks.** Fünf Arbeitsmodi
   (Plan/Design/Develop/Test/Launch) lösen den überladenen Begriff „Phase" ab
   (der jetzt ausschließlich Projekt-Meilenstein bedeutet). Ihr Prozedurinhalt
   lebt einmal in `~/.claude/rcode/stages/{plan,design,develop,test,launch}.md`,
   nicht mehr 5× dupliziert in den Team-Commands.
3. **Zwei Tracker-Modi.** `github` (Issues/Milestones/Labels) und `plan`
   (`P-NNN`-Checkbox-Zeilen in `BRAINSTORM.md`, kein GitHub nötig) — Commands
   lesen `.rcode/config.json` → `tracker` statt GitHub anzunehmen.
4. **Proportionaler Exit statt Fünf-Schritt-Exit-Contract.** Der bisherige
   Exit-Contract lief bei jedem Befehlsende vollständig, unabhängig davon, ob
   überhaupt etwas geschah — u. a. hätte `/develop-team`s Exit `/phase-gate`
   ohne definiertes N aufgerufen und jede nicht-finale Sitzung geblockt (M11).
   Jetzt: jeder der 6 möglichen Exit-Schritte feuert nur unter seiner eigenen
   Bedingung (Arbeit geschah, Unit-Status änderte sich, alle Units der Phase
   sind zu, …).
5. **Backward-Transitions-Regel demoted.** Das Rücksprung-Protokoll
   (`rules/phase-backward-transitions.md`) behauptete „nicht global geladen",
   lag aber in `rules/` und war es — ~1,2K Token in jeder Sitzung jedes
   Projekts, obwohl nur R.Code-Stage-Arbeit es je braucht. Verschoben nach
   `~/.claude/rcode/stages/backward-transitions.md`, von den Stage-Playbooks
   referenziert statt immer geladen.
6. Zusätzlich, im Detail: zwei Worker-Modi für `/issue` (A1 — standalone vs.
   dispatchter Worker, der letztere ohne eigenen Branch/PR), Env-Key-Preflight
   vor dem ersten Dispatch einer Unit-Kette (A11, IMP-169), ADRs zweistufig
   (inline in `ARCHITECTURE.md` bei Design-Entscheidung, gefeilt nach
   `docs/adr/` bei Finalisierung — A5), und der Watchdog-Seitenfund M22/A8.

## Consequences

**Leichter wird:** die Stage-Prozedur lebt einmal statt 5× — eine Änderung trifft
alle fünf Aliase gleichzeitig, keine Drift mehr möglich. Projekte ohne GitHub
(gemessen: 2 von 5) können R.Code vollständig nutzen. Jede Sitzung jedes
Projekts spart die ~1,2K Token des jetzt nicht mehr immer geladenen
Rücksprung-Protokolls. `/rcode-upgrade`-Stempel verrotten nicht mehr uncommitted.
Ein Worker, der in einer geteilten Welle dispatcht wird, hat jetzt ein
dokumentiertes Protokoll, das der tatsächlichen Praxis (ein Branch pro Welle,
kein Branch pro Unit) entspricht statt sie zu ignorieren.

**Schwerer wird:** fünf Alias-Commands bleiben als Türen bestehen (nicht
gelöscht), obwohl die Praxis zeigt, dass fast niemand sie direkt aufruft — ein
bewusster, dauerhafter kleiner Redundanzpreis, weil Nutzer ihre Namen als
Stichworte kennen und tippen. Die alte `phase-N`-Benennung (Labels, Milestones,
Tags) bleibt aus Kompatibilitätsgründen erhalten, obwohl „Phase" jetzt
ausschließlich Meilenstein bedeutet und nicht mehr für Team-Stufen verwendet
werden darf — zwei nah beieinanderliegende Begriffe bleiben nebeneinander
bestehen, mit dem Glossar als einziger Entwirrungshilfe.

**Offene Fragen, nicht hier entschieden (A15):**

- `/autonomous-overnight` hat weiterhin **0** Aufrufe, während der eine reale
  Overnight-Lauf über `/team-lead` + die Agency-Bands-Eskalationswarteschlange
  lief. Ob `/autonomous-overnight` einen eigenständigen Wert gegenüber dieser
  Kombination hat, ist unentschieden — Folgeauftrag, nicht Teil dieses Reworks.
- `CONTEXT.md`-Adoption liegt bei ~0 % in den realen Projekten, obwohl die Regel
  seit 2026-08-03 global geladen ist (A6 skaliert den Anspruch entsprechend
  herunter: nur Stub bei Init, Seeding bei Brainstorm/Migrate — kein
  rückwirkendes Nachtragen).
- Die `/rcode-upgrade`-Commit-Invariante wurde bewusst geändert (A9, von „nie
  committen" zu „committen nach einem y/n") — diese ADR ist der maßgebliche
  Beleg für diese Verhaltensänderung.
- Aufbewahrungsfrist für Handoff-Snapshots (`.rcode/handoff-<datum>-<session>.md`,
  A14) ist offen, nicht in diesem Rework gebaut.

**Revisit when:** die `plan`-Tracker-Modus-Praxis über mehr als 2 Projekte hinweg
Signal liefert; `/autonomous-overnight`-Nutzung (falls sie je über 0 steigt)
gegen die `/team-lead`-Queueing-Alternative neu bewertet werden kann; die
`CONTEXT.md`-Adoption erneut gemessen wird.
