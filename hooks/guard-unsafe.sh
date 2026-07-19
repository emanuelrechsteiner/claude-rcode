#!/bin/bash
# Guard against potentially unsafe operations
# This hook validates commands before execution
# Exit codes: 0 = allow, 2 = block
#
# Behavior on block (2026-06-05 redesign):
#   When a command is blocked, the agent MUST NOT route around the guard by
#   using an equivalent tool/language (e.g. python urllib instead of curl).
#   Instead it must report to the user, verbatim, what it intended to do and
#   ask for explicit permission. The block() footer instructs this.
#
# One-shot approval:
#   After the user approves, re-run the SAME command with CLAUDE_GUARD_OVERRIDE=1
#   prepended (e.g. `CLAUDE_GUARD_OVERRIDE=1 curl -d ... https://...`). The guard
#   recognizes the inline token and allows that single invocation (logged). This
#   is NOT a persistent bypass — it must be present on each approved command.

# Read JSON input from stdin
INPUT=$(cat)

# Extract command from tool_input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# If no command, allow (not a Bash command)
if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Log file for override usage
GUARD_LOG="$HOME/.claude/global-observation/guard-overrides.log"

# =============================================================================
# ONE-SHOT APPROVAL — user-granted override for a single invocation
# =============================================================================
# The agent prepends CLAUDE_GUARD_OVERRIDE=1 as the FIRST token of the command,
# only AFTER the user explicitly approved the specific command it described.
# IMP-051: anchor the token to command-START so it authorizes exactly ONE command,
# not a whole script. `export CLAUDE_GUARD_OVERRIDE=1` on line 1 of a multi-line
# block (the old session-wide bypass) no longer matches, and a command that merely
# MENTIONS the token (echo/grep/comment) no longer false-logs an OVERRIDE-ALLOWED.
if [[ "$COMMAND" =~ ^[[:space:]]*CLAUDE_GUARD_OVERRIDE=1[[:space:]] ]]; then
    mkdir -p "$(dirname "$GUARD_LOG")" 2>/dev/null
    printf '%s\tOVERRIDE-ALLOWED\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$COMMAND" >> "$GUARD_LOG" 2>/dev/null
    echo "NOTE: guard-unsafe override token present — allowing this single user-approved invocation (logged)." >&2
    exit 0
fi

# IMP-051: detect the OLD bare `export CLAUDE_GUARD_OVERRIDE=1` bypass attempt and
# warn (it no longer disarms the guard). Non-blocking hint; the real command is
# still classified normally below.
if [[ "$COMMAND" =~ (^|[[:space:]\;\&\|])export[[:space:]]+CLAUDE_GUARD_OVERRIDE=1 ]]; then
    echo "NOTE: 'export CLAUDE_GUARD_OVERRIDE=1' no longer grants a script-wide bypass (IMP-051). Prepend 'CLAUDE_GUARD_OVERRIDE=1 ' to the SINGLE command you want allowed." >&2
fi

# =============================================================================
# block() — emit a standardized block message and exit 2
# =============================================================================
# Usage: block "<one-line reason>" ["<optional extra body>"]
# The footer is identical for every block so the agent always sees the same
# instruction: do NOT work around it, report intent, ask permission.
block() {
    local reason="$1"
    local extra="$2"
    {
        echo "BLOCKED: $reason"
        if [[ -n "$extra" ]]; then
            echo "$extra"
        fi
        echo ""
        echo "──────────────────────────────────────────────────────────────"
        echo "DO NOT work around this block."
        echo "Specifically: do NOT achieve the same effect with a different"
        echo "tool or language (e.g. python/node/wget instead of curl, or a"
        echo "pipe/heredoc to dodge a file-read rule)."
        echo ""
        echo "Instead, STOP and do exactly this:"
        echo "  1. Tell the user, verbatim, the command you were about to run."
        echo "  2. Explain in one line what it would do and why you wanted it."
        echo "  3. Ask for explicit permission to proceed."
        echo ""
        echo "If the user approves, re-run the SAME command with"
        echo "  CLAUDE_GUARD_OVERRIDE=1  prepended (one-shot, logged)."
        echo "──────────────────────────────────────────────────────────────"
    } >&2
    exit 2
}

# =============================================================================
# CRITICAL BLOCKERS - These commands are never allowed
# =============================================================================

# Destructive file system operations
#
# IMP-103: disposable-temp carve-out. This arm blocks a recursive force-delete of
# ANY absolute path, which also caught the session scratchpad (/private/tmp/claude-501/…)
# and every /tmp target — so a sub-agent could not clean up after itself. Because this
# arm runs FIRST in the PreToolUse|Bash chain, it also made the excessive-agency-gate's
# temp allowlist (IMP-059 glob-under-tmp, IMP-102 resolved roots) unreachable for
# absolute targets: the floor blocked them before that gate ever ran.
#
# Exempt ONLY the exact disposable temp roots, incl. their macOS-resolved /private
# forms. /private itself is NOT a temp root — /private/etc and /private/var/db stay
# blocked. Any target containing '..' stays blocked (traversal climbs out of the temp
# root). The bare-wildcard arm below is untouched.
_rm_disposable_temp() {   # $1 = target → 0 when disposable temp, 1 otherwise
    case "$1" in
        *..*)                                                     return 1 ;;
        /tmp|/tmp/*|/private/tmp|/private/tmp/*)                  return 0 ;;
        /var/tmp|/var/tmp/*|/private/var/tmp|/private/var/tmp/*)  return 0 ;;
        /var/folders/*|/private/var/folders/*)                    return 0 ;;
        *)                                                        return 1 ;;
    esac
}

if [[ "$COMMAND" =~ rm[[:space:]]+-rf[[:space:]]+(/|~|\$HOME) ]]; then
    # Classify EVERY target this arm governs, not just the one that matched: a
    # command may carry several (`rm -rf /tmp/foo && rm -rf /etc`), and the
    # exemption may only apply when ALL of them are disposable.
    _rm_critical=0
    while IFS= read -r _rm_target; do
        [[ -z "$_rm_target" ]] && continue
        case "$_rm_target" in
            /*|'~'|'~/'*|'$HOME'*|'${HOME}'*) ;;  # governed by this arm
            *) continue ;;                         # relative → never was this arm's concern
        esac
        if ! _rm_disposable_temp "$_rm_target"; then
            _rm_critical=1
        fi
    done < <(printf '%s' "$COMMAND" \
             | grep -oE 'rm[[:space:]]+-rf[[:space:]]+[^[:space:];&|]+' \
             | sed -E 's/^rm[[:space:]]+-rf[[:space:]]+//')

    if [[ "$_rm_critical" -eq 1 ]]; then
        block "Destructive rm -rf on critical path"
    fi
fi

if [[ "$COMMAND" =~ rm[[:space:]]+-rf[[:space:]]+\* ]]; then
    block "Destructive rm -rf with wildcard"
fi

# Privilege escalation
if [[ "$COMMAND" =~ ^sudo[[:space:]] ]] || [[ "$COMMAND" =~ \|[[:space:]]*sudo ]]; then
    block "sudo commands require manual execution"
fi

if [[ "$COMMAND" =~ ^su[[:space:]] ]]; then
    block "su commands require manual execution"
fi

# Disk formatting and partition operations
# IMP-076: command-position match instead of bare substring — the old pattern
# blocked read-only commands that merely MENTION the tools (grep -n 'mkfs|fdisk',
# echo/python strings; reproduced live 2026-07-03). Now fires only when the tool
# is invoked: at command start or right after ; & | — followed by space or EOL
# (mkfs.ext4-style suffixes included).
if [[ "$COMMAND" =~ (^|[\;\&\|])[[:space:]]*(mkfs(\.[a-z0-9]+)?|fdisk|parted|gdisk)([[:space:]]|$) ]]; then
    block "Disk formatting commands require manual execution"
fi

# Raw disk writes
if [[ "$COMMAND" =~ dd[[:space:]].*if= ]]; then
    block "dd commands require manual execution"
fi

# Writing to device files (except /dev/null and /dev/stdout which are safe)
if [[ "$COMMAND" =~ \>[[:space:]]*/dev/ ]] && [[ ! "$COMMAND" =~ /dev/null ]] && [[ ! "$COMMAND" =~ /dev/stdout ]] && [[ ! "$COMMAND" =~ /dev/stderr ]]; then
    block "Writing to device files requires manual execution"
fi

# =============================================================================
# SECURITY SENSITIVE - Block commands that could exfiltrate data
# =============================================================================
# NOTE: these patterns intentionally also catch the common work-around tools so
# the guard is consistent across languages, not just curl. If the agent reaches
# for an equivalent, it gets the same block + ask-permission footer.

# Network exfiltration with curl/wget posting data
# Allow read-only GET curls (with optional -s/-L/-o flags writing to /tmp) —
# asset fetches (screenshots, public images) were blocked 72 times in the
# 30-day window ending 2026-04-20. See IMP-023.
#
# IMP-045 localhost carve-out: a request whose target host is loopback /
# local-dev (localhost, 127.0.0.1, 0.0.0.0, ::1, host.docker.internal) is a
# local smoke-test (per local-first-deploy.md), NOT external exfiltration.
# Detect it up front and skip the curl exfil arms for it. Non-local
# destinations are unaffected. The localhost token must appear as a URL host
# (after a scheme:// or //), not a bare substring, to avoid matching e.g. a
# remote path segment named "localhost".
CURL_LOCAL=0
if [[ "$COMMAND" =~ (https?://|//)(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]|::1|host\.docker\.internal)([:/[:space:]\"\']|$) ]]; then
    CURL_LOCAL=1
fi

if [[ "$CURL_LOCAL" != 1 ]] && [[ "$COMMAND" =~ curl.*(-d|--data|-F|--form|--upload-file) ]]; then
    block "curl data upload requires manual execution"
fi

# Block explicit non-GET methods
if [[ "$CURL_LOCAL" != 1 ]] && [[ "$COMMAND" =~ curl.*(-X[[:space:]]*(POST|PUT|PATCH|DELETE)|--request[[:space:]]*(POST|PUT|PATCH|DELETE)) ]]; then
    block "curl mutating HTTP method requires manual execution"
fi

# Block curl output writes outside /tmp (read-only downloads to /tmp are OK).
# IMP-047: gate on CURL_LOCAL like the -d/-X arms above — localhost output writes
# (e.g. `curl -o /dev/null -w %{http_code} http://127.0.0.1:8000/...` health checks)
# were false-blocked because this arm ignored the localhost carve-out.
if [[ "$CURL_LOCAL" != 1 ]] && [[ "$COMMAND" =~ curl.*(-o|--output|-O|--remote-name)[[:space:]]+[^[:space:]]+ ]]; then
    # Extract path after -o / -O if present
    OUTPATH=$(echo "$COMMAND" | grep -oE "(-o|--output)[[:space:]]+[^[:space:]]+" | awk '{print $NF}')
    # IMP-047: /dev/null is a discard sink (status-code checks), not a written file — exempt it.
    if [[ -n "$OUTPATH" && ! "$OUTPATH" =~ ^/tmp/|^\./|^[^/]|^/dev/null$ ]]; then
        block "curl -o writing outside /tmp or relative path requires manual execution"
    fi
fi

if [[ "$COMMAND" =~ wget.*--post ]]; then
    block "wget POST requires manual execution"
fi

# Equivalent HTTP-with-embedded-data work-arounds (python/node) — same class as
# the curl data-upload block above. Catches the most common dodges so the guard
# is not trivially bypassable. GET-only one-liners are NOT matched here.
#
# IMP-045 relax: an authenticated READ-ONLY GET (Authorization header but no
# request body / no mutating method) to a docs/registry host is legitimate and
# must NOT be blocked. So the data-detection arm triggers only on a genuine
# body/payload or an explicit mutating method — NOT on the mere presence of a
# header (headers=/Authorization removed from the trigger set). A localhost
# target is exempt entirely (local dev). Genuine exfil (data= / json= / body: /
# -d / POST|PUT|PATCH|DELETE) to a non-local host still blocks.
if [[ "$CURL_LOCAL" != 1 ]] \
   && [[ "$COMMAND" =~ (python3?|node|deno|ruby|perl).*(urlopen|requests\.(post|put|patch|delete)|http\.client|fetch\(|axios\.) ]] \
   && [[ "$COMMAND" =~ (data=|json=|body:|-d[[:space:]]|POST|PUT|PATCH|DELETE) ]]; then
    block "scripted HTTP request carrying data requires manual execution" \
          "(This is the python/node/etc. equivalent of a blocked curl data upload.)"
fi

# Reverse shells and netcat — word-boundary aware to prevent false positives
# on commands like "rsync" (contains "nc " as substring). Bash doesn't support
# \b so we anchor explicitly to start-of-command or whitespace.
# Fix 2026-05-24: previously matched "rsync -a" as netcat. See TRIAGE-RESULTS.md.
if [[ "$COMMAND" =~ (^|[[:space:]])(nc|netcat|ncat)[[:space:]] ]]; then
    block "netcat commands require manual execution"
fi

# SSH key operations
if [[ "$COMMAND" =~ ssh-keygen.*-f ]]; then
    block "SSH key generation requires manual execution"
fi

# =============================================================================
# GIT DANGEROUS OPERATIONS - These need extra caution (warn, do not block)
# =============================================================================

if [[ "$COMMAND" =~ git[[:space:]]+push[[:space:]]+--force ]]; then
    echo "WARNING: Force push detected - proceeding with caution" >&2
    # Allow but warn - could also block via block() to be strict
fi

if [[ "$COMMAND" =~ git[[:space:]]+reset[[:space:]]+--hard ]]; then
    echo "WARNING: Hard reset detected - uncommitted changes will be lost" >&2
fi

if [[ "$COMMAND" =~ git[[:space:]]+clean[[:space:]]+-fd ]]; then
    echo "WARNING: Clean with -fd will delete untracked files and directories" >&2
fi

# =============================================================================
# ENVIRONMENT VARIABLE EXPOSURE (warn, do not block)
# =============================================================================

if [[ "$COMMAND" =~ (printenv|env)[[:space:]]*$ ]] || [[ "$COMMAND" =~ echo[[:space:]]+\$[A-Z_]*KEY ]] || [[ "$COMMAND" =~ echo[[:space:]]+\$[A-Z_]*SECRET ]] || [[ "$COMMAND" =~ echo[[:space:]]+\$[A-Z_]*TOKEN ]]; then
    echo "WARNING: Potential secret exposure in command" >&2
    # Allow but warn - secrets should be in .env files
fi

# =============================================================================
# IMP-034: Block file-read Bash patterns (per tool-discipline.md Rule 2)
# Anchored regex prevents false positives on piped/heredoc/redirected variants.
# =============================================================================

# IMP-040 Fix B: only block file-reads that have a dedicated-tool equivalent.
#   - cat / head           → always block (Read covers these).
#   - tail WITHOUT -f/-F/--follow → block (Read(offset=) covers it).
#   - tail -f / -F / --follow     → ALLOW (log streaming; no Read substitute).
#   - less / more                 → ALLOW (interactive pagers; no Read substitute).
# The [^|\<\>]*$ anchoring still excludes piped/redirected forms
# (cat f | grep x, cat f > out PASS).

# IMP-082 (2026-07-03): read-only shell access to the framework's OWN telemetry
# (global-observation logs/JSONL) is exempt — jq/zcat/wc pipelines over these
# files have no dedicated-tool substitute, and blocking them forced 88
# CLAUDE_GUARD_OVERRIDEs in one audit day (2026-06-20). No output redirection
# allowed (read-only); tool-discipline Rule 2 already carves out this class.
if [[ "$COMMAND" =~ ^[[:space:]]*(cat|head|tail)[[:space:]] ]] \
   && [[ "$COMMAND" == *"global-observation/"* ]] \
   && [[ "$COMMAND" != *">"* ]]; then
    exit 0
fi

if [[ "$COMMAND" =~ ^[[:space:]]*(cat|head)[[:space:]]+[^|\<\>]*$ ]]; then
    block "'$COMMAND' is a file-read pattern blocked by tool-discipline.md Rule 2." \
"Use the dedicated tool instead:
  - cat FILE          → Read(file_path=\"FILE\")
  - head -N FILE      → Read(file_path=\"FILE\", limit=N)
  - grep PAT FILE     → Grep(pattern=\"PAT\", path=\"FILE\")"
fi

# tail file-read block — but tail -f / -F / --follow (log streaming) has no
# Read-tool equivalent, so it must pass.
if [[ "$COMMAND" =~ ^[[:space:]]*tail[[:space:]]+[^|\<\>]*$ ]] \
   && [[ ! "$COMMAND" =~ (^|[[:space:]])(-f|-F|--follow)([[:space:]]|=|$) ]]; then
    block "'$COMMAND' is a file-read pattern blocked by tool-discipline.md Rule 2." \
"Use the dedicated tool instead:
  - tail -N FILE      → Read(file_path=\"FILE\", offset=<total-N>)
(tail -f / --follow for log streaming is allowed — no Read equivalent.)"
fi

# =============================================================================
# SAFE - Allow the command
# =============================================================================

exit 0
