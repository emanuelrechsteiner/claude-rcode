# Agent Work Cache

Session-specific shared state between agents. Contents are ephemeral — cleared between sessions.

## Directories

- `research/` — Research agent outputs (reused by other agents to avoid duplication)
- `decisions/` — Planning agent decisions (consumed by implementation agents)
- `implementations/` — Implementation progress notes (consumed by testing/review)

## Protocol

1. Before researching, check `research/` for existing results
2. Before deciding, check `decisions/` for prior decisions
3. After completing work, write a summary to the appropriate directory