#!/bin/bash
# knowledge-keywords.sh — keyword and path-word extraction for the IMP-267 knowledge injection.
# ─────────────────────────────────────────────────────────────────────────────
# Sourced by hooks/knowledge-inject.sh (and by its regression suite). Defines
# functions only: sourcing has no side effects, and nothing runs until called.
# Pure: no network, no temp files.
#
#   kk_extract "<text>" [N]   up to N ranked keywords (default 10), one per line
#   kk_paths   "<text>" [N]   up to N words from path-like tokens (default 8)
#
# Ranking: frequency in the text, then first occurrence. Filters: at least 4
# characters, not a pure number, not a stopword.
#
# Byte handling: everything runs under LC_ALL=C. Umlauts and ß are two-byte
# UTF-8 sequences; grep -o matches them as whole sequences, so they survive.
# ─────────────────────────────────────────────────────────────────────────────

# Stopwords: English, German, and hook noise (task, brief, file, ...). Lowercase.
KK_STOP="the and this that with from have will should must also into than then
there which when where what your you are not but for our their they them these
those been being were was its about over under between through during before
after again further once here more most other some such only own same too very
can could would may might shall just each both all any because as until while
of at by to in on off out up down an a is be do does did doing done has had
having get gets got make makes made need needs use used using uses via per etc
yet still already even ever either neither nor so if or ok
der die das und ist nicht eine einen einem einer eines auch aber wenn dass sich
wird werden wurde wurden haben hat hatte kann können konnte sollen soll sollte
muss müssen dann noch schon hier dort alle aller allen diese dieser dieses
diesem bitte machen sind sein seine seiner beim nach über unter zwischen wie
was wer bei von zum zur mit ohne oder also für durch gegen gibt viel sehr nur
ganz dazu damit weil doch mal eben etwas jede jeder jedes sie wir ihr ich man
es er den dem des auf aus bis vor ihre euch
task brief file files path please agent agents user run runs verify check
whether claude code first within without across however therefore hence thus
another every always never already mention mentions line lines"

# _kk_rank MAX  (stdin: text) -> up to MAX ranked keywords, one per line.
_kk_rank() {
    local max="$1"
    case "$max" in
        ''|*[!0-9]*)
            printf 'knowledge-keywords: max must be a non-negative integer, got "%s"\n' "$max" >&2
            return 2 ;;
    esac
    LC_ALL=C tr '[:upper:]' '[:lower:]' \
        | LC_ALL=C sed -e 's/Ä/ä/g' -e 's/Ö/ö/g' -e 's/Ü/ü/g' \
        | LC_ALL=C grep -oE '(ä|ö|ü|ß|[a-z0-9])+' \
        | LC_ALL=C grep -E '^(ä|ö|ü|ß|[a-z0-9]){4}' \
        | LC_ALL=C awk -v stop="${KK_STOP//$'\n'/ }" '
            BEGIN { n = split(stop, s, " "); for (i = 1; i <= n; i++) stopword[s[i]] = 1 }
            /^[0-9]+$/ || ($0 in stopword) { next }
            { if (!($0 in count)) first[$0] = ++seq
              count[$0]++ }
            END { for (w in count) printf "%d\t%d\t%s\n", count[w], first[w], w }' \
        | LC_ALL=C sort -t "$(printf '\t')" -k1,1nr -k2,2n \
        | head -n "$max" \
        | cut -f3
}

# kk_extract TEXT [N] -> up to N keywords (default 10), ranked, one per line.
kk_extract() {
    printf '%s' "$1" | _kk_rank "${2:-10}"
}

# kk_paths TEXT [N] -> up to N words from path-like tokens (default 8).
# A path-like token contains "/" or ends in ".ext". Per token: the basename
# without its extension, then the last two directory names; the usual word
# filters then apply, so /a/b/c-d.ts yields nothing.
kk_paths() {
    printf '%s' "$1" \
        | LC_ALL=C tr '\140"\047(),;:{}<>*' '             ' \
        | LC_ALL=C awk '
            { for (i = 1; i <= NF; i++) {
                t = $i
                sub(/\.+$/, "", t)
                if (t !~ /\// && t !~ /\.[A-Za-z][A-Za-z0-9]*$/) continue
                base = t; sub(/^.*\//, "", base); sub(/\.[A-Za-z0-9]+$/, "", base)
                dirs = t
                if (sub(/\/[^\/]*$/, "", dirs) == 0) dirs = ""
                m = split(dirs, parts, "/"); out = base; kept = 0
                for (j = m; j >= 1 && kept < 2; j--)
                    if (parts[j] != "") { out = out " " parts[j]; kept++ }
                print out
            } }' \
        | _kk_rank "${2:-8}"
}
