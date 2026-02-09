#!/bin/bash
set -euo pipefail
USAGE=$(cat <<-END
    Usage: ./install_cluster.sh [OPTION]
    Install dotfile dependencies on the RunPod cluster
    Installs to /workspace-vast for persistence across nodes

    OPTIONS:
        --force      force reinstall of oh-my-zsh and plugins
END
)

force=false
while (( "$#" )); do
    case "$1" in
        -h|--help)
            echo "$USAGE" && exit 1 ;;
        --force)
            force=true && shift ;;
        --) # end argument parsing
            shift && break ;;
        -*|--*=) # unsupported flags
            echo "Error: Unsupported flag $1" >&2 && exit 1 ;;
    esac
done

DOT_DIR="$(dirname "$(realpath "$0")")"

# Validate we're on the cluster and have required dependencies
[[ -d "/workspace-vast" ]] || { echo "Error: /workspace-vast not found - are you on the cluster?"; exit 1; }
for cmd in curl git; do
    command -v "$cmd" >/dev/null || { echo "Error: $cmd not found"; exit 1; }
done

VAST_PREFIX="/workspace-vast/$(whoami)"

# Create directories on VAST per cluster setup instructions
echo "Creating directories on VAST..."
mkdir -p "$VAST_PREFIX/git" "$VAST_PREFIX/exp" "$VAST_PREFIX/envs"

# Create XDG base directories
mkdir -p "$VAST_PREFIX/.local/share" "$VAST_PREFIX/.config" "$VAST_PREFIX/.cache" "$VAST_PREFIX/.local/state"

# Set up uv directories on VAST
export UV_PYTHON_INSTALL_DIR="$VAST_PREFIX/.uv/python"
export XDG_CACHE_HOME="$VAST_PREFIX/.cache"
mkdir -p "$UV_PYTHON_INSTALL_DIR"

# Install uv if not already installed
if command -v uv >/dev/null 2>&1; then
    echo "uv already installed, skipping"
else
    echo "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
[[ -f "$HOME/.local/bin/env" ]] && source "$HOME/.local/bin/env"

# Install python 3.11 if not already installed via uv
if uv python list --only-installed 2>/dev/null | grep -q "3.11"; then
    echo "Python 3.11 already installed via uv, skipping"
else
    echo "Installing Python 3.11..."
    uv python install 3.11
fi

# Install Node.js/npm if not available
NODE_DIR="$VAST_PREFIX/.node"
if command -v npm >/dev/null 2>&1; then
    echo "npm already installed, skipping"
else
    echo "Installing Node.js..."
    mkdir -p "$NODE_DIR"
    NODE_VERSION="v22.13.1"
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz" | tar -xJ -C "$NODE_DIR" --strip-components=1
    echo "Node.js installed to $NODE_DIR"
fi
export PATH="$NODE_DIR/bin:$PATH"

# Configure npm global prefix for VAST storage and install Claude Code
export NPM_CONFIG_PREFIX="$VAST_PREFIX/.npm-global"
mkdir -p "$NPM_CONFIG_PREFIX"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"

# Install Claude Code if not already installed
if command -v claude >/dev/null 2>&1; then
    echo "Claude Code already installed, skipping"
else
    echo "Installing Claude Code..."
    # npm install -g @anthropic-ai/claude-code
    curl -fsSL https://claude.ai/install.sh | bash
    echo "Claude Code installed"
fi

# Setting up oh my zsh and oh my zsh plugins
ZSH="$VAST_PREFIX/.oh-my-zsh"
ZSH_CUSTOM="$ZSH/custom"
if [ -d "$ZSH" ] && [ "$force" = "false" ]; then
    echo "Skipping download of oh-my-zsh and related plugins, pass --force to force redownload"
else
    echo " --------- INSTALLING DEPENDENCIES --------- "
    rm -rf "$ZSH"

    export ZSH="$VAST_PREFIX/.oh-my-zsh"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    git clone https://github.com/romkatv/powerlevel10k.git \
        ${ZSH_CUSTOM:-$VAST_PREFIX/.oh-my-zsh/custom}/themes/powerlevel10k

    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
        ${ZSH_CUSTOM:-$VAST_PREFIX/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

    git clone https://github.com/zsh-users/zsh-autosuggestions \
        ${ZSH_CUSTOM:-$VAST_PREFIX/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

    git clone https://github.com/zsh-users/zsh-completions \
        ${ZSH_CUSTOM:-$VAST_PREFIX/.oh-my-zsh/custom}/plugins/zsh-completions

    git clone https://github.com/zsh-users/zsh-history-substring-search \
        ${ZSH_CUSTOM:-$VAST_PREFIX/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

    git clone https://github.com/jimeh/tmux-themepack.git "$VAST_PREFIX/.local/share/tmux-themepack"

    echo " --------- INSTALLED SUCCESSFULLY --------- "
fi

# Install Zellij to VAST storage
ZELLIJ_BIN="$VAST_PREFIX/.local/bin/zellij"
if [ -f "$ZELLIJ_BIN" ] && [ "$force" = "false" ]; then
    echo "Skipping Zellij install, pass --force to force reinstall"
else
    echo "Installing Zellij to VAST storage..."
    mkdir -p "$VAST_PREFIX/.local/bin"
    # Download and extract zellij binary
    curl -fsSL https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz | tar -xz -C "$VAST_PREFIX/.local/bin"
    chmod +x "$ZELLIJ_BIN"
    echo "Zellij installed to $ZELLIJ_BIN"
fi

# Set up Claude Code config directory on VAST
CLAUDE_DIR="$VAST_PREFIX/.claude"
echo "Setting up Claude Code config at $CLAUDE_DIR..."
mkdir -p "$CLAUDE_DIR"
cp -r "$DOT_DIR/Claude/." "$CLAUDE_DIR/"
echo "Claude Code config files copied to $CLAUDE_DIR"

echo " --------- NOW RUN ./deploy_cluster.sh [OPTION] -------- "
