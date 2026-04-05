#!/bin/sh
#
# SparrowOS Dynamic MOTD
# Displays system status with cyberpunk ASCII art on terminal login.
#

set -eu

# Colors
C_RESET="\033[0m"
C_GREEN="\033[38;2;0;255;0m"
C_CYAN="\033[38;2;0;255;255m"
C_MAGENTA="\033[38;2;255;0;255m"
C_DIM="\033[38;2;80;80;80m"
C_GRAY="\033[38;2;224;224;224m"

# System info
HOSTNAME=$(hostname)
UPTIME=$(uptime | sed 's/.*up //' | sed 's/,.*//')
ZFS_USED=$(zfs get -H -o value used sparrow 2>/dev/null || echo "N/A")
ZFS_AVAIL=$(zfs get -H -o value available sparrow 2>/dev/null || echo "N/A")

# Tenant info
TENANT_COUNT=0
TENANT_NAMES=""
if command -v sparrow-tenant >/dev/null 2>&1; then
    TENANT_COUNT=$(sparrow-tenant list 2>/dev/null | grep -c "active" || echo "0")
    TENANT_NAMES=$(sparrow-tenant list 2>/dev/null | grep "active" | awk '{print $1}' | tr '\n' ', ' | sed 's/,$//')
fi

# AI tool status
AI_STATUS=""
for tool in claude codex gemini; do
    if pgrep -f "$tool" >/dev/null 2>&1; then
        AI_STATUS="${AI_STATUS}${tool} (active), "
    fi
done
AI_STATUS=${AI_STATUS%", "}
[ -z "$AI_STATUS" ] && AI_STATUS="idle"

# Security level
SEC_LEVEL="STANDARD"
if sysctl -n security.mac.biba.enabled 2>/dev/null | grep -q "1"; then
    SEC_LEVEL="HARDENED"
fi

# Last snapshot
LAST_SNAP=$(zfs list -H -t snapshot -o name -S creation sparrow 2>/dev/null | head -1)
if [ -n "$LAST_SNAP" ]; then
    SNAP_TIME=$(zfs get -H -o value creation "$LAST_SNAP" 2>/dev/null || echo "unknown")
else
    SNAP_TIME="none"
fi

# Detect install mode
MODE="HYBRID"
if ! command -v sway >/dev/null 2>&1; then
    MODE="SERVER"
elif ! command -v sparrow-tenant >/dev/null 2>&1; then
    MODE="WORKSTATION"
fi

# Print MOTD
printf "${C_GREEN}"
cat <<'LOGO'
 ███████╗██████╗  █████╗ ██████╗ ██████╗  ██████╗ ██╗    ██╗
 ██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔═══██╗██║    ██║
 ███████╗██████╔╝███████║██████╔╝██████╔╝██║   ██║██║ █╗ ██║
 ╚════██║██╔═══╝ ██╔══██║██╔══██╗██╔══██╗██║   ██║██║███╗██║
 ███████║██║     ██║  ██║██║  ██║██║  ██║╚██████╔╝╚███╔███╔╝
 ╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝  ╚══╝╚══╝
LOGO
printf "${C_CYAN} Speed and Security with Simple-intuitive UX${C_RESET}\n"
printf "${C_DIM} ────────────────────────────────────────────────────────${C_RESET}\n"
printf "${C_GRAY} Mode:      ${C_CYAN}%-12s${C_GRAY} Host: ${C_GREEN}%-16s${C_GRAY} Uptime: ${C_GREEN}%s${C_RESET}\n" \
    "$MODE" "$HOSTNAME" "$UPTIME"
printf "${C_GRAY} Tenants:   ${C_GREEN}%-3s${C_GRAY} active${C_RESET}" "$TENANT_COUNT"
[ -n "$TENANT_NAMES" ] && printf "${C_DIM} (%s)${C_RESET}" "$TENANT_NAMES"
printf "\n"
printf "${C_GRAY} ZFS:       ${C_GREEN}%s${C_GRAY} used / ${C_GREEN}%s${C_GRAY} available${C_RESET}\n" \
    "$ZFS_USED" "$ZFS_AVAIL"
printf "${C_GRAY} AI Tools:  ${C_MAGENTA}%s${C_RESET}\n" "$AI_STATUS"
printf "${C_GRAY} Security:  ${C_CYAN}%s${C_GRAY}   Last snapshot: ${C_GREEN}%s${C_RESET}\n" \
    "$SEC_LEVEL" "$SNAP_TIME"
printf "${C_DIM} ────────────────────────────────────────────────────────${C_RESET}\n"
printf "\n"
