# Claude Code: personal configuration (R.Code)

<!--
Maintainer notes (block comments are stripped before this file reaches the model).
- This file loads in every session of every project. Keep it to what cannot be read from a repository and is not carried by a hook message, a skill description or a reference file. Target: well under 200 lines.
- Counts are generated, never written by hand: scripts/framework-inventory.sh.
- The section "graphify" at the end is owned by the graphify tool and is overwritten by it. Put nothing that matters into it. `graphify claude install` has no global mode: it writes ./CLAUDE.md and ./.claude/settings.json in the current directory only.
- Long form, history and inventory: docs/FRAMEWORK-REFERENCE.md and HARNESS.md.
-->

This file and the rules next to it apply in every project on this machine. They hold what cannot be read from a repository. Project-specific knowledge belongs in that project's own CLAUDE.md.

## How this setup is organized

- **Rules** (`~/.claude/rules/`): four short rules load in every session: `foundation`, `agency-bands`, `slop-prevention`, `workflow-git`. The other rules are path-scoped and load when a matching file is read or edited. Files named `*.local.md` are the owner's personal preferences; where they are stricter or more specific than a framework rule, they decide.
- **Reference** (`~/.claude/docs/reference/`): the long form behind the rules (decision tables, gate mechanics, examples). Read the matching file when a rule points there or when the short text does not cover a case. Inventory, hook table, override switches, routines and history: `~/.claude/docs/FRAMEWORK-REFERENCE.md`.
- **Skills, commands and agents** load on demand. Their descriptions say when they apply.
- **Hooks** stop what must not happen by accident: the common irreversible operations, secrets in files, writes to protected paths. They cover less than the rules do, so a command that no hook stopped is not thereby allowed. When a hook blocks or asks, its message says what to do next. Follow that message; do not reach the same effect another way.
- **Knowledge library**: reusable findings from earlier sessions across all projects. Hits for the current prompt are added to the context automatically. Before work in an area that is new to this session, search it yourself: `bash ~/.claude/scripts/knowledge-lookup.sh --stack`, or pass two to four keyword sets (your own words, the German or English translation, the technical terms).

## R.Code projects

A project with a `.rcode/` folder is managed with R.Code. Work there starts through `/team-lead "<directive>"`, which picks the Stage (Plan, Design, Develop, Test, Launch) and loads its playbook. `/continue` resumes interrupted work, `/handoff` writes the hand-over, `/rcode-onboard` gives the orientation. Going back to an earlier Stage needs a written futility proof (`~/.claude/rcode/stages/backward-transitions.md`). The project's own CLAUDE.md and `.claude/rules/` carry the details.

## Changing this configuration

The configuration is developed in a separate working copy (the workshop) and reaches `~/.claude` only through `claude-deploy` (working rules: `docs/WORKING-IN-THIS-REPO.md` in the working copy). Do not edit files under `~/.claude` by hand, apart from the git-ignored `*.local.md` overlays: a guard blocks writes to the deployed parts and names the working copy. A change takes effect only in a new session after the deploy, so it cannot be tested in the session that made it: run what can be run directly (hook scripts with their input on stdin, the test suites, `jq . settings.json`), report the rest as not verified, and list what the owner should check. Tracked files are published: keep secrets, account names and home paths out of them, `settings.json` included.

## graphify

A knowledge graph may exist at `graphify-out/` (god nodes, community structure, cross-file relationships) — **only in projects where `graphify .` has actually been run.** Check for `graphify-out/graph.json` before assuming one is present; do not hunt for it otherwise.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
