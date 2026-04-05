#!/bin/sh
#
# SparrowOS ISO Build Script
#
# Builds a complete SparrowOS installation ISO from FreeBSD 15.0-RELEASE source.
# Supports three install modes: Workstation, Server, Hybrid.
#
# Requirements:
#   - Must run on a FreeBSD amd64 system
#   - ZFS pool available for Poudriere
#   - Internet access (to fetch FreeBSD source if not cached)
#   - ~20GB free disk space
#
# Usage: ./build-iso.sh [--skip-world] [--skip-kernel] [--skip-packages]
#

set -eu

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SPARROW_VERSION="$(cat "${PROJECT_ROOT}/VERSION")"

FBSD_VERSION="15.0-RELEASE"
ARCH="amd64"
FBSD_SRC="/usr/src"

BUILD_DIR="/usr/obj/sparrow-build"
STAGE_DIR="${BUILD_DIR}/stage"
ISO_DIR="${BUILD_DIR}/iso"
ISO_NAME="SparrowOS-${SPARROW_VERSION}-${ARCH}.iso"

# Flags
SKIP_WORLD=0
SKIP_KERNEL=0
SKIP_PACKAGES=0

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-world)    SKIP_WORLD=1 ;;
        --skip-kernel)   SKIP_KERNEL=1 ;;
        --skip-packages) SKIP_PACKAGES=1 ;;
        --help|-h)
            echo "Usage: build-iso.sh [--skip-world] [--skip-kernel] [--skip-packages]"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================

log() { printf "\033[0;36m[sparrow-build]\033[0m %s\n" "$*"; }
log_ok() { printf "\033[0;32m[sparrow-build]\033[0m %s\n" "$*"; }
log_err() { printf "\033[0;31m[sparrow-build] ERROR:\033[0m %s\n" "$*" >&2; }

log "SparrowOS Build System v${SPARROW_VERSION}"
log "Target: FreeBSD ${FBSD_VERSION} / ${ARCH}"
log "Build dir: ${BUILD_DIR}"

# Must be FreeBSD
[ "$(uname -s)" = "FreeBSD" ] || { log_err "Must run on FreeBSD"; exit 1; }

# Must be root
[ "$(id -u)" -eq 0 ] || { log_err "Must run as root"; exit 1; }

# Check FreeBSD source exists
if [ ! -d "${FBSD_SRC}/sys" ]; then
    log "FreeBSD source not found at ${FBSD_SRC}. Fetching..."
    # TODO: git clone or fetch FreeBSD source
    log_err "Please install FreeBSD source tree at ${FBSD_SRC}"
    exit 1
fi

# ============================================================================
# STEP 1: PREPARE BUILD ENVIRONMENT
# ============================================================================

log "Preparing build environment..."
mkdir -p "${BUILD_DIR}" "${STAGE_DIR}" "${ISO_DIR}"

# Copy SparrowOS kernel config to source tree
cp "${PROJECT_ROOT}/base/kernel/SPARROW" "${FBSD_SRC}/sys/${ARCH}/conf/SPARROW"

# ============================================================================
# STEP 2: BUILD WORLD
# ============================================================================

if [ "${SKIP_WORLD}" -eq 0 ]; then
    log "Building world (this will take a while)..."
    cd "${FBSD_SRC}"
    make -j"$(sysctl -n hw.ncpu)" buildworld \
        SRCCONF="${PROJECT_ROOT}/base/src.conf" \
        __MAKE_CONF="${PROJECT_ROOT}/base/make.conf" \
        2>&1 | tail -5
    log_ok "World build complete."
else
    log "Skipping world build (--skip-world)"
fi

# ============================================================================
# STEP 3: BUILD KERNEL
# ============================================================================

if [ "${SKIP_KERNEL}" -eq 0 ]; then
    log "Building SPARROW kernel..."
    cd "${FBSD_SRC}"
    make -j"$(sysctl -n hw.ncpu)" buildkernel \
        KERNCONF=SPARROW \
        SRCCONF="${PROJECT_ROOT}/base/src.conf" \
        2>&1 | tail -5
    log_ok "Kernel build complete."
else
    log "Skipping kernel build (--skip-kernel)"
fi

# ============================================================================
# STEP 4: INSTALL TO STAGING DIRECTORY
# ============================================================================

log "Installing world and kernel to staging directory..."
cd "${FBSD_SRC}"

make installworld \
    DESTDIR="${STAGE_DIR}" \
    SRCCONF="${PROJECT_ROOT}/base/src.conf" \
    __MAKE_CONF="${PROJECT_ROOT}/base/make.conf"

make installkernel \
    DESTDIR="${STAGE_DIR}" \
    KERNCONF=SPARROW

make distribution \
    DESTDIR="${STAGE_DIR}" \
    SRCCONF="${PROJECT_ROOT}/base/src.conf"

log_ok "World and kernel installed to staging."

# ============================================================================
# STEP 5: OVERLAY SPARROWOS CONFIGURATION
# ============================================================================

log "Applying SparrowOS configuration overlay..."

# Boot configuration
install -m 644 "${PROJECT_ROOT}/base/loader.conf" "${STAGE_DIR}/boot/loader.conf"
install -m 644 "${PROJECT_ROOT}/base/sysctl.conf" "${STAGE_DIR}/etc/sysctl.conf"
install -m 644 "${PROJECT_ROOT}/base/rc.conf" "${STAGE_DIR}/etc/rc.conf"

# Security configuration
mkdir -p "${STAGE_DIR}/etc/pf.tables"
install -m 600 "${PROJECT_ROOT}/security/pf/pf.conf" "${STAGE_DIR}/etc/pf.conf"
install -m 644 "${PROJECT_ROOT}/security/hardening/sysctl-hardening.conf" \
    "${STAGE_DIR}/etc/sysctl.d/sparrow-hardening.conf"

# Audit configuration
mkdir -p "${STAGE_DIR}/etc/security"
if [ -f "${PROJECT_ROOT}/security/hardening/audit/audit_control" ]; then
    install -m 640 "${PROJECT_ROOT}/security/hardening/audit/audit_control" \
        "${STAGE_DIR}/etc/security/audit_control"
fi

# rctl profiles
mkdir -p "${STAGE_DIR}/usr/local/etc/sparrow/rctl-profiles"
for _profile in "${PROJECT_ROOT}"/tenant/rctl-profiles/*.conf; do
    [ -f "$_profile" ] && install -m 644 "$_profile" \
        "${STAGE_DIR}/usr/local/etc/sparrow/rctl-profiles/"
done

# Tenant management CLI
mkdir -p "${STAGE_DIR}/usr/local/bin"
install -m 755 "${PROJECT_ROOT}/tenant/sparrow-tenant" "${STAGE_DIR}/usr/local/bin/sparrow-tenant"

# AI tool wrapper
if [ -f "${PROJECT_ROOT}/ai/common/sparrow-ai" ]; then
    install -m 755 "${PROJECT_ROOT}/ai/common/sparrow-ai" "${STAGE_DIR}/usr/local/bin/sparrow-ai"
fi

# Desktop configuration (Sway, Foot, Waybar, etc.)
# These go into /usr/local/share/sparrow/ and are copied to user home on first login
_skel="${STAGE_DIR}/usr/local/share/sparrow/skel"
mkdir -p "${_skel}/.config/sway/config.d"
mkdir -p "${_skel}/.config/waybar"
mkdir -p "${_skel}/.config/foot"
mkdir -p "${_skel}/.config/fuzzel"
mkdir -p "${_skel}/.config/helix/themes"

cp "${PROJECT_ROOT}/desktop/sway/config" "${_skel}/.config/sway/config"
for _f in "${PROJECT_ROOT}"/desktop/sway/config.d/*; do
    [ -f "$_f" ] && cp "$_f" "${_skel}/.config/sway/config.d/"
done

[ -f "${PROJECT_ROOT}/desktop/foot/foot.ini" ] && \
    cp "${PROJECT_ROOT}/desktop/foot/foot.ini" "${_skel}/.config/foot/foot.ini"
[ -f "${PROJECT_ROOT}/desktop/fuzzel/fuzzel.ini" ] && \
    cp "${PROJECT_ROOT}/desktop/fuzzel/fuzzel.ini" "${_skel}/.config/fuzzel/fuzzel.ini"
[ -f "${PROJECT_ROOT}/desktop/waybar/config.jsonc" ] && \
    cp "${PROJECT_ROOT}/desktop/waybar/config.jsonc" "${_skel}/.config/waybar/config.jsonc"
[ -f "${PROJECT_ROOT}/desktop/waybar/style.css" ] && \
    cp "${PROJECT_ROOT}/desktop/waybar/style.css" "${_skel}/.config/waybar/style.css"

# Helix editor config
for _f in config.toml languages.toml; do
    [ -f "${PROJECT_ROOT}/devtools/helix/${_f}" ] && \
        cp "${PROJECT_ROOT}/devtools/helix/${_f}" "${_skel}/.config/helix/"
done
[ -f "${PROJECT_ROOT}/devtools/helix/themes/sparrow.toml" ] && \
    cp "${PROJECT_ROOT}/devtools/helix/themes/sparrow.toml" "${_skel}/.config/helix/themes/"

# Zsh config
[ -f "${PROJECT_ROOT}/devtools/zsh/zshrc" ] && \
    cp "${PROJECT_ROOT}/devtools/zsh/zshrc" "${_skel}/.zshrc"

# Boot splash
if [ -f "${PROJECT_ROOT}/ux/boot/splash.bmp" ]; then
    install -m 644 "${PROJECT_ROOT}/ux/boot/splash.bmp" \
        "${STAGE_DIR}/boot/sparrow-splash.bmp"
fi

# Onboarding script
if [ -f "${PROJECT_ROOT}/ux/onboarding/sparrow-setup" ]; then
    install -m 755 "${PROJECT_ROOT}/ux/onboarding/sparrow-setup" \
        "${STAGE_DIR}/usr/local/bin/sparrow-setup"
fi

# MOTD
if [ -f "${PROJECT_ROOT}/ux/motd/motd.sh" ]; then
    install -m 755 "${PROJECT_ROOT}/ux/motd/motd.sh" \
        "${STAGE_DIR}/usr/local/bin/sparrow-motd"
fi

# pf anchor template for tenants
if [ -f "${PROJECT_ROOT}/security/pf/pf-tenant.conf.tmpl" ]; then
    install -m 644 "${PROJECT_ROOT}/security/pf/pf-tenant.conf.tmpl" \
        "${STAGE_DIR}/usr/local/etc/sparrow/pf-tenant.conf.tmpl"
fi

log_ok "Configuration overlay applied."

# ============================================================================
# STEP 6: INSTALL PACKAGES
# ============================================================================

if [ "${SKIP_PACKAGES}" -eq 0 ]; then
    log "Installing packages from Poudriere repository..."

    # Mount devfs and resolv.conf for pkg to work in chroot
    mount -t devfs devfs "${STAGE_DIR}/dev"
    cp /etc/resolv.conf "${STAGE_DIR}/etc/resolv.conf"

    # Install packages
    chroot "${STAGE_DIR}" env ASSUME_ALWAYS_YES=yes \
        pkg install -y $(cat "${PROJECT_ROOT}/build/poudriere/sparrow-pkglist.txt" | \
        grep -v '^#' | grep -v '^$' | tr '\n' ' ')

    # Cleanup chroot mounts
    umount "${STAGE_DIR}/dev"

    log_ok "Packages installed."
else
    log "Skipping package installation (--skip-packages)"
fi

# ============================================================================
# STEP 7: CONFIGURE INSTALLER
# ============================================================================

log "Configuring installer..."

# Copy installerconfig for automated installation
mkdir -p "${STAGE_DIR}/etc/installerconfig.d"
if [ -f "${PROJECT_ROOT}/build/iso/installerconfig" ]; then
    install -m 644 "${PROJECT_ROOT}/build/iso/installerconfig" \
        "${STAGE_DIR}/etc/installerconfig"
fi

# Post-install hooks
for _hook in "${PROJECT_ROOT}"/build/iso/install-hooks/*.sh; do
    [ -f "$_hook" ] && install -m 755 "$_hook" "${STAGE_DIR}/etc/installerconfig.d/"
done

# ============================================================================
# STEP 8: GENERATE ISO
# ============================================================================

log "Generating ISO image: ${ISO_NAME}..."

cd "${FBSD_SRC}/release"

# Use FreeBSD's release infrastructure
# This creates a bootable ISO with BIOS and UEFI support
make cdrom \
    DESTDIR="${STAGE_DIR}" \
    KERNCONF=SPARROW \
    VOLUME_LABEL="SparrowOS" \
    2>&1 | tail -5

# Move ISO to output directory
if [ -f "${BUILD_DIR}/release/cdrom/SparrowOS.iso" ]; then
    mv "${BUILD_DIR}/release/cdrom/SparrowOS.iso" "${ISO_DIR}/${ISO_NAME}"
else
    # Fallback: use mkisoimages.sh directly
    log "Using mkisoimages.sh fallback..."
    sh "${FBSD_SRC}/release/amd64/mkisoimages.sh" \
        -b "${STAGE_DIR}/boot" \
        "${ISO_DIR}/${ISO_NAME}" \
        "${STAGE_DIR}"
fi

log_ok "ISO generated: ${ISO_DIR}/${ISO_NAME}"

# ============================================================================
# STEP 9: CHECKSUMS AND SIGNING
# ============================================================================

log "Generating checksums..."
cd "${ISO_DIR}"
sha256 "${ISO_NAME}" > "${ISO_NAME}.sha256"
sha512 "${ISO_NAME}" > "${ISO_NAME}.sha512"

# GPG sign if key is available
if command -v gpg >/dev/null 2>&1 && gpg --list-secret-keys 2>/dev/null | grep -q "sparrow"; then
    log "Signing ISO with GPG..."
    gpg --armor --detach-sign "${ISO_NAME}"
    log_ok "ISO signed."
else
    log "GPG key not found — skipping signing (run sign-release.sh manually)"
fi

# ============================================================================
# SUMMARY
# ============================================================================

_size=$(ls -lh "${ISO_DIR}/${ISO_NAME}" | awk '{print $5}')

log_ok "============================================"
log_ok "SparrowOS ${SPARROW_VERSION} Build Complete!"
log_ok "============================================"
log_ok "ISO:       ${ISO_DIR}/${ISO_NAME}"
log_ok "Size:      ${_size}"
log_ok "SHA-256:   $(cat "${ISO_DIR}/${ISO_NAME}.sha256")"
log_ok ""
log_ok "Test with: qemu-system-x86_64 -m 4G -cdrom ${ISO_DIR}/${ISO_NAME}"
log_ok "============================================"
