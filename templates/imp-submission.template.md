<!--
Status: ACTIVE
Last Updated: 2026-09-26
Purpose: Template for an IMP submission without private data (IMP-219,
Wave 4 / Workstream G-script). Fill it in, then check it with
`scripts/imp-submit.sh` — see CONTRIBUTING.md, section "Submitting an
improvement (IMP) without your private data". The six "## " headings below
are the required-field anchors that `scripts/imp-submit.sh` looks up by
exact text match — renaming a heading makes the corresponding field
invisible to the script (it then counts as never filled in).
`scripts/imp-submit.sh` also accepts the older German headings this
template used to ship (as aliases), so a form filled in against an earlier
copy still validates.
-->

# IMP Submission

## What does NOT belong in here

This form ends up as GitHub issue or PR text. Write into it: WHAT is
observable, WHICH rule / WHICH hook / WHICH skill is affected, and WHICH
number backs it up. Do NOT write into it: real project, company, or account
names, machine-specific paths (home directory, project root, volume name),
personal identifiers (email address, session/trigger/Notion ID), or any
identifying phrase. Use placeholders instead, like `<project>`, `<path>`,
`<account>`, `<team>`. `scripts/imp-submit.sh` checks the filled-in form
against your local vault (if present, `scripts/vault/vault.sh`) and always
structurally against known patterns (paths, email addresses, IDs) — but the
best check remains never writing a real value in the first place.

## Problem Class

<!-- One line: what kind of problem — e.g. "missing escalation",
"silent fallback", "wrong exit behavior", "excess token spend". -->

## Symptom

<!-- What is observably wrong — without project or location names. Use
placeholders like `<project>`, `<path>`, `<account>`. -->

## Measurement / Evidence

<!-- The number or artifact the symptom hangs on, plus its measurement
depth — measured, not assumed. Example: "17 of 40 sessions showed X (grep
over 40 JSONL files, cutoff date <date>)". -->

## Proposed Change

<!-- Which rule / hook / skill should change — a diff sketch if possible:
```diff
- old line
+ new line
```
-->

## Risk / Band

<!-- AUTO | SOFT-ACK | ESCALATE per rules/agency-bands.md, plus one line of
justification (reversibility, blast radius, input trust). -->

## Rollback

<!-- How this change can be reverted if it turns out to be wrong. -->

## Local IMP ID (optional — submitter's own reference only)

<!-- e.g. IMP-042, if you have one — for your own tracking only, not
checked further on submission. -->
