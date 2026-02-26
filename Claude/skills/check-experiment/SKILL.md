---
name: check-experiment
description: Check the status of a running or completed experiment — slurm jobs, result completeness, failures
---

# Check Experiment Status

Check the health and completion status of an experiment. This skill reports whether jobs have completed, failed, or are still running, and flags any empty LLM responses or judge failures in the results. It does NOT analyze results or report eval scores.

## Arguments

$ARGUMENTS = experiment subdirectory name or path (e.g., "260224_censorship-baselines" or "experiments/260224_censorship-baselines"). If empty, infer the experiment from recent conversation context (e.g., a directory the user has been working in). If ambiguous, ask.

## Steps

### 1. Locate the experiment directory

Resolve the experiment directory. Check these locations in order:
- If an absolute path is given, use it directly
- `experiments/$ARGUMENTS` relative to the current project root
- `/workspace-vast/$USER/experiments/$ARGUMENTS`
- If just a partial name is given (e.g., "censorship"), glob for matching directories

If the directory doesn't exist, report an error and stop.

### 2. Read submission scripts (if not already in context)

If the submission scripts (`1_submit_all.sh`, `1b_*.sh`, `1c_*.sh`, etc.) have NOT already been read in this conversation, read them now to understand:
- What jobs were submitted (eval jobs, training jobs, etc.)
- What models and evals are expected
- Any special configuration

Also read `config.yaml` to understand the expected evals and models.

If these files are already in the conversation context, skip this step.

### 3. Read job logs to identify submitted jobs

Check for job submission logs that record slurm job IDs:
- `eval_jobs.log` — eval job submissions
- `jobs.log` — training job submissions
- `jobs_resubmit.log` — resubmission logs
- Any other `*jobs*.log` files

Extract the slurm job IDs and job descriptions from these files.

### 4. Check slurm job status

For each job ID found in the logs, check its current status:

```bash
sacct -j <comma-separated-job-ids> --format=JobID,JobName%40,State,ExitCode,Elapsed,Start,End --noheader --parsable2
```

If there are no job logs or you need to find jobs by name, use:
```bash
sacct -u $USER --name=<job-name-pattern> --format=JobID,JobName%40,State,ExitCode,Elapsed,Start,End --noheader --parsable2 --starttime=<reasonable-start-date>
```

Categorize jobs as: RUNNING, PENDING, COMPLETED, FAILED, TIMEOUT, CANCELLED, PREEMPTED, or other.

### 5. Check results for completeness and failures

List the contents of the `results/` directory. For each eval/model combination found:

**a) Check for empty or missing responses:**
Read the `*_results.jsonl` files and check for:
- Lines where `response` is empty, null, or missing
- Lines where `response` contains only whitespace
- Files that are unexpectedly small or empty

Use grep to efficiently scan for issues rather than reading entire files:
```bash
# Count total lines
wc -l results/**/*_results.jsonl

# Check for empty responses (adapt field name as needed)
grep -c '"response": ""' <file>
grep -c '"response": null' <file>
grep -c '"response":""' <file>
```

Before doing this, check the results file to see exactly how model responses are formatted so you can search properly.

**b) Check for judge/classification failures:**
Look for lines where judgment fields are empty or indicate failure:
- `classification` is empty, null, or missing
- `judgment` is empty, null, or missing
- `score` is null or missing (when expected)
- Any field containing "error" or "Error" in judge output

Before doing this, check the results file to see exactly how judge responses are formatted so you can search properly.

**c) Check for missing expected results:**
Cross-reference the models and evals from `config.yaml` against what actually exists in `results/`. Flag any expected model/eval combinations that have no results directory or no result files.

### 6. Check log files for errors (if needed)

If any jobs FAILED, were CANCELLED, or hit TIMEOUT, read the relevant log files from `logs/` to identify the error. Log files typically follow the pattern `<job-name>_<job-id>.out`.

Only read logs for jobs that had problems — don't read logs for successfully completed jobs unless there are other red flags (like empty responses despite a COMPLETED status).

### 7. Report status

Present a concise summary organized by job/model. For each:

- **Job status**: COMPLETED / FAILED / RUNNING / PENDING / etc.
- **Result files**: present or missing
- **Empty responses**: count (if any)
- **Judge failures**: count (if any)
- **Error summary**: brief description if the job failed (from logs)

Format as a bullet-point list. Example:

- `eval_qwen32b_thinking` (job 994696): **COMPLETED**
  - gpqa: 198 results, 0 empty responses, 0 judge failures
  - censorship: 150 results, 2 empty responses, 0 judge failures
- `eval_sonnet45_thinking` (job 994697): **FAILED** (exit code 1)
  - Error: ANTHROPIC_API_KEY not set
  - No results produced
- `eval_honly_opus46_thinking` (job 994698): **RUNNING** (elapsed 01:23:45)
  - No results yet

At the end, give a one-line overall summary like:
- "3/5 jobs completed successfully, 1 failed, 1 still running. 2 empty responses found across all results."

## Important

- Do NOT analyze results, compute scores, or interpret eval outcomes. This skill is purely about job health and completeness.
- Do NOT attempt to resubmit or fix anything. Just report.
- Use `Bash` with `sacct` and `grep`/`wc` for efficient checking — avoid reading entire large result files when counts suffice.
- If the experiment has no job logs at all (e.g., jobs were submitted manually), fall back to checking result directories and slurm history.
