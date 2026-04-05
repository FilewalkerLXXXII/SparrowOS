#!/bin/sh
# SparrowOS — Tenant quota and rctl limit alert checker
#
# Monitors ZFS disk usage and rctl resource denials for all tenants.
# Alerts are emitted at configurable thresholds and sent to syslog.
# If a desktop session is available, notify-send is also used.
#
# Usage:
#   quota-alerts.sh              — run once (suitable for cron)
#   quota-alerts.sh --daemon     — run continuously (60 s interval)
#
# Must be run as root to access rctl and ZFS data.

set -eu

SPARROW_CONF_DIR="/usr/local/etc/sparrow/tenants"
ZFS_TENANT_ROOT="zroot/sparrow/tenants"
CHECK_INTERVAL=60

# Alert thresholds (percentage of quota)
THRESHOLD_WARN=80
THRESHOLD_HIGH=90
THRESHOLD_CRIT=95

# rctl denial tracking
DENIAL_STATE_DIR="/var/run/sparrow/rctl-denials"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log_info() {
    logger -t sparrow-quota -p user.info "$*"
}

log_warn() {
    logger -t sparrow-quota -p user.warning "WARNING: $*"
}

log_crit() {
    logger -t sparrow-quota -p user.crit "CRITICAL: $*"
}

desktop_notify() {
    urgency="$1"
    summary="$2"
    body="$3"

    # Only attempt notify-send if DISPLAY or WAYLAND_DISPLAY is set
    if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
        if command -v notify-send >/dev/null 2>&1; then
            notify-send -u "$urgency" "$summary" "$body" 2>/dev/null || true
        fi
    fi
}

get_tenant_list() {
    if [ ! -d "$SPARROW_CONF_DIR" ]; then
        return
    fi
    for d in "$SPARROW_CONF_DIR"/*/; do
        tenant=$(basename "$d")
        if [ -f "${d}tenant.conf" ]; then
            echo "$tenant"
        fi
    done
}

# ---------------------------------------------------------------------------
# Disk quota checks
# ---------------------------------------------------------------------------

check_disk_quota() {
    tenant="$1"
    dataset="${ZFS_TENANT_ROOT}/${tenant}"

    # Get used and quota in bytes
    used=$(zfs get -Hp -o value used "$dataset" 2>/dev/null) || return 0
    quota=$(zfs get -Hp -o value quota "$dataset" 2>/dev/null) || return 0

    # Skip if no quota set (quota=0 means unlimited)
    if [ "$quota" -eq 0 ] 2>/dev/null; then
        return 0
    fi

    pct=$((used * 100 / quota))

    if [ "$pct" -ge "$THRESHOLD_CRIT" ]; then
        msg="Tenant '$tenant' disk at ${pct}% (critical >= ${THRESHOLD_CRIT}%)"
        log_crit "$msg"
        desktop_notify "critical" "SparrowOS: Disk Critical" "$msg"
    elif [ "$pct" -ge "$THRESHOLD_HIGH" ]; then
        msg="Tenant '$tenant' disk at ${pct}% (high >= ${THRESHOLD_HIGH}%)"
        log_warn "$msg"
        desktop_notify "critical" "SparrowOS: Disk High" "$msg"
    elif [ "$pct" -ge "$THRESHOLD_WARN" ]; then
        msg="Tenant '$tenant' disk at ${pct}% (warning >= ${THRESHOLD_WARN}%)"
        log_warn "$msg"
        desktop_notify "normal" "SparrowOS: Disk Warning" "$msg"
    fi
}

# ---------------------------------------------------------------------------
# rctl denial checks
# ---------------------------------------------------------------------------

check_rctl_denials() {
    tenant="$1"

    mkdir -p "$DENIAL_STATE_DIR"

    # Resources we monitor for denials
    for resource in memoryuse pcpu maxproc openfiles vmemoryuse; do
        # Current denial count (racct accounting)
        current=$(rctl -u "jail:${tenant}:${resource}" 2>/dev/null | awk -F= '{print $2}')
        current="${current:-0}"

        state_file="${DENIAL_STATE_DIR}/${tenant}.${resource}"

        if [ -f "$state_file" ]; then
            previous=$(cat "$state_file")
        else
            previous=0
        fi

        # Check if the resource is near its limit
        limit_line=$(rctl -l "jail:${tenant}" 2>/dev/null | grep "^jail:${tenant}:${resource}:deny=" || true)
        if [ -z "$limit_line" ]; then
            continue
        fi

        limit_val=$(echo "$limit_line" | awk -F= '{print $2}')

        # Detect sustained denials by checking if current usage is at/near the limit
        # rctl logs denials; we compare the usage to the limit
        if [ -n "$limit_val" ] && [ "$limit_val" -gt 0 ] 2>/dev/null; then
            usage_pct=$((current * 100 / limit_val))
            if [ "$usage_pct" -ge 95 ]; then
                msg="Tenant '$tenant' hitting ${resource} limit: ${current}/${limit_val} (${usage_pct}%)"
                log_warn "$msg"
                desktop_notify "critical" "SparrowOS: rctl Limit" "$msg"
            fi
        fi

        echo "$current" > "$state_file"
    done
}

# ---------------------------------------------------------------------------
# Main check loop
# ---------------------------------------------------------------------------

run_checks() {
    tenants=$(get_tenant_list)
    if [ -z "$tenants" ]; then
        return
    fi

    echo "$tenants" | while read -r tenant; do
        # Only check running jails for rctl; disk applies to all
        check_disk_quota "$tenant"

        if jls -j "$tenant" >/dev/null 2>&1; then
            check_rctl_denials "$tenant"
        fi
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    if [ "$(id -u)" -ne 0 ]; then
        printf 'ERROR: This script must be run as root.\n' >&2
        exit 1
    fi

    mode="${1:-once}"

    case "$mode" in
        --daemon|-d)
            log_info "Starting quota-alerts daemon (interval=${CHECK_INTERVAL}s)"
            while true; do
                run_checks
                sleep "$CHECK_INTERVAL"
            done
            ;;
        *)
            run_checks
            ;;
    esac
}

main "$@"
