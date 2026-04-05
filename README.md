# SparrowOS

**A secure development operating system built on FreeBSD 15.0**

> Speed and Security with Simple-intuitive UX

SparrowOS is a custom FreeBSD distribution that combines a cyberpunk-themed Wayland desktop with multi-tenant developer workspace isolation and first-class AI coding tool integration.

## Features

- **Hybrid Workstation/Server** — Use as a local desktop, a multi-tenant dev server, or both simultaneously
- **Cyberpunk Aesthetic** — Neon green, cyan, and magenta on dark backgrounds. Tiling windows. Keyboard-driven.
- **Multi-Tenant Isolation** — Each developer gets a VNET jail with ZFS encryption, resource limits, and VPN access
- **AI Tool Integration** — Claude Code, Codex CLI, and Gemini CLI running in sandboxed jails
- **Security-First** — Capsicum sandboxing, MAC Biba integrity, pf firewall, OpenBSM audit, GELI encryption
- **ZFS Everything** — Boot environments, per-tenant encrypted datasets, snapshots before AI operations

## Tech Stack

| Component | Choice |
|-----------|--------|
| Base OS | FreeBSD 15.0 + pkgbase |
| Desktop | Sway (Wayland) + Foot + Waybar |
| Editor | Helix + code-server (VS Code in browser) |
| Shell | Zsh + Starship |
| Security | Capsicum + MAC Biba + pf + jails + rctl |
| Storage | ZFS on GELI-encrypted root |
| Tenants | VNET jails + Bastille + WireGuard |
| AI Tools | Claude Code, Codex CLI, Gemini CLI |

## Quick Start

```sh
# Build the ISO (requires FreeBSD build machine)
make iso

# Test in QEMU
qemu-system-x86_64 -m 4G -cdrom SparrowOS-0.1.0-alpha-amd64.iso

# Manage tenants
sparrow-tenant create alice --profile medium --ai claude,codex
sparrow-tenant list
sparrow-tenant status alice

# Use AI tools
sparrow-ai claude
sparrow-ai codex
sparrow-ai gemini
```

## Install Modes

At install time, choose your mode:

- **Workstation** — Sway desktop for local development
- **Server** — Headless multi-tenant server with SSH/WireGuard access
- **Hybrid** — Both simultaneously (default)

## License

BSD 2-Clause. See [LICENSE](LICENSE).
