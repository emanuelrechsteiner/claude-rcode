# testing-and-quality

How to run tests:
- Unit: `npm test` or repo specific
- E2E: Playwright/Cypress if present
- Coverage: document thresholds and gaps

CI hints:
- Add smoke tests that run in <60s
- Ensure `lint` and `typecheck` jobs
