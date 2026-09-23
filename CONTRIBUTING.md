# Contributing

Thanks for using Claude R.Code! Improvements (new rules, hooks, better docs) are welcome.

## How this repo is generated — read this before opening a PR

If you're reading this in `claude-rcode`: this repo is a **generated public
artifact**, published from a private source-of-truth repo. It has no git
history before each release's single squashed commit, and it is never
hand-edited directly. Because of that, **pull requests opened against this
repo cannot be merged here** — a `pr-guard` check on every PR fails on
purpose, and branch protection enforces it structurally, not just as a
convention.

That doesn't mean contributions aren't welcome — it changes how they land:

1. Open your PR as usual (fork, branch, changes, `gh pr create`). This is
   still the right way to *propose* a change and get it reviewed/discussed.
2. A maintainer reviews it. If accepted, they run `scripts/backport-pr.sh
   <PR-number>` in the private repo, which fetches your diff, applies it
   onto a new local branch there, and preserves your authorship via a
   `Co-Authored-By: <your name> <your GitHub noreply email>` trailer on the
   resulting commit.
3. The change ships in the next release published from the private repo.
4. The maintainer closes your original PR with a comment pointing at the
   release/commit that shipped it.

Your name stays attached to the change the whole way through — it just
travels via `Co-Authored-By` rather than a GitHub merge button. See
`docs/PUBLISHING.md` for the full architecture and the maintainer-side
runbook (`scripts/publish.sh`, `scripts/backport-pr.sh`).

The rest of this document (commit conventions, quality gates, scrub-check)
still applies to what a maintainer does when back-porting your change into
the private repo — read it as "what the eventual commit needs to satisfy,"
not as "steps you personally run against this repo."

## Quick path

1. Fork the repo on GitHub
2. Clone your fork: `git clone <your-fork-url> ~/.claude` (back up your existing `~/.claude` first if needed — or install into a scratch directory and copy over just the files you're changing)
3. Make changes on a branch: `git checkout -b improvement/short-description`
4. Commit with the conventional format below
5. Push: `git push origin improvement/short-description`
6. Open a PR against `main` of the upstream repo

## What belongs upstream

Good upstream contributions:

- New always-loaded rules that benefit any user (not personal preferences)
- New hooks that improve safety, observability, or workflow for everyone
- New skills that solve a generic problem
- Bug fixes (existing hook breaks, regex too broad, etc.)
- Documentation improvements
- Cross-platform polish (Windows PowerShell hook equivalents, etc.)

Stays personal (use your own `.local.*` overlay):

- Identity mappings, names, emails
- Personal project names in examples
- Machine-specific paths or env vars
- Personal CLAUDE.md additions

## Commit conventions

Use Conventional Commits:

```
<type>(<area>): <description>

<body>

Co-Authored-By: <if applicable>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `style`, `chore`, `perf`.

Areas (examples): `rules`, `hooks`, `skills`, `agents`, `commands`, `templates`, `install`, `gitignore`, `observation`.

## Scrub check before pushing

This is a **mandatory gate**, not a suggestion — a pre-push hook and a GitHub Action both run it, so an unscrubbed push either gets blocked locally or fails CI. Run it yourself first:

```bash
cd ~/.claude
bash scripts/scrub-check.sh
```

It scans every tracked file for secret patterns (API keys, tokens, private key headers) and known personal-data patterns (real names/emails outside the `LICENSE`/README author-credit allowlist, machine-specific absolute paths, provider IDs). A non-zero exit prints the offending file:line — move the content to a `.local.*` overlay or genericize it, then re-run.

Install the pre-push hook once per clone:

```bash
bash scripts/install-git-hooks.sh
```

## Quality gates for PRs

- All hooks pass shellcheck (where applicable)
- New rules include a brief rationale ("derived from X" or "prevents Y")
- New skills follow SKILL.md frontmatter convention
- New hooks register in settings.json AND document trigger event
- No personal content in committed files (`scripts/scrub-check.sh` exits 0)

## Questions, bugs, suggestions

Open an issue on GitHub. Tag it `question`, `bug`, or `enhancement`.
