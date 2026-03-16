---
name: finetuning-api
description: >
  Anthropic Finetuning API — RL/GRPO, on-policy distillation, and supervised fine-tuning (SFT)
  for Claude models. Covers the full /v1/finetuning/ endpoint surface: trainers, snapshots,
  trajectories, forward_backward, apply_grads, rlsample, teacher logprobs via /forward, loss
  configuration, GRPO advantage estimation, checkpoints, and training loops. Use this skill whenever
  the user mentions finetuning, fine-tuning, training a Claude model, RL training, GRPO, distillation
  from Opus to Haiku, SFT, reward functions for Claude, trajectory weights, training steps,
  lr_factor, snapshots, checkpoints, or references any /v1/finetuning/ endpoint. Also use when the user asks
  how to customize Claude for a specific task, domain-adapt a model, or improve Claude's
  performance on their use case through training. Even if they say "train" or "customize" without
  explicitly saying "finetune", this skill likely applies.
---

# Finetuning API

Build finetuning workflows using the Anthropic Finetuning API. Covers all three training methods (RL/GRPO, on-policy distillation, SFT), the full API surface, best practices, and complete working examples.

**Status**: Early alpha. Features and interfaces may change.

## Defaults

- **Student model**: `claude-haiku-4-5-20251001` (only supported model for finetuning)
- **Teacher models** (distillation only): `claude-opus-4-5-20251101`, `claude-opus-4-6`
- **Beta header**: `anthropic-beta: finetuning-2025-09-03` (required on all requests)
- **HTTP client**: Use `httpx` with `base_url="https://api.anthropic.com"` and `timeout=1800`

---

## Architecture

All finetuning goes through dedicated `/v1/finetuning/` endpoints. The core concepts:

- **Trainer**: A finetuning instance for a base model. Maintains state across training steps.
- **Snapshot** (`ft_snap_...`): Inference-only weights. Used for inference via `/v1/messages`. Can be listed and retrieved. Expire after 7 days unless promoted.
- **Checkpoint** (`ft_ckpt_...`): Full trainer state (weights + optimizer). Used to resume/fork training via `initial_checkpoint_id` on `POST /trainers`. No GET/LIST endpoints — save the ID from the create response. Expire after 7 days. Cannot be created before the first `forward_backward` call.
- **Trajectory**: A sequence of conversation turns collected during model interaction (RL) or provided directly (SFT).
- **Training Step**: Two-phase process — `forward_backward` (compute gradients) then `apply_grads` (update weights).

**Snapshots vs Checkpoints**: These are NOT interchangeable. Snapshots are for inference only (no optimizer state). Checkpoints are for resuming training (full state). You cannot use a snapshot ID as `initial_checkpoint_id`.

### Training Flow

```
Create Trainer → Snapshot → [Sample (RL) or Provide Data (SFT)] → forward_backward → apply_grads → Snapshot → repeat
```

A snapshot makes the trainer's current weights available for inference. It is required before `/rlsample` — think of it as making the trainer "ready for sampling". After `apply_grads`, the system auto-creates an internal snapshot for the next step, but the initial snapshot after trainer creation must be created explicitly.

For distillation, add a `/forward` call to precompute teacher logprobs before `forward_backward`.

### Save-and-Resume Flow

```
Train → POST /trainers/{id}/checkpoints (save ft_ckpt_...) → POST /trainers/{id}/snapshots (save ft_snap_...) → Later: POST /trainers with initial_checkpoint_id
```

---

## Choosing a Training Method

| Situation | Method | Rationale |
|-----------|--------|-----------|
| Golden trajectories, no environment | **SFT** | Only option without live interaction |
| Golden trajectories + environment | **SFT → GRPO** | SFT bootstraps, RL refines |
| Environment + Opus >> Haiku on your task | **Distillation** | Strong teacher signal when gap is large |
| Environment + both Opus and Haiku are weak | **GRPO** | No good teacher; model must explore |

**Key considerations:**
- Assess the Opus-Haiku performance gap first. Large gap → distillation. Small/no gap → GRPO.
- Distillation is simpler (no reward function needed) but plateaus when the student becomes competent.
- SFT is a reliable initialization step before switching to RL.

---

## Reading Guide

**Quick start / overview:**
→ Read `SKILL.md` (this file)

**RL/GRPO workflow with reward functions and advantage estimation:**
→ Read `workflows.md` § Reinforcement Learning

**On-policy distillation from Opus into Haiku:**
→ Read `workflows.md` § Distillation

**Supervised fine-tuning on static datasets:**
→ Read `workflows.md` § Supervised Learning

**Hyperparameters, monitoring, troubleshooting:**
→ Read `best-practices.md`

**Full API endpoint reference (request/response schemas):**
→ Read `api-reference.md`

---

## Quick Client Setup

```python
import httpx
import os

client = httpx.Client(
    base_url="https://api.anthropic.com",
    headers={
        "x-api-key": os.environ["ANTHROPIC_API_KEY"],
        "Anthropic-Version": "2023-06-01",
        "Anthropic-Beta": "finetuning-2025-09-03",
        "content-type": "application/json",
    },
    timeout=1800,
)
```

---

## Common Pitfalls

- **Missing snapshot before rlsample**: You must create a snapshot (`POST /trainers/{id}/snapshots`) before the first `/rlsample` call on a new trainer. After `apply_grads`, the system handles this automatically for subsequent steps.
- **Using snapshot IDs to resume training**: `initial_checkpoint_id` requires a checkpoint ID (`ft_ckpt_...`), not a snapshot ID (`ft_snap_...`). Snapshots lack optimizer state.
- **Missing beta header**: All finetuning endpoints require `anthropic-beta: finetuning-2025-09-03`. Omitting it returns a 400 error.
- **Step mismatch**: Always use the `next_step` value from `apply_grads` response. Using a stale step returns 409.
- **System prompt on continuations**: Only specify the system prompt in the first `/rlsample` call of a trajectory. Omit it on subsequent turns.
- **Unsupported features**: Multimodal content and server-side tool use/MCPs are not supported.
- See the **Batch Validation Rules** section in `workflows.md` for the full list of trajectory and distillation constraints.

