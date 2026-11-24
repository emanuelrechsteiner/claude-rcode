# Foundation

> How work is organized in this setup. Always loaded. Long forms: `~/.claude/docs/reference/delegation.md` (helpers, agent selection, model tiers, parallel work) and `~/.claude/docs/reference/tools.md` (tool notes).

## Working directly or with helpers

Decide per task. Work directly when the task is small, sequential, or needs context you already hold: a fresh subagent has to rebuild that context first and does not give a better answer than you would. You always do these yourself, also when a preference file makes delegation the default for larger work: a single-file edit or a small mechanical change, a task of about two minutes, a question or an explanation. Use subagents when units are independent and can run in parallel, when the output is long and you only need the conclusion (wide searches, test runs, audits), or when you want a reviewer that has not seen your reasoning.

When you delegate:

- Pick the agent whose description fits the unit; `Explore` only reads and runs nothing that changes state. Pass `model` and `effort` on every Agent call, because a spawn without them can inherit the caller's model. Helpers start on `haiku`. A unit moves to a higher tier when its named check failed on the lower one, also after one retry at a higher effort, and that failure is written down where a later reader finds it.
- Write a brief the helper can act on without your conversation: the files or sources by absolute path (point at the source, do not paraphrase it), what is wrong or wanted, what you measured, the check that decides whether the result stands, and what is not part of the task. Quote an explicit user instruction about how the work is to be done word for word; a helper that thinks such an instruction is wrong reports back and stops, it does not replace it. Knowledge-library notes that fit the unit go into the brief with their paths. The form is `~/.claude/templates/auftragsbrief.md.template`.
- Send independent units to several helpers in one message. Helpers that write at the same time need disjoint file sets or their own worktree (`parallel-dispatch` skill).
- A helper's "done" is a claim. Check its result against the unit's check before you build on it or report it.
- Helpers report operations that need the user's approval to you. You ask the user once per operation (see `agency-bands`).

For work that spans several agents or waves, `/team-lead` and `~/.claude/agents/control-agent.md` hold the full procedure.

A build that spans several units runs in order: research and plan, design where it has a user interface, implementation, checks. Do not start a step while the type check, the tests or the build of the previous one fail. Agents per step: `~/.claude/docs/reference/delegation.md` (Larger builds).

## Scope, knowledge and decisions

- Stay inside the request or the work unit. Propose a useful extra instead of adding it; record a detour before you take it when a goal plan is running.
- Before work in an area that is new to this session, search the knowledge library (see CLAUDE.md). Open a note only when its summary line fits.
- Before you integrate a library, SDK or cloud service you have not used in this session, fetch its current documentation (Context7 or the vendor's site) instead of writing from memory, and check the exact export and adapter names against it before you write imports. A claim that something does not exist carries the date of its source; when the user doubts it, check live before you answer again.
- When the user gives a categorical correction ("never X", "always X"), write it down in the same turn, without asking first, then continue the task: a correction that lives only in the chat is gone in the next session. About one codebase it goes into that project's CONTEXT.md, an ADR or the project memory. About how the user works with you it goes into `~/.claude/rules/preferences.local.md`; before you write a project memory, look for the same stance in other projects' memories (`~/.claude/projects/*/memory/`), because a hit there means it belongs in the preferences file, with a one-line pointer left in the project copy. Where the correction can be checked mechanically, add the test that would have caught the violation. A second identical correction means the first one was not persisted; treat it as a defect of the process, not as a reminder.
- A decision someone may later ask "why?" about gets an ADR (`docs/adr/NNNN-slug.md`). A term defined in a project's CONTEXT.md is binding in conversation, identifiers, file names and commit messages.

## Asking and acting

- When you ask the user something or offer options, lead with the option you would choose and one sentence on why it fits this situation. If the options are equivalent, say so. For the approval of an irreversible operation state the safe default and leave the decision open.
- Before you edit a file you have not read in this session, read it; for code also look for its importers or callers. Check that the planned change matches what the user asked for.
- Before a bulk file operation (moving, copying or creating many files) name the target path in one line, and afterwards check that no duplicate tree was left behind. When two repositories or folders have similar names, compare modification time and size and say which one you chose and why.
