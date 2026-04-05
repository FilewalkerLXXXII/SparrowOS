#!/bin/sh
# ===========================================================================
# SparrowOS -- ZFS Pool & Dataset Layout
# ===========================================================================
# Creates the "sparrow" ZFS pool and its full dataset hierarchy for a
# hybrid Workstation / Multi-Tenant Server installation.
#
# Usage:  layout.sh <disk-partition>
#         e.g.  layout.sh ada0p4
#
# The script expects the target partition to already exist and be unused.
# It is normally called by encryption.sh after GELI setup, but can also
# be run standalone on an unencrypted partition.
# ===========================================================================
set -eu

# ---- argument handling ----------------------------------------------------
if [ $# -lt 1 ]; then
    echo "Usage: $0 <disk-partition>" >&2
    echo "  e.g. $0 ada0p4" >&2
    exit 1
fi

DISK="$1"

# ---- pool defaults --------------------------------------------------------
POOL="sparrow"

echo ">>> Creating ZFS pool '${POOL}' on /dev/${DISK} ..."
zpool create -f \
    -o ashift=12 \
    -O compression=lz4 \
    -O atime=off \
    -O mountpoint=none \
    "${POOL}" "/dev/${DISK}"

# ---- Boot environment (root filesystem) -----------------------------------
echo ">>> Creating ROOT datasets ..."
zfs create -o canmount=off                  "${POOL}/ROOT"
zfs create -o canmount=noauto -o mountpoint=/ "${POOL}/ROOT/default"

# Mark the default boot environment so the loader finds it.
zpool set bootfs="${POOL}/ROOT/default" "${POOL}"

# ---- /usr hierarchy -------------------------------------------------------
echo ">>> Creating /usr datasets ..."
zfs create -o mountpoint=/usr/local          "${POOL}/usr"
zfs create -o mountpoint=/usr/local          "${POOL}/usr/local"
zfs create -o mountpoint=/usr/src            "${POOL}/usr/src"
zfs create -o mountpoint=/usr/obj            "${POOL}/usr/obj"

# ---- /var hierarchy -------------------------------------------------------
echo ">>> Creating /var datasets ..."
zfs create -o mountpoint=/var/log  -o exec=off               "${POOL}/var"
zfs create -o mountpoint=/var/log  -o exec=off               "${POOL}/var/log"
zfs create -o mountpoint=/var/tmp  -o exec=off -o setuid=off "${POOL}/var/tmp"

# ---- /home ----------------------------------------------------------------
echo ">>> Creating /home dataset ..."
zfs create -o mountpoint=/home               "${POOL}/home"

# ---- Jails ----------------------------------------------------------------
echo ">>> Creating jails datasets ..."
zfs create -o mountpoint=/jails              "${POOL}/jails"
zfs create                                   "${POOL}/jails/base"
zfs create                                   "${POOL}/jails/templates"

# ---- Multi-tenant root ----------------------------------------------------
# The "tenants" dataset is a container; per-tenant child datasets are created
# at provisioning time (e.g. sparrow/tenants/acme).  setuid=off prevents
# tenants from running setuid binaries.
echo ">>> Creating tenants dataset ..."
zfs create -o mountpoint=/tenants -o setuid=off "${POOL}/tenants"

echo ">>> ZFS layout complete."
zfs list -r "${POOL}"
