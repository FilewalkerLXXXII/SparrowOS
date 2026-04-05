#!/bin/sh
# ===========================================================================
# SparrowOS -- GELI Full-Disk Encryption + ZFS Setup
# ===========================================================================
# Partitions the target disk with GPT, encrypts the swap and ZFS partitions
# with GELI (AES-XTS 256), then hands off to layout.sh for dataset creation.
#
# Usage:  encryption.sh <disk-device>
#         e.g.  encryption.sh ada0
#
# Partition map created:
#   p1  freebsd-boot   512K   (BIOS boot code)
#   p2  efi            1G     (EFI System Partition)
#   p3  freebsd-swap   4G     (GELI-encrypted swap)
#   p4  freebsd-zfs    rest   (GELI-encrypted ZFS)
# ===========================================================================
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- argument handling ----------------------------------------------------
if [ $# -lt 1 ]; then
    echo "Usage: $0 <disk-device>" >&2
    echo "  e.g. $0 ada0" >&2
    exit 1
fi

DISK="$1"
DEV="/dev/${DISK}"

if [ ! -c "${DEV}" ]; then
    echo "Error: ${DEV} is not a character device." >&2
    exit 1
fi

# ---- confirm destructive operation ----------------------------------------
echo "WARNING: This will DESTROY all data on ${DEV}."
printf "Type 'yes' to continue: "
read -r CONFIRM
if [ "${CONFIRM}" != "yes" ]; then
    echo "Aborted." >&2
    exit 1
fi

# ---- load GELI kernel module if needed ------------------------------------
if ! kldstat -q -m g_eli 2>/dev/null; then
    echo ">>> Loading GELI kernel module ..."
    kldload geom_eli
fi

# ---- GPT partitioning -----------------------------------------------------
echo ">>> Destroying any existing partition table on ${DEV} ..."
gpart destroy -F "${DISK}" 2>/dev/null || true

echo ">>> Creating GPT scheme on ${DISK} ..."
gpart create -s gpt "${DISK}"

echo ">>> Creating partitions ..."
# p1 -- BIOS boot (512K)
gpart add -t freebsd-boot -s 512K  -l sparrow-boot "${DISK}"

# p2 -- EFI System Partition (1G)
gpart add -t efi           -s 1G   -l sparrow-efi  "${DISK}"

# p3 -- Swap (4G, will be GELI encrypted)
gpart add -t freebsd-swap  -s 4G   -l sparrow-swap "${DISK}"

# p4 -- ZFS (remainder of disk, will be GELI encrypted)
gpart add -t freebsd-zfs           -l sparrow-zfs  "${DISK}"

# ---- Write boot code ------------------------------------------------------
echo ">>> Installing boot code ..."
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 "${DISK}"

# ---- Format EFI partition --------------------------------------------------
echo ">>> Formatting EFI partition ..."
newfs_msdos -F 32 "/dev/${DISK}p2"

# ---- GELI encryption -- swap (one-time key, no passphrase) ----------------
echo ">>> Initializing GELI on swap (${DISK}p3) with one-time keys ..."
# Swap uses a random one-time key each boot (configured via /etc/fstab and
# /etc/rc.conf).  We initialise the provider here so the device node is ready.
geli onetime -e AES-XTS -l 256 "/dev/${DISK}p3"

# ---- GELI encryption -- ZFS (passphrase-protected) ------------------------
echo ""
echo ">>> Initializing GELI on ZFS partition (${DISK}p4)."
echo "    Cipher: AES-XTS, Key length: 256 bits"
echo "    You will be prompted to set an encryption passphrase."
echo ""

geli init \
    -e AES-XTS \
    -l 256 \
    -s 4096 \
    "/dev/${DISK}p4"

echo ">>> Attaching GELI provider for ${DISK}p4 ..."
geli attach "/dev/${DISK}p4"

# The decrypted device is now available at /dev/${DISK}p4.eli
GELI_DEV="${DISK}p4.eli"

# ---- Hand off to layout.sh for ZFS dataset creation -----------------------
echo ">>> Calling layout.sh to build ZFS dataset hierarchy ..."
sh "${SCRIPT_DIR}/layout.sh" "${GELI_DEV}"

echo ""
echo ">>> Encryption setup complete."
echo "    Encrypted swap : /dev/${DISK}p3.eli"
echo "    Encrypted ZFS  : /dev/${GELI_DEV}"
echo ""
echo "Remember to back up your GELI metadata:"
echo "    geli backup /dev/${DISK}p4 /root/${DISK}p4.eli.bak"
