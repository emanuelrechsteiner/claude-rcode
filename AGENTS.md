# Agents — read this first

This repo is the configuration of Claude Code itself and exists in
**two** places. Before any change, run `pwd` to find out where you are:

| Path | Place | Rule |
|---|---|---|
| `…/claude-code-config` | **Workshop** | Change and commit here. Nothing here is live. |
| `~/.claude` | **Live install** | What Claude Code reads. **Do not edit by hand** — only `claude-deploy` writes here. Exception: git-ignored `rules/*.local.md` overlays are machine-local and edited in place. |

Three rules:

1. **Changes go in the workshop only.**
2. **You cannot verify your own work in your own session** —
   Claude Code reads rules, hooks, and skills at session start. Never
   claim "it works" — write an acceptance protocol for the user instead.
3. **Verify what's verifiable without a deploy:** call hook scripts directly,
   `jq . settings.json`, run the regression suites under `hooks/tests/`.

**Full workshop conventions: [`docs/WORKING-IN-THIS-REPO.md`](docs/WORKING-IN-THIS-REPO.md)**
— also covers the example commands for hook testing and the format of
the acceptance protocol.
