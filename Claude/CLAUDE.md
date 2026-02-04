# Compute Cluster
This workspace is located on a shared Runpod instant cluster. I've described the basics below; for more detailed info on how to use the cluster, see the guide in `/workspace-vast/bsosis/git/dotfiles/RUNPOD_INFRASTRUCTURE_GUIDE.md` -- refer to this whenever I ask you how to do anything complex on the cluster.

## Directory Structure
The home directory `/home/bsosis` (my username) should not be used for persistent storage, since it is not mirrored across nodes. Instead, anything that needs to be stored persistently should go in `/workspace-vast/bsosis`. Code is contained in `/workspace-vast/bsosis/git`; `/workspace-vast/bsosis/logs` contains most (though not all) logs. 

Generally, you should confine file searches/`find` commands to the project directory (or to the logs directory, if relevant). I'll almost always run you in the directory for a particular repo, and everything you need should be in that directory. Searching through `/workspace-vast/bsosis` or `/workspace-vast/bsosis/git` will turn up a lot of false positives from other projects or worktrees, and `/home/bsosis` will generally contain only temporary files. 

## Compute
The cluster consists of 24 nodes of 8xH200.

## Environment Configuration
I've set up dotfiles with many important environment variables. See `/workspace-vast/bsosis/git/dotfiles/deploy_cluster.sh` for configuration info if needed; this script writes the environment variables to `/workspace-vast/bsosis/.cluster_env.sh`, ensures it gets sourced, and sets up various important directories in `/workspace-vast/bsosis`.

## Virtual Environments
Generally, repo directories will each contain a `.venv` directory; you should use this directory with `uv` when running Python code. Running commands without uv will generally fail as the global environment does not have any of the required packages installed.

## Claude Code Configuration
The directory `workspace-vast/bsosis/git/dotfiles/Claude` contains configuration for Claude Code; the `deploy_cluster.sh` script copies this to the appropriate directory. If I ask you to modify the Claude Code settings or CLAUDE.md file, you should modify the version in the `dotfiles` repo, so that I can easily deploy the changes across nodes.

## Slurm
We use slurm to manage GPU jobs; you should NEVER run jobs outside the slurm queue. 

We have three main QoS tiers:
- dev: top priority debugging interactive jobs; max 8 GPUs. You generally won't use this
- high: won't be preempted; max 16 GPUs
- low: can be preempted; unlimited jobs
We have three partitions:
- dev: Dev or low QoS allowed
- general: High and low QoS allowed
- overflow: All QoS allowed.
In most cases you'll want to use high or low priority on general -- most of the time I'll let you know if I want something different.

Important: you should NEVER export CUDA_VISIBLE_DEVICES yourself; slurm does this for you. Overwriting this will cause slurm to land jobs on GPUs that might be utilized causing all jobs to drain into that slot and crash.

In most cases, you should not run slurm jobs -- or any code that uses a GPU -- yourself, unless I specifically request it. I'd rather manage the slurm calls to make sure they don't conflict with anyone else on the cluster.

## Secrets Management
API keys are managed via Bitwarden CLI. Run `load_secrets` once per shell session (prompts for master password), then secrets are available as environment variables. For SLURM jobs, use `sbatch --export=ALL` or the `sbatch-secure` wrapper which auto-prompts if secrets aren't loaded.

## VLLM and accelerate
Sometimes VLLM and accelerate don't clean up properly (especially if the slurm job is preempted or hits a time limit), which can cause issues on the cluster. When using either, you should capture the PID and make sure it gets killed properly on exit. (Note, make sure you don't kill any other user's processes!)

## Username
Don't hard-code my username in anything you write: this is a shared project, and needs to work for my collaborators as well. Use relative paths, placeholders (`$USER` or `%u`), generic job names, etc. instead.
