<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/agency-bands.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/agency-bands.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Agency Bands Rule (intro line under the title)

> AUTO / SOFT-ACK / ESCALATE — the single band system for what self-approves vs. what needs a human y/n, scored by reversibility × blast-radius × input-trust, NOT by mode. **Supersedes `excessive-agency-gate.md` + `autonomy-arbiter.md` (merged 2026-07-03, IMP-079); all enforcement semantics preserved.** Always loaded.

## Decision Table (common ops)

Original table row (shortened to `SOFT-ACK (IMP-146)` in the rule):

| Action | Band |
|---|---|
| curl/wget/HTTP-POST at command head | SOFT-ACK (IMP-146, 2026-08-23 — 24 reflex overrides in 3 weeks proved zero net protection from the block) |

## Global Machine-State Changes (IMP-163)

**Evidence:** `gh auth switch --user acct-3aa5eb` ran without a y/n and was reported only afterward, under "What I did to your environment." Three documented incidents trace to exactly this: wrong repo / wrong deploy account (the account being deployed to did not match the account the human expected — `plans/meta-proposal-2026-08-24-august-vollanalyse.md` IMP-163). `cloud-cli-discipline.md` already describes the team/scope auto-pick risk for read commands (`teams ls`, `whoami`); this row is the gate for the *write* side of the same risk class.

## Bulk-Pipeline Manifest Gate (IMP-152)

**Evidence:** on 2026-08-03, a bulk documentation pipeline run with `--backend claude-cli` leaked third-party health data before any manifest gate existed; the gate was retrofitted only project-locally afterward (`plans/meta-proposal-2026-08-23-chat-analyse.md` IMP-152, findings-meta.md A1). This paragraph makes the rule generic instead of reinventing it per project.

*Same-incident evidence for the sink-vs-suite gap:* on 2026-08-03, the automatic security check found the first fix cosmetic — "the 'exclusion' only removes files from the file count … `graphify extract` is invoked on the unfiltered project root" — yet **four minutes later** the triggering work-thread reported "fixed" with 42 green checks. The suite measured the file counter, not the actual call the external tool received. That check result never reached the work-thread that made the "fixed" claim — see `testing-quality.md` "Automatic Check Results Belong to Their Trigger" for that second, independent defect from the same incident.

Original paragraph (shortened to a one-line justification in the rule):

**Why no deterministic hook covers this gate.** `hooks/mcp-agency-gate.sh` fires only on `tool_name` values prefixed `mcp__*` (its own case-guard, `case "$TOOL" in mcp__*) ;; *) exit 0 ;; esac`) — the documented 2026-08-03 incident ran as a Bash-CLI invocation (`--backend claude-cli`), a class of call this hook structurally never sees. A hypothetical MCP-routed equivalent would not be safely pattern-matchable either: the hook's existing `ESCALATE_RE` suffixes (`apply_migration`, `merge_pull_request`, …) work because the *operation itself* is irreversible regardless of its payload. Whether a bulk run's file corpus is sensitive and its target external and unvetted is a property of the **file contents and provenance**, not of the tool name — a generic name like `upload_file` fits both a harmless single-screenshot upload and this exact incident. Encoding that distinction as a name-suffix regex would either block benign single-file uploads (the same reflex-override pattern IMP-146 already found for `curl`/`wget`) or wave the real case through because no observed MCP connector in this repo's configuration (`settings.json`) carries a recognizable bulk-verb suffix to match against. This gate therefore stays deliberately **behavioral-only** — enforced by this rule and your own pre-run judgment, not by a pattern a shell script can check.

## Bash-gate ESCALATE patterns (command-position only)

Original bullet point (without the origin parenthetical in the rule):

- **`npm config set … -g`/`--global`/`--location=global`/`-L global`** (IMP-163/193/209) — writes npm's global config, not the project's `.npmrc`. The flag may sit **before or after** `config set`, and the value may be **quoted** (`--location='global'`) — the gate checks the raw, quote-preserving segment for this one value, because `strip_data()` removes quoted *contents* and would otherwise let `--location=''` through (a parser differential found by the security review the same day the `--location` check shipped). `--location=project` and the read forms (`get`, `list`) stay AUTO; the no-scope form and `--location=user` (both write the user's `~/.npmrc`) are an open scope decision, still AUTO

> **Why the flag-position and quoting classes matter (IMP-209):** the five findings behind them came through the new security-review return channel (IMP-207) on its first day — three from 2026-08-24 that had sat unread for 16 days, two from the same day about the `--location` fix itself. Measured before the fix: 11 of 11 bypass forms passed with exit 0; after: 11 of 11 exit 2, 12 legitimate forms still exit 0, ACK-token contract (single-use, op-bound) verified for the new forms. Regression: `hooks/tests/gate-regression.sh` (169 cases).

## ESCALATE in automatic-approval mode (don't-ask/Auto)

**2026-08 measurement (IMP-145):** across 5 Framework sessions running under an automatic-approval mode (don't-ask / Auto / `--dangerously-skip-permissions`), 26 actions were denied — 16× by the classifier, 10× by the don't-ask mode itself — including **`AskUserQuestion` itself, twice**, and a `gh release create` **with a valid ACK token**. The ask-channel is structurally dead in those modes: if even the ask tool gets denied, retrying it again does not help. (Evidence: `plans/meta-proposal-2026-08-23-chat-analyse.md` IMP-145, findings-framework §1.)

## The MCP ESCALATE Set — two layers since IMP-078

Original paragraph (without the last sentence in the rule):

**Deterministic (`mcp-agency-gate.sh`, 2026-07-03; SQL-aware since 2026-08-06):** fires on every `mcp__*` call; classifies by tool-name **suffix** (server prefixes are per-connector UUIDs). Irreversible-class suffixes — `apply_migration`, `deploy_edge_function`, `firebase_deploy`, `pause_project`/`restore_project`, `merge/rebase/reset/delete_branch`, `merge_pull_request`, `execute_action`, calendar-event mutations — get native `permissionDecision:"ask"` (real one-click y/n; unanswerable asks fail safe in headless runs). **`execute_sql` is classified by the STATEMENT, not the tool name:** read-only queries (`SELECT`/`WITH`/`EXPLAIN`/`SHOW`) have no blast radius and get an explicit `permissionDecision:"allow"` (AUTO band — no prompt); only write/DDL statements (`INSERT`/`UPDATE`/`DELETE`/`DROP`/`ALTER`/`CREATE`/`TRUNCATE`/`GRANT`/…) escalate to `ask`. An unparseable query fails safe to `ask`. Word-boundary normalization means column names like `updated_at`/`created_at` do NOT trigger. `deploy_to_vercel`: preview = SOFT-ACK (allow + stderr note); prod-flagged input = ask. Logged with `gate:"mcp"` (`decision:"allow-read"` for the AUTO SQL path). Prior blanket-ask on all `execute_sql` produced 1016 spurious prompts in one proj-5b6377 session — fixed 2026-08-06.

## References

- Sources: Casco YC W26; OWASP LLM07; Chrome "act without asking"; OpenClaw daemon prompt-injection RCE (KB clusters 09 + 15, private)

## Moved from the rule on 2026-09-29 (IMP-234)

> Condensing round IMP-234 (instruction files under 150k chars). The passages below were shortened or removed in `rules/agency-bands.md`; each is carried over verbatim from the rule as it stood before that round, under the heading it had there. The normative content stays in the rule; what lives only here is rationale, hook internals, history, and citations.

### The Core Principle

**You are the arbiter, and agency is gated by reversibility — never by mode.** Genuinely irreversible operations require an explicit human y/n even in `--dangerously-skip-permissions` / YOLO / autonomous mode. Mode only widens the set of *reversible* ops you may auto-run — one wrong autonomous irreversible action costs more than N confirmations on safe ones (Casco YC, OWASP LLM07). Default posture is permissive: **allow unless the op actually executed is genuinely irreversible, external, or production-affecting.** A read-only command, or one that merely *mentions* a dangerous op as string data, is not a dangerous op.

### Decision Table (common ops)

Original rows whose cells were shortened (the full lists now live once, under "Bash-gate ESCALATE patterns" and "Global Machine-State Changes"; the German cell fragment was translated to "at command head"):

| Action | Band |
|---|---|
| `rm -rf` on a disposable target (`/tmp`, `$TMPDIR`, `/var/folders`, `node_modules`, `dist`, `build`, `.next`, `target`, `.cache`, `*.egg-info`, relative `./path`) | AUTO |
| curl/wget/HTTP-POST am Kommandokopf | SOFT-ACK (IMP-146) |
| Bulk pipeline run against an EXTERNAL backend over a file corpus (e.g. a bulk-doc pipeline invoked with `--backend <external-cli/-service>`) | ESCALATE — requires a pre-run file manifest + y/n (see "Bulk-Pipeline Manifest Gate" below) |
| Global machine/account-identity change — `gh auth switch`, `vercel switch`, `git config --global` (write), `npm config set … -g`/`--global`, `gcloud config set account`, `aws configure` (wizard/`set`, not `list`/`get`) | ESCALATE (see "Global Machine-State Changes" below) |

### Global Machine-State Changes (IMP-163)

A command that changes **identity or configuration outside the current project** — which GitHub account `gh` acts as, which team `vercel` deploys to, the user's global `~/.gitconfig`, npm's global config, the active `gcloud`/`aws` account — is **always ESCALATE**, even though the command itself looks like a harmless one-liner. Reason: unlike a file edit, this state is **not scoped to the session or the repo** — it persists in the shell/tool's own config after the session ends, and the **next, unaware run inherits it silently.** A local, per-repo equivalent (`git config user.email …` without `--global`, `gh auth status`, `aws configure list`) is read-only or repo-scoped and stays AUTO — the ESCALATE is specifically for the *global* form.

The `cloud-cli-discipline` skill already describes the team/scope auto-pick risk for read commands (`teams ls`, `whoami`); this row is the gate for the *write* side of the same risk class.

**If approved:** either (a) revert the global change back to its prior value before the session ends (state the revert command explicitly), or (b) if the change is meant to persist past this session, say so explicitly in the same turn — a silent, undocumented persistence is exactly the failure mode this row exists to close.

### Bulk-Pipeline Manifest Gate (IMP-152)

A bulk run that feeds a local file corpus through an **external** backend (e.g. a bulk documentation/analysis pipeline invoked with `--backend <external-cli/-service>`) is **always ESCALATE** — regardless of how reversible the run itself looks. Reason: the Meta Rule-of-Two from `agents-as-users.md`. (1) the file corpus is normally **untrusted/unaudited** (no one has reviewed every file individually), (2) it can contain **sensitive/private data** (health, personal, or financial data belonging to third parties), and (3) the run is an **external send** to a foreign backend — 2 of 3 (usually all 3) booleans fire, which forces ESCALATE even where R looks reversible.

**Verify at the sink, not the suite.** A fix to a data-exfiltration bug — bulk pipeline, export, sync into an external backend — counts as fixed only once the proof is taken at the actual sender/output: which files/records the external tool really receives (a capture of the real invocation parameters, or a dry run that prints the real target-file list) — **not** a green test/regression suite that merely checks a counter or a manifest field. A green suite can confirm an exclusion field was *set* correctly without proving the sender ever *reads* that field. This is a general rule for any data-sink fix, not only this bulk-pipeline case; the full pattern (incl. the companion "same code path" discipline) lives in `testing-quality.md` under "Verify at the Sink, Not the Suite" and "Verify Via the Same Code Path, Not a Reimplementation" — not duplicated here to avoid a second copy drifting out of sync.

**Why no deterministic hook covers this gate.** `hooks/mcp-agency-gate.sh` fires only on `tool_name` values prefixed `mcp__*`, so a Bash-CLI invocation (`--backend claude-cli`) is structurally invisible to it; and whether a bulk run's file corpus is sensitive and its target external and unvetted is a property of the **file contents and provenance**, not of the tool name — a name-suffix regex would either block benign single-file uploads or wave the real case through. This gate therefore stays deliberately **behavioral-only** — enforced by this rule and your own pre-run judgment, not by a pattern a shell script can check.

### Enforcement — Four Deterministic Layers + You

A PreToolUse hook is a synchronous shell script — **it cannot invoke an LLM.** Hooks only classify; the judgment lives in this rule and your turn. Evaluation order:

1. **CRITICAL floor — native `deny[]` + `guard-unsafe.sh`:** never-allow hard-block on `rm -rf` of `/`, `~`, `$HOME`, or `*`, host-destruction (`mkfs`/`dd`/device writes), netcat/reverse-shells; also WARNS (non-blocking) on force-push. Network-exfiltration via curl/wget/scripted-HTTP data-upload is SOFT-ACK, not a hard block (IMP-146, see the Decision Table row above) — the `curl -o` output-path arm stays a hard block (writes to a critical filesystem path). Untouched by everything below.
2. **Native `ask[]` (settings.json):** real y/n FIRST for `git push --force`, `git reset --hard`, `npm publish`. The bash gate deliberately does NOT re-match these — no double-prompt.
3. **Bash gate (`excessive-agency-gate.sh`), PreToolUse|Bash:** the pattern list below. Two OS outcomes only: **exit 0** = allow (may print one non-blocking stderr `NOTE`); **exit 2** = ESCALATE (block + ask). Fails OPEN on parse-failure/empty command (the CRITICAL floor still stands). Logged to `~/.claude/global-observation/excessive-agency.log`.
4. **MCP gate (`mcp-agency-gate.sh`), PreToolUse `mcp__.*` — NEW 2026-07-03, IMP-078:** deterministic layer for the MCP ESCALATE set (below); returns native `permissionDecision:"ask"`. What no gate can pattern-match falls to your judgment per the band matrix.

### Reading the classifier

**Never route around a gate** — not via another tool, another language, `eval`, base64, or a subprocess (`subprocess.run`, `child_process`). If the gate blocked it, the answer is "ask the user," not "find another door."

### Bash-gate ESCALATE patterns (command-position only)

- **`gh auth switch`** (IMP-163) — changes the active GitHub identity for every subsequent `gh` call in the shell, inherited by the next unaware session
- **`vercel switch`** (IMP-163) — changes the active Vercel team/scope for every subsequent deploy
- **`git config --global`** with a write action (IMP-163) — writes the user's GLOBAL `~/.gitconfig`; read-only forms (`--get`, `--get-all`, `--get-regexp`, `-l`/`--list`) stay AUTO; plain `git config` without `--global` (repo-local) stays AUTO. **Also `--system` and `--file <path>`/`-f <path>` (IMP-209)** — both write outside the repo (`/etc/gitconfig`; any caller-chosen path, incl. `~/.gitconfig`), with the same read-only carve-out
- **`npm config set … -g`/`--global`/`--location=global`/`-L global`** (IMP-163/193/209) — writes npm's global config, not the project's `.npmrc`. The flag may sit **before or after** `config set`, and the value may be **quoted** (`--location='global'`) — the gate checks the raw, quote-preserving segment for this one value, because `strip_data()` removes quoted *contents* and would otherwise let `--location=''` through. `--location=project` and the read forms (`get`, `list`) stay AUTO; the no-scope form and `--location=user` (both write the user's `~/.npmrc`) are an open scope decision, still AUTO
- **`gcloud config set account`** (IMP-163) — switches the active gcloud account; global options between binary and subcommand (`gcloud --verbosity=none config set account …`) are tolerated by the matcher (IMP-209), `gcloud config list` stays AUTO
- **`aws configure`** (IMP-163) — writes AWS CLI credentials/profile globally; `aws --profile p configure set …` (options before the subcommand) escalates too (IMP-209); `aws configure list`/`get` stay AUTO (read-only)
- **`vercel switch`** likewise tolerates options before the subcommand (`vercel --debug switch other-team`, IMP-209)

> Regression for the flag-position and quoting classes (IMP-209): `hooks/tests/gate-regression.sh` (169 cases).

### ACK-token contract (`CLAUDE_AGENCY_ACK_ONCE`)

- **Single-use** (consumed sha recorded per `$PPID`/session; replay re-blocks) and **op-bound** (mismatched sha logs `ack-mismatch` and still blocks). Allow logged with `authorizer=user`.
- Replaces the broken session-wide `CLAUDE_GATEGUARD_OFF` inline bypass (env-read before any inline `export` — never worked inline); that flag now scopes only `gateguard.sh` (Read-before-Edit), not this gate.

### ESCALATE in automatic-approval mode (don't-ask/Auto)

**Why (IMP-145):** in an automatic-approval mode (don't-ask / Auto / `--dangerously-skip-permissions`) the ask-channel is structurally dead — even `AskUserQuestion` itself, and a `gh release create` with a valid ACK token, were denied — so retrying the ask does not help.

1. **No ask-tool retry.** The op is NOT requested via `AskUserQuestion` or an equivalent dialog tool; a second attempt after a denial is forbidden — this is the dead channel, not a random failure.
2. **The op is NOT executed.** No self-minted ACK token, no substitute op, no routing around the gate (unchanged from the principle above).

The principle from "The Core Principle" above — **irreversible ops need y/n even in YOLO/Auto mode** — stays verbatim. The queue IS the y/n, just deferred asynchronously to the next moment a human can actually answer. This applies in addition to the existing overnight mechanism (`commands/autonomous-overnight.md`) — that one is for a pre-agreed, seven-check-vetted overnight run; this paragraph also fires outside an explicit `/autonomous-overnight` run, the moment the ask-channel is provably dead.

### The MCP ESCALATE Set — two layers since IMP-078

The bash gate cannot see MCP tool calls. They are now covered twice:

(The "Deterministic" paragraph is carried verbatim above, under the IMP-217 heading of the same name.)

**Behavioral (this rule):** backstop for anything the suffix list misses — the ESCALATE rows of the decision table apply unchanged to MCP routes: prod SQL/schema changes, external human comms (incl. PR/issue/comment creation that notifies others), prod deploys, credential/IAM/secret writes. Read-only MCP calls and clearly reversible, notify-no-one actions (create a draft, add a label) are AUTO.

### Delegation — Control-Agent Is the Single Escalation Point

Also enforced via agent system prompts (irreversible-ops y/n clause regardless of mode flags) and the R.Code phase-gate (no phase advance after unconfirmed irreversible ops).

**Anti-patterns:** trusting the agent with `git push --force` (the single most damaging command — always confirm); standing-allowlisting irreversible ops (the ACK token is per-op and single-use, NOT a standing bypass); subprocess/eval bypasses; "it's just my dev machine" (the OpenClaw daemon RCE proves prompt-injection reaches personal machines).

### When to Override (Documented Cases)

- **Per-op user approval:** the ACK-token path above (single-use, op-bound, logged `authorizer=user`).
- **Gate self-testing / log analysis:** `CLAUDE_GATE_TESTMODE=1` (exit 0, logged).

All overrides are logged. Relaxation stays bounded by **reversibility, not mode**: the deterministic gates fire regardless of what the LLM "decided," the ack token (minted only after a real user y/n) is the only way past, and the CRITICAL floor + native `deny[]` are evaluated first.

### References

- Supersedes `excessive-agency-gate.md` + `autonomy-arbiter.md` (IMP-079, 2026-07-03; originals in git history)
- Mechanisms: `excessive-agency-gate.sh` + `mcp-agency-gate.sh` (IMP-078) + `guard-unsafe.sh` + native `ask[]`/`deny[]` + `CLAUDE_AGENCY_ACK_ONCE`
- Companions: `agents-as-users.md`, `workflow-git.md` (lifecycle band mapping; report-only mode), the `cloud-cli-discipline` skill

### Second pass — gate-log path, regression-suite path, Companions line (first-pass wording)

Log: `~/.claude/global-observation/excessive-agency.log`.

Regression suite: `hooks/tests/gate-regression.sh`.

Companions: `agents-as-users.md`, `workflow-git.md` (lifecycle band mapping), the `cloud-cli-discipline` skill.
