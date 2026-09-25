# Launch Playbook

Stage 5 — Launch. Release, deployment, and production operations (ship and
run). Loaded by `~/.claude/commands/team-lead.md` (directly, or via the
`/launch-team` alias) once R.Code Mode has selected this Stage.

## Asset cluster

| Asset | Kind | Use for |
|---|---|---|
| `version-control-agent` | agent (sonnet) | Release commits, tags, PRs |
| `worktree-consolidate` | skill | Merge-readiness audit before a cut |
| `validate-build` | skill | Build/type/lint validation |
| `dependency-audit` | skill | Pre-release dependency check |
| `documentation` | skill | Release notes / changelog drafting |
| `backend-agent` | agent (sonnet) | Production diagnosis and hotfix |
| `nextjs-debug` | skill | Framework-level production diagnostics |
| `react-perf-check` | skill | Performance regression diagnosis |
| `research` | skill | Vendor/dependency incident status |
| `pattern-document` | skill | Postmortem → reusable rule |
| `memory-index` | skill | Cross-project repetition check |
| `testing-agent` | agent (sonnet) | Regression test per Post-Fix Protocol |

## Operating modes

| Mode | Trigger when | Loop |
|---|---|---|
| Ship | Directive is a release/deploy ask | Cut the release using the Ship-half assets above, under the `release-cli-discipline` skill (`~/.claude/skills/release-cli-discipline/SKILL.md`) §1–3 (local-first deploy, tarball-test before publish, `printf`-piping + verify-by-pull) |
| Run | Directive reports a production incident | `~/.claude/skills/incident-response/SKILL.md` — its six-phase runbook (Observe → Hypothesize → Verify → Fix → Regression test → Postmortem) is the Run-mode procedure, never re-copy it here; the asset cluster above supplies the delegates it calls out (`backend-agent`, `testing-agent`, `pattern-document`, `memory-index`, `nextjs-debug`, `react-perf-check`) |

## Version authority (double-authority fix)

`~/.claude/commands/phase-gate.md` already creates internal milestone tags
on project-Phase completion — a Phase concept, not this Stage. This Stage
must never become a second tag-creator:

| Instance | May tag | Format | Purpose |
|---|---|---|---|
| `~/.claude/commands/phase-gate.md` | internal milestone tags | `v0.N.0-<phase-name>` | Phase marker, local, optional-but-recommended |
| This Stage (Launch) | user-facing releases | `vMAJOR.MINOR.PATCH` | semver, changelog, `gh release` (ESCALATE — verbatim y/n) |

This Stage owns the user-facing semver, changelog, `gh release`, and
rollback path. It never creates `v0.N.0-*` milestone tags — exclusively
`/phase-gate`.

## Stage nuance (backward transitions)

Full protocol in `~/.claude/rcode/stages/backward-transitions.md` — read it,
don't re-derive it here.

Launch's standard iteration is **5→4** — a release-blocking finding Test
can still validate through its existing strategy. Its typical drawing-board
case is **5→3** — a production incident whose root cause is an
implementation decision Test could not structurally have caught — skipping
straight back to Develop rather than re-running a Test strategy that never
covered this defect class.

## Authority boundary

This Stage's authority ends at shipping what Test validated and keeping the
shipped system running — not re-opening milestone scope, not overruling a
Test no-go. If it becomes clear mid-work that the *plan itself* is wrong
(e.g. the RC was never actually ready), that's an escalation to management,
never a silent re-plan.

## --overnight

When the invoking command carries `--overnight`, follow
`~/.claude/commands/autonomous-overnight.md` unchanged (its `Mechanism
(INVARIANT — DO NOT MODIFY)` section governs ESCALATE-band queueing) — not
restated here.
