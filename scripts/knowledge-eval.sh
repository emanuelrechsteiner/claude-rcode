#!/usr/bin/env bash
# knowledge-eval.sh - the ruler for scripts/knowledge-lookup.sh: runs a question set against
# the real lookup and reports hit@1, hit@3, hit@10, MRR@10 and a tokens-to-answer proxy.
# Read-only on the library; writes only a private temp dir and (unless --no-history)
# one line to <K>/eval/history.tsv. Run with --help for usage.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LK=${KNOWLEDGE_EVAL_LOOKUP:-$REPO_ROOT/scripts/knowledge-lookup.sh}   # override: test shims only
# Evaluation queries are not real usage: keep them out of the lookup's usage log
# (<K>/eval/lookup-log.tsv, lookup v3), which is the source of future real questions.
export KNOWLEDGE_LOOKUP_LOG=0
# shellcheck source=scripts/lib/knowledge-eval-score.sh
. "$SCRIPT_DIR/lib/knowledge-eval-score.sh"

usage() {
  cat <<'EOF'
Usage: bash knowledge-eval.sh [--set dev|test|all] [--questions FILE] [--max N]
                              [--alts] [--no-history] [--verbose] [--help]

Scores knowledge-lookup.sh against a question file. Env: CLAUDE_KNOWLEDGE_DIR (required;
<K>/mirror must exist). Default question file: <K>/eval/questions.tsv.

Question file: tab-separated, header "id set query expected class source confirmed"
(columns are found by name; unknown extra columns are ignored; optional column: alts). set: dev|test.
expected: mirror-relative paths separated by "|" (any one is a hit) or "-" (no defined
expectation: unscored, not in n). class: lookup|paraphrase|crosslang|supersession|structural;
structural rows print "SKIP <id> class=structural" and are not in n. confirmed: yes|no
(unconfirmed rows are scored and counted as unconfirmed=<u>). query: split like a shell
would for the lookup CLI; single or double quotes keep a phrase as one keyword.

  --set S         rows of set dev, test or all (default all)
  --questions F   use file F instead of <K>/eval/questions.tsv
  --max N         passed to the lookup (default 10, so MRR@10 is computable)
  --alts          score the retrieval protocol: a row with a non-empty alts column (keyword
                  sets separated by "|") runs ONE lookup with query as primary keywords and each
                  set as --alt (given before "--"); rows without alts run as usual and count in
                  no_alts=<n>. No alts column in the file: EVAL SKIP, exit 3. Deterministic.
  --no-history    do not append to <K>/eval/history.tsv
  --verbose       one "ROW <id> rank=<r> tta=<tok>" line per scored row
                  (with --alts also sets=<m>, the number of alt sets, 1 without alts)

Output: "EVAL <set> n=.. hit@1=a/n hit@3=b/n hit@10=c/n mrr10=.. tta_median=.. tta_p90=..
unconfirmed=.. mode=single|alts [no_alts=..] runtime=..s", then one MISS line per row whose expected note is not in the
top 3, then SKIP lines. rank is the first listed path matching any expected path.
tta (tokens-to-answer) is a PROXY that assumes the agent reads in rank order: lookup stdout
bytes/4 + sizes/4 of the listed files up to and including the first expected one, capped at
the top 5; a row whose expected note is absent or beyond rank 5 costs the top-5 total and is
flagged tta-miss. median/p90 are nearest-rank over scored rows.
History line: timestamp set n hit1 hit3 hit10 mrr10 tta_median tta_p90 runtime_s mirror_stamp
lookup_git_hash mode (hit10 = expected note in the shown top 10, the window the agent sees; an old 11- or 12-column header is upgraded by rewriting the header only; hash gets "-dirty" when the lookup or scripts/lib has uncommitted changes).
Exit codes: 0 ok, 1 environment/lookup failure, 2 usage or malformed question file,
3 EVAL SKIP (no question file, or no scorable rows) - never a pass line without data.
EOF
}

SET=all; QFILE=""; MAXN=10; HIST=1; VERBOSE=0; ALTS=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --set) [ $# -ge 2 ] || ke_die "--set needs a value" 2; SET=$2; shift 2 ;;
    --questions) [ $# -ge 2 ] || ke_die "--questions needs a file" 2; QFILE=$2; shift 2 ;;
    --max) [ $# -ge 2 ] || ke_die "--max needs a value" 2; MAXN=$2; shift 2 ;;
    --alts) ALTS=1; shift ;;
    --no-history) HIST=0; shift ;;
    --verbose) VERBOSE=1; shift ;;
    *) ke_die "unknown argument: $1 (see --help)" 2 ;;
  esac
done
case "$SET" in dev|test|all) ;; *) ke_die "--set must be dev, test or all" 2 ;; esac
case "$MAXN" in ''|*[!0-9]*) ke_die "--max needs a positive integer" 2 ;; esac
MAXN=$((10#$MAXN)); [ "$MAXN" -ge 1 ] || ke_die "--max needs a positive integer" 2

KDIR=${CLAUDE_KNOWLEDGE_DIR:-}
[ -n "$KDIR" ] || ke_die "CLAUDE_KNOWLEDGE_DIR is not set" 1
while [ "${KDIR%/}" != "$KDIR" ] && [ -n "${KDIR%/}" ]; do KDIR=${KDIR%/}; done
MIRROR="$KDIR/mirror"
[ -d "$MIRROR" ] || ke_die "mirror missing: $MIRROR (run scripts/knowledge-mirror.sh first)" 1
[ -r "$LK" ] || ke_die "lookup not readable: $LK" 1
command -v perl >/dev/null 2>&1 || ke_die "perl is required for the runtime clock" 1

[ -n "$QFILE" ] || QFILE="$KDIR/eval/questions.tsv"
if [ ! -e "$QFILE" ]; then echo "EVAL SKIP no question file at $QFILE" >&2; exit 3; fi
[ -f "$QFILE" ] && [ -r "$QFILE" ] || ke_die "question file unreadable: $QFILE" 1

HAS_ALTS=0
head -n 1 "$QFILE" | tr -d '\r' | tr '\t' '\n' | grep -x alts >/dev/null && HAS_ALTS=1
if [ "$ALTS" -eq 1 ] && [ "$HAS_ALTS" -eq 0 ]; then echo "EVAL SKIP no alts column in $QFILE" >&2; exit 3; fi
MODE=single; [ "$ALTS" -eq 1 ] && MODE=alts

WORK=$(mktemp -d "${TMPDIR:-/tmp}/knowledge-eval.XXXXXX") || ke_die "mktemp failed" 1
trap 'rm -rf "$WORK"' EXIT
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
T0=$(now)

ke_read_questions "$QFILE" "$SET" > "$WORK/rows.us" || exit $?
if [ ! -s "$WORK/rows.us" ]; then echo "EVAL SKIP set $SET has no rows" >&2; exit 3; fi

: > "$WORK/scored.tsv"; : > "$WORK/miss.txt"; : > "$WORK/skip.txt"; : > "$WORK/row.txt"
UNCONF=0; NOALTS=0
while IFS=$'\037' read -r id _set query expected class conf alts; do
  if [ "$class" = "structural" ]; then echo "SKIP $id class=structural" >> "$WORK/skip.txt"; continue; fi
  if [ "$expected" = "-" ]; then continue; fi
  [ "$ALTS" -eq 1 ] || alts=""
  if [ "$ALTS" -eq 1 ] && [ -z "$alts" ]; then NOALTS=$((NOALTS + 1)); fi
  ke_score_row "$id" "$query" "$expected" "$alts"
  [ "$conf" = "no" ] && UNCONF=$((UNCONF + 1))
  printf '%s\t%s\t%s\n' "$id" "$RANK" "$TTA" >> "$WORK/scored.tsv"
  flag=""; [ "$TTAMISS" -eq 1 ] && flag=" tta-miss"
  sets=""; [ "$ALTS" -eq 1 ] && sets=" sets=$SETS"
  echo "ROW $id rank=$RANK tta=$TTA$sets$flag" >> "$WORK/row.txt"
  if [ "$RANK" -eq 0 ] || [ "$RANK" -gt 3 ]; then
    r="-"; [ "$RANK" -gt 0 ] && r=$RANK
    echo "MISS $id q=\"$query\" expected=$expected rank=$r, top3=$TOP3" >> "$WORK/miss.txt"
  fi
done < "$WORK/rows.us"

N=$(wc -l < "$WORK/scored.tsv" | tr -d ' ')
if [ "$N" -eq 0 ]; then echo "EVAL SKIP set $SET has no scorable rows" >&2; exit 3; fi
read -r H1 H3 H10 MRR TMED TP90 <<< "$(ke_stats "$WORK/scored.tsv")"
RUNTIME=$(perl -e "printf '%.1f', $(now) - $T0")
NAFIELD=""; [ "$ALTS" -eq 1 ] && NAFIELD=" no_alts=$NOALTS"
echo "EVAL $SET n=$N hit@1=$H1/$N hit@3=$H3/$N hit@10=$H10/$N mrr10=$MRR tta_median=$TMED tta_p90=$TP90 unconfirmed=$UNCONF mode=$MODE$NAFIELD runtime=${RUNTIME}s"
cat "$WORK/miss.txt" "$WORK/skip.txt"
if [ "$VERBOSE" -eq 1 ]; then cat "$WORK/row.txt"; fi

if [ "$HIST" -eq 1 ]; then
  README="$MIRROR/README.md"
  [ -r "$README" ] || ke_die "cannot read $README for the mirror stamp (use --no-history to skip)" 1
  STAMP=$(sed -n 's/^.*Last run: \([^ ]*\).*$/\1/p' "$README" | head -n 1)
  [ -n "$STAMP" ] || ke_die "no \"Last run:\" stamp in $README (use --no-history to skip)" 1
  command -v git >/dev/null 2>&1 || ke_die "git is required for the lookup hash" 1
  HASH=$(git -C "$REPO_ROOT" log -1 --format=%h -- scripts/knowledge-lookup.sh scripts/lib) \
    || ke_die "git log failed in $REPO_ROOT" 1
  [ -n "$HASH" ] || ke_die "no git history for scripts/knowledge-lookup.sh in $REPO_ROOT" 1
  DIRTY=$(git -C "$REPO_ROOT" status --porcelain -- scripts/knowledge-lookup.sh scripts/lib) \
    || ke_die "git status failed in $REPO_ROOT" 1
  [ -z "$DIRTY" ] || HASH="$HASH-dirty"
  HF="$KDIR/eval/history.tsv"
  mkdir -p "$KDIR/eval" || ke_die "cannot create $KDIR/eval" 1
  H11=$(printf 'timestamp\tset\tn\thit1\thit3\tmrr10\ttta_median\ttta_p90\truntime_s\tmirror_stamp\tlookup_git_hash')
  H12=$(printf '%s\tmode' "$H11")
  H13=$(printf 'timestamp\tset\tn\thit1\thit3\thit10\tmrr10\ttta_median\ttta_p90\truntime_s\tmirror_stamp\tlookup_git_hash\tmode')
  if [ ! -s "$HF" ]; then
    printf '%s\n' "$H13" > "$HF" || ke_die "cannot write $HF" 1
  else
    CURH=$(head -n 1 "$HF" | tr -d '\r')
    if [ "$CURH" = "$H11" ] || [ "$CURH" = "$H12" ]; then
      { printf '%s\n' "$H13"; tail -n +2 "$HF"; } > "$WORK/hist.new" && cat "$WORK/hist.new" > "$HF" \
        || ke_die "cannot upgrade the header of $HF" 1
    elif [ "$CURH" != "$H13" ]; then
      ke_die "unexpected header in $HF (not the 11-, 12- or 13-column history header)" 1
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SET" "$N" \
    "$H1" "$H3" "$H10" "$MRR" "$TMED" "$TP90" "$RUNTIME" "$STAMP" "$HASH" "$MODE" >> "$HF" || ke_die "cannot append to $HF" 1
fi
exit 0
