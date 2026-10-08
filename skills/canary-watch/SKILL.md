---
name: canary-watch
description: Post-deploy smoke check of a URL — HTTP status, console errors, failed requests, assets, SSE streams, key content, web vitals against a baseline. Use after a deploy, risky merge, or upgrade. Triggers on "canary", "post-deploy check", "smoke test the deploy".
disable-model-invocation: true
---

<!--
Adapted from affaan-m/ECC skills/canary-watch @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# Canary Watch: Post-Deploy Verification

Check a deployed URL for regressions right after a release. Manual-only (`/canary-watch <url>`): it touches a live site, so it runs when asked.

## When to Use

- After a deploy to production or staging
- After merging a risky PR
- To verify that a fix actually fixed the problem on the deployed site
- During a launch window (repeated checks)
- After a dependency upgrade

## Scope and safety

- Read-only. Only requests that a normal visitor could make, to the URL the user named. No credentialed actions unless the user supplies a safe test account. No load generation.
- Fetching the user's own deployed URL is AUTO per `web-research-trust`. `curl` at a command head is SOFT-ACK (`agency-bands`): state intent in one line. Prefer the Playwright MCP tools for browser-level checks.
- This skill verifies and reports. It does not roll back, redeploy, or change settings; a production mutation is ESCALATE-band even when a check fails. A failing critical check hands over to `incident-response`.

## What it checks

```
1. HTTP status      the page returns 200 (or the expected redirect)
2. Console errors   new errors that were not there before
3. Network          failed API calls, 5xx responses
4. Performance      LCP / CLS / INP against a baseline
5. Content          key elements still present (h1, nav, footer, primary CTA)
6. API health       critical endpoints answer within their limit
7. Static assets    JS, CSS, images, fonts return 2xx/3xx with the expected content type
8. SSE streams      event-stream endpoints connect and deliver a first event or heartbeat
```

## Modes

- **Quick check (default):** one pass, report the results.
  `/canary-watch https://example.com`
- **Sustained watch:** repeat every N minutes for M hours. Use `/loop` with an interval in the session, or a scheduled task; a model cannot watch silently between turns. Every tick must leave a one-line run record (time, status, verdict), otherwise a tick that never ran looks the same as one that passed.
- **Compare mode:** the same checks against staging and production side by side; report the differences.

## Baseline

Regression thresholds need a baseline. Capture one when the site is known healthy: LCP, CLS, response times, request count, console-error count. Store it with the project (for example `docs/canary-baseline.md`), dated and tied to a commit.

Without a baseline, only the absolute thresholds below apply. Say so in the report; do not invent a baseline.

## Alert thresholds

```yaml
critical:   # report first, recommend action
  - HTTP status != 200 (unexpected)
  - more than 5 new console errors
  - LCP > 4s
  - an API endpoint returns 5xx
  - a static asset returns 4xx/5xx
  - an SSE endpoint cannot connect, or drops before the first heartbeat

warning:    # flag in the report
  - LCP up more than 500ms from baseline
  - CLS > 0.1
  - new console warnings
  - response time more than 2x baseline
  - static asset content type changed unexpectedly
  - SSE heartbeat latency more than 2x baseline

info:       # log only
  - minor performance variance
  - new network requests (a third-party script added?)
```

The numbers are starting points. Lab measurements from one session on one network vary: repeat a performance check before calling a regression, and compare like with like (same device profile and throttling).

## Procedure

1. Confirm the target URL and environment with the user's wording, not a guess. Note the commit or deploy ID if known.
2. Run the checks with the available tools: HTTP checks via `WebFetch` or `curl -I`; console, network, content, and vitals via the Playwright MCP tools; assets by loading the page and reading its request list.
3. Compare against the baseline when one exists.
4. Report. A check that could not be run is "not checked", never "OK". A tool that failed to start is a finding in itself.

## Output

```markdown
## Canary Report: example.com, 2026-10-01 03:15 UTC
Deploy: <commit or deploy id, if known>   Baseline: <date/commit | none>

### Status: HEALTHY | DEGRADED | FAILING

| Check | Result | Baseline | Delta |
|---|---|---|---|
| HTTP | 200 | 200 | none |
| Console errors | 0 | 0 | none |
| LCP | 1.8s | 1.6s | +200ms |
| CLS | 0.01 | 0.01 | none |
| API /health | 145ms | 120ms | +25ms |
| Static assets | 42/42 ok | 42/42 | none |
| SSE /events | connected | connected | +80ms heartbeat |

Not checked: <list, with the reason>
Verdict: <regressions found | none detected>. Next action: <one step>.
```

Lead with the verdict line, then the table. Show critical items first.

## Notifications

Report in the conversation. Do not post to Slack, Discord, email, or any external channel from this skill: outward messages are ESCALATE-band and need the user's explicit approval for that exact message.

## Pairing

- `human-testing` or `visual-qa-agent`: pre-deploy and rendered verification before the release.
- `cloud-cli-discipline`: confirm which team and project the deploy went to before judging the wrong URL.
- `production-audit`: the readiness review that precedes a launch.
- `incident-response`: when a critical check fails.
