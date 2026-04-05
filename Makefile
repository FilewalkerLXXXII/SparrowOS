#
# SparrowOS — Top-Level Build Orchestrator
#
# Usage:
#   make iso        — Build the complete SparrowOS ISO
#   make world      — Build FreeBSD world with SparrowOS config
#   make kernel     — Build custom SPARROW kernel
#   make packages   — Build packages via Poudriere
#   make test       — Run smoke tests in VM
#   make clean      — Clean build artifacts
#

.PHONY: all world kernel packages iso test clean lint

SPARROW_VERSION != cat VERSION
FBSD_SRC ?= /usr/src
NCPU != sysctl -n hw.ncpu 2>/dev/null || echo 4
SRCCONF = $(CURDIR)/base/src.conf
MAKECONF = $(CURDIR)/base/make.conf

all: iso

# ============================================================================
# BUILD TARGETS
# ============================================================================

world:
	@echo "=== Building FreeBSD world ==="
	cd $(FBSD_SRC) && make -j$(NCPU) buildworld \
		SRCCONF=$(SRCCONF) __MAKE_CONF=$(MAKECONF)

kernel:
	@echo "=== Building SPARROW kernel ==="
	cp base/kernel/SPARROW $(FBSD_SRC)/sys/amd64/conf/SPARROW
	cd $(FBSD_SRC) && make -j$(NCPU) buildkernel KERNCONF=SPARROW \
		SRCCONF=$(SRCCONF)

packages:
	@echo "=== Building packages via Poudriere ==="
	poudriere bulk -j sparrow-builder -p default \
		-f build/poudriere/sparrow-pkglist.txt

iso: world kernel packages
	@echo "=== Building SparrowOS ISO v$(SPARROW_VERSION) ==="
	sh build/iso/build-iso.sh

iso-quick:
	@echo "=== Building ISO (skip world/kernel/packages) ==="
	sh build/iso/build-iso.sh --skip-world --skip-kernel --skip-packages

# ============================================================================
# TESTING
# ============================================================================

test:
	@echo "=== Running smoke tests ==="
	sh tests/vm/bhyve-test.sh

test-qemu:
	@echo "=== Running QEMU smoke test ==="
	sh tests/vm/qemu-test.sh

test-security:
	@echo "=== Running security audit tests ==="
	sh tests/security/audit-capsicum.sh
	sh tests/security/audit-pf.sh
	sh tests/security/audit-jail-escape.sh
	sh tests/security/audit-tenant-isolation.sh

test-tenant:
	@echo "=== Running tenant lifecycle tests ==="
	sh tests/tenant/test-tenant-create.sh
	sh tests/tenant/test-tenant-limits.sh
	sh tests/tenant/test-tenant-access.sh

# ============================================================================
# VALIDATION
# ============================================================================

lint:
	@echo "=== Validating configs ==="
	@# Check shell scripts for syntax errors
	@for f in $$(find . -name '*.sh' -type f); do \
		sh -n "$$f" || exit 1; \
	done
	@echo "All shell scripts valid."
	@# Check pf config syntax (requires FreeBSD)
	@if command -v pfctl >/dev/null 2>&1; then \
		pfctl -nf security/pf/pf.conf && echo "pf.conf valid."; \
	fi

# ============================================================================
# CLEANUP
# ============================================================================

clean:
	@echo "=== Cleaning build artifacts ==="
	rm -rf /usr/obj/sparrow-build

distclean: clean
	@echo "=== Deep clean (including Poudriere data) ==="
	@echo "WARNING: This will remove Poudriere build data."
	@echo "Run 'poudriere jail -d -j sparrow-builder' manually if needed."

# ============================================================================
# POUDRIERE SETUP (one-time)
# ============================================================================

poudriere-setup:
	@echo "=== Setting up Poudriere build environment ==="
	poudriere jail -c -j sparrow-builder -v $(FBSD_VERSION) -a $(ARCH)
	poudriere ports -c -p default

# ============================================================================
# INFO
# ============================================================================

info:
	@echo "SparrowOS v$(SPARROW_VERSION)"
	@echo "Target: FreeBSD 15.0-RELEASE / amd64"
	@echo "Kernel: SPARROW"
	@echo "Build machine: $$(hostname)"
	@echo "CPUs available: $(NCPU)"

.DEFAULT_GOAL := all
