---
name: create-hook
description: "Create Claude Code hooks. Use when the user wants to create a hook, register a hook in settings.json, add lifecycle automation (SessionStart, PreToolUse, PostToolUse, Stop), gate or audit tool calls, or block specific commands. Asks for missing requirements, then creates the hook script + registration."
context: fork
model: sonnet
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Creating Claude Code Hooks

Claude Code hooks run shell scripts at specific lifecycle events. They exchange JSON over stdin/stdout and can observe, block, modify, or follow up on agent behavior.

When the user asks for a hook, gather missing requirements first, then create both the hook script and the registration in `settings.json`.

## Gather Requirements

Before writing anything, determine:

1. **Scope**: User-global (`~/.claude/hooks/`) or project-scoped (`.claude/hooks/`)?
2. **Event**: Which lifecycle event should fire the hook?
3. **Behavior**: Audit only, block, rewrite input, inject context, or warn?
4. **Matcher**: Should it only run for specific tools / commands / file patterns?
5. **Safety**: Fail-open (allow on error) or fail-closed (block on error)?

Infer from conversation when possible; ask only for the missing pieces.

## Choose the Location

| Scope | Path | When to Use |
|-------|------|-------------|
| User-global | `~/.claude/hooks/` + `~/.claude/settings.json` | Personal defaults across all projects |
| Project | `.claude/hooks/` + `.claude/settings.json` | Project-specific, version-controlled, shared with team |

Prefer **project hooks** when the behavior should be reproducible for collaborators.

## Choose the Event

Use the narrowest event that matches the user's goal.

### Common Lifecycle Events

| Event | When It Fires | Typical Use |
|-------|--------------|-------------|
| `SessionStart` | At session begin | Context loading, identity checks, env setup |
| `SessionEnd` / `Stop` | At session end | Cleanup, metrics, save state |
| `UserPromptSubmit` | After user submits a prompt | Validate prompt, inject context |
| `PreToolUse` | Before any tool runs | Gate/block dangerous calls (Bash, Edit, etc.) |
| `PostToolUse` | After a tool succeeds | Audit, capture signals, follow-up |
| `PostToolUseFailure` | After a tool fails | Error logging, retry logic |
| `Notification` | When Claude sends a notification | External alerts |

### Quick Event Chooser

- **Block dangerous bash commands** → `PreToolUse` with `Bash` matcher
- **Audit edits** → `PostToolUse` with `Edit|Write` matcher
- **Inject project context at start** → `SessionStart`
- **Capture metrics at end** → `Stop`
- **Validate prompts for secrets** → `UserPromptSubmit`

## Hook Registration Format

Hooks are registered in `settings.json` under the `hooks` key:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/guard-unsafe.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/observation-capture.sh" }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/session-start-context.sh" }
        ]
      }
    ]
  }
}
```

Each entry can include:
- `matcher`: Regex against tool name (e.g., `Bash`, `Edit|Write`, `mcp__.*`)
- `hooks[]`: Array of hook scripts to run
- `type`: `"command"` for shell scripts (default)
- `command`: Absolute path or `~/`-relative path

## Hook Script Format

Hook scripts receive JSON on stdin via the standard Claude Code hook input schema:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf /tmp/foo"
  }
}
```

Scripts exit with:
- **0** — allow (success); stdout may contain JSON with additional context
- **2** — block (deny with feedback to user)
- **Other** — non-blocking error (depends on `failClosed` setting)

### Minimal Example: Block Destructive `rm` Commands

```bash
#!/bin/bash
# ~/.claude/hooks/block-rm-rf-root.sh
# Blocks rm -rf on root-level paths

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ -z "$COMMAND" ]]; then
    exit 0  # not a Bash command, allow
fi

# Block rm -rf on /, ~, $HOME (paranoid default)
if [[ "$COMMAND" =~ rm[[:space:]]+-rf[[:space:]]+(/|~|\$HOME) ]]; then
    echo "BLOCKED: Destructive rm -rf on critical path" >&2
    exit 2
fi

exit 0
```

Register:
```json
"PreToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      { "type": "command", "command": "~/.claude/hooks/block-rm-rf-root.sh" }
    ]
  }
]
```

Make executable: `chmod +x ~/.claude/hooks/block-rm-rf-root.sh`

## Regex Pitfalls (read this!)

Bash regex does **not** support `\b` (word boundary). Use anchoring:

```bash
# BAD — matches "rsync -a" because "nc " is a substring of "rsync -"
if [[ "$COMMAND" =~ (nc|netcat|ncat)[[:space:]] ]]; then

# GOOD — anchors to start-of-string or whitespace
if [[ "$COMMAND" =~ (^|[[:space:]])(nc|netcat|ncat)[[:space:]] ]]; then
```

The fix above is the actual fix applied to `~/.claude/hooks/guard-unsafe.sh:96` on 2026-05-24 after a false-positive blocked `rsync` operations.

## Verify Dependencies

Before finishing, verify that every binary the script uses exists on the hook environment's `$PATH`:

```bash
command -v jq || echo "jq not found — install with brew install jq"
command -v python3 || echo "python3 not found"
```

Hooks run in a stripped environment — don't assume aliases or shell functions are available.

## Implementation Workflow

1. **Pick scope** (user vs. project)
2. **Pick event** (use the narrowest that matches the goal)
3. **Create the script** at `~/.claude/hooks/<name>.sh` or `.claude/hooks/<name>.sh`
4. **Add shebang** (`#!/bin/bash`) and `chmod +x`
5. **Read stdin JSON** with `jq -r '.tool_input.command'` (or relevant field)
6. **Implement logic** — keep deterministic; exit 0 (allow) or 2 (block)
7. **Register in settings.json** under correct event + matcher
8. **Verify dependencies** (`command -v jq` etc.)
9. **Test with a fake stdin**:
   ```bash
   echo '{"tool_input":{"command":"test"}}' | ~/.claude/hooks/your-hook.sh
   echo "exit: $?"
   ```

## Testing Pattern

Write a test script that exercises edge cases:

```bash
#!/bin/bash
# /tmp/hook-test.sh
HOOK=~/.claude/hooks/your-hook.sh
PASS=0; FAIL=0

run_test() {
  local cmd="$1" expected="$2" label="$3" actual
  printf '{"tool_input":{"command":"%s"}}' "$cmd" | "$HOOK" >/dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "PASS [$label]"; PASS=$((PASS+1))
  else
    echo "FAIL [$label]: expected $expected, got $actual"; FAIL=$((FAIL+1))
  fi
}

run_test "ls /tmp" 0 "allow-ls"
run_test "rm -rf /" 2 "block-rm-rf"
# ... add more cases ...

echo "Passed: $PASS / Failed: $FAIL"
```

Run from outside the Claude session so the test commands themselves don't trigger the hook.

## Common Hook Patterns

### Audit Edits to JSONL
```bash
# PostToolUse with matcher: "Edit|Write"
LOG=~/.claude/signals.jsonl
INPUT=$(cat)
echo "$INPUT" | jq -c '{ts: now, tool: .tool_name, file: .tool_input.file_path}' >> "$LOG"
exit 0
```

### Inject Context at Session Start
```bash
# SessionStart, no matcher
echo '{"additionalContext": "Current branch: '"$(git branch --show-current 2>/dev/null)"'"}'
exit 0
```

### Block Secret Patterns in Edits
```bash
# PreToolUse with matcher: "Edit|Write"
INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')
if echo "$CONTENT" | grep -qE "github_pat_|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{32,}"; then
  echo "BLOCKED: secret pattern detected in edit" >&2
  exit 2
fi
exit 0
```

## Final Checklist

- [ ] Correct scope (user vs. project)
- [ ] Correct event chosen (narrowest match)
- [ ] Matcher tested with realistic inputs
- [ ] Script is executable (`chmod +x`)
- [ ] Exits 0 (allow) or 2 (block) — no silent failures
- [ ] Regex uses bash-compatible patterns (no `\b`)
- [ ] All dependencies (`jq`, `python3`, etc.) verified on `$PATH`
- [ ] Registered in correct `settings.json`
- [ ] Tested with multiple input cases
- [ ] If failClosed needed → script catches all errors and exits 2 on failure

## Related Skills

- `[[create-rule]]` — for declarative rules instead of scripted hooks
- `[[create-skill]]` — for full-featured Skills (more powerful than hooks)
- `[[migrate-to-skills]]` — for porting old hook scripts to skill format
