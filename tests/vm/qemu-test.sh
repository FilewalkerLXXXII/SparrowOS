#!/bin/sh
#
# SparrowOS QEMU Test Harness (macOS Apple Silicon)
#
# Downloads FreeBSD 14.2-RELEASE aarch64 VM image, boots it with HVF
# acceleration, and provisions SparrowOS configs for testing.
#
# Usage:
#   ./qemu-test.sh              # Download image + boot VM
#   ./qemu-test.sh boot         # Boot existing VM (skip download)
#   ./qemu-test.sh provision    # Copy SparrowOS configs into running VM
#   ./qemu-test.sh clean        # Remove VM disk image
#

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VM_DIR="${PROJECT_ROOT}/tests/vm"

# FreeBSD 14.2-RELEASE aarch64 (latest stable with aarch64 VM images)
# Note: FreeBSD 15.0 may not have VM images yet; 14.2 is close enough for config testing
FBSD_VERSION="14.2"
FBSD_ARCH="aarch64"
FBSD_IMAGE_URL="https://download.freebsd.org/releases/VM-IMAGES/${FBSD_VERSION}-RELEASE/${FBSD_ARCH}/Latest/FreeBSD-${FBSD_VERSION}-RELEASE-${FBSD_ARCH}.qcow2.xz"
FBSD_IMAGE="${VM_DIR}/FreeBSD-${FBSD_VERSION}-RELEASE-${FBSD_ARCH}.qcow2"
VM_DISK="${VM_DIR}/sparrow-test.qcow2"

# QEMU settings
QEMU_BIN="qemu-system-aarch64"
QEMU_RAM="8G"
QEMU_CPUS="4"
SSH_PORT="2222"
VNC_PORT="5900"

# EFI firmware for aarch64
QEMU_EFI="/opt/homebrew/share/qemu/edk2-aarch64-code.fd"

# Colors
log()    { printf "\033[0;36m[qemu-test]\033[0m %s\n" "$*"; }
log_ok() { printf "\033[0;32m[qemu-test]\033[0m %s\n" "$*"; }
log_err(){ printf "\033[0;31m[qemu-test] ERROR:\033[0m %s\n" "$*" >&2; }

# ============================================================================
# DOWNLOAD
# ============================================================================

cmd_download() {
    if [ -f "$VM_DISK" ]; then
        log "VM disk already exists: $VM_DISK"
        return 0
    fi

    if [ ! -f "$FBSD_IMAGE" ]; then
        log "Downloading FreeBSD ${FBSD_VERSION}-RELEASE ${FBSD_ARCH} VM image..."
        log "URL: ${FBSD_IMAGE_URL}"
        curl -L -o "${FBSD_IMAGE}.xz" "$FBSD_IMAGE_URL"
        log "Decompressing..."
        xz -d "${FBSD_IMAGE}.xz"
        log_ok "Download complete: ${FBSD_IMAGE}"
    fi

    # Create a working copy (don't modify the original)
    log "Creating VM disk from base image..."
    qemu-img create -f qcow2 -b "$FBSD_IMAGE" -F qcow2 "$VM_DISK" 64G
    log_ok "VM disk created: ${VM_DISK} (64GB, backed by base image)"
}

# ============================================================================
# BOOT
# ============================================================================

cmd_boot() {
    [ -f "$VM_DISK" ] || { log_err "VM disk not found. Run: $0 download"; exit 1; }

    # Check for EFI firmware
    if [ ! -f "$QEMU_EFI" ]; then
        # Try alternate locations
        for _efi in \
            /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
            /usr/local/share/qemu/edk2-aarch64-code.fd \
            /opt/homebrew/Cellar/qemu/*/share/qemu/edk2-aarch64-code.fd; do
            if [ -f "$_efi" ]; then
                QEMU_EFI="$_efi"
                break
            fi
        done
        [ -f "$QEMU_EFI" ] || { log_err "UEFI firmware not found at $QEMU_EFI"; exit 1; }
    fi

    log "Booting SparrowOS test VM..."
    log "  RAM: ${QEMU_RAM}, CPUs: ${QEMU_CPUS}"
    log "  SSH: localhost:${SSH_PORT}"
    log "  Console: serial output below"
    log ""
    log "  Connect via SSH:  ssh -p ${SSH_PORT} root@localhost"
    log "  Default password: (empty or 'root' for FreeBSD VM images)"
    log ""
    log "  Press Ctrl+A, X to quit QEMU"
    log ""

    ${QEMU_BIN} \
        -machine virt,accel=hvf,highmem=on \
        -cpu host \
        -m "${QEMU_RAM}" \
        -smp "${QEMU_CPUS}" \
        -bios "${QEMU_EFI}" \
        -drive if=virtio,file="${VM_DISK}",format=qcow2 \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
        -device virtio-rng-pci \
        -nographic
}

# ============================================================================
# BOOT WITH GRAPHICS (VNC)
# ============================================================================

cmd_boot_gui() {
    [ -f "$VM_DISK" ] || { log_err "VM disk not found. Run: $0 download"; exit 1; }

    log "Booting SparrowOS test VM with VNC display..."
    log "  VNC: localhost:${VNC_PORT}"
    log "  SSH: localhost:${SSH_PORT}"
    log ""
    log "  Connect VNC viewer to: localhost:${VNC_PORT}"
    log "  Connect via SSH: ssh -p ${SSH_PORT} root@localhost"
    log ""

    ${QEMU_BIN} \
        -machine virt,accel=hvf,highmem=on \
        -cpu host \
        -m "${QEMU_RAM}" \
        -smp "${QEMU_CPUS}" \
        -bios "${QEMU_EFI}" \
        -drive if=virtio,file="${VM_DISK}",format=qcow2 \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
        -device virtio-gpu-pci \
        -device virtio-rng-pci \
        -display vnc=:0 \
        -daemonize

    log_ok "VM started in background. VNC: localhost:${VNC_PORT}, SSH: localhost:${SSH_PORT}"
}

# ============================================================================
# PROVISION (copy SparrowOS configs into running VM)
# ============================================================================

cmd_provision() {
    log "Provisioning SparrowOS configs into VM..."

    SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${SSH_PORT} root@localhost"
    SCP_CMD="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P ${SSH_PORT}"

    # Check VM is reachable
    ${SSH_CMD} "echo 'VM reachable'" 2>/dev/null || {
        log_err "Cannot reach VM on port ${SSH_PORT}. Is it running?"
        exit 1
    }

    # Create directory structure
    ${SSH_CMD} "mkdir -p /usr/local/etc/sparrow/rctl-profiles /usr/local/bin /etc/pf.anchors /etc/pf.tables"

    # Security configs
    log "  Copying pf.conf..."
    ${SCP_CMD} "${PROJECT_ROOT}/security/pf/pf.conf" root@localhost:/etc/pf.conf
    ${SCP_CMD} "${PROJECT_ROOT}/security/pf/tables/ai-allowed-hosts" root@localhost:/etc/pf.tables/ai-allowed-hosts
    ${SCP_CMD} "${PROJECT_ROOT}/security/hardening/sysctl-hardening.conf" root@localhost:/etc/sysctl.d/sparrow-hardening.conf 2>/dev/null || \
        ${SCP_CMD} "${PROJECT_ROOT}/security/hardening/sysctl-hardening.conf" root@localhost:/etc/sysctl.conf.sparrow

    # Base configs
    log "  Copying base configs..."
    ${SCP_CMD} "${PROJECT_ROOT}/base/sysctl.conf" root@localhost:/etc/sysctl.conf.sparrow
    ${SCP_CMD} "${PROJECT_ROOT}/base/rc.conf" root@localhost:/etc/rc.conf.sparrow

    # Tenant management
    log "  Copying tenant tools..."
    ${SCP_CMD} "${PROJECT_ROOT}/tenant/sparrow-tenant" root@localhost:/usr/local/bin/sparrow-tenant
    ${SSH_CMD} "chmod +x /usr/local/bin/sparrow-tenant"
    for _profile in small medium large; do
        ${SCP_CMD} "${PROJECT_ROOT}/tenant/rctl-profiles/${_profile}.conf" \
            root@localhost:/usr/local/etc/sparrow/rctl-profiles/
    done

    # AI tools
    log "  Copying AI tool wrappers..."
    ${SCP_CMD} "${PROJECT_ROOT}/ai/common/sparrow-ai" root@localhost:/usr/local/bin/sparrow-ai
    ${SSH_CMD} "chmod +x /usr/local/bin/sparrow-ai"

    # MOTD
    log "  Copying MOTD..."
    ${SCP_CMD} "${PROJECT_ROOT}/ux/motd/motd.sh" root@localhost:/usr/local/bin/sparrow-motd
    ${SSH_CMD} "chmod +x /usr/local/bin/sparrow-motd"

    # Shell configs (for root testing)
    log "  Copying shell/editor configs..."
    ${SSH_CMD} "mkdir -p ~/.config/helix/themes"
    ${SCP_CMD} "${PROJECT_ROOT}/devtools/helix/config.toml" root@localhost:~/.config/helix/config.toml
    ${SCP_CMD} "${PROJECT_ROOT}/devtools/helix/themes/sparrow.toml" root@localhost:~/.config/helix/themes/sparrow.toml

    # Install packages needed for testing
    log "  Installing test packages (this may take a while)..."
    ${SSH_CMD} "env ASSUME_ALWAYS_YES=yes pkg update && pkg install -y bash tmux git" 2>/dev/null || \
        log "  Package install skipped (may need manual setup)"

    log_ok "Provisioning complete!"
    log ""
    log "Test commands:"
    log "  ssh -p ${SSH_PORT} root@localhost"
    log "  sparrow-tenant list"
    log "  sparrow-motd"
    log "  pfctl -sr  (check firewall rules)"
}

# ============================================================================
# SMOKE TEST (automated)
# ============================================================================

cmd_smoke() {
    log "Running smoke tests against VM..."

    SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${SSH_PORT} root@localhost"
    PASS=0
    FAIL=0

    run_test() {
        _name="$1"
        shift
        printf "  %-40s " "$_name"
        if ${SSH_CMD} "$@" >/dev/null 2>&1; then
            printf "\033[0;32mPASS\033[0m\n"
            PASS=$((PASS + 1))
        else
            printf "\033[0;31mFAIL\033[0m\n"
            FAIL=$((FAIL + 1))
        fi
    }

    run_test "VM reachable"                    "true"
    run_test "FreeBSD version"                 "uname -r | grep -q RELEASE"
    run_test "ZFS loaded"                      "kldstat | grep -q zfs || zfs list >/dev/null 2>&1"
    run_test "pf.conf syntax valid"            "pfctl -nf /etc/pf.conf"
    run_test "sparrow-tenant exists"           "test -x /usr/local/bin/sparrow-tenant"
    run_test "sparrow-tenant --help"           "/usr/local/bin/sparrow-tenant help"
    run_test "sparrow-ai exists"               "test -x /usr/local/bin/sparrow-ai"
    run_test "sparrow-motd runs"               "/usr/local/bin/sparrow-motd"
    run_test "sysctl hardening applied"        "sysctl security.bsd.see_other_uids | grep -q 0"
    run_test "pkg available"                   "pkg -N"

    log ""
    log_ok "Results: ${PASS} passed, ${FAIL} failed"

    [ "$FAIL" -eq 0 ] && return 0 || return 1
}

# ============================================================================
# CLEAN
# ============================================================================

cmd_clean() {
    log "Cleaning VM artifacts..."
    rm -f "$VM_DISK"
    log_ok "VM disk removed."
    log "Base image kept at: ${FBSD_IMAGE}"
    log "To remove everything: rm -f ${VM_DIR}/FreeBSD-* ${VM_DIR}/sparrow-*"
}

# ============================================================================
# MAIN
# ============================================================================

usage() {
    cat <<EOF
SparrowOS QEMU Test Harness

Usage: $0 [command]

Commands:
  download    Download FreeBSD VM image and create test disk
  boot        Boot VM with serial console (Ctrl+A, X to quit)
  boot-gui    Boot VM with VNC display (connect viewer to :5900)
  provision   Copy SparrowOS configs into running VM
  smoke       Run automated smoke tests against VM
  clean       Remove VM disk image

Default (no args): download + boot
EOF
}

case "${1:-default}" in
    download)   cmd_download ;;
    boot)       cmd_boot ;;
    boot-gui)   cmd_boot_gui ;;
    provision)  cmd_provision ;;
    smoke)      cmd_smoke ;;
    clean)      cmd_clean ;;
    help|--help|-h) usage ;;
    default)    cmd_download && cmd_boot ;;
    *)          log_err "Unknown command: $1"; usage; exit 1 ;;
esac
