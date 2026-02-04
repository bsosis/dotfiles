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

## Research Best Practices
- Always save any LLM transcripts produced by experiments. The aggregate numbers are in general much much less informative than transcripts; every single experiment that generates language model outputs (beyond logits or individual tokens) should save the transcripts, no exceptions.
- In general, you should always err on the side of saving more data rather than less: training curves over time rather than just final results, benchmark scores by category or by individual question rather than just aggregate results, etc.
- You should generally use temperature of 0.6 or 0.7 to evaluate language models (although there are some cases where temperature of 1 is appropriate).

## Code Style
Some conventions I prefer:
- You tend to use command-line argument names with multiple words (e.g. `model_id`, `n_samples`, `judge_model`, etc.) when this is unnecessary. Try to use single-word argument names (e.g. `model`, `n`, `judge`) to make them easier to type. If using just a single word would be too ambiguous, you can use multi-word arguments, but separate them by dashes rather than underscores.
- If you write code to give text outputs or summaries of data, I prefer them to be in Markdown so I can easily copy them into Obsidian. When you do this, follow the following guidelines:
    - Do not use headers or section breaks: I'm typically going to paste the summaries into already-existing files with their own headers, so I don't want any extra headers in the outputs that I have to reformat or remove.
    - Instead, you should generally put information in bullet points
    - Keep everything concise; do not include any extraneous descriptions; minimize filler whitespace
- When using LLM judges or similar, default to using Anthropic's API. Use `claude-sonnet-4-5` or `claude-opus-4-5`, as these should refer to the latest models.

## Reasoning Mode
There are a couple considerations to keep in mind when running models with reasoning.
- Qwen 3 models -- which I use often -- have reasoning enabled by default. To disable it you'll need to pass `"chat_template_kwargs": {"enable_thinking": False}` (or similar).
- If VLLM is run with a reasoning parser (e.g. `--reasoning-parser qwen3`), it extracts the reasoning into separate reasoning and reasoning_content fields instead of keeping `<think>` tags in the main content.
- By default, if you write a script that starts a VLLM server, you should check if the model is a Qwen 3 model and include the reasoning parser if so.
- Scripts that interact with existing VLLM servers (e.g. python scripts that use a given host/port, etc.) should accommodate both separate reasoning content and reasoning that's included in the main content.