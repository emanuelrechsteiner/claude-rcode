#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the bash -c bodies expand at run time, not here
# shellcheck disable=SC2034 # variables are assigned for the case files sourced after this one
# knowledge-mirror-regression v3: fixture home for generated dated keys, link hygiene, Mentions,
# the IMP trim and the graph export (invented values). Sourced by scripts/tests/knowledge-mirror-regression.sh
# before km-cases-v3-*.sh; shares its helpers and variables (T run check ok bad ...).

H3="$T/home-v3"; K3="$T/know-v3"; C3="$H3/.claude"
# session ids are assembled at run time: a literal id would look like a real one to the scrub gate
SID_PRESENT=$(printf '%s-%s-%s-%s-%s' 11111111 2222 4333 8444 555555555555)
SID_MISSING=$(printf '%s-%s-%s-%s-%s' aaaaaaaa bbbb 4ccc 8ddd eeeeeeeeeeee)
SID_BODY=$(printf '%s-%s-%s-%s-%s' 99999999 8888 4777 8666 555555555555)
MA="$C3/projects/-pa/memory"; MB="$C3/projects/-pb/memory"
mkdir -p "$MA" "$MB" "$C3/logbook" "$C3/plans" "$C3/rules" "$C3/docs/adr" "$C3/docs/archive/rules-evidence" "$C3/global-observation"
# memory, project -pa
printf -- '---\nname: alpha-note\ndescription: Alpha\nmetadata:\n  modified: 2026-02-01T10:00:00Z\n  originSessionId: %s\n---\nBody date 2026-03-05 loses to the frontmatter date.\nSelf [[alpha-note]], case+alias [[Beta|the beta]], own-folder [[consent]], other-folder [[shared]], fold-twin [[Twin_X]], ghost [[ghost-pa]].\nCode `[[beta]]` stays. Anchor [[beta#top]].\n' "$SID_PRESENT" > "$MA/alpha_note.md"
printf -- '---\nname: beta\ndescription: "Beta"\noriginSessionId: %s\n---\nDecided 2026-03-05, again 2026-07-07.\n' "$SID_MISSING" > "$MA/beta.md"
printf -- '---\nname: gamma\ndescription: "Gamma, set 2026-04-04"\n---\nNo date in the body.\n' > "$MA/gamma.md"
printf -- '---\nname: delta\n---\nNo date. Session in the body: %s\n' "$SID_BODY" > "$MA/delta.md"
touch -t 202601151200 "$MA/delta.md"
printf -- '---\nname: epsilon\ndescription: "set 2026-05-05"\n---\nbody 2026-06-06\n' > "$MA/epsilon.md"
printf -- '---\nname: zeta\ndescription: tab\there\nstatus: superseded\nsuperseded_by: memory/-pa/alpha_note.md\nvalid_from: 2026-01-01\nbackfilled: 2026-02-02\n---\nZeta 2026-01-02\n' > "$MA/zeta.md"
printf -- '---\nname: own\ndated: 2020-01-01\n---\nOwn dated key.\n' > "$MA/own.md"
# V-03 / V-19 / V-11 / V-12 shapes: backfill dates, session-id sources, a source owning every generated key
printf -- '---\nname: bfonly\nbackfilled: 2026-09-09\n---\nBody date 2026-05-09.\n' > "$MA/bfonly.md"
printf -- '---\nname: bfmt\nbackfilled: 2026-09-09\n---\nNo date.\n' > "$MA/bfmt.md"; touch -t 202601201200 "$MA/bfmt.md"
printf -- '---\nname: vfwin\nbackfilled: 2026-09-09\nmodified: 2026-03-01T10:00:00Z\nvalid_from: 2026-01-20\n---\nBody.\n' > "$MA/vfwin.md"
printf -- '---\nname: modok\nbackfilled: 2026-09-09\nmodified: 2026-03-01T10:00:00Z\n---\nBody.\n' > "$MA/modok.md"
printf -- '---\nname: sidkey\nrelated: %s\noriginSessionId: %s\n---\nBody 2026-08-08.\n' "$SID_BODY" "$SID_MISSING" > "$MA/sidkey.md"
printf -- '---\nname: sidfm\nnote: from %s\n---\nBody mentions %s\n' "$SID_PRESENT" "$SID_MISSING" > "$MA/sidfm.md"
printf -- '---\nname: ownall\nkind: custom\norigin: mine\ndated: 2020-01-01\ndated_from: manual\norigin_session: x\noriginSessionId: %s\n---\nOwns all.\n' "$SID_PRESENT" > "$MA/ownall.md"
printf 'Consent in a.\n' > "$MA/consent.md"; printf 'Twin dash.\n' > "$MA/twin-x.md"; printf 'Twin underscore.\n' > "$MA/twin_x.md"
printf 'Ord memory one 2026-01-01 [[rules/ord]]\n' > "$MA/ordm1.md"; printf 'Ord memory two 2026-05-01 [[rules/ord]]\n' > "$MA/ordm2.md"
printf '%s\n' '- [Alpha note](alpha_note.md) - hook a' '- [Beta with `code`](beta.md) - hook b' '- [Gamma](gamma.md) - c' \
  '- [Missing](gone.md) - d' '- [Web](https://example.org/a.md) - e' '- [Delta](delta.md) - f' '- [Twin](twin-x.md) - g' > "$MA/MEMORY.md"
# memory, project -pb
printf 'Shared in b.\n' > "$MB/shared.md"; printf 'Consent in b.\n' > "$MB/consent.md"
printf -- '- [Shared](shared.md)\n' > "$MB/MEMORY.md"
printf 'TRANSCRIPT-SENTINEL-MUST-NOT-LEAK\n' > "$C3/projects/-pa/$SID_PRESENT.jsonl"; chmod 000 "$C3/projects/-pa/$SID_PRESENT.jsonl"
printf 'TRANSCRIPT-SENTINEL-MUST-NOT-LEAK\n' > "$C3/projects/-pb/$SID_BODY.jsonl"
# logbook: existing and missing memory paths (backtick forms), a fence, links
printf '# Day\nBoth forms `~/.claude/projects/-pa/memory/alpha_note.md` and `projects/-pa/memory/beta.md`; missing `~/.claude/projects/-pa/memory/nope.md`.\nSee [[rules/ord]] and IMP-1.\n```\n`projects/-pa/memory/gamma.md`\n```\n' > "$C3/logbook/2026-03-01.md"
printf '# Quiet day\n' > "$C3/logbook/2026-03-02.md"; printf '# Implemented day\n' > "$C3/logbook/2026-03-03.md"
d=1; while [ "$d" -le 12 ]; do printf '# Cap day\nUses [[rules/cap]].\n' > "$C3/logbook/2026-04-$(printf %02d "$d").md"; d=$((d+1)); done
printf '# Plan\nSee [[rules/ord]] and [[ledger/IMP-1]].\n' > "$C3/plans/meta-proposal-2026-03-10.md"
# rules, evidence, adr, docs
printf '# R1\nSlug [[alpha-note]], local [[layer-note.local]], ghost [[ghost-rule]].\n' > "$C3/rules/r1.md"
printf '# E1\nBack to [[rules/r1]].\n' > "$C3/docs/archive/rules-evidence/r1.md"
printf '# Twin rule\n' > "$C3/rules/Twin_X.md"
printf '# Ord\n' > "$C3/rules/ord.md"; printf '# Cap\n' > "$C3/rules/cap.md"; printf '# Plain rule\n' > "$C3/rules/plain.md"
printf '# Ord rule\nLinks [[ord]].\n' > "$C3/rules/ordr.md"
printf '# Fence end\n````text\nopen code\n' > "$C3/rules/fenceend.md"; printf '# E\n```\nopen\n' > "$C3/docs/archive/rules-evidence/fenceend.md"
printf '# Fence doc\nSee [[rules/fenceend]].\n' > "$C3/docs/fence.md"
printf '# ADR\nSee [[rules/ord]].\n' > "$C3/docs/adr/0001-x.md"
printf '# Doc\nSee [[rules/ord]]; [x](sibling.md) and [y](nowhere.md).\n' > "$C3/docs/d.md"; printf '# Sibling\n' > "$C3/docs/sibling.md"
cat > "$C3/global-observation/improvement-ledger.json" <<'EOF'
{"lastUpdated": "2026-04-01", "b": {"entries": [
  {"id": "IMP-1", "status": "implemented", "title": "Linked", "proposedAt": "2026-03-01T00:00:00Z", "implementedAt": "2026-03-03",
   "notes": "Real note.", "filesModified": ["rules/ord.md"], "verification": {"kpi": "k", "note": "proposed entries carry no measurement; a human review must set status"}},
  {"id": "IMP-2", "status": "proposed", "title": "Empty shell", "verification": {"kpi": "k2", "note": "proposed entries carry no measurement; again"}},
  {"id": "IMP-3", "status": "proposed", "title": "Boilerplate only", "verification": {"note": "proposed entries carry no measurement; only this"}},
  {"id": "IMP-4", "status": "implemented", "title": "Templates", "notes": "Tokens [[rules/name]] and [[name]] and [[evidence/...]] are placeholders.",
   "verification": {"note": "custom note kept"}},
  {"id": "IMP-5", "status": "proposed", "title": "Nobody mentions me"}]}}
EOF
EXPECT_V3_TOTAL=$(find "$C3/logbook" "$C3/plans" "$C3/rules" "$C3/docs" "$MA" "$MB" -type f -name '*.md' | wc -l | tr -d ' ')
EXPECT_V3_TOTAL=$((EXPECT_V3_TOTAL + 5 + 1)) # + 5 ledger notes + ledger.md
v3_run() { local hk=$H kk=$K; H="$H3"; K="$K3"; RUN_FLAGS=""; run "$@"; H="$hk"; K="$kk"; RUN_FLAGS=--no-v3-links; }
G3="$K3/mirror/graph"
edge() { awk -F '\t' -v s="$1" -v d="$2" -v v="$3" '$1 == s && $2 == d && $3 == v { f = 1 } END { exit !f }' "$G3/edges.tsv"; }
export G3; export -f edge
