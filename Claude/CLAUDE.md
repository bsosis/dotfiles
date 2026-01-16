# Compute Cluster
This workspace is located on a shared Runpod instant cluster. I've described the basics below; for more detailed info on how to use the cluster, see the guide in `/workspace-vast/bsosis/git/dotfiles/RUNPOD_INFRASTRUCTURE_GUIDE.md`.

## Directory Structure
The home directory `/home/bsosis` (my username) should not be used for persistent storage, since it is not mirrored across nodes. Instead, anything that needs to be stored persistently should go in `/workspace-vast/bsosis`. My workspace contains `/workspace-vast/bsosis/envs`, containing uv virtual envs (by default use the env `helpfulonly`), `/workspace-vast/bsosis/exp`, containing experiments, and `/workspace-vast/bsosis/git`, containing code.

## Compute
The cluster consists of 24 nodes of 8xH200.

## Environment Configuration
I've set up dotfiles with many important environment variables; see `/workspace-vast/bsosis/git/dotfiles/deploy_cluster.sh` for configuration info if needed.

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

If you're running a slurm job, include my username (bsosis) in the job name (along with a description of the job) so that it can easily be identified.

Slurm jobs don't automatically source `.bashrc` or `.zshrc`, so environment variables won't be set by default. If these are needed, you can add the following to sbatch scripts:
```bash
source /workspace-vast/bsosis/.cluster_env.sh
```
This file is stored in VAST (not the local home directory) so it's accessible from any node. Most often this isn't needed, though, and it shouldn't be used in shared repos where other people might have their environments configured differently; I'll usually tell you when I want it.
