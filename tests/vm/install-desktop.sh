#!/bin/sh
# Run this INSIDE the FreeBSD VM to install Wayland desktop packages
set -eu

echo "=== SparrowOS Desktop Package Installation ==="
echo ""

export ASSUME_ALWAYS_YES=yes

echo "[1/6] Updating package repository..."
pkg update

echo "[2/6] Installing Sway + Wayland core..."
pkg install -y sway seatd dbus foot wayland

echo "[3/6] Installing desktop utilities..."
pkg install -y fuzzel waybar swaybg swayidle grim slurp wl-clipboard

echo "[4/6] Installing development tools..."
pkg install -y helix tmux zsh git starship fzf ripgrep fd-find bat

echo "[5/6] Installing fonts..."
pkg install -y ibm-plex firacode

echo "[6/6] Enabling services..."
sysrc seatd_enable=YES
sysrc dbus_enable=YES
service seatd start 2>/dev/null || true
service dbus start 2>/dev/null || true

# Add root to video group
pw groupmod video -m root 2>/dev/null || true

echo ""
echo "=== Verifying installation ==="
which sway foot fuzzel waybar hx
pkg info | wc -l
echo "packages installed"
echo ""
echo "=== DESKTOP_INSTALL_COMPLETE ==="
