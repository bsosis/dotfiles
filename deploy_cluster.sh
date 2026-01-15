#!/bin/bash
set -euo pipefail
USAGE=$(cat <<-END
    Usage: ./deploy_cluster.sh [OPTIONS] [--aliases <alias1,alias2,...>]
    eg. ./deploy_cluster.sh --aliases=custom

    Creates ~/.zshrc, ~/.tmux.conf, and ~/.config/zellij configured
    for RunPod cluster with persistent storage in /workspace-vast

    OPTIONS:
        --aliases               specify additional alias scripts to source in .zshrc, separated by commas
END
)

export DOT_DIR="$(dirname "$(realpath "$0")")"
USER_VAST="/workspace-vast/$(whoami)"

ALIASES=()
while (( "$#" )); do
    case "$1" in
        -h|--help)
            echo "$USAGE" && exit 1 ;;
        --aliases=*)
            IFS=',' read -r -a ALIASES <<< "${1#*=}" && shift ;;
        --) # end argument parsing
            shift && break ;;
        -*|--*=) # unsupported flags
            echo "Error: Unsupported flag $1" >&2 && exit 1 ;;
    esac
done

echo "deploying on cluster..."
echo "using extra aliases: ${ALIASES[@]}"

# Tmux setup
echo "source \"$DOT_DIR/config/tmux.conf\"" > $HOME/.tmux.conf

# Zellij setup - symlink config directory
mkdir -p "$HOME/.config"
rm -rf "$HOME/.config/zellij"
ln -sf "$DOT_DIR/config/zellij" "$HOME/.config/zellij"
echo "linked ~/.config/zellij -> $DOT_DIR/config/zellij"

# Generate unified env file for both bash and zsh
cat > $HOME/.cluster_env.sh << EOF
# Cluster-specific environment variables
# Sourced by both bash and zsh

# Use oh-my-zsh from VAST storage (zsh only, but harmless to set in bash)
export ZSH="$USER_VAST/.oh-my-zsh"
# Shared huggingface cache
export HF_HOME="/workspace-vast/pretrained_ckpts"
# Save huggingface token to user's VAST storage
export HF_TOKEN_PATH="$USER_VAST/.cache/huggingface/token"
# uv configuration for cross-node compatibility
export UV_PYTHON_INSTALL_DIR="$USER_VAST/.uv/python"
export UV_CACHE_DIR="$USER_VAST/.cache/uv"
# Configure XDG_DATA_HOME to use VAST storage (used for uv tools, etc.)
export XDG_DATA_HOME="$USER_VAST/.local/share"
# Set npm global prefix to VAST storage (for claude-code auto-updates)
export NPM_CONFIG_PREFIX="$USER_VAST/.npm-global"
# Use git config from VAST storage for persistence
export GIT_CONFIG_GLOBAL="$USER_VAST/.gitconfig"
# Add to PATH
export PATH="$USER_VAST/.npm-global/bin:$USER_VAST/.local/bin:\$PATH"
# Set temp directory to ~/tmp
export TMPDIR="\$HOME/tmp"
# Set Claude Code temp directory to ~/tmp
export CLAUDE_CODE_TMPDIR="\$HOME/tmp/claude"
EOF
echo "created ~/.cluster_env.sh"

# zshrc setup
cat > $HOME/.zshrc << EOF
source "\$HOME/.cluster_env.sh"
mkdir -p "\$TMPDIR"
mkdir -p "\$CLAUDE_CODE_TMPDIR"

source "$DOT_DIR/config/zshrc.sh"
EOF

# Append additional alias scripts if specified
if [ -n "${ALIASES+x}" ]; then
    for alias in "${ALIASES[@]}"; do
        echo "source \"$DOT_DIR/config/aliases_${alias}.sh\"" >> $HOME/.zshrc
    done
fi

# bashrc setup
cat > $HOME/.bashrc << EOF
source "\$HOME/.cluster_env.sh"
mkdir -p "\$TMPDIR"
mkdir -p "\$CLAUDE_CODE_TMPDIR"

source "$DOT_DIR/config/aliases.sh"
EOF
echo "created ~/.bashrc"

# Claude Code setup - symlink ~/.claude to VAST storage for persistence
mkdir -p "$USER_VAST/.claude"
rm -rf "$HOME/.claude"
ln -sf "$USER_VAST/.claude" "$HOME/.claude"
echo "linked ~/.claude -> $USER_VAST/.claude"

echo "Deploy complete. Run 'zsh' to start using the new config."
