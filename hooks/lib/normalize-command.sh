#!/usr/bin/env bash
# normalize-command.sh — shared command-data stripper for the bash safety
# gates (guard-unsafe.sh; excessive-agency-gate.sh keeps its own embedded
# copy — see note below).
#
# Mirrors excessive-agency-gate.sh's Python strip_data() function exactly:
# heredoc bodies and single/double-quoted spans are removed (treated as
# DATA, not as executed command text). NEWLINES ARE PRESERVED — a bare
# newline is a command separator, the same as ';', and command-position
# anchoring (`(^|[;&|<NL>])[[:space:]]*`) needs the real newline byte to
# recognize a line break as a boundary. Whitespace is deliberately NOT
# collapsed to a single space (that would destroy the newline boundary).
#
# IMP-106 (2026-08-22): extracted so guard-unsafe.sh's CRITICAL-floor arms
# can match at COMMAND POSITION instead of matching a dangerous substring
# ANYWHERE in the raw string — which previously blocked pure prose/data:
#   echo 'niemals rm -rf / ausführen'      -> was blocked, is data
#   grep 'rm -rf /' README.md              -> was blocked, is data
#   git commit -F - <<EOF ... rm -rf ~ ... EOF  -> was blocked, is a message
#
# Why excessive-agency-gate.sh is NOT rewired to call this file:
# its own strip_data() runs INSIDE a single already-spawned python3 process
# that also computes a security-critical ack-token signature on a
# documented latency-sensitive hot path (IMP-076/081 removed a python3
# spawn from this exact hook because it dominated gate latency). Re-plumbing
# it through a second shell-out to this file would add a process hop for a
# hook that fires on every Bash call, for zero coverage gain — its own
# strip_data() already implements the identical algorithm. Both files are
# therefore kept as VERIFIABLY IDENTICAL, independently-run logic rather
# than a shared runtime dependency. If they ever drift, that is a bug to
# fix by re-diffing the two `strip_data` bodies, not a reason to force a
# process-boundary call here.
#
# Usage:
#   source ".../hooks/lib/normalize-command.sh"
#   COMMAND_NORM="$(guard_normalize_command "$COMMAND")"
#
# FAIL-OPEN TOWARD STRICTNESS (per rules/fail-loud.md — never a silent
# hole): if python3 is unavailable, errors, or produces nothing for a
# non-empty input, this prints the RAW command UNCHANGED. Callers then see
# the OLD (unanchored, substring) behavior for that one invocation — an
# over-block risk in the worst case, never a new bypass.

guard_normalize_command() {
    local cmd="$1"
    local out

    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s' "$cmd"
        return
    fi

    out=$(GNC_CMD_IN="$cmd" python3 <<'PYEOF' 2>/dev/null
import os, re, sys

cmd = os.environ.get("GNC_CMD_IN", "")

def strip_data(s):
    out, in_h, tag = [], False, None
    hd = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")
    for ln in s.split("\n"):
        if in_h:
            if ln.strip() == tag:
                in_h = False
            continue
        m = hd.search(ln)
        if m:
            tag = m.group(1); in_h = True; out.append(ln[:m.start()]); continue
        out.append(ln)
    s = "\n".join(out)
    s = re.sub(r"'[^']*'", "", s)      # single-quoted strings -> data, removed
    s = re.sub(r'"[^"]*"', "", s)      # double-quoted strings -> data, removed
    return s

sys.stdout.write(strip_data(cmd))
PYEOF
    )

    if [ -z "$out" ] && [ -n "$cmd" ]; then
        # Normalization produced nothing for a non-empty input -> treat as a
        # failure and fall back to the RAW command (fail-open toward the
        # stricter, pre-fix substring behavior; never toward a hole).
        printf '%s' "$cmd"
    else
        printf '%s' "$out"
    fi
}
