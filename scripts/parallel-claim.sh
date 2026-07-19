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
#   claim   <file_path> <agent_id> [ttl_secs]   → 0 if won, 2 if conflict
#   release <file_path> <agent_id>              → 0 if released, 1 if not owner
#   check   <file_path>                          → prints owner_id|expires_at, exit 0 if locked
#   list    [agent_id]                           → list all (or filtered) active locks
#   cleanup                                       → remove expired locks
#   release-all <agent_id>                       → release ALL locks owned by this agent

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
    [ -z "$file_path" ] || [ -z "$agent_id" ] && { echo "usage: claim <file_path> <agent_id> [ttl]"; return 2; }

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
              --arg claimed_at "$now_iso" \
              --arg expires_at "$expires_iso" \
              --argjson claimed_epoch "$now" \
              --argjson expires_epoch "$expires" \
            '{agent_id:$aid, file_path:$fp, claimed_at:$claimed_at, expires_at:$expires_at, claimed_epoch:$claimed_epoch, expires_at_epoch:$expires_epoch}' \
            > "$meta"
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

cmd_release_all() {
    local agent_id="$1"
    [ -z "$agent_id" ] && { echo "usage: release-all <agent_id>"; return 2; }
    local released=0
    for meta in "$LOCK_ROOT"/*/owner.json; do
        [ -f "$meta" ] || continue
        local owner
        owner=$(jq -r '.agent_id' "$meta")
        if [ "$owner" = "$agent_id" ]; then
            local dir
            dir=$(dirname "$meta")
            rm -rf "$dir"
            released=$((released+1))
        fi
    done
    echo "released $released locks for $agent_id"
}

case "${1:-}" in
    claim)        shift; cmd_claim "$@" ;;
    release)      shift; cmd_release "$@" ;;
    check)        shift; cmd_check "$@" ;;
    list)         shift; cmd_list "$@" ;;
    cleanup)      cmd_cleanup ;;
    release-all)  shift; cmd_release_all "$@" ;;
    *)
        cat >&2 <<USAGE
Usage: $(basename "$0") <command> [args]

Commands:
  claim   <file_path> <agent_id> [ttl_secs]   Claim a file; output "claimed"|"renewed"|"stolen-expired"; exit 0 if won, 2 if conflict
  release <file_path> <agent_id>              Release; exit 0 if released, 1 if not owner
  check   <file_path>                          Print "owner|expires_at" or "unlocked"|"expired"; exit 0 if locked
  list    [agent_id]                           List all (or filtered) active locks
  cleanup                                       Remove expired locks
  release-all <agent_id>                       Release all locks owned by agent
USAGE
        exit 2
        ;;
esac
