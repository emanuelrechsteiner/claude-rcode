#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # awk programs live in single-quoted strings on purpose
# knowledge-mirror-imp.sh - IMP id wikilinks for scripts/lib/knowledge-mirror-graph.sh (sourced by it,
# never executed). Appends km_imp to KM_AWK_COMMON: a plain-text IMP-<digits> token becomes
# [[ledger/IMP-<digits>|IMP-<digits>]] when that ledger note is in this run's target set (T).
# Whole token only (no alphanumeric or "-" on either side), never inside a markdown link or URL,
# never the ledger note's own id (KM_REL), never while NOIMP is set (a ledger note's own heading).
# km_bare feeds it only the prose outside [[...]]; km_spans only the prose outside code spans.
# This text lives in a shell single-quoted string: awk code and comments must never contain a single quote.
KM_AWK_COMMON="$KM_AWK_COMMON"'
function km_lastidx(s, t,    p, o, r) { # last offset of t in s, 0 if none
  o = 0; r = 0
  while ((p = index(substr(s, o + 1), t)) > 0) { r = o + p; o = r }
  return r
}
function km_inlink(pre,    w) { # pre = text before a token: inside link text, a link target or a URL?
  if (km_lastidx(pre, "[") > km_lastidx(pre, "]")) return 1
  if (km_lastidx(pre, "](") > km_lastidx(pre, ")")) return 1
  w = pre; sub(/^.*[ \t]/, "", w)
  return index(w, "://") > 0
}
function km_imp(s,    out, rest, a, n, pos, done, c, d, id, lk) {
  if (NOIMP || index(s, "IMP-") == 0) return s
  out = ""; rest = s; done = 0
  while ((a = index(rest, "IMP-")) > 0) {
    n = 4; while (substr(rest, a + n, 1) ~ /^[0-9]$/) n++
    pos = done + a; id = substr(rest, a, n)
    c = (pos > 1) ? substr(s, pos - 1, 1) : ""; d = substr(rest, a + n, 1); lk = id
    if (n > 4 && c !~ /^[A-Za-z0-9-]$/ && d !~ /^[A-Za-z0-9-]$/ && ("ledger/" id ".md") != ENVIRON["KM_REL"] \
        && (("ledger/" id ".md") in T) && !km_inlink(substr(s, 1, pos - 1))) lk = "[[ledger/" id "|" id "]]"
    out = out substr(rest, 1, a - 1) lk
    done += a + n - 1; rest = substr(rest, a + n)
  }
  return out rest
}
'
