#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
# shellcheck disable=SC2034 # RUN_FLAGS is read by run() in km-fixtures.sh
# knowledge-mirror-regression v3 cases: link hygiene (memory links, MEMORY.md links, logbook/plan memory
# paths), --check-links with dangling causes, --no-v3-links. Sourced by knowledge-mirror-regression.sh
# after km-cases-v3-meta.sh (the v3 mirror in $K3 exists); shares its helpers and variables.

echo "== v3 links: bare memory links resolve inside the project folder =="
AN="$K3/mirror/memory/-pa/alpha_note.md"
line() { grep -m1 "$2" "$1"; }
check "[[alpha-note]] (hyphen for underscore) -> [[memory/-pa/alpha_note]]" "$(line "$AN" 'Self')" grep -qF 'Self [[memory/-pa/alpha_note]],' "$AN"
check "[[Beta|the beta]] (case fold) -> [[memory/-pa/beta|the beta]], alias kept" "$(line "$AN" 'Self')" grep -qF 'case+alias [[memory/-pa/beta|the beta]],' "$AN"
check "[[consent]] exists in two projects: the own folder wins -> [[memory/-pa/consent]]" "$(line "$AN" 'Self')" grep -qF 'own-folder [[memory/-pa/consent]],' "$AN"
check "[[shared]] exists only in another project: stays bare (resolved globally by the checker)" "$(line "$AN" 'Self')" grep -qF 'other-folder [[shared]],' "$AN"
check "[[Twin_X]] folds to two files: non-unique, stays bare" "$(line "$AN" 'Self')" grep -qF 'fold-twin [[Twin_X]],' "$AN"
check "V-10 [[Twin_X]] stays bare although rules/Twin_X.md exists: an ambiguous in-folder fold never falls through to a rule" "$(line "$AN" 'Self')" \
  /bin/bash -c '[ -f "$1/rules/Twin_X.md" ] && ! grep -qF "[[rules/Twin_X" "$2"' _ "$K3/mirror" "$AN"
check "[[ghost-pa]] with no similar file stays bare" "$(line "$AN" 'Self')" grep -qF 'ghost [[ghost-pa]].' "$AN"
check "inline code span \`[[beta]]\` untouched, [[beta#top]] -> [[memory/-pa/beta#top]] (anchor kept)" "$(tail -n 3 "$AN")" \
  grep -qxF 'Code `[[beta]]` stays. Anchor [[memory/-pa/beta#top]].' "$AN"
check "frontmatter is never rewritten (originSessionId etc. byte-identical)" "$(sed -n 6,12p "$AN")" grep -qxF 'description: Alpha' "$AN"

echo "== v3 links: MEMORY.md [title](file.md) =="
MM3="$K3/mirror/memory/-pa/MEMORY.md"
check "- [Alpha note](alpha_note.md) -> - [[memory/-pa/alpha_note|Alpha note]] (hook text kept)" "$(sed -n 6,8p "$MM3")" \
  grep -qxF -- '- [[memory/-pa/alpha_note|Alpha note]] - hook a' "$MM3"
check "a title with an inline code span is rewritten too (alias keeps the backticks)" "$(sed -n 6,9p "$MM3")" \
  grep -qxF -- '- [[memory/-pa/beta|Beta with `code`]] - hook b' "$MM3"
check "link to a missing file, an https link and a non-unique fold stay markdown links" "$(sed -n 6,14p "$MM3")" \
  /bin/bash -c 'grep -qxF -- "- [Missing](gone.md) - d" "$1" && grep -qxF -- "- [Web](https://example.org/a.md) - e" "$1" && grep -qxF -- "- [Twin](twin-x.md) - g" "$1"' _ "$MM3"
v3_run --check-links
CL="$OUT"
check "--check-links counts markdown links and resolves them (LINKS line present, exit 0)" "rc=$RC out=$CL" \
  /bin/bash -c '[ "$1" = 0 ] && grep -qE "^LINKS total=[0-9]+ resolved=[0-9]+ ambiguous=1 dangling=[0-9]+$" <<<"$2"' _ "$RC" "$CL"
check "a relative markdown link that resolves is a resolved link (docs/d.md [x](sibling.md): edge mdlink)" "$(cat "$G3/edges.tsv" 2>&1 | head -2)" edge docs/d.md docs/sibling.md mdlink
check "the unrewritten non-unique MEMORY.md link resolves relative to its folder (edge mdlink)" "x" edge memory/-pa/MEMORY.md memory/-pa/twin-x.md mdlink

echo "== v3 links: every dangling line carries a cause (slug, missing, excluded-by-design, template) =="
check "every dangling: line has the form 'dangling: <token> cause=<cause> in <path>' with a known cause" "$CL" \
  /bin/bash -c '! grep "^dangling: " <<<"$1" | grep -vE "^dangling: .+ cause=(slug|missing|excluded-by-design|template) in [^ ]+$" | grep -q .' _ "$CL"
check "slug: [[alpha-note]] in a RULE (no rewrite there) while alpha_note.md exists" "$CL" grep -qx 'dangling: alpha-note cause=slug in rules/r1.md' <<<"$CL"
check "missing: [[ghost-rule]]" "$CL" grep -qx 'dangling: ghost-rule cause=missing in rules/r1.md' <<<"$CL"
check "missing: [[ghost-pa]] in a memory copy" "$CL" grep -qx 'dangling: ghost-pa cause=missing in memory/-pa/alpha_note.md' <<<"$CL"
check "excluded-by-design: a *.local target" "$CL" grep -qx 'dangling: layer-note.local cause=excluded-by-design in rules/r1.md' <<<"$CL"
for t in 'rules/name' 'name' 'evidence/...'; do
  check "template: placeholder token '$t' in a ledger note" "$CL" grep -qxF "dangling: $t cause=template in ledger/IMP-4.md" <<<"$CL"
done
check "missing: markdown links to absent files (MEMORY.md gone.md, docs nowhere.md)" "$CL" \
  /bin/bash -c 'grep -qx "dangling: gone.md cause=missing in memory/-pa/MEMORY.md" <<<"$1" && grep -qx "dangling: nowhere.md cause=missing in docs/d.md" <<<"$1"' _ "$CL"
check "ambiguous: the non-unique fold [[Twin_X]] is reported ambiguous with its candidate count" "$CL" grep -qx 'ambiguous: Twin_X (2 candidates)' <<<"$CL"
check "V-10 the ambiguous bare token is not an edge to the same-named rule (no alpha_note -> rules/Twin_X.md row)" "$(grep -F Twin_X "$G3/edges.tsv")" \
  /bin/bash -c '! grep -qF "rules/Twin_X.md" "$1"' _ "$G3/edges.tsv"
check "[[shared]] and [[consent]] are not reported (resolved)" "$CL" /bin/bash -c '! grep -qE "^(dangling|ambiguous): (shared|consent)" <<<"$1"' _ "$CL"

echo "== v3 links: logbook and plan copies, backtick \`projects/<f>/memory/<x>.md\` =="
LB="$K3/mirror/logbook/2026-03-01.md"
check "existing target, both forms (~/.claude/projects/... and projects/...) -> [[memory/-pa/<file>]]" "$(sed -n 7,9p "$LB")" \
  grep -qF 'Both forms [[memory/-pa/alpha_note]] and [[memory/-pa/beta]]; missing `~/.claude/projects/-pa/memory/nope.md`.' "$LB"
check "the edge logbook -> memory is via wikilink" "x" edge logbook/2026-03-01.md memory/-pa/alpha_note.md wikilink
check "inside a fenced block the path stays a backtick and is not reported" "$CL" \
  /bin/bash -c 'grep -qxF "\`projects/-pa/memory/gamma.md\`" "$1" && ! grep -q gamma <<<"$2"' _ "$LB" "$CL"
check "missing target stays as written and --check-links reports it with cause missing" "$CL" \
  grep -qx 'dangling: projects/-pa/memory/nope.md cause=missing in logbook/2026-03-01.md' <<<"$CL"
HB="$T/home-v3b"; KB="$T/know-v3b"; mkdir -p "$HB/.claude/plans" "$HB/.claude/rules" "$HB/.claude/projects/-pb/memory"
printf 'Shared.\n' > "$HB/.claude/projects/-pb/memory/shared.md"
printf '# Plan memory\nSee `~/.claude/projects/-pb/memory/shared.md` and `projects/-pb/memory/ghost.md`.\n' > "$HB/.claude/plans/meta-proposal-2026-03-11.md"
printf '# Rule with path\n`projects/-pb/memory/shared.md`\n' > "$HB/.claude/rules/pathrule.md"
HK="$H"; KK="$K"; H="$HB"; K="$KB"; RUN_FLAGS=""; run; RUN_FLAGS=--no-v3-links; H="$HK"; K="$KK"
check "plan copies get the same rewrite (existing -> wikilink, missing stays)" "$(cat "$KB/mirror/plans/meta-proposal-2026-03-11.md")" \
  grep -qF 'See [[memory/-pb/shared]] and `projects/-pb/memory/ghost.md`.' "$KB/mirror/plans/meta-proposal-2026-03-11.md"
check "the path rewrite is limited to logbook and plans (a rule copy keeps the backtick)" "$(tail -n 2 "$KB/mirror/rules/pathrule.md")" \
  grep -qxF '`projects/-pb/memory/shared.md`' "$KB/mirror/rules/pathrule.md"
check "the missing plan path is reported (cause missing) and counted" "$OUT" grep -qE '^LINKS total=[0-9]+ resolved=[0-9]+ ambiguous=0 dangling=1$' <<<"$OUT"

echo "== v3 links: --no-v3-links reproduces the v2 link behaviour =="
KNL="$T/know-v3-nl"
( cd "$T" && env -u CLAUDE_BAUHOF_ROOT HOME="$H3" CLAUDE_KNOWLEDGE_DIR="$KNL" /bin/bash "$KM" --no-v3-links >"$T/out" 2>"$T/err" ); RC=$?
check "--no-v3-links run: exit 0" "rc=$RC err=$(cat "$T/err")" test "$RC" -eq 0
NL="$KNL/mirror"
check "no memory link rewrite, no MEMORY.md rewrite, no logbook path rewrite" "$(sed -n 6,12p "$NL/memory/-pa/MEMORY.md")" \
  /bin/bash -c 'grep -qF "Self [[alpha-note]]," "$1/memory/-pa/alpha_note.md" && grep -qxF -- "- [Alpha note](alpha_note.md) - hook a" "$1/memory/-pa/MEMORY.md" && grep -qF "\`~/.claude/projects/-pa/memory/alpha_note.md\`" "$1/logbook/2026-03-01.md"' _ "$NL"
check "no ## Mentions section anywhere" "$(grep -rl '^## Mentions' "$NL" | head -2)" /bin/bash -c '! grep -rq "^## Mentions" "$1"' _ "$NL"
check "edges.tsv holds only the v2 edge kinds (wikilink, evidence)" "$(cut -f3 "$NL/graph/edges.tsv" | sort | uniq -c)" \
  /bin/bash -c '! tail -n +2 "$1/graph/edges.tsv" | cut -f3 | grep -vxE "wikilink|evidence" | grep -q .' _ "$NL"
