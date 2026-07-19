---
name: daily-docs
description: Daily logbook entry — aggregates yesterday's signals, git activity, and memory updates into a Markdown logbook and syncs to Notion.
---

Run the documentation-agent in Mode B (Daily-Docs Routine).

## Date window
Process activity from yesterday (00:00 to 23:59 local).
Use: `yesterday=$(date -v-1d +%Y-%m-%d)`

## Data sources
1. **Signals:** `~/.claude/signals.jsonl` — filter entries with date == $yesterday
2. **Git activity** — discover repos on the **real filesystem**, then list *yesterday's*
   commits by **author-date across all branches** (see WHY below for the three failure
   modes this replaces):

   ```bash
   yesterday=$(date -v-1d +%Y-%m-%d)

   # Search roots = where the user's repos actually live. Configure via the
   # CLAUDE_DAILY_DOCS_ROOTS env var (colon-separated, like $PATH); defaults to
   # $HOME if unset. Do NOT derive repo paths from ~/.claude/projects/ dir-names:
   # that encoding collapses both "/" and "_" to "-", so decoding is lossy
   # (e.g. a dir named "…-PHASE-II-MyApp" is really ".../PHASE_II/MyApp").
   IFS=: read -ra ROOTS <<< "${CLAUDE_DAILY_DOCS_ROOTS:-$HOME}"
   for r in "${ROOTS[@]}"; do
     [ -d "$r" ] || { echo "WARN: search root missing (drive unmounted?): $r" >&2; continue; }
     find "$r" -maxdepth 5 -type d -name .git -not -path '*/node_modules/*' 2>/dev/null
   done | while read -r gitdir; do
     repo=$(dirname "$gitdir")
     email=$(git -C "$repo" config user.email)
     # author-date OR committer-date == yesterday, ALL branches, authored by me.
     # git log dedupes by commit, so each appears once; tformat: keeps a trailing
     # newline after every record so repos don't run together when concatenated.
     git -C "$repo" log --all --author="$email" \
         --pretty=tformat:'%H%x09%ad%x09%cd%x09%s' --date=format:'%Y-%m-%d' \
       | awk -F'\t' -v d="$yesterday" -v repo="$repo" \
           '$2==d || $3==d { printf "%s\t%s\t%s\n", repo, substr($1,1,9), $4 }'
   done
   ```

   **WHY author-date + `--all` + filesystem discovery** — all three were real failure
   modes on 2026-07-11..13 (runs "reconstructed from memory"):
   - **Filesystem discovery:** narrow/hardcoded root lists miss real work trees entirely
     (e.g. secondary drives or non-default project locations) and can treat Claude
     session-transcript dirs as repos. This was the dominant blind spot in an earlier
     version of this routine — hence the configurable `CLAUDE_DAILY_DOCS_ROOTS` above.
   - **`--all`:** a scan limited to the current branch misses commits on sibling
     branches (e.g. `claude/*` worktree branches).
   - **author-date (+ committer-date as a secondary OR):** `--since/--until` filter by
     **committer-date**, which a rebase / `git branch -f` resets to the rebase day while
     preserving author-date → a day followed by an overnight rebase can scan as 0 commits.
3. **Memory updates:** mtime > yesterday in `~/.claude/projects/<slugified-home-path>/memory/`
   (the dir name is `$HOME` with `/` and `_` collapsed to `-`, per Claude Code's own
   session-transcript naming — derive it, don't hardcode it)
4. **Session metrics:** `~/.claude/session-env/*` from yesterday

## Categorize
- Features shipped
- Bugs fixed
- Refactors / cleanup
- Research / decisions made
- Blockers encountered
- Plans for today

## Outputs
### A) Local Markdown logbook
Path: `${LOGBOOK_DIR}/YYYY-MM-DD.md` (where YYYY-MM-DD = yesterday)

Format:
```markdown
# YYYY-MM-DD — Daily Logbook

## Summary
[2-3 sentence overview of the day]

## Activity

### Features Shipped
- ...

### Bugs Fixed
- ...

### Refactors / Cleanup
- ...

### Research / Decisions
- ...

### Blockers
- ...

## Plans for Today
- ...
```

### B) Notion sync
- Parent page: `${NOTION_PARENT_PAGE_ID}` (set in settings.local.json env since 2026-07-03
  — the "📔 Claude Code Logbuch" page; before that every run was status:partial)
- **IDEMPOTENT (2026-07-03):** first `notion-fetch` the parent and check whether a
  sub-page named `YYYY-MM-DD` ALREADY exists (a legacy cloud routine, trigger
  `trig_01QJzQsDzg42p4KcDD1zyvvF`, may still create these at ~07:00 until the user
  deletes it at claude.ai/code/routines). If it exists: UPDATE/append that page
  (notion-update-page) — never create a duplicate sibling. Only create when absent.
- Content = same Markdown
- Use the available Notion MCP tools (notion-create-pages / notion-update-page)

### C) Run log
Append one JSONL row to `~/.claude/global-observation/daily-docs-log.jsonl`:
```json
{"date": "YYYY-MM-DD", "ts": <unix>, "status": "ok|partial|fail", "logbook_path": "...", "notion_page_id": "...", "items_processed": N}
```

## Failure modes
- Search root missing (external drive unmounted): log `WARN` per §Data-sources #2, set
  run status to `partial`, and continue with the roots that ARE present. Do NOT silently
  skip — a missing NvME drive would otherwise look identical to a genuinely quiet day.
- Quiet day (no activity): write a brief "quiet day" entry, sync anyway. Do NOT skip.
- Notion auth failure: write Markdown locally, log "partial", return.
- Notion conflict on existing page: fetch current, merge, push. If unclear, write local + flag for review.