---
name: production-audit
description: Local-evidence production-readiness audit with a ship/block verdict and 0-100 score across auth, data, payments, operations, UX; no repo data sent to third-party scanners. Use before a launch or after a merge. Triggers on "production audit", "ready to ship", "what breaks in prod".
disable-model-invocation: true
---

<!--
Adapted from affaan-m/ECC skills/production-audit @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# Production Audit

Use when the user asks whether an application is ready to ship, what could break in production, or what must be fixed before a launch. Manual-only (`/production-audit`): it is a deliberate pre-launch pass, not something to trigger on the phrase "is this ready".

The audit is built from local and user-authorized evidence only. Do not run unpinned remote code (`npx <pkg>@latest`), upload repository contents to a third-party service, or call an external scanner unless the user approves that specific tool and data flow.

## When to Use

- "Is this production-ready", "what would break in prod", "what did we miss", "ready to ship?"
- A feature was merged and needs a pre-deploy or post-merge risk pass
- A public launch, demo, customer rollout, or investor walkthrough is close
- CI is green but the question is production risk, not test status
- A deployed URL, release branch, PR, or current checkout is available as evidence

## When not to use

- During active implementation: line-level secure coding comes first (`quality-review` has a security specialist pass).
- Pure libraries, templates, docs-only repos, scaffolds, unless the question is packaging or release readiness.
- A formal compliance audit. This is engineering triage, not legal, financial, medical, or regulatory certification.
- When the only input is an idea with no repo, deployment, CI, or runtime surface.
- A live outage: that is `incident-response`.

## How it works

Order of work:

1. Establish the release surface.
2. Read recent changes and the current branch state.
3. Inspect the runtime, auth, data, payment, background-job, AI, and deployment boundaries that actually exist in the repo.
4. Check CI, tests, migrations, environment documentation, and the rollback path.
5. Produce a short ship/block recommendation with specific fixes.

This is read-only. It changes no file and deploys nothing; fixes are offered at the end, not applied.

## Evidence checklist

Start with cheap, local signals:

```text
git status --short --branch
git log --oneline --decorate -20
git diff --stat origin/main...HEAD
```

(Use the repo's real trunk instead of `main` where it differs; see `workflow-git`.)

Then inspect the project-specific surface:

- Package scripts, CI workflows, release scripts, Docker files, deployment manifests
- API routes, webhooks, auth middleware, background workers, cron jobs, database migrations
- Environment-variable documentation and startup checks
- Observability: error reporting, logs, health checks, dashboards
- Rollback, seed, migration, and backfill instructions
- End-to-end coverage of the user paths that matter most

For a deployed URL in scope, use browser or HTTP checks against that URL only, and avoid credentialed actions unless the user supplies a safe test account. For large repos, split the reading across read-only `Explore` agents (auth, data, ops, UX; per-spawn Agent/Model/Effort per `agents/control-agent.md` §2) and merge their findings; name the source file for every claim.

## Risk lenses

### Security and auth
- Are public, API, and admin routes clearly separated?
- Are authentication and authorization enforced server-side?
- Are secrets kept out of client bundles, logs, example output, and committed files?
- Are rate limits, CSRF protection, CORS policy, and upload validation present where needed?
- Does an AI or agent surface defend against prompt injection, tool abuse, and untrusted content reaching privileged actions?

### Data integrity
- Do migrations run forward cleanly, with a rollback or recovery plan (`database-migrations`)?
- Are destructive migrations, backfills, and imports staged safely?
- Do database policies, grants, and service-role boundaries match the tenancy model?
- Are writes, jobs, and webhook handlers idempotent under retry?

### Payments and webhooks
- Are webhook signatures verified before the payload is trusted?
- Is each payment, subscription, or fulfillment webhook idempotent?
- Are replay, duplicate delivery, and out-of-order delivery handled?
- Are test-mode and live-mode credentials separated?

### Operations
- Can the app start from a clean checkout using documented commands?
- Are required environment variables named, validated, and fail-fast?
- Is there a health check that proves dependencies are reachable?
- Are deploy, rollback, and incident-owner paths documented?
- Are logs useful without leaking secrets or personal data?

### User experience
- Are the launch-critical paths covered on desktop and mobile?
- Are forms usable on mobile (no input zoom, no layout overlap, no blocked submit)?
- Do loading, empty, error, and permission-denied states say what happened?
- Is there a support or recovery path when a critical operation fails?

## Scoring

Scores force prioritization; they do not imply mathematical certainty.

| Band | Score | Meaning |
|---|---|---|
| Blocked | 0-49 | Do not ship until the top risks are fixed |
| Risky | 50-69 | Ship only behind a small rollout or an internal beta |
| Launchable with caveats | 70-84 | Ship if the owners accept the listed risks |
| Strong | 85-100 | No obvious launch blockers from the available evidence |

Cap the score at **69** if any of these holds:
- Authentication or authorization is missing on sensitive data
- Payment or fulfillment webhooks are not idempotent
- Required migrations cannot be run safely
- Secrets are exposed in client bundles, logs, or committed files
- There is no rollback path for a high-impact release

Cap the score at **84** if CI is not green, if the launch-critical path was not tested end to end, or if a lens above could not be inspected at all. An unchecked lens is missing evidence, not a pass.

## Output format

Lead with one sentence:

```text
Production audit: 76/100, launchable with caveats; webhook idempotency and rollback docs are the two risks to fix before public launch.
```

Then:

- **Blockers:** must-fix items before deploy
- **High-value fixes:** next fixes to raise the score
- **Evidence checked:** files, commands, CI runs, deployed URL, PRs inspected
- **Evidence missing:** what would change confidence if provided
- **Next action:** one concrete fix or verification step

Keep strengths short. The user asked about readiness, so the useful answer is the remaining risk and the next action.

## Example

User: `/production-audit`

```text
Production audit: 68/100, risky: Stripe webhooks are verified but not idempotent, and there is no rollback note for the pending migration.

Blockers:
- Add idempotency for `checkout.session.completed` before fulfilling orders.
- Write and test the rollback path for `20260511_add_billing_state.sql`.

High-value fixes:
- Add a health check that verifies database and payment-provider reachability.
- Add one E2E path for upgrade, webhook fulfillment, and billing-page refresh.

Evidence checked:
- api/stripe/webhook.ts
- db/migrations/20260511_add_billing_state.sql
- CI run for the release branch

Evidence missing: staging deploy URL; no production error-report access.

Next action: patch webhook idempotency first?
```

## Anti-patterns

- Running `npx <package>@latest` or a remote scanner as the default audit path
- Uploading source, secrets, customer data, or private topology to an external service without explicit approval
- A score with no named evidence
- Treating green CI as production readiness
- A generic "let me know what you want to do" as the closing line
- Applying fixes during the audit; the audit reports, the owner decides

## Related skills

- `quality-review`: multi-specialist code review of a milestone, including security.
- `incident-response`: when production is already broken.
- `database-migrations`: migration safety behind the data-integrity lens.
- `human-testing`: click-through verification of the launch-critical paths.
- `dependency-audit`: vulnerable and outdated packages.
- `validate-build`: build, type, and lint check.
- `canary-watch`: verification of a deployed URL after release.
