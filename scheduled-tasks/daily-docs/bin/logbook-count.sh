#!/usr/bin/env bash
# logbook-count v3.4 — day count "touched file days" (TFD), count basis REPO IDENTITY
# Usage: LOGBOOK_ROOTS=<path to roots.txt> bash logbook-count.sh YYYY-MM-DD
# Optional (backfill/old days before the transcript epoch): LOGBOOK_GIT_ROOTS=<path to
# git-roots.txt> — tree roots (not repos) for the source-independent git discovery.
# Without this variable, a day BEFORE the transcript epoch with no discovery repos stays
# an ABORT(24), never a silent 0. See roots.txt.example / git-roots.txt.example next to it.
# Writes EXCLUSIVELY to $WORK (mktemp -d under TMPDIR). No repo, no ~/.claude.
#
# MODULE STATUS (assembled 2026-07-18 from two workflow rounds, R4+R5 — backend-agent):
# This script is FULLY SELF-CONTAINED. qv2.py and canon.py sit next to it as
# HISTORICAL, NOT-WIRED-IN reference artifacts (a development stage before they were
# embedded into this script) — they are NOT invoked at runtime, they only serve
# traceability/audit of the S12/S9a/S9b logic. qh.py (the Q_H/history-DB axis)
# is SPECIFIED but NOT integrated into this script, and its source was no longer
# reconstructable at assembly time (it sat in the ephemeral $TMPDIR of a
# terminated subagent). The 2026-01-15 value below comes from the source-independent
# GIT DISCOVERY branch (the v3.4 addition), not from Q_H — details in the assembly log.
set -euo pipefail

# ============================== R0 Execution contract ==============================
# 1. set -euo pipefail is on line 5.
# 2. NO `grep -f` anywhere. Set subtraction only via awk FILENAME==PF.
#    `NR==FNR` is FORBIDDEN (with an empty pattern file it consumes the payload data, exit 0).
# 3. Fallbacks only as if/then/else, never `A | B || C > out`.
# 4. Working files only in $WORK.
# 5. Freshness assertion on $WORK.
# 6. TOOLS ARE PINNED (measured, not assumed): in this environment `grep`
#    is a shell function that redirects to ugrep with `--ignore-files`. Measured on
#    2026-07-18: `grep -c 'set' v32.sh` -> rc=1, 0 hits; `/usr/bin/grep -c` -> 19.
#    An ignored directory makes the positive scan SILENTLY empty. The same applies to
#    `find` (bfs shim, different cycle semantics). Both are invoked with absolute paths.
# IMP-219 (2026-09-25): timezone from the environment, never hardcoded. Priority:
# already-set $TZ (e.g. a test suite) > $CLAUDE_LOGBOOK_TZ (optional in
# ~/.claude/env.local.sh) > system timezone (readlink /etc/localtime). NEVER
# set `TZ=""` (on macOS an empty TZ equals UTC — a silent
# mismeasurement, not an honest "unknown" report, see ABORT(6) below).
if [ -z "${TZ:-}" ]; then
  [ -n "${CLAUDE_LOGBOOK_TZ:-}" ] || { [ -f "$HOME/.claude/env.local.sh" ] && . "$HOME/.claude/env.local.sh"; }
  TZ="${CLAUDE_LOGBOOK_TZ:-}"
fi
if [ -z "${TZ:-}" ]; then
  LOCALTIME_LINK=$(readlink /etc/localtime 2>/dev/null || true)
  case "$LOCALTIME_LINK" in
    */zoneinfo/*) TZ="${LOCALTIME_LINK#*/zoneinfo/}" ;;
  esac
fi
[ -n "${TZ:-}" ] || { echo "ABORT(6): timezone not determinable (neither \$TZ nor \$CLAUDE_LOGBOOK_TZ set, readlink /etc/localtime without a zoneinfo path) — set CLAUDE_LOGBOOK_TZ in ~/.claude/env.local.sh" >&2; exit 6; }
export TZ
FINDBIN=/usr/bin/find
GREPBIN=/usr/bin/grep
for b in "$FINDBIN" "$GREPBIN"; do
  [ -x "$b" ] || { echo "ABORT(20): pinned tool missing: $b" >&2; exit 20; }
done
D="${1:?ABORT(1): day missing (YYYY-MM-DD)}"
# ROOTS resolution (2026-07-18): the default is the file NEXT TO the script, not an
# environment variable. Reason: the original defect of this routine — ${LOGBOOK_DIR}
# was never set, silently expanded to empty, and the run repaired itself from old
# log lines. A mandatory env variable that the scheduler doesn't set is the same
# defect in a new shape (measured: invocation without LOGBOOK_ROOTS -> ABORT(3)).
# LOGBOOK_ROOTS remains a higher-priority override for tests/backfill.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTS="${LOGBOOK_ROOTS:-$SCRIPT_DIR/roots.txt}"
[ -r "$ROOTS" ] || { echo "ABORT(3): roots file not readable: $ROOTS (neither \$LOGBOOK_ROOTS nor $SCRIPT_DIR/roots.txt)" >&2; exit 3; }
: "${LOGBOOK_GIT_ROOTS:=$SCRIPT_DIR/git-roots.txt}"; export LOGBOOK_GIT_ROOTS
FAULT="${LOGBOOK_FAULT:-}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/logbook-$D.XXXXXX")"
if [ -n "${LOGBOOK_KEEP:-}" ]; then trap 'echo "WORK=$WORK kept" >&2' EXIT
else trap 'rm -rf "$WORK"' EXIT; fi
N_PRE=$(ls -A "$WORK" | wc -l | tr -d ' ')
if [ "$N_PRE" != "0" ]; then echo "ABORT(10): working directory not fresh ($N_PRE entries)" >&2; exit 10; fi
if [ "$FAULT" = "b" ]; then : > "$WORK/altbestand.txt"
  N_PRE=$(ls -A "$WORK" | wc -l | tr -d ' ')
  echo "ABORT(10): working directory not fresh ($N_PRE entries)" >&2; exit 10; fi

rcpt() { echo "RECEIPT $*" >&2; }

# ============================== W19 symlink guard (ABORT 19) ==============================
# A directory symlink hides an unbounded subtree WITHOUT any number,
# certificate, or stderr line diverging. Measured: original script against a tree
# with 2 outsourced subtrees -> EXIT=0, day count 90 instead of 99, certificate "state=verified".
#
# WHY ABORT AND NOT `find -L` (three actual measurements, not claims):
#  (a) CYCLES: /usr/bin/find -L on a symlink loop -> rc=0, 0 stderr lines.
#      Switching to -L therefore introduces a NEW silent failure mode.
#  (b) DOUBLE-COUNTING: -L lists the same file again under every path (3 inodes -> 6 paths).
#      With item_key = <repo_id>::<relpath>, two paths are two keys.
#  (c) CANONICAL KEY: with two paths to one file, it's undecidable which
#      relpath is the key. Guessing would be a number with no evidence.
#
# CLASSIFICATION instead of a counter — otherwise the guard would be unusable: the
# desktop tree carries 67 legitimate symlinks (node_modules/.bin, dead debug/latest
# pointers). A guard on the rule "any symlink -> abort" would have fired daily from day one.
#   DIR symlink      -> ABORT (hides a subtree)
#   pattern symlink   -> ABORT (hides a countable source file)
#   any other         -> goes into the certificate, NO abort (hides nothing)
#
# IMP-225 — IN-TREE FILE LINKS (4th argument "intree", used ONLY by S1a):
# Claude Code itself creates, when a background-job session starts, file symlinks
# <new-session>/subagents/agent-*.jsonl -> <parent-session>/subagents/agent-*.jsonl
# in the SAME project directory (measured 2026-09-27: 3 such links; every
# background job made the next daily-docs run ABORT(19)). Such a link hides
# nothing: its target is a regular file that the normal walk (find WITHOUT -L,
# BSD grep -r, which does not follow file links — measured) already counts once.
# A pattern link is TOLERATED iff ALL hold (else it stays a pattern symlink -> ABORT):
#   - stat() through the link succeeds (not dangling, no cycle),
#   - the fully resolved target is a REGULAR file,
#   - it lies strictly under realpath(tree root),
#   - its basename matches the same pattern (so the walk counts it).
# Tolerated links are excluded from the count, listed on stderr (NOTE W19) and
# certified as symlinks_tolerated=N. The find/find -L axis still has to agree:
# n_L must equal n + tolerated, otherwise ABORT(19) as before.
W19_CERT=""
w19() {
  local baum="$1"; local quelle="$2"; local muster="$3"; local modus="${4:-}"
  local dirn=0 mustn=0 sonst=0 n=0 nL=0 frc=0 wurzel=nein tol=0 crc=0
  local L="$WORK/w19-$quelle.links"; local B="$WORK/w19-$quelle.bad"
  local P="$WORK/w19-$quelle.pattern"; local V="$WORK/w19-$quelle.verdicts"
  : > "$L"; : > "$B"; : > "$P"; : > "$V"
  # (0) Root probe: find WITHOUT -L does not enter a symlink root at all.
  if [ -L "$baum" ]; then wurzel=ja; fi
  set +e
  "$FINDBIN" "$baum" -type l -print > "$L" 2>/dev/null; frc=$?
  set -e
  # (1)+(2) Census and classification in the SAME traversal, which does not enter the links.
  while IFS= read -r lk; do
    [ -n "$lk" ] || continue
    if [ -d "$lk" ]; then dirn=$((dirn+1)); printf 'DIR\t%s\n' "$lk" >> "$B"
    else
      case "$(basename "$lk")" in
        $muster)
          if [ "$modus" = intree ]; then printf '%s\n' "$lk" >> "$P"
          else mustn=$((mustn+1)); printf 'MUSTER\t%s\n' "$lk" >> "$B"; fi ;;
        *) sonst=$((sonst+1)) ;;
      esac
    fi
  done < "$L"
  # (2b) IMP-225: classify pattern links (intree mode only) in ONE pass.
  if [ -s "$P" ]; then
    set +e
    python3 - "$P" "$baum" "$muster" > "$V" 2>"$WORK/w19-$quelle.pyerr" <<'PY'
import fnmatch, os, stat, sys
sys.stdout.reconfigure(errors='surrogateescape')
lst, root, pat = sys.argv[1], sys.argv[2], sys.argv[3]
rroot = os.path.realpath(root)
with open(lst, 'rb') as fh:
    links = [os.fsdecode(x) for x in fh.read().split(b'\n') if x]
for lk in links:
    try:
        st = os.stat(lk)                      # follows the link; dangling/cycle -> OSError
    except FileNotFoundError:
        print('DANGLING\t%s\t%s' % (lk, os.readlink(lk))); continue
    except OSError as e:
        print('UNRESOLVABLE\t%s\t%s' % (lk, e.strerror)); continue
    tgt = os.path.realpath(lk)
    if not stat.S_ISREG(st.st_mode):
        print('NONREGULAR\t%s\t%s' % (lk, tgt)); continue
    if tgt == rroot or os.path.commonpath([rroot, tgt]) != rroot:
        print('OUTSIDE\t%s\t%s' % (lk, tgt)); continue
    if not fnmatch.fnmatchcase(os.path.basename(tgt), pat):
        print('PATTERN_MISMATCH\t%s\t%s' % (lk, tgt)); continue
    print('TOLERATED\t%s\t%s' % (lk, tgt))
PY
    crc=$?
    set -e
    if [ "$crc" -ne 0 ] || [ "$(wc -l < "$V" | tr -d ' ')" != "$(wc -l < "$P" | tr -d ' ')" ]; then
      { echo "ABORT(19): symlink classification FAILED in the scan tree of $quelle (python_rc=$crc)"
        echo "  tree=$baum"
        head -3 "$WORK/w19-$quelle.pyerr" | sed 's/^/  python: /'
      } >&2
      exit 19
    fi
    while IFS=$'\t' read -r urteil lk ziel; do
      if [ "$urteil" = TOLERATED ]; then tol=$((tol+1))
      else mustn=$((mustn+1)); printf 'MUSTER-%s\t%s -> %s\n' "$urteil" "$lk" "$ziel" >> "$B"; fi
    done < "$V"
  fi
  # (3) Second, different-kind axis: set comparison find vs. find -L.
  #     -L is ONLY counted, NEVER used for the actual collection.
  #     find -L lists every tolerated link as one more -type f path -> n_L = n + tolerated.
  n=$("$FINDBIN"    "$baum" -name "$muster" -type f 2>/dev/null | wc -l | tr -d ' ')
  nL=$("$FINDBIN" -L "$baum" -name "$muster" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$wurzel" = ja ] || [ "$dirn" -gt 0 ] || [ "$mustn" -gt 0 ] || [ "$nL" != "$((n+tol))" ] || [ "$frc" -ne 0 ]; then
    { echo "ABORT(19): symlink in the scan tree of $quelle"
      echo "  tree=$baum"
      echo "  root_is_symlink=$wurzel dir_symlinks=$dirn pattern_symlinks=$mustn other=$sonst find_rc=$frc symlinks_tolerated=$tol"
      echo "  files without -L=$n with -L=$nL (difference=$((nL-n)) invisible files)"
      head -5 "$B" | sed 's/^/  affected: /'
      echo "  MEASUREMENT INCOMPLETE. NOT switched to -L: -L stays silent on cycles (rc=0,"
      echo "  0 stderr) and lists the same file again under every path -> two item_keys."
      echo "  Resolution: list the outsourced tree as its own root in roots.txt,"
      echo "  or replace the symlink with the real directory."
    } >&2
    exit 19
  fi
  if [ "$modus" = intree ]; then
    local zst=symlinkfrei
    if [ "$tol" -gt 0 ]; then
      zst=tolerated
      { echo "NOTE W19 $quelle: $tol in-tree file symlink(s) TOLERATED — not counted; each target is counted once by the normal walk:"
        awk -F'\t' '$1=="TOLERATED"{print "  tolerated: " $2 " -> " $3}' "$V"
      } >&2
    fi
    W19_CERT="${W19_CERT}${quelle}:symlinks=$((dirn+mustn+sonst+tol));dir=$dirn;muster=$mustn;sonstige=$sonst;symlinks_tolerated=$tol;n=$n;n_L=$nL;state=$zst|"
    rcpt "W19 $quelle symlinks=$((dirn+mustn+sonst+tol)) (dir=$dirn muster=$mustn sonstige=$sonst) symlinks_tolerated=$tol n=$n n_L=$nL state=$zst"
    return 0
  fi
  W19_CERT="${W19_CERT}${quelle}:symlinks=$((dirn+mustn+sonst));dir=$dirn;muster=$mustn;sonstige=$sonst;n=$n;n_L=$nL;state=symlinkfrei|"
  rcpt "W19 $quelle symlinks=$((dirn+mustn+sonst)) (dir=$dirn muster=$mustn sonstige=$sonst) n=$n n_L=$nL state=symlinkfrei"
}

# ============================== S0 day window ==============================
PREV=$(python3 -c "import sys,datetime;print(datetime.date.fromisoformat(sys.argv[1])-datetime.timedelta(days=1))" "$D")
python3 - "$D" > "$WORK/win.txt" <<'PY'
import os, sys
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
d = datetime.fromisoformat(sys.argv[1]).replace(tzinfo=ZoneInfo(os.environ['TZ']))
f = '%Y-%m-%dT%H:%M:%SZ'
print(d.astimezone(ZoneInfo('UTC')).strftime(f))
print((d + timedelta(days=1)).astimezone(ZoneInfo('UTC')).strftime(f))
PY
WSTART=$(sed -n 1p "$WORK/win.txt"); WEND=$(sed -n 2p "$WORK/win.txt")
if [ "$FAULT" = "d" ]; then WSTART=""; fi
RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
if [ -z "$WSTART" ] || [ -z "$WEND" ]; then
  echo "ABORT(2): window bounds empty (WSTART='$WSTART' WEND='$WEND')" >&2; exit 2; fi
if ! [[ "$WSTART" =~ $RE ]] || ! [[ "$WEND" =~ $RE ]]; then
  echo "ABORT(2): window format invalid" >&2; exit 2; fi
if ! [[ "$WSTART" < "$WEND" ]]; then echo "ABORT(2): window not ascending" >&2; exit 2; fi
rcpt "S0 tz=$TZ window=[$WSTART,$WEND)"

# ============================== S1 Preflight ==============================
# S1d Roots + Sentinels
NROOTS=0; NSYMROOT=0
: > "$WORK/roots_ok.txt"
while IFS=$'\t' read -r root sentinel; do
  [ -n "$root" ] || continue
  if [ ! -d "$root" ]; then echo "ABORT(3): root missing: $root" >&2; exit 3; fi
  if [ ! -r "$sentinel" ]; then echo "ABORT(3): sentinel unreadable: $sentinel (volume not mounted?)" >&2; exit 3; fi
  # W19 on the roots axis: DELIBERATELY NO tree traversal, only root identity.
  # Reasoning measured: the git axis is STRUCTURALLY IMMUNE to subtree blindness —
  # a directory symlink sits in the tree as an entry with mode 120000 and is not
  # traversed (`git ls-files -s mirror` -> "120000 ... mirror"); every file appears
  # exactly once under its real path. The full guard would also be untenable here
  # (one repo alone: 14252 symlinks in node_modules -> daily abort).
  # What actually breaks on THIS axis is the COUNT BASIS: if the root is addressed via a
  # symlink, the relpath hangs off the access path and the same file would get two
  # item_keys — the collapsing of worktrees/clones would silently fail.
  rp=$(cd "$root" && pwd -P)
  if [ -L "$root" ] || [ "$rp" != "$root" ]; then
    NSYMROOT=$((NSYMROOT+1))
    { echo "ABORT(19): root addressed via a symlink — count basis not unique"
      echo "  root=$root"; echo "  realpath=$rp"
      echo "  The relpath hangs off the access path; the same file would get two item_keys."
      echo "  Resolution: enter the resolved path in roots.txt ($rp)."
      echo "  KNOWN FRICTION: /var and /tmp are themselves symlinks to /private/* on macOS."
      echo "  A root beneath those triggers this even though the situation is harmless. Deliberately"
      echo "  NOT relaxed via a special case — an exception for /private would be the first"
      echo "  breach of exactly the rule that carries this guard."
    } >&2
    exit 19
  fi
  echo "$root" >> "$WORK/roots_ok.txt"; NROOTS=$((NROOTS+1))
done < "$ROOTS"
if [ "$NROOTS" -eq 0 ]; then echo "ABORT(3): roots.txt empty" >&2; exit 3; fi
CERT_S1D="roots=$NROOTS;sentinels=readable;symlink_roots=$NSYMROOT;state=verified"
rcpt "S1d roots_checked=$NROOTS sentinels=readable symlink_roots=$NSYMROOT"

# ============================== S0e SOURCE EPOCHS (MEASURED) =========================
# DEFECT ROOT CAUSE (round 5): every source had exactly TWO states - "present" or "missing",
# and "missing" was always an ABORT. But a source that did NOT YET EXIST on the
# target day is not a measurement error, it's a fact about the world. For every day before
# a source's start, the script therefore aborted BEFORE the git axis even
# ran - even though git is the only axis that exists across the entire time span.
# Epochs are MEASURED (from disk), never assumed.
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
  EPO_QUELLE=measured
  printf 'signals\t%s\ntranskripte\t%s\ndesktop\t%s\n' "$EP_SIG" "$EP_TR" "$EP_DESK" > "$EPO_CACHE"
fi
for e in "signals:$EP_SIG" "transkripte:$EP_TR" "desktop:$EP_DESK"; do
  case "${e#*:}" in
    ????-??-??) : ;;
    *) echo "ABORT(22): source epoch for ${e%%:*} not measurable ('${e#*:}') — without an epoch, 'missing' cannot be distinguished from 'did not exist yet'" >&2; exit 22 ;;
  esac
done
rcpt "S0e epochs signals=$EP_SIG transkripte=$EP_TR desktop=$EP_DESK ($EPO_QUELLE)"

# S1c signal archives D-1 and D (NEVER D+1)
# W19 on the archive axis BEFORE collection.
[ -d "$ARC" ] && w19 "$ARC" "S1c_signals" "signals-*.jsonl.gz"
# FOUR distinguishable states. "empty" != "missing": a valid, content-empty gz
# (50 bytes, gzcat rc=0, 0 lines) made the only guard against a blind
# transcript branch structurally unfireable. Reproduced: EXIT=0, items 79
# instead of 224 (65% undercounting), status DEGRADED like on a healthy day,
# i4_gap=0. Hence empty_verified is TRIP-WORTHY (see ABORT(17)) and never "ok".
CERT_S1C=""; SIG_EMPTY_DAYS=0; SIG_PRE_DAYS=0
for dd in "$PREV" "$D"; do
  f="$ARC/signals-$dd.jsonl.gz"
  if [ ! -f "$f" ]; then
    # BEFORE the epoch: a fact, not a measurement error. Do NOT count as empty_verified —
    # otherwise ABORT(17) (hook/rotation failure) would falsely fire on every old day.
    if [[ "$dd" < "$EP_SIG" ]]; then
      : > "$WORK/sig-$dd.jsonl"; SIG_PRE_DAYS=$((SIG_PRE_DAYS+1))
      CERT_S1C="${CERT_S1C}${dd}:epoche=$EP_SIG;state=not_yet_existing|"
      rcpt "S1c signals-$dd state=not_yet_existing (source starts $EP_SIG)"
      continue
    fi
    echo "ABORT(5): archive MISSING (state=missing): signals-$dd.jsonl.gz (day is IN the epoch starting $EP_SIG)" >&2; exit 5
  fi
  set +e
  gzcat "$f" > "$WORK/sig-$dd.jsonl" 2>"$WORK/gz-$dd.err"; GZ_RC=$?
  set -e
  NZ=$(wc -l < "$WORK/sig-$dd.jsonl" | tr -d ' ')
  if [ "$GZ_RC" -ne 0 ]; then
    echo "ABORT(5): archive TRUNCATED (state=truncated) $dd — gzcat_rc=$GZ_RC, $NZ lines before failure; partial output is NOT used" >&2; exit 5; fi
  if [ "$NZ" -eq 0 ]; then ST=empty_verified; SIG_EMPTY_DAYS=$((SIG_EMPTY_DAYS+1)); else ST=ok; fi
  CERT_S1C="${CERT_S1C}${dd}:rc=$GZ_RC;zeilen=$NZ;state=$ST|"
  rcpt "S1c signals-$dd rc=$GZ_RC lines=$NZ state=$ST"
done

# S1e manifest D-1 (manual-work baseline)
MAN="$HOME/.claude/logbook/manifests/manifest-$PREV.tsv.gz"
if [ -r "$MAN" ]; then MAN_STATUS=ok; else MAN_STATUS=DEGRADED_missing; fi
rcpt "S1e manifest-$PREV status=$MAN_STATUS"

# S1b desktop
if [ ! -d "$DESK" ]; then DESK_STATUS=MISSING
elif [[ "$D" < "$EP_DESK" ]]; then DESK_STATUS=not_yet_existing
else DESK_STATUS=ok; fi
rcpt "S1b desktop_status=$DESK_STATUS (source starts $EP_DESK)"

# S1a transcripts — positive check BY CONTENT (never mtime), with a READ CERTIFICATE.
# "No error message" is not proof. The original script threw away grep's exit status via
# `|| true`; measured, this let an unreadable file rc=2 AND 11 of 12 hits on stdout
# through — a genuine partial hit that was reported as "ok".
PROJ="$HOME/.claude/projects"
w19 "$PROJ" "S1a_transcripts" "*.jsonl" intree
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
  { echo "ABORT(15): S1a scan INCOMPLETE — grep_rc=$GREP_RC find_rc=$FIND_RC unreadable_files=$NUNREAD of $NALL"
    head -5 "$WORK/unreadable.txt" | sed 's/^/  unreadable: /'
    head -3 "$WORK/grep_s1a.err"  | sed 's/^/  grep: /'
  } >&2
  exit 15
fi
TR_STATE=verified
if [ "$NCAND" -eq 0 ]; then
  if [[ "$D" < "$EP_TR" ]]; then
    TR_STATE=not_yet_existing
    rcpt "S1a 0 transcripts — state=not_yet_existing (source starts $EP_TR)"
  else
    echo "ABORT(4): 0 transcripts for $D — a measurement error, NOT an empty day (files=$NALL, all readable, day is IN the epoch starting $EP_TR)" >&2; exit 4
  fi
fi
# TWO checks, but NOT independent: the census and grep draw their population from
# the same traversal. Only W19 establishes their independence, by making the
# population itself checkable.
CERT_S1A="rc=$GREP_RC;find_rc=$FIND_RC;dateien=$NALL;unlesbar=$NUNREAD;kandidaten=$NCAND;epoche=$EP_TR;state=$TR_STATE"
rcpt "S1a candidates=$NCAND files=$NALL unreadable=$NUNREAD grep_rc=$GREP_RC"
# TEST HOOK (IMP-225): stop right after the S1a receipt so the symlink regression suite
# (scripts/tests/logbook-count-symlink-regression.sh) needs no fixtures for S2+.
# NEVER set in production (the scheduled run does not export it). Exits 99, NOT 0:
# if the variable leaks into a real run (a leftover export, settings.json env,
# env.local.sh sourced above), a truncated run must never look like a pass.
if [ "${LOGBOOK_STOP_AFTER_S1A:-}" = "1" ]; then rcpt "STOP after S1a (LOGBOOK_STOP_AFTER_S1A=1) — test hook, exit 99"; exit 99; fi

# ============================== S2 TOOL MAP (declared, not guessed) ==============
# Classes: W = write tool (column 3 = target parameter in priority order)
#          B = bash-like (column 3 = command parameter) -> goes through qb.py
#          R = known AND demonstrably does not write to the filesystem
# A tool that is NOT listed here must not silently return 0: if its input contains
# a path-like value, it lands BY NAME in the mandatory bucket unbekanntes_werkzeug_mit_pfad.
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
# Regex fallback for name-variable MCP write tools (suffix convention)
cat > "$WORK/toolmap_re.tsv" <<'MAPEOF'
write_file|edit_file|create_text_file	W	path,file_path,relative_path
MAPEOF
NMAP=$(wc -l < "$WORK/toolmap.tsv" | tr -d ' ')
rcpt "S2 tool_map_entries=$NMAP classes=W/B/R"

# All declared parameter names (superset) — jq extracts exactly these keys.
PKEYS='file_path,path,filename,notebook_path,source,destination,filePath,relative_path,local_path,paths,files,project,url,query'
# KNOWN = every mapped tool name, each framed by U+001F (unit separator) on both
# sides; S3 and S6 test membership with contains("\u001f"+name+"\u001f"). The
# separator is written as an ESCAPE (chr(31) / "\u001f"), never as a raw control
# byte: the earlier version carried raw NUL bytes here, bash drops NULs when it
# reads a script, so KNOWN became all names run together and the S3 check degraded
# into a substring match ("Writ" counted as known), while S6 used a space and never
# matched at all. Regression: scripts/tests/logbook-count-desktop-regression.sh (k, l).
KNOWN=$(cut -f1 "$WORK/toolmap.tsv" | python3 -c "import sys;print(chr(31)+chr(31).join(l for l in sys.stdin.read().split(chr(10)) if l)+chr(31))")

# ============================== S3 Events ==============================
# iv = declared parameter values (parameter map).  sc = path-like string leaves
# ONLY for tools the map doesn't know (mandatory-bucket candidates).
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
             sc:( if ($known|contains("\u001f"+$t.name+"\u001f")) then []
                  else [ $t.input | .. | strings | select(length < 4096) ] | .[0:40] end )} ]}
  | select((.tu|length) > 0)' \
  < <(tr '\n' '\0' < "$WORK/cand.txt") > "$WORK/events.jsonl"
NEV=$(wc -l < "$WORK/events.jsonl" | tr -d ' ')
rcpt "S3 event_lines=$NEV"

# ---- Extractor: map -> (id, target path) + mandatory bucket -------------------
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
# path-like: absolute, OR relative with a directory separator AND an extension. No URLs.
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

# ---- qb.py: bash write-target recognizer (defined BEFORE S6 because the desktop branch needs it)
cat > "$WORK/qb.py" <<'PYEOF'
import sys, json, os, re, shlex
# Write operators, systematically checked (defect B/3):
#   cp mv install rsync ln  -> last argument
#   dd of=TARGET             -> explicit target
#   touch                    -> all non-flag arguments (creation = write)
#   tee [-a]                 -> first non-flag argument
#   sed -i                   -> last argument
#   > >> >| &> 2>            -> redirect target (also covers heredoc `cat > f <<EOF`)
#   mkdir -p                 -> directory target (evidence Bdir)
#   python open(p,'w'/'a'/'x'), pathlib write_text/write_bytes -> regex on the raw command
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
                # ORDER IS NORMATIVE: check the STANDALONE operator form first.
                # Otherwise `>>?(.+)` eats the token '>>' itself (the second '>' as a "path")
                # and the append-redirect is silently swallowed — this actually happened in testing.
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

# ============================== S4 Subtract failures ==============================
# Error IDs are collected across ALL lines of the candidate files (not window-filtered):
# a tool_result can arrive after the window ends. Safe direction = subtract more.
xargs -0 -n 40 jq -r 'select((.message.content?|type)=="array") | .message.content[]
   | select(.type=="tool_result" and .is_error==true) | .tool_use_id' \
   < <(tr '\n' '\0' < "$WORK/cand.txt") | sort -u > "$WORK/failed_ids.txt"
NFAIL=$(wc -l < "$WORK/failed_ids.txt" | tr -d ' ')

python3 "$WORK/extract.py" "$WORK/toolmap.tsv" "$WORK/toolmap_re.tsv" "$WORK/events.jsonl" \
        "$WORK/pairs3.tsv" "$WORK/unknown_qt.tsv" 2> "$WORK/extract_qt.meta"
cut -f1,2 "$WORK/pairs3.tsv" | sort -u > "$WORK/pairs.tsv"
NPAIRS=$(wc -l < "$WORK/pairs.tsv" | tr -d ' ')
rcpt "S3b map_hits=$NPAIRS unknown_tools=$(jq -r '.unknown_tools' "$WORK/extract_qt.meta") unknown_paths=$(jq -r '.unknown_paths' "$WORK/extract_qt.meta")"

if [ "$FAULT" = "c" ]; then : > "$WORK/failed_ids.txt"; NFAIL=0; fi
awk -F'\t' -v PF="$WORK/failed_ids.txt" '
  FILENAME==PF { bad[$1]=1; next } !($1 in bad)' "$WORK/failed_ids.txt" "$WORK/pairs.tsv" \
  > "$WORK/pairs_ok.tsv"
NOK=$(wc -l < "$WORK/pairs_ok.tsv" | tr -d ' ')
# R4 filter self-defense: an empty pattern file must NEVER reduce.
if [ "$NFAIL" -eq 0 ] && [ "$NPAIRS" -gt 0 ] && [ "$NOK" -ne "$NPAIRS" ]; then
  echo "ABORT(12): failure filter reduced $NPAIRS -> $NOK with 0 patterns (tool defect)" >&2; exit 12; fi
cut -f2 "$WORK/pairs_ok.tsv" | sort -u > "$WORK/qt_raw.txt"
rcpt "S4 pairs=$NPAIRS error_ids=$NFAIL remaining=$NOK raw_paths=$(wc -l < "$WORK/qt_raw.txt" | tr -d ' ')"

# ============================== S6 Desktop raw paths ==============================
: > "$WORK/qd_raw.txt"
NAUDIT=0; DESK_FIND_RC=0; DESK_JQ_RC=0; DESK_UNREAD=0; DESK_LINES=0; DESK_UNPARSEABLE=0; DESK_WIN_LINES=0; DESK_WIN_UNPARSEABLE=0; DESK_UNDATED=0
# IMP-223: the desktop app writes the occasional audit.jsonl line that jq rejects
# ("Invalid \uXXXX\uXXXX surrogate pair escape" — a lone UTF-16 high surrogate,
# e.g. a tool_result text truncated between the two halves of a surrogate pair
# and followed directly by "[TRUNCATED]"). One such line used to abort the whole
# run (5 of 13 daily-docs fails, 2026-09-10..09-21). Such lines are now COUNTED
# (receipt + certificate + summary, never silent) and skipped. Above this share
# the scan counts as genuinely incomplete -> ABORT(16). The share is checked twice:
# over all scanned non-blank lines AND over the lines inside [WSTART,WEND) only.
# Integer percent; the check is unparseable*100 > lines*MAX (exactly 1% passes).
# Decision record: docs/adr/0004-desktop-audit-lone-surrogate-tolerance.md
DESK_UNPARSEABLE_MAX_PCT=1
if [ "$DESK_STATUS" = "ok" ]; then
  w19 "$DESK" "S1b_desktop" "audit.jsonl"
  set +e
  "$FINDBIN" "$DESK" -name audit.jsonl -print0 > "$WORK/audits.z" 2>"$WORK/desk_find.err"; DESK_FIND_RC=$?
  set -e
  NAUDIT=$(tr -dc '\0' < "$WORK/audits.z" | wc -c | tr -d ' ')
  # Readability census like S1a — a partial failure must not pass as "ok:N".
  while IFS= read -r -d '' af; do [ -r "$af" ] || DESK_UNREAD=$((DESK_UNREAD+1)); done < "$WORK/audits.z"
  if [ "$DESK_FIND_RC" -ne 0 ] || [ "$DESK_UNREAD" -gt 0 ]; then
    echo "ABORT(16): S1b/S6 desktop scan INCOMPLETE — find_rc=$DESK_FIND_RC unreadable=$DESK_UNREAD of $NAUDIT" >&2; exit 16; fi
  if [ "$NAUDIT" -gt 0 ]; then
    # Bring desktop events into the SAME shape as S3 (no cwd in audit.jsonl ->
    # relative targets stay unresolvable and are reported as such, not guessed).
    # TOLERANT READER (IMP-223): a python pre-pass (desk_lines.py) parses every
    # line on its own, passes the ORIGINAL bytes of every line jq will accept on to
    # the unchanged jq filter, and counts the rest (file:line of the first ones in
    # desk_lines.meta). NOT `jq -R 'fromjson?'`: measured on the real audit files
    # (jq-1.7.1), -R mode corrupts multibyte UTF-8 characters at ~4 KiB buffer
    # boundaries (7 of 8322 events differed, "€" -> U+FFFD), and it glues the last
    # line of a file without a trailing newline onto the next file's first line.
    # An unreadable file makes the pre-pass exit non-zero -> ABORT(16); any line
    # the pre-pass lets through but jq still rejects -> jq rc != 0 -> ABORT(16).
    cat > "$WORK/desk_lines.py" <<'PYEOF'
import sys, json, re
listfile, metafile, wstart, wend = sys.argv[1:5]
# IN-WINDOW share (review finding #5): the corpus-wide share alone is measured over
# every audit file ever written (~159k lines), so 1% would let ~1.6k unparseable
# lines through — enough to swallow a whole day. Every line is therefore also
# classified against the SAME window as the jq filter (top-level "timestamp",
# fractional seconds dropped, WSTART <= ts < WEND). A line json cannot parse has no
# top level, so its FIRST raw "timestamp":"YYYY-MM-DDTHH:MM:SS is used; a rejected
# line with no such prefix is counted as undated (it still weighs on the corpus share).
TS_RAW = re.compile(rb'"timestamp"\s*:\s*"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})')
TS_STR = re.compile(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})')
def in_window(ts19):
    return ts19 is not None and wstart <= ts19 + 'Z' < wend
# A lone high surrogate can only come from a \uD8xx..\uDBxx escape (raw UTF-8
# surrogate bytes are invalid UTF-8 and decode to U+FFFD). The tree walk below is
# the expensive part (~25 s on 159k lines), so it only runs on lines matching this
# superset gate; the walk then decides.
HIGH_ESC = re.compile(rb'\\u[dD][89abAB][0-9a-fA-F]{2}')
paths = [p for p in open(listfile, 'rb').read().decode('utf-8', 'surrogateescape').split('\0') if p]
def lone_high(x):
    # json.loads combines a valid \uD8xx\uDCxx pair into ONE code point, so any
    # remaining high surrogate is lone — exactly what jq-1.7.1 rejects ("Invalid
    # \uXXXX\uXXXX surrogate pair escape"). A lone LOW surrogate jq accepts (U+FFFD).
    if isinstance(x, str): return any('\ud800' <= c <= '\udbff' for c in x)
    if isinstance(x, dict): return any(lone_high(k) or lone_high(v) for k, v in x.items())
    if isinstance(x, list): return any(lone_high(v) for v in x)
    return False
def ts_of(ev, raw):
    # Parsed line: exactly the field jq filters on. Unparsed line: raw prefix.
    if ev is not None:
        t = ev.get('timestamp') if isinstance(ev, dict) else None
        m = TS_STR.match(t) if isinstance(t, str) else None
        return m.group(1) if m else None
    m = TS_RAW.search(raw)
    return m.group(1).decode('ascii') if m else None
nlines = nbad = wlines = wbad = undated = 0; first = []; out = sys.stdout.buffer
for p in paths:
    try:
        fh = open(p, 'rb')
    except OSError as err:
        print('desk_lines: cannot open %s: %s' % (p, err), file=sys.stderr); sys.exit(3)
    with fh:
        for ln, raw in enumerate(fh, 1):
            if not raw.strip(): continue
            nlines += 1
            ev = None
            try:
                ev = json.loads(raw.decode('utf-8', 'replace'))
                ok = not (HIGH_ESC.search(raw) and lone_high(ev))
            except ValueError:
                ok = False
            ts = ts_of(ev, raw)
            if in_window(ts): wlines += 1
            if ok:
                out.write(raw if raw.endswith(b'\n') else raw + b'\n')
            else:
                nbad += 1
                if ts is None: undated += 1
                elif in_window(ts): wbad += 1
                if len(first) < 3: first.append('%s:%d' % (p, ln))
with open(metafile, 'w') as fh:
    json.dump({'files': len(paths), 'lines': nlines, 'unparseable': nbad,
               'window_lines': wlines, 'window_unparseable': wbad,
               'undated_unparseable': undated, 'first': first}, fh)
PYEOF
    set +e
    python3 "$WORK/desk_lines.py" "$WORK/audits.z" "$WORK/desk_lines.meta" "$WSTART" "$WEND" 2>"$WORK/desk_lines.err" \
    | jq -c --arg s "$WSTART" --arg e "$WEND" --arg pk "$PKEYS" --arg known "$KNOWN" '
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
                 sc:( if ($known|contains("\u001f"+$t.name+"\u001f")) then []
                      else [ $t.input | .. | strings | select(length < 4096) ] | .[0:40] end )} ]}
      | select((.tu|length) > 0)' \
      2>"$WORK/desk_jq.err" > "$WORK/devents.jsonl"; DESK_PIPE_RC=("${PIPESTATUS[@]}")
    set -e
    DESK_PRE_RC=${DESK_PIPE_RC[0]}; DESK_JQ_RC=${DESK_PIPE_RC[1]}
    if [ "$DESK_PRE_RC" -ne 0 ] || [ ! -s "$WORK/desk_lines.meta" ]; then
      { echo "ABORT(16): S6 desktop pre-pass FAILED (rc=$DESK_PRE_RC) — scan incomplete, not silent undercounting"
        head -3 "$WORK/desk_lines.err" | sed 's/^/  desk_lines: /'; } >&2
      exit 16
    fi
    if [ "$DESK_JQ_RC" -ne 0 ]; then
      { echo "ABORT(16): S6 desktop jq FAILED (rc=$DESK_JQ_RC) — partial failure, not silent undercounting"
        head -3 "$WORK/desk_jq.err" | sed 's/^/  jq: /'; } >&2
      exit 16
    fi
    DESK_LINES=$(jq -r '.lines' "$WORK/desk_lines.meta")
    DESK_UNPARSEABLE=$(jq -r '.unparseable' "$WORK/desk_lines.meta")
    DESK_WIN_LINES=$(jq -r '.window_lines' "$WORK/desk_lines.meta")
    DESK_WIN_UNPARSEABLE=$(jq -r '.window_unparseable' "$WORK/desk_lines.meta")
    DESK_UNDATED=$(jq -r '.undated_unparseable' "$WORK/desk_lines.meta")
    NDFILES=$(jq -r '.files' "$WORK/desk_lines.meta")
    if [ "$NDFILES" -ne "$NAUDIT" ]; then
      echo "ABORT(16): S6 desktop pre-pass read $NDFILES of $NAUDIT audit files" >&2; exit 16; fi
    if [ "$DESK_UNPARSEABLE" -gt 0 ]; then
      { echo "WARN S6 desktop: $DESK_UNPARSEABLE of $DESK_LINES lines unparseable (skipped, counted; in window: $DESK_WIN_UNPARSEABLE of $DESK_WIN_LINES, undated: $DESK_UNDATED), first:"
        jq -r '.first[] | "  " + .' "$WORK/desk_lines.meta"; } >&2
    fi
    # Two shares, both must hold: corpus-wide (all audit lines) AND in-window (only
    # the lines this run actually counts). The corpus share alone dilutes a bad day.
    if [ $((DESK_UNPARSEABLE * 100)) -gt $((DESK_LINES * DESK_UNPARSEABLE_MAX_PCT)) ]; then
      echo "ABORT(16): S6 desktop scan INCOMPLETE — unparseable=$DESK_UNPARSEABLE of $DESK_LINES lines exceeds ${DESK_UNPARSEABLE_MAX_PCT}% (DESK_UNPARSEABLE_MAX_PCT)" >&2
      exit 16
    fi
    if [ $((DESK_WIN_UNPARSEABLE * 100)) -gt $((DESK_WIN_LINES * DESK_UNPARSEABLE_MAX_PCT)) ]; then
      echo "ABORT(16): S6 desktop scan INCOMPLETE — in-window unparseable=$DESK_WIN_UNPARSEABLE of $DESK_WIN_LINES window lines [$WSTART,$WEND) exceeds ${DESK_UNPARSEABLE_MAX_PCT}% (DESK_UNPARSEABLE_MAX_PCT; corpus: $DESK_UNPARSEABLE of $DESK_LINES)" >&2
      exit 16
    fi
    python3 "$WORK/extract.py" "$WORK/toolmap.tsv" "$WORK/toolmap_re.tsv" "$WORK/devents.jsonl" \
            "$WORK/dpairs.tsv" "$WORK/unknown_qd.tsv" 2> "$WORK/extract_qd.meta"
    cut -f2 "$WORK/dpairs.tsv" | sort -u > "$WORK/qd_raw.txt"
    # Q_B FOR THE DESKTOP BRANCH — the same recognizer as in the CLI branch (defect B/2).
    python3 "$WORK/qb.py" < "$WORK/devents.jsonl" > "$WORK/qbd_raw.tsv" 2> "$WORK/qbd.meta"
  fi
fi
[ -f "$WORK/qbd_raw.tsv" ] || : > "$WORK/qbd_raw.tsv"
[ -f "$WORK/qbd.meta" ] || echo '{"ncmds":0,"unparsed":0}' > "$WORK/qbd.meta"
[ -f "$WORK/unknown_qd.tsv" ] || : > "$WORK/unknown_qd.tsv"
CERT_S1B="status=$DESK_STATUS;find_rc=$DESK_FIND_RC;jq_rc=$DESK_JQ_RC;audits=$NAUDIT;unlesbar=$DESK_UNREAD;lines=$DESK_LINES;unparseable=$DESK_UNPARSEABLE;window_lines=$DESK_WIN_LINES;window_unparseable=$DESK_WIN_UNPARSEABLE;undated_unparseable=$DESK_UNDATED;state=$( [ "$DESK_STATUS" = ok ] && echo verified || echo degraded_missing )"
rcpt "S6 desktop_status=$DESK_STATUS audit_files=$NAUDIT lines=$DESK_LINES unparseable=$DESK_UNPARSEABLE raw_paths=$(wc -l < "$WORK/qd_raw.txt" | tr -d ' ') desktop_bash_calls=$(jq -r '.ncmds' "$WORK/qbd.meta") desktop_bash_targets=$(awk -F'\t' '$1=="F"' "$WORK/qbd_raw.tsv" | wc -l | tr -d ' ') window_lines=$DESK_WIN_LINES window_unparseable=$DESK_WIN_UNPARSEABLE undated_unparseable=$DESK_UNDATED"
# Test hook (IMP-223, scripts/tests/logbook-count-desktop-regression.sh): stop right
# after the S6 receipt so the desktop step can be exercised in isolation against a
# scratch $HOME. Unset in production — the scheduler never sets it. Exits 99, NOT 0,
# so a leaked variable can never turn a truncated run into an apparent pass.
if [ "${LOGBOOK_STOP_AFTER_S6:-}" = "1" ]; then rcpt "STOP after S6 (LOGBOOK_STOP_AFTER_S6=1) — test hook, exit 99"; exit 99; fi

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

    workcopy is an ATTRIBUTE, not part of the key. The key is formed only
    above, from <repo_id>::<relpath>. (The earlier name 'workcopy_id' still
    carried the old key semantics and has therefore been removed.)
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

# COUNT BASIS: REPO IDENTITY (user decision 1, binding).
# item_key := <repo_id>::<relpath> for git-managed files, fs::<path> otherwise.
# The work copy is an ATTRIBUTE (column 9), NEVER the key. This collapses
# worktrees AND clones onto ONE key; the A<->B sync stays visible via the
# attribute (workcopies[]), without a file counting twice.
# Output columns: dec key flag cat repo_id worktree src raw workcopy
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

# ---- Pass 1: Q_T + Q_D (+ CANARY for S8) --------------------------------
CANARY="/Volumes/<canary>/CANARY-$D.md"
{ awk '{print "T\t" $0}' "$WORK/qt_raw.txt"
  awk '{print "D\t" $0}' "$WORK/qd_raw.txt"
  if [ "$FAULT" != "f" ]; then echo -e "C\t$CANARY"; fi
} > "$WORK/pass1.in"
python3 "$WORK/canon.py" < "$WORK/pass1.in" > "$WORK/pass1.tsv"
if [ ! -f "$WORK/pass1.tsv" ]; then echo "ABORT(9): sink pass1.tsv not written" >&2; exit 9; fi
if [ ! -s "$WORK/pass1.tsv" ]; then echo "ABORT(9): pass1.tsv empty despite input" >&2; exit 9; fi

awk -F'\t' '($1=="keep"||$1=="rescued") && $7=="T" {print $2}' "$WORK/pass1.tsv" | sort -u > "$WORK/qt.txt"
awk -F'\t' '($1=="keep"||$1=="rescued") && $7=="D" {print $2}' "$WORK/pass1.tsv" | sort -u > "$WORK/qd.txt"
awk -F'\t' '($1=="keep"||$1=="rescued") && $7=="C" {print $2}' "$WORK/pass1.tsv" | sort -u > "$WORK/canary.txt"
NQT=$(wc -l < "$WORK/qt.txt" | tr -d ' '); NQD=$(wc -l < "$WORK/qd.txt" | tr -d ' ')
rcpt "S5 Q_T=$NQT Q_D=$NQD"

# ============================== S7d Q_B (bash write targets) ==============================
python3 "$WORK/qb.py" < "$WORK/events.jsonl" > "$WORK/qb_raw.tsv" 2> "$WORK/qb.meta"
NBASH=$(jq -r '.ncmds' "$WORK/qb.meta"); NBUNPARSED=$(jq -r '.unparsed' "$WORK/qb.meta")
NBASHD=$(jq -r '.ncmds' "$WORK/qbd.meta")
# The CLI and desktop branches run through the SAME recognizer and are merged here.
cat "$WORK/qb_raw.tsv" "$WORK/qbd_raw.tsv" > "$WORK/qb_all.tsv"
awk -F'\t' '$1=="F"{print "B\t" $2}' "$WORK/qb_all.tsv" | sort -u > "$WORK/qb_files.in"
awk -F'\t' '$1=="DIR"{print $2}' "$WORK/qb_all.tsv" | sort -u > "$WORK/qb_dirs.txt"
awk -F'\t' '$1=="F"{print $3}' "$WORK/qb_all.tsv" | sort | uniq -c | sort -rn | awk '{printf "%s:%s ", $2, $1}' > "$WORK/qb_ops.txt"
rcpt "S7d bash_calls=$NBASH(+desktop $NBASHD) unparseable=$NBUNPARSED qb_file_targets=$(wc -l < "$WORK/qb_files.in" | tr -d ' ') qb_dir_targets=$(wc -l < "$WORK/qb_dirs.txt" | tr -d ' ') ops=[$(cat "$WORK/qb_ops.txt")]"

# ============================== S7c Q_G (git content proof) ==============================
# Repo coverage = roots.txt  UNION  work copies derived from Q_T/Q_D.
# DEFECT ROOT CAUSE 2 (round 5): the repo set was roots.txt UNION the work
# copies derived from Q_T/Q_D. For every day BEFORE the transcript epoch the
# second term contributes nothing — the git axis then saw only the 3 roots and
# was structurally blind for every other repo. Measured: on 2026-01-15 all
# commits sit in a repo that doesn't appear in roots.txt. Hence a third,
# source-independent axis: filesystem discovery via LOGBOOK_GIT_ROOTS (tree
# roots, not repos).
: > "$WORK/repos_disc.txt"
GITROOTS="${LOGBOOK_GIT_ROOTS:-}"
NDISC=0
if [ -n "$GITROOTS" ] && [ -r "$GITROOTS" ]; then
  while IFS= read -r tr0; do
    [ -n "$tr0" ] || continue
    case "$tr0" in \#*) continue ;; esac
    if [ ! -d "$tr0" ]; then
      echo "ABORT(23): git discovery root missing: $tr0 (volume not mounted?) — a silently skipped root is silent undercounting" >&2; exit 23; fi
    "$FINDBIN" "$tr0" -maxdepth "${LOGBOOK_GIT_DEPTH:-5}" -type d -name .git -not -path '*/node_modules/*' 2>/dev/null \
      | while IFS= read -r gd; do dirname "$gd"; done
  done < "$GITROOTS" | sort -u > "$WORK/repos_disc.txt"
  NDISC=$(wc -l < "$WORK/repos_disc.txt" | tr -d ' ')
fi
{ cat "$WORK/roots_ok.txt" "$WORK/repos_disc.txt"
  # Work copy now comes from column 9 (attribute), no longer from the key.
  awk -F'\t' '($1=="keep"||$1=="rescued") && $9!="-" && $9!="" {print $9}' "$WORK/pass1.tsv"
} | sort -u > "$WORK/repos_cand.txt"
rcpt "S7b git_discovery roots=$( [ -r "${GITROOTS:-/nonexistent}" ] && wc -l < "$GITROOTS" | tr -d ' ' || echo 0) repos_found=$NDISC"
# ABORT(24): a day BEFORE the transcript epoch has, by construction, no T/D/signals
# axis (see S0e). If git discovery is then also empty (LOGBOOK_GIT_ROOTS not set or
# 0 repos found), NO axis is viable anymore — an "items=0" would be indistinguishable
# from "not measured". This is the silent zero-count the guard is meant to prevent.
if [ "$TR_STATE" != "verified" ] && [ "$NDISC" -eq 0 ]; then
  echo "ABORT(24): day is before the transcript epoch (starting $EP_TR) AND no discovery repos found (LOGBOOK_GIT_ROOTS not set or empty) — no viable axis covers this day" >&2
  exit 24
fi
# IMPORTANT (conflict resolution A): a commit belongs to HISTORY, not the work copy.
# Q_G is therefore scanned EXACTLY ONCE PER repo_id — otherwise a clone (A and B)
# would count every commit twice.
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
    # NO --since/--until: both filter on the COMMITTER-date axis, which a later
    # rebase resets to the rebase day while the author date stays put. For the
    # backfill that's exactly the normal case. Filtering is therefore done in
    # Python on (author date OR committer date) == target day.
    # This axis reads EXCLUSIVELY the commit history — never the reflog. It is
    # therefore independent of gc.reflogExpire (90 days) and covers old days.
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
# STRICT wins: a file that is strict in ONE commit of the day is strict —
# even if another commit of the same day makes it ambiguous.
awk -F'\t' '$1=="STRICT"{print $2 "/" $4}' "$WORK/qg_raw.tsv" | sort -u > "$WORK/g_strict_paths.txt"
awk -F'\t' '$1=="AMBIG"{print $2 "/" $4}'  "$WORK/qg_raw.tsv" | sort -u > "$WORK/g_ambig_all.txt"
awk -v PF="$WORK/g_strict_paths.txt" 'FILENAME==PF{s[$0]=1;next} !($0 in s)' \
  "$WORK/g_strict_paths.txt" "$WORK/g_ambig_all.txt" > "$WORK/g_ambig_paths.txt"
awk '{print "G\t" $0}' "$WORK/g_strict_paths.txt" > "$WORK/qg_strict.in"
awk '{print "g\t" $0}' "$WORK/g_ambig_paths.txt"  > "$WORK/qg_ambig.in"
rcpt "S7c repo_ids=$NREPO work_copies=$NREPO_WC merge_commits=$NMERGE g_strict=$(wc -l < "$WORK/qg_strict.in" | tr -d ' ') g_ambig=$(wc -l < "$WORK/qg_ambig.in" | tr -d ' ')"

# ---- Pass 2: Q_B + Q_G (strict + ambig) ---------------------------------
cat "$WORK/qb_files.in" "$WORK/qg_strict.in" "$WORK/qg_ambig.in" > "$WORK/pass2.in"
if [ -s "$WORK/pass2.in" ]; then
  python3 "$WORK/canon.py" < "$WORK/pass2.in" > "$WORK/pass2.tsv"
else : > "$WORK/pass2.tsv"; fi
# Q_B: weakest evidence class -> strictest admission criterion.
# Only targets that resolve into a known work copy (flag != UNRESOLVED) count.
awk -F'\t' '($1=="keep"||$1=="rescued") && $7=="B" && $3!="UNRESOLVED" {print $2}' "$WORK/pass2.tsv" | sort -u > "$WORK/qb.txt"
awk -F'\t' '($1=="keep"||$1=="rescued") && $7=="B" && $3=="UNRESOLVED" {print $2}' "$WORK/pass2.tsv" | sort -u > "$WORK/qb_unresolved.txt"

# ============================== S12 Q_V (VCS operations) ==============================
# ITS OWN CATEGORY, SEPARATE from items. A VCS operation materializes files into a
# work copy; that is NOT an item (otherwise the number would no longer be invariant
# against work organization: the same code written directly on development vs.
# merged via a feature branch would yield different daily counts). But making it
# disappear is equally wrong — a merge with conflicts is real work. Hence its own metric.
# THREE INDEPENDENT AXES (answer to the common-mode finding):
#   V1 reflog       — resolves `git -C $VAR merge` (the target isn't in the command string)
#   V2 transcript   — sees `merge --no-commit` (no HEAD movement, no reflog entry)
#   V3 merge-commit — `git diff <sha>^1 <sha>`, NEVER `diff-tree` (that returns 0 for merges)
# No single axis covers the day completely; that is measured, not assumed.
cat > "$WORK/qv2.py" <<'QVEOF'
#!/usr/bin/env python3
"""Q_V — VCS operations as their own category (v3.3).

Three INDEPENDENT axes, union on op_key:
  V1 reflog   per work copy     -> HEAD-moving ops (also outside Claude)
  V2 transcript (Bash)          -> invoked commands, even without HEAD movement
  V3 merge-commits (Q_G)        -> merges that produced a merge commit

Output: JSON  {vcs_operationen:[...], vcs_materialisiert:[repo_id::relpath], zaehler:{}}
Writes ONLY to stdout. No mutation.
"""
import json, os, re, shlex, subprocess, sys, datetime as dt
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

DAY = sys.argv[1]
ROOTS = sys.argv[2]
TZ = ZoneInfo(os.environ["TZ"])  # IMP-219: system timezone instead of a hardcoded name
d = datetime.strptime(DAY, "%Y-%m-%d")
LO = datetime(d.year, d.month, d.day, tzinfo=TZ)
HI = LO + dt.timedelta(days=1)
assert LO < HI
LOU, HIU = LO.astimezone(timezone.utc), HI.astimezone(timezone.utc)

def git(wc, *a):
    r = subprocess.run(["git","-C",wc,*a], capture_output=True, text=True)
    return r.returncode, r.stdout.strip()

# ---------- Work copies + repo_id ----------
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
# Only WORK-COPY-writing selectors; "commit:" moves HEAD but does NOT write
# the work copy -> excluded.
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
        # Predecessor = next reflog line (older)
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

# ---------- V3: merge commits in the window ----------
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

# ---------- V2: transcripts ----------
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

# Attach V2 to V1/V3 (time window +/- 15 min, same work copy OR -C target)
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
 "tag": DAY, "tz": TZ.key,
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
  { echo "ABORT(21): S12/Q_V FAILED (rc=$QV_RC) — VCS axis not evaluable"
    head -5 "$WORK/qv2.err" | sed 's/^/  qv2: /'; } >&2
  exit 21
fi
jq -r '.vcs_materialisiert[]' "$WORK/vcs.json" | sort -u > "$WORK/vcs_materialisiert.txt"
NVCS=$(jq -r '.zaehler.operationen' "$WORK/vcs.json")
NVCSMAT=$(wc -l < "$WORK/vcs_materialisiert.txt" | tr -d ' ')
rcpt "S12 vcs_operations=$NVCS files_materialized=$NVCSMAT axes=$(jq -c '.zaehler.achsen' "$WORK/vcs.json") dryrun_discarded=$(jq -r '.zaehler.dryrun_verworfen' "$WORK/vcs.json")"

# Union + absorption in ONE deterministic step (conflict A + B).
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

# COUNT BASIS REPO IDENTITY: work-copy evidence and git content proof share
# ONE key space (<repo_id>::<relpath>). The former three identity concepts
# (item=work copy, absorption=repo, collapse=repo-without-worktree) thereby fall
# into ONE axis: "absorption" is no longer a special rule, just the ordinary
# union on the key. It is now reported only as a METRIC.
# 1) Work-copy items (T, D, B); workcopies is carried along as an ATTRIBUTE.
items = {}             # key -> set(evidence)
workcopies = {}        # key -> set(workcopy)
qb_ok = set(lines('qb.txt'))
wc_keys = set()        # keys with work-copy evidence (for the absorption metric)
for c in rows('pass1.tsv') + rows('pass2.tsv'):
    dec, key, flag, cat, rid, wt, src, raw, wcp = c[:9]
    if dec not in ('keep', 'rescued'): continue
    if src == 'C': continue                      # canary
    if src in ('G', 'g'): continue               # git handled separately (different evidence class)
    if src == 'B' and key not in qb_ok: continue # drop unresolved bash targets
    items.setdefault(key, set()).add({'T': 'T', 'D': 'D', 'B': 'B'}[src])
    wc_keys.add(key)
    if wcp and wcp != '-': workcopies.setdefault(key, set()).add(wcp)

# 2) B-dir evidence: ambiguous G paths whose directory was a statically resolved bash target
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

# 3) S12 ANTI-DOUBLE-COUNT RULE — the only interlock with vcs_operationen.
# A file that a VCS operation only MATERIALIZED is not an item: the same file
# was already counted on the day it was authored, and the daily total would
# otherwise measure merge frequency instead of work. But it is suppressed ONLY
# when the evidence set is EXCLUSIVELY {Gm}. As soon as T/D/B OR a G-strict from
# a NON-merge commit is present, the file stays an item — Gm then only grows
# into the evidence set. This way a file that was merged AND then edited counts
# exactly ONCE (via its edit event), and a purely materialized one NEVER.
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
# sync_pairs now via the ATTRIBUTE: the same key touched in >=2 work copies.
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

# ============================== S7 Q_M (manual work) ==============================
: > "$WORK/qm.txt"
if [ "$MAN_STATUS" = "ok" ]; then MANUAL_BUCKET=0; MANUAL_PY=0
else MANUAL_BUCKET=null; MANUAL_PY=None; fi
rcpt "S7 Q_M bucket=$MANUAL_BUCKET"

# ============================== S10 union (items.txt comes from union.py) ==============================
if [ ! -f "$WORK/items.txt" ]; then echo "ABORT(9): sink items.txt not written" >&2; exit 9; fi
# "empty despite input" only when there WAS input. A demonstrably work-free old
# day must be allowed to deliver 0 — otherwise "0" is unspeakable by construction.
NIN_PASS=$(awk -F'\t' '($1=="keep"||$1=="rescued") && $7!="C"' "$WORK/pass1.tsv" "$WORK/pass2.tsv" | wc -l | tr -d ' ')
if [ ! -s "$WORK/items.txt" ] && [ "$NIN_PASS" -gt 0 ]; then
  echo "ABORT(9): items.txt empty despite $NIN_PASS input lines" >&2; exit 9; fi
ITEMS=$(wc -l < "$WORK/items.txt" | tr -d ' ')
SHA=$(shasum -a 256 "$WORK/items.txt" | cut -d' ' -f1)

# ============================== S8 self-check ==============================
# (1) CANARY — must survive the entire canonicalization chain
NCAN=$(wc -l < "$WORK/canary.txt" | tr -d ' ')
if [ "$NCAN" -ne 1 ]; then
  echo "ABORT(11): SELF-CHECK DEFECT — canary did not survive the chain ($NCAN)" >&2; exit 11; fi

# (2) Second counter via a different code path
NQT2=$(python3 -c "import sys;print(len(set(l for l in open(sys.argv[1]).read().split('\n') if l)))" "$WORK/qt.txt")
if [ "$NQT" -ne "$NQT2" ]; then echo "ABORT(11): second counter diverges ($NQT vs $NQT2)" >&2; exit 11; fi

# (3) I4 — signals as a hook-failure detector (never counted). Field is .ts, not .timestamp.
set +e
jq -r --arg s "$WSTART" --arg e "$WEND" '
  select(.ts != null)
  | select((.ts|sub("\\.[0-9]+Z$";"Z")) >= $s and (.ts|sub("\\.[0-9]+Z$";"Z")) < $e)
  | (.file // "") | select(. != "")' \
  "$WORK/sig-$PREV.jsonl" "$WORK/sig-$D.jsonl" 2>"$WORK/i4_jq.err" | sort -u > "$WORK/sig_raw.txt"
I4_JQ_RC=${PIPESTATUS[0]}
set -e
if [ "$I4_JQ_RC" -ne 0 ]; then
  echo "ABORT(15): I4 detector jq FAILED (rc=$I4_JQ_RC) — the failure detector itself is blind" >&2; exit 15; fi
awk '{print "S\t" $0}' "$WORK/sig_raw.txt" > "$WORK/sig.in"
if [ -s "$WORK/sig.in" ]; then python3 "$WORK/canon.py" < "$WORK/sig.in" > "$WORK/sig.tsv"
else : > "$WORK/sig.tsv"; fi
awk -F'\t' '($1=="keep"||$1=="rescued"){print $2}' "$WORK/sig.tsv" | sort -u > "$WORK/qsig.txt"
NSIG=$(wc -l < "$WORK/qsig.txt" | tr -d ' ')
awk -v PF="$WORK/qt.txt" 'FILENAME==PF{r[$0]=1;next} !($0 in r)' "$WORK/qt.txt" "$WORK/qsig.txt" > "$WORK/i4_gap.txt"
I4=$(wc -l < "$WORK/i4_gap.txt" | tr -d ' ')
# GUARD DECOUPLING: a guard must not depend on the source it monitors.
# The old condition `NSIG>0 && NQT==0` shared disk, permissions, and rotation
# ($HOME/.claude) with the object it protects — an empty-but-valid archive set
# NSIG=0 and made the only guard against a blind transcript branch structurally
# unfireable.
# Now ABORT(13) fires as soon as Q_T=0 and ONE witness from FOUR independent
# axes is alive. The git axis (repos OUTSIDE $HOME/.claude) shares neither
# directory tree nor rotation nor permissions with the transcript branch — it
# is the source-independent minimum expectation.
NGSTRICT=$(wc -l < "$WORK/g_strict_paths.txt" | tr -d ' ')
NQD_RAW=$(wc -l < "$WORK/qd_raw.txt" | tr -d ' ')
ZEUGEN="signals=$NSIG events=$NEV pairs=$NPAIRS desktop=$NQD_RAW git_strict=$NGSTRICT vcs=$NVCS"
# Epoch-aware: a transcript branch that did NOT EXIST YET on the target day is not blind.
if [ "$TR_STATE" = "verified" ] && [ "$NQT" -eq 0 ] \
   && { [ "$NSIG" -gt 0 ] || [ "$NEV" -gt 0 ] || [ "$NPAIRS" -gt 0 ] \
     || [ "$NQD_RAW" -gt 0 ] || [ "$NGSTRICT" -gt 0 ] || [ "$NVCS" -gt 0 ]; }; then
  echo "ABORT(13): Q_T=0, but independent witnesses are alive ($ZEUGEN) — transcript branch blind" >&2; exit 13; fi
# ABORT(17): a second, independent net. Fires exactly when ABORT(13) does NOT
# (a live transcript branch), and proves a hook/rotation failure.
if [ "$SIG_EMPTY_DAYS" -ge 2 ] && [ "$NEV" -gt 0 ]; then
  echo "ABORT(17): both signals archives state=empty_verified, but $NEV event lines in the window — hook or rotation failure" >&2; exit 17; fi
rcpt "S8 canary=survived second_counter=$NQT2 OK Q_signals=$NSIG i4_gap=$I4 witnesses=[$ZEUGEN]"

# ============================== R6 abort conditions ==============================
if [ "$FAULT" = "e" ]; then ITEMS=0; fi
MAXSRC=$(( NEV + NSIG + NOK + $(wc -l < "$WORK/qd_raw.txt" | tr -d ' ') ))
if [ "$ITEMS" -eq 0 ] && [ "$MAXSRC" -gt 0 ]; then
  echo "ABORT(7): items=0, WHILE sources deliver (events=$NEV signals=$NSIG raw_pairs=$NOK desktop=$(wc -l < "$WORK/qd_raw.txt" | tr -d ' '))" >&2; exit 7; fi
if [ "$ITEMS" -eq 0 ]; then
  rcpt "S10 items=0 — NO source delivers; day is reported as demonstrably work-free (not a measurement error)"; fi
UNIQ_KEPT=$(awk -F'\t' '($1=="keep"||$1=="rescued") && $7=="T"{print $2}' "$WORK/pass1.tsv" | sort -u | wc -l | tr -d ' ')
# ABORT(14) with a CROSS-SOURCE reference size. Previously MIN=UNIQ_KEPT/2, where
# UNIQ_KEPT came exclusively from Q_T: at Q_T=0, MIN was 0 and the threshold
# neutralized itself exactly when the source it protects against failed.
REF=$UNIQ_KEPT; REFQ=Q_T
for pair in "$NGSTRICT:G_strict" "$NQD_RAW:Q_D" "$NSIG:Q_signals"; do
  v=${pair%%:*}; q=${pair##*:}
  if [ "$v" -gt "$REF" ]; then REF=$v; REFQ=$q; fi
done
MIN=$(( REF / 2 ))
if [ "$ITEMS" -lt "$MIN" ]; then
  echo "ABORT(14): items=$ITEMS < 50% of REF=$REF (origin $REFQ)" >&2; exit 14; fi
rcpt "S10 plausibility_reference=$REF source=$REFQ minimum_expectation=$MIN (uniq_kept=$UNIQ_KEPT)"

# ============================== Output ==============================
STATUS=ok; [ "$MAN_STATUS" = "ok" ] || STATUS=DEGRADED
[ "$TR_STATE" = "verified" ] || STATUS=DEGRADED
[ "$SIG_PRE_DAYS" -eq 0 ] || STATUS=DEGRADED
[ "$DESK_STATUS" = "ok" ] || STATUS=DEGRADED
jl() { sort -u | python3 -c "import sys,json;print(json.dumps([l for l in sys.stdin.read().split(chr(10)) if l],ensure_ascii=False))"; }
exclq() { awk -F'\t' -v c="$1" -v s="$2" '$1=="drop" && $7==s && $4 ~ ("^" c) {n++} END{print n+0}' "$WORK/pass1.tsv" "$WORK/pass2.tsv"; }
SYNC=$(wc -l < "$WORK/sync_pairs.txt" | tr -d ' ')

# ---- CERTIFICATE REQUIREMENT (ABORT 18) --------------------------------------------------
# No field in `sources` may carry a literal value — the same rule as
# "no log line without count_basis". A hardcoded "ok" is an assertion,
# not a measurement (the original script had "ok" as a string in the emitter line).
CERT_S1E="manifest=$MAN_STATUS;state=$( [ "$MAN_STATUS" = ok ] && echo verified || echo degraded_missing )"
CERT_S1B="${CERT_S1B};epoche=$EP_DESK"
for cv in "S1a:$CERT_S1A" "S1b:$CERT_S1B" "S1c:$CERT_S1C" "S1d:$CERT_S1D" "S1e:$CERT_S1E"; do
  nm=${cv%%:*}; val=${cv#*:}
  case "$val" in
    '' ) echo "ABORT(18): certificate for $nm is empty — source was not demonstrably read" >&2; exit 18 ;;
    *state=* ) : ;;
    * ) echo "ABORT(18): certificate for $nm without state= : '$val'" >&2; exit 18 ;;
  esac
done

# ---- EVIDENCE_TIER (mandatory field, 1-4) ------------------------------------------------
# 1 = all four axes verified (transcript, desktop, signals, git/VCS)
# 2 = one axis degraded or empty-verified
# 3 = two axes missing; 4 = only ONE axis carries the day anymore (thin day)
TIER=1; TIER_GRUND=""
[ "$DESK_STATUS" = "ok" ]   || { TIER=$((TIER+1)); TIER_GRUND="$TIER_GRUND desktop_$DESK_STATUS;"; }
[ "$SIG_EMPTY_DAYS" -eq 0 ] || { TIER=$((TIER+1)); TIER_GRUND="$TIER_GRUND signals_leer($SIG_EMPTY_DAYS/2);"; }
[ "$SIG_PRE_DAYS" -eq 0 ]   || { TIER=$((TIER+1)); TIER_GRUND="$TIER_GRUND signals_vor_epoche($SIG_PRE_DAYS/2,ab_$EP_SIG);"; }
[ "$TR_STATE" = "verified" ] || { TIER=$((TIER+1)); TIER_GRUND="$TIER_GRUND transkripte_vor_epoche(ab_$EP_TR);"; }
[ "$MAN_STATUS" = "ok" ]    || { TIER=$((TIER+1)); TIER_GRUND="$TIER_GRUND manifest_fehlt;"; }
# reflog retention: gc.reflogExpire is 90 days. For older days, axis V1 drops
# out; this MUST lower the tier, otherwise an old day would look as fully
# measured as a new one. The backfill reaches back 168 days — the older half
# is affected.
AGE=$(python3 -c "import sys,datetime;print((datetime.date.today()-datetime.date.fromisoformat(sys.argv[1])).days)" "$D")
if [ "$AGE" -gt 90 ]; then TIER=$((TIER+1)); TIER_GRUND="$TIER_GRUND reflog_retention_ueberschritten(${AGE}d>90d);"; fi
[ "$TIER" -le 4 ] || TIER=4
[ -n "$TIER_GRUND" ] || TIER_GRUND=" alle_achsen_verifiziert;"
# nicht_erfassbar[] sentences are copied verbatim into the logbook entry, so
# they follow the logbook language (CLAUDE_DAILY_DOCS_LANG, same switch and
# same env.local.sh fallback as SKILL.md's Output section). The JSON key stays.
# Read only this one value from env.local.sh (no sourcing: a counting run
# must not inherit arbitrary shell state).
if [ -z "${CLAUDE_DAILY_DOCS_LANG:-}" ] && [ -f "$HOME/.claude/env.local.sh" ]; then
  CLAUDE_DAILY_DOCS_LANG=$(sed -n 's/^[[:space:]]*export[[:space:]]*CLAUDE_DAILY_DOCS_LANG=["'\'']\{0,1\}\([a-z]*\).*/\1/p' "$HOME/.claude/env.local.sh" | tail -1)
fi
if [ "${CLAUDE_DAILY_DOCS_LANG:-en}" = "de" ]; then
  NE1="Uncommittete Arbeit und Edit-und-Revert am selben Tag: Q_G meldet nur das Netto-Delta zum Vorgaenger-Blob."
  NE2="Schreibvorgaenge ausserhalb der Werkzeugebene (Hooks, Framework-Skripte) erzeugen kein tool_use und sind auf keiner Achse sichtbar."
  NE3="Externe Systeme (Notion, Deploys, Kommunikation) haben per Konstruktion 0 Items — bewusste Eigenschaft der Zaehlbasis, kein Messfehler."
  NE4="git merge --no-commit und git checkout -- <pfad> im Terminal ausserhalb einer Claude-Session: keine HEAD-Bewegung (kein reflog) und kein Transkript."
  NE5="Umfang entfernter Arbeitskopien (git worktree remove): dateien=null, nicht 0 — nicht rekonstruierbar."
  if [ "$AGE" -gt 90 ]; then NE6="reflog-Retention ueberschritten (${AGE}d > 90d): Achse V1 faellt fuer diesen Tag aus."
  else NE6="Fuer diesen Tag keine retentionsbedingte Achsen-Luecke (Alter ${AGE}d <= 90d)."; fi
  if [ "$MAN_STATUS" = ok ]; then NE7="Handarbeits-Zweig gemessen."
  else NE7="Handarbeits-Zweig (Q_M) nicht messbar: kein manifest-$PREV — buckets.manual ist null, nicht 0."; fi
else
  NE1="Uncommitted work and edit-then-revert on the same day: Q_G reports only the net delta against the previous blob."
  NE2="Writes outside the tool layer (hooks, framework scripts) produce no tool_use and are visible on no axis."
  NE3="External systems (Notion, deploys, communication) have 0 items by construction — a deliberate property of the count basis, not a measurement error."
  NE4="git merge --no-commit and git checkout -- <path> in a terminal outside a Claude session: no HEAD movement (no reflog) and no transcript."
  NE5="Size of removed working copies (git worktree remove): files=null, not 0 — not reconstructable."
  if [ "$AGE" -gt 90 ]; then NE6="reflog retention exceeded (${AGE}d > 90d): axis V1 drops out for this day."
  else NE6="No retention-related axis gap for this day (age ${AGE}d <= 90d)."; fi
  if [ "$MAN_STATUS" = ok ]; then NE7="Manual-work branch measured."
  else NE7="Manual-work branch (Q_M) not measurable: no manifest-$PREV — buckets.manual is null, not 0."; fi
fi
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
 "day": "$D", "tz": "$TZ", "window": ["$WSTART", "$WEND"],
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
 # NEVER splice JSON into Python source via command substitution: a JSON null
 # is valid JSON and invalid Python (NameError). Hence json.load here, not jq.
 # (Backticks in this heredoc are likewise forbidden — it is UNQUOTED, the shell
 #  would otherwise execute them as a command; this actually happened on the first run.)
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
   "$NE1", "$NE2", "$NE3", "$NE4", "$NE5", "$NE6", "$NE7"
 ],
 "i4_gap": $I4,
 "nebenmetriken": {"ereigniszeilen": $NEV, "schreibpaare_roh": $NPAIRS,
                   "fehlschlaege_gefiltert": $NFAIL, "bash_calls": $NBASH, "bash_unparsebar": $NBUNPARSED,
                   "desktop_zeilen": $DESK_LINES, "desktop_unparseable": $DESK_UNPARSEABLE,
                   "signals_keys": $NSIG, "repo_ids_gescannt": $NREPO,
                   "arbeitskopien_gesehen": $NREPO_WC},
 "items_sha256": "$SHA"
}, indent=1, ensure_ascii=False))
PY
cat "$WORK/out.json"
if [ -n "${LOGBOOK_ITEMS_OUT:-}" ]; then cp "$WORK/items.txt" "$LOGBOOK_ITEMS_OUT"; fi
