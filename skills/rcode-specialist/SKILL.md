---
name: rcode-specialist
description: "Expert knowledge of the R.Code framework and its config repo, distilled into token-efficient reference sheets: project workflow, git history, improvement ledger, hooks and gates, scripts and deploy, vault and publishing, skills and agents, decisions, open defects. Load before working on or inside R.Code, the framework workshop, hooks, deploy, publishing, or the ledger."
---

# R.Code specialist: router

Snapshot of the repo as of commit d5186a4 (2026-10-01), `~/.claude/rcode/VERSION` 2026-09-23, studied 2026-10-03.
Read this page, then ONLY the sheet your task needs. Never load all sheets.

## Brief line for any sub-agent

> Read `~/.claude/skills/rcode-specialist/SKILL.md`, then only the reference sheet(s) your task names. Anchors are `file:line`; re-grep before relying on a line number.

## Which sheet

All sheets live in `references/` next to this file.

| Your task touches | Read |
|---|---|
| Working inside an R.Code project: Stages, `/issue`, trackers, gather scripts, commit and branch rules, backward transitions | `references/workflow.md` |
| Why something is the way it is; releases; reversals; who decided what when | `references/history.md` |
| What an IMP-nnn is; what is open; grep one line per entry | `references/ledger-index.md`, then `references/ledger.md` (themes, backlog, status errors) |
| Changing or debugging a hook or gate; bypass tokens; rule-vs-hook mismatches | `references/hooks.md` |
| Scripts, `deploy-to-live.sh`, the contract linter, test suites, CI, installers | `references/scripts-deploy-tests.md` |
| Vault, pseudonyms, publish chain, scrub-check, a release | `references/vault-publish.md` |
| Which skill, agent or routine exists; their hard rules | `references/skills-agents-routines.md` |
| ADRs, rejected alternatives, retention, model-era numbers, templates, public claims | `references/docs-decisions.md` |
| What is broken or open right now; questions only the owner can answer | `references/open-defects.md` |

Unsure: start with `references/open-defects.md` (what not to trust), then the sheet for your area.

## Invariants that hold without reading anything

1. Entrance is `/team-lead "<directive>"`; the five Stage commands are thin aliases.
2. Vocabulary is binding: Phase = project milestone; Stage = Plan, Design, Develop, Test, Launch; Step = 0 to 9 of `/issue`; work unit = `#N` or `P-NNN`.
3. Single writer: only the lead writes `.rcode/agent-log.md` and `PROJECT-STATUS.md`, never a dispatched worker.
4. Two locations: change only the workshop; `~/.claude` receives finished deploys only. A change is effective in a NEW session after deploy; never claim "works" from the session that wrote it.
5. Gather scripts are the one parser; unknown state is never fabricated as 0; `ok:false` means stop.
6. Backward Stage jump: Iteration N to N-1 is SOFT-ACK; below N-1 needs the four-part futility proof and is ESCALATE.
7. Irreversible or external operations are ESCALATE with a real y/n; never route around a gate; an ack token is single-use and op-bound.
8. Framework files are English only. Product name is "R.Code for Claude Code", never "Claude R.Code". Never write the pre-rebrand name (see MIGRATION.md).
9. No real names, paths, emails or ids in versioned files: use tokens; the vault write gate rejects them.
10. Publishing is disabled by default (`PUBLISH_DISABLED=1`); one run at a time, a human pushes.
11. Ledger write-back is proposed-only; a human promotes. First line of any completion report: `Done: yes` or `Done: no — missing: ...`.
12. Shell is zsh: write `${var}:` never `$var:`.

## Freshness

If `git log -1` is newer than d5186a4, treat the sheets as possibly stale and re-check the cited file. Defects in `references/open-defects.md` were true on 2026-10-03; verify against the current tree before citing or fixing.
