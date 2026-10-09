#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
# shellcheck disable=SC2034 # variables are assigned for the other files sourced into this shell, not read here
# shellcheck disable=SC2126 # grep | wc -l is deliberate: the count is taken from a pipe fed by find/ls
# knowledge-mirror-regression cases: fixtures and helpers (invented values; frontmatter SHAPE only).
# Sourced by scripts/tests/knowledge-mirror-regression.sh (never run on its own); shares its
# helpers, fixtures and variables (T H C K run check ok bad ...) and its order of cases.

# ---- fixtures (invented values; frontmatter SHAPE only) ----------------------
# EXPECT counts allowlisted fixture files (the expected copy set, derived here
# rather than hard-coded in each case); hard-excluded decoys are not counted.
EXPECT=0
fx() { EXPECT=$((EXPECT+1)); }
mkdir -p "$C/logbook" "$C/projects/-proj-a/memory" "$C/projects/-proj-b/memory" \
         "$C/projects/vault/memory" "$C/plans" "$C/rules" "$C/vault" "$C/global-observation" \
         "$C/docs/archive/rules-evidence" "$C/docs/adr" "$C/docs/nested"
printf '# Log one\nbody\n' > "$C/logbook/2026-01-01.md"; fx
printf '# Log two\nbody\n' > "$C/logbook/2026-01-02.md"; fx
printf '{"a":1}\n' > "$C/logbook/noise.jsonl"
printf -- '---\nname: sample-memory\ndescription: invented see `rules/a.md` here\nmetadata:\n  type: feedback\n---\nBody text.\n' \
  > "$C/projects/-proj-a/memory/sample.md"; fx
printf -- '- [sample](sample.md) - index\n' > "$C/projects/-proj-a/memory/MEMORY.md"; fx
printf -- '%s\n' "$SENTINEL" > "$C/projects/-proj-a/memory/secret.local.md"
printf '# Plan\n' > "$C/plans/meta-proposal-2026-01-01.md"; fx
printf '# Other plan\n' > "$C/plans/not-a-proposal.md"
printf '# Rule A\n' > "$C/rules/a.md"; fx
printf '# Rule B\n' > "$C/rules/b.md"; fx
cat > "$C/rules/refs.md" <<'EOF'
# Refs
See `docs/adr/0001-x.md` and `docs/nested/skip.md`.
Line ref `rules/a.md:12` and `~/.claude/CONTEXT.md` and `rules/missing.md`.
Bare [[a]] and [[unknown-bare]].
Anchor `rules/a.md#top`.
---
```text
fenced `rules/a.md` and [[fenced-ghost]] and [[a]]
```
tail line
EOF
fx
printf -- '---\nno closing marker here\n' > "$C/rules/unclosed.md"; fx
printf '%s\n' "$SENTINEL" > "$C/rules/zz-private.local.md"
# Hunt-list shapes: a REAL memory note with top-level type:/source: keys, CRLF and
# frontmatter-only/empty files, partial path matches, a name with a space.
printf -- '---\nname: real-memory\ntype: feedback\nsource: web\n---\nReal body.\n' > "$C/projects/-proj-a/memory/real.md"; fx
printf -- '---\r\nname: crlf\r\n---\r\nCrlf body `rules/a.md` end\r\n' > "$C/rules/crlf.md"; fx
printf -- '---\nname: fmonly\n---\n' > "$C/rules/fmonly.md"; fx
printf -- '---\n---\n' > "$C/rules/fmempty.md"; fx
printf '# Partial\n`scripts/rules/a.md` `docs/adr/top.md` `docs/0001-x.md` `rules/a.md.bak` `xrules/a.md`\n' > "$C/rules/partial.md"; fx
printf '# Spaced\n' > "$C/rules/with space.md"; fx
printf '# Spaced ref\nBare [[with space]] and [[rules/with space]].\n' > "$C/docs/spaced-ref.md"; fx
# Any file name is linkable: non-ASCII (e-grave, 2 bytes) and every bare form (#heading, |alias).
NA="r$(printf '\303\250')gle"
printf '# Non-ASCII rule\n' > "$C/rules/$NA.md"; fx
printf '# Forms\nAnchor [[a#top]] alias [[a|the rule]] both [[a#top|al]].\nNonascii bare [[%s]] and `rules/%s.md` and `rules/with space.md`.\n' "$NA" "$NA" > "$C/rules/forms.md"; fx
printf '# Evidence A\nwhy a\n'> "$C/docs/archive/rules-evidence/a.md"; fx
printf '# Evidence orphan\n' > "$C/docs/archive/rules-evidence/orphan.md"; fx
printf '# ADR one\n' > "$C/docs/adr/0001-x.md"; fx
printf '# Top\nSee [[ghost]], [[orphan]], [[rules/b]].\n' > "$C/docs/top.md"; fx
printf '# Orphan doc\n' > "$C/docs/orphan.md"; fx
printf 'NESTED-MUST-NOT-COPY\n' > "$C/docs/nested/skip.md"
printf '# Context\nterms\n' > "$C/CONTEXT.md"; fx
for x in docs/archive/rules-evidence/x docs/adr/y docs/z; do printf '%s\n' "$SENTINEL" > "$C/$x.local.md"; done
# REACHABLE vault decoy: matches projects/*/memory/*.md, so only the /vault/
# hard exclude keeps it out. ($C/vault/decoy.md below is outside every glob and
# only a bystander.)
printf '%s\n' "$VSENTINEL" > "$C/projects/vault/memory/decoy.md"
printf '%s\n' "$VSENTINEL" > "$C/vault/decoy.md"
cat > "$C/global-observation/improvement-ledger.json" <<'EOF'
{
  "lastUpdated": "2026-01-05",
  "batchA": {"entries": [
    {"id": "IMP-001", "status": "proposed", "title": "Dup first", "notes": "FIRST-VERSION-MUST-LOSE"},
    {"id": "IMP-002", "status": "implemented", "title": "Second", "category": "cat-b", "riskLevel": "low",
     "proposedAt": "2026-01-02", "implementedAt": "2026-01-03",
     "notes": "Verbatim note text.", "evidence": "Verbatim evidence text.",
     "filesModified": ["rules/a.md", "scripts/other.sh"], "filesCreated": ["docs/adr/0001-x.md"],
     "verification": {"measured": null}},
    {"id": "IMP-003", "title": "No status entry"}]},
  "batchB": {"entries": [
    {"id": "IMP-001", "status": "implemented", "title": "Dup last", "category": "cat-a", "riskLevel": "medium",
     "proposedAt": "2026-01-01", "implementedAt": null,
     "verification": {"kpi": "kpi-x", "baseline": 1, "target": 2, "measured": "2", "measuredAt": "2026-01-04", "note": "note-x"}},
    {"id": "OTHER-7", "title": "Not an IMP id"},
    {"id": "IMP-004", "status": "proposed", "title": "Holds a reference",
     "relatedTo": [{"id": "IMP-002", "reason": "STUB-MUST-NOT-REPLACE-IMP-002"}]},
    {"id": "IMP-005", "status": "proposed", "title": "Fix [a] [b](c) ]] stray [["},
    {"id": "IMP-006", "status": "proposed", "title": "Hostile notes",
     "notes": "first line\n---\n## Fake heading\n```\nunclosed fence `rules/a.md`", "evidence": "plain evidence",
     "filesModified": ["rules/a.md"]},
    {"id": "IMP-007", "status": "implemented", "title": "Files with trailing notes",
     "filesModified": ["rules/a.md: two valid forms of reference", "rules/with space.md (new, always-loaded) more words",
       "docs/adr/0001-x.md: first ADR", "~/.claude/CONTEXT.md — glossary", "rules/a.md:12",
       "scripts/x.sh: not a mirrored path", "rules/missing.md: absent target"],
     "filesCreated": ["see rules/a.md"]}]},
  "activeImprovements": {"IMP-077": {"id": "IMP-077", "status": "x", "title": "OUT-OF-SCOPE-CONTAINER"}},
  "improvementQueue": {"priority_high": [
    {"id": "IMP-900", "status": "queued", "title": "Queue item", "category": "cat-q", "riskLevel": "high"}]}
}
EOF
# Ledger notes expected by the contract (not computed from the file with the
# implementation's own walk): unique IMP ids in <batch>.entries and
# improvementQueue.priority_*: 001 (duplicate, last wins) 002 003 004 005 006 007 900.
# OTHER-7 (not IMP-*), the nested relatedTo object and activeImprovements/IMP-077 add none.
LEDGER_IDS="IMP-001 IMP-002 IMP-003 IMP-004 IMP-005 IMP-006 IMP-007 IMP-900"
NIDS=8
EXPECT_TOTAL=$((EXPECT + NIDS + 1)) # copies + ledger notes + ledger.md index

# run <args...> — runs the real script; sets RC, OUT, ERR. Env: K as target.
run() {
  ( cd "$RUN_CWD" && env -u CLAUDE_BAUHOF_ROOT HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K" "${EXTRA_ENV[@]}" \
    /bin/bash "$KM" $RUN_FLAGS "$@" >"$T/out" 2>"$T/err" )
  RC=$?; OUT="$(cat "$T/out")"; ERR="$(cat "$T/err")"
}
# The v2 cases below pin the v2 link behaviour: they run with --no-v3-links. The v3 files
# (km-cases-v3-*.sh) clear RUN_FLAGS and test the default run.
RUN_FLAGS=--no-v3-links
GM=2; export GM # generated dated: / dated_from: lines after kind:/origin: in a source copy (no session id in the fixtures)
EXTRA_ENV=(A=1)
RUN_CWD="$T"
tree_count() { find "$T" -mindepth 1 | grep -v -e '/out$' -e '/err$' | wc -l | tr -d ' '; }
first_err_ok() { printf '%s\n' "$ERR" | head -1 | grep -q '^knowledge-mirror: refuse:'; }
# Expected graph totals, derived from the fixtures above: a.md Evidence edge 1;
# refs.md 5 resolved + 1 dangling (unknown-bare); top.md 1 resolved + ghost
# dangling + orphan ambiguous (evidence/ and docs/); IMP-002 Files 2; index 8;
# crlf.md 1; spaced-ref.md 2; IMP-006 Files 1 (its unclosed fence is closed by the
# mirror, so the Files link stays visible); the bracket title adds none;
# forms.md 6 (three anchor/alias forms, bare and backtick non-ASCII, spaced backtick);
# IMP-007 Files 5 (the leading path of each note-carrying entry that is mirrored).
EXP_LINKS="35 resolved=32 ambiguous=1 dangling=2"
crline() { sed -n "$2p" "$1" | LC_ALL=C grep -q "$(printf '\r')\$"; } # line $2 of $1 ends in CR
no_dup_keys() { # no top-level key twice inside any frontmatter block under mirror/ (js-yaml, i.e. Obsidian, rejects that)
  find "$K/mirror" -type f -name '*.md' -print0 | xargs -0 awk '
    FNR == 1 { fm = ($0 ~ /^---\r?$/); split("", seen); next }
    fm && /^---\r?$/ { fm = 0; next }
    fm && match($0, /^[A-Za-z_][A-Za-z0-9_-]*[ \t]*:/) { k = substr($0, 1, RLENGTH - 1); sub(/[ \t]+$/, "", k)
      if (k in seen) { print FILENAME ": duplicate key " k; bad = 1 }; seen[k] = 1 }
    END { exit bad }'
}
every_copy_one_kind() { # every row of hashes.tsv: the copy has exactly one top-level kind: line; the row count is TOTAL
  local rel n=0
  while IFS="$(printf '\t')" read -r rel _; do
    [ "$(grep -c '^kind: ' "$K/mirror/$rel")" = 1 ] || { echo "not exactly one kind: in $rel"; return 1; }
    n=$((n + 1))
  done < "$K/mirror/.state/hashes.tsv"
  [ "$n" = "$EXPECT_TOTAL" ] || { echo "rows $n != $EXPECT_TOTAL"; return 1; }
}
prov_after_fm() { # file: line 1 is ---, the line after the closing --- is the provenance comment
  awk 'NR==1 && $0!="---"{exit 1} /^---$/{n++; if(n==2){getline l; exit !(l ~ /^<!-- knowledge-mirror: /)}} END{if(n<2)exit 1}' "$1"
}
export -f prov_after_fm crline
no_leak_names() { ! printf '%s\n%s\n' "$OUT" "$ERR" | grep -E '\.local\.md|vault/|\.jsonl' >/dev/null; }
