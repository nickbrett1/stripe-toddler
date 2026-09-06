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

CONFIG="$HOME/.config/goose/config.yaml"
if [ -f "$CONFIG" ]; then
    echo "INFO: Keeping existing $CONFIG (provider + extensions preserved)."
else
    echo "INFO: No goose config found - writing project goose config (extensions only; provider resolves from Doppler env at runtime)."
    mkdir -p "$HOME/.config/goose"
    cat > "$CONFIG" <<'GOOSECFGEOF'
extensions:
  mcphub-dev:
    type: streamable_http
    name: mcphub-dev
    enabled: true
    uri: http://nas:8781/mcp/dev
    timeout: 300

  sonarqube:
    type: stdio
    name: sonarqube
    enabled: true
    cmd: doppler
    args: ["run", "--", "npx", "-y", "sonarqube-mcp-server"]
    timeout: 300

  svelte:
    type: streamable_http
    name: svelte
    enabled: true
    uri: https://mcp.svelte.dev/mcp
    description: Svelte MCP server (remote)
    timeout: 300
GOOSECFGEOF
    echo "INFO: Wrote project goose config (MCPHub dev group + local/remote exceptions)."
fi

echo "INFO: Ensuring goose recipes are available (spec-first development process)..."
RECIPES_DIR="$HOME/.config/goose/recipes"
if [ -d "$RECIPES_DIR/.git" ]; then
    (cd "$RECIPES_DIR" && git pull --ff-only --quiet)         || echo "WARN: Could not update goose-recipes (offline or conflict); keeping existing copy."
else
    mkdir -p "$HOME/.config/goose"
    git clone --quiet https://github.com/nickbrett1/goose-recipes.git "$RECIPES_DIR"         || echo "WARN: Could not clone goose-recipes; recipes will be unavailable."
fi

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

# --- Goose pre-flight wrapper -------------------------------------------------
# Running plain `goose` skips the Doppler env injection that `goose-dev` provides,
# which makes the LLM provider and several MCP servers fail cryptically. Install a
# wrapper that runs scripts/goose-env-check.sh first and explains what's missing.
echo "INFO: Installing goose pre-flight env-check wrapper..."
GOOSE_BIN_DIR="$USER_HOME_DIR/.local/bin"
mkdir -p "$GOOSE_BIN_DIR"
if [ -f "$GOOSE_BIN_DIR/goose" ] && ! grep -qs "goose wrapper" "$GOOSE_BIN_DIR/goose"; then
    echo "INFO: Moving real goose binary to $GOOSE_BIN_DIR/goose-bin"
    mv "$GOOSE_BIN_DIR/goose" "$GOOSE_BIN_DIR/goose-bin"
fi
if [ -f "/workspaces/stripe-toddler/scripts/goose-env-check.sh" ]; then
    install -m 0755 "/workspaces/stripe-toddler/scripts/goose-env-check.sh" "$GOOSE_BIN_DIR/goose-env-check.sh"
fi
install -m 0755 "/workspaces/stripe-toddler/scripts/goose-wrapper.sh" "$GOOSE_BIN_DIR/goose"
echo "INFO: goose wrapper installed (real binary at $GOOSE_BIN_DIR/goose-bin)"

echo -e "\nINFO: Custom container setup script finished."
echo -e "\n⚠️  To complete cloud login, run:"
echo "    cd /workspaces/stripe-toddler && bash scripts/cloud_login.sh"
