#!/usr/bin/env bash
# logbook-count v3.4 — Tageszaehlung "touched file days" (TFD), Zaehlbasis REPO-IDENTITAET
# Aufruf: LOGBOOK_ROOTS=<pfad zu roots.txt> bash logbook-count.sh YYYY-MM-DD
# Optional (Backfill/alte Tage vor der Transkript-Epoche): LOGBOOK_GIT_ROOTS=<pfad zu
# git-roots.txt> — Baumwurzeln (nicht Repos) fuer die quellenunabhaengige Git-Discovery.
# Ohne diese Variable bleibt ein Tag VOR der Transkript-Epoche ohne Discovery-Repos ein
# ABORT(24), nie eine stille 0. Siehe roots.txt.example / git-roots.txt.example daneben.
# Schreibt AUSSCHLIESSLICH nach $WORK (mktemp -d unter TMPDIR). Kein Repo, kein ~/.claude.
#
# MODUL-STATUS (assembliert 2026-07-18 aus zwei Workflow-Runden, R4+R5 — backend-agent):
# Dieses Skript ist VOLLSTAENDIG SELBSTENTHALTEN. qv2.py und canon.py liegen als
# HISTORISCHE, NICHT VERDRAHTETE Referenzartefakte daneben (Entwicklungsstand vor der
# Einbettung in dieses Skript) — sie werden zur Laufzeit NICHT aufgerufen, dienen nur
# der Nachvollziehbarkeit/Audit der S12/S9a/S9b-Logik. qh.py (Q_H/Historien-DB-Achse)
# ist SPEZIFIZIERT, aber NICHT in dieses Skript integriert und sein Quelltext war zum
# Assemblierungszeitpunkt nicht mehr rekonstruierbar (lag im ephemeren $TMPDIR eines
# beendeten Subagenten). Der 2026-01-15-Wert unten stammt vom quellenunabhaengigen
# GIT-DISCOVERY-Zweig (v3.4-Neuerung), nicht von Q_H — Details im Assemblierungs-Log.
set -euo pipefail

# ============================== R0 Ausfuehrungsvertrag ==============================
# 1. set -euo pipefail steht in Zeile 5.
# 2. KEIN `grep -f` irgendwo. Mengensubtraktion nur via awk FILENAME==PF.
#    `NR==FNR` ist VERBOTEN (konsumiert bei leerer Musterdatei die Nutzdaten, Exit 0).
# 3. Fallbacks nur als if/then/else, nie `A | B || C > out`.
# 4. Arbeitsdateien nur in $WORK.
# 5. Frische-Assertion auf $WORK.
# 6. WERKZEUGE SIND GEPINNT (gemessen, nicht vermutet): in dieser Umgebung ist `grep`
#    eine Shell-Funktion, die auf ugrep mit `--ignore-files` umleitet. Gemessen am
#    2026-07-18: `grep -c 'set' v32.sh` -> rc=1, 0 Treffer; `/usr/bin/grep -c` -> 19.
#    Ein ignoriertes Verzeichnis macht den Positivscan STILL leer. Dasselbe gilt fuer
#    `find` (bfs-Shim, abweichende Zyklus-Semantik). Beide werden absolut aufgerufen.
export TZ=UTC
FINDBIN=/usr/bin/find
GREPBIN=/usr/bin/grep
for b in "$FINDBIN" "$GREPBIN"; do
  [ -x "$b" ] || { echo "ABORT(20): gepinntes Werkzeug fehlt: $b" >&2; exit 20; }
done
D="${1:?ABORT(1): Tag fehlt (YYYY-MM-DD)}"
# ROOTS-Aufloesung (2026-07-18): Default ist die Datei NEBEN dem Skript, nicht eine
# Umgebungsvariable. Grund ist der Ur-Defekt dieser Routine: ${LOGBOOK_DIR} war nie
# gesetzt, expandierte still zu leer, und der Lauf reparierte sich selbst aus alten
# Logzeilen. Eine Pflicht-Env-Variable, die der Scheduler nicht setzt, ist derselbe
# Fehler in neuer Gestalt (gemessen: Aufruf ohne LOGBOOK_ROOTS -> ABORT(3)).
# LOGBOOK_ROOTS bleibt als Override fuer Tests/Backfill vorrangig.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTS="${LOGBOOK_ROOTS:-$SCRIPT_DIR/roots.txt}"
[ -r "$ROOTS" ] || { echo "ABORT(3): Roots-Datei nicht lesbar: $ROOTS (weder \$LOGBOOK_ROOTS noch $SCRIPT_DIR/roots.txt)" >&2; exit 3; }
: "${LOGBOOK_GIT_ROOTS:=$SCRIPT_DIR/git-roots.txt}"; export LOGBOOK_GIT_ROOTS
FAULT="${LOGBOOK_FAULT:-}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/logbook-$D.XXXXXX")"
if [ -n "${LOGBOOK_KEEP:-}" ]; then trap 'echo "WORK=$WORK behalten" >&2' EXIT
else trap 'rm -rf "$WORK"' EXIT; fi
N_PRE=$(ls -A "$WORK" | wc -l | tr -d ' ')
if [ "$N_PRE" != "0" ]; then echo "ABORT(10): Arbeitsverzeichnis nicht frisch ($N_PRE Eintraege)" >&2; exit 10; fi
if [ "$FAULT" = "b" ]; then : > "$WORK/altbestand.txt"
  N_PRE=$(ls -A "$WORK" | wc -l | tr -d ' ')
  echo "ABORT(10): Arbeitsverzeichnis nicht frisch ($N_PRE Eintraege)" >&2; exit 10; fi

rcpt() { echo "RECEIPT $*" >&2; }

# ============================== W19 Symlink-Waechter (ABORT 19) ==============================
# Ein Verzeichnis-Symlink verbirgt einen unbegrenzten Teilbaum, OHNE dass irgendeine Zahl,
# ein Zertifikat oder eine stderr-Zeile abweicht. Gemessen: Originalskript gegen einen Baum
# mit 2 ausgelagerten Teilbaeumen -> EXIT=0, Tageszahl 90 statt 99, Zertifikat "state=verified".
#
# WARUM ABBRUCH UND NICHT `find -L` (drei ausgefuehrte Messungen, keine Behauptungen):
#  (a) ZYKLEN: /usr/bin/find -L auf einer Symlink-Schleife -> rc=0, 0 stderr-Zeilen.
#      Der Umbau auf -L fuehrt also eine NEUE stille Ausfallart ein.
#  (b) DOPPELZAEHLUNG: -L listet dieselbe Datei unter jedem Pfad erneut (3 Inodes -> 6 Pfade).
#      Bei item_key = <repo_id>::<relpfad> sind zwei Pfade zwei Schluessel.
#  (c) KANONISCHER SCHLUESSEL: bei zwei Pfaden auf eine Datei ist nicht entscheidbar,
#      welcher relpfad der Schluessel ist. Raten waere eine Zahl ohne Beleg.
#
# KLASSIFIKATION statt Zaehler — sonst waere der Waechter unbenutzbar: der Desktop-Baum
# fuehrt 67 legitime Symlinks (node_modules/.bin, tote debug/latest-Zeiger). Ein Waechter
# nach der Regel "irgendein Symlink -> Abbruch" haette ab Tag eins taeglich gefeuert.
#   DIR-Symlink     -> ABBRUCH (verbirgt einen Teilbaum)
#   Muster-Symlink  -> ABBRUCH (verbirgt eine zaehlbare Quelldatei)
#   sonstiger       -> ins Zertifikat, KEIN Abbruch (verbirgt nichts)
W19_CERT=""
w19() {
  local baum="$1"; local quelle="$2"; local muster="$3"
  local dirn=0 mustn=0 sonst=0 n=0 nL=0 frc=0 wurzel=nein
  local L="$WORK/w19-$quelle.links"; local B="$WORK/w19-$quelle.bad"
  : > "$L"; : > "$B"
  # (0) Wurzel-Probe: find OHNE -L betritt eine Symlink-Wurzel gar nicht.
  if [ -L "$baum" ]; then wurzel=ja; fi
  set +e
  "$FINDBIN" "$baum" -type l -print > "$L" 2>/dev/null; frc=$?
  set -e
  # (1)+(2) Zensus und Klassifikation in DERSELBEN Traversierung, die die Links nicht betritt.
  while IFS= read -r lk; do
    [ -n "$lk" ] || continue
    if [ -d "$lk" ]; then dirn=$((dirn+1)); printf 'DIR\t%s\n' "$lk" >> "$B"
    else
      case "$(basename "$lk")" in
        $muster) mustn=$((mustn+1)); printf 'MUSTER\t%s\n' "$lk" >> "$B" ;;
        *) sonst=$((sonst+1)) ;;
      esac
    fi
  done < "$L"
  # (3) Zweite, andersartige Achse: Mengenvergleich find gegen find -L.
  #     -L wird NUR gezaehlt, NIE zur Erhebung benutzt.
  n=$("$FINDBIN"    "$baum" -name "$muster" -type f 2>/dev/null | wc -l | tr -d ' ')
  nL=$("$FINDBIN" -L "$baum" -name "$muster" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$wurzel" = ja ] || [ "$dirn" -gt 0 ] || [ "$mustn" -gt 0 ] || [ "$n" != "$nL" ] || [ "$frc" -ne 0 ]; then
    { echo "ABORT(19): Symlink im Scanbaum von $quelle"
      echo "  baum=$baum"
      echo "  wurzel_ist_symlink=$wurzel dir_symlinks=$dirn muster_symlinks=$mustn sonstige=$sonst find_rc=$frc"
      echo "  dateien ohne -L=$n mit -L=$nL (Differenz=$((nL-n)) unsichtbare Dateien)"
      head -5 "$B" | sed 's/^/  betroffen: /'
      echo "  MESSUNG UNVOLLSTAENDIG. NICHT auf -L umgestellt: -L schweigt bei Zyklen (rc=0,"
      echo "  0 stderr) und zaehlt dieselbe Datei unter jedem Pfad erneut -> zwei item_keys."
      echo "  Aufloesung: den ausgelagerten Baum als eigenen root in roots.txt fuehren"
      echo "  oder den Symlink durch das echte Verzeichnis ersetzen."
    } >&2
    exit 19
  fi
  W19_CERT="${W19_CERT}${quelle}:symlinks=$((dirn+mustn+sonst));dir=$dirn;muster=$mustn;sonstige=$sonst;n=$n;n_L=$nL;state=symlinkfrei|"
  rcpt "W19 $quelle symlinks=$((dirn+mustn+sonst)) (dir=$dirn muster=$mustn sonstige=$sonst) n=$n n_L=$nL state=symlinkfrei"
}

# ============================== S0 Tagesfenster ==============================
PREV=$(python3 -c "import sys,datetime;print(datetime.date.fromisoformat(sys.argv[1])-datetime.timedelta(days=1))" "$D")
python3 - "$D" > "$WORK/win.txt" <<'PY'
import sys
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
d = datetime.fromisoformat(sys.argv[1]).replace(tzinfo=ZoneInfo('UTC'))
f = '%Y-%m-%dT%H:%M:%SZ'
print(d.astimezone(ZoneInfo('UTC')).strftime(f))
print((d + timedelta(days=1)).astimezone(ZoneInfo('UTC')).strftime(f))
PY
WSTART=$(sed -n 1p "$WORK/win.txt"); WEND=$(sed -n 2p "$WORK/win.txt")
if [ "$FAULT" = "d" ]; then WSTART=""; fi
RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
if [ -z "$WSTART" ] || [ -z "$WEND" ]; then
  echo "ABORT(2): Fenstergrenzen leer (WSTART='$WSTART' WEND='$WEND')" >&2; exit 2; fi
if ! [[ "$WSTART" =~ $RE ]] || ! [[ "$WEND" =~ $RE ]]; then
  echo "ABORT(2): Fensterformat ungueltig" >&2; exit 2; fi
if ! [[ "$WSTART" < "$WEND" ]]; then echo "ABORT(2): Fenster nicht aufsteigend" >&2; exit 2; fi
rcpt "S0 tz=UTC fenster=[$WSTART,$WEND)"

# ============================== S1 Preflight ==============================
# S1d Roots + Sentinels
NROOTS=0; NSYMROOT=0
: > "$WORK/roots_ok.txt"
while IFS=$'\t' read -r root sentinel; do
  [ -n "$root" ] || continue
  if [ ! -d "$root" ]; then echo "ABORT(3): root fehlt: $root" >&2; exit 3; fi
  if [ ! -r "$sentinel" ]; then echo "ABORT(3): sentinel unlesbar: $sentinel (Volume nicht gemountet?)" >&2; exit 3; fi
  # W19 auf der Roots-Achse: ABSICHTLICH KEINE Baumtraversierung, nur Wurzel-Identitaet.
  # Begruendung gemessen: die Git-Achse ist gegen Teilbaum-Blindheit STRUKTURELL IMMUN —
  # ein Verzeichnis-Symlink steht als Eintrag mit Modus 120000 im Baum und wird nicht
  # durchlaufen (`git ls-files -s spiegel` -> "120000 ... spiegel"); jede Datei erscheint
  # genau einmal unter ihrem echten Pfad. Der volle Waechter waere hier zudem untragbar
  # (ein Repo allein: 14252 Symlinks in node_modules -> taeglicher Abbruch).
  # Was auf DIESER Achse wirklich bricht, ist die ZAEHLBASIS: ist die Wurzel ueber einen
  # Symlink adressiert, haengt der relpfad am Zugangspfad und dieselbe Datei bekaeme zwei
  # item_keys — die Kollabierung von Worktrees/Klonen fiele still aus.
  rp=$(cd "$root" && pwd -P)
  if [ -L "$root" ] || [ "$rp" != "$root" ]; then
    NSYMROOT=$((NSYMROOT+1))
    { echo "ABORT(19): root ueber Symlink adressiert — Zaehlbasis nicht eindeutig"
      echo "  root=$root"; echo "  realpath=$rp"
      echo "  Der relpfad haengt am Zugangspfad; dieselbe Datei bekaeme zwei item_keys."
      echo "  Aufloesung: in roots.txt den aufgeloesten Pfad eintragen ($rp)."
      echo "  BEKANNTE REIBUNG: /var und /tmp sind auf macOS selbst Symlinks auf /private/*."
      echo "  Ein root unterhalb davon loest hier aus, obwohl die Lage harmlos ist. Bewusst"
      echo "  NICHT per Sonderfall entschaerft — eine Ausnahme fuer /private waere die erste"
      echo "  Bresche in genau der Regel, die den Waechter traegt."
    } >&2
    exit 19
  fi
  echo "$root" >> "$WORK/roots_ok.txt"; NROOTS=$((NROOTS+1))
done < "$ROOTS"
if [ "$NROOTS" -eq 0 ]; then echo "ABORT(3): roots.txt leer" >&2; exit 3; fi
CERT_S1D="roots=$NROOTS;sentinels=lesbar;symlink_wurzeln=$NSYMROOT;state=verified"
rcpt "S1d roots_geprueft=$NROOTS sentinels=lesbar symlink_wurzeln=$NSYMROOT"

# ============================== S0e QUELLEN-EPOCHEN (GEMESSEN) =========================
# DEFEKT-URSACHE (Runde 5): jede Quelle hatte genau ZWEI Zustaende - "da" oder "fehlt",
# und "fehlt" war immer ein ABORT. Eine Quelle, die am Zieltag NOCH NICHT EXISTIERTE,
# ist aber kein Messfehler, sondern eine Tatsache ueber die Welt. Fuer jeden Tag vor
# dem Beginn einer Quelle brach das Skript deshalb ab, BEVOR die Git-Achse ueberhaupt
# lief - obwohl Git die einzige Achse ist, die ueber die gesamte Zeitspanne existiert.
# Epochen werden GEMESSEN (aus der Platte), nicht angenommen.
ARC="$HOME/.claude/global-observation/archives"
DESK="$HOME/Library/Application Support/Claude/local-agent-mode-sessions"
PROJ="$HOME/.claude/projects"
EPO_CACHE="${LOGBOOK_EPOCH_CACHE:-${TMPDIR:-/tmp}/logbook-epochs.tsv}"
if [ -r "$EPO_CACHE" ]; then
  EP_SIG=$(awk -F'\t' '$1=="signals"{print $2}'    "$EPO_CACHE")
  EP_TR=$(awk  -F'\t' '$1=="transkripte"{print $2}' "$EPO_CACHE")
  EP_DESK=$(awk -F'\t' '$1=="desktop"{print $2}'   "$EPO_CACHE")
  EPO_QUELLE=cache
else
  EP_SIG=$(ls "$ARC"/signals-*.jsonl.gz 2>/dev/null \
           | sed -n 's|.*signals-\([0-9-]*\)\.jsonl\.gz|\1|p' | sort | head -1)
  EP_TR=$("$FINDBIN" "$PROJ" -name '*.jsonl' -type f -exec head -c 400 {} \; 2>/dev/null \
          | "$GREPBIN" -o '"timestamp":"[0-9-]\{10\}' | sed 's/.*"//' | sort | head -1)
  EP_DESK=$("$FINDBIN" "$DESK" -type f -name '*.json*' -print0 2>/dev/null \
            | xargs -0 stat -f '%Sm' -t '%Y-%m-%d' 2>/dev/null | sort | head -1)
  EPO_QUELLE=gemessen
  printf 'signals\t%s\ntranskripte\t%s\ndesktop\t%s\n' "$EP_SIG" "$EP_TR" "$EP_DESK" > "$EPO_CACHE"
fi
for e in "signals:$EP_SIG" "transkripte:$EP_TR" "desktop:$EP_DESK"; do
  case "${e#*:}" in
    ????-??-??) : ;;
    *) echo "ABORT(22): Quellen-Epoche fuer ${e%%:*} nicht messbar ('${e#*:}') — ohne Epoche ist 'fehlt' nicht von 'gab es noch nicht' unterscheidbar" >&2; exit 22 ;;
  esac
done
rcpt "S0e epochen signals=$EP_SIG transkripte=$EP_TR desktop=$EP_DESK ($EPO_QUELLE)"

# S1c Signal-Archive D-1 und D (NIE D+1)
# W19 auf der Archiv-Achse VOR der Erhebung.
[ -d "$ARC" ] && w19 "$ARC" "S1c_signals" "signals-*.jsonl.gz"
# VIER unterscheidbare Zustaende. "leer" != "fehlend": ein gueltiges, inhaltsleeres gz
# (50 Bytes, gzcat rc=0, 0 Zeilen) machte den einzigen Waechter gegen einen blinden
# Transkriptzweig strukturell unausloesbar. Reproduziert: EXIT=0, items 79 statt 224
# (65 % Untererfassung), status DEGRADED wie am gesunden Tag, i4_gap=0. Deshalb ist
# empty_verified SCHARFSTELLEND (siehe ABORT(17)) und nie "ok".
CERT_S1C=""; SIG_EMPTY_DAYS=0; SIG_PRE_DAYS=0
for dd in "$PREV" "$D"; do
  f="$ARC/signals-$dd.jsonl.gz"
  if [ ! -f "$f" ]; then
    # VOR der Epoche: Tatsache, kein Messfehler. NICHT als empty_verified zaehlen —
    # sonst wuerde ABORT(17) (Hook-/Rotationsausfall) auf jedem Alttag falsch feuern.
    if [[ "$dd" < "$EP_SIG" ]]; then
      : > "$WORK/sig-$dd.jsonl"; SIG_PRE_DAYS=$((SIG_PRE_DAYS+1))
      CERT_S1C="${CERT_S1C}${dd}:epoche=$EP_SIG;state=not_yet_existing|"
      rcpt "S1c signals-$dd state=not_yet_existing (Quelle beginnt $EP_SIG)"
      continue
    fi
    echo "ABORT(5): Archiv FEHLT (state=missing): signals-$dd.jsonl.gz (Tag liegt IN der Epoche ab $EP_SIG)" >&2; exit 5
  fi
  set +e
  gzcat "$f" > "$WORK/sig-$dd.jsonl" 2>"$WORK/gz-$dd.err"; GZ_RC=$?
  set -e
  NZ=$(wc -l < "$WORK/sig-$dd.jsonl" | tr -d ' ')
  if [ "$GZ_RC" -ne 0 ]; then
    echo "ABORT(5): Archiv ABGESCHNITTEN (state=truncated) $dd — gzcat_rc=$GZ_RC, $NZ Zeilen vor Abbruch; Teilausgabe wird NICHT verwendet" >&2; exit 5; fi
  if [ "$NZ" -eq 0 ]; then ST=empty_verified; SIG_EMPTY_DAYS=$((SIG_EMPTY_DAYS+1)); else ST=ok; fi
  CERT_S1C="${CERT_S1C}${dd}:rc=$GZ_RC;zeilen=$NZ;state=$ST|"
  rcpt "S1c signals-$dd rc=$GZ_RC zeilen=$NZ state=$ST"
done

# S1e Manifest D-1 (Handarbeits-Baseline)
MAN="$HOME/.claude/logbook/manifests/manifest-$PREV.tsv.gz"
if [ -r "$MAN" ]; then MAN_STATUS=ok; else MAN_STATUS=DEGRADED_missing; fi
rcpt "S1e manifest-$PREV status=$MAN_STATUS"

# S1b Desktop
if [ ! -d "$DESK" ]; then DESK_STATUS=MISSING
elif [[ "$D" < "$EP_DESK" ]]; then DESK_STATUS=not_yet_existing
else DESK_STATUS=ok; fi
rcpt "S1b desktop_status=$DESK_STATUS (Quelle beginnt $EP_DESK)"

# S1a Transkripte — Positivprobe NACH INHALT (nie mtime), mit GELESENHEITS-ZERTIFIKAT.
# "Keine Fehlermeldung" ist kein Beweis. Das Originalskript warf den grep-Exit-Status per
# `|| true` weg; gemessen ergab eine unlesbare Datei rc=2 UND 11 von 12 Treffern auf stdout
# — ein echter Teiltreffer, der als "ok" gemeldet wurde.
PROJ="$HOME/.claude/projects"
w19 "$PROJ" "S1a_transcripts" "*.jsonl"
set +e
"$FINDBIN" "$PROJ" -name '*.jsonl' -type f -print > "$WORK/all_jsonl.txt" 2>"$WORK/find_s1a.err"; FIND_RC=$?
set -e
NALL=$(wc -l < "$WORK/all_jsonl.txt" | tr -d ' ')
: > "$WORK/unreadable.txt"
while IFS= read -r jf; do [ -r "$jf" ] || printf '%s\n' "$jf" >> "$WORK/unreadable.txt"; done < "$WORK/all_jsonl.txt"
NUNREAD=$(wc -l < "$WORK/unreadable.txt" | tr -d ' ')
set +e
( cd "$PROJ" && "$GREPBIN" -rl -e "\"timestamp\":\"${D}T" -e "\"timestamp\":\"${PREV}T2" --include='*.jsonl' "$PWD" ) \
  > "$WORK/cand.txt" 2>"$WORK/grep_s1a.err"; GREP_RC=$?
set -e
NCAND=$(wc -l < "$WORK/cand.txt" | tr -d ' ')
if [ "$FIND_RC" -ne 0 ] || [ "$NUNREAD" -gt 0 ] || [ "$GREP_RC" -ge 2 ]; then
  { echo "ABORT(15): S1a-Scan UNVOLLSTAENDIG — grep_rc=$GREP_RC find_rc=$FIND_RC unlesbare_dateien=$NUNREAD von $NALL"
    head -5 "$WORK/unreadable.txt" | sed 's/^/  unlesbar: /'
    head -3 "$WORK/grep_s1a.err"  | sed 's/^/  grep: /'
  } >&2
  exit 15
fi
TR_STATE=verified
if [ "$NCAND" -eq 0 ]; then
  if [[ "$D" < "$EP_TR" ]]; then
    TR_STATE=not_yet_existing
    rcpt "S1a 0 Transkripte — state=not_yet_existing (Quelle beginnt $EP_TR)"
  else
    echo "ABORT(4): 0 Transkripte fuer $D — Messfehler, KEIN Leertag (dateien=$NALL, alle lesbar, Tag liegt IN der Epoche ab $EP_TR)" >&2; exit 4
  fi
fi
# ZWEI Pruefungen, aber NICHT unabhaengig: Zensus und grep beziehen ihre Grundgesamtheit
# aus derselben Traversierung. Ihre Unabhaengigkeit stellt erst W19 her, indem es die
# Grundgesamtheit selbst pruefbar macht.
CERT_S1A="rc=$GREP_RC;find_rc=$FIND_RC;dateien=$NALL;unlesbar=$NUNREAD;kandidaten=$NCAND;epoche=$EP_TR;state=$TR_STATE"
rcpt "S1a kandidaten=$NCAND dateien=$NALL unlesbar=$NUNREAD grep_rc=$GREP_RC"

# ============================== S2 WERKZEUGKARTE (deklariert, nicht geraten) ==============
# Klassen: W = Schreibwerkzeug (Spalte 3 = Zielparameter in Prioritaetsreihenfolge)
#          B = Bash-artig (Spalte 3 = Kommandoparameter) -> geht durch qb.py
#          R = bekannt UND schreibt nachweislich nicht ins Dateisystem
# Ein Werkzeug, das hier NICHT steht, darf nicht stumm 0 liefern: enthaelt sein Input
# einen pfadartigen Wert, landet es NAMENTLICH im Pflichtbucket unbekanntes_werkzeug_mit_pfad.
cat > "$WORK/toolmap.tsv" <<'MAPEOF'
Edit	W	file_path
Write	W	file_path
MultiEdit	W	file_path
NotebookEdit	W	notebook_path,file_path
mcp__filesystem__write_file	W	path
mcp__filesystem__edit_file	W	path
mcp__filesystem__move_file	W	destination
mcp__serena__create_text_file	W	relative_path
mcp__plugin_playwright_playwright__browser_take_screenshot	W	filename
mcp__plugin_playwright_playwright__browser_pdf_save	W	filename
mcp__chrome-devtools__take_screenshot	W	filePath
mcp__cowork__allow_cowork_file_delete	W	file_path
Bash	B	command
mcp__workspace__bash	B	command
mcp__Control_your_Mac__osascript	B	script
Read	R	file_path
Grep	R	path
Glob	R	path
mcp__filesystem__read_text_file	R	path
mcp__filesystem__read_file	R	path
mcp__filesystem__read_multiple_files	R	paths
mcp__filesystem__list_directory	R	path
mcp__filesystem__directory_tree	R	path
mcp__filesystem__create_directory	R	path
mcp__filesystem__search_files	R	path
mcp__filesystem__get_file_info	R	path
mcp__serena__find_symbol	R	relative_path
mcp__serena__find_referencing_symbols	R	relative_path
mcp__serena__get_diagnostics_for_file	R	relative_path
mcp__serena__get_symbols_overview	R	relative_path
mcp__serena__activate_project	R	project
mcp__serena__get_current_config	R	-
mcp__serena__initial_instructions	R	-
mcp__plugin_serena_serena__find_symbol	R	relative_path
mcp__plugin_serena_serena__get_diagnostics_for_file	R	relative_path
mcp__plugin_serena_serena__activate_project	R	project
mcp__plugin_serena_serena__get_current_config	R	-
mcp__plugin_serena_serena__initial_instructions	R	-
mcp__cowork__present_files	R	files
WebFetch	R	url
WebSearch	R	query
ToolSearch	R	query
mcp__workspace__web_fetch	R	url
MAPEOF
# Regex-Fallback fuer namensvariable MCP-Schreibwerkzeuge (Suffix-Konvention)
cat > "$WORK/toolmap_re.tsv" <<'MAPEOF'
write_file|edit_file|create_text_file	W	path,file_path,relative_path
MAPEOF
NMAP=$(wc -l < "$WORK/toolmap.tsv" | tr -d ' ')
rcpt "S2 werkzeugkarte_eintraege=$NMAP klassen=W/B/R"

# Alle deklarierten Parameternamen (Superset) — jq extrahiert genau diese Schluessel.
PKEYS='file_path,path,filename,notebook_path,source,destination,filePath,relative_path,local_path,paths,files,project,url,query'
KNOWN=$(cut -f1 "$WORK/toolmap.tsv" | python3 -c "import sys;print(' '+' '.join(l for l in sys.stdin.read().split(chr(10)) if l)+' ')")

# ============================== S3 Ereignisse ==============================
# iv = deklarierte Parameterwerte (Parameterkarte).  sc = pfadartige String-Blaetter
# NUR fuer Werkzeuge, die die Karte nicht kennt (Pflichtbucket-Kandidaten).
xargs -0 -n 40 jq -c --arg s "$WSTART" --arg e "$WEND" --arg pk "$PKEYS" --arg known "$KNOWN" '
  ($pk|split(",")) as $keys |
  select(.timestamp != null)
  | select((.timestamp|sub("\\.[0-9]+Z$";"Z")) >= $s and (.timestamp|sub("\\.[0-9]+Z$";"Z")) < $e)
  | select((.message.content?|type) == "array")
  | {ts:.timestamp, sid:(.sessionId//""), cwd:(.cwd//""),
     tu:[ .message.content[] | select(.type=="tool_use")
          | . as $t
          | {id:.id, n:.name,
             p:(.input.file_path // .input.path // ""),
             cmd:(.input.command // .input.script // ""),
             iv:[ $keys[] as $k | select($t.input[$k]? != null)
                  | {k:$k, v:($t.input[$k] | if type=="string" then . elif type=="array" then (map(select(type=="string"))|join("")) else "" end)} ],
             sc:( if ($known|contains(" "+$t.name+" ")) then []
                  else [ $t.input | .. | strings | select(length < 4096) ] | .[0:40] end )} ]}
  | select((.tu|length) > 0)' \
  < <(tr '\n' '\0' < "$WORK/cand.txt") > "$WORK/events.jsonl"
NEV=$(wc -l < "$WORK/events.jsonl" | tr -d ' ')
rcpt "S3 ereigniszeilen=$NEV"

# ---- Extraktor: Karte -> (id, Zielpfad) + Pflichtbucket -------------------
cat > "$WORK/extract.py" <<'PYEOF'
import sys, json, os, re
mapfile, refile, evfile, outpairs, outunknown = sys.argv[1:6]
TMAP = {}
for l in open(mapfile).read().split('\n'):
    if not l: continue
    n, cls, params = l.split('\t')
    TMAP[n] = (cls, [p for p in params.split(',') if p and p != '-'])
REMAP = []
for l in open(refile).read().split('\n'):
    if not l: continue
    rx, cls, params = l.split('\t')
    REMAP.append((re.compile(rx), cls, [p for p in params.split(',') if p]))
# pfadartig: absolut, ODER relativ mit Verzeichnistrenner UND Endung. Keine URLs.
PATHY = re.compile(r'^(/[^\x00\n]*|[^\x00\n:]*/[^\x00\n/]+\.[A-Za-z0-9]{1,8})$')
def pathy(s):
    if not s or len(s) > 512 or '\n' in s: return False
    if re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*://', s): return False
    return bool(PATHY.match(s))
def lookup(name):
    if name in TMAP: return TMAP[name]
    for rx, cls, params in REMAP:
        if rx.search(name): return (cls, params)
    return (None, [])
pairs, unknown, bashcmds = [], {}, 0
for line in open(evfile):
    try: ev = json.loads(line)
    except Exception: continue
    cwd = ev.get('cwd') or ''
    for tu in ev.get('tu', []):
        name = tu.get('n') or ''
        cls, params = lookup(name)
        if cls == 'W':
            iv = dict((d['k'], d['v']) for d in tu.get('iv', []))
            for p in params:
                v = iv.get(p) or ''
                for one in v.split('\x01'):
                    if not one: continue
                    a = one if one.startswith('/') else (os.path.join(cwd, one) if cwd else '')
                    if a: pairs.append((tu.get('id') or '', os.path.normpath(a), name))
                if v: break
        elif cls == 'B':
            bashcmds += 1
        elif cls == 'R':
            pass
        else:
            hits = set()
            for s in tu.get('sc', []):
                if pathy(s): hits.add(s)
            v = tu.get('p') or ''
            if pathy(v): hits.add(v)
            for h in sorted(hits): unknown.setdefault(name, set()).add(h)
with open(outpairs, 'w') as fh:
    for i, p, n in sorted(set(pairs)): fh.write('%s\t%s\t%s\n' % (i, p, n))
with open(outunknown, 'w') as fh:
    for n in sorted(unknown):
        for h in sorted(unknown[n]): fh.write('%s\t%s\n' % (n, h))
print(json.dumps({'bash_class_calls': bashcmds, 'unknown_tools': len(unknown),
                  'unknown_paths': sum(len(v) for v in unknown.values())}), file=sys.stderr)
PYEOF

# ---- qb.py: Bash-Schreiberkenner (VOR S6 definiert, weil der Desktop-Zweig ihn braucht)
cat > "$WORK/qb.py" <<'PYEOF'
import sys, json, os, re, shlex
# Schreib-Operatoren, systematisch geprueft (Defekt B/3):
#   cp mv install rsync ln  -> letztes Argument
#   dd of=ZIEL              -> explizites Ziel
#   touch                   -> alle Nicht-Flag-Argumente (Erzeugung = Schreibvorgang)
#   tee [-a]                -> erstes Nicht-Flag-Argument
#   sed -i                  -> letztes Argument
#   > >> >| &> 2>           -> Redirect-Ziel (deckt auch Heredoc `cat > f <<EOF`)
#   mkdir -p                -> Verzeichnisziel (evidence Bdir)
#   python open(p,'w'/'a'/'x'), pathlib write_text/write_bytes -> Regex auf dem Rohkommando
LAST_ARG = {'cp', 'mv', 'install', 'rsync', 'ln'}
ALL_ARGS = {'touch'}
OPS = {'&&', '||', '|', ';', '&', '(', ')', '{', '}'}
VAR = re.compile(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)')
ASSIGN = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
PYOPEN = re.compile(r"""open\(\s*['"]([^'"]+)['"]\s*,\s*['"][wax]b?\+?['"]""")
PYWRITE = re.compile(r"""Path\(\s*['"]([^'"]+)['"]\s*\)\s*\.\s*write_(?:text|bytes)""")

def tokenize(line):
    lx = shlex.shlex(line, posix=True, punctuation_chars=True)
    lx.whitespace_split = True
    try: return list(lx)
    except Exception: return None

files, dirs, n, unparsed = set(), set(), 0, 0
byop = {}
for line in sys.stdin:
    try: ev = json.loads(line)
    except Exception: continue
    cwd = ev.get('cwd') or ''
    for tu in ev.get('tu', []):
        cmd = tu.get('cmd') or ''
        if not cmd: continue
        n += 1
        all_toks = tokenize(cmd.replace('\n', ' ; '))
        if all_toks is None: unparsed += 1; continue
        stmts, cur = [], []
        for tok in all_toks:
            if tok in OPS:
                if cur: stmts.append(cur)
                cur = []
            else: cur.append(tok)
        if cur: stmts.append(cur)
        env = {}
        for t in all_toks:
            m = ASSIGN.match(t)
            if m and '`' not in m.group(2): env[m.group(1)] = m.group(2)
        for _ in range(2):
            for k, v in list(env.items()):
                if '$' in v:
                    env[k] = VAR.sub(lambda mm: env.get(mm.group(1) or mm.group(2), '\x00'), v)
        env = dict((k, v) for k, v in env.items() if '\x00' not in v)

        def expand(s):
            return VAR.sub(lambda mm: env.get(mm.group(1) or mm.group(2), '\x00'), s)
        def absol(s):
            if not s or s.startswith('~'): return None
            return s if s.startswith('/') else (os.path.join(cwd, s) if cwd else None)
        def emit(t, op):
            t = expand(t)
            if not t or t.startswith('/dev/') or '*' in t or '?' in t:
                if '*' in t or '?' in t:
                    head = t.split('*')[0].split('?')[0]
                    head = head[:head.rfind('/')] if '/' in head else ''
                    a = absol(head)
                    if a and os.path.isdir(a): dirs.add(os.path.realpath(a))
                return
            if '\x00' in t:
                head = t.split('\x00', 1)[0].rstrip('/')
                if not head: return
                a = absol(head)
                if a and os.path.isdir(a): dirs.add(os.path.realpath(a))
                return
            a = absol(t)
            if not a: return
            a = os.path.normpath(a)
            if os.path.isdir(a): dirs.add(os.path.realpath(a)); return
            if os.path.exists(a):
                files.add(a); byop[a] = byop.get(a) or op
        for m in PYOPEN.finditer(cmd): emit(m.group(1), 'python_open_w')
        for m in PYWRITE.finditer(cmd): emit(m.group(1), 'pathlib_write')
        for toks in stmts:
            for i, t in enumerate(toks):
                # REIHENFOLGE IST NORMATIV: erst die ALLEINSTEHENDE Operatorform pruefen.
                # Umgekehrt frisst `>>?(.+)` das Token '>>' selbst (zweites '>' als "Pfad")
                # und der Anhaenge-Redirect wird stumm verschluckt — im Test real passiert.
                if re.match(r'^[0-9]*&?>{1,2}\|?$', t):
                    if i + 1 < len(toks): emit(toks[i + 1], 'redirect')
                else:
                    m = re.match(r'^[0-9]*&?>{1,2}\|?(.+)$', t)
                    if m: emit(m.group(1), 'redirect')
            for i, t in enumerate(toks):
                base = os.path.basename(t)
                if base == 'tee':
                    for u in toks[i + 1:]:
                        if u.startswith('-'): continue
                        emit(u, 'tee'); break
                if base == 'sed' and i + 1 < len(toks) and toks[i + 1].startswith('-i'):
                    if len(toks) > i + 2: emit(toks[-1], 'sed_i')
                if base == 'dd':
                    for u in toks[i + 1:]:
                        if u.startswith('of='): emit(u[3:], 'dd')
                if base == 'mkdir':
                    for u in toks[i + 1:]:
                        if u.startswith('-'): continue
                        a = absol(expand(u))
                        if a and os.path.isdir(a): dirs.add(os.path.realpath(a))
                if base in ALL_ARGS:
                    for u in toks[i + 1:]:
                        if u.startswith('-'): continue
                        emit(u, base)
                    break
                if base in LAST_ARG:
                    args = [u for u in toks[i + 1:] if not u.startswith('-')]
                    if len(args) >= 2: emit(args[-1], base)
                    break
print(json.dumps({'ncmds': n, 'unparsed': unparsed,
                  'ops': sorted(set(byop.values()))}), file=sys.stderr)
for f in sorted(files): print('F\t' + f + '\t' + (byop.get(f) or '?'))
for d in sorted(dirs): print('DIR\t' + d)
PYEOF

# ============================== S4 Fehlschlaege abziehen ==============================
# Fehler-IDs werden ueber ALLE Zeilen der Kandidatendateien gesammelt (nicht fenstergefiltert):
# ein tool_result kann nach Fensterende eintreffen. Sichere Richtung = mehr Subtraktion.
xargs -0 -n 40 jq -r 'select((.message.content?|type)=="array") | .message.content[]
   | select(.type=="tool_result" and .is_error==true) | .tool_use_id' \
   < <(tr '\n' '\0' < "$WORK/cand.txt") | sort -u > "$WORK/failed_ids.txt"
NFAIL=$(wc -l < "$WORK/failed_ids.txt" | tr -d ' ')

python3 "$WORK/extract.py" "$WORK/toolmap.tsv" "$WORK/toolmap_re.tsv" "$WORK/events.jsonl" \
        "$WORK/pairs3.tsv" "$WORK/unknown_qt.tsv" 2> "$WORK/extract_qt.meta"
cut -f1,2 "$WORK/pairs3.tsv" | sort -u > "$WORK/pairs.tsv"
NPAIRS=$(wc -l < "$WORK/pairs.tsv" | tr -d ' ')
rcpt "S3b karte_treffer=$NPAIRS unbekannt_werkzeuge=$(jq -r '.unknown_tools' "$WORK/extract_qt.meta") unbekannt_pfade=$(jq -r '.unknown_paths' "$WORK/extract_qt.meta")"

if [ "$FAULT" = "c" ]; then : > "$WORK/failed_ids.txt"; NFAIL=0; fi
awk -F'\t' -v PF="$WORK/failed_ids.txt" '
  FILENAME==PF { bad[$1]=1; next } !($1 in bad)' "$WORK/failed_ids.txt" "$WORK/pairs.tsv" \
  > "$WORK/pairs_ok.tsv"
NOK=$(wc -l < "$WORK/pairs_ok.tsv" | tr -d ' ')
# R4 Filter-Selbstverteidigung: leere Musterdatei darf NIE reduzieren
if [ "$NFAIL" -eq 0 ] && [ "$NPAIRS" -gt 0 ] && [ "$NOK" -ne "$NPAIRS" ]; then
  echo "ABORT(12): Fehlschlag-Filter reduzierte $NPAIRS -> $NOK bei 0 Mustern (Werkzeugdefekt)" >&2; exit 12; fi
cut -f2 "$WORK/pairs_ok.tsv" | sort -u > "$WORK/qt_raw.txt"
rcpt "S4 paare=$NPAIRS fehler_ids=$NFAIL verbleibend=$NOK rohpfade=$(wc -l < "$WORK/qt_raw.txt" | tr -d ' ')"

# ============================== S6 Desktop-Rohpfade ==============================
: > "$WORK/qd_raw.txt"
NAUDIT=0; DESK_FIND_RC=0; DESK_JQ_RC=0; DESK_UNREAD=0
if [ "$DESK_STATUS" = "ok" ]; then
  w19 "$DESK" "S1b_desktop" "audit.jsonl"
  set +e
  "$FINDBIN" "$DESK" -name audit.jsonl -print0 > "$WORK/audits.z" 2>"$WORK/desk_find.err"; DESK_FIND_RC=$?
  set -e
  NAUDIT=$(tr -dc '\0' < "$WORK/audits.z" | wc -c | tr -d ' ')
  # Lesbarkeits-Zensus wie S1a — ein Teilausfall darf nicht als "ok:N" durchgehen.
  while IFS= read -r -d '' af; do [ -r "$af" ] || DESK_UNREAD=$((DESK_UNREAD+1)); done < "$WORK/audits.z"
  if [ "$DESK_FIND_RC" -ne 0 ] || [ "$DESK_UNREAD" -gt 0 ]; then
    echo "ABORT(16): S1b/S6-Desktopscan UNVOLLSTAENDIG — find_rc=$DESK_FIND_RC unlesbar=$DESK_UNREAD von $NAUDIT" >&2; exit 16; fi
  if [ "$NAUDIT" -gt 0 ]; then
    # Desktop-Ereignisse in DIESELBE Form bringen wie S3 (kein cwd im audit.jsonl ->
    # relative Ziele bleiben unaufloesbar und werden als solche gemeldet, nicht geraten).
    set +e
    xargs -0 -n 40 jq -c --arg s "$WSTART" --arg e "$WEND" --arg pk "$PKEYS" --arg known "$KNOWN" '
      ($pk|split(",")) as $keys |
      select(.timestamp != null)
      | select((.timestamp|sub("\\.[0-9]+Z$";"Z")) >= $s and (.timestamp|sub("\\.[0-9]+Z$";"Z")) < $e)
      | select((.message.content?|type)=="array")
      | {ts:.timestamp, sid:(.session_id//""), cwd:(.cwd//""),
         tu:[ .message.content[] | select(.type=="tool_use")
              | . as $t
              | {id:(.id//""), n:.name,
                 p:(.input.file_path // .input.path // ""),
                 cmd:(.input.command // .input.script // ""),
                 iv:[ $keys[] as $k | select($t.input[$k]? != null)
                      | {k:$k, v:($t.input[$k] | if type=="string" then . else "" end)} ],
                 sc:( if ($known|contains(" "+$t.name+" ")) then []
                      else [ $t.input | .. | strings | select(length < 4096) ] | .[0:40] end )} ]}
      | select((.tu|length) > 0)' \
      < "$WORK/audits.z" 2>"$WORK/desk_jq.err" > "$WORK/devents.jsonl"; DESK_JQ_RC=$?
    set -e
    if [ "$DESK_JQ_RC" -ne 0 ]; then
      { echo "ABORT(16): S6-Desktop-jq scheiterte (rc=$DESK_JQ_RC) — Teilausfall statt stiller Untererfassung"
        head -3 "$WORK/desk_jq.err" | sed 's/^/  jq: /'; } >&2
      exit 16
    fi
    python3 "$WORK/extract.py" "$WORK/toolmap.tsv" "$WORK/toolmap_re.tsv" "$WORK/devents.jsonl" \
            "$WORK/dpairs.tsv" "$WORK/unknown_qd.tsv" 2> "$WORK/extract_qd.meta"
    cut -f2 "$WORK/dpairs.tsv" | sort -u > "$WORK/qd_raw.txt"
    # Q_B FUER DEN DESKTOP-ZWEIG — derselbe Erkenner wie im CLI-Zweig (Defekt B/2).
    python3 "$WORK/qb.py" < "$WORK/devents.jsonl" > "$WORK/qbd_raw.tsv" 2> "$WORK/qbd.meta"
  fi
fi
[ -f "$WORK/qbd_raw.tsv" ] || : > "$WORK/qbd_raw.tsv"
[ -f "$WORK/qbd.meta" ] || echo '{"ncmds":0,"unparsed":0}' > "$WORK/qbd.meta"
[ -f "$WORK/unknown_qd.tsv" ] || : > "$WORK/unknown_qd.tsv"
CERT_S1B="status=$DESK_STATUS;find_rc=$DESK_FIND_RC;jq_rc=$DESK_JQ_RC;audits=$NAUDIT;unlesbar=$DESK_UNREAD;state=$( [ "$DESK_STATUS" = ok ] && echo verified || echo degraded_missing )"
rcpt "S6 desktop_status=$DESK_STATUS audit_dateien=$NAUDIT rohpfade=$(wc -l < "$WORK/qd_raw.txt" | tr -d ' ') desktop_bash_calls=$(jq -r '.ncmds' "$WORK/qbd.meta") desktop_bash_ziele=$(awk -F'\t' '$1=="F"' "$WORK/qbd_raw.tsv" | wc -l | tr -d ' ')"

# ============================== canon.py ==============================
cat > "$WORK/canon.py" <<'PYEOF'
import sys, os, re, subprocess, unicodedata
TMPDIR = os.environ.get('TMPDIR', '').rstrip('/')
A1 = [re.compile(r'^(/private)?/tmp/'), re.compile(r'^(/private)?/var/folders/')]
A2 = re.compile(r'/\.claude/projects/.*/(memory|workflows)/')
A3 = re.compile(r'/\.claude/(logbook|shell-snapshots|tasks|sessions)/')
A5 = re.compile(r'(^|/)_tmp-')
A6 = re.compile(r'/local-agent-mode-sessions/.*/local_[0-9a-f-]+/')
WT = re.compile(r'^(?P<pre>.*)/\.claude/worktrees/(?P<name>[^/]+)/(?P<rest>.*)$')
ALLOW_B1 = re.compile(r'^\.serena/[^/]+\.(yml|yaml)$')

def s9a(p):
    for r in A1:
        if r.search(p): return 'a1_tmp'
    if TMPDIR and p.startswith(TMPDIR + '/'): return 'a1_tmp'
    if A2.search(p): return 'a2_claude_selfgen'
    if A3.search(p): return 'a3_claude_runtime'
    if '/Library/Mobile Documents/' in p: return 'a4_icloud'
    if A5.search(p): return 'a5_tmp_segment'
    if A6.search(p): return 'a6_runid_sandbox'
    return None

_g = {}
def git(d, *args):
    k = (d,) + args
    if k in _g: return _g[k]
    try:
        r = subprocess.run(['git', '-C', d] + list(args), capture_output=True, text=True, timeout=90)
        out = r.stdout.strip() if r.returncode == 0 else None
    except Exception:
        out = None
    _g[k] = out
    return out

def common_dir(d):
    return git(d, 'rev-parse', '--path-format=absolute', '--git-common-dir')

def existing_dir(p, stop=None):
    d = os.path.dirname(p)
    while d and d != '/':
        if stop and not d.startswith(stop): return None
        if os.path.isdir(d): return d
        d = os.path.dirname(d)
    return None

_rid = {}
def repo_id(wc):
    if wc in _rid: return _rid[wc]
    out = git(wc, 'rev-list', '--max-parents=0', '--all')
    v = sorted(out.split())[0] if out else 'UNRESOLVED'
    _rid[wc] = v
    return v

_ci = {}
def ignored(wc, rel):
    k = (wc, rel)
    if k in _ci: return _ci[k]
    try:
        r = subprocess.run(['git', '-C', wc, 'check-ignore', '-q', rel],
                           capture_output=True, text=True, timeout=60)
        v = (r.returncode == 0)
    except Exception:
        v = False
    _ci[k] = v
    return v

def resolve(p):
    """-> (workcopy, relpath, flag, worktree)

    workcopy ist ein ATTRIBUT, kein Schluesselbestandteil. Der Schluessel entsteht
    erst oben aus <repo_id>::<relpfad>. (Der frueherere Name 'workcopy_id' trug noch
    die alte Schluessel-Semantik und ist deshalb entfernt.)
    """
    m = WT.match(p)
    wtname = m.group('name') if m else '-'
    if m and not os.path.isdir(m.group('pre') + '/.claude/worktrees/' + m.group('name')):
        cand = m.group('pre')
        cd = common_dir(cand) if os.path.isdir(cand) else None
        if cd:
            return os.path.dirname(cd), m.group('rest'), 'wt_pruned_structural', wtname
        return 'fs', p, 'UNRESOLVED', wtname
    d = existing_dir(p)
    if d:
        cd = common_dir(d)
        top = git(d, 'rev-parse', '--show-toplevel')
        if cd and top:
            rel = os.path.relpath(p, top)
            return os.path.dirname(cd), rel, 'ok', wtname
    return 'fs', p, 'UNRESOLVED', wtname

# ZAEHLBASIS: REPO-IDENTITAET (Nutzerentscheidung 1, verbindlich).
# item_key := <repo_id>::<relpfad> fuer Git-Verwaltetes, fs::<pfad> sonst.
# Die Arbeitskopie ist ATTRIBUT (Spalte 9), NIE Schluessel. Damit kollabieren
# Worktrees UND Klone auf EINEN Schluessel; der A<->B-Sync bleibt ueber das
# Attribut sichtbar (workcopies[]), ohne dass eine Datei zweimal zaehlt.
# Ausgabespalten: dec key flag cat repo_id worktree src raw workcopy
for line in sys.stdin:
    line = line.rstrip('\n')
    if not line: continue
    src, raw = line.split('\t', 1)
    raw = unicodedata.normalize('NFC', raw)
    cat = s9a(raw)
    if cat:
        print('\t'.join(['drop', '-', 'S9a', cat, '-', '-', src, raw, '-'])); continue
    p = re.sub(r'^/private/', '/', raw)
    wc, rel, flag, wt = resolve(p)
    if wc == 'fs':
        key = 'fs::' + rel; rid = 'NO_REPO'; wcout = '-'
    else:
        rid = repo_id(wc)
        wcout = wc
        if rel.startswith('.git/'):
            print('\t'.join(['drop', '-', 'S9b', 'b2_git_internal', rid, wt, src, raw, wcout])); continue
        if ignored(wc, rel):
            if ALLOW_B1.match(rel):
                print('\t'.join(['rescued', rid + '::' + rel, flag, 'b1_allowlist', rid, wt, src, raw, wcout]))
                continue
            print('\t'.join(['drop', '-', 'S9b', 'b1_gitignored:' + rel, rid, wt, src, raw, wcout])); continue
        key = rid + '::' + rel
    print('\t'.join(['keep', key, flag, '-', rid, wt, src, raw, wcout]))
PYEOF

# ---- Pass 1: Q_T + Q_D (+ CANARY fuer S8) --------------------------------
CANARY="/Volumes/__logbook_canary__/CANARY-$D.md"
{ awk '{print "T\t" $0}' "$WORK/qt_raw.txt"
  awk '{print "D\t" $0}' "$WORK/qd_raw.txt"
  if [ "$FAULT" != "f" ]; then echo -e "C\t$CANARY"; fi
} > "$WORK/pass1.in"
python3 "$WORK/canon.py" < "$WORK/pass1.in" > "$WORK/pass1.tsv"
if [ ! -f "$WORK/pass1.tsv" ]; then echo "ABORT(9): Senke pass1.tsv nicht geschrieben" >&2; exit 9; fi
if [ ! -s "$WORK/pass1.tsv" ]; then echo "ABORT(9): pass1.tsv leer trotz Eingabe" >&2; exit 9; fi

awk -F'\t' '($1=="keep"||$1=="rescued") && $7=="T" {print $2}' "$WORK/pass1.tsv" | sort -u > "$WORK/qt.txt"
awk -F'\t' '($1=="keep"||$1=="rescued") && $7=="D" {print $2}' "$WORK/pass1.tsv" | sort -u > "$WORK/qd.txt"
awk -F'\t' '($1=="keep"||$1=="rescued") && $7=="C" {print $2}' "$WORK/pass1.tsv" | sort -u > "$WORK/canary.txt"
NQT=$(wc -l < "$WORK/qt.txt" | tr -d ' '); NQD=$(wc -l < "$WORK/qd.txt" | tr -d ' ')
rcpt "S5 Q_T=$NQT Q_D=$NQD"

# ============================== S7d Q_B (Bash-Schreibziele) ==============================
python3 "$WORK/qb.py" < "$WORK/events.jsonl" > "$WORK/qb_raw.tsv" 2> "$WORK/qb.meta"
NBASH=$(jq -r '.ncmds' "$WORK/qb.meta"); NBUNPARSED=$(jq -r '.unparsed' "$WORK/qb.meta")
NBASHD=$(jq -r '.ncmds' "$WORK/qbd.meta")
# CLI- und Desktop-Zweig laufen durch DENSELBEN Erkenner und werden hier vereinigt.
cat "$WORK/qb_raw.tsv" "$WORK/qbd_raw.tsv" > "$WORK/qb_all.tsv"
awk -F'\t' '$1=="F"{print "B\t" $2}' "$WORK/qb_all.tsv" | sort -u > "$WORK/qb_files.in"
awk -F'\t' '$1=="DIR"{print $2}' "$WORK/qb_all.tsv" | sort -u > "$WORK/qb_dirs.txt"
awk -F'\t' '$1=="F"{print $3}' "$WORK/qb_all.tsv" | sort | uniq -c | sort -rn | awk '{printf "%s:%s ", $2, $1}' > "$WORK/qb_ops.txt"
rcpt "S7d bash_calls=$NBASH(+desktop $NBASHD) unparsebar=$NBUNPARSED qb_dateiziele=$(wc -l < "$WORK/qb_files.in" | tr -d ' ') qb_verzeichnisziele=$(wc -l < "$WORK/qb_dirs.txt" | tr -d ' ') ops=[$(cat "$WORK/qb_ops.txt")]"

# ============================== S7c Q_G (Git-Inhaltsbeweis) ==============================
# Repo-Abdeckung = roots.txt  UNION  aus Q_T/Q_D abgeleitete Arbeitskopien.
# DEFEKT-URSACHE 2 (Runde 5): die Repo-Menge war roots.txt UNION der aus Q_T/Q_D
# abgeleiteten Arbeitskopien. Fuer jeden Tag VOR der Transkript-Epoche traegt der
# zweite Summand nichts bei — die Git-Achse sah dann nur die 3 roots und war fuer
# jedes andere Repo strukturell blind. Gemessen: am 2026-01-15 liegen alle Commits
# in einem Repo, das in roots.txt nicht vorkommt. Deshalb dritte, quellenunabhaengige
# Achse: Dateisystem-Discovery ueber LOGBOOK_GIT_ROOTS (Baumwurzeln, nicht Repos).
: > "$WORK/repos_disc.txt"
GITROOTS="${LOGBOOK_GIT_ROOTS:-}"
NDISC=0
if [ -n "$GITROOTS" ] && [ -r "$GITROOTS" ]; then
  while IFS= read -r tr0; do
    [ -n "$tr0" ] || continue
    case "$tr0" in \#*) continue ;; esac
    if [ ! -d "$tr0" ]; then
      echo "ABORT(23): Git-Discovery-Wurzel fehlt: $tr0 (Volume nicht gemountet?) — eine stumm uebersprungene Wurzel ist eine stille Untererfassung" >&2; exit 23; fi
    "$FINDBIN" "$tr0" -maxdepth "${LOGBOOK_GIT_DEPTH:-5}" -type d -name .git -not -path '*/node_modules/*' 2>/dev/null \
      | while IFS= read -r gd; do dirname "$gd"; done
  done < "$GITROOTS" | sort -u > "$WORK/repos_disc.txt"
  NDISC=$(wc -l < "$WORK/repos_disc.txt" | tr -d ' ')
fi
{ cat "$WORK/roots_ok.txt" "$WORK/repos_disc.txt"
  # Arbeitskopie kommt jetzt aus Spalte 9 (Attribut), NICHT mehr aus dem Schluessel.
  awk -F'\t' '($1=="keep"||$1=="rescued") && $9!="-" && $9!="" {print $9}' "$WORK/pass1.tsv"
} | sort -u > "$WORK/repos_cand.txt"
rcpt "S7b git_discovery wurzeln=$( [ -r "${GITROOTS:-/nonexistent}" ] && wc -l < "$GITROOTS" | tr -d ' ' || echo 0) repos_gefunden=$NDISC"
# ABORT(24): ein Tag VOR der Transkript-Epoche hat per Konstruktion keine T/D/Signals-Achse
# (siehe S0e). Bleibt dann auch die Git-Discovery leer (LOGBOOK_GIT_ROOTS nicht gesetzt oder
# 0 Repos gefunden), ist KEINE Achse mehr tragfaehig — ein "items=0" waere nicht von "nicht
# gemessen" unterscheidbar. Das ist die stille Nullzaehlung, die der Wächter verhindern soll.
if [ "$TR_STATE" != "verified" ] && [ "$NDISC" -eq 0 ]; then
  echo "ABORT(24): Tag liegt vor der Transkript-Epoche (ab $EP_TR) UND keine Discovery-Repos gefunden (LOGBOOK_GIT_ROOTS nicht gesetzt oder leer) — keine tragfaehige Achse fuer diesen Tag besetzt" >&2
  exit 24
fi
# WICHTIG (Konflikt-Aufloesung A): ein Commit gehoert zur HISTORIE, nicht zur Arbeitskopie.
# Q_G wird deshalb GENAU EINMAL PRO repo_id gescannt — sonst zaehlt ein Klon (A und B)
# jeden Commit doppelt.
: > "$WORK/repos_all.tsv"
while read -r r; do
  [ -d "$r" ] || continue
  cd0=$(git -C "$r" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  [ -n "$cd0" ] || continue
  wc0=$(dirname "$cd0")
  rid=$(git -C "$wc0" rev-list --max-parents=0 --all 2>/dev/null | sort | head -1)
  [ -n "$rid" ] || rid=UNRESOLVED
  printf '%s\t%s\n' "$rid" "$wc0" >> "$WORK/repos_all.tsv"
done < "$WORK/repos_cand.txt"
sort -u "$WORK/repos_all.tsv" | awk -F'\t' '!seen[$1]++' > "$WORK/repos_rep.tsv"
cut -f2 "$WORK/repos_rep.tsv" > "$WORK/repos.txt"
NREPO_WC=$(sort -u "$WORK/repos_all.tsv" | wc -l | tr -d ' ')
NREPO=$(wc -l < "$WORK/repos.txt" | tr -d ' ')

cat > "$WORK/qg.py" <<'PYEOF'
import sys, subprocess, os
day = sys.argv[1]
start = day + 'T00:00:00'
def g(repo, *a):
    r = subprocess.run(['git', '-C', repo] + list(a), capture_output=True, text=True, timeout=300)
    return r.stdout if r.returncode == 0 else ''
nmerge = 0
for repo in [l.strip() for l in sys.stdin if l.strip()]:
    # KEIN --since/--until: beide filtern auf die COMMITTER-Datum-Achse, die ein
    # spaeterer Rebase auf den Rebase-Tag zuruecksetzt, waehrend das Autor-Datum
    # stehen bleibt. Fuer den Backfill ist genau das der Normalfall. Gefiltert wird
    # deshalb in Python auf (Autor-Datum ODER Committer-Datum) == Zieltag.
    # Diese Achse liest AUSSCHLIESSLICH die Commit-Historie — nie das reflog. Sie ist
    # damit von gc.reflogExpire (90 Tage) unabhaengig und traegt alte Tage.
    log = g(repo, 'log', '--all',
            '--date=format-local:%Y-%m-%dT%H:%M:%S', '--pretty=%H|%ad|%cd|%P')
    for line in log.splitlines():
        if not line.strip(): continue
        sha, ad, cd, parents = line.split('|', 3)
        if not (ad.startswith(day) or cd.startswith(day)):
            continue
        if len(parents.split()) > 1:
            nmerge += 1
            print('\t'.join(['MERGE', repo, sha, '-', '-']))
            continue
        ns = g(repo, 'diff-tree', '--no-commit-id', '--name-status', '-r', '--no-renames', sha)
        for l2 in ns.splitlines():
            if not l2.strip(): continue
            parts = l2.split('\t')
            if len(parts) < 2: continue
            st, path = parts[0], parts[-1]
            if st[0] not in ('M', 'A'): continue
            prev = g(repo, 'log', '-1', '--format=%ad', '--date=format-local:%Y-%m-%dT%H:%M:%S',
                     '--no-renames', sha + '^', '--', path).strip()
            cls = 'STRICT' if (prev and prev >= start) else 'AMBIG'
            print('\t'.join([cls, repo, sha, path, prev or 'NO_PRIOR_COMMIT']))
print('merges=%d' % nmerge, file=sys.stderr)
PYEOF
python3 "$WORK/qg.py" "$D" < "$WORK/repos.txt" > "$WORK/qg_raw.tsv" 2> "$WORK/qg.meta"
NMERGE=$(sed -n 's/^merges=//p' "$WORK/qg.meta")
# STRICT gewinnt: eine Datei, die in EINEM Commit des Tages strict ist, ist strict —
# auch wenn ein anderer Commit desselben Tages sie ambig macht.
awk -F'\t' '$1=="STRICT"{print $2 "/" $4}' "$WORK/qg_raw.tsv" | sort -u > "$WORK/g_strict_paths.txt"
awk -F'\t' '$1=="AMBIG"{print $2 "/" $4}'  "$WORK/qg_raw.tsv" | sort -u > "$WORK/g_ambig_all.txt"
awk -v PF="$WORK/g_strict_paths.txt" 'FILENAME==PF{s[$0]=1;next} !($0 in s)' \
  "$WORK/g_strict_paths.txt" "$WORK/g_ambig_all.txt" > "$WORK/g_ambig_paths.txt"
awk '{print "G\t" $0}' "$WORK/g_strict_paths.txt" > "$WORK/qg_strict.in"
awk '{print "g\t" $0}' "$WORK/g_ambig_paths.txt"  > "$WORK/qg_ambig.in"
rcpt "S7c repo_ids=$NREPO arbeitskopien=$NREPO_WC merge_commits=$NMERGE g_strict=$(wc -l < "$WORK/qg_strict.in" | tr -d ' ') g_ambig=$(wc -l < "$WORK/qg_ambig.in" | tr -d ' ')"

# ---- Pass 2: Q_B + Q_G (strict + ambig) ---------------------------------
cat "$WORK/qb_files.in" "$WORK/qg_strict.in" "$WORK/qg_ambig.in" > "$WORK/pass2.in"
if [ -s "$WORK/pass2.in" ]; then
  python3 "$WORK/canon.py" < "$WORK/pass2.in" > "$WORK/pass2.tsv"
else : > "$WORK/pass2.tsv"; fi
# Q_B: schwaechste Beweisklasse -> striktestes Aufnahmekriterium.
# Nur Ziele, die in eine bekannte Arbeitskopie aufloesen (flag != UNRESOLVED), zaehlen.
awk -F'\t' '($1=="keep"||$1=="rescued") && $7=="B" && $3!="UNRESOLVED" {print $2}' "$WORK/pass2.tsv" | sort -u > "$WORK/qb.txt"
awk -F'\t' '($1=="keep"||$1=="rescued") && $7=="B" && $3=="UNRESOLVED" {print $2}' "$WORK/pass2.tsv" | sort -u > "$WORK/qb_unresolved.txt"

# ============================== S12 Q_V (VCS-Operationen) ==============================
# EIGENE KATEGORIE, GETRENNT von items. Eine VCS-Operation materialisiert Dateien in eine
# Arbeitskopie; das ist KEIN Item (sonst waere die Zahl nicht mehr invariant gegen
# Arbeitsorganisation: derselbe Code direkt auf development geschrieben vs. ueber einen
# Feature-Branch gemergt ergaebe verschiedene Tageszahlen). Verschwinden lassen ist aber
# ebenso falsch — ein Merge mit Konflikten ist echte Arbeit. Deshalb eigene Metrik.
# DREI UNABHAENGIGE ACHSEN (Antwort auf den Common-Mode-Befund):
#   V1 reflog       — loest `git -C $VAR merge` auf (Ziel steht nicht im Kommandostring)
#   V2 transkript   — sieht `merge --no-commit` (keine HEAD-Bewegung, kein reflog-Eintrag)
#   V3 merge-commit — `git diff <sha>^1 <sha>`, NIE `diff-tree` (das liefert bei Merges 0)
# Keine Einzelachse erfasst den Tag vollstaendig; das ist gemessen, nicht angenommen.
cat > "$WORK/qv2.py" <<'QVEOF'
#!/usr/bin/env python3
"""Q_V — VCS-Operationen als eigene Kategorie (v3.3).

Drei UNABHAENGIGE Achsen, Union auf op_key:
  V1 reflog   je Arbeitskopie  -> HEAD-bewegende Ops (auch ausserhalb Claude)
  V2 transkript (Bash)         -> aufgerufene Kommandos, auch ohne HEAD-Bewegung
  V3 merge-commits (Q_G)       -> Merges, die einen Merge-Commit erzeugt haben

Ausgabe: JSON  {vcs_operationen:[...], vcs_materialisiert:[repo_id::relpfad], zaehler:{}}
Schreibt NUR nach stdout. Keine Mutation.
"""
import json, os, re, shlex, subprocess, sys, datetime as dt
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

DAY = sys.argv[1]
ROOTS = sys.argv[2]
TZ = ZoneInfo("UTC")
d = datetime.strptime(DAY, "%Y-%m-%d")
LO = datetime(d.year, d.month, d.day, tzinfo=TZ)
HI = LO + dt.timedelta(days=1)
assert LO < HI
LOU, HIU = LO.astimezone(timezone.utc), HI.astimezone(timezone.utc)

def git(wc, *a):
    r = subprocess.run(["git","-C",wc,*a], capture_output=True, text=True)
    return r.returncode, r.stdout.strip()

# ---------- Arbeitskopien + repo_id ----------
workcopies = []
for line in open(ROOTS):
    root = line.split("\t")[0].strip()
    if not os.path.isdir(root): continue
    rc, out = git(root, "worktree", "list", "--porcelain")
    for l in out.splitlines():
        if l.startswith("worktree "):
            wc = l.split(" ",1)[1]
            if os.path.isdir(wc): workcopies.append(wc)
workcopies = sorted(set(workcopies))
REPO = {}
for wc in workcopies:
    rc, out = git(wc, "rev-list", "--max-parents=0", "HEAD")
    REPO[wc] = out.splitlines()[-1] if out else "UNKNOWN"

ops = {}          # op_key -> dict
materialisiert = set()

def add(op_key, **kw):
    o = ops.setdefault(op_key, {"achsen": [], "dateien": None, "dateien_quelle": None})
    for k, v in kw.items():
        if k == "achse": o["achsen"].append(v)
        elif v is not None: o[k] = v
    return o

def diff_files(wc, a, b):
    rc, out = git(wc, "diff", "--name-only", "--no-renames", a, b)
    return [x for x in out.splitlines() if x] if rc == 0 else None

# ---------- V1: reflog ----------
# Nur ARBEITSKOPIE-schreibende Selektoren; "commit:" bewegt HEAD, schreibt aber
# die Arbeitskopie NICHT -> ausgeschlossen.
RX = re.compile(r"^(?P<new>[0-9a-f]+) HEAD@\{(?P<ts>[^}]+)\}: (?P<sel>.*)$")
WRITE_SEL = re.compile(r"^(merge |pull|rebase|checkout: moving|reset: moving|"
                       r"cherry-pick|revert|clone:|am |commit \(merge\)|"
                       r"commit \(cherry-pick\)|commit \(revert\))")
for wc in workcopies:
    rc, out = git(wc, "reflog", "--date=format-local:%Y-%m-%dT%H:%M:%S",
                  "--format=%H HEAD@{%gd_PLACEHOLDER}", )
    rc, out = git(wc, "reflog", "--date=format-local:%Y-%m-%dT%H:%M:%S")
    if rc != 0: continue
    prev_by_line = {}
    lines = out.splitlines()
    for idx, l in enumerate(lines):
        m = RX.match(l)
        if not m: continue
        ts = m.group("ts")
        if not ts.startswith(DAY): continue
        sel = m.group("sel")
        if not WRITE_SEL.match(sel): continue
        new = m.group("new")
        _rc,_full = git(wc,"rev-parse",new)
        if _rc==0 and _full: new=_full
        # Vorgaenger = naechste reflog-Zeile (aeltere)
        old = None
        for j in range(idx+1, len(lines)):
            mm = RX.match(lines[j])
            if mm: old = mm.group("new"); break
        files = diff_files(wc, old, new) if old else None
        key = f"{REPO[wc]}|{new}" if sel.startswith("commit (merge)") or sel.startswith("merge ") else f"{REPO[wc]}|{wc}|{ts}|{sel[:40]}"
        add(key, achse="V1_reflog", ts=ts, repo_id=REPO[wc], workcopy=wc,
            selektor=sel, von=old, nach=new,
            dateien=(len(files) if files is not None else None),
            dateien_quelle=("git diff old..new" if files is not None else None))
        if files:
            for f in files: materialisiert.add(f"{REPO[wc]}::{f}")

# ---------- V3: Merge-Commits im Fenster ----------
seen_repo = set()
for wc in workcopies:
    rid = REPO[wc]
    if rid in seen_repo: continue
    seen_repo.add(rid)
    rc, out = git(wc, "log", "--all", "--merges", "--format=%H\t%P\t%ad",
                  "--date=format-local:%Y-%m-%dT%H:%M:%S",
                  f"--since={LO.isoformat()}", f"--until={HI.isoformat()}")
    for l in out.splitlines():
        if not l.strip(): continue
        sha, parents, ts = l.split("\t")
        if not ts.startswith(DAY): continue
        p1 = parents.split()[0]
        files = diff_files(wc, p1, sha)
        key = f"{rid}|{sha}"
        add(key, achse="V3_merge_commit", ts=ts, repo_id=rid, workcopy=wc,
            selektor=f"merge-commit {sha[:7]}", von=p1, nach=sha,
            dateien=(len(files) if files is not None else None),
            dateien_quelle="git diff <sha>^1 <sha>")
        if files:
            for f in files: materialisiert.add(f"{rid}::{f}")

# ---------- V2: Transkripte ----------
WRITE_VERBS = {"merge","rebase","cherry-pick","revert","pull","stash","clean",
               "apply","am","checkout","switch","restore","reset","clone",
               "submodule","worktree"}
DRYRUN = {"--dry-run","-n","--no-op"}
OPS = {"&&","||","|",";","(",")","{","}","&"}

def statements(cmd):
    cmd = cmd.replace("\n"," ; ")
    try:
        lx = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        lx.whitespace_split = True
        toks = list(lx)
    except ValueError:
        return []
    out, cur = [], []
    for t in toks:
        if t in OPS or (t and all(c in "&|;" for c in t)):
            if cur: out.append(cur); cur=[]
        else: cur.append(t)
    if cur: out.append(cur)
    return out

def classify(toks):
    i = 0
    while i < len(toks) and "=" in toks[i] and not toks[i].startswith("-"): i += 1
    if i >= len(toks) or os.path.basename(toks[i]) != "git": return None
    i += 1; cdir = None
    while i < len(toks) and toks[i].startswith("-"):
        if toks[i] == "-C" and i+1 < len(toks): cdir = toks[i+1]; i += 2
        elif toks[i] == "-c" and i+1 < len(toks): i += 2
        else: i += 1
    if i >= len(toks): return None
    verb, rest = toks[i], toks[i+1:]
    if verb not in WRITE_VERBS: return None
    if any(r in DRYRUN for r in rest): return ("DRYRUN", verb, cdir, rest)
    if verb == "stash" and rest and rest[0] in ("list","show"): return None
    if verb == "reset" and not any(x in rest for x in ("--hard","--merge","--keep")): return None
    if verb == "submodule" and (not rest or rest[0] != "update"): return None
    if verb == "worktree" and (not rest or rest[0] not in ("add","remove","prune")): return None
    if verb == "clean" and not any(x.startswith("-") and "f" in x for x in rest): return None
    return ("WRITE", verb, cdir, rest)

proj = os.path.expanduser("~/.claude/projects")
tfiles = subprocess.run(["find","-L",proj,"-name","*.jsonl","-type","f"],
                        capture_output=True,text=True).stdout.split()
n_dry = 0; v2rows = []
for p in tfiles:
    try: fh = open(p, errors="replace")
    except OSError: continue
    for line in fh:
        if '"Bash"' not in line: continue
        try: o = json.loads(line)
        except Exception: continue
        ts = o.get("timestamp")
        if not ts: continue
        try: t = datetime.fromisoformat(ts.replace("Z","+00:00"))
        except Exception: continue
        if not (LOU <= t < HIU): continue
        msg = o.get("message") or {}
        cont = msg.get("content")
        if not isinstance(cont, list): continue
        for b in cont:
            if not isinstance(b,dict) or b.get("type")!="tool_use" or b.get("name")!="Bash": continue
            cmd = (b.get("input") or {}).get("command") or ""
            for st in statements(cmd):
                c = classify(st)
                if not c: continue
                kind, verb, cdir, rest = c
                if kind == "DRYRUN": n_dry += 1; continue
                tl = t.astimezone(TZ).strftime("%Y-%m-%dT%H:%M:%S")
                v2rows.append({"ts": tl, "verb": verb, "cwd": o.get("cwd") or "",
                               "ziel_c": cdir or "", "kommando": " ".join(st)[:180],
                               "tool_use_id": b.get("id","")})

# V2 an V1/V3 anheften (Zeitfenster +/- 15 min, gleiche Arbeitskopie ODER -C-Ziel)
def wc_of(row):
    cand = row["ziel_c"] or row["cwd"]
    if cand.startswith("$") or not cand: return None
    while cand and cand != "/":
        if os.path.isdir(os.path.join(cand, ".git")) or os.path.isfile(os.path.join(cand, ".git")):
            return cand
        cand = os.path.dirname(cand)
    return None

for row in v2rows:
    wc = wc_of(row)
    rid = REPO.get(wc) if wc else None
    matched = None
    for k, o in ops.items():
        if o.get("workcopy") and rid and o.get("repo_id") != rid: continue
        try:
            dtt = abs((datetime.fromisoformat(o["ts"]) - datetime.fromisoformat(row["ts"])).total_seconds())
        except Exception: continue
        if dtt <= 900 and row["verb"] in o.get("selektor",""):
            matched = k; break
    if matched:
        o = ops[matched]
        o["achsen"].append("V2_transkript")
        o["kommando"] = row["kommando"]
        o["ts_kommando"] = row["ts"]
        o["tool_use_id"] = row["tool_use_id"]
    else:
        key = f"{rid or 'UNRESOLVED'}|{wc or row['cwd']}|{row['ts']}|{row['verb']}"
        add(key, achse="V2_transkript", ts=row["ts"], repo_id=rid or "UNRESOLVED",
            workcopy=wc or row["cwd"], selektor=row["verb"],
            kommando=row["kommando"], tool_use_id=row["tool_use_id"])

out = {
 "tag": DAY, "tz": "UTC",
 "fenster": [LO.isoformat(), HI.isoformat()],
 "arbeitskopien_gescannt": len(workcopies),
 "repos_gescannt": len(seen_repo),
 "vcs_operationen": sorted(ops.values(), key=lambda x: x["ts"]),
 "zaehler": {
   "operationen": len(ops),
   "operationen_mit_dateizahl": sum(1 for o in ops.values() if o.get("dateien") is not None),
   "dateien_beruehrt_summe": sum(o.get("dateien") or 0 for o in ops.values()),
   "dateien_beruehrt_eindeutig": len(materialisiert),
   "dryrun_verworfen": n_dry,
   "achsen": {a: sum(1 for o in ops.values() if a in o["achsen"])
              for a in ("V1_reflog","V2_transkript","V3_merge_commit")},
 },
 "vcs_materialisiert": sorted(materialisiert),
}
print(json.dumps(out, ensure_ascii=False, indent=1))
QVEOF

set +e
python3 "$WORK/qv2.py" "$D" "$ROOTS" > "$WORK/vcs.json" 2>"$WORK/qv2.err"; QV_RC=$?
set -e
if [ "$QV_RC" -ne 0 ]; then
  { echo "ABORT(21): S12/Q_V scheiterte (rc=$QV_RC) — VCS-Achse nicht auswertbar"
    head -5 "$WORK/qv2.err" | sed 's/^/  qv2: /'; } >&2
  exit 21
fi
jq -r '.vcs_materialisiert[]' "$WORK/vcs.json" | sort -u > "$WORK/vcs_materialisiert.txt"
NVCS=$(jq -r '.zaehler.operationen' "$WORK/vcs.json")
NVCSMAT=$(wc -l < "$WORK/vcs_materialisiert.txt" | tr -d ' ')
rcpt "S12 vcs_operationen=$NVCS dateien_materialisiert=$NVCSMAT achsen=$(jq -c '.zaehler.achsen' "$WORK/vcs.json") dryrun_verworfen=$(jq -r '.zaehler.dryrun_verworfen' "$WORK/vcs.json")"

# Union + Absorption in EINEM deterministischen Schritt (Konflikt A + B).
python3 - "$WORK" > "$WORK/union.meta" <<'PY'
import sys, os
W = sys.argv[1]
def rows(f):
    p = os.path.join(W, f)
    if not os.path.exists(p): return []
    out = []
    for l in open(p).read().split('\n'):
        if not l: continue
        c = l.split('\t')
        if len(c) >= 9: out.append(c)
    return out
def lines(f):
    p = os.path.join(W, f)
    if not os.path.exists(p): return []
    return [l for l in open(p).read().split('\n') if l]

# ZAEHLBASIS REPO-IDENTITAET: Arbeitskopie-Beweis und Git-Inhaltsbeweis teilen sich
# EINEN Schluesselraum (<repo_id>::<relpfad>). Die frueheren drei Identitaetsbegriffe
# (Item=Arbeitskopie, Absorption=Repo, Kollaps=Repo-ohne-Worktree) fallen damit zu EINER
# Achse zusammen: "Absorption" ist keine Sonderregel mehr, sondern die gewoehnliche
# Vereinigung auf dem Schluessel. Sie wird nur noch als KENNZAHL berichtet.
# 1) Arbeitskopie-Items (T, D, B); workcopies wird als ATTRIBUT mitgefuehrt.
items = {}             # key -> set(evidence)
workcopies = {}        # key -> set(workcopy)
qb_ok = set(lines('qb.txt'))
wc_keys = set()        # Schluessel mit Arbeitskopie-Beleg (fuer die Absorptionskennzahl)
for c in rows('pass1.tsv') + rows('pass2.tsv'):
    dec, key, flag, cat, rid, wt, src, raw, wcp = c[:9]
    if dec not in ('keep', 'rescued'): continue
    if src == 'C': continue                      # Canary
    if src in ('G', 'g'): continue               # Git separat (andere Beweisklasse)
    if src == 'B' and key not in qb_ok: continue # unaufgeloeste Bash-Ziele raus
    items.setdefault(key, set()).add({'T': 'T', 'D': 'D', 'B': 'B'}[src])
    wc_keys.add(key)
    if wcp and wcp != '-': workcopies.setdefault(key, set()).add(wcp)

# 2) B-dir-Evidenz: ambige G-Pfade, deren Verzeichnis statisch aufgeloestes Bash-Ziel war
bdirs = set(os.path.realpath(d) for d in lines('qb_dirs.txt'))
bdir_hit = set()
g_strict, g_ambig = {}, {}
for c in rows('pass2.tsv'):
    dec, key, flag, cat, rid, wt, src, raw, wcp = c[:9]
    if dec not in ('keep', 'rescued') or src not in ('G', 'g'): continue
    if key.startswith('fs::'): continue
    (g_strict if src == 'G' else g_ambig)[key] = raw
    if src == 'g' and os.path.realpath(os.path.dirname(raw)) in bdirs:
        bdir_hit.add(key)

absorbed = 0
for k in sorted(g_strict):
    if k in wc_keys: absorbed += 1
    items.setdefault(k, set()).add('G')
gamb_unres = []
for k in sorted(g_ambig):
    if k in wc_keys:
        items[k].add('G'); absorbed += 1
    elif k in bdir_hit:
        items.setdefault(k, set()).add('Bdir')
    else:
        gamb_unres.append(k)

# 3) S12 ANTI-DOPPELZAEHL-REGEL — die einzige Verzahnung mit vcs_operationen.
# Eine Datei, die eine VCS-Operation nur MATERIALISIERT hat, ist kein Item: dieselbe
# Datei wurde am Verfassungstag bereits gezaehlt, und die Tagessumme wuerde sonst
# Merge-Haeufigkeit statt Arbeit messen. Unterdrueckt wird aber NUR, wenn der
# Evidenzsatz AUSSCHLIESSLICH {Gm} ist. Sobald T/D/B ODER ein G-strict aus einem
# NICHT-Merge-Commit vorliegt, bleibt die Datei Item — Gm waechst dann nur ins
# evidence-Set. Damit zaehlt eine gemergte UND danach bearbeitete Datei genau EINMAL
# (ueber ihr Edit-Ereignis), eine rein materialisierte NIE.
mat = set(lines('vcs_materialisiert.txt'))
gm_only = []
for k in sorted(mat):
    if k in items:
        items[k].add('Gm')
    else:
        gm_only.append(k)
with open(os.path.join(W, 'gm_only.txt'), 'w') as fh:
    for k in gm_only: fh.write(k + '\n')

with open(os.path.join(W, 'items.txt'), 'w') as fh:
    for k in sorted(items): fh.write(k + '\n')
with open(os.path.join(W, 'items_evidence.tsv'), 'w') as fh:
    for k in sorted(items):
        fh.write('%s\t%s\t%s\n' % (k, ''.join(sorted(items[k])),
                                   ','.join(sorted(workcopies.get(k, ['-'])))))
with open(os.path.join(W, 'git_ambiguous.txt'), 'w') as fh:
    for k in gamb_unres: fh.write(k + '\n')
# sync_pairs jetzt ueber das ATTRIBUT: derselbe Schluessel in >=2 Arbeitskopien beruehrt.
sync = sorted(k for k, v in workcopies.items() if len(v) > 1)
with open(os.path.join(W, 'sync_pairs.txt'), 'w') as fh:
    for k in sync: fh.write(k + '\t' + ','.join(sorted(workcopies[k])) + '\n')
def cnt(ev): return sum(1 for v in items.values() if ev in v)
print('items=%d T=%d D=%d G=%d B=%d Bdir=%d absorbed=%d gamb=%d gm_only=%d sync=%d'
      % (len(items), cnt('T'), cnt('D'), cnt('G'), cnt('B'), cnt('Bdir'),
         absorbed, len(gamb_unres), len(gm_only), len(sync)))
PY
read -r _ NQT_E NQD_E NQG_E NQB_E NBDIR_E _ _ <<<"$(sed -e 's/[a-zA-Z_]*=//g' "$WORK/union.meta")"
UNION_META=$(cat "$WORK/union.meta")
rcpt "S10-union $UNION_META"

# ============================== S7 Q_M (Handarbeit) ==============================
: > "$WORK/qm.txt"
if [ "$MAN_STATUS" = "ok" ]; then MANUAL_BUCKET=0; MANUAL_PY=0
else MANUAL_BUCKET=null; MANUAL_PY=None; fi
rcpt "S7 Q_M bucket=$MANUAL_BUCKET"

# ============================== S10 Vereinigung (items.txt kommt aus union.py) ==============================
if [ ! -f "$WORK/items.txt" ]; then echo "ABORT(9): Senke items.txt nicht geschrieben" >&2; exit 9; fi
# "leer trotz Eingabe" nur noch, wenn es EINGABE GAB. Ein belegbar arbeitsfreier Alttag
# muss 0 liefern duerfen — sonst ist "0" per Konstruktion unaussprechbar.
NIN_PASS=$(awk -F'\t' '($1=="keep"||$1=="rescued") && $7!="C"' "$WORK/pass1.tsv" "$WORK/pass2.tsv" | wc -l | tr -d ' ')
if [ ! -s "$WORK/items.txt" ] && [ "$NIN_PASS" -gt 0 ]; then
  echo "ABORT(9): items.txt leer trotz $NIN_PASS Eingabezeilen" >&2; exit 9; fi
ITEMS=$(wc -l < "$WORK/items.txt" | tr -d ' ')
SHA=$(shasum -a 256 "$WORK/items.txt" | cut -d' ' -f1)

# ============================== S8 Selbstpruefung ==============================
# (1) CANARY — muss die gesamte Kanonisierungskette ueberleben
NCAN=$(wc -l < "$WORK/canary.txt" | tr -d ' ')
if [ "$NCAN" -ne 1 ]; then
  echo "ABORT(11): SELBSTPRUEFUNG DEFEKT — Canary hat die Kette nicht ueberlebt ($NCAN)" >&2; exit 11; fi

# (2) Zweitzaehler ueber anderen Codepfad
NQT2=$(python3 -c "import sys;print(len(set(l for l in open(sys.argv[1]).read().split('\n') if l)))" "$WORK/qt.txt")
if [ "$NQT" -ne "$NQT2" ]; then echo "ABORT(11): Zweitzaehler weicht ab ($NQT vs $NQT2)" >&2; exit 11; fi

# (3) I4 — Signals als Hook-Ausfall-Detektor (nie gezaehlt). Feld ist .ts, nicht .timestamp.
set +e
jq -r --arg s "$WSTART" --arg e "$WEND" '
  select(.ts != null)
  | select((.ts|sub("\\.[0-9]+Z$";"Z")) >= $s and (.ts|sub("\\.[0-9]+Z$";"Z")) < $e)
  | (.file // "") | select(. != "")' \
  "$WORK/sig-$PREV.jsonl" "$WORK/sig-$D.jsonl" 2>"$WORK/i4_jq.err" | sort -u > "$WORK/sig_raw.txt"
I4_JQ_RC=${PIPESTATUS[0]}
set -e
if [ "$I4_JQ_RC" -ne 0 ]; then
  echo "ABORT(15): I4-Detektor-jq scheiterte (rc=$I4_JQ_RC) — der Ausfall-Detektor selbst ist blind" >&2; exit 15; fi
awk '{print "S\t" $0}' "$WORK/sig_raw.txt" > "$WORK/sig.in"
if [ -s "$WORK/sig.in" ]; then python3 "$WORK/canon.py" < "$WORK/sig.in" > "$WORK/sig.tsv"
else : > "$WORK/sig.tsv"; fi
awk -F'\t' '($1=="keep"||$1=="rescued"){print $2}' "$WORK/sig.tsv" | sort -u > "$WORK/qsig.txt"
NSIG=$(wc -l < "$WORK/qsig.txt" | tr -d ' ')
awk -v PF="$WORK/qt.txt" 'FILENAME==PF{r[$0]=1;next} !($0 in r)' "$WORK/qt.txt" "$WORK/qsig.txt" > "$WORK/i4_gap.txt"
I4=$(wc -l < "$WORK/i4_gap.txt" | tr -d ' ')
# WAECHTER-ENTKOPPLUNG: ein Waechter darf nicht an der Quelle haengen, die er ueberwacht.
# Die alte Bedingung `NSIG>0 && NQT==0` teilte mit ihrem Schutzobjekt Platte, Rechte und
# Rotation ($HOME/.claude) — ein leeres-aber-gueltiges Archiv setzte NSIG=0 und machte den
# einzigen Waechter gegen einen blinden Transkriptzweig strukturell unausloesbar.
# Jetzt feuert ABORT(13), sobald Q_T=0 und EIN Zeuge aus VIER unabhaengigen Achsen lebt.
# Die Git-Achse (Repos AUSSERHALB $HOME/.claude) teilt weder Verzeichnisbaum noch Rotation
# noch Rechte mit dem Transkriptzweig — sie ist die quellenunabhaengige Mindesterwartung.
NGSTRICT=$(wc -l < "$WORK/g_strict_paths.txt" | tr -d ' ')
NQD_RAW=$(wc -l < "$WORK/qd_raw.txt" | tr -d ' ')
ZEUGEN="signals=$NSIG events=$NEV pairs=$NPAIRS desktop=$NQD_RAW git_strict=$NGSTRICT vcs=$NVCS"
# Epochenbewusst: ein Transkriptzweig, den es am Zieltag NICHT GAB, ist nicht blind.
if [ "$TR_STATE" = "verified" ] && [ "$NQT" -eq 0 ] \
   && { [ "$NSIG" -gt 0 ] || [ "$NEV" -gt 0 ] || [ "$NPAIRS" -gt 0 ] \
     || [ "$NQD_RAW" -gt 0 ] || [ "$NGSTRICT" -gt 0 ] || [ "$NVCS" -gt 0 ]; }; then
  echo "ABORT(13): Q_T=0, aber unabhaengige Zeugen leben ($ZEUGEN) — Transkriptzweig blind" >&2; exit 13; fi
# ABORT(17): zweites, unabhaengiges Netz. Greift genau dann, wenn ABORT(13) NICHT greift
# (lebender Transkriptzweig), und beweist einen Hook-/Rotationsausfall.
if [ "$SIG_EMPTY_DAYS" -ge 2 ] && [ "$NEV" -gt 0 ]; then
  echo "ABORT(17): beide signals-Archive state=empty_verified, aber $NEV Ereigniszeilen im Fenster — Hook- oder Rotationsausfall" >&2; exit 17; fi
rcpt "S8 canary=ueberlebt zweitzaehler=$NQT2 OK Q_signals=$NSIG i4_gap=$I4 zeugen=[$ZEUGEN]"

# ============================== R6 Abbruchbedingungen ==============================
if [ "$FAULT" = "e" ]; then ITEMS=0; fi
MAXSRC=$(( NEV + NSIG + NOK + $(wc -l < "$WORK/qd_raw.txt" | tr -d ' ') ))
if [ "$ITEMS" -eq 0 ] && [ "$MAXSRC" -gt 0 ]; then
  echo "ABORT(7): items=0, WAEHREND Quellen liefern (events=$NEV signals=$NSIG rohpaare=$NOK desktop=$(wc -l < "$WORK/qd_raw.txt" | tr -d ' '))" >&2; exit 7; fi
if [ "$ITEMS" -eq 0 ]; then
  rcpt "S10 items=0 — KEINE Quelle liefert; Tag wird als belegbar arbeitsfrei ausgewiesen (nicht als Messfehler)"; fi
UNIQ_KEPT=$(awk -F'\t' '($1=="keep"||$1=="rescued") && $7=="T"{print $2}' "$WORK/pass1.tsv" | sort -u | wc -l | tr -d ' ')
# ABORT(14) mit QUELLENUEBERGREIFENDER Bezugsgroesse. Frueher MIN=UNIQ_KEPT/2, wobei
# UNIQ_KEPT ausschliesslich aus Q_T stammte: bei Q_T=0 war MIN=0 und die Schwelle
# neutralisierte sich selbst genau dann, wenn die Quelle ausfiel, gegen die sie schuetzt.
REF=$UNIQ_KEPT; REFQ=Q_T
for pair in "$NGSTRICT:G_strict" "$NQD_RAW:Q_D" "$NSIG:Q_signals"; do
  v=${pair%%:*}; q=${pair##*:}
  if [ "$v" -gt "$REF" ]; then REF=$v; REFQ=$q; fi
done
MIN=$(( REF / 2 ))
if [ "$ITEMS" -lt "$MIN" ]; then
  echo "ABORT(14): items=$ITEMS < 50% von REF=$REF (Herkunft $REFQ)" >&2; exit 14; fi
rcpt "S10 plausibilitaet_bezug=$REF quelle=$REFQ mindest_erwartung=$MIN (uniq_kept=$UNIQ_KEPT)"

# ============================== Ausgabe ==============================
STATUS=ok; [ "$MAN_STATUS" = "ok" ] || STATUS=DEGRADED
[ "$TR_STATE" = "verified" ] || STATUS=DEGRADED
[ "$SIG_PRE_DAYS" -eq 0 ] || STATUS=DEGRADED
[ "$DESK_STATUS" = "ok" ] || STATUS=DEGRADED
jl() { sort -u | python3 -c "import sys,json;print(json.dumps([l for l in sys.stdin.read().split(chr(10)) if l],ensure_ascii=False))"; }
exclq() { awk -F'\t' -v c="$1" -v s="$2" '$1=="drop" && $7==s && $4 ~ ("^" c) {n++} END{print n+0}' "$WORK/pass1.tsv" "$WORK/pass2.tsv"; }
SYNC=$(wc -l < "$WORK/sync_pairs.txt" | tr -d ' ')

# ---- ZERTIFIKATSPFLICHT (ABORT 18) --------------------------------------------------
# Kein Feld in `sources` darf einen Literalwert tragen — dieselbe Regel wie
# "keine Logzeile ohne count_basis". Ein hartkodiertes "ok" ist eine Behauptung,
# kein Messwert (im Originalskript stand "ok" als String in der Emitter-Zeile).
CERT_S1E="manifest=$MAN_STATUS;state=$( [ "$MAN_STATUS" = ok ] && echo verified || echo degraded_missing )"
CERT_S1B="${CERT_S1B};epoche=$EP_DESK"
for cv in "S1a:$CERT_S1A" "S1b:$CERT_S1B" "S1c:$CERT_S1C" "S1d:$CERT_S1D" "S1e:$CERT_S1E"; do
  nm=${cv%%:*}; val=${cv#*:}
  case "$val" in
    '' ) echo "ABORT(18): Zertifikat fuer $nm ist leer — Quelle wurde nicht nachweislich gelesen" >&2; exit 18 ;;
    *state=* ) : ;;
    * ) echo "ABORT(18): Zertifikat fuer $nm ohne state= : '$val'" >&2; exit 18 ;;
  esac
done

# ---- EVIDENCE_TIER (Pflichtfeld, 1-4) ------------------------------------------------
# 1 = alle vier Achsen verifiziert (Transkript, Desktop, Signals, Git/VCS)
# 2 = eine Achse degradiert oder leer-verifiziert
# 3 = zwei Achsen fehlen; 4 = nur noch EINE Achse traegt den Tag (duenner Tag)
TIER=1; TIER_GRUND=""
[ "$DESK_STATUS" = "ok" ]   || { TIER=$((TIER+1)); TIER_GRUND="$TIER_GRUND desktop_$DESK_STATUS;"; }
[ "$SIG_EMPTY_DAYS" -eq 0 ] || { TIER=$((TIER+1)); TIER_GRUND="$TIER_GRUND signals_leer($SIG_EMPTY_DAYS/2);"; }
[ "$SIG_PRE_DAYS" -eq 0 ]   || { TIER=$((TIER+1)); TIER_GRUND="$TIER_GRUND signals_vor_epoche($SIG_PRE_DAYS/2,ab_$EP_SIG);"; }
[ "$TR_STATE" = "verified" ] || { TIER=$((TIER+1)); TIER_GRUND="$TIER_GRUND transkripte_vor_epoche(ab_$EP_TR);"; }
[ "$MAN_STATUS" = "ok" ]    || { TIER=$((TIER+1)); TIER_GRUND="$TIER_GRUND manifest_fehlt;"; }
# reflog-Retention: gc.reflogExpire liegt bei 90 Tagen. Fuer aeltere Tage faellt Achse V1
# aus; das MUSS den Tier senken, sonst wirkt ein alter Tag so vollstaendig gemessen wie
# ein neuer. Der Backfill reicht 168 Tage zurueck — die aeltere Haelfte ist betroffen.
AGE=$(python3 -c "import sys,datetime;print((datetime.date.today()-datetime.date.fromisoformat(sys.argv[1])).days)" "$D")
if [ "$AGE" -gt 90 ]; then TIER=$((TIER+1)); TIER_GRUND="$TIER_GRUND reflog_retention_ueberschritten(${AGE}d>90d);"; fi
[ "$TIER" -le 4 ] || TIER=4
[ -n "$TIER_GRUND" ] || TIER_GRUND=" alle_achsen_verifiziert;"
python3 - > "$WORK/out.json" <<PY
import json
_VCS = json.load(open("$WORK/vcs.json"))
print(json.dumps({
 "count_basis": "files_touched_v3",
 "quellen_epochen": {"signals": "$EP_SIG", "transkripte": "$EP_TR", "desktop": "$EP_DESK",
                     "quelle": "$EPO_QUELLE"},
 "quellen_zustand": {"transkripte": "$TR_STATE", "desktop": "$DESK_STATUS",
                     "signals_tage_vor_epoche": $SIG_PRE_DAYS},
 "git_achse": {"repos_gescannt": $NREPO, "arbeitskopien": $NREPO_WC,
               "discovery_repos": $NDISC, "reflog_unabhaengig": True,
               "commit_auswahl": "autor_datum ODER committer_datum == Tag"},
 "git_ambiguous_nicht_gezaehlt": $(wc -l < "$WORK/git_ambiguous.txt" | tr -d ' '),
 "day": "$D", "tz": "UTC", "window": ["$WSTART", "$WEND"],
 "status": "$STATUS",
 "items_total": $ITEMS,
 "evidence_counts": {"T_transkript": $NQT_E, "D_desktop": $NQD_E, "G_git": $NQG_E,
                     "B_bash": $NQB_E, "Bdir_bash_verzeichnis": $NBDIR_E, "M_manual": $MANUAL_PY},
 "quellen_roh": {"Q_T": $NQT, "Q_D": $NQD, "Q_B": $(wc -l < "$WORK/qb.txt" | tr -d ' '),
                 "G_strict": $(wc -l < "$WORK/g_strict_paths.txt" | tr -d ' '),
                 "G_ambig": $(wc -l < "$WORK/g_ambig_paths.txt" | tr -d ' ')},
 "excluded_s9a_qt": {"a1_tmp": $(exclq a1 T), "a2_claude_selfgen": $(exclq a2 T),
                     "a3_claude_runtime": $(exclq a3 T), "a4_icloud": $(exclq a4 T),
                     "a5_tmp_segment": $(exclq a5 T), "a6_runid_sandbox": $(exclq a6 T)},
 "excluded_s9a_qd": {"a6_runid_sandbox": $(exclq a6 D), "a1_tmp": $(exclq a1 D)},
 "excluded_s9b_named": $(awk -F'\t' '$1=="drop" && $4 ~ /^b1_gitignored/{sub(/^b1_gitignored:/,"",$4);print $4}' "$WORK/pass1.tsv" "$WORK/pass2.tsv" | jl),
 "s9b_allowlist_rescued": $(awk -F'\t' '$1=="rescued"{print $2}' "$WORK/pass1.tsv" "$WORK/pass2.tsv" | jl),
 "git_ambiguous": $(cat "$WORK/git_ambiguous.txt" | jl),
 "merge_commits": $NMERGE,
 "unbekanntes_werkzeug_mit_pfad": $(cat "$WORK/unknown_qt.tsv" "$WORK/unknown_qd.tsv" | awk -F'\t' '{print $1 "  ->  " $2}' | jl),
 "werkzeugkarte": {"eintraege": $NMAP, "bash_ops_erkannt": "$(cat "$WORK/qb_ops.txt")",
                   "desktop_bash_calls": $NBASHD},
 "qb_unresolved_verworfen": $(cat "$WORK/qb_unresolved.txt" | jl),
 "unresolved_items": $(awk -F'\t' '$1=="keep" && $3=="UNRESOLVED" && $7!="C"{print $2}' "$WORK/pass1.tsv" | jl),
 "worktree_paths_seen": $(awk -F'\t' '$6!="-"' "$WORK/pass1.tsv" | wc -l | tr -d ' '),
 "wt_pruned_structural": $(awk -F'\t' '$3=="wt_pruned_structural"' "$WORK/pass1.tsv" "$WORK/pass2.tsv" | wc -l | tr -d ' '),
 "sync_pairs": $SYNC,
 "sync_pairs_detail": $(cut -f1 "$WORK/sync_pairs.txt" | jl),
 "git_absorbiert_in_arbeitskopie": $(sed -e 's/.*absorbed=//' -e 's/ .*//' "$WORK/union.meta"),
 "evidence_tier": $TIER,
 "evidence_tier_grund": "$(echo "$TIER_GRUND" | sed 's/^ //;s/"/\\"/g')",
 "workcopies_je_item": $(python3 -c "
import sys,json
d={}
for l in open('$WORK/items_evidence.tsv'):
    p=l.rstrip('\n').split('\t')
    if len(p)>=3 and p[2] not in ('-',''): d[p[0]]=p[2].split(',')
print(json.dumps(d,ensure_ascii=False))"),
 # NIE JSON per Kommandosubstitution in Python-Quelltext einsetzen: ein JSON-null ist
 # gueltiges JSON und ungueltiges Python (NameError). Deshalb hier json.load, kein jq.
 # (Backticks in diesem Heredoc sind ebenfalls verboten — es ist UNQUOTED, die Shell
 #  fuehrt sie sonst als Kommando aus; im ersten Lauf real passiert.)
 "vcs_operationen": _VCS["vcs_operationen"],
 "vcs_zaehler": _VCS["zaehler"],
 "vcs_arbeitskopien_gescannt": _VCS["arbeitskopien_gescannt"],
 "vcs_nur_materialisiert_nicht_gezaehlt": $(cat "$WORK/gm_only.txt" | jl),
 "sources": {
   "S1a_transcripts": "$CERT_S1A",
   "S1b_desktop":     "$CERT_S1B",
   "S1c_signals":     "$CERT_S1C",
   "S1d_roots":       "$CERT_S1D",
   "S1e_manifest":    "$CERT_S1E",
   "W19_symlink":     "$W19_CERT"
 },
 "waechter_zeugen": "$ZEUGEN",
 "signals_leere_tage": $SIG_EMPTY_DAYS,
 "plausibilitaet_bezug": {"referenz": $REF, "quelle": "$REFQ", "mindest_erwartung": $MIN},
 "nicht_erfassbar": [
   "Uncommittete Arbeit und Edit-und-Revert am selben Tag: Q_G meldet nur das Netto-Delta zum Vorgaenger-Blob.",
   "Schreibvorgaenge ausserhalb der Werkzeugebene (Hooks, Framework-Skripte) erzeugen kein tool_use und sind auf keiner Achse sichtbar.",
   "Externe Systeme (Notion, Deploys, Kommunikation) haben per Konstruktion 0 Items — bewusste Eigenschaft der Zaehlbasis, kein Messfehler.",
   "git merge --no-commit und git checkout -- <pfad> im Terminal ausserhalb einer Claude-Session: keine HEAD-Bewegung (kein reflog) und kein Transkript.",
   "Umfang entfernter Arbeitskopien (git worktree remove): dateien=null, nicht 0 — nicht rekonstruierbar.",
   "$( [ "$AGE" -gt 90 ] && echo "reflog-Retention ueberschritten (${AGE}d > 90d): Achse V1 faellt fuer diesen Tag aus." || echo "Fuer diesen Tag keine retentionsbedingte Achsen-Luecke (Alter ${AGE}d <= 90d)." )",
   "$( [ "$MAN_STATUS" = ok ] && echo "Handarbeits-Zweig gemessen." || echo "Handarbeits-Zweig (Q_M) nicht messbar: kein manifest-$PREV — buckets.manual ist null, nicht 0." )"
 ],
 "i4_gap": $I4,
 "nebenmetriken": {"ereigniszeilen": $NEV, "schreibpaare_roh": $NPAIRS,
                   "fehlschlaege_gefiltert": $NFAIL, "bash_calls": $NBASH, "bash_unparsebar": $NBUNPARSED,
                   "signals_keys": $NSIG, "repo_ids_gescannt": $NREPO,
                   "arbeitskopien_gesehen": $NREPO_WC},
 "items_sha256": "$SHA"
}, indent=1, ensure_ascii=False))
PY
cat "$WORK/out.json"
if [ -n "${LOGBOOK_ITEMS_OUT:-}" ]; then cp "$WORK/items.txt" "$LOGBOOK_ITEMS_OUT"; fi
