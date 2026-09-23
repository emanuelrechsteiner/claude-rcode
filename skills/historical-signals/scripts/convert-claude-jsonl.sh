#!/bin/bash
# convert-claude-jsonl.sh — Convert one Claude Code session JSONL → signals.jsonl format
#
# Usage: convert-claude-jsonl.sh <claude-jsonl-file>
# Stdout: one signal per line (JSON), signals.jsonl schema + "source" field
# Stderr: parse errors and skip warnings
# Exit 0 on success or recoverable skip; 1 on missing input
#
# Improvements over /tmp prototype (Phase B 2026-05-24):
#  1. Per-tool-use intent inference (not session-level)
#  2. cwd derivation walks up from first file_path (fixes underscore-mangling bug)
#  3. Source attribution via "source" field
#  4. Graceful handling of malformed JSONL

set -u

JSONL="${1:-}"
if [[ -z "$JSONL" ]]; then
    echo "usage: $0 <claude-jsonl-file>" >&2
    exit 1
fi

if [[ ! -f "$JSONL" ]]; then
    echo "[error: file not found: $JSONL]" >&2
    exit 1
fi

SOURCE="${HISTORICAL_SIGNAL_SOURCE:-claude_jsonl_historical}"

# === Step 1: Find first file_path used by any Edit/Write tool_use ===
FIRST_FILE=$(
    jq -r '
      select(.type == "assistant" and (.message.content | type) == "array") |
      .message.content[]? |
      select(.type == "tool_use" and
             (.name == "Edit" or .name == "Write" or
              .name == "MultiEdit" or .name == "NotebookEdit")) |
      (.input.file_path // .input.notebook_path // empty)
    ' "$JSONL" 2>/dev/null | awk 'NF' | head -1
) || FIRST_FILE=""

# === Step 2: Derive cwd by walking up the directory tree ===
derive_cwd() {
    local file="$1"

    if [[ -z "$file" ]]; then
        local project_name
        project_name=$(basename "$(dirname "$JSONL")")
        echo "$project_name" | sed 's|^-|/|; s|-|/|g'
        return
    fi

    local d
    d=$(dirname "$file")
    while [[ "$d" != "/" && "$d" != "." && -n "$d" ]]; do
        if [[ -d "$d/.git" || -f "$d/package.json" || -d "$d/.claude" || \
              -d "$d/.rcode" || -f "$d/Package.swift" ]]; then
            echo "$d"
            return
        fi
        if ls "$d"/*.xcodeproj >/dev/null 2>&1; then
            echo "$d"
            return
        fi
        d=$(dirname "$d")
    done

    dirname "$file"
}

CWD=$(derive_cwd "$FIRST_FILE")

# === Step 3: R.Code detection from content ===
RCODE="false"
if grep -qE '(\.rcode|/issue|/phase-gate|/decompose|/brainstorm|PROJECT-STATUS\.md)' "$JSONL" 2>/dev/null; then
    RCODE="true"
fi

# === Step 4: Convert with per-tool-use intent inference ===
ERR_FILE="/tmp/historical-signals-err-$$"
trap "rm -f $ERR_FILE" EXIT

# Intent context: look back up to 30 entries for the most recent user-typed prompt.
# Claude JSONLs interleave many non-user entry types (file-history-snapshot, attachment,
# last-prompt, ai-title, system) between user message and first tool_use, so a small
# window misses the prompt. We accept entries of type "last-prompt" (.lastPrompt field)
# OR "user" (.message.content), and skip system-injected boilerplate like
# <local-command-caveat> and <command-name>.

jq -c --slurp \
   --arg cwd "$CWD" \
   --arg source "$SOURCE" \
   --argjson rcode "$RCODE" '
  . as $all |
  $all | to_entries[] |
  .key as $idx |
  .value |
  select(.type == "assistant" and (.message.content | type) == "array") |
  .timestamp as $ts |

  ([
    $all[(if $idx < 30 then 0 else $idx - 30 end):$idx] |
    .[] |
    if (.type == "last-prompt" and (.lastPrompt // null) != null) then
      .lastPrompt
    elif (.type == "user") then
      (if (.message.content | type) == "string" then .message.content
       elif (.message.content | type) == "array" then
         ([.message.content[]? | select(.type == "text") | .text] | join(" "))
       else "" end)
    else empty end
  ] | reverse |
     map(select(. != "" and . != null and
                (test("<local-command-caveat>") | not) and
                (test("<command-name>") | not))) | .[0] // "") as $ctx_raw |
  ($ctx_raw | ascii_downcase) as $ctx |

  # Map keywords to intent buckets (EN + common DE word-stems).
  # Only leading \b — no trailing \b — so stems match all conjugations
  # (entwickl → entwickle/entwickeln/entwicklung; behebe → behebt/beheben; etc.)
  (if   ($ctx | test("\\b(fix|bug|hotfix|repair|broken|crash|error|fail|issue|fehler|behoben|behebe|repariere|kaputt|defekt|wirft)")) then "fix"
   elif ($ctx | test("\\b(refactor|restructure|cleanup|extract|simplif|reorganiz|umstrukturier|aufrau|verein|verschön)")) then "refactor"
   elif ($ctx | test("\\b(add|implement|creat|new|build|feature|entwickl|develop|baue|hinzuf|implementi|erstell)")) then "feature"
   else "edit" end) as $intent |

  .message.content[]? |
  select(.type == "tool_use" and
         (.name == "Edit" or .name == "Write" or
          .name == "MultiEdit" or .name == "NotebookEdit")) |
  {
    ts: $ts,
    cwd: $cwd,
    intent: $intent,
    file: (.input.file_path // .input.notebook_path // ""),
    branch: "",
    rcode: $rcode,
    source: $source
  }
' "$JSONL" 2>"$ERR_FILE"

# Skip warning only when jq wrote something to stderr.
# Exit code alone is unreliable (141 = SIGPIPE from caller piping to `head -3`).
if [[ -s "$ERR_FILE" ]]; then
    ERR_HEAD=$(head -1 "$ERR_FILE")
    echo "[skip: $(basename "$JSONL") — $ERR_HEAD]" >&2
fi

exit 0
