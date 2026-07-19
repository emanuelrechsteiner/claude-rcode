# Claude R.Code

> A portable, project- and language-agnostic Claude Code configuration framework: always-loaded rules, safety hooks, specialized agents, forked skills, and the R.Code atomic development workflow — installed with one command.

Claude R.Code turns [Claude Code](https://claude.com/claude-code) from a general-purpose coding agent into a harness with guard rails: rules that load on every session, hooks that gate risky operations, agents sized for the work they do, skills that stay out of your main context until you need them, and an atomic issue-driven development workflow for projects that opt in.

## What's in here

| Component | Where | What it does |
|-----------|-------|---------------|
| **Rules** (always loaded) | `rules/*.md` | Coding standards, security, git workflow, context management, autonomy bands — injected into every session |
| **Hooks** (lifecycle automation) | `hooks/*.sh` | Deterministic shell gates on session start, before/after tool calls, and on session end — block destructive commands, enforce read-before-edit, scan for secrets |
| **Agents** (Task tool) | `agents/*.md` | Specialized sub-agents for heavy implementation (planning, backend, testing, code review, cleanup, UI, docs, git) — each sized to the right model tier for its job |
| **Skills** (on-demand, forked context) | `skills/*/SKILL.md` | Lightweight specialists that run in an isolated context and report back a summary — research, validation, pattern extraction, and more |
| **Commands** (slash commands) | `commands/*.md` | The R.Code atomic development workflow: `/brainstorm`, `/decompose`, `/issue`, `/review`, `/phase-gate`, and general-purpose commands like `/continue` and `/handoff` |
| **Scheduled tasks** | `scheduled-tasks/*/SKILL.md` | Cron-style recurring agent runs (daily docs, nightly observation rollup, weekly self-review) |
| **Templates** | `templates/*.template` | Starter files for your personal, gitignored `*.local.*` overlay |
| **Examples** | `examples/*.example` | Worked examples of the overlay pattern |

See `CLAUDE.md` for the framework architecture (rules/agents/skills/hooks tables) and `HARNESS.md` for the system-design rationale.

### Two ideas worth knowing about before you install

- **Agency bands (AUTO / SOFT-ACK / ESCALATE).** Every tool call is implicitly classified by reversibility, blast-radius, and input trust. Reversible, local, trusted work runs without asking. Anything genuinely irreversible or external — force-push, a production migration, a merge, an outbound message — always gets a real y/n, even in unattended/autonomous runs. See `rules/agency-bands.md`.
- **The observation pipeline.** Edits and session-end events are captured as lightweight signals. When enough accumulate, an on-demand skill (`meta-observer`) synthesizes them into concrete proposals for new or changed rules — the framework is meant to improve itself from its own friction, reviewed by you before anything lands.

## Install

Requirements: `bash` 4+, `git`, `jq`. Hooks are bash scripts — on Windows they need WSL or Git Bash (`install.ps1` covers native PowerShell for a plain clone + backup; hook execution itself still needs a bash environment). A [Claude Code](https://claude.com/claude-code) install with either a Pro/Max subscription or an Anthropic API key.

### One command

```bash
git clone https://github.com/emanuelrechsteiner/claude-rcode.git && cd claude-rcode && ./install.sh
```

`install.sh` auto-detects the right mode for your machine:

| Detected state | Mode | What happens |
|---|---|---|
| No `~/.claude`, or empty | **fresh** | Clones straight into `~/.claude`, copies templates to `*.local.*` overlays, makes hooks executable |
| `~/.claude` already tracks this repo | **fresh** (self-update) | `git pull` — safe, your `.local.*` files are gitignored and untouched |
| `~/.claude` has unrelated content | asks you | Prompts `overwrite \| augment \| abort` with a recommendation based on what it finds |

You can also force a mode explicitly: `./install.sh --mode {auto|fresh|overwrite|augment}` (default `auto`).

- **`fresh`** — clone (or self-update) straight into `~/.claude`.
- **`overwrite`** — backs up your entire existing `~/.claude` to `~/.claude.backup-<timestamp>` (nothing is deleted, only moved), then does a fresh install. Because moving your whole config is a state-changing operation, this always asks for a one-time confirmation, including when `--mode overwrite` is passed directly (skip with `--yes` once you're sure).
- **`augment`** — the interesting one. It scans your existing `~/.claude` unit-by-unit (every rule, hook, skill, agent, command, plus your `settings.json`), classifies each R.Code unit against what you already have as **new** (safe to add), **identical** (skipped), or **conflicting** (shown as a diff, your call: keep yours / take R.Code's / skip). It then prints a recommendation — *augment*, *lean toward overwrite*, or *skip, your config already covers this* — based on how much new value R.Code would add versus how much would collide. Nothing is written without your say-so per conflicting file, `settings.json` is never replaced wholesale (only its `hooks` registrations are merged via `jq`, your `env`/`model`/`permissions` stay untouched), and `--dry-run` prints the full report and changes nothing on disk.

### Windows

```powershell
iwr -useb https://raw.githubusercontent.com/emanuelrechsteiner/claude-rcode/main/install.ps1 | iex
```

`install.ps1` is a minimal, community-maintained installer: clone/backup only (no `augment` scan-and-merge — that logic is bash-only). The hooks themselves need WSL or Git Bash to execute; PowerShell alone gets you the files, not the automation.

### Logging in

The installer never touches credentials. On first `claude` launch after install, Claude Code runs its own login flow:

```
Setup complete. Start Claude Code with:  claude
On first launch, Claude Code runs its OWN login flow — choose either:
  • Pro/Max subscription  → browser OAuth (claude.ai)
  • Anthropic API key      → paste when prompted, or export ANTHROPIC_API_KEY
R.Code never stores or reads your credentials.
```

## Personalize (the `.local.*` overlay pattern)

Personal content lives in gitignored `*.local.md`, `*.local.sh`, `*.local.json` files. The committed repo stays generic; you create your own overlays from the shipped templates (the installer does this automatically for missing files):

| Template | Copies to | Purpose |
|----------|-----------|---------|
| `templates/CLAUDE.local.md.template` | `~/.claude/CLAUDE.local.md` | Personal additions to the global framework doc |
| `templates/MEMORY_FIRST.local.md.template` | `~/.claude/MEMORY_FIRST.local.md` | Personal context loaded at session start |
| `templates/identity.local.md.template` | `~/.claude/rules/identity.local.md` | Your git identities and which project paths trigger which |
| `templates/settings.local.json.template` | `~/.claude/settings.local.json` | Machine-specific preferences (model, editor mode, notifications) and env vars (e.g. a Notion page ID) — the committed `settings.json` deliberately omits all of these |

`.local.*` files are gitignored and survive every `git pull`.

## Update

```bash
cd ~/.claude
git pull            # pull latest framework updates — your .local.* overlays are untouched
```

To contribute improvements upstream, see `CONTRIBUTING.md`.

## Upgrading a project's rails

Projects that opted into the R.Code atomic workflow (they have a `.rcode/` directory) carry their own copy of the workflow rules. When the framework itself moves forward, run `/rcode-upgrade` inside that project — it does a three-way diff against the new rule versions and asks per-file before touching anything you've customized.

## Coming from the private predecessor

If you're migrating a project that was set up under the pre-public, privately-run predecessor of this framework (different state-directory name, different command slugs), see `MIGRATION.md` for the one-time rename.

## Architecture

- `CLAUDE.md` — the framework's own onboarding doc: rules, agents, skills, hooks, and the behavioral directives that tie them together.
- `HARNESS.md` — the system-design rationale (why rules/skills/hooks/agents/MCP as separate layers, the layered-defense model, the self-improvement loop).

Key idea: **you orchestrate, agents execute.** Heavy implementation goes to specialized agents sized for the job; lightweight diagnostics go to forked skills that keep your main context clean.

## Contributing

See `CONTRIBUTING.md`. Every push is gated by `scripts/scrub-check.sh` (locally via a pre-push hook installed by `scripts/install-git-hooks.sh`, and again in CI) — it scans for secrets and personal-data patterns before anything reaches the remote.

## License

MIT — see `LICENSE`.

## Credits

Maintained by [Emanuel Rechsteiner](https://github.com/emanuelrechsteiner).
