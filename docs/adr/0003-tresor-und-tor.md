# 0003 — Tresor und Tor: pseudonymisiert von Anfang an

- Status: accepted
- Date: 2026-09-25

## Context

Auslöser waren zwei wörtliche Nutzeranweisungen (2026-09-25): „Gibt es eine
Möglichkeit, das pseudonomized by design zu machen? Dass NIE ein echte Name
oder realer Pfad, etc im Framework landet? Beim Optimieren auf dem Rechner
des Entwicklers ist das ok, aber im Framework selbst hat es eigentlich
nichts zu suchen." und, zum Mechanismus: „IM Prinzip müsssten wir das so
lösen, wie in einer Datenbank, die ein Vault für P2 Daten hat. Wir brauchen
eine Schicht, die das gehasst auslesen kann. Die rechten Namen und Pfade
sind also wie in einer Datenbank die P2 Daten, die dürfen nur in den Vault
geschrieben werden, müssen irgendwie gehasst werden."

Vor diesem Rework lag über den gesamten Bestand verteilt eine Mischung aus
echten Maschinenpfaden, Konto- und Projektnamen und persönlichen Kennungen
in versionierten Dateien — Prosa, Kommentaren, Test-Fixtures, dem
Verbesserungs-Ledger. Eine Bestandsaufnahme vor Welle 3 zählte 326 Funde in
64 Dateien. Der Schreiber, der diese Dateien laufend erweitert, ist ein
Sprachmodell: eine Konvention allein („bitte keine echten Namen") ist
erfahrungsgemäß nicht zuverlässig genug, um eine Invariante zu tragen
(`rules/slop-prevention.md`).

**Bedrohungsmodell:** nicht „niemand darf die Namen kennen" — sie liegen
ohnehin unverändert in den Projekten auf derselben Platte —, sondern: die
Namen verlassen den Rechner nie **über das Framework**: nicht über einen
Commit in dieses Repo, nicht über dessen Veröffentlichung als öffentlicher
Klon, nicht über eine von hier aus eingereichte Verbesserung.

## Decision

**Invariante:** Kein versioniertes Byte dieses Repos enthält einen echten
Projekt-, Firmen- oder Kontonamen, einen maschinenspezifischen Pfad
(Benutzerordner, Volume-Name, Projektwurzel), eine persönliche Kennung
(E-Mail-, Sitzungs-, Trigger-, Notion-ID) oder eine identifizierende Phrase.
Diese Werte leben ausschließlich im lokalen **Tresor**
(`~/.claude/vault/`, gitignored, reine Laufzeitdaten im Haus). Das Framework
verweist auf sie über **Tokens**.

**Drei Schichten, weil der Schreiber unzuverlässig ist:**

| Schicht | Aufgabe | Wo |
|---|---|---|
| Tresor | Speicher der echten Werte + zugleich die Sperrliste | `~/.claude/vault/` (`map.tsv` + `secret`) |
| Tor | verweigert jeden Schreibzugriff mit echtem Wert in eine versionierte Datei | PreToolUse-Hook, git `pre-commit`, öffentliche CI |
| Tokenizer | ersetzt an der Erfassung — in Skripten, die selbst in versionierte Dateien schreiben | `scripts/vault/vault.sh tokenize` |

**Hashing statt Klartext-Platzhalter.** Ein Token ist ein HMAC-SHA256-Präfix
mit einem lokalen Geheimwert (`hex6 = erste 6 Hex von
HMAC-SHA256(secret, "<kind>:<group>")`). Ein reiner Hash wäre per Wörterbuch
rückrechenbar — Projekt- und Kontonamen haben wenig Entropie; ein HMAC ohne
den Geheimwert nicht. Auf demselben Rechner ist ein Token stabil (eine
Messreihe über mehrere Sitzungen bleibt zusammen lesbar), auf einem anderen
Rechner unterscheidet sich derselbe Klartext-Wert im Token — die Tresore
zweier Entwickler sind nicht gegeneinander verknüpfbar.

**Der Tresor** liegt unter `${CLAUDE_VAULT_DIR:-$HOME/.claude/vault}`
(Verzeichnis `0700`, `secret` `0600`, einmal erzeugt und danach nie
überschrieben). `map.tsv` führt je Zeile `kind`, `term` (der echte Wert),
`token` und `group`: mehrere `term`s mit derselben `group` — Kurzname,
Langname, andere Schreibweise, Repo-Name, Pfad-Alias — teilen sich EIN
Token, damit dieselbe reale Entität nach der Ersetzung als eine Entität
erkennbar bleibt, statt in mehrere unverbundene Tokens zu zerfallen.

**Ein Matcher für alle Verbraucher** (`rules/testing-quality.md`, „Verify
Via the Same Code Path"): `scripts/vault/lib.sh` wird von `vault.sh`
(check/tokenize/resolve), `scripts/scrub-check.sh`,
`publish-transforms.d/50-pseudonymize.sh`, `hooks/vault-write-gate.sh` und
`scripts/git-hooks/pre-commit` gleichermaßen gesourct — kein zweiter,
unabhängig geschriebener Ausdruck, der mit der Zeit vom ersten abweichen
könnte.

**Strukturmuster brauchen keinen Tresor** und greifen deshalb auch in der
öffentlichen CI eines Klons, der nie einen Tresor besitzt: Benutzer-/
Volume-Pfade (`/Users/<seg>`, `/Volumes/<seg>` ohne erkennbaren
Platzhalter), E-Mail-Adressen (außer dokumentierten Ausnahmen wie
`noreply@anthropic.com` oder `*@example.com`), UUIDs sowie Sitzungs- und
Trigger-Kennungsformen. Eine IANA-Zeitzone (`Europe/Berlin` u. ä.) ist
davon bewusst ausgenommen und nur eine Warnung, kein Fund — der Wert ist zu
grobkörnig, um für sich genommen jemanden zu identifizieren, kommt aber oft
genug in echten Konfigurationswerten vor, dass er nicht blockieren soll.

**Ausnahmen, jede eng gefasst:** eine zeilengenaue Allowlist
(`scripts/scrub-allowlist.txt`, `pfad:zeile:schnipsel`) für Stellen, die den
Mustertext selbst als Quelltext enthalten (die Musterdefinition in `lib.sh`
träfe sonst sich selbst); eine einzeilige Fixture-Markierung
(`# vault-check: fixtures (<Grund>)`) für Testdateien unter `*/tests/*`, die
nur strukturelle Funde freistellt — ein echter Tresor-Begriff wird auch in
einer markierten Testdatei gemeldet; gitignorierte Dateien sind nie
Prüfgegenstand.

**Was das NICHT ist:** kein Ersatz für die harten Tore
(`rules/agency-bands.md`, das Bash- und das MCP-Gate) und keine
Verschlüsselung des Tresors selbst — er liegt auf derselben Platte neben den
Projekten, die er benennt; eine Verschlüsselung schützte dort praktisch
nichts zusätzlich, solange der Rechner selbst als Vertrauensgrenze gilt.

**Einzelentscheidungen zu Grenzfällen**, getroffen von der Leitung während
der Umsetzung und im Abschlussbericht dem Eigentümer genannt (jede mit einer
Zeile rücknehmbar). **Vom Eigentümer bestätigt am 2026-09-26** (Abnahme von
PR #6, wörtlich: „alle Entscheidungen so wie von Dir vorgeschlagen"):

| Kategorie | Tresor-Begriff? | Behandlung |
|---|---|---|
| Öffentliche Framework-Namen (die Namen, unter denen sich dieses Framework selbst veröffentlicht) | Nie | `scripts/vault/public-names.txt`; `init`/`add` überspringen bzw. verweigern sie, `vault.sh prune-public` entfernt sie aus einem bereits bestehenden Tresor |
| Produktnamen Dritter (z. B. das gleichnamige Anthropic-Produkt „Cowork") | Nie | zweite Kategorie in `public-names.txt` — der Altlisten-Import hatte den Namen zunächst fälschlich als privat übernommen |
| Öffentliche Identität des Eigentümers (Zuschreibung, GitHub-Konto) | Nie | bleibt sichtbar, wo sie ohnehin schon öffentlich ist (Lizenz-Zuschreibung, Eigentümerschaft des öffentlichen Repos); in Test-Fixtures trotzdem durch einen synthetischen Namen ersetzt — Testhygiene, nicht Geheimhaltung |
| Früherer Name des Frameworks (vor dem Rebrand) | Nie | war selbst ein veröffentlichter Name; `MIGRATION.md` braucht ihn zur Einordnung für Alt-Nutzer — das separate Rebrand-Thema (sein Vorkommen in noch aktiven Dokumenten) bleibt davon unberührt |
| Private Repository-Adresse(n) | `<private-repo-url>` | mehrere Schreibformen als Aliasse derselben Gruppe; im Code nie als Rückfallwert — der Wert kommt aus `git remote get-url origin` oder einer benannten Umgebungsvariable, sonst lauter Abbruch statt stillem Fallback |
| Kennzeichen einer bestimmten privaten, lokalen Überlagerungsschicht | `<private-layer>` | strenger als jede andere Kategorie: Verweise darauf UND Beschreibungen ihrer Mechanik oder Zitate aus ihrem Umfeld werden **entfernt statt tokenisiert** — eine ausdrückliche Vorgabe des Eigentümers nur für diese eine Schicht |
| Namen und identifizierende Angaben Dritter (ein Beta-Tester, ein Vorfall mit sensiblen personenbezogenen Daten Dritter) | Keiner | werden auf eine Rolle bzw. eine verallgemeinerte Kategorie reduziert, nicht tokenisiert — ein Token signalisierte weiterhin „hier gibt es eine bestimmte dritte Person", eine Rolle nicht einmal das |
| Kurze Sitzungskennungen als Belegzeiger (z. B. im Ledger) | ja, `kind=id` | `vault.sh add id <wert> --token "$(vault.sh token id <wert>)"` — lokal auflösbar, dann tokenisiert; von Commit-Kennungen und Prüfsummen im selben Text nach Kontext unterschieden, die unverändert bleiben (öffentlich und ohnehin reproduzierbar) |

## Consequences

**Leichter wird:** Die Veröffentlichung eines Klons wird ein Vorgang ohne
inhaltliche Prüfung der eigenen Historie — die Quelle ist bereits sauber,
die bestehenden `publish-transforms.d`-Skripte sind nur noch ein zweites
Netz. Ein Beitrag Dritter (`scripts/imp-submit.sh`) kann geprüft und als
fertiger Issue-/PR-Text erzeugt werden, ohne dass der Beitragende einen
echten Namen, Pfad oder eine Kennung von seinem Rechner weggibt. Neue
Skripte, die Maschinenwerte brauchen, haben mit `~/.claude/env.local.sh` und
`vault.sh token` einen dokumentierten Ort dafür, statt sich einen eigenen
Rückfallwert auszudenken.

**Schwerer wird:** Das Verbesserungs-Ledger und ähnliche Belegdateien lesen
sich nach der Umschreibung in Tokens statt Klarnamen — wer den Kontext eines
Eintrags nachvollziehen will, braucht `vault.sh resolve` auf demselben
Rechner, auf dem der Eintrag entstand; auf einem anderen Rechner oder ohne
Tresor bleibt der Token ein Token. Der Tresor selbst ist nirgends gesichert
(bewusst — er liegt neben den Projekten, die er benennt, siehe Decision) und
seine Sicherung obliegt allein dem Eigentümer; sein Verlust macht ältere
Tokens irreversibel unauflösbar. Eine Freitext-Restlücke bleibt
grundsätzlich bestehen — kein Muster und kein Tresor-Eintrag erkennt jede
Umschreibung eines echten Sachverhalts zuverlässig, weshalb zwei lesende
Gegenprüfer als zusätzliche, nicht automatisierbare Schicht eingeplant sind
(Welle 5 dieses Reworks fand auf diesem Weg mehrere Fälle, die kein Muster
kannte). Und: Das Tor ist ein Hygiene-Tor, kein CRITICAL-Floor — bei einem
Infrastrukturfehler (fehlendes `jq`, ein defektes `vault.sh`) lässt es den
Schreibzugriff laut durch, statt ihn stillschweigend zu blockieren oder
stillschweigend durchzulassen (`rules/fail-loud.md`); wer die Prüfung bewusst
umgeht (`CLAUDE_VAULT_GATE_OFF=1`), tut das geloggt, aber ungehindert.

**Referenzen:** `scripts/vault/` (Kern, Matcher, öffentliche Namensliste),
`hooks/vault-write-gate.sh` (PreToolUse-Tor), `scripts/git-hooks/pre-commit`
(zweite Schicht für Bash-seitige Schreiber), `scripts/imp-submit.sh`
(geprüfte Einreichung für Dritte ohne Netzwerkzugriff), `docs/PUBLISHING.md`
(Veröffentlichungskette gegen denselben Tresor).
