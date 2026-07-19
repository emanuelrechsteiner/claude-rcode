# Contributing

Thanks for using Claude R.Code! Improvements (new rules, hooks, better docs) are welcome.

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
