#!/bin/sh
# SparrowOS — code-server lifecycle management for tenant jails
#
# Manages a code-server instance running inside a FreeBSD jail.
# Each tenant gets a dedicated code-server bound to its VNET IP on port 8080.
#
# Usage:  tenant-codeserver.sh <start|stop|status> <tenant_name>
#
# Must be run as root (uses jexec).

set -eu

SPARROW_CONF_DIR="/usr/local/etc/sparrow/tenants"
CODE_SERVER_PORT="8080"
PIDFILE_DIR="/var/run/sparrow/code-server"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
    printf '[sparrow-codeserver] %s\n' "$*"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

usage() {
    printf 'Usage: %s <start|stop|status> <tenant_name>\n' "$(basename "$0")" >&2
    exit 1
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "This script must be run as root."
    fi
}

load_tenant_conf() {
    tenant="$1"
    conf="${SPARROW_CONF_DIR}/${tenant}/tenant.conf"
    if [ ! -f "$conf" ]; then
        die "Tenant config not found: $conf"
    fi
    # shellcheck disable=SC1090
    . "$conf"
}

jail_running() {
    tenant="$1"
    jls -j "$tenant" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

do_start() {
    tenant="$1"
    load_tenant_conf "$tenant"

    if ! jail_running "$tenant"; then
        die "Jail '$tenant' is not running. Start the jail first."
    fi

    pidfile="${PIDFILE_DIR}/${tenant}.pid"
    mkdir -p "$PIDFILE_DIR"

    if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        log "code-server for '$tenant' is already running (PID $(cat "$pidfile"))."
        return 0
    fi

    tenant_ip="${TENANT_IP:?TENANT_IP not set in tenant.conf}"
    bind_addr="${tenant_ip}:${CODE_SERVER_PORT}"

    log "Starting code-server for tenant '$tenant' on $bind_addr ..."

    # Run code-server inside the jail in the background
    jexec "$tenant" /usr/local/bin/code-server \
        --bind-addr "$bind_addr" \
        --auth none \
        --disable-telemetry \
        --user-data-dir "/home/${tenant}/.local/share/code-server" \
        --extensions-dir "/home/${tenant}/.local/share/code-server/extensions" \
        >/var/log/sparrow/code-server-"${tenant}".log 2>&1 &

    cs_pid=$!
    echo "$cs_pid" > "$pidfile"

    log "code-server started for '$tenant' (PID $cs_pid)."
    log "Access via: http://${bind_addr}"
}

do_stop() {
    tenant="$1"
    pidfile="${PIDFILE_DIR}/${tenant}.pid"

    if [ ! -f "$pidfile" ]; then
        log "No PID file for tenant '$tenant' — not running."
        return 0
    fi

    pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
        log "Stopping code-server for '$tenant' (PID $pid) ..."
        kill "$pid"
        # Wait briefly for graceful shutdown
        i=0
        while [ $i -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            i=$((i + 1))
        done
        if kill -0 "$pid" 2>/dev/null; then
            log "Forcefully killing PID $pid ..."
            kill -9 "$pid" 2>/dev/null || true
        fi
        log "code-server stopped for '$tenant'."
    else
        log "PID $pid is not running (stale PID file)."
    fi

    rm -f "$pidfile"
}

do_status() {
    tenant="$1"
    pidfile="${PIDFILE_DIR}/${tenant}.pid"

    if [ ! -f "$pidfile" ]; then
        log "code-server for '$tenant': stopped (no PID file)"
        return 1
    fi

    pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
        load_tenant_conf "$tenant"
        tenant_ip="${TENANT_IP:-unknown}"
        log "code-server for '$tenant': running (PID $pid) on ${tenant_ip}:${CODE_SERVER_PORT}"
        return 0
    else
        log "code-server for '$tenant': stopped (stale PID file)"
        rm -f "$pidfile"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    if [ $# -lt 2 ]; then
        usage
    fi

    cmd="$1"
    tenant="$2"

    require_root

    case "$cmd" in
        start)  do_start "$tenant" ;;
        stop)   do_stop "$tenant" ;;
        status) do_status "$tenant" ;;
        *)      usage ;;
    esac
}

main "$@"
