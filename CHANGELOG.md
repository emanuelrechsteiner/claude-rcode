# Changelog

All notable changes to Claude R.Code are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [SemVer](https://semver.org/).

This repository starts its history at `v1.0.0`. Claude R.Code is a public rebuild of a private, single-operator Claude Code configuration that had been in daily use and iteration for months before this release — that history (commit-by-commit) lives in the private predecessor's local history, not here. Publishing as a clean `v1.0.0` was a deliberate choice over faking a higher version number: this is a new git object with no inherited tags, so a fresh semver start is the honest one. See `MIGRATION.md` if you're coming from a project set up under that predecessor.

## [1.0.0] — Initial public release

Initial public release of Claude R.Code.

### Added

- **Rules** — always-loaded guidance covering agent orchestration, code quality, testing, security, git workflow, documentation, tool discipline, context management, and the autonomy-band system (`rules/agency-bands.md`) that governs which operations run automatically versus requiring explicit confirmation.
- **Hooks** — deterministic lifecycle automation: session-start identity and context checks, pre-tool-use guards against destructive commands and secret leaks, post-edit validation, and session-end metrics.
- **Agents** — specialized Task-tool sub-agents for planning, backend work, testing, code review (read-only), cleanup, UI, documentation, and git discipline, plus a central control-agent for multi-agent orchestration.
- **Skills** — on-demand, forked-context specialists for research, validation, pattern extraction, documentation, and framework self-maintenance.
- **Commands** — the R.Code atomic development workflow (`/brainstorm` → `/decompose` → `/issue` → `/review` → `/phase-gate`), plus general-purpose commands (`/continue`, `/handoff`, `/lessons`, `/status-sync`).
- **Scheduled tasks** — cron-style recurring agent runs for daily documentation, nightly observation rollups, and weekly self-review.
- **Observation pipeline** — a hook-driven signal capture system feeding an on-demand meta-analysis skill that proposes rule/hook changes from accumulated session friction.
- **Installer** — `install.sh` with `fresh` / `overwrite` / `augment` modes (auto-detected by default) for adopting the framework on a machine with no existing config, replacing one, or selectively merging into an existing `~/.claude` setup. `install.ps1` provides a minimal clone/backup installer for Windows.
- **Release gate** — `scripts/scrub-check.sh`, enforced both as a local pre-push hook and in CI, scanning every push for secrets and personal-data patterns before it reaches the public remote.
