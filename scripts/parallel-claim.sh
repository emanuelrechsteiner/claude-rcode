#!/bin/bash
# Parallel Claim Utility — File-Lock Registry for Multi-Agent Coordination
# ─────────────────────────────────────────────────────────────────────────
# Implements file-level locking using directory atomicity (mkdir is POSIX-
# atomic). Adapted from HCOM's coordination pattern. Used by:
#   - hooks/parallel-lock-check.sh    (PreToolUse: enforce locks)
#   - hooks/subagent-lock-release.sh  (SubagentStop: auto-release)
#   - skills/parallel-dispatch        (orchestrator: claim then dispatch)
#
# Lock storage: /tmp/claude-locks/<sha1>/owner.json
# TTL: 30 minutes default (configurable via $CLAUDE_LOCK_TTL_SECS)
#
# Commands:
#   claim   <file_path> <agent_id> [ttl_secs] [session_id]
#                                                → 0 if won, 2 if conflict
#   bind    <file_path> <harness_agent_id> [session_id]
#                                                → 0 if bound/already-mine, 1 if held by another
#   release <file_path> <agent_id>              → 0 if released, 1 if not owner
#   check   <file_path>                          → prints owner_id|expires_at, exit 0 if locked
#   list    [agent_id]                           → list all (or filtered) active locks
#   cleanup                                       → remove expired locks
#   release-all <agent_id>                       → release ALL locks owned by this agent
#                                                  (matches claim id OR bound harness id)
#   release-session <session_id>                 → release ALL locks claimed by this session
#
# ── THE TWO IDENTITY SPACES (IMP-114, 2026-08-01) ─────────────────────────────
# This registry has always had two identifiers that never intersect:
#
#   claim id    — invented by the ORCHESTRATOR ("pdispatch-<turn>-<unit>"),
#                 per skills/parallel-dispatch/SKILL.md.
#   harness id  — a 17-hex string the runtime puts in .agent_id of the
#                 PreToolUse / SubagentStop payloads. The orchestrator cannot
#                 know it at claim time: claims happen BEFORE dispatch.
#
# Comparing them by string equality — which both hooks did — can never match.
# Measured consequences before this fix:
#   * release-all matched nothing: 3,212/3,212 release records said
#     "released 0 locks"; only TTL-steal ever freed a lock.
#   * WORSE, and unreported until it was tested directly: parallel-lock-check.sh
#     compared the same two spaces to answer "is this MY lock?", so after a
#     claim the file was denied to the very subagent it was claimed for — and
#     to the orchestrator too. A claim was a self-inflicted denial of service
#     until TTL expiry. That is why write fan-outs were never actually usable.
#
# The join: a lock is claimed with a session_id and an initially-null
# harness_agent_id. The first agent that actually touches the file BINDS it
# (first-come, within the claiming session). Ownership afterwards is decided by
# the bound harness id — which both hooks CAN see. Protection is preserved: a
# second, different subagent of the same session is still denied.
# ─────────────────────────────────────────────────────────────────────────────

set -u

LOCK_ROOT="${CLAUDE_LOCK_ROOT:-/tmp/claude-locks}"
DEFAULT_TTL="${CLAUDE_LOCK_TTL_SECS:-1800}"  # 30 min

mkdir -p "$LOCK_ROOT" 2>/dev/null

# sha1 of path → stable per-file directory name
path_to_key() {
    printf '%s' "$1" | shasum | awk '{print $1}'
}

# Read current epoch time
now_epoch() { date +%s; }

# Audit trail. Until IMP-114 only RELEASES were logged, so the coordination log
# could not answer the most basic question — how often locks are actually
# claimed. "exactly 1 multi-lock dispatch in 6 weeks" (rules/parallel-by-default.md)
# was derived from that release-only view and was therefore not measurable.
COORD_LOG="${CLAUDE_COORD_LOG:-$HOME/.claude/global-observation/parallel-coordination.jsonl}"
log_event() {
    local event="$1" agent="$2" file="$3" result="$4"
    mkdir -p "$(dirname "$COORD_LOG")" 2>/dev/null || true
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           --arg event "$event" --arg agent_id "$agent" \
           --arg file "$file" --arg result "$result" \
        '{ts:$ts,event:$event,agent_id:$agent_id,file:$file,result:$result}' \
        >> "$COORD_LOG" 2>/dev/null || true
}

# Check if a lock is expired
is_expired() {
    local meta="$1"
    [ -f "$meta" ] || return 0
    local expires
    expires=$(jq -r '.expires_at_epoch // 0' "$meta" 2>/dev/null || echo 0)
    local now
    now=$(now_epoch)
    [ "$now" -gt "$expires" ]
}

cmd_claim() {
    local file_path="$1"
    local agent_id="$2"
    local ttl="${3:-$DEFAULT_TTL}"
    local session_id="${4:-${CLAUDE_SESSION_ID:-}}"
    [ -z "$file_path" ] || [ -z "$agent_id" ] && { echo "usage: claim <file_path> <agent_id> [ttl] [session_id]"; return 2; }

    local key
    key=$(path_to_key "$file_path")
    local dir="$LOCK_ROOT/$key"
    local meta="$dir/owner.json"

    # Atomic claim via mkdir
    if mkdir "$dir" 2>/dev/null; then
        # Won the race — write metadata
        local now
        now=$(now_epoch)
        local expires=$((now + ttl))
        local now_iso
        now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local expires_iso
        if [[ "$(uname)" == "Darwin" ]]; then
            expires_iso=$(date -u -r "$expires" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
        else
            expires_iso=$(date -u -d "@$expires" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
        fi
        jq -n --arg aid "$agent_id" \
              --arg fp "$file_path" \
              --arg sid "$session_id" \
              --arg claimed_at "$now_iso" \
              --arg expires_at "$expires_iso" \
              --argjson claimed_epoch "$now" \
              --argjson expires_epoch "$expires" \
            '{agent_id:$aid, file_path:$fp, session_id:$sid, harness_agent_id:null, claimed_at:$claimed_at, expires_at:$expires_at, claimed_epoch:$claimed_epoch, expires_at_epoch:$expires_epoch}' \
            > "$meta"
        log_event "claim" "$agent_id" "$file_path" "claimed"
        echo "claimed"
        return 0
    fi

    # Directory exists — check if expired or owned by same agent
    if [ -f "$meta" ]; then
        local owner
        owner=$(jq -r '.agent_id // ""' "$meta" 2>/dev/null)

        # Same owner = re-claim (refresh TTL)
        if [ "$owner" = "$agent_id" ]; then
            local now
            now=$(now_epoch)
            local expires=$((now + ttl))
            local expires_iso
            if [[ "$(uname)" == "Darwin" ]]; then
                expires_iso=$(date -u -r "$expires" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
            else
                expires_iso=$(date -u -d "@$expires" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
            fi
            # Update expiry
            jq --arg expires_at "$expires_iso" --argjson expires_epoch "$expires" \
                '.expires_at = $expires_at | .expires_at_epoch = $expires_epoch' \
                "$meta" > "${meta}.tmp" && mv "${meta}.tmp" "$meta"
            echo "renewed"
            return 0
        fi

        # Different owner — check if expired
        if is_expired "$meta"; then
            # Steal it: overwrite metadata
            local now
            now=$(now_epoch)
            local expires=$((now + ttl))
            local now_iso
            now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            local expires_iso
            if [[ "$(uname)" == "Darwin" ]]; then
                expires_iso=$(date -u -r "$expires" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
            else
                expires_iso=$(date -u -d "@$expires" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
            fi
            jq -n --arg aid "$agent_id" --arg fp "$file_path" \
                  --arg claimed_at "$now_iso" --arg expires_at "$expires_iso" \
                  --argjson claimed_epoch "$now" --argjson expires_epoch "$expires" \
                '{agent_id:$aid, file_path:$fp, claimed_at:$claimed_at, expires_at:$expires_at, claimed_epoch:$claimed_epoch, expires_at_epoch:$expires_epoch, stolen_from_expired:true}' \
                > "$meta"
            echo "stolen-expired"
            return 0
        fi

        # Active conflict
        local expires_at
        expires_at=$(jq -r '.expires_at // ""' "$meta" 2>/dev/null)
        echo "conflict: held by $owner until $expires_at" >&2
        return 2
    fi

    # Directory exists but no metadata — corrupt state, treat as available
    local now
    now=$(now_epoch)
    local expires=$((now + ttl))
    local now_iso
    now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -n --arg aid "$agent_id" --arg fp "$file_path" \
        '{agent_id:$aid, file_path:$fp, claimed_at:"recovered"}' > "$meta"
    echo "recovered"
    return 0
}

# ── bind: attach the runtime's harness agent id to a claimed lock (IMP-114) ───
# Called by parallel-lock-check.sh on every Edit/Write of a locked file. This is
# the join between the two identity spaces documented at the top of this file.
#
# Returns 0 (caller ALLOWS the edit) when:
#   * the lock is already bound to THIS harness agent, or
#   * the lock is unbound and was claimed by THIS session → bind it now, or
#   * the lock is a legacy record with no session_id → bind it (before this fix
#     such a lock denied everyone until TTL; first-come is strictly better and
#     is the only migration path for locks already on disk).
# Returns 1 (caller DENIES) when the lock is bound to a DIFFERENT harness agent
# — the real cross-agent collision this registry exists to catch.
cmd_bind() {
    local file_path="$1"
    local harness_id="$2"
    local session_id="${3:-}"
    [ -z "$file_path" ] || [ -z "$harness_id" ] && { echo "usage: bind <file_path> <harness_agent_id> [session_id]"; return 2; }

    local key dir meta
    key=$(path_to_key "$file_path")
    dir="$LOCK_ROOT/$key"
    meta="$dir/owner.json"

    [ -f "$meta" ] && ! is_expired "$meta" || { echo "unlocked"; return 0; }

    local bound claim_sess
    bound=$(jq -r '.harness_agent_id // ""' "$meta" 2>/dev/null)
    claim_sess=$(jq -r '.session_id // ""' "$meta" 2>/dev/null)

    if [ "$bound" = "$harness_id" ]; then
        echo "already-mine"; return 0
    fi
    if [ -n "$bound" ]; then
        echo "held-by:$bound" >&2; return 1
    fi
    # Unbound. Bind only if the session matches, or if the lock predates the
    # session_id field entirely (legacy migration — see comment above).
    if [ -z "$claim_sess" ] || [ "$claim_sess" = "$session_id" ]; then
        jq --arg h "$harness_id" '.harness_agent_id = $h' "$meta" > "${meta}.tmp" 2>/dev/null \
            && mv "${meta}.tmp" "$meta"
        log_event "bind" "$harness_id" "$file_path" "bound"
        echo "bound"; return 0
    fi
    echo "other-session:$claim_sess" >&2; return 1
}

cmd_release() {
    local file_path="$1"
    local agent_id="$2"
    [ -z "$file_path" ] || [ -z "$agent_id" ] && { echo "usage: release <file_path> <agent_id>"; return 2; }

    local key
    key=$(path_to_key "$file_path")
    local dir="$LOCK_ROOT/$key"
    local meta="$dir/owner.json"

    [ -d "$dir" ] || { echo "not-locked"; return 0; }
    [ -f "$meta" ] || { rm -rf "$dir"; echo "released-orphan"; return 0; }

    local owner
    owner=$(jq -r '.agent_id // ""' "$meta")
    if [ "$owner" = "$agent_id" ]; then
        rm -rf "$dir"
        echo "released"
        return 0
    fi
    echo "not-owner (held by $owner)" >&2
    return 1
}

cmd_check() {
    local file_path="$1"
    [ -z "$file_path" ] && { echo "usage: check <file_path>"; return 2; }

    local key
    key=$(path_to_key "$file_path")
    local meta="$LOCK_ROOT/$key/owner.json"

    [ -f "$meta" ] || { echo "unlocked"; return 1; }
    if is_expired "$meta"; then
        echo "expired"
        return 1
    fi
    jq -r '"\(.agent_id)|\(.expires_at)"' "$meta"
    return 0
}

cmd_list() {
    local filter_agent="${1:-}"
    local found=0
    for meta in "$LOCK_ROOT"/*/owner.json; do
        [ -f "$meta" ] || continue
        if is_expired "$meta"; then continue; fi
        if [ -n "$filter_agent" ]; then
            local owner
            owner=$(jq -r '.agent_id' "$meta")
            [ "$owner" = "$filter_agent" ] || continue
        fi
        jq -r '"\(.agent_id) \(.file_path) (until \(.expires_at))"' "$meta"
        found=$((found+1))
    done
    [ $found -eq 0 ] && echo "(no active locks)"
}

cmd_cleanup() {
    local removed=0
    for meta in "$LOCK_ROOT"/*/owner.json; do
        [ -f "$meta" ] || continue
        if is_expired "$meta"; then
            local dir
            dir=$(dirname "$meta")
            rm -rf "$dir"
            removed=$((removed+1))
        fi
    done
    echo "cleaned $removed expired locks"
}

# Matches EITHER identity space (IMP-114): the orchestrator's claim id, or the
# bound harness id. Before this, only the claim id was compared — and the sole
# caller (subagent-lock-release.sh) always passed a harness id, so the match
# could never succeed.
cmd_release_all() {
    local agent_id="$1"
    [ -z "$agent_id" ] && { echo "usage: release-all <agent_id>"; return 2; }
    local released=0
    for meta in "$LOCK_ROOT"/*/owner.json; do
        [ -f "$meta" ] || continue
        local owner bound
        owner=$(jq -r '.agent_id // ""' "$meta" 2>/dev/null)
        bound=$(jq -r '.harness_agent_id // ""' "$meta" 2>/dev/null)
        if [ "$owner" = "$agent_id" ] || { [ -n "$bound" ] && [ "$bound" = "$agent_id" ]; }; then
            local dir
            dir=$(dirname "$meta")
            rm -rf "$dir"
            released=$((released+1))
        fi
    done
    echo "released $released locks for $agent_id"
}

# Orchestrator-side cleanup for locks that were claimed but never bound (the
# subagent never touched that file, so no SubagentStop can release them).
# Without this they linger until TTL — the leak observed as 18 stale dirs.
cmd_release_session() {
    local session_id="$1"
    [ -z "$session_id" ] && { echo "usage: release-session <session_id>"; return 2; }
    local released=0
    for meta in "$LOCK_ROOT"/*/owner.json; do
        [ -f "$meta" ] || continue
        local sess
        sess=$(jq -r '.session_id // ""' "$meta" 2>/dev/null)
        if [ -n "$sess" ] && [ "$sess" = "$session_id" ]; then
            rm -rf "$(dirname "$meta")"
            released=$((released+1))
        fi
    done
    log_event "release-session" "$session_id" "" "released $released"
    echo "released $released locks for session $session_id"
}

case "${1:-}" in
    claim)           shift; cmd_claim "$@" ;;
    bind)            shift; cmd_bind "$@" ;;
    release)         shift; cmd_release "$@" ;;
    check)           shift; cmd_check "$@" ;;
    list)            shift; cmd_list "$@" ;;
    cleanup)         cmd_cleanup ;;
    release-all)     shift; cmd_release_all "$@" ;;
    release-session) shift; cmd_release_session "$@" ;;
    *)
        cat >&2 <<USAGE
Usage: $(basename "$0") <command> [args]

Commands:
  claim   <file_path> <agent_id> [ttl] [session_id]
                                               Claim a file; "claimed"|"renewed"|"stolen-expired"; exit 0 if won, 2 if conflict
  bind    <file_path> <harness_agent_id> [session_id]
                                               Attach the runtime agent id to a claimed lock; exit 0 = allow, 1 = held by another
  release <file_path> <agent_id>              Release; exit 0 if released, 1 if not owner
  check   <file_path>                          Print "owner|expires_at" or "unlocked"|"expired"; exit 0 if locked
  list    [agent_id]                           List all (or filtered) active locks
  cleanup                                       Remove expired locks
  release-all <agent_id>                       Release all locks owned by agent (claim id OR bound harness id)
  release-session <session_id>                 Release all locks claimed by a session (unbound leftovers)
USAGE
        exit 2
        ;;
esac
