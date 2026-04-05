#!/bin/sh
# SparrowOS — Claude Code installation script
#
# Installs Claude Code (the Anthropic CLI) inside a FreeBSD jail.
# Tries the native FreeBSD path first (node20 + npm), and falls back
# to the Linuxulator if the native build fails.
#
# Usage:
#   setup.sh [jail_name]
#
# If jail_name is omitted, installs into the current environment.
# Must be run as root when targeting a jail.

set -eu

NODE_PKG="node20"
NPM_PKG="npm-node20"
CLAUDE_NPM_PKG="@anthropic-ai/claude-code"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
    printf '[sparrow-claude] %s\n' "$*"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

# Run a command, optionally inside a jail
jail_exec() {
    if [ -n "${TARGET_JAIL:-}" ]; then
        jexec "$TARGET_JAIL" "$@"
    else
        "$@"
    fi
}

# ---------------------------------------------------------------------------
# Dependency installation
# ---------------------------------------------------------------------------

install_node() {
    log "Checking for Node.js ..."
    if jail_exec command -v node >/dev/null 2>&1; then
        node_ver=$(jail_exec node --version)
        log "Node.js already installed: $node_ver"
        return 0
    fi

    log "Installing $NODE_PKG and $NPM_PKG ..."
    jail_exec pkg install -y "$NODE_PKG" "$NPM_PKG"

    if ! jail_exec command -v node >/dev/null 2>&1; then
        die "Failed to install Node.js."
    fi

    log "Node.js installed: $(jail_exec node --version)"
}

# ---------------------------------------------------------------------------
# Native installation
# ---------------------------------------------------------------------------

install_native() {
    log "Attempting native installation of Claude Code ..."

    install_node

    log "Installing $CLAUDE_NPM_PKG globally via npm ..."
    jail_exec npm install -g "$CLAUDE_NPM_PKG"

    # Verify installation
    if jail_exec command -v claude >/dev/null 2>&1; then
        claude_ver=$(jail_exec claude --version 2>/dev/null || echo "unknown")
        log "Claude Code installed successfully: $claude_ver"
        return 0
    else
        log "Native installation did not produce 'claude' binary."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Linuxulator fallback
# ---------------------------------------------------------------------------

install_linuxulator() {
    log "Falling back to Linuxulator-based installation ..."

    # Ensure the Linux compatibility layer is available
    if ! jail_exec test -d /compat/linux; then
        log "Enabling Linuxulator ..."
        if [ -n "${TARGET_JAIL:-}" ]; then
            # Enable linux inside the jail
            jail -m "name=${TARGET_JAIL}" linux=inherit 2>/dev/null || true
        fi
        jail_exec pkg install -y linux_base-c7 2>/dev/null || \
            jail_exec pkg install -y linux_base-rl9 2>/dev/null || \
            die "Could not install Linux base for Linuxulator."
    fi

    # Install Linux Node.js if not present
    if ! jail_exec /compat/linux/usr/bin/node --version >/dev/null 2>&1; then
        log "Installing Linux Node.js via Linuxulator ..."
        jail_exec sh -c 'cd /tmp && fetch https://nodejs.org/dist/v20.11.1/node-v20.11.1-linux-x64.tar.xz -o node.tar.xz && \
            mkdir -p /compat/linux/usr/local && \
            tar xf node.tar.xz -C /compat/linux/usr/local --strip-components=1 && \
            rm node.tar.xz'
    fi

    # Install Claude Code under Linuxulator
    log "Installing Claude Code via Linuxulator npm ..."
    jail_exec /compat/linux/usr/local/bin/npm install -g "$CLAUDE_NPM_PKG"

    # Create a wrapper script so 'claude' works from the FreeBSD side
    wrapper="/usr/local/bin/claude"
    if [ -n "${TARGET_JAIL:-}" ]; then
        jexec "$TARGET_JAIL" sh -c "cat > $wrapper" <<'WRAPPER'
#!/bin/sh
# SparrowOS — Claude Code Linuxulator wrapper
exec /compat/linux/usr/local/bin/claude "$@"
WRAPPER
        jexec "$TARGET_JAIL" chmod +x "$wrapper"
    else
        cat > "$wrapper" <<'WRAPPER'
#!/bin/sh
exec /compat/linux/usr/local/bin/claude "$@"
WRAPPER
        chmod +x "$wrapper"
    fi

    # Verify
    if jail_exec claude --version >/dev/null 2>&1; then
        log "Claude Code installed via Linuxulator: $(jail_exec claude --version 2>/dev/null)"
        return 0
    else
        die "Linuxulator installation also failed."
    fi
}

# ---------------------------------------------------------------------------
# Post-install configuration
# ---------------------------------------------------------------------------

post_install() {
    log "Running post-install configuration ..."

    # Create default config directory structure
    jail_exec mkdir -p /usr/local/etc/sparrow/ai
    jail_exec mkdir -p /var/log/sparrow

    # Test that claude responds
    log "Verifying installation ..."
    version=$(jail_exec claude --version 2>/dev/null || echo "")
    if [ -n "$version" ]; then
        log "Verification passed: Claude Code $version"
    else
        log "WARNING: 'claude --version' did not return output."
    fi

    log "Claude Code setup complete."
    log "Configure API key in: ~/.config/sparrow/ai-keys/claude.env"
    log "  Example: export ANTHROPIC_API_KEY=\"sk-ant-...\""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    TARGET_JAIL="${1:-}"

    if [ -n "$TARGET_JAIL" ]; then
        if [ "$(id -u)" -ne 0 ]; then
            die "Must be root to install into jail '$TARGET_JAIL'."
        fi
        if ! jls -j "$TARGET_JAIL" >/dev/null 2>&1; then
            die "Jail '$TARGET_JAIL' is not running."
        fi
        log "Target jail: $TARGET_JAIL"
    else
        log "Installing into current environment."
    fi

    # Try native first, fall back to Linuxulator
    if install_native; then
        post_install
    else
        log "Native installation failed — trying Linuxulator ..."
        install_linuxulator
        post_install
    fi
}

main "$@"
