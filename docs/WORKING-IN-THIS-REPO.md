<!--
Status: ACTIVE
Last Updated: 2026-08-22
Purpose: Working rules for agents and humans working on this repo — the two-location model, what you can verify yourself, the acceptance checklist
-->

# Working Rules — Working in This Repo

This document applies to **everyone** working on `claude-code-config`:
humans and agents alike. It answers three questions: Where do I make
changes? What can I verify myself? What does the user have to verify?

## 1. Where am I? (always first)

```bash
pwd
```

| Path | Location | Rule |
|---|---|---|
| `…/claude-code-config` | **workshop** | Change, test, and commit here. |
| `~/.claude` | **live install** | Never edit by hand. Receives only `claude-deploy`. |

The same pattern applies to the Cockpit: workshop `…/cockpit` (sibling
directory), live install `~/.claude/cockpit`.

**Double-loading in the workshop (fixed 2026-09-24, IMP-217):** A session
run from the workshop loads `CLAUDE.md` twice — once as the user
instruction from the live install (`~/.claude/CLAUDE.md`), once as the
project instruction from the workshop — Claude Code compares only paths,
never content. The documented `claudeMdExcludes` switch
(`code.claude.com/docs/en/memory`, path patterns matched against absolute
paths) excludes the **workshop copy**, so the session keeps reading the
deployed state:

```json
// .claude/settings.local.json in the workshop (machine-local, git-ignored)
{ "claudeMdExcludes": ["<BAUHOF>/CLAUDE.md"] }
```

Visible at the next session start: the "N instruction files add up to …"
line counts one fewer `CLAUDE.md`. The overall 150,000-character limit
behind that line is, incidentally, **only a warning** — nothing gets
truncated (officially undocumented; evidence: Claude Code issue #96506).

**What happens if you edit the live install anyway:** your change goes
live immediately (the very next tool call in the same session already uses
the new hook), and the next deploy aborts, because the live install has
uncommitted changes to tracked files. You've then created cleanup work,
not an improvement.

## 2. The self-reference problem — why you cannot sign off on your own work

Claude Code reads rules, hooks, skills, agents, and `settings.json` into
memory **at session start**. Your running session therefore works with the
state from before — not with what you just wrote.

This has hard consequences:

- **A changed rule does NOT take effect in your session.** You cannot
  observe whether it works.
- **A changed hook that lives in the live install, by contrast, takes
  effect IMMEDIATELY** — on the very next tool call. This is not an
  advantage but a danger: a bug in it can cripple the running session (a
  PreToolUse hook with exit code 2 blocks tool calls). This is exactly why
  work happens in the workshop.
- **A new skill/command only shows up in the menu in a new session.**

> **Phrase results accordingly.** Not: "The hook works now." Instead: "The
> hook passes the direct invocations (see below); whether it works in
> practice shows up after `claude-deploy`, in a new session — see the
> acceptance checklist for verification steps."

## 3. What you CAN and MUST verify YOURSELF

These checks run without a deploy, directly in the workshop. Run them
before reporting done — "unverified" is an acceptable result, "probably
fine" is not.

### Call hook scripts directly

A hook is an ordinary shell script that receives JSON on `stdin` and
answers via exit code and output. This can be checked completely without
Claude Code:

```bash
# Check a gate with one harmless and one dangerous command
# (verified 2026-08-04: returns 0 and 2 respectively)
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  | CLAUDE_GATE_TESTMODE=1 bash hooks/excessive-agency-gate.sh; echo "harmless -> $?"
echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1"}}' \
  | bash hooks/excessive-agency-gate.sh; echo "dangerous -> $?"
```

Exit code 0 = allowed through, 2 = blocked (asks the user).
`CLAUDE_GATE_TESTMODE=1` keeps the gate from blocking itself during the
self-test.

Always check **both directions**: the case that should pass, and the case
that should block. A gate that blocks everything passes a one-sided test
just as well as a correct one.

### Run the existing regression suites

Eight suites live under `hooks/tests/`, one under `scripts/tests/` — the
four biggest:

```bash
bash hooks/tests/gate-regression.sh              # 73 cases
bash hooks/tests/web-fetch-gate-regression.sh    # 97 cases
bash scripts/tests/deploy-regression.sh          # 20 cases (deploy)
bash hooks/tests/parallel-lock-regression.sh     # 12 cases
ls hooks/tests/ scripts/tests/                   # full list
```

If you change a gate, **extend its suite with the new case** — otherwise
the change stays permanently unverified.

> **Fixed (2026-08-22):** The long-standing failure of
> `hooks/tests/controller-first-regression.sh` documented here earlier
> (26/3, due to `q2-probe-dispatch-dump.sh` being retired under IMP-115)
> is repaired — the suite now runs 35/35 green. The warning sat here 18
> days longer than the defect existed — whoever fixes a suite takes the
> notice down in the same commit.

### `settings.json` syntax

```bash
jq . settings.json > /dev/null && echo "JSON OK"
```

A syntax error here is especially treacherous: Claude Code then starts
with default values — no hooks, no permissions — and only mentions it in
passing. **Never commit without this check.**

### Inventory instead of hand-counting

```bash
./scripts/framework-inventory.sh          # numbers straight from disk
./scripts/framework-inventory.sh --json
```

**Never** maintain counts in documents by hand — they drifted apart three
times simultaneously in the past (IMP-083).

### Vault check

The vault (`~/.claude/vault/`, gitignored) holds real names/paths/
identifiers — the framework itself may not contain a single one
(`docs/adr/0003-vault-and-gate.md`).

```bash
bash scripts/vault/vault.sh check <file>                      # exit 0 clean, 2 hit
CLAUDE_VAULT_DIR=/nonexistent bash scripts/vault/vault.sh check --structural-only <file>  # CI simulation without a vault
```

Every write additionally passes through `hooks/vault-write-gate.sh`
(PreToolUse Write|Edit|MultiEdit); bypass only deliberately, via
`CLAUDE_VAULT_GATE_OFF=1` (logged, never the value). In the workshop, only
the pre-commit hook belongs here (`bash scripts/install-git-hooks.sh
--only pre-commit` — pre-push stays reserved for the public contribution
path).

**One-time setup** (once per machine): copy/fill in
`templates/env.local.sh.template` to `~/.claude/env.local.sh`, then run
`vault.sh init`.

**Ground rule:** prose → token, code → env var + fail-loud (never a token
as a fallback value), tests → synthetic values.

### Cockpit (its own repo, its own workshop)

```bash
cd "${CLAUDE_WORKSHOP_ROOT}/cockpit"   # from ~/.claude/env.local.sh
npm test          # 25 checks
npm run typecheck

# Check the event hook directly (writes to $COCKPIT_DIR)
echo '{"session_id":"probe","cwd":"/tmp"}' \
  | COCKPIT_DIR=/tmp bash hooks/cockpit-event.sh SessionStart; echo "exit=$?"
```

## 4. Deploy and sign-off

### Deploy (after the commit in the workshop)

```bash
claude-deploy config     # or: cockpit | all
```

The tool only ever fast-forwards and aborts if the workshop has
uncommitted changes.

**Runtime preferences (since IMP-127, 2026-08-04).** Two things in the
live install are written by Claude Code itself at runtime, and used to
make every deploy fail because of it:

| What | Who writes it | Handling |
|---|---|---|
| `settings.json` → `model`, `effortLevel` | `/model`, `/config` | Pulled **back** into the workshop and recorded there as its own commit. The live install keeps the value. |
| `plugins/installed_plugins.json`, `plugins/known_marketplaces.json` | every plugin update | No longer versioned; carried across the deploy. |

The list of pulled-back keys sits as `RUNTIME_KEYS_JSON` near the top of
the script. **It is deliberately short** — every entry disables one
protective check. If the live install diverges in a key that is *not*
listed, or in any other tracked file, the deploy still aborts and names
the spot. That is the expected outcome for "someone edited the live
install by hand" — and that is exactly what should stand out.

> **Dead end, don't rebuild it:** a `~/.claude/settings.local.json` does
> *not* solve this. At the **user level**, Claude Code does not read this
> file — per `code.claude.com/docs/en/settings`, the local level only
> exists per-project (`.claude/settings.local.json` at the repo root).
> Verified on 2026-08-04: the `NOTION_PARENT_PAGE_ID` entered there is not
> set in the session environment. On this machine, per-machine environment
> values belong in `~/.zshrc` — that is demonstrably where they actually
> arrive from.

### Acceptance checklist — what the USER verifies

At the end of its work, an agent writes an acceptance checklist in exactly
this form, so the verification never has to be guessed:

```markdown
## Acceptance on the running Claude Code

Prerequisite: `claude-deploy config`, then start a NEW session
(`/clear` is NOT enough — hooks and rules are only read at process start).

1. <Concrete action> -> expected: <concretely observable result>
2. …

If step N fails: <what that means, where the error would show up>
Rollback: `cd ~/.claude && git reset --hard <commit-before-the-change>`
```

Every step must name an **observable** result — an output, a file, a line
in a log. "Should run better now" is not a verification step.

If the deploy introduces a new vault term (a new `kind`, a new group with a
noticeable count), the acceptance checklist additionally names `bash
scripts/vault/vault.sh status` (plain numbers, never a value) as a
verification step.

### An important subtlety: `/clear` is not enough

`/clear` empties the conversation history, but **starts no new process**.
Hooks, rules, skills, and `settings.json` stay at the state from process
start. A genuine sign-off needs a new terminal, or a new `claude`
invocation.

## 5. Rollback

Both sides are versioned; every deploy is reversible:

```bash
cd ~/.claude && git log --oneline | head -5      # find the state before the deploy
cd ~/.claude && git reset --hard <commit>        # roll back
```

Backup copies of `settings.json` already live as `settings.json.bak-*` in
the live install anyway.

## 6. Common mistakes

| Mistake | Why it hurts |
|---|---|
| Editing `~/.claude` directly | Goes live immediately; blocks the next deploy |
| Reporting "tested" without having run a command | The self-reference problem makes observation in your own session impossible — the claim is then pure invention |
| Changing a gate without extending the regression suite | The change stays permanently unverified |
| Updating counts in `CLAUDE.md` by hand | Drift; `framework-inventory.sh` is the only source of truth |
| Committing `settings.json` without the `jq` check | Claude Code silently starts with no hooks and no permissions |
| Testing only a gate's positive case | A gate that blocks everything passes this test too |
| Building a side-finding into the same session | Scope drift — the session then ends with an open construction site instead of a commit + deploy |

## Side-findings: note them, don't build them (IMP-148)

A work session ends with a commit + deploy, not with an open construction
site. If an extra problem surfaces during the actual task (another hook
worth improving, a third-done documentation gap, a refactoring wish) — it
gets noted as `status: proposed` in the ledger, not built in the same
session. Otherwise the task quietly grows past its own scope, and in the
end neither the core task ships cleanly nor is the side-finding verified
properly.

> **Backed by the agent's own past behavior:** 2026-08-04 "What you're
> doing right now is scope drift … nothing more", 2026-08-05 "No scope
> drift. Wrap up and deploy" — both times the user had to pull a running
> session back onto the actual task.

## References

- Two-location model, compact: section "Two Locations: Workshop and Live
  Install" in `CLAUDE.md`
- Deploy tool: `scripts/deploy-to-live.sh` (aliased as `claude-deploy`)
- Framework architecture: `HARNESS.md`
- Full inventory with history (hook table, routine status, IMP evidence —
  moved out of `CLAUDE.md` since 2026-09-24): `docs/FRAMEWORK-REFERENCE.md`;
  archived rule evidence: `docs/archive/rules-evidence/`
