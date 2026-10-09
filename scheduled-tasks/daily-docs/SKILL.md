---
name: daily-docs
description: Daily logbook entry — item counting runs exclusively through a reference script (never manually/by feel), aggregates signals/git/memory for the prose, writes markdown + syncs to Notion.
---

<!-- Expected cwd: ~/.claude · Timer: launchd com.claude-code.routine-daily-docs (since 2026-08-22, IMP-135; label made generic since IMP-219, 2026-09-25; before that an unversioned cloud binding to a directory renamed on 2026-08-02 — 20 days of silent failure). -->

Run the documentation-agent in Mode B (Daily-Docs Routine).

## Date window
Process activity from yesterday (00:00 to 23:59 local).
`yesterday=$(date -v-1d +%Y-%m-%d)`

## Run order — THE RECEIPT COMES FIRST

**The very first durable action of every run — before counting, before the logbook,
before Notion:**

```bash
bash ~/.claude/scheduled-tasks/daily-docs/bin/run-log.sh start "$yesterday"
```

Mandatory order: **C-start → count → A → B → C-finish**.
No longer A → B → C. The receipt is CREATED before any artifact exists, and at the
end only ever RAISED (`finish`), never written for the first time.

### Why reversed (measured 2026-07-31, run for 2026-07-30)

The run fired on schedule at 07:10, wrote §A (`logbook/2026-07-30.md`),
updated §B (Notion sub-page `<notion-subpage-id>`) — and
died 11 seconds after §C began with `[Request interrupted by user]`
(last action: `grep -rn 'daily-docs-log'`, transcript
`<session-id>`). Result: both artifacts present,
the date series jumped 2026-07-29 → 2026-07-31, every coverage check reported a
**FALSE NEGATIVE "never ran"**. Backfilled the line: 2026-08-01.

This is the inverse of the IMP-075 case and structurally guaranteed as long as §C
comes last: **§A and §B each leave one artifact, §C IS the artifact.**
Any abort in between — interrupt, crash, context end, token budget,
scheduler timeout — produces artifacts with no proof. With `start` first, the
same case instead leaves a `status:"partial"` line standing: a visible partial
run instead of an invisible gap.

Side finding from the same run: its last action was researching whether
consumers read `items` or `items_total` — a question that only arose because
the §C template below had shown `"items": N` for years, while the rest of this spec
mandates `items_total`. The drift is fixed via the backfill; number fields are
no longer hand-typed anyway (see `finish` below).

> Why a script and not a prose instruction: the same lesson as with the counting
> (2026-07-18 — `logbook-count.sh` replaced the agent's own estimate). An agent
> that aborts no longer executes a prose instruction. A call that happens first,
> by contrast, has already happened.

## Daily count — MANDATORY PROCEDURE

You do NOT count yourself. You run the reference script and adopt its JSON
unchanged. A self-estimated number, or one recomputed from `git log`, is a
procedural error.

**Script:** `~/.claude/scheduled-tasks/daily-docs/bin/logbook-count.sh <YYYY-MM-DD>`
(maintained separately — this spec references only the call and the contract terms,
not the internal logic).

### Count basis — one sentence
An item is a unique file by repo identity (`<repo_id>::<relpath>`, else
`fs::<path>` outside any repo) whose content was changed on the target day by an
evidenced write. Merge-materialized files do NOT count as items
— they appear under `vcs_operationen` (see Outputs A), never added into `items_total`.

### Procedure
1. `bash ~/.claude/scheduled-tasks/daily-docs/bin/logbook-count.sh "$yesterday"`
2. **Exit ≠ 0 → no logbook entry with a number.** See the fail-loud contract below.
3. **Exit = 0 →** adopt the following fields from the JSON unchanged. The names were
   verified against the real script output on 2026-07-18 — use EXACTLY these, don't guess:

   | Field in the JSON | Meaning |
   |---|---|
   | `items_total` | the day's count (NOT `items` — that field does not exist) |
   | `count_basis` | always `files_touched_v3` |
   | `evidence_tier` + `evidence_tier_grund` | evidence tier and its justification |
   | `quellen_epochen` | when each source starts to exist (replaces the earlier `aera`) |
   | `sources` | a read-certificate per source (an object, not an array) |
   | `vcs_operationen` + `vcs_zaehler` | merges etc., their own paragraph |
   | `nicht_erfassbar` | mandatory section of the entry |
   | `status` | `OK` or `DEGRADED` |

   ALL of these fields are MANDATORY in every entry — even on an `items_total:0` day.
   **Can't find a field: do NOT improvise, do NOT fall back to a similar-looking one.**
   Then the script's contract has changed → `status:"fail"`, `reason` = the missing field.

### What you must NEVER do
- Add up `items_total` and `vcs_operationen` — two independent quantities, not summands.
- **State numbers computed yourself in the prose.** No "85 commits", no "39 items on the
  transcript axis", no partial sums. The ONLY valid number in the entry is `items_total`
  from the script. Evidence is LISTED (SHAs, paths), never summed.
  *Measured during the 2026-07-18 backfill: numbers from evidenced individual parts feel
  evidenced but don't reproduce — actually observed "85 commits" (really 83) and "54 commits"
  (really 53). A sum is only evidenced if the arithmetic behind it is reproducible too.*
- **Infer technology from file names.** "BootScene.ts, MenuScene.ts" proves no
  framework. Either find and cite the evidence (a `package.json` entry) or drop
  the claim.
- **Call a directory a "repo" without having checked for `.git`.**
- Write any number at all on exit ≠ 0 (not even an "approximate" one, or one
  self-counted from `git log`).
- Omit the "Not capturable for this day" section — it is mandatory in every
  entry, even a complete one.
- Derive `evidence_tier`/`quellen_epochen` yourself — both come only from the script.

### Fail-loud contract
If the script aborts with an ABORT code: run-log line `"status":"fail"`,
`"reason"` = the ABORT message verbatim. NO invented number, NO improvised
alternative count, no `mkdir`/workaround. Exit ≠ 0 means: no `items_total` field
in the entry — neither in the logbook nor in the run log.
Mechanism: `bash bin/run-log.sh fail "$yesterday" --reason "<ABORT message verbatim>"` —
the script omits the number fields instead of setting them to `null`.

### ABORT codes (script exit ≠ 0 — each is a procedural stop, not a warning)
| Exit | Meaning |
|---|---|
| 1 | day argument missing |
| 2 | window bounds empty/invalid/not ascending |
| 3 | search root missing or sentinel unreadable (volume not mounted) |
| 4 | 0 transcripts found — a measurement error, not an empty day |
| 5 | signals missing or truncated |
| 6 | timezone not determinable (IMP-219: neither `$TZ` nor `$CLAUDE_LOGBOOK_TZ` set, system timezone unreadable) |
| 7 | `items_total=0` even though other sources deliver |
| 9 | output not written or empty despite input |
| 10 | working directory not fresh |
| 11 | canary/second counter diverges |
| 12 | failure filter collapses at 0 patterns |
| 13 | Q_T=0 despite independent witnesses |
| 14 | `items_total` < 50% of the reference axis |
| 15/16 | transcript/desktop scan incomplete |
| 17 | signals `empty_verified`, but event lines in the window |
| 18 | certificate requirement violated (no `state=`) |
| 19 | symlink in the scan tree, or root addressed via a symlink |
| 20 | a pinned tool (`/usr/bin/find`/`/usr/bin/grep`) is missing |
| 21 | S12/Q_V not evaluable |

`evidence_tier` (1–4) plus `evidence_tier_grund` is also delivered by the script, along with
`quellen_epochen` — the start dates of the sources (`signals:2026-06-19`,
`transkripte:2026-03-18`, `desktop:2026-02-04`). For daily runs (always "yesterday"),
all sources exist, so the epochs are just context. Measured on 2026-07-18:
a daily run delivers `evidence_tier:2` / `status:DEGRADED`, because the manual-work
branch (`manifest`) retroactively never exists — that is the NORMAL STATE, not an error and
no reason to hold back the entry. Tier 1 is currently unreachable for any day.

## Additional sources for the prose (NOT for the count)

These provide CONTENT for Features/Bugs/Decisions — not the item count (which comes
exclusively from the script above). Every prose statement must trace back to a SHA or an
item path from the script's JSON — no guessing.

**Source note (user directive 2026-08-23, see `skills/meta-observer/SKILL.md`
§ Source Doctrine):** the day's NARRATIVE — decisions, blockers, course changes —
comes from that day's session transcripts; `git log` only supplies the fact list of
commits, not the path that led there. This weighting applies to the prose under "Activity" and
"Research / Decisions" below; it changes nothing about the counting
mechanism (the script, `items_total`).

1. **Commit messages** (context, not a count source):
   ```bash
   yesterday=$(date -v-1d +%Y-%m-%d)
   # Additional search roots come from the environment (IMP-219, corrected
   # 2026-09-25 — previously a fixed directory depth between the workshop and
   # a parent level, which was an assumption about one machine's folder
   # structure baked into versioned code). Optional, ":"-separated
   # variable CLAUDE_EXTRA_SEARCH_ROOTS (see templates/env.local.sh.template).
   # If missing, ONLY the two $HOME roots are searched — the loop
   # below WARNs per missing root regardless and keeps working with the
   # roots present (see "Failure modes"), no logic change.
   [ -n "${CLAUDE_EXTRA_SEARCH_ROOTS:-}" ] || { [ -f "$HOME/.claude/env.local.sh" ] && . "$HOME/.claude/env.local.sh"; }
   ROOTS=("$HOME/Cowork" "$HOME/.claude")
   if [ -n "${CLAUDE_EXTRA_SEARCH_ROOTS:-}" ]; then
     IFS=':' read -ra EXTRA_ROOTS <<< "$CLAUDE_EXTRA_SEARCH_ROOTS"
     ROOTS+=("${EXTRA_ROOTS[@]}")
   fi
   for r in "${ROOTS[@]}"; do
     [ -d "$r" ] || { echo "WARN: root missing (drive unmounted?): $r" >&2; continue; }
     find "$r" -maxdepth 5 -type d -name .git -not -path '*/node_modules/*' 2>/dev/null
   done | while read -r gitdir; do
     repo=$(dirname "$gitdir"); email=$(git -C "$repo" config user.email)
     git -C "$repo" log --all --author="$email" \
         --pretty=tformat:'%H%x09%ad%x09%cd%x09%s' --date=format:'%Y-%m-%d' \
       | awk -F'\t' -v d="$yesterday" '$2==d || $3==d { printf "%s\t%s\n", substr($1,1,9), $4 }'
   done | awk -F'\t' '!seen[$1]++'   # SHA dedupe, see footnote
   ```
   *Footnote — four real failures, hence written this way:* roots instead of deriving
   from `~/.claude/projects/` directory names (the encoding lossily collapses "/" and "_"
   into "-"); `--all` instead of the current branch (otherwise missed commits on
   `claude/*` worktree branches); author-date OR committer-date (a plain
   `--since/--until` filter on committer-date misses commits after a nightly
   rebase); SHA dedupe (two clones of the same remote — e.g.
   `COWORK/proj-6964a0` and `$HOME/.claude` — each emit every commit
   twice; observed for real on 2026-07-17: 2 commits appeared as 4 lines).
2. **Signals:** `~/.claude/global-observation/signals.jsonl` (current) +
   `~/.claude/global-observation/archives/signals-<yesterday>.jsonl.gz` (rotated) —
   entries with `date == $yesterday`. *The old path `~/.claude/signals.jsonl` was the
   third original defect: the file does not exist there, silently returned 0 hits, and was
   wrongly declared "rotated away".*
3. **Memory updates:** verify positively by CONTENT, never by mtime (IMP-195 — file mtime under
   `~/.claude/projects/` is demonstrably not an activity signal; an unidentified
   process touches files in this tree without changing their content — 99 of 603
   transcript files in the 2026-09-09 run carried exactly `10:30` as mtime with
   week-old content. Same pattern as `logbook-count.sh` § S1a, "never mtime").
   For each file under `~/.claude/projects/$(echo "$HOME" | tr '/' '-')/memory/*.md`
   (Claude Code's own directory encoding: every `/` in the cwd path becomes `-` —
   for a session with cwd `$HOME` this yields exactly this folder name, IMP-219:
   no hardcoded username anymore), check the frontmatter field `modified:` against
   `$yesterday`:
   ```bash
   HOME_PROJECT_DIR="$(echo "$HOME" | tr '/' '-')"
   grep -l "modified: ${yesterday}" ~/.claude/projects/${HOME_PROJECT_DIR}/memory/*.md 2>/dev/null
   ```
   Not every memory file carries `modified:` in its frontmatter (older files lack the
   field entirely). A file without this field is a PROSE SOURCE WITHOUT A DATE
   RECORD — it may be cited, but not claimed as "changed yesterday"; mtime does not
   substitute for the missing record.

   **Knowledge-library contract (2026-10-09, `docs/OBSIDIAN.md` § Contract v3):** the
   logbook entry lists every memory note identified here under a heading
   `### Memory notes`, one per line, as a backtick path in the exact form
   `~/.claude/projects/<folder>/memory/<file>.md` (write `### Memory notes: none` when
   nothing qualifies — the heading is mandatory either way, so a missing list is
   visible). The knowledge mirror rewrites that path form into a link to the mirrored
   note, which turns the day's logbook into a graph edge into the note instead of
   prose about it. For this list scan ALL project folders
   (`~/.claude/projects/*/memory/*.md`) with the same content-based `modified:` test —
   the `$HOME` folder above is only the one a `cwd=$HOME` session writes to.
4. **Session metrics:** `~/.claude/session-env/*` from yesterday

## Categorization
Only from evidenced facts (commit message, item path, transcript title) — no
embellishing:
- Features Shipped
- Bugs Fixed
- Refactors / Cleanup
- Research / Decisions (with justification)
- Blockers Encountered
- Plans for Today

## Outputs

### A) Local Markdown logbook
Path: `~/.claude/logbook/YYYY-MM-DD.md` (YYYY-MM-DD = yesterday)

**Hardcoded on purpose (2026-07-18) — do not reintroduce an APP-SPECIFIC variable
here.** The old path read `${LOGBOOK_DIR}`, never set in `settings.json`/
`settings.local.json`. Unset, it expanded to empty → the path became
`/YYYY-MM-DD.md` (filesystem root). Runs silently repaired themselves by inferring the
directory from an earlier line in `daily-docs-log.jsonl` — a
silent fallback (forbidden by `rules/fail-loud.md`) that masked the unset bug for
weeks. `settings.local.json` would NOT be a durable solution (gitignored,
`*.local.json`) — the path is machine-stable and not secret, it belongs in the
spec itself. `$HOME` (IMP-219, instead of a literal user path) does NOT fall
into the same danger class as the old `${LOGBOOK_DIR}`: `$HOME` is not an
app-specific configuration variable that first needs wiring somewhere
— every process (login shell, launchd) gets it set by the operating system, and
the pre-flight guard below checks `-d` on the result anyway before writing.

**Pre-flight guard — fail loud, no workaround:**
```bash
LOGBOOK_DIR_RESOLVED="$HOME/.claude/logbook"
[ -n "$LOGBOOK_DIR_RESOLVED" ] && [ -d "$LOGBOOK_DIR_RESOLVED" ] || {
  echo "FAIL: logbook dir empty or missing: '${LOGBOOK_DIR_RESOLVED:-<empty>}'" >&2
  exit 1
}
```
If the guard trips: §C line `"status":"fail"` + `"reason"` with the unresolved path,
then stop. NEVER: create the directory, infer the path from earlier log lines, write to
`/`.

**Output language (`CLAUDE_DAILY_DOCS_LANG`, see `templates/env.local.sh.template`):**
this is the ONLY language-switchable surface in this routine — the prompt above and
the script contracts stay English regardless. Read the variable the same way as
`CLAUDE_LOGBOOK_NOTION_PAGE_ID` below (`[ -n "${CLAUDE_DAILY_DOCS_LANG:-}" ] || { [ -f
"$HOME/.claude/env.local.sh" ] && . "$HOME/.claude/env.local.sh"; }`). `CLAUDE_DAILY_DOCS_LANG`
unset or `en` → use the **English** heading set below. `CLAUDE_DAILY_DOCS_LANG=de` →
use the **German** heading set instead, verbatim. The JSON field names you copy
values from (`items_total`, `quellen_epochen`, `vcs_operationen`, `nicht_erfassbar`,
`sources`, …) never change — only the section headings and static prose around them do.
The §B Notion page always mirrors whichever heading set §A used for that day.

Format (English, default):
```markdown
# YYYY-MM-DD — Daily Logbook

## Count Status
- items_total: N — count_basis: files_touched_v3 — evidence_tier: T (reason: …) — status: OK|DEGRADED
- quellen_epochen: [verbatim from the script JSON]
- sources: [certificates verbatim from the script JSON]

## VCS Operations
[own paragraph, NEVER counted into `items_total` — e.g. "3 merges, 40 files
materialized, of which 13 exclusively merge-derived and not
included in items_total"; if 0 operations: "none"]

## Summary
[2-3 sentences]

## Activity
### Features Shipped
### Bugs Fixed
### Refactors / Cleanup
### Research / Decisions
### Blockers

## Not Capturable For This Day
- [verbatim from `nicht_erfassbar[]`; never leave empty — even a complete day
  has this section]

## Plans for Today
```

Format (German, only when `CLAUDE_DAILY_DOCS_LANG=de`):
```markdown
# YYYY-MM-DD — Daily Logbook

## Zähl-Status
- items_total: N — count_basis: files_touched_v3 — evidence_tier: T (Grund: …) — status: OK|DEGRADED
- quellen_epochen: [wörtlich aus dem Skript-JSON]
- sources: [Zertifikate wörtlich aus dem Skript-JSON]

## VCS-Operationen
[eigener Absatz, NIE in `items_total` eingerechnet — z.B. "3 Merges, 40 Dateien
materialisiert, davon 13 ausschliesslich merge-hergeleitet und nicht in items_total
enthalten"; bei 0 Operationen: "keine"]

## Summary
[2-3 Sätze]

## Activity
### Features Shipped
### Bugs Fixed
### Refactors / Cleanup
### Research / Decisions
### Blockers

## Für diesen Tag nicht erfassbar
- [wörtlich aus `nicht_erfassbar[]`; nie leer lassen — auch ein vollständiger Tag
  hat diese Sektion]

## Plans for Today
```

### B) Notion sync
- Parent page: `${CLAUDE_LOGBOOK_NOTION_PAGE_ID}` (see `~/.claude/env.local.sh`,
  template `templates/env.local.sh.template`) — the "📔 Claude Code Logbook" page.

**Hardcoded on purpose (2026-08-04), from the environment since IMP-219 (2026-09-25).**
The same lesson as the logbook path in §A, just learned one round later: the value
used to sit as `${NOTION_PARENT_PAGE_ID}` in `~/.claude/settings.local.json` — a file
Claude Code does **not read** at the user level (the local settings tier exists
only per project). The variable was therefore never set, the Notion step silently
failed every day, and the run reported `status:partial`. The ledger recorded the item on
2026-07-03 as "RESOLUTION: set in settings.local.json" — it wasn't resolved, just
made invisible. The value is machine-stable and **not a credential** (access
comes from the Notion login, not from the page id) — it therefore sat
directly in this spec until IMP-219. **Why this isn't the same mistake now:**
`~/.claude/env.local.sh` is not a Claude Code configuration tier that the
engine itself reads (the way `settings.local.json` would be) — it's an ordinary
shell file that the EXECUTING AGENT reads itself via `source`/`.` in the Bash tool
(pre-flight guard below); the engine-doesn't-read-the-user-tier mechanism that
doomed the original attempt does not apply here.

**Pre-flight guard — fail loud, no workaround:**
```bash
[ -n "${CLAUDE_LOGBOOK_NOTION_PAGE_ID:-}" ] || { [ -f "$HOME/.claude/env.local.sh" ] && . "$HOME/.claude/env.local.sh"; }
NOTION_PARENT_RESOLVED="${CLAUDE_LOGBOOK_NOTION_PAGE_ID:-}"
[ -n "$NOTION_PARENT_RESOLVED" ] || {
  echo "FAIL: CLAUDE_LOGBOOK_NOTION_PAGE_ID not configured (see templates/env.local.sh.template)" >&2
  exit 1
}
```
If the guard trips, or the Notion call fails: §C line `"status":"partial"`
**with** `"reason"`. NEVER: silently skip the step — that is exactly what masked the
failure for weeks (`rules/fail-loud.md`).
- **IDEMPOTENT (2026-07-03):** first `notion-fetch` on the parent, check whether a
  sub-page named `YYYY-MM-DD` already exists (a legacy routine, trigger
  `<routine-trigger-id>`, may still create some at 07:00, until the user
  deletes it under claude.ai/code/routines). If it exists: UPDATE
  (`notion-update-page`) — never create a duplicate sibling. Only create anew
  when absent.
- Content = the same markdown from §A (same language as §A used for that day).
- Tools: `notion-create-pages` / `notion-update-page`.

### C) Run log — two-phase, ONE line per date

Target: `~/.claude/global-observation/daily-docs-log.jsonl`.
**The line is NEVER hand-written or appended via `echo >>`.**
Exclusively via `bin/run-log.sh` — it builds the number and certificate fields
via `jq` directly from `logbook-count.sh`'s `count.json`, cutting off the
historical error source "hand-typed number" (real: "85 commits" instead of 83).

**Phase 1 — `start`, already done at the very top of the run** (see "Run order"):
writes `{"date":…,"ts":…,"status":"partial","phase":"started","reason":…}`.

**Phase 2 — after §A and §B:**
```bash
bash ~/.claude/scheduled-tasks/daily-docs/bin/run-log.sh finish "$yesterday" \
  --count-json "$J" \
  --logbook "$HOME/.claude/logbook/$yesterday.md" \
  --notion-page-id "<id>" --notion-modus "<new_subpage|updated_existing_subpage>"
```
On a script ABORT instead of `finish`:
```bash
bash ~/.claude/scheduled-tasks/daily-docs/bin/run-log.sh fail "$yesterday" --reason "<ABORT message verbatim>"
```
Notion failed, but the logbook was written: `finish … --status partial --reason "<reason>"`.

Resulting line (field names MANDATORY — `items` does not exist, `aera` has been replaced by
`quellen_epochen`; both wrongly appeared in this template until 2026-08-01):
```json
{"date":"YYYY-MM-DD","ts":<unix>,"status":"ok|partial|fail","logbook_path":"…","notion_page_id":"…","items_total":N,"count_basis":"files_touched_v3","evidence_tier":T,"evidence_tier_grund":"…","quellen_epochen":{…},"sources":{…},"vcs_operationen":N,"git_ambiguous_nicht_gezaehlt":N,"items_sha256":"…","notion_modus":"…","reason":"…"}
```

The script enforces (exit ≠ 0, no silent repair):
- `reason` MANDATORY on `partial`/`fail`, omitted on `ok`.
- `fail` lines contain **no** number fields — not as `null`, but absent entirely
  (fail-loud contract).
- `finish` requires an existing logbook file — `status:"ok"` without an artifact is
  not allowed; and a `count.json` whose `day` matches the date.
- Date ordering and uniqueness are preserved (gap detection depends on it);
  installation is atomic via temp + `mv`, fully verified beforehand.
- If the `start` line is missing, `finish` is still written, but marked with
  `"start_zeile_fehlte": true` — the process violation stays visible.

**Self-check** (structure, duplicates, open partial runs):
```bash
bash ~/.claude/scheduled-tasks/daily-docs/bin/run-log.sh check
```
A `status:"partial"` line that stays standing is exactly the abort case — it
needs to be followed up on, not cleaned away.

## Failure modes
- **Run aborts mid-way** (interrupt, crash, context end, token budget,
  scheduler timeout): the `status:"partial"` line from `run-log.sh start` stays
  standing. That is the INTENDED end state — a visible partial run. Do not
  clean it up, do not raise it to `ok` without §A and §B actually existing.
  Follow-up: complete the missing steps, then `finish`. `run-log.sh check`
  lists all open partial runs.
- **Script ABORT:** see the fail-loud contract above — `status:"fail"`, `reason` =
  the ABORT message verbatim, no `items_total` field, no improvised number.
- **Logbook dir empty/missing:** `status:"fail"` with an explicit `reason` (§A
  pre-flight guard). Never infer from old log lines, never `mkdir`, never write to `/`.
- **Root for the prose git log missing** (external volume not mounted): log a `WARN`,
  keep working with the roots present, name the missing root explicitly under "Not
  Capturable For This Day". This does NOT change the `status` — that depends on the
  script exit, not on prose completeness.
- **Quiet day** (script correctly reports `items_total`, even low or 0): still
  write and sync a complete entry. Never skip.
- **Notion auth error:** write the markdown locally, log `status:"partial"`,
  return.
- **Notion conflict** (page exists, version diverges): fetch the current state,
  merge, push. If the merge is unclear: write locally + flag for manual review.
