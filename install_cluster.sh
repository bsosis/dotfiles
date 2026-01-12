#!/bin/bash
set -euo pipefail
USAGE=$(cat <<-END
    Usage: ./install_cluster.sh [OPTION]
    Install dotfile dependencies on the RunPod cluster
    Installs to /workspace-vast for persistence across nodes

    OPTIONS:
        --extras     install extra dependencies
        --force      force reinstall of oh-my-zsh and plugins
END
)

extras=false
force=false
while (( "$#" )); do
    case "$1" in
        -h|--help)
            echo "$USAGE" && exit 1 ;;
        --extras)
            extras=true && shift ;;
        --force)
            force=true && shift ;;
        --) # end argument parsing
            shift && break ;;
        -*|--*=) # unsupported flags
            echo "Error: Unsupported flag $1" >&2 && exit 1 ;;
    esac
done

DOT_DIR="$(dirname "$(realpath "$0")")"
USER_VAST="/workspace-vast/$(whoami)"

# Create directories on VAST per cluster setup instructions
echo "Creating directories on VAST..."
mkdir -p "$USER_VAST/git" "$USER_VAST/exp" "$USER_VAST/envs"

# Set up uv directories on VAST
export UV_PYTHON_INSTALL_DIR="$USER_VAST/.uv/python"
export UV_CACHE_DIR="$USER_VAST/.cache/uv"
mkdir -p "$UV_PYTHON_INSTALL_DIR" "$UV_CACHE_DIR"

# Install uv and python
curl -LsSf https://astral.sh/uv/install.sh | sh
source "$HOME/.local/bin/env"
uv python install 3.11

# Setting up oh my zsh and oh my zsh plugins
ZSH="$USER_VAST/.oh-my-zsh"
ZSH_CUSTOM="$ZSH/custom"
if [ -d "$ZSH" ] && [ "$force" = "false" ]; then
    echo "Skipping download of oh-my-zsh and related plugins, pass --force to force redownload"
else
    echo " --------- INSTALLING DEPENDENCIES --------- "
    rm -rf "$ZSH"

    export ZSH="$USER_VAST/.oh-my-zsh"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    git clone https://github.com/romkatv/powerlevel10k.git \
        ${ZSH_CUSTOM:-$USER_VAST/.oh-my-zsh/custom}/themes/powerlevel10k

    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
        ${ZSH_CUSTOM:-$USER_VAST/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

    git clone https://github.com/zsh-users/zsh-autosuggestions \
        ${ZSH_CUSTOM:-$USER_VAST/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

    git clone https://github.com/zsh-users/zsh-completions \
        ${ZSH_CUSTOM:=$USER_VAST/.oh-my-zsh/custom}/plugins/zsh-completions

    git clone https://github.com/zsh-users/zsh-history-substring-search \
        ${ZSH_CUSTOM:-$USER_VAST/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

    git clone https://github.com/jimeh/tmux-themepack.git "$USER_VAST/.tmux-themepack"

    echo " --------- INSTALLED SUCCESSFULLY --------- "
    echo " --------- NOW RUN ./deploy_cluster.sh [OPTION] -------- "
fi

if [ $extras == true ]; then
    echo " --------- INSTALLING EXTRAS --------- "
    if command -v cargo &> /dev/null; then
        NO_ASK_OPENAI_API_KEY=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/hmirin/ask.sh/main/install.sh)"
    fi
fi
