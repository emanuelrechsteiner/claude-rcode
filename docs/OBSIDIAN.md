<!--
Status: ACTIVE
Last Updated: 2026-10-08
Purpose: How R.Code uses Obsidian as a read window over its distilled knowledge: safe setup of the workshop (Stage 1), the knowledge folder (Stage 2), project level, link convention, decisions
-->

# Obsidian as a read window

Tokens used here: `<WORKSHOP>` is this repo's working copy (see `CONTEXT.md`, **Workshop**). `<KNOWLEDGE>` is the directory that `CLAUDE_KNOWLEDGE_DIR` points to (Stage 2). Neither is a real path.

**Status (2026-10-08):** both Obsidian vaults are open on the owner's machine in restricted mode with the four settings written; Stage 1 is verified for A1–A3 and A9 and still unverified for A4–A8 (the link-resolution and graph observations, see the table); Stage 2's mirror has run against the real `~/.claude` and C3–C7 passed; Stage 3's lookup is deployed and its session-start hint was quoted verbatim by a new session. Everything listed under "What is NOT verified" stays open. The decision behind all of it is `docs/adr/0006-obsidian-read-window.md` (IMP-248).

## Purpose

Obsidian is a **read window** over distilled knowledge: rules, ADRs, the glossary, plans, the logbook, per-project memory and a ledger index, with working links between them. It ingests nothing, stores nothing, and is not a second source of truth. It never writes into a file that the framework or Claude Code reads.

It covers the distilled layer only. A measurement taken on 2026-10-08 put the distilled stores at about 10.84 MiB and the raw data (transcripts, caches, app stores) at about 34.10 GiB. The raw data never enters the window.

There are two windows, one per stage:

- **Stage 1** opens the workshop checkout (framework design: rules, docs, commands, agents, skills).
- **Stage 2** opens a machine-local knowledge folder holding read-only copies of the runtime distillate (logbook, memory).

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
| A4: link `agency-bands` opens | not yet recorded |
| A8: "Excluded files" changes resolution? | not yet recorded |
| A9: `git status` empty, no `.trash/`? | yes: after opening the vault and after a quit/restart, `git status` shows nothing from Obsidian (only files other agents were editing at the time) and `ls -a` shows `.obsidian` but no `.trash` |
| Stage 2 (C3–C7) | C3 dry-run 315 targets, 4 hard-excluded, nothing written; C4 real run created `mirror/` (101 logbook, 189 memory, 3 plans, 21 rules, ledger.md, README.md, 315 hashes) and an empty `notes/`; the Knowledge vault opened in Obsidian in restricted mode; C5 a hand-edited copy made the next run refuse with exit 3, name the file, print the recovery hint, and overwrite nothing (the edit was made outside Obsidian; detection is content-based); after deleting `hashes.tsv` the rerun refreshed the copy; C6 `CHANGED 0`; C7 `notes/test.md` survived |
| Stage 3 (L1–L3) | L1 suite 68/68; L2 `knowledge-lookup.sh zsh` lists the mirrored zsh-modifier memory note, `--stack` in a Node project derived 7 keywords and found 149 files; L3 a new headless session quoted the 📚 line verbatim after deploy |

## Stage 2: the knowledge folder

**Status:** built, not yet verified in Obsidian. `scripts/knowledge-mirror.sh` (bash 3.2) and `scripts/tests/knowledge-mirror-regression.sh` (same code path as the script) are in the workshop. A dry-run against the real `~/.claude` on 2026-10-08 listed 314 targets (101 logbook, 188 memory, 3 meta-proposals, 21 rules, 1 ledger index) and reported `hard-excluded 4 path(s)`; the script counts excluded paths but never names them, and 4 equals the number of `rules/*.local.md` overlays on that machine. The target folder was not created. Checklist C1 to C7 below is still open.

**Why a copy.** Obsidian rewrites links and frontmatter [O/C]. The only way to keep it from writing into a file the framework or Claude Code reads is to give it a copy. Stage 2 therefore puts read-only copies of the runtime distillate in `<KNOWLEDGE>`, outside every repo.

**Layout.** `<KNOWLEDGE>/mirror/` is owned by `scripts/knowledge-mirror.sh` and overwritten on each run. `<KNOWLEDGE>/notes/` is the owner's own space and is never touched by the script. Open `<KNOWLEDGE>` as its own Obsidian vault.

**Where it lives.** `CLAUDE_KNOWLEDGE_DIR` is set in `~/.claude/env.local.sh`, the machine-local file that is never versioned; the block to copy is at the end of `templates/env.local.sh.template`. It is an absolute path with **no default**: an unset variable makes the script refuse to run. It must be:

- outside `~/.claude` and outside the workshop;
- not under iCloud, Dropbox or Obsidian Sync, because it holds memory files and private project names;
- recommended on the internal disk under `$HOME`, so it stays available when the SSD is unmounted.

**What the mirror copies** (an allowlist, nothing else):

- the logbook (`~/.claude/logbook/*.md`);
- per-project memory (`~/.claude/projects/*/memory/*.md`), one folder per project directory;
- meta-proposals (`~/.claude/plans/meta-proposal-*.md`);
- the tracked rules only (`rules/*.md`, never a `*.local.md`);
- the improvement ledger rendered as `ledger.md`, one line per entry (id, status, title).

Each copy carries a provenance comment placed after a closed frontmatter block, otherwise as line 1 (a source whose opening `---` is never closed counts as having no frontmatter). `mirror/README.md` carries the run timestamp.

**What it hard-excludes**, even if the allowlist is widened later: `*.local.md`, `vault/` (the pseudonym store), and `*.jsonl` (raw transcripts). The regression suite pins the first two with fixtures the allowlist can actually reach; `*.jsonl` cannot be produced by the allowlist at all, so that exclude is defense in depth, not a pinned behaviour.

**Refusals** (exit 1, nothing written): the target is unset or empty, not an absolute path, contains a `.` or `..` component, is named `vault`, is equal to or inside `~/.claude` or the workshop, or *contains* either of them (so `$HOME` itself is refused); `<KNOWLEDGE>/mirror/` or anything below it is a symlink. Separately (exit 3, nothing overwritten): a mirror copy was edited by hand since the last run, detected with a per-file hash; the message names the file and how to recover. It writes only under `<KNOWLEDGE>/mirror/` and creates an empty `<KNOWLEDGE>/notes/` if missing. `--dry-run` prints the complete target list and a count and writes nothing, not even `notes/`.

**Manual trigger for now.** The owner runs the script by hand. No hook or schedule is added, so no `settings.json` change and nothing that needs a deploy plus a new session just to test. The mirror is a snapshot and goes stale between runs; check the timestamp in `mirror/README.md`. An automatic trigger is added only after about two weeks show the copy actually going stale.

### Checklist (run from the workshop, no deploy needed)

- **C1:** `bash <WORKSHOP>/scripts/tests/knowledge-mirror-regression.sh` passes. Then `bash <WORKSHOP>/scripts/run-all-tests.sh --workshop` is green; the new suite is discovered automatically.
- **C2:** Set `CLAUDE_KNOWLEDGE_DIR` in `~/.claude/env.local.sh`.
- **C3:** `bash <WORKSHOP>/scripts/knowledge-mirror.sh --dry-run` prints the full target list and a count. Expect zero `*.local.md`, zero `vault/` paths, zero `.jsonl`.
- **C4:** Do a real run, then open `<KNOWLEDGE>` as a second Obsidian vault. Expect `mirror/logbook/` (101 files: 100 dated plus the logbook README), `mirror/memory/<dir>/` (188 files in total), `mirror/plans/` (3), `mirror/rules/` (21), `mirror/ledger.md`, `mirror/README.md` with the run timestamp, and an empty `notes/`. These counts are the dry-run of 2026-10-08 and will drift. The script prints `TOTAL` and `CHANGED` lines and, on stderr, `hard-excluded N path(s)` — expect N = 4 (the four `*.local.md` overlays); it never names them.
- **C5:** Edit one mirrored file in Obsidian, then rerun. The script refuses, names the file, and overwrites nothing.
- **C6:** Rerun with no source changes. It prints `CHANGED 0`.
- **C7:** Create `notes/test.md`, then rerun. The note survives.

### Not testable before deploy

Commands and scripts load from `~/.claude` only after the work is merged to `main`, `claude-deploy` has run, and a **new** session has started. Until then these cannot be checked:

- `/rcode-init` writing `.obsidian/` into a new project's `.gitignore`;
- the script's presence at `~/.claude/scripts/knowledge-mirror.sh`;
- `.obsidian/` being ignored in the live install's `.gitignore`.

After deploy, in a new session: `~/.claude/pending-verification.md` lists the merged commits; `git -C ~/.claude check-ignore -v .obsidian/workspace.json` names `.gitignore`; `bash ~/.claude/scripts/knowledge-mirror.sh --dry-run` succeeds; `/rcode-init` in a throwaway temp directory writes a `.gitignore` containing `.obsidian/` (delete the directory afterwards).

## Stage 3: the agent's lookup

**Status:** built on 2026-10-08 (`scripts/knowledge-lookup.sh`, its regression suite, one rule sentence, one session-start hint); not yet exercised in a real task.

**Why a third stage.** Knowledge comes in three kinds, and each has one right place:

1. **Always true** — how the owner works with the agent, tool pitfalls, model choice: a few sentences in `rules/` and `*.local.md`, loaded into every session. That budget is nearly full (148.9k of 150k instruction tokens on 2026-09-24), so nothing else may be "always loaded".
2. **True for one project** — its terms, decisions, invariants: `CONTEXT.md`, `docs/adr/`, the project's own memory, loaded only there.
3. **True across projects, needed only sometimes** — what was learned about a library, a pitfall, a pattern in another project: this must be **searched on demand**, never loaded. Stage 2 put it in one place; Stage 3 is the search.

**Use.** `bash ~/.claude/scripts/knowledge-lookup.sh --stack` derives keywords from the current project's dependency files (`package.json`, `Package.swift`, `requirements.txt`, `pyproject.toml`, `Cargo.toml`, `go.mod`); `bash ~/.claude/scripts/knowledge-lookup.sh <keyword> ...` searches explicit terms; `--max N` widens the file list (default 12). Output: one header line with the number of matching files and keywords, then per file a header `== <path under mirror/>  [matched/total keywords]` and up to three matching lines. Ranking: distinct keywords matched, then matching lines. Exit 0 also on zero hits; exit 1 when the library is not available (set `CLAUDE_KNOWLEDGE_DIR` and run the mirror first); exit 2 on a usage error. Frontmatter and provenance lines never count as hits; nothing outside `<KNOWLEDGE>/mirror/` is ever searched.

**Wiring.** `rules/foundation.md` § Context Management asks the agent to run the lookup before implementing in an area it has not worked in during the session. `hooks/session-start-context.sh` prints one 📚 line at session start when `<KNOWLEDGE>/mirror/README.md` exists, and nothing when it does not. The mirror is a snapshot: rerun `scripts/knowledge-mirror.sh` so the lookup sees recent memory.

### Checklist

- **L1:** `bash <WORKSHOP>/scripts/tests/knowledge-lookup-regression.sh` passes.
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
