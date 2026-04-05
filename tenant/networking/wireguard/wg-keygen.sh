#!/bin/sh
# SparrowOS — WireGuard keypair generator for tenant peers
#
# Generates a WireGuard private/public key pair for a named tenant and
# stores the keys under the central peer directory.  Outputs a ready-to-use
# client configuration fragment.
#
# Usage:  wg-keygen.sh <tenant_name>
#
# Must be run as root (key directory is restricted).

set -eu

WG_BASE="/usr/local/etc/sparrow/wireguard"
PEER_DIR="${WG_BASE}/peers"
SERVER_CONF="${WG_BASE}/server.conf"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
    printf '[sparrow-wg] %s\n' "$*"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

usage() {
    printf 'Usage: %s <tenant_name>\n' "$(basename "$0")" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Key generation
# ---------------------------------------------------------------------------

generate_keys() {
    tenant="$1"
    tenant_dir="${PEER_DIR}/${tenant}"

    if [ -d "$tenant_dir" ]; then
        die "Peer directory already exists: $tenant_dir (use --force to regenerate)"
    fi

    mkdir -p "$tenant_dir"
    chmod 700 "$tenant_dir"

    # Generate keypair
    wg genkey | tee "${tenant_dir}/private.key" | wg pubkey > "${tenant_dir}/public.key"
    chmod 600 "${tenant_dir}/private.key"
    chmod 644 "${tenant_dir}/public.key"

    log "Keys generated for tenant '$tenant'."
    log "  Private key: ${tenant_dir}/private.key"
    log "  Public key:  ${tenant_dir}/public.key"
}

# ---------------------------------------------------------------------------
# Client config output
# ---------------------------------------------------------------------------

print_client_config() {
    tenant="$1"
    tenant_dir="${PEER_DIR}/${tenant}"

    priv_key=$(cat "${tenant_dir}/private.key")

    # Read server public key (expected at well-known location)
    server_pub_key_file="${WG_BASE}/server-public.key"
    if [ -f "$server_pub_key_file" ]; then
        server_pub_key=$(cat "$server_pub_key_file")
    else
        server_pub_key="<SERVER_PUBLIC_KEY>"
        log "WARNING: Server public key not found at $server_pub_key_file"
        log "         Replace <SERVER_PUBLIC_KEY> in the client config manually."
    fi

    # Derive a tenant IP from the tenant config if available, else placeholder
    tenant_conf="/usr/local/etc/sparrow/tenants/${tenant}/tenant.conf"
    if [ -f "$tenant_conf" ]; then
        # shellcheck disable=SC1090
        . "$tenant_conf"
        tenant_ip="${TENANT_IP:-<TENANT_WG_IP>}"
    else
        tenant_ip="<TENANT_WG_IP>"
    fi

    # Server endpoint — read from server.conf or use placeholder
    if [ -f "$SERVER_CONF" ]; then
        server_endpoint=$(grep -E '^Endpoint' "$SERVER_CONF" | head -1 | awk '{print $3}')
    fi
    server_endpoint="${server_endpoint:-<SERVER_ENDPOINT>}"

    cat <<EOF

# ----- WireGuard client config for tenant: ${tenant} -----
# Save this as /usr/local/etc/wireguard/wg0.conf inside the tenant jail,
# or hand it to the tenant operator.

[Interface]
PrivateKey = ${priv_key}
Address = ${tenant_ip}/32
DNS = 10.99.0.1

[Peer]
PublicKey = ${server_pub_key}
Endpoint = ${server_endpoint}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    if [ $# -lt 1 ]; then
        usage
    fi

    tenant="$1"

    # Validate tenant name (alphanumeric + hyphens only)
    case "$tenant" in
        *[!a-zA-Z0-9_-]*)
            die "Invalid tenant name: '$tenant' (alphanumeric, hyphens, underscores only)"
            ;;
    esac

    if [ "$(id -u)" -ne 0 ]; then
        die "This script must be run as root."
    fi

    generate_keys "$tenant"
    print_client_config "$tenant"
}

main "$@"
