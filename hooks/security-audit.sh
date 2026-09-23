#!/bin/bash
# Security Audit Hook — PreToolUse on Edit/Write
# Scans content being written/edited for secret patterns and blocks if found.
# Ported from ~/.cursor/hooks/security-audit.sh on 2026-05-24.
# Triggered by the 2026-05-24 finding of github_pat_* file on an external volume.
# Exit codes: 0 = allow, 2 = block.

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
# Edit uses new_string, Write uses content
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')

# No content to inspect → allow
[[ -z "$CONTENT" ]] && exit 0

LOG=~/.claude/global-observation/security-audit.log
mkdir -p "$(dirname "$LOG")"

# Whitelisted paths — these are expected to legitimately contain secret-like strings
# (e.g., gitignored .env files, example configs, this hook's own pattern definitions)
if [[ "$FILE_PATH" =~ \.env(\.|$) ]] || \
   [[ "$FILE_PATH" =~ /secrets/ ]] || \
   [[ "$FILE_PATH" =~ /\.aws/credentials ]] || \
   [[ "$FILE_PATH" =~ claude-framework-consolidation/01-sources/ ]] || \
   [[ "$FILE_PATH" =~ /security-audit\.sh$ ]] || \
   [[ "$FILE_PATH" =~ /SECURITY-ACTIONS\.md$ ]] || \
   [[ "$FILE_PATH" =~ /TRIAGE-RESULTS\.md$ ]]; then
    exit 0
fi

ISSUES=""

# GitHub Fine-Grained PAT (the format found in the 2026-05-24 audit)
if echo "$CONTENT" | grep -qE 'github_pat_[A-Za-z0-9_]{82}'; then
    ISSUES+="GitHub Fine-Grained PAT (github_pat_*). "
fi

# GitHub Classic PAT (ghp_/ghs_ prefix + 36 chars)
if echo "$CONTENT" | grep -qE 'gh[ps]_[A-Za-z0-9]{36}'; then
    ISSUES+="GitHub Classic PAT (gh[ps]_*). "
fi

# AWS Access Key (AKIA + 16 alphanumeric uppercase)
if echo "$CONTENT" | grep -qE 'AKIA[0-9A-Z]{16}'; then
    ISSUES+="AWS Access Key (AKIA*). "
fi

# OpenAI / Anthropic / Stripe (sk- prefix + 32+ chars)
if echo "$CONTENT" | grep -qE 'sk-[A-Za-z0-9_-]{32,}'; then
    ISSUES+="OpenAI/Anthropic/Stripe key (sk-*). "
fi

# Google API key (AIza + 35 chars)
if echo "$CONTENT" | grep -qE 'AIza[A-Za-z0-9_-]{35}'; then
    ISSUES+="Google API key (AIza*). "
fi

# Slack token (xox[abps]- + chars)
if echo "$CONTENT" | grep -qE 'xox[abps]-[A-Za-z0-9-]{10,}'; then
    ISSUES+="Slack token (xox*-*). "
fi

# Firecrawl API key (fc- prefix, 20+ chars) — added 2026-05-27 after Firecrawl key leak incident
if echo "$CONTENT" | grep -qE 'fc-[a-zA-Z0-9_-]{20,}'; then
    ISSUES+="Firecrawl API key (fc-*). "
fi

# Generic hardcoded secret pattern (api_key/password/token/secret = "20+ chars")
if echo "$CONTENT" | grep -qiE '(api[_-]?key|password|secret|token|auth[_-]?key)[[:space:]]*[:=][[:space:]]*["\047][A-Za-z0-9+/=_-]{20,}["\047]'; then
    ISSUES+="Hardcoded credential literal. "
fi

# Firebase config exposed in non-config file
if [[ ! "$FILE_PATH" =~ (config|env|firebase) ]] && echo "$CONTENT" | grep -qE 'apiKey.*authDomain.*projectId'; then
    ISSUES+="Firebase config exposed outside config file. "
fi

if [[ -n "$ISSUES" ]]; then
    TS=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$TS] SECRET PATTERN in $FILE_PATH ($TOOL_NAME): $ISSUES" >> "$LOG"
    cat >&2 <<EOF
🔒 BLOCKED: Secret pattern detected in edit
  File: $FILE_PATH
  Pattern: $ISSUES
  Move secrets to: .env (gitignored), Keychain, or env vars
  Logged: $LOG
EOF
    exit 2
fi

exit 0
