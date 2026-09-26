<!--
Status: ACTIVE
Last Updated: 2026-09-25
Purpose: Vorlage für eine IMP-Einreichung ohne private Daten (IMP-219,
Welle 4 / Gewerk G-script). Ausfüllen, dann mit `scripts/imp-submit.sh`
prüfen lassen — siehe CONTRIBUTING.md, Abschnitt „Submitting an improvement
(IMP) without your private data". Die sechs „## "-Überschriften unten sind
die Pflichtfeld-Anker, die `scripts/imp-submit.sh` per exaktem Textvergleich
wiederfindet — wer eine Überschrift umbenennt, macht das zugehörige Feld für
das Skript unsichtbar (es zählt dann als nie ausgefüllt).
-->

# IMP-Einreichung

## Was NICHT hineingehört

Dieses Formular wird als Issue- oder PR-Text auf GitHub landen. Schreibe
hinein: WAS beobachtbar ist, WELCHE Regel / WELCHER Hook / WELCHES Skill
betroffen ist, und WELCHE Zahl das belegt. Schreibe NICHT hinein: echte
Projekt-, Firmen- oder Kontonamen, maschinenspezifische Pfade
(Benutzerordner, Projektwurzel, Volume-Name), persönliche Kennungen
(E-Mail-Adresse, Sitzungs-, Trigger-, Notion-ID) oder eine identifizierende
Phrase. Nutze stattdessen Platzhalter wie `<projekt>`, `<pfad>`, `<konto>`,
`<team>`. `scripts/imp-submit.sh` prüft das ausgefüllte Formular gegen
deinen lokalen Tresor (falls vorhanden, `scripts/vault/vault.sh`) und immer
strukturell gegen bekannte Muster (Pfade, E-Mail-Adressen, IDs) — die beste
Prüfung bleibt trotzdem, von Anfang an keinen echten Wert zu schreiben.

## Problemklasse

<!-- Eine Zeile: welche Art von Problem — z. B. "fehlende Eskalation",
"stiller Fallback", "falsches Exit-Verhalten", "Token-Mehrverbrauch". -->

## Symptom

<!-- Was beobachtbar falsch ist — ohne Projekt- oder Ortsnamen. Nutze
Platzhalter wie `<projekt>`, `<pfad>`, `<konto>`. -->

## Messwert / Beleg

<!-- Die Zahl oder das Artefakt, an dem das Symptom hängt, plus Messtiefe —
gemessen, nicht vermutet. Beispiel: "17 von 40 Sitzungen zeigten X (grep
über 40 JSONL-Dateien, Stichtag <datum>)". -->

## Vorgeschlagene Änderung

<!-- Welche Regel / welcher Hook / welches Skill sich ändern sollte — wenn
möglich als Diff-Skizze:
```diff
- alte Zeile
+ neue Zeile
```
-->

## Risiko / Band

<!-- AUTO | SOFT-ACK | ESCALATE nach rules/agency-bands.md, plus eine Zeile
Begründung (Reversibilität, Blast-Radius, Input-Vertrauen). -->

## Rücknahme

<!-- Wie diese Änderung rückgängig gemacht werden kann, falls sie sich als
falsch erweist. -->

## Lokale IMP-ID (optional — nur Referenz des Einreichers)

<!-- z. B. IMP-042, falls vorhanden — dient nur deiner eigenen Zuordnung,
wird beim Absenden nicht weiter geprüft. -->
