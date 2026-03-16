# Finetuning API — API Reference

All endpoints require the beta header: `Anthropic-Beta: finetuning-2025-09-03`

---

## Trainer Management

### Create Trainer

`POST /v1/finetuning/trainers`

**Request:**
```json
{
  "model_name": "claude-haiku-4-5-20251001",
  "initial_checkpoint_id": "ft_ckpt_xyz789"
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `model_name` | string | Yes | Base model to finetune. Currently only `claude-haiku-4-5-20251001`. |
| `initial_checkpoint_id` | string | No | Resume from an existing checkpoint (`ft_ckpt_...`). NOT a snapshot ID. |

**Response (201):**
```json
{
  "type": "trainer",
  "id": "ft_trainer_abc123",
  "model_name": "claude-haiku-4-5-20251001",
  "initial_checkpoint_id": null,
  "status": "idle",
  "step": 0,
  "step_details": null,
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z"
}
```

---

### Get Trainer

`GET /v1/finetuning/trainers/{trainer_id}`

| Query Parameter | Type | Default | Description |
|----------------|------|---------|-------------|
| `include_training_history` | boolean | false | Include full per-step metrics history. |

**Response:**
```json
{
  "type": "trainer",
  "id": "ft_trainer_abc123",
  "model_name": "claude-haiku-4-5-20251001",
  "status": "idle",
  "step": 5,
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:01:00Z"
}
```

**Trainer Status Values:**
| Status | Description |
|--------|-------------|
| `idle` | Ready for training |
| `grads_pending` | Gradients computed, waiting for `apply_grads` |
| `training` | A training operation is in progress |
| `errored` | The trainer encountered an error |

When `include_training_history=true`, the response includes a `training_history` array with per-step metrics (loss, valid trajectories, filtered indices).

---

### List Trainers

`GET /v1/finetuning/trainers`

| Query Parameter | Type | Default | Description |
|----------------|------|---------|-------------|
| `limit` | integer | 20 | Maximum trainers to return |
| `after_id` | string | — | Trainer ID for forward pagination |
| `before_id` | string | — | Trainer ID for backward pagination |

**Response:**
```json
{
  "data": [
    {
      "type": "trainer",
      "id": "ft_trainer_abc123",
      "model_name": "claude-haiku-4-5-20251001",
      "status": "idle",
      "step": 5,
      "created_at": "2024-01-01T00:00:00Z",
      "updated_at": "2024-01-01T00:01:00Z"
    }
  ],
  "has_more": false,
  "first_id": "ft_trainer_abc123",
  "last_id": "ft_trainer_xyz789"
}
```

---

## Training

### RL Sample

`POST /v1/finetuning/trainers/{trainer_id}/rlsample`

Generate completions for RL while tracking trajectories.

**Request:**
```json
{
  "snapshot_id": "ft_snap_abc123",
  "messages": [
    {"role": "user", "content": "What is the best move?"}
  ],
  "previous_message_id": "ft_msg_prev123",
  "max_tokens": 1024,
  "system": "You are a helpful assistant."
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `step` | integer | Yes* | Trainer step to sample from. Mutually exclusive with `snapshot_id`. |
| `snapshot_id` | string | No* | Snapshot ID (`ft_snap_...`) to sample from. Mutually exclusive with `step`. |
| `messages` | array | Yes | New messages for this turn (do not re-send prior turns) |
| `max_tokens` | integer | Yes | Maximum tokens to generate |
| `previous_message_id` | string | No | Continue an existing trajectory |
| `system` | string/array | No | System prompt. Only on first message of a trajectory. |
| `tools` | array | No | Tool definitions (same format as `/v1/messages`). `tool_choice` must be `auto` or omitted. |

\* Exactly one of `step` or `snapshot_id` must be provided.

**Response:**
```json
{
  "id": "ft_msg_abc123",
  "type": "message",
  "role": "assistant",
  "content": [{"type": "text", "text": "The answer is 5."}],
  "trajectory_id": "ft_traj_xyz789",
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 150,
    "output_tokens": 25
  }
}
```

**Stop Reasons:**
| Value | Description |
|-------|-------------|
| `end_turn` | Model finished normally |
| `max_tokens` | Response truncated at token limit |
| `refusal` | Safety refusal. Trajectory auto-filtered during training. |

---

### Forward (Precompute Teacher Logprobs)

`POST /v1/finetuning/trainers/{trainer_id}/forward`

Precompute teacher model logprobs for distillation.

**Request:**
```json
{
  "model": "claude-opus-4-6",
  "trajectory_ids": ["ft_traj_abc123"]
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `model` | string | Yes | Teacher model to compute logprobs with |
| `trajectory_ids` | array | Yes | Trajectory IDs to score |

**Response:**
```json
{
  "results": [
    {"trajectory_id": "ft_traj_abc123", "logprob_id": "ft_lp_xyz789"}
  ]
}
```

Pass the returned `logprob_id` values as `ref_logprob_id` on individual trajectories in `forward_backward`.

---

### Forward Backward

`POST /v1/finetuning/trainers/{trainer_id}/forward_backward`

Compute gradients for a batch of trajectories. Call multiple times to accumulate gradients before `apply_grads`.

**Request:**
```json
{
  "step": 0,
  "batch": [...],
  "loss_config": {
    "type": "policy_gradient",
    "reward_weight": 0.0,
    "distillation_weight": 1.0
  }
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `step` | integer | Yes | Must match trainer's current step |
| `batch` | array | Yes | Trajectories (all same type: RL or SFT) |
| `loss_config` | object | No | For distillation. See loss config below. |

**RL Trajectory Format:**
```json
{
  "messages": "ft_traj_xyz789",
  "weight": {
    "application": "trajectory",
    "trajectory_weight": 1.5
  },
  "ref_logprob_id": "ft_lp_abc123"
}
```

**SFT Trajectory Format:**
```json
{
  "messages": [
    {"role": "user", "content": "What is 2+2?"},
    {"role": "assistant", "content": "4"}
  ],
  "system": "You are a helpful assistant.",
  "tools": [],
  "weight": {
    "application": "trajectory",
    "trajectory_weight": 1.0
  }
}
```

**Per-Turn Weighted Trajectory (RL only):**
```json
{
  "messages": "ft_traj_abc456",
  "weight": {
    "application": "per_turn",
    "per_turn_weight": [
      {"message_id": "ft_msg_001", "weight": 1.5},
      {"message_id": "ft_msg_002", "weight": 0.5}
    ]
  }
}
```

**Loss Config:** See the Loss Configuration section in `workflows.md` for the full table and per-token loss formula. Defaults to `{"type": "policy_gradient", "reward_weight": 1.0}` (pure RL).

**Response:**
```json
{
  "loss": 2.3456,
  "training_info": {
    "requested_trajectories": 10,
    "valid_trajectories": 9,
    "filtered_indices": [4]
  }
}
```

| Field | Description |
|-------|-------------|
| `loss` | Training loss for this batch |
| `training_info.requested_trajectories` | Total submitted |
| `training_info.valid_trajectories` | Used after filtering refusals |
| `training_info.filtered_indices` | Indices of filtered trajectories |

---

### Apply Gradients

`POST /v1/finetuning/trainers/{trainer_id}/apply_grads`

Apply accumulated gradients and advance the training step.

**Request:**
```json
{
  "step": 0,
  "lr_factor": 1.0
}
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `step` | integer | Yes | — | Must match `forward_backward` step |
| `lr_factor` | float | No | 1.0 | Learning rate multiplier. Must be > 0. |

**Response:**
```json
{
  "next_step": 1,
  "result": {}
}
```

| Field | Description |
|-------|-------------|
| `next_step` | Step number for subsequent calls |
| `result` | Reserved for future use |

---

## Checkpoint Management

### Create Checkpoint

`POST /v1/finetuning/trainers/{trainer_id}/checkpoints`

Save full trainer state (weights + optimizer) for resuming or forking training. No request body required. Requires at least one `forward_backward` call on the trainer.

Idempotent: if a checkpoint already exists at the current step, the existing checkpoint is returned.

**There are no GET or LIST endpoints for checkpoints.** Save the returned `id` immediately.

**Response (201):**
```json
{
  "type": "checkpoint",
  "id": "ft_ckpt_abc123",
  "trainer_id": "ft_trainer_xyz789",
  "step": 5,
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z",
  "expires_at": "2024-01-08T00:00:00Z"
}
```

Pass the returned `id` as `initial_checkpoint_id` when creating a new trainer to resume from this point.

---

## Snapshot Management

### Create Snapshot

`POST /v1/finetuning/trainers/{trainer_id}/snapshots`

No request body required.

**Response (201):**
```json
{
  "type": "snapshot",
  "id": "ft_snap_abc123",
  "trainer_id": "ft_trainer_xyz789",
  "step": 5,
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z",
  "expires_at": "2024-02-01T00:00:00Z"
}
```

Unpromoted snapshots expire after 7 days.

---

### Get Snapshot

`GET /v1/finetuning/snapshots/{snapshot_id}`

**Response:**
```json
{
  "type": "snapshot",
  "id": "ft_snap_abc123",
  "trainer_id": "ft_trainer_xyz789",
  "step": 5,
  "created_at": "2024-01-01T00:00:00Z",
  "expires_at": "2024-02-01T00:00:00Z"
}
```

---

### List Snapshots

`GET /v1/finetuning/snapshots`

| Query Parameter | Type | Default | Description |
|----------------|------|---------|-------------|
| `trainer_id` | string | — | Filter by trainer |
| `limit` | integer | 20 | Maximum to return |
| `after_id` | string | — | Pagination cursor |
| `before_id` | string | — | Pagination cursor |

**Response:**
```json
{
  "data": [
    {
      "type": "snapshot",
      "id": "ft_snap_abc123",
      "trainer_id": "ft_trainer_xyz789",
      "step": 5,
      "created_at": "2024-01-01T00:00:00Z",
      "expires_at": "2024-02-01T00:00:00Z"
    }
  ],
  "has_more": false,
  "first_id": "ft_snap_abc123",
  "last_id": "ft_snap_def456"
}
```

---

### Promote Snapshot

`POST /v1/finetuning/snapshots/{snapshot_id}/promote`

Prevent snapshot expiration. No request body required.

**Response:**
```json
{
  "type": "snapshot",
  "id": "ft_snap_abc123",
  "trainer_id": "ft_trainer_xyz789",
  "step": 5,
  "created_at": "2024-01-01T00:00:00Z",
  "expires_at": null
}
```

---

### Run Inference with Snapshot

`POST /v1/messages`

Use the finetuned model by appending the snapshot ID to the base model name:

```json
{
  "model": "claude-haiku-4-5-20251001-ft_snap_abc123",
  "max_tokens": 1024,
  "messages": [{"role": "user", "content": "hello"}]
}
```

---

## Identifier Formats

| Resource | Prefix |
|----------|--------|
| Trainer | `ft_trainer_` |
| Snapshot | `ft_snap_` |
| Checkpoint | `ft_ckpt_` |
| Trajectory | `ft_traj_` |
| Message | `ft_msg_` |
| Logprob | `ft_lp_` |

---

## Error Handling

### Standard HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 201 | Resource created |
| 400 | Invalid request |
| 401 | Authentication failed |
| 404 | Resource not found |
| 409 | Conflict (e.g., step mismatch) |
| 429 | Rate limit exceeded |
| 500 | Server error |

### Error Format

```json
{
  "error": {
    "type": "invalid_request_error",
    "message": "Trainer not found: ft_trainer_invalid123"
  }
}
```

### Common Errors

**Step Mismatch (409):**
```json
{"error": {"type": "invalid_request_error", "message": "Step mismatch: expected 5, got 4"}}
```
Solution: Use the correct step from the latest response.

**Missing Beta Header (400):**
```json
{"error": {"type": "invalid_request_error", "message": "Missing required `finetuning-2025-09-03` value in the `anthropic-beta` header."}}
```
Solution: Include `anthropic-beta: finetuning-2025-09-03` header.

---

## Weight Behavior

**Trajectory Weight:**
- Applied uniformly to the entire trajectory
- Positive: reinforce behavior
- Negative: discourage behavior
- Larger magnitude = stronger effect

**Per-Turn Weight (RL only):**
- Applied to specific messages
- Enables credit assignment across turns
- Not supported for SFT trajectories
