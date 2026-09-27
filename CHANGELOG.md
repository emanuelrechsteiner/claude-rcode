# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This repository is a generated public artifact: each version is one commit
produced by `scripts/publish.sh` from the private source-of-truth repository
(see `docs/PUBLISHING.md`). This file is maintained by hand in that source
repository and published with every release.

## [Unreleased]

## [1.6.1] - 2026-09-27

Maintenance: three routine fixes, a model-era refresh, and verdict-first
completion reports.

### Changed

- `rules/api-cost-optimization.md` covers the current model tiers (Haiku 4.5,
  Sonnet 5, Opus 5.5, Fable 5.1); every claim was checked against the source
  (`docs/model-era-review-2026-09-27.md`).
- Completion reports start with `Done: yes` or `Done: no — missing: …`,
  scoped per visible surface (`rules/slop-prevention.md`).
- A correction about how you work with the agent (not about one codebase) is
  stored once, user-global, in `~/.claude/rules/preferences.local.md`
  (`rules/domain-docs-convention.md`, template
  `templates/preferences.local.md.template`).
- `scripts/ledger-append-proposed.sh` recomputes the ledger's header counters
  on every write and offers `--recompute-only` / `--check`.

### Fixed

- The subagent watchdog no longer reads a bare number such as a character
  count of 529 as an overload error; it needs error context around 429/529.
- Daily docs: the desktop scan counts unparseable lines instead of aborting,
  and file symlinks inside the scanned tree are tolerated without double
  counting (`docs/adr/0004-desktop-audit-lone-surrogate-tolerance.md`).
- Signal rotation writes an explicit empty shard for days without signals,
  merges late entries instead of overwriting them, and exits loudly when
  continuity cannot be proven; daily metrics book such days as verified empty.

## [1.6.0] - 2026-09-26

English throughout, and self-improvement front and center.

### Changed

- The framework, its docs and ADRs (renamed: `docs/adr/0002-rcode-plan-follows-practice.md`,
  `docs/adr/0003-vault-and-gate.md`) and the Cockpit are English throughout.
  The `Hausbau` output style's instruction text is English and still answers
  in the asker's language. German input keywords (skill triggers, report-only
  classifier phrases) remain accepted aliases alongside their English forms.

### Added

- Self-improvement is presented as a headline feature on the website home
  page and in the README.
- `CLAUDE_DAILY_DOCS_LANG` (`en` default, or `de`) in `~/.claude/env.local.sh`
  sets the language of the daily-docs logbook: its headings and the
  "not capturable" sentences `logbook-count.sh` emits. JSON keys are unchanged.

### Fixed

- `scripts/tests/routine-run-regression.sh` ran its real-`claude` parser probe
  in the project folder, which started a short-lived Claude session there. It
  now runs in a throwaway folder.
- Cockpit (companion repo `claude-cockpit`): the pane follows the session in
  its folder that was most recently active, not the one that started last, so
  a short-lived background `claude -p` call can no longer take it over and
  leave every card waiting.

## [1.5.0] - 2026-09-26

Plain developer language by default, and a Cockpit that always shows the
current wave of work.

### Changed

- **Default output style: none.** A fresh install answers in ordinary
  software-developer language. The `Hausbau` output style (every change
  explained through a house-building metaphor, for readers who are not deeply
  technical) still ships in `output-styles/hausbau.md` and is opt-in:
  `/output-style Hausbau`. Until 1.4.1 it was switched on for everyone.
- `/team-lead` and the control agent record every wave as a task list
  (`TaskCreate`, set to `in_progress` at dispatch and `completed` in the wave
  review), so the wave is visible next to the session while it runs.

### Added

- Publish step removes the maintainer's personal `outputStyle` from the
  published `settings.json`; regression suite
  `hooks/tests/publish-strip-regression.sh`.
- Cockpit (companion repo `claude-cockpit`): card 4 derives a "Welle" (wave)
  from the subagent start/stop hook events, one row per subagent, in every
  session that dispatches subagents — independent of whether the model keeps
  a task list, which appears above it when present.

## [1.4.1] - 2026-09-26

The Cockpit is now public and installable, and the website and README show it
as it runs today. No rule, hook, skill, agent or script behavior changed for a
public install.

### Added

- Cockpit setup, step by step: the Cockpit page ("Set it up"), the install
  page ("Optional: the Cockpit") and the README carry the one-line installer
  of the companion repo `claude-cockpit`. It lists every change before making
  it (Ghostty, tmux, Node and jq via Homebrew; the Cockpit under
  `~/.claude/cockpit`; the `cockpit` command; ten entries in
  `~/.claude/settings.json`; Ghostty keybindings and the `rcode` color theme),
  asks once, backs up every file it edits, and supports `--dry-run`.

### Changed

- Cockpit product images: the Subagents card names model and effort for
  every subagent and adds a status line (its task while running, "idle" once
  done); the Workflows card lists every task with its own bar.
- Website Cockpit page describes both cards.

### Fixed

- The publish step also removes the private Cockpit `subagentStatusLine`
  setting, so a public install never points at a script it does not have.

## [1.4.0] - 2026-09-26

A name that follows Anthropic's rules, a website, and a front page that shows
what the framework does. No rule, hook, skill, agent, script or setting changed.

### Added

- Website at <https://rcode-for-claude-code.vercel.app/>: home, install,
  how it works, Cockpit and vault pages. Static files in `site/`, served by
  Vercel; deployed by the maintainer with each release (`docs/PUBLISHING.md`).
- Two animated terminal demos in `docs/assets/demo/`: the Autonomy Arbiter
  stopping `gh pr merge` until you answer, and `/team-lead` running three
  agents while the Cockpit shows their progress.
- Brand assets in `docs/assets/brand/`: wordmark, banners for light and dark
  themes, social preview image (1280×640), favicon, and the architecture
  diagram (`architecture-{dark,light}.svg`) in the brand's own style.
- Cockpit product images in `docs/assets/cockpit/`: Claude Code and the
  Cockpit side by side in Ghostty, and the Cockpit column up close. Demo
  data only.
- The block composition from the banner (colored, modular blocks) is the
  brand's primary motif and runs through every page of the website.

### Changed

- The project is named **R.Code for Claude Code**. Anthropic does not allow
  "Claude" or "Claude Code" as part of a third-party product name. The
  repository name `claude-rcode` stays.
- README rebuilt as a front page: banner, tagline "Build smarter. Build
  better.", four benefits, demos, one-line install, generated component counts.
- Trademark notice on the README and every site page.

## [1.3.0] - 2026-09-26

Pseudonymized by design: real names, machine paths and personal identifiers
never enter the framework. They live only in a local vault on the
developer's machine; the framework carries tokens. Decision record:
`docs/adr/0003-vault-and-gate.md`.

### Added

- Local vault `~/.claude/vault/` (git-ignored, secret `0600`) as the single
  source of real values, with `scripts/vault/vault.sh`
  (`init | add | check | tokenize | resolve | token | status | doctor | prune-public`).
  Tokens are keyed HMAC-SHA256 prefixes (`proj-…`, `acct-…`, `id-…`) or fixed
  role tokens (`<dir>`, `<email>`, `<private-repo-url>`, `<BAUHOF>`).
- One matcher for every consumer: `scripts/vault/lib.sh`.
- Write gate `hooks/vault-write-gate.sh`: refuses real values in Write, Edit,
  MultiEdit and Serena writes to tracked files of a framework repo.
- Commit gate `scripts/git-hooks/pre-commit`, also run as `pre-merge-commit`;
  install with `bash scripts/install-git-hooks.sh --only pre-commit`. Blocks
  staged real values and force-added ignored files.
- Vault gate on the improvement-ledger write path (`scripts/ledger-append-vault-gate.sh`).
- Contribution path for third parties: `templates/imp-submission.template.md`
  and `scripts/imp-submit.sh` (validates a submission against the vault, no
  network access). See `CONTRIBUTING.md`.
- Templates: `templates/env.local.sh.template` (machine-specific runtime
  values), `templates/reminders.local.md.template`,
  `templates/automode-environment.template.json`.
- `scripts/vault/public-names.txt`: names that are public by decision and
  never treated as vault terms.

### Changed

- Machine paths and personal names in prose, rules, skills, hooks, scripts and
  scheduled tasks replaced by role tokens or environment variables; runtime
  values come from `~/.claude/env.local.sh`, `git remote`, or the system.
- `autoMode` is an installation-only settings key; it is no longer shipped in
  `settings.json` and survives `claude-deploy`.
- Routine timers use generic launchd labels (`com.claude-code.routine-<task>`);
  `scripts/install-routine-timers.sh` migrates the previous per-user labels.
- `scripts/scrub-check.sh` uses the vault matcher for every PII finding and
  redacts values in CI (`GITHUB_ACTIONS`, `CI`, or `--redact`).
- In commit mode (`--staged`) the rebrand check only counts added lines, so
  touching a file with accepted historical mentions no longer blocks a commit.
- Publish transforms `30-placeholder-scan` and `50-pseudonymize` are no-ops on
  the now-clean tree.
- This changelog replaces the previous stub that pointed to GitHub Releases.

### Removed

- Publish transforms `60-declaw-scrub-check-pii` and
  `65-generalize-reminders-section`.
- Hard-coded detection literals in `scripts/scrub-check.sh`.

### Fixed

- `publish-manifest.txt` excluded every directory named `vault/`, which also
  dropped the vault tool `scripts/vault/` from the published tree; the pattern
  is now anchored to the root (`/vault/`).
- Renamed files were skipped by the staged scan (`--diff-filter=AMRC`).
- The HMAC secret is never passed on a command line.

### Security

- CI output of `scrub-check.sh` never prints a matched value.

### Upgrade notes

1. `bash scripts/vault/vault.sh init`, then add your own private terms with
   `vault.sh add`.
2. Copy `templates/env.local.sh.template` to `~/.claude/env.local.sh` and fill
   in your values.
3. `bash scripts/install-git-hooks.sh --only pre-commit` in your working copy.
4. `bash ~/.claude/scripts/install-routine-timers.sh` if you use the routines.

## [1.2.0] - 2026-09-25

### Changed

- `CLAUDE.md` is a signpost instead of a logbook (about 57,000 to about 15,000
  characters); the full inventory moved to `docs/FRAMEWORK-REFERENCE.md`.
- Evidence and incident history moved verbatim out of the always-loaded rules
  into `docs/archive/rules-evidence/`.
- `release-cli-discipline` and `cloud-cli-discipline` are on-demand skills
  instead of always-loaded rules.
- Always-loaded instructions stay under Claude Code's 150,000-character limit.

## [1.1.1] - 2026-09-24

### Fixed

- The cockpit handover re-syncs its dependencies after deploy.

### Changed

- README: cockpit showcase.

## [1.1.0] - 2026-09-23

### Changed

- Public history restarted with a single commit; it replaces 1.0.0 and 1.0.1.
- R.Code "plan follows practice" rework (`docs/adr/0002-rcode-plan-follows-practice.md`):
  `/team-lead` is the main entrance, `.rcode/config.json` gains a `tracker`
  field (`github` or `plan`), binding glossary, two-tier ADRs.

### Security

- Publish pipeline hardened: the gate runs against the unmodified private copy
  of `scrub-check.sh`, private hook registrations are stripped from the
  published `settings.json`, and a cached auto-mode snapshot is removed.

## [1.0.1] and [1.0.0]

Superseded. Their history was replaced by 1.1.0 and is no longer available.

[Unreleased]: https://github.com/emanuelrechsteiner/claude-rcode/compare/v1.6.1...HEAD
[1.6.1]: https://github.com/emanuelrechsteiner/claude-rcode/compare/v1.6.0...v1.6.1
[1.6.0]: https://github.com/emanuelrechsteiner/claude-rcode/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/emanuelrechsteiner/claude-rcode/compare/v1.4.1...v1.5.0
[1.4.1]: https://github.com/emanuelrechsteiner/claude-rcode/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/emanuelrechsteiner/claude-rcode/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/emanuelrechsteiner/claude-rcode/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/emanuelrechsteiner/claude-rcode/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/emanuelrechsteiner/claude-rcode/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/emanuelrechsteiner/claude-rcode/releases/tag/v1.1.0
