#!/bin/bash
# shellcheck shell=bash
# shellcheck disable=SC2034 # the globals this file sets (PICK*, TAKE_DETAIL, EXPIRED) are read by knowledge-inject.sh
# knowledge-inject-lib.sh — helpers of knowledge-inject.sh (IMP-268; split off for the line budget)
# ─────────────────────────────────────────────────────────────────────────────
# Sourced by hooks/knowledge-inject.sh. Functions only: sourcing has no side effects. The
# functions read globals the hook sets before its mode runs: KDIR, AGENTS_DIR, QUEUE, QUEUE_TTL,
# STATE_DIR, EXPIRED, PICK, PICK_LEAD, PICK_NOTE, TAKE_DETAIL, BLOCK, and the hook's log_line,
# acquire_lock, release_lock and kdir helpers.
#
#   para_*            the subagent paragraphs: the automatic floor (IMP-267), lead-supplied (IMP-268);
#                     every paragraph has a Bash-less variant that names Read or Grep, never bash
#   para_reserve      bytes the longest paragraph needs after a block (the block is cut to fit)
#   is_bashless TYPE  0 when agents/<type>.md declares a tools list without Bash
#   queue_append / denial_count   the queue line of a dispatch; the check hook's denial count (kb_counter_key)
#   take_queued TYPE  pops the oldest queue entry of TYPE; the caller holds the queue lock. Two or
#                     more unexpired entries of TYPE: ambiguous, PICK_LEAD forced to "" (see the hook header)
# ─────────────────────────────────────────────────────────────────────────────

# kdir_tail: the clause that makes a Read of a mirror note count as a lookup.
kdir_tail() { printf '%s' "a Read of a note under $KDIR/mirror/ also counts"; }

gate_text() { if [ "${KG_OFF:-0}" = 1 ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; } # gate_text DEFAULT OFF: OFF when KG_OFF=1 (CLAUDE_KNOWLEDGE_GATE=off)

# para_mandatory: the floor paragraph for an agent that has Bash (IMP-267).
para_mandatory() {
    printf '%s' "$(gate_text "Knowledge-first (IMP-267): before your first Write/Edit run ONE library lookup: bash ~/.claude/scripts/knowledge-lookup.sh --max 6 \"<your own words>\" --alt \"<German/English translation>\" --alt \"<technical terms>\"; judge by the » lines; open only the top note's section ($(kdir_tail)). The knowledge gate denies the first edit without it." "Knowledge library (IMP-267): when your unit touches an area the brief does not cover, run one lookup: bash ~/.claude/scripts/knowledge-lookup.sh --max 6 \"<your own words>\" --alt \"<German/English translation>\" --alt \"<technical terms>\"; judge by the » lines; open only the top note's section (a Read of a note under $KDIR/mirror/ works as well).")"
}

# para_bashless_block: the floor paragraph for a Bash-less agent when a block was queued (IMP-267).
para_bashless_block() {
    printf '%s' "$(gate_text "You have no Bash tool: the block above is your library lookup; $(kdir_tail). The gate lets you through." "You have no Bash tool: the block above is the automatic library lookup for this dispatch; for a further lookup, Read or Grep one note under $KDIR/mirror/.")"
}

# para_bashless_noblock: the floor paragraph for a Bash-less agent when nothing was queued (IMP-267).
para_bashless_noblock() {
    printf '%s' "$(gate_text "You have no Bash tool and no library block was queued for this dispatch: $(kdir_tail) as your library route." "You have no Bash tool and no library block was queued for this dispatch; when your unit touches an area the brief does not cover, Read or Grep one note under $KDIR/mirror/.")"
}

# para_lead_cited: the Lead cited notes; the brief is the subagent's lookup (IMP-268). No hits.
para_lead_cited() {
    printf '%s' "$(gate_text "Knowledge-first (IMP-268): your brief carries library knowledge the Lead selected for this unit (the KNOWLEDGE field); it counts as your lookup for the knowledge gate. Open the cited notes' sections when you need more. When you move to an area the brief does not cover, run bash ~/.claude/scripts/knowledge-lookup.sh --max 6 \"<your own words>\" --alt \"<German/English translation>\" --alt \"<technical terms>\" yourself." "Knowledge library (IMP-268): your brief carries library knowledge the Lead selected for this unit (the KNOWLEDGE field). Open the cited notes' sections when you need more. When you move to an area the brief does not cover, run bash ~/.claude/scripts/knowledge-lookup.sh --max 6 \"<your own words>\" --alt \"<German/English translation>\" --alt \"<technical terms>\" yourself.")"
}

# para_lead_cited_bashless: the same paragraph for a Bash-less agent: the bash sentence becomes a Read or Grep (IMP-268).
para_lead_cited_bashless() {
    local p
    p=$(para_lead_cited)
    printf '%s' "${p%%When you move to an area*}Read or Grep one note under the library mirror when you leave the brief's area."
}

# para_lead_none_hits: the Lead found nothing; the automatic floor hits are delivered (IMP-268).
para_lead_none_hits() {
    printf '%s' "$(gate_text "Knowledge-first (IMP-268): the Lead searched the library twice for this unit and found nothing relevant; the hits above are the automatic floor. Judge them by the » lines. Your first Write/Edit is allowed without a further lookup; search yourself when you move to an area the brief does not cover." "Knowledge library (IMP-268): the Lead searched the library for this unit and found nothing relevant; the hits above are the automatic floor. Judge them by the » lines. Search yourself when you move to an area the brief does not cover.")"
}

# para_lead_none_hits_bashless: the same for a Bash-less agent (IMP-268).
para_lead_none_hits_bashless() {
    printf '%s' "$(gate_text "Knowledge-first (IMP-268): the Lead searched the library twice for this unit and found nothing relevant; the hits above are the automatic floor. Judge them by the » lines. Your first Write/Edit is allowed without a further lookup; Read or Grep one note under the library mirror when you move to an area the brief does not cover." "Knowledge library (IMP-268): the Lead searched the library for this unit and found nothing relevant; the hits above are the automatic floor. Judge them by the » lines. Read or Grep one note under the library mirror when you move to an area the brief does not cover.")"
}

# para_lead_none_empty: the Lead found nothing and no hits are attached (IMP-268). The text claims no
# floor search: with retrieval off there was none.
para_lead_none_empty() {
    printf '%s' "$(gate_text "Knowledge-first (IMP-268): the Lead searched the library twice for this unit and found nothing relevant; no automatic hits are attached to this dispatch. Your first Write/Edit is allowed without a further lookup; search yourself when you move to an area the brief does not cover." "Knowledge library (IMP-268): the Lead searched the library for this unit and found nothing relevant; no automatic hits are attached to this dispatch. Search yourself when you move to an area the brief does not cover.")"
}

# para_lead_none_empty_bashless: the same for a Bash-less agent (IMP-268).
para_lead_none_empty_bashless() {
    printf '%s' "$(gate_text "Knowledge-first (IMP-268): the Lead searched the library twice for this unit and found nothing relevant; no automatic hits are attached to this dispatch. Your first Write/Edit is allowed without a further lookup; Read or Grep one note under the library mirror when you move to an area the brief does not cover." "Knowledge library (IMP-268): the Lead searched the library for this unit and found nothing relevant; no automatic hits are attached to this dispatch. Read or Grep one note under the library mirror when you move to an area the brief does not cover.")"
}

# para_reserve: bytes for the longest subagent paragraph plus the 2-byte separator.
para_reserve() {
    local most=0 n p
    for p in "$(para_mandatory)" "$(para_bashless_block)" "$(para_bashless_noblock)" \
        "$(para_lead_cited)" "$(para_lead_cited_bashless)" "$(para_lead_none_hits)" "$(para_lead_none_hits_bashless)" \
        "$(para_lead_none_empty)" "$(para_lead_none_empty_bashless)"; do
        n=$(printf '%s' "$p" | LC_ALL=C wc -c | tr -d ' ')
        if [ "$n" -gt "$most" ]; then most=$n; fi
    done
    printf '%s' $((most + 2))
}

# is_bashless AGENT_TYPE: 0 when agents/<type>.md has a tools list without Bash. A missing
# tools key means all tools (Bash included), so it is not Bash-less. Accepts block lists at
# any indentation, inline lists (also [bracketed]) and Bash(...) forms.
is_bashless() {
    local file verdict
    case "$1" in ''|*[!A-Za-z0-9_:.-]*|*..*) return 1 ;; esac
    file="$AGENTS_DIR/$1.md"
    [ -f "$file" ] || return 1
    verdict=$(awk '
        NR == 1 && $0 != "---" { exit }
        NR > 1 && $0 == "---" { exit }
        /^tools:/ { intools = 1; split(substr($0, 7), parts, ","); for (p in parts) tok(parts[p]); next }
        intools && /^[ \t]*-/ { item = $0; sub(/^[ \t]*-[ \t]*/, "", item); tok(item); next }
        intools && /^[^ \t-]/ { intools = 0 }
        function tok(t) {
            gsub(/\[|\]/, "", t); gsub(/^[ \t]+|[ \t,]+$/, "", t); sub(/^"/, "", t); sub(/"$/, "", t)
            if (t ~ /^Bash([ (]|$)/) hasbash = 1
            if (t != "") present = 1
        }
        END { if (present && !hasbash) print "bashless" }' "$file")
    [ "$verdict" = "bashless" ]
}

# queue_append AGENT_TYPE DESCRIPTION LEAD: one JSON line per queued entry, under the lock.
# LEAD is cited | none | "" (no lead-supplied verdict; the entry carries the automatic floor).
queue_append() {
    local line
    if ! line=$(jq -nc --arg ts "$(ts)" --arg agent_type "$1" --arg description "$2" --arg block "$BLOCK" \
        --arg lead "$3" \
        '{ts: $ts, agent_type: $agent_type, description: $description, block: $block, lead_supplied: $lead}'); then
        printf 'knowledge-inject: cannot build queue line for %s\n' "$1" >&2
        return 0
    fi
    acquire_lock || log_line queue-lock-timeout "append without lock after 20 tries"
    if ! { printf '%s\n' "$line" >> "$QUEUE"; } 2>/dev/null; then
        printf 'knowledge-inject: cannot append %s\n' "$QUEUE" >&2
    fi
    release_lock
}

# denial_count SUBAGENT DESCRIPTION PROMPT: the check hook's denial count for this brief (0 when unknown).
denial_count() {
    local key count=""
    key=$(kb_counter_key "$1" "$2" "$3") || key=""
    if [ -n "$key" ]; then count=$(cat "$STATE_DIR/brief-denials-$key" 2>/dev/null); fi
    case "$count" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$count" ;; esac
}

# take_queued AGENT_TYPE (the caller holds the lock): drops entries older than QUEUE_TTL, then
# pops the oldest entry whose agent_type equals AGENT_TYPE. Sets PICK, PICK_LEAD (the entry's
# lead_supplied; "" for entries written before IMP-268), PICK_NOTE, TAKE_DETAIL and EXPIRED.
# Ambiguity (two or more unexpired entries of the type): PICK_LEAD is forced to "" and PICK_NOTE
# gains ambiguous-queue=<n>. Returns 0 taken, 1 nothing taken (TAKE_DETAIL says why), 2 queue
# unreadable (nothing changed), 3 rewrite failed (nothing taken).
take_queued() {
    local now tmp summary n i m
    now=$(date +%s)
    tmp=$(mktemp "$STATE_DIR/queue.XXXXXX") || return 3
    if ! jq -c --argjson now "$now" --argjson ttl "$QUEUE_TTL" \
        'select(($now - (.ts | fromdateiso8601)) <= $ttl)' "$QUEUE" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 2
    fi
    EXPIRED=$(( $(jq -s length "$QUEUE") - $(jq -s length "$tmp") ))
    summary=$(jq -sc --arg t "$1" '{n: length, i: (map(.agent_type == $t) | index(true)), m: (map(select(.agent_type == $t)) | length)}' "$tmp") \
        || { rm -f "$tmp"; return 2; }
    n=$(printf '%s' "$summary" | jq -r '.n') || { rm -f "$tmp"; return 2; }
    i=$(printf '%s' "$summary" | jq -r '.i // empty') || { rm -f "$tmp"; return 2; }
    m=$(printf '%s' "$summary" | jq -r '.m') || { rm -f "$tmp"; return 2; }
    if [ -z "$i" ]; then
        { mv -f "$tmp" "$QUEUE"; } || { rm -f "$tmp"; return 3; }
        if [ "$n" -eq 0 ]; then TAKE_DETAIL="queue-empty"; else TAKE_DETAIL="no-type-match"; fi
        return 1
    fi
    PICK=$(jq -sr --argjson i "$i" '.[$i].block' "$tmp") || { rm -f "$tmp"; return 2; }
    PICK_LEAD=$(jq -sr --argjson i "$i" '.[$i].lead_supplied // ""' "$tmp") || { rm -f "$tmp"; return 2; }
    PICK_NOTE="matched=$1"
    if [ "$m" -ge 2 ]; then PICK_LEAD=""; PICK_NOTE="$PICK_NOTE ambiguous-queue=$m"; fi
    if ! jq -sc --argjson i "$i" 'del(.[$i]) | .[]' "$tmp" > "$tmp.next" \
        || ! mv -f "$tmp.next" "$QUEUE"; then
        rm -f "$tmp" "$tmp.next"
        return 3
    fi
    rm -f "$tmp"
    return 0
}
