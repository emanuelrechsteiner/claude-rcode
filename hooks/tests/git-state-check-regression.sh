#!/bin/bash
# Regressionssuite für hooks/git-state-check.sh
#
# Anlass (2026-08-02, Live-Befund): Check 2 fing `git rebase --abort` mit ab,
# fand die Konflikte, die ein Abbruch gerade beseitigt hätte, und blockierte mit
# exit 2 — der Hook versperrte die Notausfahrt aus genau dem Zustand, den er
# verhindern soll. Erschwerend gingen alle Meldungen auf stdout, sodass der
# Blocker ohne jede Begründung erschien ("No stderr output").
#
# Diese Suite hält beide Eigenschaften fest UND die Schutzwirkung, die bleiben
# muss: --continue und commit dürfen bei offenen Konflikten weiterhin blocken.
#
# Aufruf:  bash hooks/tests/git-state-check-regression.sh
# Exit:    0 = alle Fälle grün · 1 = mindestens ein Fall rot

set -uo pipefail

HOOK="${CLAUDE_HOOK:-$HOME/.claude/hooks/git-state-check.sh}"
[[ -f "$HOOK" ]] || { echo "FEHLER: Hook nicht gefunden: $HOOK" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

GRUEN=0
ROT=0

# Ruft den Hook mit einem Befehl auf. Gibt "<rc>|<stdout>|<stderr>" zurück.
ruf_hook() {
    local cmd="$1"
    local out err rc
    out=$(mktemp); err=$(mktemp)
    printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        | bash "$HOOK" >"$out" 2>"$err"
    rc=$?
    printf '%s|%s|%s' "$rc" "$(tr '\n' ' ' <"$out")" "$(tr '\n' ' ' <"$err")"
    rm -f "$out" "$err"
}

pruefe_rc() {
    local name="$1" cmd="$2" erwartet="$3"
    local ergebnis rc
    ergebnis=$(ruf_hook "$cmd"); rc="${ergebnis%%|*}"
    if [[ "$rc" == "$erwartet" ]]; then
        echo "  ok    $name (rc=$rc)"; ((GRUEN++))
    else
        echo "  ROT   $name — erwartet rc=$erwartet, bekam rc=$rc"; ((ROT++))
    fi
}

# ── Konfliktbehafteten Arbeitsbaum herstellen ────────────────────────────────
REPO="$WORK/repo"
mkdir -p "$REPO" && cd "$REPO" || exit 1
git init -q . 2>/dev/null
git config user.email "test@example.invalid"
git config user.name "Regression Test"
printf 'eins\n' > datei.txt
git add datei.txt && git commit -q -m "basis"
git checkout -q -b zweig
printf 'zwei\n' > datei.txt && git commit -qam "zweig"
git checkout -q - 2>/dev/null || git checkout -q master 2>/dev/null || git checkout -q main
printf 'drei\n' > datei.txt && git commit -qam "trunk"
git merge zweig >/dev/null 2>&1   # erzeugt den Konflikt — Rückgabewert egal

if [[ -z "$(git diff --name-only --diff-filter=U)" ]]; then
    echo "FEHLER: Testaufbau erzeugte keinen Konflikt — Suite aussagelos." >&2
    exit 1
fi
echo "Testaufbau: offener Konflikt in $(git diff --name-only --diff-filter=U | tr '\n' ' ')"
echo ""

echo "── Notausfahrten MÜSSEN durchgelassen werden (der behobene Fehler) ──"
pruefe_rc "git rebase --abort"        "git rebase --abort"        0
pruefe_rc "git merge --abort"         "git merge --abort"         0
pruefe_rc "git rebase --skip"         "git rebase --skip"         0
pruefe_rc "git rebase --quit"         "git rebase --quit"         0
pruefe_rc "git cherry-pick --abort"   "git cherry-pick --abort"   0

echo ""
echo "── Schutzwirkung MUSS erhalten bleiben ──"
pruefe_rc "git rebase --continue bei Konflikt" "git rebase --continue"       2
pruefe_rc "git commit bei Konflikt"            "git commit -m 'trotzdem'"    2
pruefe_rc "git push bei Konflikt"              "git push origin main"        2

echo ""
echo "── Begründung muss auf STDERR stehen, nicht auf stdout ──"
ergebnis=$(ruf_hook "git commit -m x")
stdout_teil="${ergebnis#*|}"; stdout_teil="${stdout_teil%%|*}"
stderr_teil="${ergebnis##*|}"
if [[ -n "${stderr_teil// /}" ]]; then
    echo "  ok    Begründung auf stderr vorhanden"; ((GRUEN++))
else
    echo "  ROT   stderr leer — Blocker ohne Begründung (der zweite Befund)"; ((ROT++))
fi
if [[ -z "${stdout_teil// /}" ]]; then
    echo "  ok    stdout bleibt leer"; ((GRUEN++))
else
    echo "  ROT   stdout trägt Text: '${stdout_teil}'"; ((ROT++))
fi

echo ""
echo "── Nicht-git-Befehle und sauberer Baum ──"
pruefe_rc "npm test (kein git)" "npm test" 0
pruefe_rc "git status (nicht in der Prüfliste)" "git status" 0
git merge --abort >/dev/null 2>&1
pruefe_rc "git commit im sauberen Baum" "git commit -m 'sauber'" 0

echo ""
echo "═══════════════════════════════════════════"
echo "  grün: $GRUEN · rot: $ROT"
[[ $ROT -eq 0 ]] && { echo "  ALLE FÄLLE GRÜN"; exit 0; }
echo "  SUITE ROT"; exit 1
