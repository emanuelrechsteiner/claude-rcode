<!--
Status: ACTIVE
Last Updated: 2026-10-08
Purpose: Publish-pipeline architecture, runbook, and PR-governance model for the private→public repo mirror.
-->

# Publishing — architecture & runbook

> **Publishing is hard-disabled since 2026-08-12** (owner decision, private-layer protection): `scripts/publish.sh` exits at its `PUBLISH_DISABLED=1` line before doing anything. Re-enabling is a deliberate edit of that one line, never an environment override. Even when enabled, the script never pushes — it stages, transforms, scrub-checks, commits into the public dir and prints the `git push` command for a human to run. The runbook below describes the enabled state.

This document explains how `claude-code-config` (private) and `claude-rcode`
(public) relate, how to actually run a publish, how to handle a public PR,
how to handle an accidental leak, and the branch-protection settings the
public repo's maintainer must configure once.

## Architecture

- **`claude-code-config`** (this repo, private — the maintainer's private
  source repo) is the **single source of truth**. It contains real names,
  real machine paths, and personal settings — it is never meant to be
  public.
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

# 0. Release notes: add the version entry to public/CHANGELOG.md
#    (Keep a Changelog format; move items from [Unreleased], update the
#    compare links at the bottom) and commit it. The publish aborts if the
#    file is missing — scripts/publish-transforms.d/20-changelog.sh.

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

# 5. Optional: publish a GitHub Release from the tag, pasting the version's
#    section from CHANGELOG.md as its notes.
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

The vault (`scripts/vault/`, data at `${CLAUDE_VAULT_DIR:-~/.claude/vault}`,
gitignored, machine-local) is the **single source of truth** for every real
name, path, account, or identifier this repo's own tracked files must never
contain in plain text. One matcher (`scripts/vault/lib.sh`'s
`vault_matcher_run`) backs every consumer that touches this data: the
write-gate hook, pre-commit, `scripts/scrub-check.sh`, and the publish
transforms below — no second, independently-written matcher exists
anywhere in this pipeline (see `rules/testing-quality.md` "Verify Via the
Same Code Path" if you're tempted to add one).

- **`scripts/vault/vault.sh init`** builds the vault. `--import-legacy
  <tsv>` and `--from-registry <jsonl>` are one-time IMPORT sources (a
  historical pseudonym list, and this maintainer's project registry) — not
  a second enforcement mechanism that keeps running forever afterward.
  Both are idempotent: re-running `init` against the same sources adds
  nothing new. Add a term directly with `scripts/vault/vault.sh add <kind>
  <term> --group <g>`; `<kind>` is one of `project | account | path | user
  | volume | email | id | phrase`, and most kinds get a stable,
  non-reversible HMAC token for free (an explicit `--token` is required
  only for `id`/`phrase`, since those need a human-chosen, readable
  placeholder that varies per instance).
- **`scripts/vault/public-names.txt`** (tracked, NOT gitignored) is the
  short, explicit exception list: names the framework publishes ITSELF
  under (this repo's own public identity) and third-party product names
  the framework legitimately works with by that exact name (tool-name
  prefixes, standard folder names) — never vault terms, regardless of how
  they entered an import source. `vault.sh prune-public` removes any such
  name from an existing vault; every matcher consumer also filters them
  out at read time, so even a hand-edited `map.tsv` can't reintroduce one
  silently.
- **`publish-transforms.d/50-pseudonymize.sh`** tokenizes the ENTIRE
  staging tree in one pass, all vault kinds, longest-term-first, honoring
  `scripts/scrub-allowlist.txt` (below) exactly the way `check` does — the
  allowlist is the only exemption mechanism this transform has. A missing
  vault is a hard, fatal error: publishing without tokenization must never
  happen silently.
- **`scripts/scrub-check.sh --require-pseudonym-list`** re-runs `vault.sh
  check` against the staging tree and blocks it if any real vault term (or
  the vault's own private-layer markers, if that group is unexpectedly
  empty) is still present after the transform ran — this is the gate that
  actually enforces the replacement, not just performs it.
  `scripts/publish.sh`'s Step 5 always passes this switch. Without it (the
  default — what public CI runs, since a contributor's checkout
  structurally has no vault), a missing vault produces a loud "skipped"
  line rather than either a silent no-op or a spurious failure on a
  machine that was never supposed to have one.
- **`scripts/scrub-allowlist.txt`** (`path:line:signature` triples) is the
  ONE exemption mechanism across every matcher consumer — for example the
  two intentional authorship-attribution lines (the MIT license holder,
  one README credit line) that must keep a real name visible on purpose. A
  finding is only suppressed while its exact file, line, and signature
  substring still match; a moved or reworded line goes stale on purpose
  and re-surfaces until the entry is updated.

To add a new entry: find the real term in an actual `scrub-check`/`vault.sh
check` finding (never guess), add it to the vault with
`scripts/vault/vault.sh add`, and re-run `scripts/publish.sh --dry-run ...`.

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

## Website (Vercel)

The static site in `site/` is published with every release like any other
file, but it is **served from Vercel**, not from GitHub Pages:
`https://rcode-for-claude-code.vercel.app/`. There is no build step — the
folder is plain HTML, CSS, JS, SVG and PNG. The Vercel project
(`rcode-for-claude-code`) is linked from `site/` (`site/.vercel/` is
git-ignored via `site/.gitignore`), so the deploy is one command from the
private repo, run by the maintainer after the release commit exists:

```bash
vercel whoami && vercel teams ls        # confirm the active account/team first
cd site && vercel deploy --prod --yes   # ships site/ as-is to the production alias
```

The deployment URLs Vercel prints (`*-<team>.vercel.app`) are protected by
Vercel's SSO and answer 302; the production alias above answers 200 and is
the only URL that belongs in docs, badges and `og:` tags. Absolute URLs are
baked into every page's `<link rel="canonical">`, `og:url`, `og:image` and
`twitter:image` (`assets/brand/og-image.png`, 1200×630) — change them in all six pages if the alias ever changes.

The GitHub repository's *social preview* image
(`docs/assets/brand/social-preview.png`, 1280×640) has no API — upload it
once under Settings → General → Social preview. Set the repository homepage
to the Vercel URL: `gh repo edit emanuelrechsteiner/claude-rcode --homepage
https://rcode-for-claude-code.vercel.app/`.
