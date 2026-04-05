# SparrowOS Keyboard Shortcuts

## Sway Window Manager

| Key | Action |
|-----|--------|
| `Super+Return` | Open terminal (Foot) |
| `Super+d` | Application launcher (Fuzzel) |
| `Super+Space` | AI tool launcher (sparrow-ai) |
| `Super+Shift+q` | Close focused window |
| `Super+Shift+c` | Reload Sway config |
| `Super+Shift+e` | Exit Sway |
| `Super+Shift+l` | Lock screen |

## Navigation

| Key | Action |
|-----|--------|
| `Super+h/j/k/l` | Focus left/down/up/right |
| `Super+Shift+h/j/k/l` | Move window left/down/up/right |
| `Super+1-9` | Switch to workspace 1-9 |
| `Super+Shift+1-9` | Move window to workspace 1-9 |
| `Super+Tab` | Toggle focus floating/tiling |
| `Super+a` | Focus parent container |

## Layout

| Key | Action |
|-----|--------|
| `Super+b` | Split horizontal |
| `Super+v` | Split vertical |
| `Super+s` | Stacking layout |
| `Super+w` | Tabbed layout |
| `Super+e` | Toggle split |
| `Super+f` | Fullscreen toggle |
| `Super+Shift+Space` | Toggle floating |
| `Super+r` | Enter resize mode (h/j/k/l to resize) |

## SparrowOS

| Key | Action |
|-----|--------|
| `Super+t` | New terminal |
| `Super+Shift+t` | Tenant dashboard |
| `Super+Shift+s` | Screenshot (selection) |
| `Print` | Screenshot (full) |
| `Super+Print` | Screenshot to clipboard |
| `Super+n` | Toggle notification center |

## tmux (inside terminal)

| Key | Action |
|-----|--------|
| `Ctrl+a c` | New window |
| `Ctrl+a \|` | Split horizontal |
| `Ctrl+a -` | Split vertical |
| `Ctrl+a h/j/k/l` | Navigate panes |
| `Ctrl+a [` | Enter copy mode (vi keys) |
| `Ctrl+a d` | Detach session |

## Helix Editor

| Key | Action |
|-----|--------|
| `Space+f` | File picker |
| `Space+b` | Buffer picker |
| `Space+s` | Symbol picker |
| `g+d` | Go to definition |
| `g+r` | Go to references |
| `Space+a` | Code action |
| `Space+r` | Rename symbol |
| `:w` | Save |
| `:q` | Quit |
| `:wq` | Save and quit |

## AI Tools

| Command | Action |
|---------|--------|
| `sparrow-ai claude` | Launch Claude Code |
| `sparrow-ai codex` | Launch Codex CLI |
| `sparrow-ai gemini` | Launch Gemini CLI |
| `sparrow-ai status` | Show running AI tools |
| `sparrow-ai diff` | Show AI-made changes |

## Tenant Management

| Command | Action |
|---------|--------|
| `sparrow-tenant list` | List all tenants |
| `sparrow-tenant status <name>` | Tenant details |
| `sparrow-tenant create <name>` | Create tenant |
| `sparrow-tenant destroy <name>` | Remove tenant |
| `sparrow-tenant snapshot <name>` | ZFS snapshot |
| `sparrow-tenant code-server <name> start` | Start VS Code |
