#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2016 # fixtures are read by kl-cases-rank.sh / kl-cases-output.sh
# knowledge-lookup-regression fixtures for the v3 contract (ranking, matching, filters, collisions,
# superseded, ## Mentions, output). Sourced by scripts/tests/knowledge-lookup-regression.sh after
# the base fixtures; shares w, M, K, PROV. Every token is invented and unique to its case.

# description-only token: the word lives in the description, not in the body
w "$M/memory/proj/desc-only.md" "---" "name: descnote" 'description: "Walkthroughs of the descriptiontok flow, quoted \"as is\""' \
  "metadata:" "  node_type: memory" "---" "$PROV" "Body without the word."

# collision list: zustand is case-sensitive (German noun), immer matches only in code
w "$M/memory/proj/de-noun.md" "# Status" "Der Zustand der Anwendung ist gut."
w "$M/memory/proj/de-noun-start.md" "# Status" "Zustand und Wetter wurden geprueft."
w "$M/memory/proj/en-store.md" "# Stack" "Single Zustand store with Immer"
w "$M/memory/proj/immer-prose.md" "# P" "Ich mache das immer so."
w "$M/memory/proj/immer-span.md" "# P" 'State updates go through `immer` produce calls.'
w "$M/memory/proj/immer-import.md" "# P" "import { produce } from 'immer'"
w "$M/memory/proj/immer-from.md" "# P" "const x = await load() // from 'immer' bundle"
w "$M/memory/proj/immer-npm.md" "# P" "run npm i immer first"
w "$M/memory/proj/immer-fence.md" "# P" '```ts' "const next = immer(base)" '```'

# filters: one token in two project folders, a rule, a logbook entry
mkdir -p "$M/memory/proj-alpha" "$M/memory/proj-beta"
w "$M/memory/proj-alpha/a.md" "# A" "kindtok in alpha"
w "$M/memory/proj-beta/b.md" "# B" "kindtok in beta"
w "$M/rules/kindrule.md" "# K" "kindtok in a rule"
w "$M/logbook/2026-02-02.md" "# L" "kindtok in the log"

# prefix and word boundary (an umlaut is a word character: no split inside a word)
w "$M/rules/prefix-a.md" "# P" "source ~/.zshtokrc on login"
w "$M/rules/prefix-b.md" "# P" "the zshtok variable is set"
w "$M/memory/proj/uml-a.md" "# U" "$(printf 'x\303\274bertok y')"
w "$M/memory/proj/uml-b.md" "# U" "plain bertok here"

# quoted phrase: two keywords versus one literal phrase
w "$M/memory/proj/phrase-adj.md" "# P" "phrasea phraseb sit together"
w "$M/memory/proj/phrase-apart.md" "# P" "phrasea here" "phraseb there"

# BM25F-lite fields: file name x3 beats a body mention; logbook is down-weighted, not excluded
w "$M/rules/bmbase-xyztok.md" "# Notes" "unrelated content of similar size"
w "$M/rules/bmbody.md" "# Notes" "xyztok mentioned in the body once"
w "$M/memory/proj/logw.md" "# Notes" "logwtok in a memory note"
w "$M/logbook/2026-03-03.md" "# Notes" "logwtok in a logbook note"
# same-line co-occurrence: the split file sorts first by path, the same-line file must still win
w "$M/memory/proj/co-a-split.md" "# C" "cotokone then x" "cotoktwo then x"
w "$M/memory/proj/co-z-same.md" "# C" "cotokone cotoktwo x" "filler line xxx"

# superseded: old (5 hits) > other (3) > new (1) by score; expected order other, new, old, orphan
w "$M/memory/proj/sup-old.md" "---" "status: superseded" "superseded_by: memory/proj/sup-new.md" "---" \
  "suptok one" "suptok two" "suptok three" "suptok four" "suptok five"
w "$M/memory/proj/sup-new.md" "# New" "suptok current"
w "$M/memory/proj/sup-other.md" "# Other" "suptok a" "suptok b" "suptok c"
w "$M/memory/proj/sup-orphan.md" "---" "status: superseded" "superseded_by: memory/proj/nowhere.md" "---" \
  "suptok 1" "suptok 2" "suptok 3" "suptok 4" "suptok 5" "suptok 6" "suptok 7" "suptok 8" "suptok 9"

# D-05 boundaries: typographic UTF-8 punctuation separates words, an umlaut does not (escapes only)
w "$M/memory/proj/bd-curly.md" "# B" "$(printf 'he said \342\200\234boundtok\342\200\235 twice')"
w "$M/memory/proj/bd-arrow.md" "# B" "$(printf 'boundtok\342\206\222bash switch')"
w "$M/memory/proj/bd-dash.md" "# B" "$(printf 'boundtok\342\200\224x and y')"
w "$M/memory/proj/bd-nbsp.md" "# B" "$(printf 'a\302\240boundtok\302\240b')"
w "$M/memory/proj/bd-times.md" "# B" "$(printf '2\303\227boundtok\303\227')"
w "$M/memory/proj/bd-space.md" "# B" "plain boundtok x"
w "$M/memory/proj/bd-uml.md" "# B" "$(printf '\303\244boundtok after an umlaut')"
# D-01: explicit keywords are case-insensitive
w "$M/memory/proj/cap-kw.md" "# C" "the hooktok fires on commit"

# D-10 / V-05: superseded_by normalisation, and IMP copies never count as superseded
w "$M/memory/proj/sw-old.md" "---" "status: superseded" "superseded_by: [[memory/proj/sw-new]]" "---" "swtok a" "swtok b" "swtok c" "swtok d"
w "$M/memory/proj/sw-new.md" "# N" "swtok current"
w "$M/memory/proj/sw-mid.md" "# O" "swtok x" "swtok y"
w "$M/memory/proj/sa-old.md" "---" "status: superseded" "superseded_by: [[./mirror/memory/proj/sa-new.md|the new one]]" "---" "satok a" "satok b" "satok c" "satok d"
w "$M/memory/proj/sa-new.md" "# N" "satok current"
w "$M/memory/proj/sa-mid.md" "# O" "satok x" "satok y"
mkdir -p "$M/ledger"
w "$M/ledger/IMP-901.md" "---" "kind: imp" "id: IMP-901" "status: superseded" "superseded_by: memory/proj/imp-new.md" "---" "imptok 1" "imptok 2" "imptok 3" "imptok 4"
w "$M/memory/proj/imp-new.md" "# N" "imptok current"

# ## Mentions: generated reverse links are ignored to the end of the file (but not inside a fence)
w "$M/memory/proj/mentions.md" "# M" "mentbody is searchable" "## Mentions" "- [[x]] mentghost" "- [[y]] mentghost"
w "$M/memory/proj/mentions-fence.md" "# M" '```' "## Mentions" '```' "mentfence after the fence"

# output: description, sections, fenced "# comment" is no heading, token size
w "$M/memory/proj/outfmt.md" "---" "name: outfmt" 'description: "Output format note"' "---" "$PROV" \
  "# Top heading" "intro line" "## Section Alpha" "outtok in alpha" '```sh' "# outtok comment in a fence" '```' "outtok after the fence"
OUTFMT_BYTES=$(wc -c < "$M/memory/proj/outfmt.md" | tr -d ' ')
