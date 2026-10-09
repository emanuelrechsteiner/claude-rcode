<!--
Status: ACTIVE
Last Updated: 2026-10-09
Purpose: How R.Code uses Obsidian as a read window over its distilled knowledge: safe setup of the workshop (Stage 1), the knowledge folder (Stage 2), the agent's lookup (Stage 3), the knowledge-library v3 contract, project level, link convention, decisions
-->

# Obsidian as a read window

Tokens used here: `<WORKSHOP>` is this repo's working copy (see `CONTEXT.md`, **Workshop**). `<KNOWLEDGE>` is the directory that `CLAUDE_KNOWLEDGE_DIR` points to (Stage 2). Neither is a real path.

**Status (2026-10-08):** both Obsidian vaults are open on the owner's machine in restricted mode with the four settings written; Stage 1 is verified for A1–A4, A6, A7 and A9 (the duplicate-basename link resolves to `rules/`, see the table); not seen: whether the graph draws `observation-capture` as unresolved (A5) and the A8 exclusion experiment (not needed); Stage 2's mirror (v1) has run against the real `~/.claude` and C3–C7 passed; Stage 3's lookup is deployed and its session-start hint was quoted verbatim by a new session. Stage 2 v2, the justification graph, is built, deployed (2026-10-09) and has run against the real `~/.claude`: 588 copies, 18 rule→evidence edges, 238 ledger notes, `LINKS total=623 resolved=592 ambiguous=1 dangling=30` (C8 done); C9, the look at the rendered graph, is recorded in the table below. Everything listed under "What is NOT verified" stays open. The decision behind the read window is `docs/adr/0006-obsidian-read-window.md` (IMP-248); the one behind the v2 graph is `docs/adr/0007-justification-graph-in-the-mirror.md` (IMP-250, proposed). **Knowledge library v3 (2026-10-09):** the contract for curation keys, generated keys, `## Mentions`, link hygiene, the graph export, lookup v3, the evaluation harness and the lint is specified below in § Stage 2 "Contract v3" and § Stage 3 "Lookup v3 and evaluation"; every item there is marked "built" or "wave B, not built". Amended 2026-10-09: wave A is built and has run against the real `~/.claude` (numbers in the Record table); only the items marked "wave B, not built" are open (the write-time advisory hook, project hubs, the docs split, stubs for missing targets). The authored-versus-generated boundary is `docs/adr/0008-curation-keys-authored-generated-in-mirror.md`.

## Purpose

Obsidian is a **read window** over distilled knowledge: rules, ADRs, the glossary, plans, the logbook, per-project memory and the ledger (an index and, from v2, one note per id), with working links between them. It ingests nothing, stores nothing, and is not a second source of truth. It never writes into a file that the framework or Claude Code reads.

It covers the distilled layer only. A measurement taken on 2026-10-08 put the distilled stores at about 10.84 MiB and the raw data (transcripts, caches, app stores) at about 34.10 GiB. The raw data never enters the window.

There are two windows, one per stage:

- **Stage 1** opens the workshop checkout (framework design: rules, docs, commands, agents, skills).
- **Stage 2** opens a machine-local knowledge folder holding read-only copies of the distillate (logbook, memory, rules, ledger and, in v2, evidence, ADRs and docs).

**Never open `~/.claude` as an Obsidian vault.** Two reasons:

1. Obsidian's writes would land in the live install. Link and frontmatter rewrites in a live skill or rule take effect at the next tool call, a click on an unresolved link can create a new rule file, which is auto-loaded, and memory files are untracked, so no git backstop exists. The path guard (`hooks/governing-path-guard.sh`) is a hook on Claude's own tools and cannot see Obsidian's writes; the next `claude-deploy` then aborts on the local edits.
2. It exposes every `rules/*.local.md`, including the private-layer overlay. That breaks the rule that the overlay never sits in an Obsidian vault that syncs or is shared, the moment Sync or sharing is ever switched on.

Evidence grades used below: **[O]** official Obsidian documentation, **[C]** community report, **[S]** search-result snippet only (weakest).

## Naming

- An **Obsidian vault** is any folder opened in Obsidian. Always say "Obsidian vault" for it.
- The bare word `vault` in this repo means the PII pseudonym store (`/vault/`, `docs/adr/0003-vault-and-gate.md`, `hooks/vault-write-gate.sh`). Never use "vault" alone for the Obsidian folder, and never name an Obsidian vault folder, variable or path `vault`.
- The **Knowledge folder** is `<KNOWLEDGE>`; the **Knowledge mirror** is the read-only copy the script writes into it. Definitions: `CONTEXT.md`.

## Stage 1: open the workshop

No new code, nothing to deploy or publish. Every change Obsidian makes to a tracked file shows in `git status`, and `claude-deploy` refuses a dirty workshop, so a stray edit cannot reach the live install unnoticed.

**What you will see:** `rules/`, `docs/` (including `docs/adr/` and `docs/archive/rules-evidence/`), `CONTEXT.md`, `CLAUDE.md`, `HARNESS.md`, the `.md` files under `commands/`, `agents/` and `skills/`, plus the local-only `plans/` and `research/`. No runtime data: no logbook, no memory, no meta-proposals. The ledger is JSON and stays hidden unless "Show all file types" is on [O].

**Risks, and what the settings below do about them:**

- Duplicate basenames: `docs/archive/rules-evidence/` holds the evidence moved out of each rule, under the rule's basename, so it is open which file a link opens [C].
- Load-bearing YAML: every command, agent and skill definition starts with YAML frontmatter. Editing it in the Properties UI rewrites the whole block, dropping comments and changing list style [C]. Do not edit those files in Obsidian; the Source setting below avoids the rewrite.
- A rename or move rewrites links in other notes while "Automatically update internal links" is on [O], which would touch tracked rules.
- Clicking an unresolved link creates a note [O]. Every `rules/*.md` is auto-loaded after deploy, so a note created under `rules/` becomes a rule. Do not click unresolved links.
- A new **Canvas** does not follow the "default location for new notes" setting: on 2026-10-08 a click on "new canvas" left an empty `Unbenannt.canvas` in the vault root, which showed up as an untracked file and made `claude-deploy` refuse (the intended fail-loud signal). Delete such files; do not create canvases in the workshop vault.
- `plans/` and `research/` are gitignored, so edits there have no git backstop. The only one is Obsidian's File recovery, kept 7 days outside the Obsidian vault [O].
- The workshop lives on the external SSD and is unavailable when it is unmounted.

### Setup (before browsing)

Checklist written against Obsidian 1.14.4.

- **A1 Precondition.** The `.obsidian/` ignore lines in `.gitignore` and `publish-manifest.txt` are committed. `git -C <WORKSHOP> status --porcelain` prints nothing. `git -C <WORKSHOP> check-ignore -v .obsidian/workspace.json` prints a line from `.gitignore` for the pattern `.obsidian/`.
- **A2 Open and configure.** In Obsidian's own menu labels: Manage vaults, then Open folder as vault, then `<WORKSHOP>`. Leave Restricted mode on, so no community plugins load [O]. Then set:
  - Files and links: **Automatically update internal links = off**
  - **Deleted files = Move to system trash**
  - **Default location for new notes = `plans/`** (already gitignored, so an accidental note is never tracked)
  - Editor: **Properties in document = Source**

  Without clicking: the same four settings can be written into the vault's `<vault>/.obsidian/app.json` while Obsidian is closed (Obsidian reads the file when the vault opens and does not overwrite it): `{"alwaysUpdateLinks": false, "trashOption": "system", "newFileLocation": "folder", "newFileFolderPath": "plans", "propertiesInDocument": "source"}`. Used on 2026-10-08 for both vaults; the keys are community-documented, not official, so confirm them once in the Settings panes.

### Walk-through

- **A3 Expect:** the explorer shows `rules/ docs/ commands/ agents/ skills/ plans/ research/`, `CONTEXT.md` and `CLAUDE.md`, and does not show `.git/ .github/ .obsidian/`. Dot-folders are only reported hidden [C/S]: record whether that holds.
- **A4:** Open `rules/agency-bands.md`. The Backlinks pane lists the rules that reference `agency-bands` (for example `rules/workflow-git.md`). Then click the `agency-bands` link in `rules/workflow-git.md` and **record** whether it opens `rules/agency-bands.md` or the evidence file under `docs/archive/rules-evidence/`.
- **A5:** Open the graph view. The rules form a cluster; `observation-capture` appears as unresolved (see Link convention). **Do not click it**: clicking creates a note [O].
- **A6:** Open `docs/adr/0003-vault-and-gate.md`. It has a bullet-style header and no Properties panel, because it has no YAML.
- **A7:** Open any `commands/*.md`. The YAML shows as source text. Do not edit it.
- **A8 (optional):** Settings, Excluded files, add `docs/archive/`, then repeat A4. **Record** whether link resolution changes. Whether it does is not verified.
- **A9:** Quit Obsidian, then check:
  - `git -C <WORKSHOP> status --porcelain` prints nothing;
  - `ls -a <WORKSHOP>` shows `.obsidian/` and no `.trash/`;
  - if anything shows, `git -C <WORKSHOP> diff` names what Obsidian wrote, and `git -C <WORKSHOP> checkout -- <file>` reverts it.

**Done when** the graph shows the rules linked through the rule links and `git status` is empty after Obsidian is closed.

### Record your observations

| Item | Result |
|---|---|
| Date and Obsidian version | 2026-10-08, Obsidian 1.14.4 (German UI); vault opened by the owner without a trust dialog (fresh folder); Settings → "Externe Erweiterungen" shows restricted mode ON; `.obsidian/` created with app.json, appearance.json, core-plugins.json, workspace.json; no `.trash/`; `git status` shows nothing from Obsidian |
| A3: dot-folders hidden? | yes, as far as seen: the explorer's top-level list (agents … work, AGENTS) shows no `.git`, `.github` or `.obsidian`, which would sort first; the part below AGENTS was not scrolled into view |
| A4: link `agency-bands` opens | `rules/agency-bands.md` (2026-10-08): the quick switcher offers both candidates (`rules/…` and `docs/archive/rules-evidence/…`); the backlinks pane of the rule lists 12 linked mentions (CLAUDE ×3, control-agent ×3, SKILL, testing-quality, web-research-trust ×2, workflow-git ×2, basenames only); clicking the link in `rules/workflow-git.md` (reading view) opened the file with breadcrumb "rules / agency-bands", 12 backlinks, 2,050 words — identical to the rule opened directly. Basis: breadcrumb and matching stats; "Reveal in navigation" was not run |
| A5: graph | several hub-and-spoke clusters with 4–5 large hubs and many scattered single nodes (orphans shown); whether `observation-capture` is drawn as unresolved was NOT seen — the graph filter does not accept text typed through the accessibility API |
| A6 / A7 | ADR 0003: bullet header, no properties panel; `commands/rcode-init.md`: YAML shown as plain source between `---` lines, status bar "4 Eigenschaften", no panel |
| Settings panes | both vaults show the `app.json` values: links not auto-updated; new notes in `plans` / `notes` ("Eigenen Ordner unten festlegen"); deleted files to the system trash; properties "Quelle"; restricted mode on |
| A8: "Excluded files" changes resolution? | not run — the link already resolves to `rules/`, so the exclusion experiment has no open question to answer; left for a case where a duplicate wins |
| A9: `git status` empty, no `.trash/`? | yes: after opening the vault and after a quit/restart, `git status` shows nothing from Obsidian (only files other agents were editing at the time) and `ls -a` shows `.obsidian` but no `.trash` |
| Stage 2 v1 (C3–C7) | C3 dry-run 315 targets, 4 hard-excluded, nothing written; C4 real run created `mirror/` (101 logbook, 189 memory, 3 plans, 21 rules, ledger.md, README.md, 315 hashes) and an empty `notes/`; the Knowledge vault opened in Obsidian in restricted mode; C5 a hand-edited copy made the next run refuse with exit 3, name the file, print the recovery hint, and overwrite nothing (the edit was made outside Obsidian; detection is content-based); after deleting `hashes.tsv` the rerun refreshed the copy; C6 `CHANGED 0`; C7 `notes/test.md` survived |
| Stage 2 v2 (C8) | 2026-10-09, after deploy of 0d6149d: real run `TOTAL 588`, `LINKS total=623 resolved=592 ambiguous=1 dangling=30`; 588 copies with exactly one `kind:` (239 imp incl. the index, 189 memory, 101 logbook, 21 rule, 20 evidence, 7 doc, 7 adr, 4 plan); 18 rules end with `## Evidence` + `[[evidence/<name>]]`; 238 ledger notes, 124 with `measured: true`; the 23 authored `type:` keys untouched; second run `CHANGED 0`; `notes/test.md` survived |
| Stage 2 v2 (C9) | 2026-10-09, seen in Obsidian 1.14.4 (graph reopened so `graph.json` loaded): all nine groups listed in the Groups panel with their colours (rules render pink/magenta rather than red); one round cloud with a dense blue ledger disc in the centre (~240 IMP nodes fanned from the `ledger` index hub), thin blue lines to pink rule nodes; left-centre a tangle of pink rules with orange evidence, grey docs and violet ADR nodes — read pairs `web-research-trust` (pink) next to `web-research-trust` (orange) with a line, likewise `tool-discipline`, and `agency-bands` large pink with its orange twin; outer ring mostly yellow logbook dots without lines and about ten green memory stars each with one to three faint links inward; estimated 150–200 of ~590 nodes isolated, mostly logbook. Not seen: the end of `rules/agency-bands.md`, the `## Evidence` link's breadcrumb, the IMP-248 note's properties and Files links (file opening was not possible with app-scoped automation; a human click answers it) |
| Knowledge library v3 | 2026-10-09: contract written (keys, flags, files, sections in § Stage 2 "Contract v3" and § Stage 3 "Lookup v3 and evaluation"); amended 2026-10-09 after wave A was built and the adversarial reviews found 49 deviations (code fixes in the lookup, lint and mirror; the doc-side ones are written into the contract text); the marks below are flipped |
| Knowledge library v3, mirror (real run) | 2026-10-09: 589 copies, `LINKS total=2673 resolved=2657 ambiguous=0 dangling=16` (3 `template`, 12 `missing`, 1 `excluded-by-design`); rerun `CHANGED 0`; 0-inbound nodes: memory 1/150, logbook 65/101, plans 0/4, overall 71/588; MEMORY.md indexes with 0 outbound links 2/39. Suite: 379 cases |
| Knowledge library v3, eval dev set | 2026-10-09, 10 scored rows: `hit@3` 5/10 (v2) to 10/10 (v3), `hit@1` 3 to 9, `tta_median` 9531 to 1590 (proxy, tokens). Suites: eval 35 cases, lookup 142 cases |
| Knowledge library v3, eval test set | 2026-10-09, 25 owner/judge-confirmed held-out rows: `hit@3` 3/25 (v2) to 9/25 (v3), 10/25 after the D-01 fix (capitalised keywords), `hit@1` 7/25, `tta_median` 15224–19912. Class `crosslang`: 1 of 8 found, a measured limit of lexical matching (no embeddings, see Non-goals) |
| Knowledge library v3, lint | 2026-10-09, suite 76 cases: the grader reproduces the [M§2] measurement exactly (146/150 described, Why 83, How 90, both 79); `--contradictions` lists all 5 candidate contradictions plus 27 status pairs; `--rules-without-evidence` names `code-quality`, `documentation`, `identity` |
| Retrieval route 1: lookup v3 alone | 2026-10-09, same scorer: dev 10/10, test hit@3 10/25 (hit@1 8/25); ~1k tokens, 0.3 s per question, no infrastructure |
| Retrieval route 2: agent rewrite into 2–4 keyword sets, lookup only (ADR 0009) | 2026-10-09: dev 10/10, test hit@3 25/25 (hit@1 24/25), 2.8 lookup calls on average; ~2–3k tokens, no infrastructure; found all of the classes lookup 7, paraphrase 6, crosslang 8, supersession 4 |
| Retrieval route 3: agent reads the catalog (`graph/nodes.tsv`, ~16k tokens), no lookup | 2026-10-09: dev 6/10, test hit@3 24/25 (hit@1 23/25); ~16k tokens per question |
| Retrieval route 3b: catalog + lookup | 2026-10-09: dev 10/10, test hit@3 24/25; ~17k tokens |
| Retrieval route 2 on 56 held-out questions (final, ADR 0009) | 2026-10-09: live agent route 56/56 (hit@1 54/56); deterministic replay with frozen keyword sets and `--fuse best`: hit@3 50/56, hit@10 55/56, hit@1 30/56, tta_median 2,694; lookup alone 22/56 |
| Retrieval route 4: dense, on-device (Apple NaturalLanguage) | 2026-10-09 prototype, same scorer: dense alone dev 0/10, test 1/25 (3/56); equal-weight RRF below lexical; weighted hybrid (w 0.03, chosen on dev) test 11/25 (23/56) = lexical ±1. English/German models share no space (cross-language cosine 0.25 vs 0.21 unrelated). Rejected; fallback stays bge-m3 via Ollama (ADR 0009) |
| Stage 3 (L1–L3) | L1 suite 68/68; L2 `knowledge-lookup.sh zsh` lists the mirrored zsh-modifier memory note, `--stack` in a Node project derived 7 keywords and found 149 files; L3 a new headless session quoted the 📚 line verbatim after deploy |

## Stage 2: the knowledge folder

**Status:** two versions, kept apart. **v1** (logbook, memory, meta-proposals, tracked rules, a ledger index) is built: `scripts/knowledge-mirror.sh` (bash 3.2) and `scripts/tests/knowledge-mirror-regression.sh` (same code path as the script) are in the workshop, the mirror ran against the real `~/.claude` on 2026-10-08, and C3–C7 passed (Record table). Its dry-run listed 314 targets (101 logbook, 188 memory, 3 meta-proposals, 21 rules, 1 ledger index) and reported `hard-excluded 4 path(s)`; the script counts excluded paths but never names them, and 4 equals the number of `rules/*.local.md` overlays on that machine. **v2**, the justification graph (`docs/adr/0007-justification-graph-in-the-mirror.md`, IMP-250 proposed), is built and deployed on 2026-10-09 (`scripts/knowledge-mirror.sh` plus `scripts/lib/knowledge-mirror-graph.sh`; suite 273 cases; four adversarial review rounds plus a repair pass). Its real run is recorded as C8 in the table; the file counts in C4 are v1's.

**Why a copy.** Obsidian rewrites links and frontmatter [O/C]. The only way to keep it from writing into a file the framework or Claude Code reads is to give it a copy. Stage 2 therefore puts read-only copies of the runtime distillate in `<KNOWLEDGE>`, outside every repo.

**Layout.** `<KNOWLEDGE>/mirror/` is owned by `scripts/knowledge-mirror.sh` and overwritten on each run. From v2 it holds `memory/`, `rules/`, `evidence/`, `adr/`, `docs/`, `ledger/`, `logbook/` and `plans/`, plus `ledger.md` (the index of `ledger/`) and `README.md`. Amended 2026-10-09: v3 adds `graph/` (the two TSV files, see Graph export). `<KNOWLEDGE>/notes/` is the owner's own space and is never touched by the script. Open `<KNOWLEDGE>` as its own Obsidian vault.

**Where it lives.** `CLAUDE_KNOWLEDGE_DIR` is set in `~/.claude/env.local.sh`, the machine-local file that is never versioned; the block to copy is at the end of `templates/env.local.sh.template`. It is an absolute path with **no default**: an unset variable makes the script refuse to run. It must be:

- outside `~/.claude` and outside the workshop;
- not under iCloud, Dropbox or Obsidian Sync, because it holds memory files and private project names;
- recommended on the internal disk under `$HOME`, so it stays available when the SSD is unmounted.

**What the mirror copies** (an allowlist, nothing else; v2 adds the three entries marked and replaces the ledger rendering):

- the logbook (`~/.claude/logbook/*.md`) into `mirror/logbook/`;
- per-project memory (`~/.claude/projects/*/memory/*.md`) into `mirror/memory/<dir>/`, one folder per project directory;
- meta-proposals (`~/.claude/plans/meta-proposal-*.md`) into `mirror/plans/`;
- the tracked rules only (`rules/*.md`, never a `*.local.md`) into `mirror/rules/`;
- v2: the rule evidence (`docs/archive/rules-evidence/*.md`) into `mirror/evidence/`;
- v2: the ADRs (`docs/adr/*.md`) into `mirror/adr/`;
- v2: the top-level `docs/*.md` and `CONTEXT.md` into `mirror/docs/`;
- the improvement ledger: every unique ledger id becomes a note `mirror/ledger/<ID>.md`, and `mirror/ledger.md` stays as the index, now carrying a `[[ledger/<ID>]]` link per id (v1 rendered it as one line per entry: id, status, title).

**Each copy carries** YAML frontmatter with `kind` (one of `memory`, `rule`, `evidence`, `adr`, `doc`, `logbook`, `plan`, `imp`) and `origin` (the source path, written with `~`, as a quoted scalar). The key names are deliberately not `type`/`source`: 23 memory notes own a `type` key of their own (`project`, `feedback`, `user`, `reference`), and a generated key must never collide with an authored one (contract amendment 2026-10-09). Where the source already has a frontmatter block, the two keys are inserted after its opening `---` and no existing key is touched; a source whose line 1 is `---` but never closes the block counts as having no frontmatter and gets a generated one. The provenance comment follows the closing `---`. `mirror/README.md` carries the run timestamp. `kind` and `origin` are generated: no source file is edited to carry them. Amended 2026-10-09: from v3 a memory copy carries five generated keys (`kind`, `origin`, `dated`, `dated_from`, `origin_session`), not two; see Contract v3.

**Generated links (the justification graph).** The edges exist only in the copies; the sources keep their backtick paths (reasoning: `docs/adr/0007-justification-graph-in-the-mirror.md`). Because the enrichment happens before hashing, the hand-edit check under Refusals is unaffected by design (not yet verified). The contract (`<n>` is a file's basename without extension):

- A rule copy whose evidence twin exists gains a final `## Evidence` section with `[[evidence/<n>]]`.
- A backtick repo path to a mirrored target is rewritten to a path-qualified wikilink: `[[rules/<n>]]`, `[[adr/<n>]]`, `[[docs/<n>]]`, `[[evidence/<n>]]`, and `[[docs/CONTEXT]]` for `CONTEXT.md`. Path-qualified, so a rule and its same-named evidence twin are different targets. A path to a file that is not mirrored stays a backtick. A `:line` suffix is kept as visible text after the link.
- A bare `[[name]]` whose `rules/<name>.md` exists becomes `[[rules/<name>]]`.
- Never rewritten: frontmatter, the provenance comment, fenced code.
- A ledger note carries `kind: imp`, `id`, `ledger_status` (amended 2026-10-09: formerly `status`; renamed so the authored curation key `status` stays memory-only), `category`, `riskLevel`, `measured` (true or false) and dates in its frontmatter (a field that is null or missing in the ledger is omitted, never written as `null`). Its body has the title, Notes, Evidence, Files (links to the mirrored files) and Verification.

**Link check.** `scripts/knowledge-mirror.sh --check-links` is a report and exits 0. It prints `LINKS total= resolved= ambiguous= dangling=` (all links, resolved ones, ambiguous ones, dangling ones) and up to 30 dangling or ambiguous lines. A real run ends with the same `LINKS` line. `TOTAL` counts all copies and ledger notes, not `README.md`. The link check is the fail-loud signal for decay of the graph.

**What it hard-excludes**, even if the allowlist is widened later: `*.local.md`, `vault/` (the pseudonym store), and `*.jsonl` (raw transcripts). The regression suite pins the first two with fixtures the allowlist can actually reach; `*.jsonl` cannot be produced by the allowlist at all, so that exclude is defense in depth, not a pinned behaviour.

**Refusals** (exit 1, nothing written): the target is unset or empty, not an absolute path, contains a `.` or `..` component, is named `vault`, is equal to or inside `~/.claude` or the workshop, or *contains* either of them (so `$HOME` itself is refused); `<KNOWLEDGE>/mirror/` or anything below it is a symlink. Separately (exit 3, nothing overwritten): a mirror copy was edited by hand since the last run, detected with a per-file hash; the message names the file and how to recover. It writes only under `<KNOWLEDGE>/mirror/` and creates an empty `<KNOWLEDGE>/notes/` if missing. `--dry-run` prints the complete target list and a count and writes nothing, not even `notes/`. `--check-links` is the third mode (see Link check). The v2 additions change none of the refusals, hard-excludes, the hand-edit check or the idempotence of a rerun.

**Manual trigger for now.** The owner runs the script by hand. No hook or schedule is added, so no `settings.json` change and nothing that needs a deploy plus a new session just to test. The mirror is a snapshot and goes stale between runs; check the timestamp in `mirror/README.md`. The justification graph goes stale the same way: a link added to a source appears in the mirror only after the next run. An automatic trigger is added only after about two weeks show the copy actually going stale.

### Contract v3 (curation keys, generated keys, Mentions, link hygiene, graph export)

**Status:** built 2026-10-09 (wave A), except where an item says "wave B, not built". Amended 2026-10-09: the marks were flipped after the adversarial check against this contract, and the reviewer-confirmed deviations are written into the text below as "amended" notes; where this text and the code disagree, the code wins. Decision and boundary: `docs/adr/0008-curation-keys-authored-generated-in-mirror.md`, extending ADR 0007.

**Tokens.** `<K>` means `<KNOWLEDGE>`, the directory `$CLAUDE_KNOWLEDGE_DIR` points to (set in `~/.claude/env.local.sh`). Under `<K>`: `mirror/` (script-owned, as above), `notes/` (the owner's), plus two machine-local folders that are never tracked and never mirrored because they name private notes: `eval/` (question sets, history, lookup log; see Stage 3) and `curation/` (backfill worksheets, and in wave B the project map). Mark: `eval/` built (question file, history and lookup log are created or read by the scripts); `curation/` is created by the owner-gated backfill (not run on 2026-10-09; wave B, not built for the project map).

**Authored curation keys.** Set by the owner (or by the owner-gated backfill applier) in the SOURCE memory notes only. No script writes them, and the mirror copies them through unchanged like any other authored key. Superseded notes are kept, never deleted.

| Key | Values | Meaning | Mark |
|---|---|---|---|
| `status` | `active`, `superseded`, `archived`; absent means `active` | lifecycle of a note; a value outside the vocabulary is a lint finding (`status`). Amended 2026-10-09: the vocabulary applies to memory copies only; IMP copies carry the generated `ledger_status` instead (see Generated keys) | built (lint, lookup) |
| `superseded_by` | a mirror-relative path, e.g. `memory/<proj>/<file>.md` | the successor of a superseded note; the lookup ranks the note after it. Amended 2026-10-09: the lookup normalises the value the way the lint does, and ignores the status of IMP copies | built (lint, lookup) |
| `valid_from` | `YYYY-MM-DD` | the day the note's claim started to hold. Amended 2026-10-09: it has first priority as the source of `dated` (`dated_from: frontmatter`) | built (mirror) |
| `backfilled` | `YYYY-MM-DD` | stamped by the owner-gated backfill applier on every note whose lines it inserted. Amended 2026-10-09: it is never a date source for `dated` | key honoured by mirror and lint; the applier itself is not run (see Backfill) |

**Generated keys** (mirror copies only; `kind` and `origin` are built and described above):

| Key | Values | Meaning | Mark |
|---|---|---|---|
| `dated` | `YYYY-MM-DD` | the first ISO date found in the note, else the source mtime. Amended 2026-10-09: a frontmatter `valid_from` is tried first, then any other frontmatter value except `description` (so a `modified:` timestamp counts as a date: `dated_from: frontmatter`); `backfilled` never counts; the mtime fallback is the UTC date. IMP notes and the ledger index carry no `dated`/`dated_from` | built |
| `dated_from` | `frontmatter`, `body`, `description`, `mtime` | where `dated` came from, tried in that priority; `mtime` is the fallback | built |
| `origin_session` | `present`, `missing` | memory notes that carry a session id: whether the transcript file exists, by file existence only; transcript contents are never read and `*.jsonl` stays hard-excluded | built |
| `ledger_status` | the ledger's own status value | IMP copies only (amended 2026-10-09). IMP copies carry `ledger_status:` instead of `status:`, plus `id`, `category`, `riskLevel`, `measured` and dates; this keeps the authored `status` vocabulary out of the IMP namespace and restores ADR 0008's "cannot collide by construction" sentence (that ADR is immutable and is not edited) | built |

Amended 2026-10-09: there are five generated keys (`kind`, `origin`, `dated`, `dated_from`, `origin_session`) on memory copies; `ledger_status` is the sixth, on IMP copies only. A touched source mtime changes `dated` for mtime-dated notes and therefore makes `CHANGED` non-zero once; this is accepted, and so is a transcript appearing or disappearing (it flips `origin_session`). A generated key never collides with an authored one (rule of ADR 0007's amendment).

**`## Mentions`** (generated section, copies only), at the end of IMP, rule, ADR, evidence, doc and memory copies: up to 10 notes that link to this one, ordered memory, rule, adr, logbook, plan, newest first within each kind, then a line "and N more". An IMP copy also links the logbook day of its `implementedAt` or `proposedAt` when that logbook file exists, labelled `same-day` (the `same-day` link is built). The lookup ignores the section (from a `## Mentions` line to the end of the file). Amended 2026-10-09: `## Evidence` (rule copies) is followed only by `## Mentions`. Mark: built.

**Link hygiene** (copies only; sources are not rewritten). Mark for all four: built.

Amended 2026-10-09, rewrites the contract did not state (all copies only; `--no-v3-links` switches the v3 link features off and gives the v2 edge set, used as the grader's check):

- A plain `IMP-<digits>` in any copy becomes `[[ledger/IMP-n|IMP-n]]`.
- In logbook and plan copies, a backtick `projects/<f>/memory/<x>.md` (or `~/.claude/projects/...`) becomes `[[memory/<f>/<x>]]` when that copy exists; otherwise `--check-links` reports it.
- The `[t](f.md)` rewrite applies to every memory copy, not only MEMORY.md. A `:a-b` line suffix or `#heading` suffix is kept.

- A bare memory link resolves inside its own project folder first, folding `-`/`_` and case. A **unique** match is rewritten to `[[memory/<proj>/<file>]]`; an ambiguous one is left as it is.
- A MEMORY.md link `[title](file.md)` is rewritten to `[[memory/<proj>/file|title]]`.
- `--check-links` counts markdown links too. Amended 2026-10-09: it prints up to 30 dangling plus up to 30 ambiguous lines, and on an empty mirror it ends with an error instead of a `LINKS` line of zeros.
- Every `dangling:` line carries a cause: `slug` (hyphen/underscore or case mismatch), `missing` (no such target), `excluded-by-design` (target is hard-excluded, e.g. a `*.local.md`), `template` (a placeholder token, not a link). Amended 2026-10-09: the lint's own `dangling` code covers `[[wikilinks]]` in memory copies only.

**IMP copies** drop empty Notes, Evidence and Files sections and the repeated proposed-entry verification note (read-cost trim). Mark: built. Amended 2026-10-09: IMP notes and the ledger index carry no `dated`/`dated_from`; their `status:` is replaced by `ledger_status:` (see Generated keys); the `size` lint figure is measured on the mirror copy, including generated frontmatter and Mentions.

**Graph export.** Each mirror run writes two TSV files into `<K>/mirror/graph/`. They are not `.md`, so Obsidian draws no nodes for them, the lookup does not search them, and they lie outside the hash and stale logic (like `README.md`). Paths in both are mirror-relative (`memory/<proj>/<file>.md`, `rules/foundation.md`, `ledger/IMP-250.md`). Mark: built. Amended 2026-10-09: the layout of `<K>/mirror/` therefore also includes `graph/`; in `nodes.tsv` the `status` of an IMP node is `active` and its `dated` is `implementedAt`, else `proposedAt`, else empty; `edges.tsv` has one row per link occurrence, so duplicates are by design and consumers dedupe; `--orphans` of the lint ignores inbound edges of `via` `mentions` and `same-day` and prints `mentions_only=`.

| File | Header (tab-separated) | Notes |
|---|---|---|
| `graph/nodes.tsv` | `path	kind	status	dated	description` | one row per copy |
| `graph/edges.tsv` | `src	dst	via` | `via` is one of `wikilink`, `mdlink`, `evidence`, `mentions`, `same-day` |

**Wave B, not built** (not part of wave A; only on an eval signal; also not built: the O12 stubs for missing link targets; specified 2026-10-09): project map `<K>/curation/projects.tsv` (folder, project, aliases; local, owner-confirmed) and generated hub notes `mirror/projects/<name>.md` with `kind: project`; the optional split of docs over 30 KB by H2 into `mirror/docs/<name>/<section>.md` under a generated parent index (only if tokens-to-answer p90 on doc-answered questions stays above 10k after the output changes of Lookup v3).

**Non-goals (v3).** No embeddings, no Neo4j or GraphRAG, no LLM extraction into the mirror, no generated structure written into sources, no automatic per-prompt injection of lookup results, nothing new always-loaded (the instruction budget stood at 148.9k of 150k), no deletion of stale notes. **Re-entry trigger for a graph store:** the eval shows at least 20% multi-hop questions failing with links, frontmatter and the TSV export, or the corpus passes about 2,000 notes.

### Checklist (run from the workshop, no deploy needed)

- **C1:** `bash <WORKSHOP>/scripts/tests/knowledge-mirror-regression.sh` passes. Then `bash <WORKSHOP>/scripts/run-all-tests.sh --workshop` is green; the new suite is discovered automatically.
- **C2:** Set `CLAUDE_KNOWLEDGE_DIR` in `~/.claude/env.local.sh`.
- **C3:** `bash <WORKSHOP>/scripts/knowledge-mirror.sh --dry-run` prints the full target list and a count. Expect zero `*.local.md`, zero `vault/` paths, zero `.jsonl`.
- **C4:** Do a real run, then open `<KNOWLEDGE>` as a second Obsidian vault. Expect `mirror/logbook/` (101 files: 100 dated plus the logbook README), `mirror/memory/<dir>/` (188 files in total), `mirror/plans/` (3), `mirror/rules/` (21), `mirror/ledger.md`, `mirror/README.md` with the run timestamp, and an empty `notes/`. These counts are the dry-run of 2026-10-08 and will drift. The script prints `TOTAL` and `CHANGED` lines and, on stderr, `hard-excluded N path(s)` — expect N = 4 (the four `*.local.md` overlays); it never names them. Under v2 the run also creates `mirror/evidence/`, `mirror/adr/`, `mirror/docs/` and `mirror/ledger/` (one note per unique ledger id), `TOTAL` counts all copies and ledger notes (not `README.md`), and the run ends with the `LINKS` line (C8). The counts above are v1's; v2 counts are in C8 and the v3 real run (589 copies) in the Record table.
- **C5:** Edit one mirrored file in Obsidian, then rerun. The script refuses, names the file, and overwrites nothing.
- **C6:** Rerun with no source changes. It prints `CHANGED 0`.
- **C7:** Create `notes/test.md`, then rerun. The note survives.
- **C8 (v2):** `bash <WORKSHOP>/scripts/knowledge-mirror.sh --check-links` prints the `LINKS total= resolved= ambiguous= dangling=` line; dangling tokens are listed.
- **C9 (v2):** In Obsidian's graph of `<KNOWLEDGE>`, the colour groups of the Graph legend appear, and the rules cluster shows orange evidence neighbours.
- **C10 (v3, built and run 2026-10-09; see the Record table):** after a real run every copy carries `dated` and `dated_from`; every `dangling:` line carries a cause; `mirror/graph/nodes.tsv` and `edges.tsv` exist with the headers above; the rerun prints `CHANGED 0`.

### Not testable before deploy

Commands and scripts load from `~/.claude` only after the work is merged to `main`, `claude-deploy` has run, and a **new** session has started. Until then these cannot be checked:

- `/rcode-init` writing `.obsidian/` into a new project's `.gitignore`;
- the script's presence at `~/.claude/scripts/knowledge-mirror.sh`;
- `.obsidian/` being ignored in the live install's `.gitignore`.

After deploy, in a new session: `~/.claude/pending-verification.md` lists the merged commits; `git -C ~/.claude check-ignore -v .obsidian/workspace.json` names `.gitignore`; `bash ~/.claude/scripts/knowledge-mirror.sh --dry-run` succeeds; `/rcode-init` in a throwaway temp directory writes a `.gitignore` containing `.obsidian/` (delete the directory afterwards).

## Graph legend

**Status:** built; amended 2026-10-09: seen in Obsidian on 2026-10-09 (C9, Record table).

The graph of `<KNOWLEDGE>` is read by colour. The colours are Obsidian "Groups" matched by path and stored in `<KNOWLEDGE>/.obsidian/graph.json`, which is configuration of that Obsidian vault and lies outside `mirror/`.

| Colour | Path | Frontmatter `kind` |
|---|---|---|
| green | `mirror/memory/` | `memory` |
| red | `mirror/rules/` | `rule` |
| orange | `mirror/evidence/` | `evidence` |
| violet | `mirror/adr/` | `adr` |
| grey | `mirror/docs/` | `doc` |
| blue | `mirror/ledger/` | `imp` |
| yellow | `mirror/logbook/` | `logbook` |
| purple | `mirror/plans/` | `plan` |
| white | `notes/` | none: the owner's own notes, not a copy |

**Reading an edge.** Obsidian's edges are untyped: an edge says "linked", not why. The colour classes stand in for edge types, so the meaning comes from the colours at the two ends:

- from a red (rule) node to an orange (evidence) node: a **justification**, the rule and the evidence it rests on;
- from a blue (ledger) node to a red (rule) node: a **change record**.

**The measurement is not an edge.** Blue nodes carry `measured: true` or `measured: false` in their frontmatter. The "truth" edge of the graph is that measurement, and Obsidian cannot draw it as an edge; read it in the note's frontmatter.

## Stage 3: the agent's lookup

**Status:** built on 2026-10-08 (`scripts/knowledge-lookup.sh`, its regression suite, one rule sentence, one session-start hint); not yet exercised in a real task. Amended 2026-10-09: lookup v3 is built (suite 142 cases) and measured against the eval sets (Record table).

**Why a third stage.** Knowledge comes in three kinds, and each has one right place:

1. **Always true** — how the owner works with the agent, tool pitfalls, model choice: a few sentences in `rules/` and `*.local.md`, loaded into every session. That budget is nearly full (148.9k of 150k instruction tokens on 2026-09-24), so nothing else may be "always loaded".
2. **True for one project** — its terms, decisions, invariants: `CONTEXT.md`, `docs/adr/`, the project's own memory, loaded only there.
3. **True across projects, needed only sometimes** — what was learned about a library, a pitfall, a pattern in another project: this must be **searched on demand**, never loaded. Stage 2 put it in one place; Stage 3 is the search.

**Use.** `bash ~/.claude/scripts/knowledge-lookup.sh --stack` derives keywords from the current project's dependency files (`package.json`, `Package.swift`, `requirements.txt`, `pyproject.toml`, `Cargo.toml`, `go.mod`); `bash ~/.claude/scripts/knowledge-lookup.sh <keyword> ...` searches explicit terms; `--max N` widens the file list (default 12). Output: one header line with the number of matching files and keywords, then per file a header `== <path under mirror/>  [matched/total keywords]` and up to three matching lines. Ranking: distinct keywords matched, then matching lines. Exit 0 also on zero hits; exit 1 when the library is not available (set `CLAUDE_KNOWLEDGE_DIR` and run the mirror first); exit 2 on a usage error. Frontmatter and provenance lines never count as hits; nothing outside `<KNOWLEDGE>/mirror/` is ever searched. *Amended 2026-10-09 (lookup v3 replaces this paragraph where they differ, see § Lookup v3 and evaluation):* `--max` defaults to 8, not 12; the file header carries the kind and `~<n> tok`; each hit prints as `L<n> § <heading>: <text>`, not as a bare matching line; only `name:` and `description:` of the frontmatter are searched; the lookup writes one local usage log line (`--no-log` or `KNOWLEDGE_LOOKUP_LOG=0` turns it off). **Lookup v2** (built and deployed 2026-10-09, suite 84 cases) also searches the new mirror folders of Stage 2 v2 and tags each hit with its kind (taken from the folder, e.g. `(rule)`, `(imp)`, `(doc)`).

**Wiring.** `rules/foundation.md` § Context Management asks the agent to run the lookup before implementing in an area it has not worked in during the session. `hooks/session-start-context.sh` prints one 📚 line at session start when `<KNOWLEDGE>/mirror/README.md` exists, and nothing when it does not. The mirror is a snapshot: rerun `scripts/knowledge-mirror.sh` so the lookup sees recent memory.

### Lookup v3 and evaluation

**Status:** built 2026-10-09 (wave A; lookup suite 142 cases, eval suite 35, lint suite 76). Everything below amends the Use paragraph above where they differ (default `--max`, output format, what the lookup writes). Amended 2026-10-09: the reviewer-confirmed deviations are written into the items; where this text and the code disagree, the code wins.

**Lookup v3** (`scripts/knowledge-lookup.sh`, ranking in `scripts/lib/knowledge-lookup-rank.sh`, output and log in `scripts/lib/knowledge-lookup-fields.sh`). Mark for every item: built.

- **Ranking:** BM25F-lite (idf from each keyword's file count, saturated tf with k1 about 1.2, length normalisation with b about 0.75). Field boosts: basename x3, frontmatter `name:` and `description:` x3 (newly searched; `kind:`, `origin:` and provenance stay excluded), headings x2, body x1. Sort by distinct keywords matched, then by score. Amended 2026-10-09: there is also an exact-basename bonus (1.0 x idf when the file name without `.md` equals a keyword), a same-line co-occurrence bonus of 0.3 x the sum of the idf values, capped at 3 lines per file, and the logbook weight is x0.5; length normalisation applies to body and headings only.
- **Matching:** word-boundary matching, case-insensitive; `--prefix` opts in to prefix matching (`hook` finds `hooks`). A same-line co-occurrence bonus applies to multi-keyword queries. A quoted argument is one literal phrase. Amended 2026-10-09: uppercase keywords match, and the punctuation bytes `\342` and `\302` (the lead bytes of typographic punctuation) count as word boundaries.
- **Filters and defaults:** `--kind <kind>` (repeatable or comma-separated; kinds `memory rule evidence adr doc imp logbook plan index`), `--project <name>` (amended 2026-10-09: restricts the search to memory notes whose project folder name contains the value). The default excludes only `ledger.md` (kind `index`); the logbook is down-weighted, not excluded; MEMORY.md is kept. `--max` defaults to 8 (was 12).
- **Output per file:** a header with `~<n> tok`; one `» <description>` line (at most 160 characters) when the note has a description; each hit (up to 3) printed as `   L<n> § <heading>: <text>`; a hit before any heading is labelled `(top)`; a heading hit prints `L<n> § <heading>`; headings inside fenced code are skipped; headings are cut at 60 characters (160 when the heading is the hit); the 3 shown hits are the lines with the most distinct keywords, in line order. A superseded note is flagged `[superseded → <path>]` and ranked after its successor (the status of IMP copies is ignored). Amended 2026-10-09: the order `§ <heading> L<n>` in the first draft is replaced by the line format above.
- **Collision list** `scripts/lib/knowledge-lookup-collisions.tsv` (tracked, no private data), header `keyword	mode`; `mode` is `cs` (case-sensitive, e.g. `zustand`, because the German noun is capitalised) or `code` (matched only in code spans or import contexts, e.g. `immer`). It applies to `--stack` keywords too. Amended 2026-10-09: in mode `cs` an exact-case match always counts; a different-case match counts only on a line without a German function word (der, die, das, den, dem, des, und, ist, nicht, von, für, wird, ein, eine, einen, im, zu, zum, zur, auf, bei, nach, wenn, oder, auch, aber, sind), because the dev note writes "Zustand 5".
- **Usage log** `<K>/eval/lookup-log.tsv` (timestamp, query, top-3 paths; local only). This amends the earlier statement that the lookup writes nothing: it now writes exactly this one local log and nothing else. Amended 2026-10-09: `--no-log` or the environment variable `KNOWLEDGE_LOOKUP_LOG=0` turns it off (the eval harness sets it, so evaluation queries never enter the log); a failed write prints only a NOTE.

**Evaluation harness.** Mark: built.

- **Question file** `<K>/eval/questions.tsv` (machine-local, never tracked). Tab-separated, header `id	set	query	expected	class	source	confirmed`. `set` is `dev` or `test`. `expected` is one or more mirror-relative paths separated by `|` (any one counts as a hit), or `-` for "no defined expectation" (unscored). `class` is one of `lookup`, `paraphrase`, `crosslang`, `supersession`, `structural`. `confirmed` is `yes` or `no`. Readers select columns by header name and ignore unknown extra columns. The draft file `<K>/eval/questions-draft.tsv` has the same columns plus `rationale`.
- **Sets:** dev is the 12 queries of the 2026-10-09 measurement (the retrieval probe behind the optimisation plan; the measured results are over n=10 scored rows); test is 25 owner/judge-confirmed held-out questions, frozen before lookup v3 was tuned.
- **Scorer** `scripts/knowledge-eval.sh` (tracked, data-free; scoring in `scripts/lib/knowledge-eval-score.sh`). It calls `scripts/knowledge-lookup.sh` itself, so it exercises the same code path. It prints `EVAL <set> n=… hit@1=… hit@3=… mrr10=… tta_median=… tta_p90=… unconfirmed=<u> runtime=…s`, one `MISS` line per miss and a `SKIP` line per structural row, and appends a line to `<K>/eval/history.tsv` (timestamp, set, metrics, mirror stamp, lookup git hash). A missing question file prints an explicit `EVAL SKIP …` on stderr and exits 3, never a silent pass. Amended 2026-10-09: options `--set dev|test|all` (default `all`), `--questions FILE`, `--max N` (default 10, so MRR@10 is computable), `--no-history` and `--verbose` (one `ROW <id> rank=<r> tta=<tok>` line per scored row); `unconfirmed=<u>` counts scored rows with `confirmed` not `yes`. Exit codes: 0 ok, 1 environment, lookup or history failure, 2 malformed question file or usage, 3 SKIP (also when no row is scorable). Dependencies: `perl` (runtime clock) and `git` (the lookup hash, `-dirty` when `scripts/knowledge-lookup.sh` or `scripts/lib` has uncommitted changes); a missing one is an error, exit 1.
- **Tokens-to-answer (tta)** is a deterministic proxy: lookup stdout bytes/4, plus bytes/4 of each listed file up to and including the first expected one, capped at the top 5. A miss costs the top-5 total and is flagged. It assumes the agent reads in rank order and is labelled as a proxy everywhere it is printed.

**Lint** `scripts/knowledge-lint.sh`: a read-only report over the mirror that exits 0, like `--check-links`. Mark for every item: built, except the write-time advisory hook (wave B, not built). Amended 2026-10-09: it exits 1 on a usage error, an unreadable mirror, a missing graph export for a graph query, and (new) when a pipeline inside the lint fails (`LINT error`); a finding never changes the exit code. The lint also needs `--summary` (prints only the `LINT` summary lines).

- **Per-note codes:** `desc` (description missing), `claim` (WARN; the first body line is a date, status or narrative marker), `why` and `how` (required for feedback and project notes; reference and user notes are exempt), `date` (no date found; a generated `modified:` timestamp is ignored, and `backfilled` never counts), `size` (over 8 KB, measured on the mirror copy including generated frontmatter and Mentions), `dangling` (a `[[wikilink]]` outside code that does not resolve, in memory copies only; ambiguous is a WARN), `status` (a value outside the vocabulary above, or a `superseded_by` that names no mirror file; memory copies only). Amended 2026-10-09, extra codes: `type` (WARN; no or unknown source `type:`, treated as project), `ambiguous` (WARN), `frontmatter` (FAIL; missing or unclosed) and `unreadable` (FAIL), plus a `WARN status-form` finding for a malformed status value. MEMORY.md indexes get only `dangling`. Per-note lines print as `FAIL|WARN <code> <path>`, sorted by path.
- **Summary lines:** `LINT n=…`, `LINT why_present=… how_present=… both=…` and `LINT type=<t> n=… why=… how=…` (one per type).
- **Modes:** `--contradictions` (report only, never edits; line format `CONTRADICTION <rule> <path-a> <path-b> <evidence>`). Rules: `status` (same project, one note says pending and the other done; the pair needs the same basename stem or at least 3 shared non-stopword title tokens), `dup-basename` (duplicate basenames across projects), `abandoned` (a note in a folder another note declares abandoned), and, amended 2026-10-09, a fourth rule `overtaken` (a note links a same-folder note on a line saying outdated, obsolete, superseded or veraltet). `--refs` (backtick paths resolved against `~/.claude`; prints `REFS kind=<k> external=<n> dead=<n>` per contract kind, `REFS dead <path> in <note>` and `REFS session present|missing|noid`; session ids checked by file existence only). `--orphans`, `--superseded`, `--rules-without-evidence` read the graph TSV and exit 1 with a message when the export is missing; `--orphans` prints `ORPHAN(S)` lines grouped by kind, ignores inbound edges of `via` `mentions` and `same-day`, prints `mentions_only=` and skips the header rows of the graph files.
- **Write-time advisory hook:** wave B, not built (planned after two weeks of report-only running).

**Pipeline contracts** (prompt edits, effective only after merge, deploy and a new session). Mark: not covered by wave A's scripts; whether the prompt edits are merged and deployed is not recorded here (not verified 2026-10-09).

- daily-docs lists the day's new memory note paths in the logbook.
- meta-observer and weekly-improve write provisional ids as `P-IMP-NNN`, so the mirror's IMP linker does not attach them to later ledger ids.
- `/lessons` writes one pointer memory note per ADR or pattern it adds.

**Backfill** (owner-gated). Mark: the worksheet-and-applier flow was not run on 2026-10-09 (owner-gated, no source note was edited); the mirror and lint already honour `backfilled`. A worksheet `<K>/curation/backfill-<date>.tsv` holds drafted lines per note, drafted only from the note and the notes it links, with "unknown" where the note does not contain the answer. The owner accepts or rejects each row in the browser. A dated backup of each touched memory folder is taken before any source edit. An additive applier inserts the accepted lines, never rewrites a body, and stamps `backfilled: <date>`.

### Retrieval protocol (ADR 0009)

**Status:** decided 2026-10-09 (`docs/adr/0009-agentic-retrieval-over-lexical-lookup.md`). The `--alt` flag is built by unit D1 and the wiring into `rules/foundation.md` and the session-start hook by unit D2b; neither is verified in this text, and where it and the code disagree, the code wins. Options and licences: `research/knowledge-retrieval-semantic-options-2026-10-09.md` (R1).

**The protocol, as the agent sees it.** The lookup matches words, not meaning, so the agent supplies the meaning:

1. Rewrite the question into 2–4 keyword sets: its own words, the translation into the other language (German and English), synonyms and the technical terms.
2. Run them in one call: `bash ~/.claude/scripts/knowledge-lookup.sh --alt "<set 1>" --alt "<set 2>" ...` (one `--alt` per set).
3. Judge the hits by the `»` description lines, not by the matched lines.
4. Open only the top note's section (the `L<n> § <heading>` hit), not the whole note.

No vector index, no embedding model and no hosted service is involved; the tool stays lexical and deterministic.

**Measured routes (2026-10-09, same scorer, hit@3; test = 25 held-out questions, dev = 10 queries).**

| Route | Dev | Test | Cost per question |
|---|---|---|---|
| Lookup v3 alone | 10/10 | 10/25 (hit@1 8/25) | ~1k tokens, 0.3 s |
| Agent rewrite + lookup only (this protocol) | 10/10 | 25/25 (hit@1 24/25), 2.8 calls on average | ~2–3k tokens, one LLM turn per set |
| Agent reads the catalog, no lookup | 6/10 | 24/25 (hit@1 23/25) | ~16k tokens |
| Catalog + lookup | 10/10 | 24/25 | ~17k tokens |
| Dense, on-device (Apple NaturalLanguage, prototype 2026-10-09) | 0/10 alone | 1/25 alone (3/56); weighted hybrid 11/25 (23/56) = lexical ±1; equal-weight RRF worse than lexical | 140 ms, Swift, macOS-only; English and German models share no vector space, so no cross-language bridge |

The test classes are lookup 7, paraphrase 6, crosslang 8 and supersession 4; the rewrite route found all of each class. **Caveat:** n=25 gives roughly ±19 points at 95 %, so this shows a large gap between routes, not a precise rate.

**Measured again on 56 held-out questions (2026-10-09, after the set grew; lookup 13, paraphrase 15, crosslang 19, supersession 9):** live agent route 56/56 (hit@1 54/56, 2.8 calls on average). Deterministic replay of the frozen keyword sets (`questions.tsv` column `alts`, `knowledge-eval.sh --alts`) through `knowledge-lookup.sh --alt` with best-rank-first fusion (`--fuse best`, default since 2026-10-09; plain RRF scored 16/25 on the first 25 because a broad set buried notes ranked 1 in another set): hit@3 50/56 (89 %), hit@10 55/56 (98 %), hit@1 30/56, median tokens-to-answer 2,694. Lookup alone on the same 56: hit@3 22/56, hit@10 29/56. Per class, deterministic hit@3 / hit@10: lookup 12/13, paraphrase 12/15, crosslang 18/19, supersession 8/9. History: `<K>/eval/history.tsv` 2026-10-09T13:59–14:01Z.

**"Finished" thresholds** (R1 proposals, not standards): at least 50 held-out questions; hit@3 ≥ 80 % overall and ≥ 70 % on cross-language and paraphrase; hit@10 ≥ 90 %; median tokens-to-answer ≤ 5k; index stamp equal to the mirror stamp (no index exists — the lookup scans the mirror directly, so this condition is void). Met on 2026-10-09 with the deterministic numbers above; the frozen keyword sets were written by Sonnet agents following the protocol, so the deterministic score measures "the tool, given protocol-conformant rewrites", not the tool alone.

**Fallback (documented, not built):** `bge-m3` via Ollama over the 589 description lines, fused with BM25F by RRF; one new dependency, fail loud when absent. Triggered when a held-out set of at least 50 questions scores below 80 % under the protocol, when the corpus passes ~2k notes, or when the lookup usage log shows agents not following the protocol. The eval harness measures the protocol deterministically through frozen rewrites (unit D3).

### Checklist

- **L1:** `bash <WORKSHOP>/scripts/tests/knowledge-lookup-regression.sh` passes (amended 2026-10-09: 142 cases; the eval, lint and mirror suites have 35, 76 and 379).
- **L2:** `bash <WORKSHOP>/scripts/knowledge-lookup.sh zsh` finds the mirrored memory note about the zsh modifier trap (a note that exists in this repo's own project memory) among its hits; `--stack` run inside a project with a `package.json` prints `keywords: ...` on stderr and a header line with a count.
- **L3 (after deploy, new session):** the session start shows the 📚 line with the mirrored note count, and `bash ~/.claude/scripts/knowledge-lookup.sh --help` works from the live install.

## Project level

**No per-project Obsidian vault by default.** Project knowledge that lives in `.rcode/` would be invisible there, because dot-folders such as `.rcode/` and `.claude/` are reported hidden from the explorer, search and graph [C/S]. A scan on 2026-10-08 counted 35 `.rcode/agent-log.md` files, 12 `.rcode/phase-summaries/*.md` files and 39 auto-handoff files (`.rcode/handoff-*.md`) across the project trees it covered. A per-project Obsidian vault would also cost:

- one registration per project, done in the Obsidian UI only (no CLI or URI route is known) [O/C];
- an `.obsidian/` ignore line in every project;
- duplicate-basename collisions within each project (CONTEXT and ADR names) [C].

Opening one project as its own Obsidian vault stays possible ad hoc. The only framework support it needs is an ignore line:

- **Existing project:** if you open it in Obsidian, add `.obsidian/` to its `.gitignore` first. `/rcode-upgrade` does not do this: it never edits a project's `.gitignore`.
- **New project:** `/rcode-init` writes `.obsidian/` into the minimal `.gitignore` it creates when none exists (an existing `.gitignore` is never touched). Commands load from `~/.claude`, so this applies only after the change is deployed and a new session has started.

Unchanged on purpose: `rcode/templates/` (no YAML frontmatter and no `[[...]]` added, see Link convention) and `rcode/VERSION` (no bump, see Decisions).

Bringing project docs into the window is Stage 2b. It is gated: it starts only after the owner has reviewed Stage 2 and has seen a dry-run manifest of what would be copied, and it ships as a separate merge.

## Link convention

A **Rule link** is the token `[[name]]`: a bare basename, with no path and no extension, that points to `rules/<name>.md` (or, in a few places, to `skills/<name>/`). The form already exists in the tracked rules (10 rule files use it) and in the evidence files under `docs/archive/rules-evidence/`; this section documents it, it does not introduce it. It is a pointer for readers. Nothing in the framework resolves or checks it; Obsidian makes it clickable.

- **Duplicates.** `docs/archive/rules-evidence/` holds 20 files, 18 of which share their basename with a tracked rule (checked 2026-10-08). Obsidian's resolution rule for duplicate basenames is undocumented [C], so checklist step A4 records which file a click opens.
- **Skill targets.** A token that points at a skill (for example one that names the `create-skill` skill) names a folder, but Obsidian resolves a token to a note with that basename, and every skill's note is named `SKILL`. Expect such tokens to show as unresolved in Stage 1. This is an inference, not an observation.
- **One dangling link.** The token for `observation-capture` in `skills/historical-signals/SKILL.md` (line 119 on 2026-10-08) names a hook (`hooks/observation-capture.sh`), which has no note, so it shows as unresolved. Nothing checks these tokens today. Do not click an unresolved link: it creates a note.
- **In the mirror.** The Stage 2 mirror rewrites bare rule links to path-qualified ones (`[[rules/<name>]]`) and backtick repo paths to wikilinks in its copies only; the sources are not rewritten (`docs/adr/0007-justification-graph-in-the-mirror.md`).
- **Not a rule, not extended.** The convention is documented here and in `CONTEXT.md`, not in a rule, because rules are loaded into every session and cost budget there. It is not extended to `rcode/templates/`, which carry no frontmatter and no `[[...]]` today: adding either would risk the frontmatter rewrite described above and the formats that `scripts/resume-state.sh` and `scripts/rcode-units.sh` parse.

## Decisions

Owner decisions of 2026-10-08, every recommendation accepted as given.

1. **`.trash/` ignore line:** no. Set "Deleted files = Move to system trash" instead; a stray `.trash/` in `git status` blocks deploy, which is the fail-loud signal that a tracked file was deleted in Obsidian.
2. **Rule link as a documented convention:** yes, documented here and in one `CONTEXT.md` entry, not in a rule, not extended to templates.
3. **Own notes in the workshop Obsidian vault:** no. They go to `<KNOWLEDGE>/notes/`; a tracked notes folder would deploy into `~/.claude`.
4. **Where `CLAUDE_KNOWLEDGE_DIR` points:** the internal disk under `$HOME`, outside `~/.claude`, the workshop and any synced folder.
5. **Mirror trigger:** manual first; automatic only once the copy is seen going stale.
6. **Agent access through the Obsidian CLI or MCP:** no; plain Read and Grep. The CLI needs the app running and exposes `eval`, `plugin:install` and `delete` with no documented permission model [O].
7. **`rcode/VERSION` bump:** no. A `.gitignore` line in a command is neither a rail nor a parsed format, and a bump would mark every deployed project as behind for zero content change.
8. **Stage 2b (project docs):** after Stage 2 has been reviewed, as a separate merge, with the dry-run manifest shown first.
9. **Publish:** the owner's decision, to be taken after the post-deploy check in a new session, so this guide does not ship an unverified claim.

## What is NOT verified

- Everything above: no step was run in Obsidian by the author of this guide, and the setting names in Stage 1 were taken from the plan, not checked against the app.
- Whether opening an existing folder as an Obsidian vault rewrites any note.
- The dot-folder rule (community report only).
- Which file a rule link resolves to when a duplicate basename exists, and whether "Excluded files" changes that.
- The default value of "Deleted files" (the official docs do not state it [S]), and behaviour on chmod-read-only files.
- Symlink indexing on macOS in 1.14.x. It matters only if folder symlinks are ever revisited (ADR 0006 defers them).
- Whether the Stage 1 settings should be repeated for `<KNOWLEDGE>`: no settings are prescribed for it.
- Stage 2 v2: whether Obsidian resolves the generated path-qualified links the way `--check-links` does (the two resolution rules are written independently); the 30 dangling tokens are listed by `--check-links` and were not fixed in their sources.
- Knowledge library v3: everything marked "wave B, not built", and the pipeline contracts and the backfill (not run). Also unverified: that Claude Code keeps authored curation keys when it later rewrites a memory note, that an existing `status:` key in a source note carries no other meaning (0 of 150 notes carried one on 2026-10-09), and how `grep -w` treats umlauts.
