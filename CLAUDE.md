# SparrowOS — Agent Rules

## What This Project Is

SparrowOS is a **FreeBSD 15.0-based hybrid Workstation OS / Multi-Tenant Server OS** distribution.
It is NOT a from-scratch kernel. It is a build system + configuration overlay that produces a
reproducible, hardened FreeBSD installation ISO with a cyberpunk-themed Wayland desktop and
first-class AI coding tool integration.

**Mantra:** Speed and Security with Simple-intuitive UX.

## Architecture Overview

- **Base:** FreeBSD 15.0 + pkgbase, custom SPARROW kernel
- **Security:** Capsicum + MAC Biba + pf firewall + VNET jails + rctl resource limits
- **Desktop (host only):** Sway compositor, Foot terminal, Waybar, Fuzzel launcher
- **Multi-tenant:** VNET jails per tenant, ZFS datasets with encryption+quotas, WireGuard VPN, code-server per tenant
- **AI tools:** Claude Code, Codex CLI, Gemini CLI — sandboxed in jails, network-restricted via pf
- **Filesystem:** ZFS on GELI-encrypted root, boot environments, per-tenant encrypted datasets
- **Aesthetic:** Cyberpunk "Hackers" movie — neon green (#00ff00), cyan (#00ffff), magenta (#ff00ff) on #0a0a0a

## Install Modes

The ISO supports three install types selected at install time:
- **Workstation** — Sway desktop, local dev tools, no tenant system
- **Server** — Headless, tenant system + WireGuard, no desktop
- **Hybrid** — Both simultaneously (default)

## Code Conventions

- Shell scripts: POSIX sh (`#!/bin/sh`) where possible, bash only when required
- All scripts start with `set -eu` (strict mode)
- All config files include comments explaining non-obvious settings
- FreeBSD kernel configs follow `GENERIC` + delta pattern
- Template files use `{{VARIABLE}}` placeholder syntax
- File permissions: scripts 0755, configs 0644, secrets 0600

## Key Commands

- `make iso` — Build the full SparrowOS ISO (requires FreeBSD build machine)
- `make world` — Build FreeBSD world with SparrowOS src.conf
- `make kernel` — Build custom SPARROW kernel
- `make packages` — Build packages via Poudriere
- `make test` — Run smoke tests in VM

## Directory Layout

```
base/       — FreeBSD base system configs (kernel, ZFS, boot)
security/   — Security hardening (Capsicum, MAC, pf, rctl, audit)
desktop/    — Wayland desktop (Sway, Foot, Waybar, theme)
devtools/   — Development tools (Helix, code-server, Zsh, jails)
tenant/     — Multi-tenant system (sparrow-tenant CLI, networking, monitoring)
ai/         — AI tool integration (Claude Code, Codex, Gemini, sandboxing)
ux/         — UX polish (boot splash, onboarding, MOTD)
build/      — Build system (Poudriere, ISO generation, signing)
tests/      — Testing (VM harnesses, security audits, smoke tests)
docs/       — Documentation
```

## Critical Design Decisions

1. **Sway over Hyprland** — Proven FreeBSD port support
2. **Foot over Ghostty** — In FreeBSD ports, Wayland-native, proven
3. **Helix over Neovim** — Batteries-included, no plugin management needed
4. **GELI + ZFS native encryption** — Defense-in-depth (block-layer + dataset-layer)
5. **Bastille for jails** — Bastillefile templates, ZFS-aware, zero dependencies
6. **MAC Biba permissive by default** — Don't break UX; `sparrow-harden` enables enforcement
7. **Tenants are headless** — No Wayland in jails; tenants use SSH+tmux or code-server
8. **AI keys never stored in jails** — Injected as env vars at runtime
