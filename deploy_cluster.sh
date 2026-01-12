#!/bin/bash
set -euo pipefail
USAGE=$(cat <<-END
    Usage: ./deploy_cluster.sh [OPTIONS] [--aliases <alias1,alias2,...>]
    eg. ./deploy_cluster.sh --vim --aliases=custom

    Creates ~/.zshrc and ~/.tmux.conf configured for RunPod cluster
    with persistent storage in /workspace-vast

    OPTIONS:
        --vim                   deploy very simple vimrc config
        --aliases               specify additional alias scripts to source in .zshrc, separated by commas
END
)

export DOT_DIR="$(dirname "$(realpath "$0")")"
USER_VAST="/workspace-vast/$(whoami)"

VIM="false"
ALIASES=()
while (( "$#" )); do
    case "$1" in
        -h|--help)
            echo "$USAGE" && exit 1 ;;
        --vim)
            VIM="true" && shift ;;
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

# Vimrc
if [[ $VIM == "true" ]]; then
    echo "deploying .vimrc"
    echo "source \"$DOT_DIR/config/vimrc\"" > $HOME/.vimrc
fi

# zshrc setup - set cluster env vars before sourcing main config
cat > $HOME/.zshrc << EOF
# Cluster-specific: use oh-my-zsh from VAST storage
export ZSH="$USER_VAST/.oh-my-zsh"

# Cluster-specific: shared huggingface cache
export HF_HOME="/workspace-vast/pretrained_ckpts"

# Cluster-specific: uv configuration for cross-node compatibility
export UV_PYTHON_INSTALL_DIR="$USER_VAST/.uv/python"
export UV_CACHE_DIR="$USER_VAST/.cache/uv"

source "$DOT_DIR/config/zshrc.sh"
EOF

# Append additional alias scripts if specified
if [ -n "${ALIASES+x}" ]; then
    for alias in "${ALIASES[@]}"; do
        echo "source \"$DOT_DIR/config/aliases_${alias}.sh\"" >> $HOME/.zshrc
    done
fi

echo "changing default shell to zsh"
chsh -s $(which zsh)

zsh
