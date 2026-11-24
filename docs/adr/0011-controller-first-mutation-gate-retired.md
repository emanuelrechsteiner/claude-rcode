# 0011 — Retire the controller-first mutation gate

- Status: accepted
- Date: 2026-11-10

## Context

IMP-090 (2026-07-15) added a deterministic backstop to the controller-first
principle. A prompt hook (`hooks/controller-first-prompt-gate.sh`) marked a
session as substantial; from then on a PreToolUse hook
(`hooks/controller-first-mutation-gate.sh`) checked every Write, Edit and
mutating Bash call for a session flag saying that a controller step had run; a
SubagentStop hook (`hooks/controller-first-subagent-flag.sh`) set that flag.
The gate shipped in note mode, with hard enforcement (exit 2) pending a
measured low false-positive rate.

Measured on 2026-11-10 over the gate's whole logged history, the daily archives
`~/.claude/global-observation/archives/controller-first-*.jsonl.gz` (2026-07-15
to 2026-08-20) plus the current `~/.claude/global-observation/controller-first.log`
(from 2026-08-22): 49,390 note entries in 218 sessions and no block. The unlock
flag was set in two sessions, 7 times on 2026-08-09 and 10 times on 2026-09-01;
compliant entries (logged since 2026-08-01, one in ten sampled) exist for the
first of them only, 25 on 2026-08-09. The current log file alone holds 34,969
notes in 187 sessions, about 440 a day. Three defects explain the numbers.

1. The note never reached the model. A PreToolUse hook that exits 0 has its
   stderr written to the log only (code.claude.com/docs/en/hooks.md, read
   2026-11-10).
2. The unlock could not see the framework's main entrance. The flag hook set
   the flag only when a finished sub-agent had the `agent_type`
   `control-agent`, while `commands/team-lead.md` tells the lead not to
   dispatch control-agent as a sub-agent. In an isolated probe the flag stayed
   unset after backend-agent, testing-agent, knowledge-agent, Explore and
   general-purpose had finished; only a control-agent stop set it. The log
   therefore counted how often the detector could not see a controller step,
   not how often one was skipped. In the audit session of 2026-11-10 the gate
   logged more than 340 notes although every unit of work was dispatched
   through `/team-lead` (more than 40 sub-agents); the notes cover the lead's
   and the workers' calls alike.
3. The signal for "substantial" was a word list applied to every submitted
   text. In that session the owner's directive did not match it; the session
   was marked about seven minutes later by a sub-agent hand-back, and all 36
   visible reminders counted at that point followed automated turns.

In enforce mode the gate as built exits 2 on the first non-exempt mutation of a
session marked substantial, and no step available to `/team-lead` sets the
unlock: the lead and every worker would be stopped.

The audit branch had already unregistered the gate and the flag hook
(IMP-285). The owner was offered two options: retire the gate, or rebuild it.

## Decision

The owner decided on 2026-11-10 to retire the mutation gate of IMP-090 and its
SubagentStop flag hook. Neither is registered in `settings.json`;
`CLAUDE_CONTROLLER_GATE_MODE` is removed from its `env` block; the prompt hook
no longer writes or reads session state for them. What stays: `/team-lead` as
the controller entrance, the command-contract layer of IMP-089 (preamble,
model pin, linter), the prompt reminder (once per session, silent on automated
turns, naming `/team-lead`), and the dispatch checks
(`hooks/dispatch-specialist-check.sh`, `hooks/knowledge-brief-check.sh`). The
two retired scripts and their regression cases stay in the repo as history and
must not be re-registered as built.

## Consequences

Easier: one hook run fewer on every Write, Edit and Bash call; the log stops
growing; no backstop is counted as working that never acted.

Harder: a session that does not start through `/team-lead` has no deterministic
backstop if the model ignores the reminder and the delegate-by-default rule.
That was already so in practice, since the gate never acted.

A rebuild needs three changes, not one: an unlock that recognises `/team-lead`
and its Stage aliases, or any completed delegation; a signal the model
receives (`additionalContext`, or exit 2); and a signal for a substantial task
that is not a word list over every submitted text. Switching the existing
script to enforce mode is not a rebuild.

Ledger: IMP-285 records the audit finding and this decision. On its promotion
IMP-090 is to be marked deprecated with a pointer to this record; IMP-089
stays implemented.

Rejected alternatives: re-register the gate in note mode (it keeps writing
notes that reach nobody); switch it to enforce mode as built (it stops
`/team-lead` sessions); rebuild it now (the cost of a new detection and unlock
design for a step that `/team-lead` already performs).
