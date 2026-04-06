#!/bin/sh
#
# tenant-login.sh — Auto-launched when a tenant SSHs into their jail
#
# Set as the tenant user's login shell or sourced from .profile.
# Automatically attaches to or creates the sparrow-workspace tmux session.
#

set -eu

# Show MOTD
if [ -x /usr/local/bin/sparrow-motd ]; then
    /usr/local/bin/sparrow-motd
fi

echo ""

# Determine AI tool (from tenant config or default)
AI_TOOL="claude"
if [ -f /usr/local/etc/sparrow/tenant.conf ]; then
    _tools=$(grep '^TENANT_AI_TOOLS=' /usr/local/etc/sparrow/tenant.conf 2>/dev/null | cut -d= -f2)
    if [ -n "$_tools" ]; then
        # Use first AI tool from the list
        AI_TOOL=$(echo "$_tools" | cut -d, -f1)
    fi
fi

# Find or create project directory
PROJECT_DIR="$HOME/project"
mkdir -p "$PROJECT_DIR"

# Launch workspace
if command -v sparrow-workspace >/dev/null 2>&1; then
    exec sparrow-workspace --ai "$AI_TOOL" --project "$PROJECT_DIR"
elif command -v tmux >/dev/null 2>&1; then
    # Fallback: simple tmux session
    if tmux has-session -t sparrow 2>/dev/null; then
        exec tmux attach-session -t sparrow
    else
        exec tmux new-session -s sparrow -c "$PROJECT_DIR"
    fi
else
    cd "$PROJECT_DIR"
    exec /bin/sh -l
fi
