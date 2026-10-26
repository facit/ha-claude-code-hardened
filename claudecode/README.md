# Claude Code for Home Assistant (hardened fork)

A fork of [robsonfelix/robsonfelix-hass-addons](https://github.com/robsonfelix/robsonfelix-hass-addons/tree/main/claudecode) with reduced privileges. See [What this fork changes](#what-this-fork-changes).

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Anthropic's AI-powered coding assistant, directly in your Home Assistant sidebar with full access to your configuration.

## Quick Start

```bash
claude "List all my automations"
claude "Turn off all lights in the living room"
claude "Create an automation to turn on lights at sunset"
claude "Why isn't my motion sensor automation working?"
```

## Requirements

- Home Assistant OS or Supervised installation
- [Anthropic account](https://console.anthropic.com/) (authentication handled in terminal)

## Features

- **Web Terminal**: Access Claude Code through a browser-based terminal
- **Config Access**: Read and write Home Assistant configuration files
- **hass-mcp Integration**: Direct control of HA entities and services
- **Session Persistence**: Optional tmux integration to preserve sessions across page refreshes
- **Customizable Theme**: Choose between dark and light terminal themes
- **Multi-Architecture**: Supports amd64, aarch64, armv7, armhf, and i386
- **Secure Authentication**: Claude Code handles its own authentication securely

## Setup

### 1. Install the Add-on

1. Add the repository to Home Assistant
2. Install the "Claude Code" add-on
3. Start the add-on
4. Open the Web UI from the sidebar

### 2. Authenticate with Claude Code

On first launch, Claude Code will prompt you to authenticate:

1. Open the terminal from the HA sidebar
2. Type `claude` to start
3. Follow the authentication prompts
4. Your credentials are stored securely by Claude Code

**Note**: The add-on does NOT require you to enter API keys in the configuration. Claude Code handles authentication itself, storing credentials securely in its own configuration directory. This is more secure than storing keys in Home Assistant's add-on config.

## Using Claude Code

### Basic Usage

Once authenticated, Claude Code is ready to help with:

- Editing Home Assistant YAML configurations
- Creating automations and scripts
- Debugging configuration issues
- Writing custom integrations

### Home Assistant Integration

With hass-mcp enabled, Claude can:

- Query entity states: "What's the temperature in the living room?"
- Control devices: "Turn off all lights in the bedroom"
- List services: "What services are available for climate control?"
- Debug automations: "Why didn't my morning routine trigger?"

### Example Commands

```bash
# Start interactive session
claude

# One-off commands
claude "Add a new automation that turns on the porch light at sunset"
claude "Check my configuration.yaml for errors"
claude "List all unavailable entities"

# Continue previous conversation
claude --continue
```

### Keyboard Shortcuts

| Shortcut | Command |
|----------|---------|
| `c` | `claude` |
| `cc` | `claude --continue` |
| `ha-config` | Navigate to config directory |
| `ha-logs` | View Home Assistant logs |

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `enable_mcp` | Enable HA integration | true |
| `enable_playwright_mcp` | Enable browser automation via the Playwright Browser add-on | false |
| `playwright_cdp_host` | Override the Playwright Browser hostname (auto-detected when empty) | "" |
| `terminal_font_size` | Font size (10-24) | 14 |
| `terminal_theme` | dark or light | dark |
| `working_directory` | Start directory | /homeassistant |
| `session_persistence` | Use tmux for persistent sessions | true |
| `auto_update_claude` | Auto-update Claude Code on startup (rolls back automatically if the new release cannot run) | false |
| `enable_remote_control` | View and steer the session from claude.ai/code or the Claude mobile app. See the security note below | false |
| `remote_control_session_prefix` | Prefix for auto-generated Remote Control session names | HomeAssistant |

### Remote Control

With `enable_remote_control`, sessions can be driven from `claude.ai/code` or the Claude mobile app (requires a Pro, Max, Team, or Enterprise subscription; API keys are not supported).

**Security note:** this add-on runs as root with read-write access to your Home Assistant config and API. Anyone who can sign in to the linked Claude account can control it. Leave this off unless you need it.

## File Locations

| Path | Description | Access |
|------|-------------|--------|
| `/homeassistant` | HA configuration directory | read-write |
| `/share` | Shared folder | read-write |
| `/media` | Media folder | read-write |
| `/config` | This add-on's config folder (`/addon_configs/<slug>` on the host) | read-write |
| `/ssl` | SSL certificates | read-only |
| `/backup` | Backups | read-only |
| `/data/claude` | Claude Code credentials, settings and transcripts (private to this add-on) | read-write |

## Session Persistence

When `session_persistence` is enabled, the add-on uses tmux to maintain your terminal session. This means:

- Your session survives browser refreshes
- You can disconnect and reconnect without losing context
- Claude Code conversations are preserved

### tmux Commands

If you're new to tmux:

| Key | Action |
|-----|--------|
| `Ctrl+b d` | Detach from session (keeps it running) |
| `Ctrl+b [` | Enter scroll/copy mode (use arrow keys) |
| Mouse wheel | Scroll up/down (auto-enters copy mode) |
| `q` | Exit scroll/copy mode |

### Customizing tmux

Anything you put in `/config/tmux.conf` is loaded last and overrides the defaults. On the host (Samba, File editor) it is `/addon_configs/<slug>/tmux.conf`. It survives restarts, rebuilds and reinstalls:

```bash
echo 'set -g mouse off' > /config/tmux.conf
```

Turning the mouse off restores native browser selection and copy/paste while keeping persistent sessions. Alternatively set `session_persistence: false` to drop tmux entirely.

### Copy and Paste in tmux

Since tmux captures mouse events, copy/paste works differently:

| Action | How to do it |
|--------|--------------|
| **Copy** | Hold `Ctrl+Shift` while selecting text with mouse |
| **Paste** | `Shift+Insert` or middle-click |
| **Alternative paste** | `Ctrl+Shift+V` (browser dependent) |

**Note**: Regular right-click paste and simple mouse selection won't work because tmux intercepts these events for scrolling.

#### Authenticating Claude Code (first launch)

The authentication URL can be long and may wrap across multiple lines. To handle this:

1. **Zoom out** your browser (`Ctrl + -` or `Cmd + -`) until the URL fits on a single line
2. **Click the link** — it should open in a new tab
3. Complete authentication in the browser and **copy the auth code**
4. Click back on the terminal and **paste** with `Shift+Insert` or `Ctrl+Shift+V`

If clicking the link doesn't work, hold `Ctrl+Shift` while selecting the URL with your mouse to copy it, then paste it into your browser's address bar.

### Scrolling and Session Persistence Trade-offs

**With tmux (`session_persistence: true`):**
- ✅ Session survives browser refresh/disconnect
- ✅ Can detach and reattach to running sessions
- ✅ Long-running Claude tasks continue in background
- ✅ Mouse wheel scrolling works (enters copy mode automatically)
- ✅ 20,000 line scrollback buffer
- ⚠️ Use middle-click or Shift+Insert to paste (right-click paste may not work)

**Without tmux (`session_persistence: false`):**
- ✅ Native browser scrolling
- ✅ Simpler terminal behavior
- ✅ Standard copy/paste behavior
- ❌ Session lost on browser refresh
- ❌ Session lost if add-on restarts

**Recommendation:**
- Use `session_persistence: true` (default) if you run long tasks or need to survive disconnects
- Use `session_persistence: false` if you need standard copy/paste behavior

## Security

### What this fork changes

| Upstream | This fork | Why |
|----------|-----------|-----|
| `docker_api`, `full_access`, `uart`, `auth_api` | Removed | Docker socket access and privileged mode amount to root on the host OS, beyond managing HA. Protection mode can stay on |
| `hassio_role: manager` | `homeassistant` | Enough for `ha core logs/check/restart`. Change to `manager` if Claude should install or configure other add-ons |
| ttyd on `0.0.0.0:7681`, no authentication | ttyd on `127.0.0.1`, behind nginx that only admits the Ingress gateway (`172.30.32.2`) | Any other add-on on the `hassio` network could open a root shell |
| Credentials and transcripts in `/homeassistant/.claudecode` | `/data/claude` | The HA config dir is readable by other add-ons and often kept in git. Existing state is copied over on first start |
| Permission rules like `Read(/homeassistant/**)` | `Read(//homeassistant/**)`, plus `ask` rules for `secrets.yaml`, `.storage/`, `.cloud/`, `/ssl` | A single leading slash is relative to `~/.claude`, so the old rules never matched. Secrets now prompt before being sent to the model |
| `get_history` pre-approved | Prompts | Includes location history of people in the home |
| CLAUDE.md regenerated into `~/.claude/CLAUDE.md` on every start | Shipped as the managed `/etc/claude-code/CLAUDE.md` | Your own `~/.claude/CLAUDE.md` is no longer overwritten |
| Unpinned `hass-mcp`, `pymodbus`, `pyserial`, `mbpoll`, `@playwright/mcp`; unverified binaries | Pinned versions, SHA-256 checks for `ttyd` and `ha` | Each build pulled whatever was newest |
| `auto_update_claude: true` | `false` | Keeps the installed version predictable |
| `working_directory` ignored | Honoured | Bug |

Without `uart`, Modbus tools work over TCP only. Add `uart: true` to `config.yaml` if you need serial devices.

### Still true
- Claude Code runs as root inside the container, with read-write access to your HA config and the HA API (it can control every entity). Treat anything that can drive it as able to control your home.
- The Supervisor token is in the shell environment so `hass-mcp` can use it.
- Text Claude reads (entity names, logs, web pages) can try to steer it. Don't run it with `--dangerously-skip-permissions`.
- `/data` is included in this add-on's backups, so treat HA backups as secrets.
- With `enable_remote_control`, anyone who can sign in to the linked Claude account can drive this session.

### After migrating
Once the add-on works, delete the old copy of your credentials and transcripts: `rm -rf /homeassistant/.claudecode`. Older upstream versions also wrote the Supervisor token into that folder, so backups made before upstream 1.2.65 contain it. Reinstalling the add-on issues a new token.

## Troubleshooting

### Authentication issues

Claude Code manages its own authentication. If you have issues:
1. Type `claude` to start the authentication flow
2. Follow the prompts to log in or enter your API key
3. Credentials are saved automatically for future sessions

**Can't copy the URL or paste the auth code?** The terminal uses tmux, which changes how copy/paste works. See [Copy and Paste in tmux](#copy-and-paste-in-tmux) for instructions.

### hass-mcp not working

1. Verify `enable_mcp` is true in configuration
2. Check add-on logs for connection errors
3. Restart the add-on after configuration changes

### Add-on won't start, or the log stops after "Checking for Claude Code updates"

Your CPU probably doesn't expose **AVX**. Since 2.1.113, Claude Code is a Bun-compiled native binary whose JavaScript engine requires it, and every `claude` command — even `claude --version` — hangs without it. That blocks startup before the terminal server binds its port, so Home Assistant reports the add-on as unhealthy.

This is common on virtual machines using a generic CPU model. Check from any terminal on the host:

```bash
grep -o -m1 avx2 /proc/cpuinfo   # no output means AVX2 is missing
```

Fix it at the hypervisor, not in the add-on:

- **Proxmox**: VM → Hardware → Processor → Type: `host` (or `x86-64-v3`)
- **libvirt / virt-manager**: CPU model → *Copy host CPU configuration*
- **ESXi / UnRAID**: enable host CPU passthrough

Then fully **stop and start** the VM — a reboot alone doesn't re-negotiate the CPU model.

Until you do, the add-on still works: the build automatically falls back to Claude Code 2.1.112, the last release that runs without AVX, and startup prints a warning explaining this.

### Terminal not loading

1. Check that the add-on is running (green indicator)
2. Try refreshing the page
3. Check browser console for errors
4. Review add-on logs for ttyd errors

### Session not persisting

1. Ensure `session_persistence` is set to true
2. The session is named "claude" - it will auto-attach on reconnect

### Configuration changes not applying

After changing configuration:
1. Save the configuration
2. Restart the add-on completely

## Support

- [GitHub Issues](https://github.com/robsonfelix/robsonfelix-hass-addons/issues)
- [Home Assistant Community](https://community.home-assistant.io/)
