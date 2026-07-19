<!--
Status: DRAFT — pending user approval (IMP-084, metareview 2026-07-03)
Last Updated: 2026-07-03
Purpose: Retention + PII/confidentiality policy for the local observation corpus (transcripts, chat archives, file history, logbook)
-->

# Retention Policy — Observation Corpus

> **DRAFT — PENDING USER APPROVAL.** Nothing in this document is enforced by
> automation. There is **no deletion automation** attached to this policy and
> none may be built until the durations below are explicitly approved. Until
> approval, this document governs only the *manual* quarterly cleanup checklist
> at the bottom — every deletion in that checklist is an explicit y/n per
> `rules/agency-bands.md`.

## 1. Scope — what the corpus is

The observation corpus is the locally-accumulated conversational and telemetry
data under `~/.claude`. Sizes below are an **illustrative example measurement**
from one long-running installation — your own numbers will differ with usage
and are not tracked anywhere in this repo:

| Path | Contents | Example size | In git? |
|------|----------|------|---------|
| `projects/` | Full session transcripts (JSONL), one dir per project | several hundred MB at maturity | ❌ gitignored |
| `global-observation/chat-archives/` | Stop-hook chat archives (IndyDevDan pattern) | tens to low hundreds of MB | ❌ gitignored |
| `global-observation/` (rest) | signals.jsonl, session-metrics, agency/guard logs, historical-signals DB, archives/ | tens of MB | ⚠️ mixed — `archives/` + `chat-archives/` gitignored, several logs/JSONL tracked |
| `file-history/` | Per-edit file snapshots | a few MB | ❌ gitignored |
| `logbook/` | Daily logbook scaffolds | <1 MB | ❌ gitignored |
| `history.jsonl`, `stats-cache.json` | Prompt history / usage stats | small | ❌ gitignored |
| `plans/` | Meta-proposals, planning artifacts (may reference project internals) | small | ❌ gitignored |

## 2. Retention classes (DRAFT durations)

Durations are proposals — approve, adjust, or reject per row.

| Class | Paths | Keep for | Then |
|-------|-------|----------|------|
| **Session transcripts** | `projects/**/*.jsonl` | **12 months** from last modification | Manual review → delete, or archive to encrypted offline storage if a project is legally/contractually long-lived |
| **Chat archives** | `global-observation/chat-archives/` | **6 months** | Delete after confirming meta-observer no longer reads them (see IMP-082 — if they stay write-only, shorten to 3 months or disable the producer) |
| **Signals (live)** | `global-observation/signals.jsonl` | **30 days** (already automated: `scripts/rotate-signals.sh`, archive-first-then-trim) | Gzipped date shards in `archives/`, pruned at 30 days |
| **Session metrics / agency + guard logs** | `session-metrics.jsonl`, `excessive-agency.log`, `guard-overrides.log`, etc. | **12 months** (audit evidence for meta-reviews) | Truncate to last 12 months manually |
| **Historical aggregates** | `historical-signals-*.jsonl`, `historical-signals.db` | **Indefinite** — already de-identified aggregates | Rebuildable from transcripts while those exist |
| **File history** | `file-history/` | **90 days** | Delete (git is the real history) |
| **Logbook** | `logbook/` | **12 months** local | Source of truth is Notion (daily-docs routine); local copies are cache |
| **Plans / meta-proposals** | `plans/` | **Indefinite** local | Curate manually; never committed (gitignored) |

## 3. PII / secret scrubbing

Transcripts and chat archives contain, by nature: file paths, e-mail addresses,
client and project names, code from private repos, and occasionally pasted
secrets (the 2026-05-24 PAT-leak finding proves this is not hypothetical).

Rules:

1. **Before anything derived from the corpus is committed or shared** (rule
   files, meta-proposals intended for the public repo, CHANGELOG entries,
   pattern docs): scrub client names, e-mail addresses, absolute paths outside
   `~/.claude`, and any token-shaped string. Cite *paths and counts*, not raw
   transcript content.
2. **Secret patterns** follow `hooks/security-audit.sh` (github_pat_*, ghp_*,
   AKIA*, sk-*, AIza*, xox*). Anything matching these found inside the corpus
   is rotated first, then the containing transcript is purged — rotation before
   deletion, so the leak window is closed, not just hidden.
3. **Aggregation preferred over quotation**: meta-observer / memory-index
   outputs should carry statistics and pattern descriptions, not verbatim
   conversation excerpts, whenever the output can leave the machine.

## 4. NEVER committed (hard list)

These stay out of the git repo permanently — the repo is shared/public, the
corpus is not. Enforced by `.gitignore` (verify anchors quarterly, see IMP-073
for the unanchored-pattern lesson):

- `projects/` (transcripts)
- `global-observation/chat-archives/` and `global-observation/archives/`
- `history.jsonl`, `stats-cache.json`
- `file-history/`, `logbook/`, `plans/`
- `settings.local.json` (secret env block), `rules/identity.local.md`
- Any `*.bak*`, `backups/`, `shell-snapshots/`, `session-env/`

## 5. Cross-client confidentiality (multi-identity setup)

This machine operates under **multiple git identities / client contexts**
(mappings in `rules/identity.local.md`, gitignored — clients are deliberately
not named in this committed document). The corpus mixes transcripts from all
of them side by side under `projects/`. Consequences:

- **No cross-client leakage in deliverables.** Content, naming conventions,
  architecture details, or code patterns learned in one client's transcripts
  must never surface in another client's project output. Cross-project tools
  (memory-index, meta-observer, historical-signals) aggregate across that
  boundary by design — their outputs are **internal-to-this-machine only**
  unless scrubbed per §3.
- **Client-terminated = purge trigger.** When an engagement ends, that
  client's `projects/-…` directories and related chat archives are deleted at
  the next quarterly cleanup regardless of the 12-month default, unless a
  retention obligation says otherwise.
- **Transcripts are confidential work product.** Treat `projects/` with the
  same care as the client repos themselves: never uploaded, never shared,
  excluded from any future cloud-sync of `~/.claude`.

## 6. Quarterly cleanup checklist (manual — no automation)

Run alongside the quarterly `audit-config` routine. Every deletion gets an
explicit y/n; nothing here is scriptable-by-default until this policy is
approved.

- [ ] `du -sh ~/.claude/projects ~/.claude/global-observation ~/.claude/file-history` — record sizes, compare to previous quarter
- [ ] Identify `projects/` dirs past retention (12 months untouched) or belonging to ended engagements → propose deletion list → y/n → delete
- [ ] Same for `global-observation/chat-archives/` (6 months)
- [ ] Delete `file-history/` content older than 90 days (y/n)
- [ ] Verify `.gitignore` still covers everything in §4 (`git check-ignore -v` spot-checks; watch for unanchored patterns)
- [ ] `git -C ~/.claude grep -nE 'github_pat_|ghp_|AKIA|sk-[A-Za-z0-9]|AIza|xox'` over **tracked** files — must be empty
- [ ] Run `scripts/restore-drill.sh` — backup sufficiency, not just freshness (first real run still pending as of 2026-07-03)
- [ ] Run `scripts/config-drift-check.sh` — expect silence
- [ ] Note outcomes in the logbook / next meta-review input

## 7. Open questions (answer to move DRAFT → ACTIVE)

1. Approve/adjust the durations in §2 (esp. transcripts 12 mo, chat archives 6 mo)?
2. Encrypt long-lived archives (offline copy) or plain-delete at end of retention?
3. Chat archives: keep the producer hook, or disable it if IMP-082 concludes write-only?
4. Should ended-engagement purge (§5) be *earlier* than quarterly (e.g. within 30 days of termination)?
