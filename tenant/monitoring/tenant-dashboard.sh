#!/bin/sh
# SparrowOS — Real-time tenant dashboard
#
# Displays a live table of all tenants with resource usage pulled from
# rctl(8) and zfs(8).  Output is colorized using the SparrowOS palette.
#
# Usage:
#   tenant-dashboard.sh              — one-shot display
#   tenant-dashboard.sh --watch      — continuous refresh (2 s interval)
#   tenant-dashboard.sh --waybar     — JSON output for Waybar custom module
#
# Must be run as root to read rctl counters.

set -eu

SPARROW_CONF_DIR="/usr/local/etc/sparrow/tenants"
ZFS_TENANT_ROOT="zroot/sparrow/tenants"
REFRESH_INTERVAL=2

# ---------------------------------------------------------------------------
# SparrowOS color scheme (ANSI)
# ---------------------------------------------------------------------------

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[38;5;114m"     # active / healthy
C_RED="\033[38;5;203m"       # stopped / critical
C_YELLOW="\033[38;5;220m"    # warning
C_CYAN="\033[38;5;80m"       # headers
C_DIM="\033[2m"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

human_bytes() {
    # Convert bytes to human-readable (K/M/G)
    bytes="$1"
    if [ "$bytes" -ge 1073741824 ]; then
        printf '%.1fG' "$(echo "$bytes / 1073741824" | bc -l 2>/dev/null || echo 0)"
    elif [ "$bytes" -ge 1048576 ]; then
        printf '%.1fM' "$(echo "$bytes / 1048576" | bc -l 2>/dev/null || echo 0)"
    elif [ "$bytes" -ge 1024 ]; then
        printf '%.1fK' "$(echo "$bytes / 1024" | bc -l 2>/dev/null || echo 0)"
    else
        printf '%dB' "$bytes"
    fi
}

get_tenant_list() {
    # List tenant directories that contain a tenant.conf
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

is_jail_running() {
    jls -j "$1" >/dev/null 2>&1
}

get_rctl_value() {
    # Get a specific rctl resource value for a jail
    jail="$1"
    resource="$2"
    rctl -u "jail:${jail}:${resource}" 2>/dev/null | awk -F= '{print $2}'
}

get_zfs_usage() {
    # Returns "used quota" for the tenant dataset
    dataset="${ZFS_TENANT_ROOT}/$1"
    zfs get -Hp -o value used,quota "$dataset" 2>/dev/null || echo "0 0"
}

# ---------------------------------------------------------------------------
# Dashboard rendering
# ---------------------------------------------------------------------------

print_header() {
    printf "${C_CYAN}${C_BOLD}"
    printf '%-16s %-8s %-16s %6s %10s %18s %-8s\n' \
        "TENANT" "PROFILE" "IP" "CPU%" "MEMORY" "DISK (used/quota)" "STATUS"
    printf "${C_RESET}"
    printf "${C_DIM}"
    printf '%.0s-' $(seq 1 90)
    printf "${C_RESET}\n"
}

print_tenant_row() {
    tenant="$1"

    # Load tenant configuration
    conf="${SPARROW_CONF_DIR}/${tenant}/tenant.conf"
    # shellcheck disable=SC1090
    . "$conf"

    profile="${TENANT_PROFILE:-unknown}"
    ip="${TENANT_IP:-N/A}"

    if is_jail_running "$tenant"; then
        status_color="$C_GREEN"
        status_text="active"

        # CPU percentage from rctl
        cpu_raw=$(get_rctl_value "$tenant" "pcpu")
        cpu_pct="${cpu_raw:-0}"

        # Memory from rctl (bytes)
        mem_raw=$(get_rctl_value "$tenant" "memoryuse")
        mem_human=$(human_bytes "${mem_raw:-0}")

        # Disk from ZFS
        zfs_out=$(get_zfs_usage "$tenant")
        disk_used=$(echo "$zfs_out" | awk '{print $1}')
        disk_quota=$(echo "$zfs_out" | awk '{print $2}')
        disk_str="$(human_bytes "${disk_used:-0}")/$(human_bytes "${disk_quota:-0}")"
    else
        status_color="$C_RED"
        status_text="stopped"
        cpu_pct="-"
        mem_human="-"
        disk_str="-"
    fi

    printf "${C_RESET}%-16s %-8s %-16s %6s %10s %18s ${status_color}%-8s${C_RESET}\n" \
        "$tenant" "$profile" "$ip" "$cpu_pct" "$mem_human" "$disk_str" "$status_text"
}

render_dashboard() {
    clear 2>/dev/null || true
    printf "${C_BOLD}${C_GREEN}  SparrowOS Tenant Dashboard${C_RESET}"
    printf "  ${C_DIM}%s${C_RESET}\n\n" "$(date '+%Y-%m-%d %H:%M:%S')"

    print_header

    tenants=$(get_tenant_list)
    if [ -z "$tenants" ]; then
        printf "  ${C_DIM}No tenants configured.${C_RESET}\n"
        return
    fi

    echo "$tenants" | while read -r tenant; do
        print_tenant_row "$tenant"
    done

    printf '\n'
}

# ---------------------------------------------------------------------------
# Waybar JSON output
# ---------------------------------------------------------------------------

waybar_output() {
    tenants=$(get_tenant_list)
    total=0
    active=0

    if [ -n "$tenants" ]; then
        total=$(echo "$tenants" | wc -l | tr -d ' ')
        for t in $tenants; do
            if is_jail_running "$t"; then
                active=$((active + 1))
            fi
        done
    fi

    tooltip="Tenants: ${active}/${total} active"

    printf '{"text": "%s/%s", "tooltip": "%s", "class": "%s"}\n' \
        "$active" "$total" "$tooltip" \
        "$(if [ "$active" -eq "$total" ]; then echo 'healthy'; else echo 'degraded'; fi)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    mode="${1:-oneshot}"

    case "$mode" in
        --watch|-w)
            while true; do
                render_dashboard
                sleep "$REFRESH_INTERVAL"
            done
            ;;
        --waybar)
            waybar_output
            ;;
        *)
            render_dashboard
            ;;
    esac
}

main "$@"
