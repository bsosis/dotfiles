---
name: bsosis-experiment
description: Scaffold a new experiment folder with config and submission scripts
---

# New Experiment

Create a new experiment folder with standard structure, config, and stub scripts. Experiments live in `/workspace-vast/$USER/experiments/` (external to any repo) and are symlinked into the current project's `experiments/` directory.

## Arguments

$ARGUMENTS = experiment name (e.g., "gpqa_sweep" or "sdft_v3_ablation")

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

## Goal
<ask user for 1-2 sentence goal>

## Hypothesis
<ask user>

## Key Results
<!-- to be filled after experiment completes -->
```

### `config.yaml`
```yaml
# Experiment: <name>
# Date: YYYY-MM-DD
# Goal: <from user>
```
Populate with whatever parameters are relevant to the experiment based on user description.
Do NOT include boilerplate fields that aren't relevant. Keep it minimal.

### `1_submit_all.sh`
```bash
#!/bin/bash
# Submit all jobs for this experiment
# Reproduces: experiments/YYMMDD_<name>/
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Experiment: $SCRIPT_DIR"
echo "Date: $(date -Iseconds)"

# Submit jobs — fill in
```

### `2_analyze.sh`
```bash
#!/bin/bash
# Analyze results from this experiment
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Experiment: $SCRIPT_DIR ==="
echo "=== Date: $(date -Iseconds) ==="
```

4. **Make scripts executable**: `chmod +x` on all `.sh` files

5. **Do NOT create a git branch** — experiments are personal and untracked.

6. **Print next steps**:
   ```
   Experiment scaffolded: experiments/YYMMDD_<name>/
   (at /workspace-vast/$USER/experiments/YYMMDD_<name>/)

   Next steps:
   1. Edit config.yaml with your parameters
   2. Fill in 1_submit_all.sh with submission commands
   3. Run: bash experiments/YYMMDD_<name>/1_submit_all.sh
   4. Analyze: bash experiments/YYMMDD_<name>/2_analyze.sh
   ```
