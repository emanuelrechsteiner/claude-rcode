#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016 # single quotes are intended: the bash -c / eval bodies expand at run time, not here
# knowledge-mirror-regression cases: rule->evidence edge, backtick references, --check-links, mini mirror.
# Sourced by scripts/tests/knowledge-mirror-regression.sh (never run on its own); shares its
# helpers, fixtures and variables (T H C K run check ok bad ...) and its order of cases.

echo "== rule -> evidence edge =="
check "rules/a.md ends with the Evidence section ([[evidence/a]])" "$(tail -4 "$K/mirror/rules/a.md")" \
  /bin/bash -c '[ "$(tail -n 3 "$1")" = "$(printf "## Evidence\n\n[[evidence/a]]")" ]' _ "$K/mirror/rules/a.md"
check "rules/b.md (no twin) has no Evidence section" "$(cat "$K/mirror/rules/b.md")" \
  /bin/bash -c '! grep -q "^## Evidence" "$1"' _ "$K/mirror/rules/b.md"
check "rules/refs.md (no twin) has no Evidence section" "present" /bin/bash -c '! grep -q "^## Evidence" "$1"' _ "$RF"

echo "== backtick references -> wikilinks =="
check "\`docs/adr/0001-x.md\` -> [[adr/0001-x]]" "$(sed -n 7p "$RF")" grep -qF '[[adr/0001-x]]' "$RF"
check "adr backtick text is gone" "still there" /bin/bash -c '! grep -qF "\`docs/adr/0001-x.md\`" "$1"' _ "$RF"
check "\`rules/a.md:12\` -> [[rules/a]]:12" "present?" grep -qF '[[rules/a]]:12' "$RF"
check "\`rules/a.md#top\` -> [[rules/a]]#top (anchor kept as text)" "present?" grep -qF '[[rules/a]]#top' "$RF"
check "\`~/.claude/CONTEXT.md\` -> [[docs/CONTEXT]]" "present?" grep -qF '[[docs/CONTEXT]]' "$RF"
check "non-mirrored \`docs/nested/skip.md\` stays in backticks" "present?" grep -qF '`docs/nested/skip.md`' "$RF"
check "missing target \`rules/missing.md\` stays in backticks" "present?" grep -qF '`rules/missing.md`' "$RF"
check "bare [[a]] -> [[rules/a]]" "present?" grep -qF 'Bare [[rules/a]] and' "$RF"
check "bare [[unknown-bare]] left as is" "present?" grep -qF '[[unknown-bare]]' "$RF"
FM="$K/mirror/rules/forms.md"
check "bare [[a#top]] / [[a|alias]] / [[a#top|al]] are qualified, anchor and alias kept" "$(sed -n 7p "$FM")" \
  grep -qxF 'Anchor [[rules/a#top]] alias [[rules/a|the rule]] both [[rules/a#top|al]].' "$FM"
check "non-ASCII rule name: bare token and backtick path both linked, spaced backtick path linked" "$(tail -n 1 "$FM")" \
  grep -qxF "Nonascii bare [[rules/$NA]] and [[rules/$NA]] and [[rules/with space]]." "$FM"
check "fenced block untouched (backtick path, [[fenced-ghost]], bare [[a]])" "$(cat "$RF")" \
  grep -qxF 'fenced `rules/a.md` and [[fenced-ghost]] and [[a]]' "$RF"

echo "== --check-links =="
before="$(tree_count)"; hsum="$(shasum "$HT" | cut -d ' ' -f 1)"
run --check-links
check "--check-links exits 0" "rc=$RC err=$ERR" test "$RC" -eq 0
check "--check-links prints LINKS total=$EXP_LINKS" "$OUT" grep -qx "LINKS total=$EXP_LINKS" <<<"$OUT"
check "--check-links lists the dangling token with its file" "$OUT" grep -qE '^dangling: ghost cause=missing in (mirror/)?docs/top\.md$' <<<"$OUT"
check "--check-links lists the second dangling token" "$OUT" grep -qE '^dangling: unknown-bare cause=missing in (mirror/)?rules/refs\.md$' <<<"$OUT"
check "--check-links lists the ambiguous token with candidate count" "$OUT" grep -qx 'ambiguous: orphan (2 candidates)' <<<"$OUT"
check "--check-links ignores tokens inside fenced code" "$OUT" /bin/bash -c '! grep -q fenced-ghost <<<"$1"' _ "$OUT"
check "--check-links writes nothing" "tree $before -> $(tree_count)" \
  /bin/bash -c '[ "$1" = "$2" ] && [ "$(shasum "$3" | cut -d " " -f 1)" = "$4" ]' _ "$before" "$(tree_count)" "$HT" "$hsum"
# Resolution is against mirror/, never the live install: ghost exists live (and
# would be copied by a real run) but --check-links must still report it dangling.
printf '# Live only\n' > "$C/rules/ghost.md"; printf '# Live only\n' > "$C/docs/ghost.md"
run --check-links
check "--check-links resolves against mirror/, not ~/.claude (live ghost files: still dangling, not copied)" "$OUT" \
  /bin/bash -c 'grep -qx "LINKS total=$1" <<<"$2" && grep -qE "^dangling: ghost cause=missing in " <<<"$2" && [ ! -e "$3/mirror/rules/ghost.md" ] && [ ! -e "$3/mirror/docs/ghost.md" ]' _ "$EXP_LINKS" "$OUT" "$K"
rm -f "$C/rules/ghost.md" "$C/docs/ghost.md"
# No jq / shasum on PATH: --check-links needs neither.
NJ="$T/nojq-bin"; mkdir -p "$NJ"
for t in awk sed tr cat wc grep find sort head mkdir mktemp rm dirname basename date xargs cmp comm cut; do ln -sf "$(command -v $t)" "$NJ/$t"; done
check "precondition: PATH without jq and shasum" "still resolvable" /bin/bash -c '! PATH="$1" command -v jq >/dev/null && ! PATH="$1" command -v shasum >/dev/null' _ "$NJ"
( cd "$T" && /usr/bin/env -i HOME="$H" CLAUDE_KNOWLEDGE_DIR="$K" PATH="$NJ" /bin/bash "$KM" --no-v3-links --check-links >"$T/out" 2>"$T/err" ); RC=$?
check "--check-links works without jq and shasum (exit 0, same LINKS line)" "rc=$RC err=$(cat "$T/err")" \
  /bin/bash -c '[ "$1" = 0 ] && grep -qx "LINKS total=$2" "$3"' _ "$RC" "$EXP_LINKS" "$T/out"

echo "== --check-links: missing library is an error, generated structure is not a link =="
K_KEEP="$K"; K="$T/know-none"; mkdir -p "$K"
run --check-links
check "no mirror/: exit 1, 'library unavailable' on stderr, no LINKS line, nothing created" "rc=$RC out=$OUT err=$ERR" \
  /bin/bash -c '[ "$1" = 1 ] && grep -q "library unavailable" <<<"$2" && ! grep -q "^LINKS" <<<"$3" && [ ! -e "$4/mirror" ]' _ "$RC" "$ERR" "$OUT" "$K"
H_KEEP="$H"; H="$T/home-mini"; K="$T/know-mini"; mkdir -p "$H/.claude/rules"
printf '# plain\n' > "$H/.claude/rules/plain.md"
printf -- '---\nrelated: "[[ghost-fm]]"\nalso: "[[plain]]"\n---\nBody [[plain]] and [[ghost-body]]\n' > "$H/.claude/rules/fmlink.md"
run
check "V-16 mini mirror: generated keys and the source frontmatter add no link; only the body counts (2 total, 1 dangling)" "rc=$RC out=$OUT err=$ERR" \
  /bin/bash -c '[ "$1" = 0 ] && grep -qx "LINKS total=2 resolved=1 ambiguous=0 dangling=1" <<<"$2"' _ "$RC" "$OUT"
run --check-links
check "V-16 mini mirror: --check-links names the dangling BODY token and never the frontmatter token" "$OUT" \
  /bin/bash -c 'grep -qx "dangling: ghost-body cause=missing in rules/fmlink.md" <<<"$1" && ! grep -q ghost-fm <<<"$1"' _ "$OUT"
check "mini mirror: bare [[plain]] in frontmatter is not rewritten" "$(cat "$K/mirror/rules/fmlink.md")" grep -qxF 'also: "[[plain]]"' "$K/mirror/rules/fmlink.md"
K_EMPTY="$T/know-empty"; mkdir -p "$K_EMPTY/mirror/.state"; KK="$K"; K="$K_EMPTY"
run --check-links
check "V-16 an existing but EMPTY mirror: exit 1, error line on stderr, no LINKS line (never an empty healthy graph)" "rc=$RC out=$OUT err=$ERR" \
  /bin/bash -c '[ "$1" = 1 ] && grep -q "^knowledge-mirror: .*no mirror copies" <<<"$2" && ! grep -q "^LINKS" <<<"$3"' _ "$RC" "$ERR" "$OUT"
printf '# Knowledge mirror\n' > "$K_EMPTY/mirror/README.md"
run --check-links
check "V-16 a mirror holding only README.md is empty too (exit 1, no LINKS line)" "rc=$RC out=$OUT" \
  /bin/bash -c '[ "$1" = 1 ] && ! grep -q "^LINKS" <<<"$2"' _ "$RC" "$OUT"
K="$KK"
H="$H_KEEP"; K="$K_KEEP"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/km-cases-imp.sh"
