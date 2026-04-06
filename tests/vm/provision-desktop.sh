#!/bin/sh
#
# Provision SparrowOS desktop environment into the FreeBSD VM
# Run this on the HOST, not inside the VM.
#
set -eu

SSH_PORT=2222
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# SSH/SCP helpers using expect for password
ssh_cmd() {
    expect -c "
set timeout ${2:-120}
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_PORT root@localhost
expect \"assword:\"
send \"sparrow\r\"
expect \"# \"
send \"$1\r\"
expect \"# \"
send \"exit\r\"
expect eof
" 2>&1 | grep -v "^spawn\|Warning\|Permanently\|Welcome\|Release\|Security\|Handbook\|FAQ\|Questions\|Forums\|Documents\|languages\|version of\|Introduction\|directory layout\|login announcement\|resizewin"
}

scp_file() {
    expect -c "
set timeout 30
spawn scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P $SSH_PORT $1 root@localhost:$2
expect \"assword:\"
send \"sparrow\r\"
expect eof
" 2>/dev/null
}

echo "=== SparrowOS Desktop Provisioning ==="
echo ""

# Stage 1: Install packages
echo "[1/5] Installing Wayland packages (this takes several minutes)..."
ssh_cmd "env ASSUME_ALWAYS_YES=yes pkg update && env ASSUME_ALWAYS_YES=yes pkg install -y sway seatd dbus foot fuzzel waybar swaybg swayidle grim slurp wl-clipboard helix tmux zsh starship fzf ripgrep fd-find bat git && echo PKG_INSTALL_OK" 600

# Stage 2: Enable services
echo "[2/5] Enabling services..."
ssh_cmd "sysrc seatd_enable=YES && sysrc dbus_enable=YES && service seatd start 2>/dev/null; service dbus start 2>/dev/null; pw groupmod video -m root 2>/dev/null; echo SERVICES_OK"

# Stage 3: Copy desktop configs
echo "[3/5] Copying desktop configs..."
ssh_cmd "mkdir -p /root/.config/sway/config.d /root/.config/foot /root/.config/fuzzel /root/.config/waybar /root/.config/helix/themes"

scp_file "$PROJECT_ROOT/desktop/sway/config" "/root/.config/sway/config"
for f in appearance keybindings workspaces autostart; do
    [ -f "$PROJECT_ROOT/desktop/sway/config.d/$f" ] && \
        scp_file "$PROJECT_ROOT/desktop/sway/config.d/$f" "/root/.config/sway/config.d/$f"
done
scp_file "$PROJECT_ROOT/desktop/foot/foot.ini" "/root/.config/foot/foot.ini"
scp_file "$PROJECT_ROOT/desktop/fuzzel/fuzzel.ini" "/root/.config/fuzzel/fuzzel.ini"
scp_file "$PROJECT_ROOT/desktop/waybar/config.jsonc" "/root/.config/waybar/config.jsonc"
scp_file "$PROJECT_ROOT/desktop/waybar/style.css" "/root/.config/waybar/style.css"

# Stage 4: Copy devtools configs
echo "[4/5] Copying devtools configs..."
scp_file "$PROJECT_ROOT/devtools/helix/config.toml" "/root/.config/helix/config.toml"
scp_file "$PROJECT_ROOT/devtools/helix/themes/sparrow.toml" "/root/.config/helix/themes/sparrow.toml"
[ -f "$PROJECT_ROOT/devtools/helix/languages.toml" ] && \
    scp_file "$PROJECT_ROOT/devtools/helix/languages.toml" "/root/.config/helix/languages.toml"
[ -f "$PROJECT_ROOT/devtools/zsh/zshrc" ] && \
    scp_file "$PROJECT_ROOT/devtools/zsh/zshrc" "/root/.zshrc"
[ -f "$PROJECT_ROOT/devtools/tmux/tmux.conf" ] && \
    scp_file "$PROJECT_ROOT/devtools/tmux/tmux.conf" "/root/.tmux.conf"

# Stage 5: Verify
echo "[5/5] Verifying installation..."
ssh_cmd "which sway foot fuzzel waybar hx && echo VERIFY_OK || echo VERIFY_FAIL"

echo ""
echo "=== Desktop provisioning complete ==="
echo ""
echo "To test the GUI, restart the VM with graphics:"
echo "  1. Stop VM:  pkill -f sparrow-test.qcow2"
echo "  2. Start with VNC:"
echo "     cd tests/vm && qemu-system-aarch64 \\"
echo "       -machine virt,accel=hvf,highmem=on -cpu host -m 8G -smp 4 \\"
echo "       -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \\"
echo "       -drive if=virtio,file=sparrow-test.qcow2,format=qcow2 \\"
echo "       -device virtio-net-pci,netdev=net0 \\"
echo "       -netdev user,id=net0,hostfwd=tcp::2222-:22 \\"
echo "       -device virtio-gpu-pci -device virtio-keyboard-pci -device virtio-mouse-pci \\"
echo "       -display vnc=:0 -daemonize"
echo "  3. Connect VNC viewer to localhost:5900"
echo "  4. Log in as root/sparrow, then run: sway"
