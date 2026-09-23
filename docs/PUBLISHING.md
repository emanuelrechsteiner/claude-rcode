<!--
Status: ACTIVE
Last Updated: 2026-08-06
Purpose: Publish-pipeline architecture, runbook, and PR-governance model for the private→public repo mirror.
-->

# Publishing — architecture & runbook

This document explains how `claude-code-config` (private) and `claude-rcode`
(public) relate, how to actually run a publish, how to handle a public PR,
how to handle an accidental leak, and the branch-protection settings the
public repo's maintainer must configure once.

## Architecture

- **`claude-code-config`** (this repo, private, `github.com/<owner>/<private-source-repo> (placeholder — this repo is never public)`)
  is the **single source of truth**. It contains real names, real machine
  paths, and personal settings — it is never meant to be public.
- **`claude-rcode`** (`github.com/emanuelrechsteiner/claude-rcode`) is a
  **generated artifact**. It has no shared git history with the private
  repo — every publish produces exactly **one squashed release commit**.
  It is installable by anyone and is **never hand-edited**.
- Data flows **one way**, private → public, via `scripts/publish.sh`. There
  is no path in the other direction except the explicit back-port flow
  below (`scripts/backport-pr.sh`), which is a human-reviewed, local-first
  operation — not an automated sync.

```
 claude-code-config (private)              claude-rcode (public)
 ─────────────────────────────             ──────────────────────
 git history: full, real                   git history: one commit
 PII: real names/paths/settings            PII: scrubbed / placeholders
 source of truth                           generated artifact
        │
        │ scripts/publish.sh
        │  1. git archive HEAD
        │  2. apply publish-manifest.txt exclusions
        │  3. run publish-transforms.d/*.sh
        │  4. scrub-check.sh on staging (must be CLEAN)
        │  5. rsync staging → public dir, commit
        ▼
   (human reviews commit, then pushes)
```

## How to publish

Prerequisites: a local clone of `claude-rcode` somewhere on disk, `rsync`,
`jq`, a clean private working tree.

```bash
cd ~/path/to/claude-code-config    # this repo

# 1. Dry run first — always. Builds the staging tree, runs scrub-check
#    against it, and prints a file manifest + diff summary. Publishes
#    NOTHING.
scripts/publish.sh --dry-run --public-dir ~/path/to/claude-rcode

# 2. Read the output. If scrub-check reported findings, the dry run
#    already aborted — see "Handling a scrub-check finding" below.
#    If it's clean, review the manifest/diff summary for anything
#    surprising (a file you didn't expect to ship, or one missing).

# 3. Publish for real.
scripts/publish.sh --publish --public-dir ~/path/to/claude-rcode --version v1.5.0

# 4. The script committed locally in the public dir but did NOT push.
#    Review the commit, then push + tag yourself:
git -C ~/path/to/claude-rcode log -1 -p     # review
git -C ~/path/to/claude-rcode push origin HEAD
git -C ~/path/to/claude-rcode tag v1.5.0
git -C ~/path/to/claude-rcode push origin v1.5.0

# 5. Publish a GitHub Release from the tag (release notes go here, not in
#    the public CHANGELOG.md — see scripts/publish-transforms.d/20-changelog.sh).
```

### Handling a scrub-check finding during publish

`scripts/publish.sh` runs `scripts/scrub-check.sh` against the **staging
tree** (after exclusions and transforms) and aborts if anything is found.
For each finding:

1. **Prefer excluding the file** — add a line to `publish-manifest.txt`
   with a comment explaining why. This is the default; it carries no
   drift risk.
2. **Only transform if the file's content is genuinely useful publicly**
   and the PII is a small, precisely-matchable substring — add or extend a
   rule in `publish-transforms.d/30-placeholder-scan.sh`.
3. **Allowlist only for true false positives**, and only in the **private**
   repo's `scripts/scrub-allowlist.txt` (never edit an allowlist inside the
   staging tree — there isn't one; the staging tree inherits whatever the
   private repo ships).

Re-run `scripts/publish.sh --dry-run ...` until scrub-check reports clean.

## Pseudonymization

`publish-manifest.txt` and `publish-transforms.d/30-placeholder-scan.sh`
handle the *stable, small* set of PII (machine username, volume name,
retired identities, a couple of project codenames baked into public-facing
prose). Real project and client names accumulate over time as evidence in
rule prose, ledger history, and agent transcripts — a much longer-tailed
category that would defeat its own purpose if hardcoded into a tracked
transform script (the list of private names would itself ship in a public
file).

Instead:

- **`publish-pseudonyms.local.tsv`** (repo root, git-ignored, never
  versioned, never published) maps each real private name to a neutral
  public placeholder — one `real name<TAB>placeholder` pair per line. This
  file lives only on the maintainer's machine. If it does not exist,
  create it yourself; there is no tracked template because a template
  would need a real example to be useful, and a real example is exactly
  what must never be committed.
- **`publish-transforms.d/50-pseudonymize.sh`** reads that file and
  replaces every real name with its placeholder across the staging tree,
  longest name first (so a short name that happens to be a substring of a
  longer one never corrupts an already-applied longer replacement). A
  missing list file is a hard, fatal error for this transform — publishing
  without pseudonymization must never happen silently.
- **`scripts/scrub-check.sh --require-pseudonym-list`** re-reads the same
  file and blocks the staging tree if any real name is still present after
  the transform ran — this is the gate that actually enforces the
  replacement, not just performs it. `scripts/publish.sh`'s Step 5 always
  passes this switch. Without the switch (the default — this is what
  public CI runs, since a contributor's checkout structurally has no
  private list), a missing list produces a loud "skipped" line rather than
  either a silent no-op or a spurious failure on a machine that was never
  supposed to have the file.

To add a new entry: find the real name in an actual scrub-check finding
(never guess), append a line to `publish-pseudonyms.local.tsv` with a
short, stable, readable placeholder (e.g. "Projekt A"), and re-run
`scripts/publish.sh --dry-run ...`.

## How to handle a public PR (back-port flow)

The public repo's `pr-guard.yml` workflow always fails PRs there — see that
file's comments for why. The maintainer's actual acceptance path:

```bash
cd ~/path/to/claude-code-config

# 1. Fetch, check, and apply the PR's diff onto a new local branch:
scripts/backport-pr.sh 42

# 2. Review the resulting branch (backport/pr-42):
git diff main..backport/pr-42

# 3. Run this repo's normal checks on that branch, then merge to trunk:
git checkout main
git merge --no-ff backport/pr-42

# 4. Re-publish so the fix reaches the public repo (see "How to publish"
#    above).

# 5. Close the original PR with a thank-you comment (backport-pr.sh prints
#    a ready-to-edit template + the exact gh commands — both are WRITES
#    against GitHub that the script deliberately does NOT run for you).
```

If `git apply --3way --check` reports conflicts, `backport-pr.sh` aborts
before creating any branch and explains why (usually: the private tree's
paths/identifiers differ from the scrubbed public view the PR was written
against). Options in that case: re-derive the equivalent private-tree edit
by hand, ask the contributor to rebase, or apply with `git apply --reject`
and resolve the `.rej` files manually.

## Handling an accidental leak

If a secret or PII fragment ends up in a published commit on `claude-rcode`:

1. **Rotate first, always** — any leaked credential must be rotated at the
   source (API key, token, password) regardless of what happens to the git
   history. Treat it as compromised the moment it's pushed publicly.
2. **Regenerate the release, don't rewrite public history.** `claude-rcode`
   has no shared history with the private repo and is not something
   contributors fork long-lived branches from in the normal case, but a
   `git push --force` / history rewrite on a *public* repo is still an
   ESCALATE-band operation (see the private repo's `agency-bands.md`) —
   it silently breaks any clone, fork, or CI cache that already has the
   old commit. Prefer: fix the leak at the source (exclude/transform), cut
   a new release commit via `scripts/publish.sh --publish`, and note in
   the new release's notes that the previous release contained a leaked
   value that has been rotated.
3. **Only force-rewrite public history as a last resort**, with explicit
   human sign-off, understanding the blast radius above — never as a
   default response to a leak.
4. **Add a regression check.** If the leak is a pattern `scrub-check.sh`
   should have caught, add the pattern there. If it's a one-off file that
   should never have been in the manifest, add it to
   `publish-manifest.txt` with a comment describing the incident (date,
   what leaked, why the existing gates missed it).

## Branch protection the maintainer must set once (on `claude-rcode`)

In the public repo's GitHub settings → Branches → branch protection rule
for `main`:

- **Require status checks to pass before merging**, and require the
  `guard` job from `pr-guard.yml` specifically. This is what makes PRs
  structurally unmergeable through GitHub's UI — the workflow always
  fails that check.
- **Restrict who can push to matching branches** to the maintainer
  (and/or a bot identity used only by `scripts/publish.sh`'s human-run
  push step). No one else should have push access to `main`.
- Optionally: **require a pull request before merging** even for the
  maintainer's own pushes, if the maintainer wants an audit trail for
  every publish too (not required — `scripts/publish.sh` never pushes
  itself, so this is a matter of preference, not safety).

These settings are **not** something `scripts/publish.sh` can configure
remotely — GitHub branch protection is a one-time manual setup step on the
public repo itself.
