#!/bin/bash
# Add-on entrypoint: reads the add-on options, prepares Claude Code's state and
# settings, then serves the terminal through nginx (see /etc/nginx/claudecode.conf).
set -u

OPTIONS=/data/options.json
opt() { jq -r "$1" "$OPTIONS"; }

export HA_TOKEN="$SUPERVISOR_TOKEN"
export HA_URL="http://supervisor/core"

# --- Claude Code state -------------------------------------------------------
# Kept in /data, the add-on's private volume. It used to live in
# /homeassistant/.claudecode, where every add-on that maps the HA config
# (Samba, File editor, Studio Code Server, ...) could read the OAuth
# credentials and session transcripts, and where a git-versioned config dir
# would commit them.
PERSIST_DIR=/data/claude
LEGACY_DIR=/homeassistant/.claudecode
mkdir -p "$PERSIST_DIR/config" /root/.config

if [ -d "$LEGACY_DIR" ] && [ ! -e "$PERSIST_DIR/.migrated" ]; then
  echo "[INFO] Moving Claude Code state from $LEGACY_DIR to private add-on storage"
  cp -a "$LEGACY_DIR/." "$PERSIST_DIR/"
  # The old add-on regenerated this file on every start; it now ships as the
  # managed /etc/claude-code/CLAUDE.md instead.
  if head -1 "$PERSIST_DIR/CLAUDE.md" 2>/dev/null | grep -qx '# Claude Code - Home Assistant Add-on'; then
    rm -f "$PERSIST_DIR/CLAUDE.md"
  fi
  touch "$PERSIST_DIR/.migrated"
fi
# After the copy: cp -a carries the legacy directory's 755 over.
chmod 700 "$PERSIST_DIR"
chmod 600 "$PERSIST_DIR/.credentials.json" 2>/dev/null || true
if [ -d "$LEGACY_DIR" ]; then
  echo "[WARN] $LEGACY_DIR still holds a copy of your Claude credentials and transcripts."
  echo "[WARN] It is readable by other add-ons and included in backups. Once this add-on"
  echo "[WARN] works, delete it:  rm -rf $LEGACY_DIR"
fi

if [ ! -L /root/.claude ]; then rm -rf /root/.claude; ln -s "$PERSIST_DIR" /root/.claude; fi
if [ ! -L /root/.config/claude-code ]; then rm -rf /root/.config/claude-code; ln -s "$PERSIST_DIR/config" /root/.config/claude-code; fi
if [ ! -L /root/.claude.json ]; then touch "$PERSIST_DIR/.claude.json"; rm -f /root/.claude.json; ln -s "$PERSIST_DIR/.claude.json" /root/.claude.json; fi

# User overrides for tmux, editable from Samba/File editor at
# /addon_configs/<slug>/tmux.conf on the host.
touch /config/tmux.conf 2>/dev/null || true

# --- Options -----------------------------------------------------------------
FONT_SIZE=$(opt '.terminal_font_size // 14')
THEME=$(opt '.terminal_theme // "dark"')
WORKDIR=$(opt '.working_directory // "/homeassistant"')
SESSION_PERSIST=$(opt 'if .session_persistence == null then true else .session_persistence end')
ENABLE_MCP=$(opt 'if .enable_mcp == null then true else .enable_mcp end')
ENABLE_PLAYWRIGHT=$(opt '.enable_playwright_mcp // false')
PLAYWRIGHT_HOST=$(opt '.playwright_cdp_host // ""')
REMOTE_CONTROL=$(opt '.enable_remote_control // false')
RC_SESSION_PREFIX=$(opt '.remote_control_session_prefix // "HomeAssistant"')
AUTO_UPDATE=$(opt '.auto_update_claude // false')

if [ -z "$PLAYWRIGHT_HOST" ] && [ "$ENABLE_PLAYWRIGHT" = "true" ]; then
  echo '[INFO] Auto-detecting Playwright Browser hostname...'
  PLAYWRIGHT_HOST=$(curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/addons \
    | jq -r '.data.addons[] | select(.slug | endswith("playwright-browser")) | .hostname' | head -1)
  if [ -n "$PLAYWRIGHT_HOST" ] && [ "$PLAYWRIGHT_HOST" != "null" ]; then
    echo "[INFO] Found Playwright Browser: $PLAYWRIGHT_HOST"
  else
    echo '[WARN] Playwright Browser add-on not found, using default hostname'
    PLAYWRIGHT_HOST="playwright-browser"
  fi
fi

# --- settings.json -----------------------------------------------------------
SETTINGS_FILE=/root/.claude/settings.json
[ -f "$SETTINGS_FILE" ] || echo '{}' > "$SETTINGS_FILE"
settings() { jq "$@" "$SETTINGS_FILE" > /tmp/settings.tmp && mv /tmp/settings.tmp "$SETTINGS_FILE"; }

if jq -e '.mcpServers.homeassistant.env.HASS_TOKEN' "$SETTINGS_FILE" > /dev/null 2>&1; then
  settings 'del(.mcpServers.homeassistant.env.HASS_TOKEN)'
  echo '[INFO] Removed a Supervisor token that older versions persisted into settings.json'
fi

# Rules written by older versions. A single leading slash is not an absolute
# path in Claude Code permission rules, and they pre-approved get_history
# (household location history) and reads of secrets. Drop them before adding
# the current set.
LEGACY_RULES='["mcp__homeassistant__get_history","Read(/homeassistant/**)","Read(/config/**)","Read(/share/**)","Read(/media/**)","Glob(/homeassistant/**)","Glob(/config/**)","Grep(/homeassistant/**)","Grep(/config/**)"]'
settings --argjson legacy "$LEGACY_RULES" \
  'if .permissions.allow then .permissions.allow -= $legacy else . end'

# --- Claude Code CLI ---------------------------------------------------------
if ! grep -qw avx /proc/cpuinfo 2>/dev/null; then
  echo '[WARN] This CPU does not expose AVX. Claude Code 2.1.113+ is a Bun-compiled'
  echo '[WARN] binary that requires it, so this add-on is running an older release.'
  echo '[WARN] On Proxmox set the VM CPU type to "host" (or x86-64-v3), then fully'
  echo '[WARN] stop and start the VM. Verify with: grep -o -m1 avx2 /proc/cpuinfo'
fi

BUILT_VERSION=$(cat /etc/claude-code-version 2>/dev/null || echo unknown)
if [ "$AUTO_UPDATE" = "true" ]; then
  echo "[WARN] auto_update_claude=true; the build verified $BUILT_VERSION, an update may install a release that cannot run"
  timeout 300 npm update -g @anthropic-ai/claude-code || echo '[WARN] Update failed; keeping the installed version'
  if ! timeout 30 claude --version < /dev/null > /dev/null 2>&1; then
    echo "[ERROR] The updated Claude Code does not run here; rolling back to $BUILT_VERSION"
    timeout 300 npm install -g "@anthropic-ai/claude-code@$BUILT_VERSION" || echo '[ERROR] Rollback failed'
  fi
else
  echo "[INFO] Claude Code $BUILT_VERSION (verified at build time)"
fi

if timeout 30 claude --version < /dev/null > /dev/null 2>&1; then
  CLAUDE_OK=true
else
  CLAUDE_OK=false
  echo '[ERROR] claude CLI did not respond within 30s - skipping MCP setup'
  echo '[ERROR] The terminal will still start so you can debug from inside the add-on'
fi

if [ "$CLAUDE_OK" = "true" ]; then
  timeout 30 claude mcp remove homeassistant -s user > /dev/null 2>&1 || true
  timeout 30 claude mcp remove playwright -s user > /dev/null 2>&1 || true
fi

# --- MCP and permissions -----------------------------------------------------
# Pre-approved: read-only HA tools and reads of the mapped folders. Ask rules
# win over allow rules, so secrets and .storage (integration API keys and
# OAuth tokens) still prompt before their contents are sent to the model.
ALLOWED_TOOLS='[
  "Read(//homeassistant/**)", "Read(//config/**)", "Read(//share/**)", "Read(//media/**)"
]'
ASK_TOOLS='[
  "Read(//homeassistant/secrets.yaml)", "Read(//homeassistant/**/secrets.yaml)",
  "Read(//homeassistant/.storage/**)", "Read(//homeassistant/.cloud/**)",
  "Read(//homeassistant/.claudecode/**)", "Read(//ssl/**)", "Read(//data/**)",
  "Edit(//homeassistant/.storage/**)"
]'
if [ "$CLAUDE_OK" = "true" ] && [ "$ENABLE_MCP" = "true" ]; then
  timeout 30 claude mcp add-json homeassistant '{"command":"hass-mcp"}' -s user
  ALLOWED_TOOLS=$(jq -c '. + [
    "mcp__homeassistant__get_version", "mcp__homeassistant__get_entity",
    "mcp__homeassistant__list_entities", "mcp__homeassistant__search_entities_tool",
    "mcp__homeassistant__domain_summary_tool", "mcp__homeassistant__list_automations",
    "mcp__homeassistant__get_error_log"
  ]' <<< "$ALLOWED_TOOLS")
  echo '[INFO] MCP configured with Home Assistant integration'
elif [ "$ENABLE_MCP" = "true" ]; then
  echo '[WARN] MCP is enabled but was skipped: the claude CLI is not responding'
else
  echo '[INFO] MCP disabled'
fi
settings --argjson allow "$ALLOWED_TOOLS" --argjson ask "$ASK_TOOLS" '
  .permissions.allow = ($allow + (.permissions.allow // []) | unique)
  | .permissions.ask = ($ask + (.permissions.ask // []) | unique)'
echo '[INFO] Pre-authorized read-only tools; secrets and .storage still require approval'

if [ "$CLAUDE_OK" = "true" ] && [ "$ENABLE_PLAYWRIGHT" = "true" ]; then
  PLAYWRIGHT_JSON=$(jq -cn --arg ep "http://${PLAYWRIGHT_HOST}:9222" \
    '{command: "npx", args: ["--no-install", "@playwright/mcp@0.0.83", "--cdp-endpoint", $ep]}')
  timeout 30 claude mcp add-json playwright "$PLAYWRIGHT_JSON" -s user
  echo "[INFO] Playwright MCP enabled (CDP: http://${PLAYWRIGHT_HOST}:9222)"
  echo '[INFO] Make sure the Playwright Browser add-on is installed and running'
elif [ "$ENABLE_PLAYWRIGHT" = "true" ]; then
  echo '[WARN] Playwright MCP is enabled but was skipped: the claude CLI is not responding'
else
  echo '[INFO] Playwright MCP disabled'
fi

if [ "$REMOTE_CONTROL" = "true" ]; then
  settings '.remoteControlAtStartup = true'
  export CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX="$RC_SESSION_PREFIX"
  echo '[INFO] Remote Control enabled - Claude Code will auto-start with remote control'
else
  settings 'del(.remoteControlAtStartup)'
  echo '[INFO] Remote Control auto-start disabled'
fi

# --- Terminal ----------------------------------------------------------------
if [ "$THEME" = "dark" ]; then
  COLORS='background=#1e1e2e,foreground=#cdd6f4,cursor=#f5e0dc'
else
  COLORS='background=#eff1f5,foreground=#4c4f69,cursor=#dc8a78'
fi
if [ "$SESSION_PERSIST" = "true" ]; then
  SHELL_CMD=(tmux new-session -A -s claude)
else
  SHELL_CMD=(bash --login)
fi

if ! cd "$WORKDIR" 2>/dev/null; then
  echo "[WARN] working_directory $WORKDIR does not exist; using /homeassistant"
  cd /homeassistant
fi

mkdir -p /tmp/nginx
nginx -e stderr -c /etc/nginx/claudecode.conf || { echo '[ERROR] nginx failed to start'; exit 1; }

exec ttyd --interface lo --port 7682 --writable --ping-interval 30 --max-clients 5 \
  -t "fontSize=$FONT_SIZE" \
  -t fontFamily=Monaco,Consolas,monospace \
  -t scrollback=20000 \
  -t "theme=$COLORS" \
  "${SHELL_CMD[@]}"
