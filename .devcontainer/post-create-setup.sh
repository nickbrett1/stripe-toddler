#!/bin/bash
# This file is executed once per session to set up the devcontainer.
# For example:
# echo "Running devcontainer setup script..."
# npm install

CURRENT_USER=$(whoami)
USER_HOME_DIR="$HOME"

echo "INFO: Ensuring login shell is zsh for $CURRENT_USER..."
if [ -x /usr/bin/zsh ]; then
    CURRENT_SHELL=$(getent passwd "$CURRENT_USER" | cut -d: -f7)
    if [ "$CURRENT_SHELL" != "/usr/bin/zsh" ]; then
        sudo chsh -s /usr/bin/zsh "$CURRENT_USER"
        echo "INFO: Login shell changed from $CURRENT_SHELL to /usr/bin/zsh."
    else
        echo "INFO: Login shell is already /usr/bin/zsh."
    fi
else
    echo "WARN: /usr/bin/zsh not found; skipping login shell change."
fi

echo "INFO: Ensuring wrangler directory permissions..."

echo "INFO: Restoring or backing up SSH host keys..."
sudo mkdir -p /var/lib/tailscale/ssh
if [ -n "$(ls -A /var/lib/tailscale/ssh/ssh_host_* 2>/dev/null)" ]; then
    echo "INFO: Restoring SSH host keys from /var/lib/tailscale/ssh..."
    sudo cp -f /var/lib/tailscale/ssh/ssh_host_* /etc/ssh/
    sudo chmod 600 /etc/ssh/ssh_host_*_key
    sudo chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true
else
    echo "INFO: Backing up SSH host keys to /var/lib/tailscale/ssh..."
    sudo ssh-keygen -A || true
    sudo cp -f /etc/ssh/ssh_host_* /var/lib/tailscale/ssh/
fi


if [ -f "/workspaces/stripe-toddler/.devcontainer/.zshrc" ]; then
    echo "INFO: Copying .zshrc to $USER_HOME_DIR/.zshrc"
    cp "/workspaces/stripe-toddler/.devcontainer/.zshrc" "$USER_HOME_DIR/.zshrc"
    sudo chown "$CURRENT_USER:$CURRENT_USER" "$USER_HOME_DIR/.zshrc"
else
    echo "INFO: /workspaces/stripe-toddler/.devcontainer/.zshrc not found, skipping copy."
fi

if [ -f "/workspaces/stripe-toddler/.devcontainer/.p10k.zsh" ]; then
    echo "INFO: Copying .p10k.zsh to $USER_HOME_DIR/.p10k.zsh"
    cp "/workspaces/stripe-toddler/.devcontainer/.p10k.zsh" "$USER_HOME_DIR/.p10k.zsh"
    sudo chown "$CURRENT_USER:$CURRENT_USER" "$USER_HOME_DIR/.p10k.zsh"
else
    echo "INFO: /workspaces/stripe-toddler/.devcontainer/.p10k.zsh not found, skipping copy."
fi

if [ -f "/workspaces/stripe-toddler/.devcontainer/.tmux.conf" ]; then
    echo "INFO: Copying .tmux.conf to $USER_HOME_DIR/.tmux.conf"
    cp "/workspaces/stripe-toddler/.devcontainer/.tmux.conf" "$USER_HOME_DIR/.tmux.conf"
    sudo chown "$CURRENT_USER:$CURRENT_USER" "$USER_HOME_DIR/.tmux.conf"
else
    echo "INFO: /workspaces/stripe-toddler/.devcontainer/.tmux.conf not found, skipping copy."
fi

echo "INFO: Ensuring SSH service is running..."
sudo service ssh restart
mkdir -p "$USER_HOME_DIR/.wrangler"
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$USER_HOME_DIR/.wrangler"

echo "INFO: Ensuring doppler directory permissions..."
mkdir -p "$USER_HOME_DIR/.doppler"
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$USER_HOME_DIR/.doppler"

echo "INFO: Ensuring gemini directory permissions..."
mkdir -p "$USER_HOME_DIR/.gemini"
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$USER_HOME_DIR/.gemini"

echo "INFO: Creating Oh My Zsh custom directories..."
mkdir -p "$USER_HOME_DIR/.oh-my-zsh/custom/themes" "$USER_HOME_DIR/.oh-my-zsh/custom/plugins"

if [ -f "/workspaces/stripe-toddler/.devcontainer/.zshrc" ]; then
    echo "INFO: Copying .zshrc to $USER_HOME_DIR/.zshrc"
    cp "/workspaces/stripe-toddler/.devcontainer/.zshrc" "$USER_HOME_DIR/.zshrc"
    sudo chown "$CURRENT_USER:$CURRENT_USER" "$USER_HOME_DIR/.zshrc"
else
    echo "INFO: /workspaces/stripe-toddler/.devcontainer/.zshrc not found, skipping copy."
fi

if [ -f "/workspaces/stripe-toddler/.devcontainer/.p10k.zsh" ]; then
    echo "INFO: Copying .p10k.zsh to $USER_HOME_DIR/.p10k.zsh"
    cp "/workspaces/stripe-toddler/.devcontainer/.p10k.zsh" "$USER_HOME_DIR/.p10k.zsh"
    sudo chown "$CURRENT_USER:$CURRENT_USER" "$USER_HOME_DIR/.p10k.zsh"
else
    echo "INFO: /workspaces/stripe-toddler/.devcontainer/.p10k.zsh not found, skipping copy."
fi

if [ -f "/workspaces/stripe-toddler/.devcontainer/.tmux.conf" ]; then
    echo "INFO: Copying .tmux.conf to $USER_HOME_DIR/.tmux.conf"
    cp "/workspaces/stripe-toddler/.devcontainer/.tmux.conf" "$USER_HOME_DIR/.tmux.conf"
    sudo chown "$CURRENT_USER:$CURRENT_USER" "$USER_HOME_DIR/.tmux.conf"
else
    echo "INFO: /workspaces/stripe-toddler/.devcontainer/.tmux.conf not found, skipping copy."
fi






echo "INFO: Configuring git safe directory..."
git config --global --add safe.directory /workspaces/stripe-toddler






echo "INFO: Installing Antigravity CLI and Specify CLI..."
if ! command -v npm &> /dev/null; then
    echo "npm not found. Installing nodejs and npm..."
    sudo apt-get update
    sudo apt-get install -y nodejs npm
fi
sudo npm install -g @specifyapp/cli
curl -fsSL https://antigravity.google/cli/install.sh | bash
echo "INFO: Antigravity CLI and Specify CLI installation complete."

echo "INFO: Initializing Antigravity CLI global settings..."
mkdir -p "$USER_HOME_DIR/.agy"
printf '{\n  "selectedAuthType": "oauth-personal",\n  "general": {\n    "sessionRetention": {\n      "enabled": true,\n      "maxAge": "30d",\n      "warningAcknowledged": true\n    }\n  },\n  "ide": {\n    "hasSeenNudge": true,\n    "enabled": true\n  }\n}\n' > "$USER_HOME_DIR/.agy/settings.json"
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$USER_HOME_DIR/.agy"

echo "INFO: Installing agy-telemetry hook..."
curl -fsSL https://raw.githubusercontent.com/nickbrett1/agy-telemetry/main/install.py | python3

echo "INFO: Setting up goose configuration and MCP servers..."

# Create goose config directory
mkdir -p "$HOME/.config/goose"

# Write goose config with MCP server extensions
cat > "$HOME/.config/goose/config.yaml" << 'GOOSECFGEOF'
extensions:
  # Built-in goose extensions
  developer:
    type: builtin
    name: developer
    enabled: true
    bundled: true
    timeout: 300
  # Svelte MCP - Streamable HTTP
  svelte:
    type: streamable_http
    name: svelte
    enabled: true
    uri: "https://mcp.svelte.dev/mcp"
    timeout: 300
  # Memos MCP
  memos:
    type: stdio
    name: memos
    enabled: true
    cmd: node
    args: [".agents/mcp-streamable-http-proxy.cjs", "http://nas:5230/mcp"]
    timeout: 300
  # Chrome DevTools MCP
  chrome-devtools:
    type: stdio
    name: chrome-devtools
    enabled: true
    cmd: npx
    args: ["-y", "chrome-devtools-mcp"]
    timeout: 300
  # Fintechnick MCP
  fintechnick:
    type: stdio
    name: fintechnick
    enabled: true
    cmd: sh
    args: ["-c", "npx -y mcp-remote https://www.fintechnick.com/api/mcp --header "Authorization: Bearer $FINTECHNICK_MCP""]
    envs:
      FINTECHNICK_MCP: $FINTECHNICK_MCP
    timeout: 300
  # GitHub MCP Server (via doppler for token)
  github:
    type: stdio
    name: github
    enabled: true
    cmd: doppler
    args: ["run", "--", "npx", "-y", "@modelcontextprotocol/server-github"]
    timeout: 300
  # Doppler MCP Server
  doppler:
    type: stdio
    name: doppler
    enabled: true
    cmd: sh
    args: ["-c", "DOPPLER_TOKEN=$(doppler configure get token --plain) npx -y @dopplerhq/mcp-server"]
    timeout: 300
  # Optional MCP servers
  sonarqube:
    type: stdio
    name: sonarqube
    enabled: true
    cmd: doppler
    args: ["run", "--", "npx", "-y", "sonarqube-mcp-server"]
    timeout: 300
  circleci:
    type: stdio
    name: circleci
    enabled: true
    cmd: doppler
    args: ["run", "--", "npx", "-y", "@circleci/mcp-server-circleci"]
    timeout: 300
GOOSECFGEOF

echo "INFO: goose configuration complete."


echo "INFO: Installing specdag globally..."
npm install -g @japorto100/specdag

if ! pgrep -f "socat TCP-LISTEN:9222" > /dev/null; then
    echo "Setup bridget to access Chrome DevTools Protocol over a secure tunnel..."
    sudo start-stop-daemon --start --background --pidfile /var/run/socat-9222.pid --make-pidfile --chuid $(id -un):$(id -gn) --exec /usr/bin/socat -- TCP-LISTEN:9222,fork,bind=127.0.0.1 TCP:host.docker.internal:9222
fi

echo "INFO: Checking Tailscale status..."
if ! command -v tailscale &> /dev/null; then
    echo "INFO: Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

if ! pgrep -x tailscaled > /dev/null; then
    echo "INFO: Starting Tailscale daemon..."
    sudo start-stop-daemon --start --background --oknodo --pidfile /var/run/tailscaled.pid --make-pidfile --exec /usr/sbin/tailscaled -- --state=/var/lib/tailscale/tailscaled.state
fi

echo "INFO: Checking Nanobanana MCP installation..."
if [ -f "webapp/scripts/install-nanobanana.sh" ]; then
    bash webapp/scripts/install-nanobanana.sh
elif [ -f "scripts/install-nanobanana.sh" ]; then
    bash scripts/install-nanobanana.sh
fi

echo "INFO: Generating goose configuration with MCP servers from .agents/mcp_config.json..."
mkdir -p "$USER_HOME_DIR/.config/goose"

# Build goose config.yaml with MCP servers from the project's agy MCP config
goose_config="$USER_HOME_DIR/.config/goose/config.yaml"

cat > "$goose_config" << 'GOOSE_EOF'
# Goose configuration generated from project .agents/mcp_config.json
# Managed by .devcontainer/post-create-setup.sh - do not edit manually

# LLM Provider loaded from Doppler (goose project, prd config) via goose-dev alias
active_provider: litellm
providers:
  litellm:
    enabled: true
    model: deepseek-v4-flash
    configured: true
GOOSE_TELEMETRY_ENABLED: true
GOOSE_MODE: auto

extensions:
  # Built-in extensions
  developer:
    type: builtin
    name: developer
    enabled: true
    bundled: true
    timeout: 300

  # Remote MCP servers (streamable HTTP)
  svelte:
    type: streamable_http
    name: svelte
    enabled: true
    uri: "https://mcp.svelte.dev/mcp"
    timeout: 300

  # Local MCP servers (stdio)
  chrome-devtools:
    type: stdio
    name: chrome-devtools
    enabled: true
    cmd: npx
    args: ["-y", "chrome-devtools-mcp"]
    timeout: 300

  fintechnick:
    type: stdio
    name: fintechnick
    enabled: true
    cmd: sh
    args: ["-c", "npx -y mcp-remote https://www.fintechnick.com/api/mcp --header \"Authorization: Bearer $FINTECHNICK_MCP\""]
    timeout: 300

  # Xcode via SSE proxy to remote Mac
  xcode-native:
    type: stdio
    name: xcode-native
    enabled: true
    cmd: node
    args: ["/workspaces/stripe-toddler/.agents/mcp-sse-proxy.cjs", "http://mac-studio:9876/sse"]
    timeout: 300

  # Doppler-aware MCP servers (inherit secrets from goose-dev wrapper)
  sonarqube:
    type: stdio
    name: sonarqube
    enabled: true
    cmd: doppler
    args: ["run", "--", "npx", "-y", "sonarqube-mcp-server"]
    timeout: 300

  circleci:
    type: stdio
    name: circleci
    enabled: true
    cmd: doppler
    args: ["run", "--", "npx", "-y", "@circleci/mcp-server-circleci"]
    timeout: 300

  github:
    type: stdio
    name: github
    enabled: true
    cmd: doppler
    args: ["run", "--", "npx", "-y", "@modelcontextprotocol/server-github"]
    timeout: 300

  doppler:
    type: stdio
    name: doppler
    enabled: true
    cmd: sh
    args: ["-c", "DOPPLER_TOKEN=$(doppler configure get token --plain) npx -y @dopplerhq/mcp-server"]
    timeout: 300
GOOSE_EOF

# Replace $FINTECHNICK_MCP in the config with the actual env var syntax for goose
# (Goose envs should be literal, the sh -c will resolve them at runtime)
sudo chown "$CURRENT_USER:$CURRENT_USER" "$goose_config"

echo "INFO: goose config.yaml generated at $goose_config"

echo -e "\nINFO: Custom container setup script finished."
echo -e "\n⚠️  To complete cloud login, run:"
echo "    cd /workspaces/stripe-toddler && bash scripts/cloud_login.sh"
