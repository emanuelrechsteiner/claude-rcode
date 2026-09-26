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
