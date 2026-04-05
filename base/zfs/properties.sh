#!/bin/sh
# ===========================================================================
# SparrowOS -- Post-Creation ZFS Property Tuning
# ===========================================================================
# Applies per-dataset ZFS properties that fine-tune performance, safety,
# and access-control after the initial pool/dataset hierarchy has been
# created by layout.sh.
#
# Run once after layout.sh (or re-run safely -- all operations are
# idempotent).
#
# Usage:  properties.sh
# ===========================================================================
set -eu

POOL="sparrow"

echo ">>> Applying ZFS property tuning to pool '${POOL}' ..."

# ---- /var/log -- optimise for sequential log writes -----------------------
# throughput logbias tells ZFS to prefer larger, batched writes which is
# ideal for append-heavy log workloads.  128K recordsize matches the
# typical log rotation chunk size and reduces metadata overhead.
echo "    var/log : logbias=throughput, recordsize=128K"
zfs set logbias=throughput "${POOL}/var/log"
zfs set recordsize=128K    "${POOL}/var/log"

# ---- /home -- extra redundancy for user data ------------------------------
# copies=2 keeps two copies of every block within the pool, providing a
# safety net against silent corruption even on a single-disk system.
echo "    home    : copies=2"
zfs set copies=2 "${POOL}/home"

# ---- /tenants -- container-only dataset -----------------------------------
# canmount=off ensures the parent "tenants" dataset is never mounted
# directly.  Individual tenant datasets (sparrow/tenants/<name>) inherit
# the mountpoint prefix and mount automatically.
echo "    tenants : canmount=off"
zfs set canmount=off "${POOL}/tenants"

# ---- /jails -- container-only dataset -------------------------------------
# Same rationale as /tenants: the parent is organisational; only children
# (base, templates, per-jail datasets) should mount.
echo "    jails   : canmount=off"
zfs set canmount=off "${POOL}/jails"

# ---- /usr/obj -- speed over safety for build artifacts --------------------
# Build objects are fully reproducible, so we disable the ZIL sync to
# accelerate compile workloads.  Data loss on crash is acceptable here
# because a rebuild is trivial.
echo "    usr/obj : sync=disabled"
zfs set sync=disabled "${POOL}/usr/obj"

echo ">>> ZFS property tuning complete."
