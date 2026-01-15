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
VAST_PREFIX="/workspace-vast/$(whoami)"

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

# Validate we're on the cluster
[[ -d "/workspace-vast" ]] || { echo "Error: /workspace-vast not found - are you on the cluster?"; exit 1; }

echo "deploying on cluster..."
echo "using extra aliases: ${ALIASES[*]:-none}"

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

# Base prefix for all persistent storage
export VAST_PREFIX="$VAST_PREFIX"

# XDG Base Directory Specification - many tools respect these automatically
export XDG_DATA_HOME="\$VAST_PREFIX/.local/share"
export XDG_CONFIG_HOME="\$VAST_PREFIX/.config"
export XDG_CACHE_HOME="\$VAST_PREFIX/.cache"
export XDG_STATE_HOME="\$VAST_PREFIX/.local/state"

# Tool-specific overrides for tools that don't respect XDG
export ZSH="\$VAST_PREFIX/.oh-my-zsh"
export HF_HOME="/workspace-vast/pretrained_ckpts"
export HF_TOKEN_PATH="\$VAST_PREFIX/.cache/huggingface/token"
export UV_PYTHON_INSTALL_DIR="\$VAST_PREFIX/.uv/python"
export NPM_CONFIG_PREFIX="\$VAST_PREFIX/.npm-global"
export GIT_CONFIG_GLOBAL="\$VAST_PREFIX/.gitconfig"

# Add to PATH
export PATH="\$VAST_PREFIX/.npm-global/bin:\$VAST_PREFIX/.local/bin:\$PATH"

# Temp directories
export TMPDIR="\$HOME/tmp"
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
mkdir -p "$VAST_PREFIX/.claude"
rm -rf "$HOME/.claude"
ln -sf "$VAST_PREFIX/.claude" "$HOME/.claude"
echo "linked ~/.claude -> $VAST_PREFIX/.claude"

echo "Deploy complete. Run 'zsh' to start using the new config."
