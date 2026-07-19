# Test fixtures

## sample_session.jsonl

Hand-crafted minimal Claude JSONL with known counts:
- 1 file-history-snapshot
- 1 user prompt with "Bitte fix den Bug"
- 1 last-prompt entry mirroring above
- 1 assistant turn: thinking + text + tool_use(Bash, "npm test")
- 1 user turn with tool_result (is_error=true, "FAIL")
- 1 assistant turn: tool_use(Edit, file=/tmp/test.ts, old=foo, new=bar)
- 1 user turn with tool_result (is_error=false, "OK")
- 1 assistant turn: tool_use(Bash, "npm test")
- 1 user turn with tool_result (is_error=false, "PASS")

Expected counts after ingestion:
- sessions: 1
- tool_uses: 3 (Bash, Edit, Bash)
- tool_results: 3
- edits: 1
- prompts: 1
- The prompt should classify as intent="fix" based on "fix den Bug"
- The Edit's old_string_len=3, new_string_len=3, is_rewrite=0
