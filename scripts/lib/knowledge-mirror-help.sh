#!/usr/bin/env bash
# shellcheck shell=bash
# knowledge-mirror-help.sh - the --help / usage text of scripts/knowledge-mirror.sh. Sourced on demand
# by that script's usage(), never executed. Kept out of the main script so it stays under the line limit.

km_usage() {
  cat <<'EOF'
Usage: bash knowledge-mirror.sh [--dry-run | --check-links] [--no-v3-links] [--help]

Copies an allowlisted set of distilled-knowledge Markdown files from ~/.claude
into $CLAUDE_KNOWLEDGE_DIR (<K>) so <K> can be opened in Obsidian. The framework
never reads <K>; Obsidian never writes into ~/.claude.

Configuration: CLAUDE_KNOWLEDGE_DIR, an absolute path with no default. If unset,
~/.claude/env.local.sh is sourced when it exists. Optional CLAUDE_BAUHOF_ROOT
(the workshop) is only used for the refusal check.

<K> must be outside ~/.claude and the workshop (checked: refused if <K> equals,
sits inside, or contains either). <K> must NOT be under iCloud Drive, Dropbox,
Obsidian Sync or any other synced folder: the mirror holds memory files and
private project names, and a sync service would upload them. This script does
NOT check that; keeping <K> out of synced folders is your responsibility.

Mirrored (read from ~/.claude, never written):
  logbook/*.md                  -> <K>/mirror/logbook/
  projects/*/memory/*.md        -> <K>/mirror/memory/<project-dir>/
  plans/meta-proposal-*.md      -> <K>/mirror/plans/
  rules/*.md (no *.local.md)    -> <K>/mirror/rules/
  docs/archive/rules-evidence/*.md -> <K>/mirror/evidence/
  docs/adr/*.md                 -> <K>/mirror/adr/
  docs/*.md (top level only)    -> <K>/mirror/docs/
  CONTEXT.md                    -> <K>/mirror/docs/CONTEXT.md
  global-observation/improvement-ledger.json -> <K>/mirror/ledger.md (index) and
                                   <K>/mirror/ledger/<ID>.md (one note per IMP id)
Hard excludes, applied after globbing: *.local.md, /vault/ paths, *.jsonl.

Graph structure, generated into the copies (sources untouched): every .md gets the
frontmatter keys kind: (memory|rule|evidence|adr|doc|logbook|plan|imp) and origin:
(source path, $HOME shown as ~, a double-quoted YAML scalar); existing source keys
stay byte-identical. A source that itself owns one of the generated keys (kind,
origin, dated, dated_from, origin_session) keeps its own: the generated key is
omitted from the copy (one key, valid YAML) and the run prints "warning: source owns
a generated key" naming the copy. A source owning dated also gets no dated_from.
Rules get an "## Evidence" link to their evidence twin; backtick-quoted repo paths
whose target is in the mirror become [[wikilinks]] (any file name); a bare [[name]],
[[name#h]] or [[name|alias]] of a rule becomes [[rules/name...]]. Fenced code (closed
only by a fence of at least as many backticks) and inline code spans are never
touched, nor counted by --check-links. A copy that ends inside an unclosed fence gets
a closing fence of the same length before "## Evidence" / "## Mentions" are appended.
A ledger note (kind: imp) has id, ledger_status (the ledger vocabulary: implemented,
proposed, ...; the key is not "status", which is the authored curation key), category,
riskLevel, measured (true only for a non-null, non-false, non-empty
verification.measured), proposedAt, implementedAt, origin; category, riskLevel,
proposedAt and implementedAt are omitted when null or missing. It links the leading
path of each filesModified/filesCreated entry and keeps the rest of the entry.
ledger.md (the index) carries kind: imp and origin: too.

v3 (freshness, link hygiene, graph). Source copies also get dated: (valid_from when present, else
the first ISO date in a frontmatter value other than description, backfilled, dated, dated_from,
origin_session, kind, origin and originSessionId; modified: counts. Then the body, the description,
the source mtime in UTC), dated_from: (frontmatter|body|description|mtime) and, for a memory note with
a session id, origin_session: (present|missing). The session id is the frontmatter key originSessionId,
else the first UUID in the frontmatter; never one in the body. ~/.claude/projects/*/<id>.jsonl is only
tested for existence, never read. In memory copies a bare [[name]] resolves in its own project folder
first (case and -/_ folded): a unique match becomes [[memory/<proj>/<file>]], a non-unique one stays
bare (it never falls through to a same-named rule; --check-links reports it as ambiguous);
MEMORY.md [title](file.md) becomes [[memory/<proj>/file|title]]. In logbook and plan copies a
backtick path projects/<f>/memory/<x>.md (with or without ~/.claude/) becomes [[memory/<f>/<x>]]
when that copy exists, else --check-links reports it.
IMP, rule, ADR, evidence, doc and memory copies end with "## Mentions" (up to 10 linking notes, then
"and N more"; IMP notes add "(same-day)" logbook days). IMP notes drop empty sections and the
proposed-entry verification boilerplate. mirror/graph/nodes.tsv (path kind status dated description) and
edges.tsv (src dst via: wikilink|mdlink|evidence|mentions|same-day, one row per resolved link) are written
last, outside the hash and stale logic; the status of an IMP node is active. --no-v3-links switches the
link features off (and keeps the boilerplate, which carries a link): the v2 edge set; the regression
suite runs its v2 cases with it.

Each copy gets one HTML provenance comment directly after the closing "---" of
its frontmatter. <K>/mirror/.state/hashes.tsv records each written copy's
sha256; a later run exits 3 and overwrites nothing if any recorded copy was
edited by hand. Your own notes go in <K>/notes/ (created, never touched).
Unchanged copies are not rewritten; stale copies are listed (stale:), not deleted.
A failed write of a copy, of hashes.tsv or of graph/*.tsv exits 1 with an error line.
Ledger notes and ledger.md carry no timestamp (idempotent).

Refusals (exit 1, "knowledge-mirror: refuse:"): target unset/empty, not absolute,
equal to, inside or containing ~/.claude or CLAUDE_BAUHOF_ROOT, or named "vault";
any symlink under <K>/mirror.
--dry-run prints "<target> <- <source>" per file, then TOTAL and CHANGED, and
writes nothing. A real run prints TOTAL, CHANGED and the LINKS line.
--check-links is a read-only report on <K>/mirror (no copying, no writes): it
prints "LINKS total=<n> resolved=<n> ambiguous=<n> dangling=<n>" (markdown links counted; frontmatter
lines are not scanned) and up to 30 "dangling: <token> cause=<slug|missing|excluded-by-design|template> in
<path>" and 30 "ambiguous:" lines. Exit 0 whatever it finds (it is a report);
exit 1 when the library is unavailable: target refusal, no <K>/mirror, a mirror without
copies, no graph library. A missing or empty mirror is an error, never an empty healthy
graph. jq and shasum are not needed; symlinks are not followed (find -type f), so none is refused.
Exit codes: 0 ok, 1 refusal or error, 2 bad usage, 3 hand-edited copy.
EOF
}
