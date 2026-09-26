# 0001 — Reactivate Serena write tools behind a delegating, fail-closed gate

- Status: accepted
- Date: 2026-08-05
- Translated: 2026-09-26 (English; decision unchanged)

## Context

The protective hooks in `settings.json` bind to tool **names**
(`Write|Edit`). Serena's write tools are named `mcp__serena__*` — no name
matches, so every Serena edit bypassed all 10 Write|Edit hooks (including
`security-audit.sh` and `observation-capture.sh`). Because of this, all 11
write tools were globally disabled on 2026-07-17 (IMP-104/105, "read-only
by design"). The verdict at the time, a 3:0 review, rejected an adapter:
every checker is fail-open (exit 0 when `file_path`/`content` is missing) —
a half-built adapter would have reported green without actually checking
anything.

The cost: Serena's reference-aware tools (`rename_symbol`,
`safe_delete_symbol`) and the token-saving symbol edits were lost with no
replacement. The owner judged this loss too high on 2026-08-05: Serena
specializes in efficient code work, and a path to using it without
compromising the protection system was required.

## Decision

A delegating, fail-closed PreToolUse hook (`hooks/serena-write-gate.sh`,
matcher `mcp__serena__.*|mcp__plugin_serena_serena__.*`) translates every
Serena write call into the native `(file_path, new_string)` shape and calls
**the same checker scripts** as the native path (no drift-prone copies):
`parallel-lock-check` → `file-protection` → `security-audit` →
`config-protection` (whose recoverable *ask* deliberately runs last).
Fail-closed means: an unknown tool, a missing contract parameter (param
drift), unparsable input, or a missing checker script → **deny**, never
wave it through; no bypass env var exists. `rename_symbol`/
`safe_delete_symbol` get a confirmation prompt instead of a silent allow
(the language server writes N unnamed reference files). `replace_in_files`
stays double-blocked. Memory names containing path segments are refused. A
PostToolUse twin (`serena-post-tool.sh`) feeds the native follow-up chain
and the read tracker. This shrinks `excluded_tools` in
`~/.serena/serena_config.yml` down to `replace_in_files`; activation is
mandatory **after** deploy plus a new session.

## Consequences

**Gets easier:** symbol edits and reference-aware refactors using Serena's
specialized tools, at the same protection level as native edits;
`signals.jsonl` sees Serena edits for the first time. **Gets harder:** any
extension of Serena's tool set requires a deliberate contract extension in
the gate plus a regression case (fail-closed shuts new things out by
default). Known residual gaps, documented rather than hidden:
`gateguard`/`pretool-auto-read` and `controller-first-mutation-gate` are
not delegated; the N−1 reference files of a confirmed `rename_symbol` are
not individually inspected. Proof of live effect is still pending until
`claude-deploy` plus a new session allow the triple proof (secret block,
signals line, rename confirmation) — regression status: 35/35
(`hooks/tests/serena-gate-regression.sh`). Supersedes the adapter verdict
from IMP-104; ledger: IMP-130.

## Update 2026-08-05 — Live proof delivered, one finding along the way

The first session after `claude-deploy` allowed the triple proof announced
above, run against a Serena scratch project deliberately activated outside
this repo:

1. **Secret block** — a `replace_content` call containing an AWS key
   pattern (`AKIA...`) was blocked by `security-audit.sh`. Passed.
2. **Signals line** — a clean Serena edit showed up in `signals.jsonl` and
   `serena-gate-log.jsonl` — initially with an **incorrect path** (a
   finding, see below; correct after the fix).
3. **Rename confirmation** — the gate correctly triggered
   `"decision":"ask"`. Whether this turns into a real interruption depends
   on the session's approval mode: in an automatic-approval mode
   (`--dangerously-skip-permissions`/YOLO), `ask` resolves automatically
   with no visible prompt. Not a defect in the gate — a limit of this
   specific proof, not of the safeguard itself.

**Finding:** `resolve_path()` in `serena-write-gate.sh` (and
`serena-post-tool.sh`) built the absolute address from `$CWD` — the Claude
Code session's working directory — instead of from Serena's actual active
project root. The two are identical only when exactly one project is
active per session; a bash hook cannot query Serena's running process
state synchronously, so it cannot resolve this divergence. When they
diverged, the downstream protection scripts (`file-protection.sh` and
others) checked a fabricated, non-existent address instead of the real
target file, and the build log recorded that same wrong path — a silent,
security-relevant malfunction, not a cosmetic one.

**Fix:** the six tools that necessarily edit an already-existing file
(`replace_content`, `replace_symbol_body`, `insert_after_symbol`,
`insert_before_symbol`, `rename_symbol`, `safe_delete_symbol`) now refuse
(`deny`) when the assembled address does not exist on disk — fail-closed
instead of silently checking against a fiction, even ahead of the
multi-file `ask` from `rename_symbol`/`safe_delete_symbol`. The regression
harness now creates real fixture files (previously only path names were
named, never files created — the bug was structurally invisible to the old
harness) and includes two new cases that reproduce the divergence via a
second, independent directory. Regression status: **37/37**. Known residual
gap, unchanged: an unrelated file that happens to share a name under the
wrong address would still be (incorrectly) checked against itself; memory
tools remain without an existence check, because they are legitimately
allowed to create new files. Ledger: IMP-131.
