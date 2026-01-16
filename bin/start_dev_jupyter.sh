#!/bin/bash
# Default values
GPUS=1
CPUS=8
MEM="32G"
# Parse command-line arguments
while getopts "g:c:m:h" opt; do
    case $opt in
        g) GPUS="$OPTARG" ;;
        c) CPUS="$OPTARG" ;;
        m) MEM="$OPTARG" ;;
        h)
            echo "Usage: $0 [-g gpus] [-c cpus] [-m mem]"
            echo "Will start a slurm dev job, and spit out the Jupyter Server URL"
            echo "to paste into your jupyter inside VSCode."
            echo "This only works if you use VSCode SSH'ed into the runpod cluster"
            echo "To attach to the runpod job, use: tmux attach -t jupyterdev"
            echo ""
            echo "Options:"
            echo "  -g <num>     Number of GPUs (default: 1)"
            echo "  -c <num>     Number of CPUs (default: 8)"
            echo "  -m <size>    Memory allocation (default: 32G)"
            echo "  -h           Show this help message"
            echo ""
            echo "Example: $0 -g 2 -c 16 -m 64G"
            exit 0
            ;;
        *)
            echo "Invalid option. Use -h for help"
            exit 1
            ;;
    esac
done
# Check if tmux session already exists
if tmux has-session -t jupyterdev 2>/dev/null; then
    echo "tmux session 'jupyterdev' already exists!"
    echo "Attach with: tmux attach -t jupyterdev"
    exit 1
fi
echo "Starting Jupyter with: ${GPUS} GPU(s), ${CPUS} CPU(s), ${MEM} memory"
echo ""
# Create a new tmux session and run the srun command inside it
tmux new-session -s jupyterdev -d "srun -p dev,overflow \
     --qos=dev \
     --cpus-per-task=${CPUS} \
     --gres=gpu:${GPUS} \
     --mem=${MEM} \
     --job-name=D_bsosis_jupyter \
     --pty bash -c '
# Source cluster environment variables
source /workspace-vast/bsosis/.cluster_env.sh
# Activate the uv venv (make sure ipykernel is installed there)
source /workspace-vast/bsosis/envs/.venv/bin/activate
# Install the Jupyter kernel if it doesnt already exist
jupyter kernelspec list | grep -q devpodenv || python -m ipykernel install --user --name devpodenv --display-name \"devpodenv\"
# Start Jupyter Lab
echo \"================================================\"
echo \"Starting Jupyter Lab...\"
echo \"Copy the URL with token below and paste it into VSCode\"
echo \"================================================\"
jupyter lab --no-browser --ip=0.0.0.0 --port=8889 --port-retries=10
'"
echo "Started Jupyter in tmux session 'jupyterdev'"
echo "Waiting for Jupyter Lab to start and retrieve URL..."
echo ""
# Wait for Jupyter to start and capture the URL
max_attempts=20
attempt=0
jupyter_url=""
while [ $attempt -lt $max_attempts ]; do
    # Capture tmux pane output and look for the Jupyter URL (node-* only)
    output=$(tmux capture-pane -t jupyterdev -J -p 2>/dev/null)
    jupyter_url=$(echo "$output" | grep -oE 'http://node-[a-zA-Z0-9._-]+:[0-9]+/lab\?token=[a-zA-Z0-9_-]+' | tail -1)
    if [ -n "$jupyter_url" ]; then
        echo "================================================"
        echo "Jupyter Lab is ready!"
        echo "================================================"
        echo ""
        echo "URL: $jupyter_url"
        echo ""
        echo "================================================"
        break
    fi
    attempt=$((attempt + 1))
    sleep 2
done
if [ -z "$jupyter_url" ]; then
    echo "Could not retrieve Jupyter URL within timeout."
    echo "Attach manually to check: tmux attach -t jupyterdev"
fi
echo ""
echo "To attach to tmux session: tmux attach -t jupyterdev"
echo "To detach from tmux: Ctrl+b, then d"
echo "To kill the session: tmux kill-session -t jupyterdev"