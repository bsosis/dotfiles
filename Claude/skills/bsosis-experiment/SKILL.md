---
name: bsosis-experiment
description: Scaffold a new experiment folder with config and submission scripts
---

# New Experiment

Create a new experiment folder with standard structure, config, and stub scripts. Experiments live in `/workspace-vast/$USER/experiments/` (external to any repo) and are symlinked into the current project's `experiments/` directory.

## Arguments

$ARGUMENTS = experiment name (e.g., "gpqa_sweep" or "sdft_v3_ablation"), experiment description (optional)

## Steps

1. **Generate folder name**: `YYMMDD_<name>` using today's date

2. **Set up directory and symlink**:
   - Create `/workspace-vast/$USER/experiments/YYMMDD_<name>/`
   - If `experiments` does not exist in the current project root, create a symlink: `experiments -> /workspace-vast/$USER/experiments`
   - If `experiments` exists and is a real directory, ask the user before replacing it with a symlink
   - Verify the symlink is gitignored (both `experiments/` and `experiments` entries). If not, add them.

3. **Populate the experiment folder** with ALL of the following files:

### `README.md`
```markdown
# Experiment: <name>
Date: YYYY-MM-DD
Author: <git user.name>

## Description
<if not provided in initial prompt, ask user for 1-2 sentence description>

## Key Results
<!-- to be filled after experiment completes -->
```

### `config.yaml`
```yaml
# Experiment: <name>
# Date: YYYY-MM-DD
# Description: <from user>
```
Populate with whatever parameters are relevant to the experiment based on user description.
Do NOT include boilerplate fields that aren't relevant. Keep it minimal.

The submission and evaluation scripts below should load all relevant arguments from the config file; do not hard-code values in the scripts.

### `1_submit_all.sh`

**If the experiment involves running evals**, this should often (but not always) be a thin wrapper that calls the generic `experiments/submit_evals.sh` script:

```bash
#!/bin/bash
# Submit eval jobs for this experiment.
# Usage: bash 1_submit_all.sh [--honly|--no-honly|--all] [-n N]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../submit_evals.sh" "$SCRIPT_DIR" "$@"
```

For this to work, `config.yaml` must include `evals` and `models` fields in the format expected by `submit_evals.sh`:

```yaml
evals: tax_fraud,ice_eval  # comma-separated eval names from EVAL_REGISTRY

models:
  - name: Qwen/Qwen3-32B        # model path or API name
    type: vllm                   # vllm or api
    label: qwen32b               # short label for output dirs
  - name: claude-sonnet-4-5
    type: api
    label: sonnet45
  - name: claude-oven-v0-4       # honly models must have labels starting with "honly_"
    type: api
    label: honly_sonnet4
```

`submit_evals.sh` handles:
- `--all` (default) / `--honly` / `--no-honly` model filtering
- `-n N` for API job concurrency throttling via slurm dependency chaining (omit for no throttling)
- vLLM jobs are always submitted immediately (no chaining)
- API key swapping for `honly_*` models (`ANTHROPIC_API_KEY_HONLY`)
- Results saved to `<experiment_dir>/results/`, logs to `<experiment_dir>/logs/`

**If the experiment does NOT involve evals** (e.g., training runs), write a custom submission script instead.

Note, if the submission script is fairly complex you may want to use a Python script `1_submit_all.py` rather than a shell script.

### `2_analyze.sh`
```bash
#!/bin/bash
# Analyze results from this experiment
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Experiment: $SCRIPT_DIR ==="
echo "=== Date: $(date -Iseconds) ==="
```

If there are standard plotting scripts for the evals used, the analysis script should run them. Otherwise, you can implement a bespoke plotting script for the experiment (if there is an obvious way to plot the data), simply print out some summary metrics, or ask the user.

### Experimental Tips
- We will often run evaluations in both thinking and non-thinking mode; by default you should usually set up the experiment scripts to run both in parallel jobs. If uncertain, ask the user.
- The evaluation harness `src/evals/run_all.py` (and other scripts that call it) supports flags `medium` and `quick` with different preset parameters for the different evals. Usually `quick` is used for evaluating many different training checkpoints or during hyperparameter sweeps, while `medium` is used for thoroughly evaluating the best checkpoints or baseline models. If uncertain, ask the user.
- You should generally set the slurm quality of service to `high` to avoid preemption. In some cases when running large numbers of API jobs it may be desirable to use `low`, but VLLM jobs should almost always use `high` since startup times for the VLLM server make restarts very time-consuming.

4. **Make scripts executable**: `chmod +x` on all `.sh` files

5. **Do NOT create a git branch** — experiments are personal and untracked.

6. **Print next steps**:
Include a reminder to label the current Claude Code session using `/rename`. Also include notes on the important configuration choices you made.

Representative example (edit as needed):
   ```
   Experiment scaffolded: experiments/YYMMDD_<name>/
   (at /workspace-vast/$USER/experiments/YYMMDD_<name>/)

   Run `/rename YYMMDD_<name>` to label this session.
   Evaluations run in both thinking and non-thinking mode with `medium` preset and `qos=high`.

   Next steps:
   1. Edit config.yaml with your parameters
   2. Fill in 1_submit_all.sh with submission commands
   3. Run: bash experiments/YYMMDD_<name>/1_submit_all.sh
   4. Analyze: bash experiments/YYMMDD_<name>/2_analyze.sh
   ```
