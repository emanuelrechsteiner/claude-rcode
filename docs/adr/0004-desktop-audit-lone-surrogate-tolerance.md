# 0004 — Count and skip desktop audit lines that carry a lone UTF-16 high surrogate

- Status: accepted
- Date: 2026-09-27

## Context

Step S6 of the daily-docs day count (`scheduled-tasks/daily-docs/bin/logbook-count.sh`)
reads every desktop `audit.jsonl` under the `local-agent-mode-sessions` tree and
filters it with jq. Between 2026-09-10 and 2026-09-21, 5 of 13 daily-docs runs
failed with `ABORT(16)`; jq-1.7.1 reported
`Invalid \uXXXX\uXXXX surrogate pair escape`. The cause was one record type: a
desktop local-agent transcript record (`entrypoint:"local-agent"`,
`version:"2.1.221"`) whose tool-result text had been truncated at a fixed UTF-16
length. The cut fell between the two halves of a surrogate pair, so the record
contains the escape `\ud835` (a lone high surrogate) directly followed by a
literal `[TRUNCATED]`. That is valid JSON text to Python but not to jq-1.7.1, and
jq rejects the whole input batch, so one line in a corpus of about 159k lines
aborted the run.

The obvious jq-only fix, `jq -R 'fromjson?'` (read raw lines, drop the ones that
don't parse), was tried against the real audit files and rejected. jq-1.7.1 in
`-R` mode splits raw lines at its ~4095-byte read boundary. It corrupted 7 of
8,322 events (a multibyte character such as `€` straddling the boundary became
U+FFFD), and it glued the last line of a file without a trailing newline onto
the first line of the next file. The `?` would also have hidden every one of
these failures without a trace.

## Decision

A Python pre-pass reads each audit file line by line. It forwards the
**original bytes** of every line jq will accept to the unchanged jq filter. It
**counts** every other line (unparseable JSON, or a lone high surrogate that
survives decoding) and skips it, recording file:line for the first three. The
count is never silent: it shows up in the S6 receipt, in the `S1b_desktop`
certificate and as a `WARN` line. Skipping is bounded by a 1% threshold
(`DESK_UNPARSEABLE_MAX_PCT`). The threshold applies to the whole corpus and,
separately, to the lines inside the counted day's window (same window and same
`timestamp` field as the jq filter; for a line that can't be parsed, the raw
`"timestamp":"…` prefix). Crossing either share stops the run with `ABORT(16)`.
So does an unreadable file, a pre-pass failure, or a jq failure on a line the
pre-pass forwarded. A lone *low* surrogate is not counted, because jq accepts
it (as U+FFFD).

## Consequences

**Easier:** one malformed desktop record no longer aborts the whole day, and
every valid record is passed on byte-for-byte, with no re-encoding.
**Harder / trade-offs:** skipped lines are not counted, so a real write event
inside a skipped line is lost. This loss is reported, not hidden, and the
in-window bound caps it at 1% of the day's desktop lines. The corpus-wide share
by itself would allow about 1.6k bad lines on the real corpus, enough to hide a
whole day; that is why the in-window share exists. A rejected line with no
readable timestamp only counts toward the corpus share, and is reported as
`undated_unparseable`. If a future jq accepts lone high surrogates, the
pre-pass will be stricter than it needs to be, but never more lenient.
Regression: `scripts/tests/logbook-count-desktop-regression.sh`. Ledger: IMP-223.
