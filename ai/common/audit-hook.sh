#!/bin/sh
# SparrowOS — AI action audit logging hook
#
# Called before and after AI tool execution to record an audit trail.
# Each invocation logs the timestamp, tool name, working directory, user,
# and (for the "after" phase) exit code and ZFS diff summary.
#
# Usage:
#   audit-hook.sh before <tool_name> [project_dir]
#   audit-hook.sh after  <tool_name> [project_dir] [exit_code]
#
# The "before" phase takes a ZFS snapshot; the "after" phase diffs against
# it and records the changes.

set -eu

AUDIT_LOG="/var/log/sparrow-ai-audit.log"
SNAPSHOT_PREFIX="sparrow-audit"
ZFS_DATASET="${SPARROW_AI_DATASET:-zroot/sparrow/tenants/$(whoami)}"
LOG_TAG="sparrow-ai-audit"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log_audit() {
    line="$*"
    # Append to audit log file
    printf '%s\n' "$line" >> "$AUDIT_LOG" 2>/dev/null || true
    # Also send to syslog
    logger -t "$LOG_TAG" "$line"
}

ensure_log_dir() {
    log_dir=$(dirname "$AUDIT_LOG")
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" 2>/dev/null || true
    fi
}

die() {
    printf '[audit-hook] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: %s <before|after> <tool_name> [project_dir] [exit_code]\n' \
        "$(basename "$0")" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# ZFS snapshot helpers
# ---------------------------------------------------------------------------

snapshot_name() {
    tool="$1"
    printf '%s@%s-%s-%s' "$ZFS_DATASET" "$SNAPSHOT_PREFIX" "$tool" \
        "$(date +%Y%m%d-%H%M%S)"
}

take_snapshot() {
    snap="$1"
    if zfs list -H -o name "$ZFS_DATASET" >/dev/null 2>&1; then
        zfs snapshot "$snap" 2>/dev/null && echo "$snap" || true
    fi
}

find_before_snapshot() {
    tool="$1"
    zfs list -H -t snapshot -o name -s creation "$ZFS_DATASET" 2>/dev/null \
        | grep "${SNAPSHOT_PREFIX}-${tool}" \
        | tail -1
}

# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------

phase_before() {
    tool="$1"
    project_dir="$2"
    user=$(whoami)
    ts=$(timestamp)

    # Take a pre-execution ZFS snapshot
    snap=$(snapshot_name "$tool")
    snap_result=$(take_snapshot "$snap")

    log_audit "BEFORE | ts=${ts} | tool=${tool} | dir=${project_dir} | user=${user} | snapshot=${snap_result:-none}"
}

phase_after() {
    tool="$1"
    project_dir="$2"
    exit_code="${3:-0}"
    user=$(whoami)
    ts=$(timestamp)

    # Find the before-snapshot for this tool
    before_snap=$(find_before_snapshot "$tool")

    # Count changed files via ZFS diff
    changed_files=0
    diff_summary=""
    if [ -n "$before_snap" ]; then
        diff_output=$(zfs diff "$before_snap" 2>/dev/null || true)
        if [ -n "$diff_output" ]; then
            changed_files=$(printf '%s\n' "$diff_output" | wc -l | tr -d ' ')
            # Summarize: count by change type (M=modified, +=added, -=removed, R=renamed)
            modified=$(printf '%s\n' "$diff_output" | grep -c '^M' || true)
            added=$(printf '%s\n' "$diff_output" | grep -c '^+' || true)
            removed=$(printf '%s\n' "$diff_output" | grep -c '^-' || true)
            renamed=$(printf '%s\n' "$diff_output" | grep -c '^R' || true)
            diff_summary="M=${modified},+=${added},-=${removed},R=${renamed}"
        fi
    fi

    log_audit "AFTER  | ts=${ts} | tool=${tool} | dir=${project_dir} | user=${user} | exit=${exit_code} | files_changed=${changed_files} | diff=${diff_summary:-none}"

    # Take a post-execution snapshot for future reference
    post_snap=$(snapshot_name "${tool}-post")
    take_snapshot "$post_snap" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    if [ $# -lt 2 ]; then
        usage
    fi

    phase="$1"
    tool="$2"
    project_dir="${3:-$(pwd)}"

    ensure_log_dir

    case "$phase" in
        before)
            phase_before "$tool" "$project_dir"
            ;;
        after)
            exit_code="${4:-0}"
            phase_after "$tool" "$project_dir" "$exit_code"
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
