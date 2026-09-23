---
name: incident-response
description: "Incident-response runbook for production issues: observe via read-only diagnostics, form one falsifiable hypothesis, verify it against source before touching anything, ship a minimal hotfix, write a mandatory regression test, then postmortem. Diagnosis stays strictly read-only until the hypothesis is confirmed in code — jumping to a fix on a guess is the core failure mode this skill prevents. Production mutations are always ESCALATE-band, even mid-incident. Backs /launch-team's Run mode; also triggers directly. Triggers on 'incident response', 'production is down', 'prod is down', 'site is down', 'production incident', 'diagnose production issue', 'root cause analysis', 'postmortem', 'produktion ist down', 'seite ist down', 'produktionsvorfall', 'störung beheben', 'ausfall untersuchen'."
user-invocable: true
---

# Incident Response — Production Diagnosis Runbook

This is the runbook behind `/launch-team`'s **Run** mode (`commands/launch-team.md`
— the production-incident loop, currently described inline as raw MCP calls). It
also triggers directly when something in production breaks outside that flow.
Closes the framework's one verified MODERATE coverage gap: Operations/Maintenance
had no dedicated diagnosis capability before this skill.

## What This Skill Is NOT

- **Not for planned work.** Feature work, refactors, planned migrations belong to
  the phase teams (`/issue`, `/launch-team` Ship mode). This skill exists only
  for "something is broken right now."
- **Not a monitoring or alerting system.** It doesn't watch anything continuously
  — it's invoked after a symptom is already known (an alert fired, a user
  reported an error, a dashboard looks wrong).
- **Not a substitute for the normal test gate.** The regression test written in
  Phase 5 is an addition, not a shortcut — the fix still goes through the
  project's normal validation gates (`rules/testing-quality.md`) afterward.

## The Six-Phase Runbook

Work through these phases **in order**. Do not skip ahead under pressure —
jumping from Observe straight to a fix (or worse, a production mutation) on an
unverified guess is the single most common incident-response failure mode.

### 1. Observe — gather evidence before forming a hypothesis

Everything here is **read-only and safe to run without confirmation** — none of
it can mutate production state:

- Supabase: `get_logs`, `get_advisors`
- Vercel: `get_runtime_errors`, `get_runtime_logs`, `get_web_analytics`
- chrome-devtools: `lighthouse_audit`, performance traces
  (`performance_start_trace` / `performance_stop_trace` / `performance_analyze_insight`)
- `git log` on recently deployed commits — what shipped right before the
  symptom started is the highest-signal lead you have

Pull evidence from more than one of these before moving on. A single log line
is rarely enough to distinguish "the deploy broke it" from "the dependency's
API changed" from "traffic pattern shifted."

### 2. Hypothesize

State **one falsifiable claim** about the cause — "X fails because Y changed
in commit Z" — not a list of maybes. If you can't phrase it as something that
could be proven wrong, you don't have a hypothesis yet, you have a hunch.

### 3. Verify against code — stay read-only until confirmed

**Diagnosis stays strictly read-only until the hypothesis is confirmed.** Before
changing anything, confirm the hypothesis against the actual source: `Read`/
`Grep`/`Glob` the suspect module, `git show`/`git diff` the suspect commit. This
is the core discipline of the whole skill — under production pressure the
temptation is to skip straight to a fix (or a prod mutation) on a plausible
guess. If verification disproves the hypothesis, go back to step 2. Do not
patch around a cause you haven't confirmed.

### 4. Minimal fix

The smallest change that addresses the **confirmed** cause, on a hotfix branch
(`fix/<issue>-<short-desc>` off the real trunk — trunk is not always `main`, see
`rules/workflow-git.md`). Delegate the edit itself to the specialist agent for
the affected layer (`backend-agent`, `ui-agent`, etc.) — this skill diagnoses,
it doesn't necessarily write the patch. Opportunistic refactoring, "while I'm
here" cleanups, and unrelated fixes are explicitly forbidden — a hotfix ships
exactly one change.

### 5. Regression test — non-optional

Per `rules/testing-quality.md` Post-Fix Protocol:

1. Run `/fix-review` to check for missed occurrences of the same bug
2. Write a regression test that would have caught this failure (delegate to
   `testing-agent`)
3. Consider `pattern-document` if the fix reveals a reusable pattern (see
   Phase 6)
4. Commit with a message referencing the incident

Skipping this "because the fix is small" is exactly the anti-pattern the
Post-Fix Protocol exists to prevent — a bug small enough to hotfix in five
minutes is also small enough to regression-test in five minutes.

### 6. Postmortem

Check `memory-index` first — has this failure class recurred across projects
before? If the incident reveals a genuinely reusable pattern (not just a
one-off typo or a fat-fingered config value), hand off to `pattern-document` to
turn it into a rule or documented pattern. Not every incident produces a
pattern; forcing one out of a one-off is noise, not learning.

## Production Mutations Are ESCALATE — Even Mid-Incident

Prod DB migrations, `execute_sql`/`apply_migration` against prod, prod
redeploys, rollbacks, and credential/key rotation are **ESCALATE-band** per
`rules/agency-bands.md` — a mandatory verbatim y/n, never self-approved.
Incident urgency is explicitly **not** an override; the band system is scored
by reversibility and blast-radius, not by how much pressure the situation
carries. See `rules/agency-bands.md` for the full matrix and enforcement
layers — not restated here.
