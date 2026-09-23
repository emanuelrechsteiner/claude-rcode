# Agenten — zuerst hier lesen

Dieses Repo ist die Konfiguration von Claude Code selbst und existiert an
**zwei** Orten. Stelle vor jeder Änderung mit `pwd` fest, wo du bist:

| Pfad | Ort | Regel |
|---|---|---|
| `…/5-AI-APPS/claude-code-config` | **Bauhof** | Hier ändern und committen. Nichts wirkt live. |
| `~/.claude` | **Haus** | Was Claude Code liest. **Nicht von Hand ändern** — nur `claude-deploy` schreibt hierher. |

Drei Regeln:

1. **Änderungen ausschließlich im Bauhof.**
2. **Du kannst deine Arbeit nicht in deiner eigenen Sitzung verifizieren** —
   Regeln, Hooks und Skills werden beim Sitzungsstart gelesen. Melde nie
   „funktioniert", sondern schreibe ein Abnahmeprotokoll für den Nutzer.
3. **Prüfe, was ohne Übergabe prüfbar ist:** Hook-Skripte direkt aufrufen,
   `jq . settings.json`, Regressionssuiten unter `hooks/tests/`.

**Vollständige Baustellenordnung: [`docs/WORKING-IN-THIS-REPO.md`](docs/WORKING-IN-THIS-REPO.md)**
— darin auch die Beispielbefehle zum Hook-Test und das Format des
Abnahmeprotokolls.
