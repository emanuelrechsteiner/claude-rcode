#!/bin/bash
# shellcheck shell=bash
# knowledge-brief.sh — the KNOWLEDGE field of a dispatch brief: parser and decision (IMP-268)
# ─────────────────────────────────────────────────────────────────────────────
# Sourced by the check hook and knowledge-inject.sh; both call kb_decide on the block from kb_block,
# so one brief gets one decision. Functions only, no side effects on source; LC_ALL=C; bash 3.2.
#   kb_block <text> | kb_verdict <block>   marker block (exit 1 if none) | cited|none|unavailable|invalid
#   kb_citations | kb_excerpts | kb_sets <block>   cited paths | verbatim excerpts | sets clause
#   kb_decide <block> <kdir> <state_dir> <window>  "allow <verdict> <detail>" | "deny <verdict> <cause>"
#   kb_mark_dispatch <state_dir>           records a knowledge-agent dispatch (unavailable verdict)
#   kb_counter_key <subagent> <desc> <prompt>  the denial-counter key, one definition for both hooks
# Evidence rules (second review, 2026-11-01): a .md inside sets: or double quotes is neither a citation
# nor a verdict trigger; unavailable needs 20 bytes of reason once separators are removed; none needs
# a sets: clause and two DISTINCT knowledge-agent runs (agent ids) in the window; only the last 50
# lines of a run file are read; a block of 4000 bytes or more is denied.
# ─────────────────────────────────────────────────────────────────────────────

KB_MARKER_RE='^[[:space:]]*([-*>#]+[[:space:]]*)*(\*\*)?(KNOWLEDGE|WISSEN)(\*\*)?[[:space:]]*(\([^)]*\))?[[:space:]]*:'

# kb_awk_lib: awk functions shared by the programs below (printed, then concatenated into the program).
kb_awk_lib() {
    cat <<'AWK'
function cut_sets(s,   p, rest, e) {
    while (p = index(tolower(s), "sets:")) { rest = substr(s, p); e = match(rest, /[;\n]/) ? RSTART : length(rest) + 1; s = substr(s, 1, p - 1) substr(rest, e) }
    return s
}
function cut_quotes(s) { while (match(s, /"[^"]*"/)) s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + RLENGTH); return s }
function clean(t) { gsub(/^[][*]+/, "", t); gsub(/[][*.:;!?]+$/, "", t); sub(/:L[0-9]+((-|–)L?[0-9]+)?$/, "", t); gsub(/[][*.:;!?]+$/, "", t); return t }
AWK
}

# kb_block <text>: the block of the LAST marker outside fences, up to the first blank line.
kb_block() {
    local block
    block=$(printf '%s\n' "$1" | LC_ALL=C tr -d '\r' | KB_MARKER_RE="$KB_MARKER_RE" LC_ALL=C awk '
        BEGIN { re = ENVIRON["KB_MARKER_RE"] }
        { lines[++n] = $0 }
        END {
            for (i = 1; i <= n; i++) {
                l = lines[i]
                if (fence == "") {
                    if (l ~ /^[ \t]*```/) fence = "`"; else if (l ~ /^[ \t]*~~~/) fence = "~"; else if (l ~ re) start = i
                } else if ((fence == "`" && l ~ /^[ \t]*```/) || (fence == "~" && l ~ /^[ \t]*~~~/)) fence = ""
            }
            if (start == 0) exit 1
            print lines[start]
            for (i = start + 1; i <= n && lines[i] !~ /^[ \t]*$/; i++) print lines[i]
        }') || return 1
    [ -n "$block" ] || return 1
    printf '%s' "$block"
}

# kb_body <block>: the text after the marker prefix; lines joined by newlines.
kb_body() {
    printf '%s\n' "$1" | KB_MARKER_RE="$KB_MARKER_RE" LC_ALL=C awk '{ lines[++n] = $0 }
        END { re = ENVIRON["KB_MARKER_RE"]
              for (i = 1; i <= n; i++) { l = lines[i]; sub(/\r$/, "", l); if (i == 1 && match(l, re)) l = substr(l, RLENGTH + 1); printf "%s%s", (i > 1 ? "\n" : ""), l } }'
}

kb_bytes() { printf '%s' "$1" | LC_ALL=C wc -c | tr -d ' '; }

# kb_u8_cut <text> <bytes>: the first <bytes> bytes, minus a trailing partial UTF-8 sequence.
kb_u8_cut() {
    printf '%s' "$1" | LC_ALL=C awk -v n="$2" '
        BEGIN { for (i = 128; i < 192; i++) cont[sprintf("%c", i)] = 1
                for (i = 192; i < 248; i++) need[sprintf("%c", i)] = (i < 224 ? 2 : (i < 240 ? 3 : 4)) }
        { s = s (NR > 1 ? "\n" : "") $0 }
        END { s = substr(s, 1, n); len = length(s); i = len
              while (i > 0 && (substr(s, i, 1) in cont)) i--
              if (i > 0 && (substr(s, i, 1) in need) && len - i + 1 < need[substr(s, i, 1)]) s = substr(s, 1, i - 1)
              printf "%s", s }'
}

# kb_cut <block>: the body with the sets clause and double-quoted segments removed (case kept).
kb_cut() {
    kb_body "$1" | LC_ALL=C awk "$(kb_awk_lib)"'{ t = t (NR > 1 ? "\n" : "") $0 } END { printf "%s", cut_quotes(cut_sets(t)) }'
}

# kb_reason_text <block>: the text after the first unavailable word (or nicht verfügbar) in kb_cut,
# separators removed (spaces, tabs, CR, LF, em and en dash, - : ; , .). Prints nothing, rc 1 without a word.
kb_reason_text() {
    local scan word after
    scan=$(kb_cut "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')
    for word in unavailable "nicht verfügbar" "nicht verfuegbar"; do
        case "$scan" in *"$word"*) ;; *) continue ;; esac
        after=${scan#*"$word"}
        KB_T=$after LC_ALL=C awk 'BEGIN { r = ENVIRON["KB_T"]; gsub(/—|–|[ \t\r\n:;,.-]/, "", r); printf "%s", r }'
        return 0
    done
    return 1
}

# kb_verdict <block>: none phrases in the cut scan first, then unavailable (20+ bytes of reason), then
# a .md token in the cut body, else invalid. A body under 40 bytes is invalid.
kb_verdict() {
    local body scan reason
    body=$(kb_body "$1")
    if [ "$(kb_bytes "$body")" -lt 40 ]; then printf 'invalid'; return 0; fi
    scan=$(kb_cut "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')
    case "$scan" in
        *"none relevant"*|*"nothing relevant"*|*"no relevant"*|*"nichts relevant"*|*"nichts passendes"*|*"keine passenden"*|*"keine passende"*|*"kein passendes"*|*"nichts gefunden"*)
            printf 'none'; return 0 ;;
    esac
    if reason=$(kb_reason_text "$1"); then
        if [ "$(kb_bytes "$reason")" -ge 20 ]; then printf 'unavailable'; else printf 'invalid'; fi
        return 0
    fi
    if kb_cut "$1" | LC_ALL=C grep -Eq '[^[:space:]]\.md([^[:alnum:]_]|$)'; then printf 'cited'; else printf 'invalid'; fi
}

# kb_citations <block>: cited note paths outside the sets clause and double quotes, distinct, in order.
kb_citations() {
    kb_cut "$1" | LC_ALL=C tr '\140"\047()<>,;|' '          ' | LC_ALL=C awk "$(kb_awk_lib)"'
        { for (i = 1; i <= NF; i++) { t = clean($i); if (t ~ /\.md$/ && t != ".md" && !(t in seen)) { seen[t] = 1; print t } } }'
}

# kb_spaced <block> <cite>: "<token> <cite>" when the cite follows a token holding a slash (a path split by a space).
kb_spaced() {
    kb_cut "$1" | LC_ALL=C awk -v c="$2" "$(kb_awk_lib)"'
        { t = t (NR > 1 ? "\n" : "") $0 }
        END { n = split(t, w, /[ \t\n]+/); for (i = 2; i <= n; i++) if (index(w[i - 1], "/") && clean(w[i]) == c) { print w[i - 1] " " w[i]; exit } }'
}

# kb_excerpts <block>: each double-quoted segment outside the sets clause of 30+ bytes, normalised.
kb_excerpts() {
    kb_body "$1" | LC_ALL=C awk "$(kb_awk_lib)"'
        { t = t (NR > 1 ? "\n" : "") $0 }
        END {
            t = cut_sets(t)
            while (match(t, /"[^"]*"/)) {
                seg = substr(t, RSTART + 1, RLENGTH - 2); t = substr(t, RSTART + RLENGTH)
                gsub(/[ \t\n\r]+/, " ", seg); sub(/^ /, "", seg); sub(/ $/, "", seg)
                if (substr(seg, 1, 3) == "» ") { seg = substr(seg, 4); sub(/^ /, "", seg) }
                if (length(seg) >= 30) print seg
            }
        }'
}

# kb_sets <block>: the text after the first "sets:" up to ";" or the end of its line (may be empty).
kb_sets() {
    printf '%s' "$1" | LC_ALL=C awk '{ t = t (NR > 1 ? "\n" : "") $0 }
        END { p = index(tolower(t), "sets:"); if (p) { r = substr(t, p + 5); e = match(r, /[;\n]/) ? RSTART - 1 : length(r)
              r = substr(r, 1, e); gsub(/^[ \t\n]+|[ \t\n]+$/, "", r); printf "%s", r } }'
}

# kb_has_sets <block>: 0 when the block contains the word sets: (any case).
kb_has_sets() {
    case "$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')" in *sets:*) return 0 ;; esac
    return 1
}

# kb_detect_date: sets KB_DATE_KIND once: bsd (date -j), gnu (date -d) or none.
kb_detect_date() {
    if date -j -u -f '%Y-%m-%dT%H:%M:%SZ' 2000-01-01T00:00:00Z +%s >/dev/null 2>&1; then KB_DATE_KIND=bsd
    elif date -u -d 2000-01-01T00:00:00Z +%s >/dev/null 2>&1; then KB_DATE_KIND=gnu
    else KB_DATE_KIND=none; fi
}

# kb_epoch <UTC stamp>: epoch seconds; exit 1 when the stamp does not parse.
kb_epoch() {
    if [ "${KB_DATE_KIND:-}" = bsd ]; then date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
    elif [ "${KB_DATE_KIND:-}" = gnu ]; then date -u -d "$1" +%s 2>/dev/null; else return 1; fi
}

# kb_fresh_lines <file> <window>: of the LAST 50 lines, those whose first tab field is a UTC stamp
# 0..window seconds old. An unreadable file prints nothing.
kb_fresh_lines() {
    local file="$1" win="$2" now line ts epoch age
    now=$(date -u +%s)
    tail -n 50 "$file" 2>/dev/null | while IFS= read -r line || [ -n "$line" ]; do
        ts=${line%%$'\t'*}
        case "$ts" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;; *) continue ;; esac
        epoch=$(kb_epoch "$ts") || continue
        [ -n "$epoch" ] || continue
        age=$((now - epoch))
        if [ "$age" -ge 0 ] && [ "$age" -le "$win" ]; then printf '%s\n' "$line"; fi
    done
}

# kb_reason <block>: the reason of an unavailable verdict (kb_reason_text), at most 80 bytes.
kb_reason() { local text; text=$(kb_reason_text "$1") || text=""; kb_u8_cut "$text" 80; }

# kb_locate <full> <mirror> <mirror_p>: prints ok (a path inside the mirror), outside or notfound.
kb_locate() {
    local dirp=""
    if [ -d "${1%/*}" ]; then dirp=$(cd "${1%/*}" && pwd -P); fi
    if [ -z "$dirp" ]; then case "$1" in "$2"/*) printf 'notfound' ;; *) printf 'outside' ;; esac
    else case "$dirp/${1##*/}" in "$3"/*) printf 'ok' ;; *) printf 'outside' ;; esac; fi
}

# kb_decide_cited <block> <kdir>: every citation resolves inside the mirror; every excerpt of 30+ bytes must occur
# whole (normalised) in at least one cited note; the deny cause shows its first 40 bytes.
kb_decide_cited() {
    local block="$1" mirror mirror_p cites c cut full why spaced excerpts ex pat f n=0 m=0 files=""
    mirror="$2/mirror"; mirror_p=""
    if [ -d "$mirror" ]; then mirror_p=$(cd "$mirror" && pwd -P); fi
    if [ -z "$mirror_p" ]; then printf 'deny cited the library mirror is missing: %s\n' "$2"; return 0; fi
    cites=$(kb_citations "$block")
    if [ -z "$cites" ]; then
        printf '%s\n' "deny cited a cited verdict names no note outside its double quotes: put the note path in the verdict, not inside an excerpt"; return 0
    fi
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        n=$((n + 1)); cut=$(kb_u8_cut "$c" 160)
        case "$c" in */../*|*/..|../*|..) printf 'deny cited cited note path has a .. segment (refused): %s\n' "$cut"; return 0 ;; esac
        # shellcheck disable=SC2088  # "~/" is a literal cited prefix, expanded explicitly below
        case "$c" in /*) full=$c ;; "~/"*) full="${HOME:-}/${c#"~/"}" ;; *) full="$mirror/$c" ;; esac
        why=$(kb_locate "$full" "$mirror" "$mirror_p")
        if [ "$why" = outside ]; then printf 'deny cited cited note outside the library mirror: %s\n' "$cut"; return 0; fi
        if [ "$why" = ok ] && [ -L "$full" ]; then printf 'deny cited cited note is a symlink (refused): %s\n' "$cut"; return 0; fi
        if [ "$why" = ok ] && [ ! -f "$full" ]; then why=notfound; fi
        if [ "$why" = notfound ]; then
            spaced=$(kb_spaced "$block" "$c")
            if [ -n "$spaced" ]; then
                printf 'deny cited cited note path has a space ("%s"): a path is one unbroken token; cite the note without the space\n' "$(kb_u8_cut "$spaced" 120)"
            else
                printf 'deny cited cited note not found in the library: %s\n' "$cut"
            fi
            return 0
        fi
        files="$files$full
"
    done <<EOF
$cites
EOF
    excerpts=$(kb_excerpts "$block")
    if [ -z "$excerpts" ]; then
        printf '%s\n' "deny cited a cited verdict needs at least one verbatim excerpt (30 or more bytes in double quotes)"; return 0
    fi
    while IFS= read -r ex; do
        [ -n "$ex" ] || continue
        m=$((m + 1)); pat=$ex; why=no
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            if LC_ALL=C tr -s '[:space:]' ' ' < "$f" | LC_ALL=C grep -F -q -- "$pat"; then why=yes; break; fi
        done <<EOF2
$files
EOF2
        if [ "$why" = no ]; then
            printf '%s\n' "deny cited excerpt not found in the cited notes: \"$(kb_u8_cut "$ex" 40)\" (quote the note's own lines, not the lookup's L<n> § lines)"; return 0
        fi
    done <<EOF
$excerpts
EOF
    printf 'allow cited %s notes, %s excerpts\n' "$n" "$m"
}

# kb_decide <block> <kdir> <state_dir> <window>: exactly one line (see the header).
kb_decide() {
    local block="$1" verdict bytes k
    [ -n "${KB_DATE_KIND:-}" ] || kb_detect_date
    if [ -z "$block" ]; then
        printf '%s\n' "deny missing no KNOWLEDGE field: no line of the brief starts with KNOWLEDGE: or WISSEN:"; return 0
    fi
    verdict=$(kb_verdict "$block"); bytes=$(kb_bytes "$block")
    if [ "$bytes" -ge 4000 ]; then
        printf 'deny %s KNOWLEDGE block is 4000 bytes or more (%s); keep it under 4000 bytes\n' "$verdict" "$bytes"; return 0
    fi
    case "$verdict" in
        cited) kb_decide_cited "$block" "$2" ;;
        none)
            if ! kb_has_sets "$block"; then
                printf '%s\n' 'deny none a none-relevant verdict must name the sets searched (sets: "…" | "…")'; return 0
            fi
            k=$(kb_fresh_lines "$3/knowledge-agent-lookups" "$4" | LC_ALL=C awk -F '\t' '$2 != "" && !($2 in seen) { seen[$2] = 1; n++ } END { print n + 0 }')
            if [ "$k" -ge 2 ]; then printf 'allow none %s searches in window\n' "$k"
            else printf 'deny none a none-relevant verdict needs two knowledge-agent runs in this session within the last %ss (found %s)\n' "$4" "$k"; fi ;;
        unavailable)
            k=$(kb_fresh_lines "$3/knowledge-agent-dispatches" "$4" | LC_ALL=C wc -l | tr -d ' ')
            if [ "$k" -ge 1 ]; then printf 'allow unavailable %s\n' "$(kb_reason "$block")"
            else printf 'deny unavailable an unavailable verdict needs a knowledge-agent dispatch in this session within the last %ss (found none)\n' "$4"; fi ;;
        *)
            if printf '%s' "$block" | LC_ALL=C grep -q '\.md'; then
                printf '%s\n' "deny invalid the brief names no note outside its sets clause and double quotes: a .md inside sets: or quotes does not count"
            else
                printf '%s\n' "deny invalid no verdict: the body needs a none-phrase, the word unavailable with a reason, or a cited .md note (at least 40 bytes)"
            fi ;;
    esac
}

# kb_mark_dispatch <state_dir>: appends "<ts>\tknowledge-agent" to knowledge-agent-dispatches (0600).
kb_mark_dispatch() {
    ( umask 077 && printf '%s\tknowledge-agent\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$1/knowledge-agent-dispatches" ) && chmod 600 "$1/knowledge-agent-dispatches"
}

# kb_counter_key <subagent_type> <description> <prompt>: the key of the denial counter (sha1 hex of the
# subagent and the description, else the first 200 bytes of the prompt). Prints nothing when no sha1 tool exists.
kb_counter_key() {
    local keytext hasher=""
    keytext="$2"
    [ -n "$keytext" ] || keytext=$(printf '%s' "$3" | cut -c1-200)
    command -v shasum >/dev/null 2>&1 && hasher=shasum
    [ -n "$hasher" ] || { command -v sha1sum >/dev/null 2>&1 && hasher=sha1sum; }
    [ -n "$hasher" ] || return 1
    printf '%s\n%s' "$1" "$keytext" | "$hasher" 2>/dev/null | awk '{ print $1 }'
}
