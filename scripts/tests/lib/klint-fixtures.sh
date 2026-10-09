#!/usr/bin/env bash
# shellcheck shell=bash
# klint-fixtures.sh — synthetic mirrors for knowledge-lint-regression.sh. Sourced, never run.
# Everything is invented and lives under $T (set by the runner). One mirror root per report group:
#   R1 per-note codes · R4 pinned summary · R2 contradictions · R6 refs · R3 graph (+R3B/R3C variants)
PROV='<!-- knowledge-mirror: copied from ~/.claude/x.md at 2026-10-08T12:00:00Z; read-only copy, edits are refused on the next run -->'

# mn <root> <proj> <file> <type|-> <desc|-> [body line...]; optional env: SID (originSessionId),
# XFM (extra top-level frontmatter lines, newline separated).
mn() {
  local proj="$2" d="$1/mirror/memory/$2" f="$3" typ="$4" desc="$5"; shift 5
  mkdir -p "$d"
  {
    echo "---"; echo "kind: memory"; echo "origin: \"~/.claude/projects/$proj/memory/$f\""; echo "name: ${f%.md}"
    if [ "$desc" != "-" ]; then echo "description: $desc"; fi
    echo "metadata: "; echo "  node_type: memory"
    if [ "$typ" != "-" ]; then echo "  type: $typ"; fi
    if [ -n "${SID:-}" ]; then echo "  originSessionId: $SID"; fi
    echo "  modified: 2026-01-01T00:00:00.000Z"
    if [ -n "${XFM:-}" ]; then printf '%s\n' "$XFM"; fi
    echo "---"; echo "$PROV"; printf '%s\n' "$@"
  } > "$d/$f"
}
raw() { local f=$1; shift; mkdir -p "$(dirname "$f")"; printf '%s\n' "$@" > "$f"; } # raw <file> <line>...
enc() { printf %s "$1" | sed 's/[^A-Za-z0-9-]/-/g'; } # folder name Claude Code derives from a path
WHY='**Why:** because 2026-01-02.'; HOW='**How to apply:** do it.'

# ---- R1: one note per code / exemption ---------------------------------------
R1="$T/r1"; A=projA
mn "$R1" $A good.md feedback "a fine note" "Never skip the check." "$WHY" "$HOW" "[[good]] and [[memory/projA/good]] resolve."
mn "$R1" $A nodesc.md feedback - "Never skip." "$WHY" "$HOW"
mn "$R1" $A nowhy.md feedback "d" "Always x." "$HOW 2026-01-01"
mn "$R1" $A nohow.md project "d" "Always x." "$WHY"
mn "$R1" $A refexempt.md reference "d" "A fact, 2026-01-01."
mn "$R1" $A userexempt.md user "d" "A person, 2026-01-01."
mn "$R1" $A untyped.md - "d" "A fact, 2026-01-01."
mn "$R1" $A badtype.md weird "d" "A fact, 2026-01-01." "$WHY" "$HOW"
mn "$R1" $A nodate.md reference "d" "A fact without any date."
mn "$R1" $A descdate.md reference "fixed on 2026-03-03" "A fact without a body date."
XFM="dated: 2026-02-02" mn "$R1" $A datedkey.md reference "d" "A fact."
XFM=$'dated: 2026-02-02\ndated_from: mtime' mn "$R1" $A datedmtime.md reference "d" "A fact."
mn "$R1" $A big.md reference "d" "Big 2026-01-01." "$(awk 'BEGIN { for (i = 0; i < 400; i++) print "padding padding padding padding"; }')"
mn "$R1" $A small.md reference "d" "Small 2026-01-01."
XFM="status: bogus" mn "$R1" $A stbad.md reference "d" "x 2026-01-01"
XFM=$'status: superseded\nsuperseded_by: memory/projA/good.md' mn "$R1" $A stok.md reference "d" "x 2026-01-01"
XFM="status: active" mn "$R1" $A stactive.md reference "d" "x 2026-01-01"
XFM=$'status: archived\nsuperseded_by: memory/projA/gone.md' mn "$R1" $A stgone.md reference "d" "x 2026-01-01"
XFM=$'status: superseded\nsuperseded_by: "[[memory/projA/good|alias]]"' mn "$R1" $A stwrap.md reference "d" "x 2026-01-01"
XFM=$'status: superseded\nsuperseded_by: ./memory/projA/good' mn "$R1" $A stnoext.md reference "d" "x 2026-01-01"
XFM="backfilled: 2026-10-09" mn "$R1" $A backfilled.md reference "d" "A fact without a real date."
XFM="valid_from: 2026-02-02" mn "$R1" $A validfrom.md reference "d" "A fact."
XFM=$'kind: imp\nstatus: bogus\nsuperseded_by: memory/projA/nope.md' mn "$R1" $A impstatus.md reference "d" "x 2026-01-01"
mn "$R1" $A dang.md reference "d" "2026-01-01" "[[nonexistent-xyz]] and [[memory/projA/nope]]" '`[[in-code]]` inline' '```' '[[in-fence]]' '```' "[[dupname]]"
mn "$R1" $A dupname.md reference "d" "x 2026-01-01"
mn "$R1" projB dupname.md reference "d" "x 2026-01-01"
raw "$R1/mirror/memory/$A/nofm.md" "no frontmatter here 2026-01-01"
raw "$R1/mirror/memory/$A/unclosed.md" "---" "name: x"
raw "$R1/mirror/memory/$A/MEMORY.md" "- [[nonexistent-idx]] index entry" "- [[good]]"
raw "$R1/mirror/rules/r.md" "# rule" "[[never-scanned-dangling]]"
for c in "claim-date|2026-05-01 we did it." "claim-status|Status: done" "claim-stand|**Stand** 1.5" "claim-state|State of the build" \
  "claim-on|On Monday I tried it" "claim-am|Am Montag habe ich" "claim-during|During the migration" "claim-today|Today we fixed it" \
  "claim-yesterday|Yesterday it broke" "claim-insession|In this session we found" "claim-session|Session notes follow"; do
  mn "$R1" $A "${c%%|*}.md" reference "d" "${c#*|}" "2026-01-01"
done
mn "$R1" $A claim-ok.md reference "d" "**Never** squash merge." "2026-01-01"
mn "$R1" $A claim-online.md reference "d" "Online mode is required." "2026-01-01"
mn "$R1" $A claim-statement.md reference "d" "Statement of intent is a claim." "2026-01-01"
mn "$R1" $A locked.md reference "d" "Locked 2026-01-01."
chmod 000 "$R1/mirror/memory/$A/locked.md"
if [ -r "$R1/mirror/memory/$A/locked.md" ]; then UNREADABLE_OK=0; chmod 644 "$R1/mirror/memory/$A/locked.md"; else UNREADABLE_OK=1; fi

# ---- R4: tiny mirror with a hand-computed summary -------------------------------
R4="$T/r4"
mn "$R4" p a.md feedback "d" "Never X." "$WHY" "$HOW"
mn "$R4" p b.md project - "Status: x"
mn "$R4" p c.md reference "d" "Fact 2026-01-02." "[[zzz]]"

# ---- R2: contradiction rules ------------------------------------------------------
R2="$T/r2"
mn "$R2" p1 launch_pending.md project "Launch of the widget" "Launch is pending."
mn "$R2" p1 launch_done.md project "Launch of the widget" "The launch is completed."
mn "$R2" p1 tok-a.md project "alpha beta gamma checkout rollout" "Rollout planned."
mn "$R2" p1 tok-b.md project "alpha beta gamma checkout summary" "Rollout deployed and live."
mn "$R2" p1 neg-subject.md project "unrelated words entirely here" "all done and completed"
mn "$R2" p1 boundary-a.md project "zeta eta theta iota kappa" "work was abandoned, deliver soon"
mn "$R2" p1 boundary-b.md project "zeta eta theta iota kappa" "still planned"
mn "$R2" p1 dup.md reference "d" "same name 2026-01-01"
mn "$R2" p2 dup.md reference "d" "same name 2026-01-01"
mn "$R2" p5 solo_done.md project "Solo thing" "completed"
mn "$R2" p6 solo_pending.md project "Solo thing" "pending"
mn "$R2" p3 decl.md reference "d" "Old checkout \`$H/old-proj\` is abandoned."
mn "$R2" "$(enc "$H/old-proj")" stale.md reference "d" "stale note"
mn "$R2" p3 decl2.md reference "d" "~/old2 was retired in 2026."
mn "$R2" "$(enc "$H/old2")" stale2.md reference "d" "stale note two"
mn "$R2" p4 new.md reference "d" "[[old-claim]] is outdated now"
mn "$R2" p4 old-claim.md reference "d" "old claim"

# ---- R6: refs ---------------------------------------------------------------------------
R6="$T/r6"; U1=$(printf '%08d-%04d-%04d-%04d-%012d' 1 2 3 4 5); U2=$(printf '%08d-%04d-%04d-%04d-%012d' 6 7 8 9 10)
mkdir -p "$H/.claude/rules" "$H/.claude/scripts" "$H/.claude/projects/pp"
: > "$H/.claude/rules/exists.md"; : > "$H/.claude/scripts/x.sh"; echo '{"secret":"never read"}' > "$H/.claude/projects/pp/$U1.jsonl"
chmod 000 "$H/.claude/projects/pp/$U1.jsonl"
SID=$U1 mn "$R6" pj r1.md reference "d" 'see `rules/exists.md` and `hooks/missing.sh` and `~/.claude/scripts/x.sh --flag` plus `src/foo.ts`' '```' '`hooks/fenced-missing.sh`' '```' "2026-01-01"
SID=$U2 mn "$R6" pj r2.md reference "d" "no refs 2026-01-01"
mn "$R6" pj r3.md reference "d" "no session id 2026-01-01"
raw "$R6/mirror/rules/q.md" 'see `docs/gone.md`.'
raw "$R6/mirror/ledger/IMP-001.md" 'see `docs/gone2.md`.'
raw "$R6/mirror/plans/p.md" 'see `rules/exists.md`.'

# ---- R3: graph export (nodes: path kind status dated description; edges: src dst via; both with a header) ----
R3="$T/r3"
XFM="superseded_by: memory/p/n.md" mn "$R3" p m.md reference "d" "old 2026-01-01"
mn "$R3" p n.md reference "d" "new 2026-01-01"
mkdir -p "$R3/mirror/graph"
printf 'path\tkind\tstatus\tdated\tdescription\n' > "$R3/mirror/graph/nodes.tsv"
printf 'rules/a.md\trule\tactive\t2026-01-01\td\nrules/b.md\trule\tactive\t-\td\nevidence/a.md\tevidence\tactive\t-\td\n' >> "$R3/mirror/graph/nodes.tsv"
printf 'memory/p/m.md\tmemory\tsuperseded\t2026-01-01\td\nmemory/p/n.md\tmemory\tactive\t-\td\nmemory/p/o.md\tmemory\tactive\t-\td\n' >> "$R3/mirror/graph/nodes.tsv"
printf 'ledger/IMP-001.md\timp\tactive\t-\td\nledger/IMP-002.md\timp\tsuperseded\t-\td\n' >> "$R3/mirror/graph/nodes.tsv"
printf 'src\tdst\tvia\nrules/a.md\tevidence/a.md\tevidence\nevidence/a.md\trules/a.md\twikilink\nmemory/p/m.md\tmemory/p/n.md\twikilink\n' > "$R3/mirror/graph/edges.tsv"
printf 'rules/a.md\tmemory/p/o.md\tmentions\nrules/a.md\tmemory/p/o.md\tmentions\nrules/b.md\tledger/IMP-001.md\tsame-day\n' >> "$R3/mirror/graph/edges.tsv"
R3B="$T/r3b"; cp -R "$R3" "$R3B"; printf 'broken-row-only\n' >> "$R3B/mirror/graph/edges.tsv"
R3C="$T/r3c"; cp -R "$R3" "$R3C"; rm "$R3C/mirror/graph/edges.tsv"
# shim awk that exits 2 when its program text contains $KL_TEST_AWK_FAIL, else runs the real awk
mkdir -p "$T/shim"; REAL_AWK=$(command -v awk)
printf '#!/bin/sh\ncase "$*" in *"$KL_TEST_AWK_FAIL"*) exit 2 ;; esac\nexec %s "$@"\n' "$REAL_AWK" > "$T/shim/awk"; chmod +x "$T/shim/awk"
