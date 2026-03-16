# Finetuning API — Best Practices

## Reinforcement Learning

1. **Use GRPO Advantage Estimation**
   - Sample multiple completions per prompt (4–8 recommended)
   - Calculate rewards for each completion
   - Compute advantages: `advantage = reward - mean(rewards)` for each prompt group
   - Use advantages as trajectory weights instead of raw rewards

2. **Recommended Hyperparameters**
   - Batch size: hundreds of trajectories per step. For GRPO, effective batch size = prompts × samples per prompt.
   - `lr_factor`: Start with 1. Use 100–1000 if testing on simpler environments. These values were calibrated at ~64 trajectories — adjust if your batch size differs significantly.

3. **Parallel Collection**
   - Sample from the trainer while `forward_backward` is running to overlap compute.

4. **Gradient Accumulation**
   - Call `forward_backward` multiple times before `apply_grads` for larger effective batch sizes.

5. **Evaluate with Reward**
   - Loss will not necessarily decrease when the model improves.
   - Track your reward function on a held-out evaluation set as the primary metric.

---

## Distillation

1. **Run a Baseline Eval First**
   - Evaluate both Opus (teacher) and Haiku (student) on representative tasks.
   - Measure the performance gap — this is the ceiling for distillation improvement.
   - If Opus doesn't perform well, distillation won't help; consider GRPO instead.

2. **Recommended Hyperparameters**
   - `lr_factor`: Start with 0.3–1.0. Higher values (3.0+) risk training collapse. Calibrated at ~64 trajectories.
   - Batch size: 8–64 trajectories per step. Larger batches give more stable gradients.
   - Use gradient accumulation for larger effective batch sizes.

3. **What to Monitor**
   - **Loss**: Should decrease as the student learns to imitate the teacher.
   - **Train reward**: Track your grading function on the on-policy trajectories each step.
   - **Eval reward**: Periodic evaluations on held-out problems. This is the most important metric.

4. **Troubleshooting Non-Decreasing Loss**
   - Is eval reward still improving? The student may be finding valid alternative solutions that differ from the teacher's approach.
   - Try lowering `lr_factor` (e.g., from 1.0 to 0.3) if loss is erratic or increasing.
   - Very long trajectories (100+ turns) structurally accumulate more teacher-student divergence. Focus on reward metrics rather than loss.

5. **Detecting Training Collapse**
   - Symptoms: reward drops to 0, loss may spike or become erratic.
   - Usually caused by `lr_factor` being too high.
   - Recovery: kill the run, create a new trainer from the last good checkpoint (`initial_checkpoint_id`), restart with a lower `lr_factor`.

6. **Checkpoint Frequency**
   - Save checkpoints every 3–5 training steps for collapse recovery. Save snapshots at the same cadence for inference evaluation. Both expire after 7 days.

---

## General

1. **Monitor Training**
   - Track loss and your reward function across steps.
   - Use `include_training_history=true` when fetching trainer details for the full per-step metrics history.

2. **Save Checkpoints**
   - Create checkpoints and snapshots regularly for collapse recovery and evaluation.

3. **Step Synchronization**
   - Always use `next_step` from the `apply_grads` response for subsequent calls.

4. **Error Handling**
   - Implement retry logic for transient failures (429, 5xx) with exponential backoff and jitter.
   - Wrap each trajectory sampling in try/except so a single failed trajectory doesn't crash the entire training step. Log the error and continue to the next trajectory.

5. **Handle Refusals**
   - RL sampling may return refusals (`stop_reason: "refusal"`).
   - Check `training_info.filtered_indices` in `forward_backward` results.

---

## Method Selection Decision Guide

```
Do you have an environment (can generate new responses and evaluate them)?
├── No → Do you have golden example conversations?
│   ├── Yes → SFT
│   └── No → Cannot finetune (need data or an environment)
└── Yes → Is Opus much better than Haiku on your task?
    ├── Yes (large gap) → Distillation
    │   └── As student improves, consider switching to GRPO
    ├── Both weak → GRPO (model must discover solutions through exploration)
    └── Small gap → GRPO (teacher can't add much value)

Bonus: If you have golden data AND an environment → SFT first, then GRPO
```
