# Finetuning API — Training Workflows

## On-Policy Distillation

On-policy distillation trains a student model (Haiku 4.5) on its own trajectories using a stronger teacher model's (Opus) token-level log-probabilities as supervision. Unlike RL which needs a reward function, distillation uses the teacher's knowledge directly.

### How It Works

1. **Sample**: Generate trajectories from the student via `/rlsample`
2. **Compute teacher logprobs**: Call `/forward` with the teacher model and trajectory IDs
3. **Train**: Submit trajectories to `forward_backward` with `ref_logprob_id` per trajectory and a `loss_config`, then call `apply_grads`
4. **Snapshot**: Save checkpoints and evaluate

### Allowed Teacher Models

- `claude-opus-4-5-20251101`
- `claude-opus-4-6`

### Example

```python
MODEL_NAME = "claude-haiku-4-5-20251001"
TEACHER_MODEL = "claude-opus-4-6"

# Create trainer
trainer = client.post(
    url="/v1/finetuning/trainers",
    json={"model_name": MODEL_NAME},
).json()

trainer_id = trainer["id"]

# Create initial snapshot — required before first /rlsample call
snapshot = client.post(url=f"/v1/finetuning/trainers/{trainer_id}/snapshots").json()
snapshot_id = snapshot["id"]

# Sample trajectories and precompute teacher logprobs
batch = []
for prompt in prompts:
    response = client.post(
        url=f"/v1/finetuning/trainers/{trainer_id}/rlsample",
        json={
            "snapshot_id": snapshot_id,
            "system": "You are a helpful assistant.",
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 2048,
        },
    ).json()
    tid = response["trajectory_id"]

    # Precompute teacher logprobs via /forward
    fwd_resp = client.post(
        url=f"/v1/finetuning/trainers/{trainer_id}/forward",
        json={"model": TEACHER_MODEL, "trajectory_ids": [tid]},
    ).json()

    batch.append({
        "messages": tid,
        "weight": {"application": "trajectory", "trajectory_weight": 1.0},
        "ref_logprob_id": fwd_resp["results"][0]["logprob_id"],
    })

# Compute gradients with distillation loss
current_step = snapshot["step"]
fwd_bwd_response = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/forward_backward",
    json={
        "step": current_step,
        "batch": batch,
        "loss_config": {
            "type": "policy_gradient",
            "reward_weight": 0.0,
            "distillation_weight": 1.0,
        },
    },
).json()

print(f"Loss: {fwd_bwd_response['loss']}")

# Apply gradients
apply_response = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/apply_grads",
    json={"step": current_step, "lr_factor": 1.0},
).json()

current_step = apply_response["next_step"]
```

### Loss Configuration

The `loss_config` parameter controls how the training loss is computed:

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `"policy_gradient"` |
| `reward_weight` | float | Weight for the reward loss term (>= 0). Set to 0 for pure distillation. |
| `distillation_weight` | float | Weight for the distillation loss term (> 0). |

**Per-token loss formula:**

```
per_token_loss = reward_weight * L_reward + distillation_weight * L_distill

L_reward  = -advantage * log_prob_student(token)
L_distill = log_prob_student(token) - log_prob_teacher(token)

total_loss = mean(per_token_loss)
```

You can combine distillation with reward by setting both `reward_weight` and `distillation_weight` > 0. In this mode, trajectories should be weighted with reward-based advantages as in standard RL.

---

## Reinforcement Learning Workflow

### Overview

The RL workflow has three phases:
1. **Sample**: Generate model completions and track trajectories
2. **Evaluate**: Calculate rewards based on your custom criteria
3. **Train**: Update the model using trajectories and their rewards

Training is split into two API calls per step:
- `forward_backward` — computes gradients from a batch of trajectories. Can be called multiple times at the same step to accumulate gradients.
- `apply_grads` — applies accumulated gradients and advances the step.

### Step 1: Create a Trainer

```python
trainer = client.post(
    url="/v1/finetuning/trainers",
    json={"model_name": "claude-haiku-4-5-20251001"},
).json()

trainer_id = trainer["id"]

# Create initial snapshot — required before first /rlsample call.
# After apply_grads, the system auto-creates one for the next step.
snapshot = client.post(url=f"/v1/finetuning/trainers/{trainer_id}/snapshots").json()
snapshot_id = snapshot["id"]
```

### Step 2: Training Loop

#### Collect Trajectories

Sample from the model to collect interaction data. Build multi-turn conversations by chaining messages:

```python
# Start a new trajectory
response1 = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/rlsample",
    json={
        "snapshot_id": snapshot_id,
        "messages": [{"role": "user", "content": "What is 2+2?"}],
        "max_tokens": 100,
    },
).json()

# Continue the same trajectory
response2 = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/rlsample",
    json={
        "snapshot_id": snapshot_id,
        "previous_message_id": response1["id"],
        "messages": [{"role": "user", "content": "Now multiply by 3"}],
        "max_tokens": 100,
    },
).json()
```

**Key points:**
- Omit `previous_message_id` to start a new trajectory
- Include `previous_message_id` to continue an existing trajectory
- Only pass new messages — do not re-send messages from prior turns
- System prompt goes only in the first request of each trajectory

#### Agentic Multi-Turn Sampling with Tool Use

For tasks where the model interacts with an environment via tools (code execution, API calls, database queries, etc.), sample a full trajectory by looping until the model stops calling tools:

```python
def sample_agentic_trajectory(
    client,
    trainer_id,
    snapshot_id,
    task_prompt,
    tools,
    execute_tool_fn,
    system_prompt=None,
    max_turns=50,
    max_tokens=1024,
):
    """Sample a multi-turn tool-use trajectory.

    Args:
        execute_tool_fn: callable(name, input_data) -> str
            Your function that executes a tool call and returns the result.
    Returns:
        (trajectory_id, stop_reason)
    """
    # First turn: send the task prompt, system prompt, and tools
    request = {
        "snapshot_id": snapshot_id,
        "messages": [{"role": "user", "content": task_prompt}],
        "max_tokens": max_tokens,
        "tools": tools,
    }
    if system_prompt:
        request["system"] = system_prompt

    response = client.post(
        url=f"/v1/finetuning/trainers/{trainer_id}/rlsample",
        json=request,
    ).json()

    trajectory_id = response["trajectory_id"]
    previous_message_id = response["id"]

    for _turn in range(max_turns):
        # Check if the model made any tool calls
        tool_calls = [
            block for block in response.get("content", [])
            if block.get("type") == "tool_use"
        ]

        if not tool_calls:
            # Model finished without calling tools — trajectory complete
            return trajectory_id, response.get("stop_reason", "end_turn")

        # Execute each tool call in the environment
        tool_results = []
        for tc in tool_calls:
            try:
                result_text = execute_tool_fn(tc["name"], tc.get("input", {}))
            except Exception as e:
                result_text = f"Error: {e}"
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": tc["id"],
                "content": result_text,
            })

        # Continue the trajectory with tool results
        response = client.post(
            url=f"/v1/finetuning/trainers/{trainer_id}/rlsample",
            json={
                "snapshot_id": snapshot_id,
                "previous_message_id": previous_message_id,
                "messages": [{"role": "user", "content": tool_results}],
                "max_tokens": max_tokens,
            },
        ).json()

        previous_message_id = response["id"]

    return trajectory_id, "max_turns"
```

Use it in a training loop:

```python
# Define your tools
tools = [
    {
        "name": "calculator",
        "description": "Evaluate a math expression.",
        "input_schema": {
            "type": "object",
            "properties": {"expression": {"type": "string"}},
            "required": ["expression"],
        },
    }
]

def execute_tool(name, input_data):
    if name == "calculator":
        # Use your own safe math parser here
        import ast
        result = ast.literal_eval(input_data["expression"])
        return str(result)
    return f"Unknown tool: {name}"

# Sample trajectories
trajectories = []
for prompt in prompts:
    try:
        traj_id, stop_reason = sample_agentic_trajectory(
            client, trainer_id, snapshot_id,
            task_prompt=prompt,
            tools=tools,
            execute_tool_fn=execute_tool,
            system_prompt="You are a helpful assistant. Use tools when needed.",
        )
        trajectories.append(traj_id)
    except Exception as e:
        print(f"Trajectory failed: {e}")
        continue
```

**Key points for agentic sampling:**
- The model decides when to call tools and when to stop — the loop continues until `content` has no `tool_use` blocks
- Wrap each trajectory in try/except so one failure doesn't crash the entire step
- Tool results are sent as a list of `tool_result` blocks in the user message `content` field
- The `previous_message_id` chains turns server-side, so only send new messages each turn

#### Refusal Handling

If the model refuses during sampling, the response returns `stop_reason: "refusal"`. These trajectories are automatically filtered during training. Check `training_info.filtered_indices` in the `forward_backward` response.

```python
response = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/rlsample",
    json={
        "snapshot_id": snapshot_id,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 100,
    },
).json()

if response.get("stop_reason") == "refusal":
    print("Model refused -- trajectory will be filtered during training")
```

#### Calculate Rewards

```python
def calculate_reward(responses):
    """
    Your custom reward function.
    Returns a float: positive = reinforce, negative = discourage
    """
    if is_correct(responses):
        return 1.0
    elif is_partially_correct(responses):
        return 0.5
    else:
        return -0.5
```

#### Train on Collected Data

```python
# Phase 1: Compute gradients
fwd_bwd_response = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/forward_backward",
    json={
        "step": current_step,
        "batch": [
            {
                "messages": response2["trajectory_id"],
                "weight": {
                    "application": "trajectory",
                    "trajectory_weight": reward,
                },
            }
        ],
    },
).json()

print(f"Loss: {fwd_bwd_response['loss']}")

# Phase 2: Apply gradients and advance the step
apply_response = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/apply_grads",
    json={"step": current_step, "lr_factor": 1.0},
).json()

current_step = apply_response["next_step"]
```

#### Gradient Accumulation

Call `forward_backward` multiple times at the same step before `apply_grads` to train on larger effective batch sizes:

```python
for batch in trajectory_batches:
    fwd_bwd_response = client.post(
        url=f"/v1/finetuning/trainers/{trainer_id}/forward_backward",
        json={"step": current_step, "batch": batch},
    ).json()
    print(f"Batch loss: {fwd_bwd_response['loss']}")

# Apply all accumulated gradients at once
apply_response = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/apply_grads",
    json={"step": current_step, "lr_factor": 1.0},
).json()

current_step = apply_response["next_step"]
```

### Step 3: Snapshot and Use Your Model

```python
snapshot = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/snapshots",
).json()

print(f"Created snapshot: {snapshot['id']}")
```

Snapshots expire after 7 days. Promote to make persistent:

```python
promoted_snapshot = client.post(
    url=f"/v1/finetuning/snapshots/{snapshot['id']}/promote"
).json()

assert promoted_snapshot["expires_at"] is None

# Use with Messages API
response = client.post(
    url="/v1/messages",
    json={
        "model": f"claude-haiku-4-5-20251001-{snapshot['id']}",
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": "Your prompt"}],
    },
).json()
print(response["content"][0]["text"])
```

---

## Supervised Learning Workflow

SFT uses a flat conversation format — the same `messages` array from `/v1/messages`. Provide conversations directly in `forward_backward` without calling `/rlsample`.

**Important**: Only assistant completions receive the training weight. User messages, system prompts, and tool results provide context but do not contribute to training loss. Tool-use blocks within assistant messages are trained on.

### Step 1: Create a Trainer

```python
trainer = client.post(
    url="/v1/finetuning/trainers",
    json={"model_name": "claude-haiku-4-5-20251001"},
).json()

trainer_id = trainer["id"]
current_step = 0
```

### Step 2: Train with Examples

```python
fwd_bwd_response = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/forward_backward",
    json={
        "step": current_step,
        "batch": [
            {
                "messages": [
                    {"role": "user", "content": "What is 2 + 2?"},
                    {"role": "assistant", "content": "4"},
                ],
            },
            {
                "system": "You are a concise assistant.",
                "messages": [
                    {"role": "user", "content": "Capital of France?"},
                    {"role": "assistant", "content": "Paris"},
                    {"role": "user", "content": "And Germany?"},
                    {"role": "assistant", "content": "Berlin"},
                ],
                "weight": {
                    "application": "trajectory",
                    "trajectory_weight": 1.5,
                },
            },
        ],
    },
).json()

print(f"Loss: {fwd_bwd_response['loss']}")

# Apply gradients
apply_response = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/apply_grads",
    json={"step": current_step, "lr_factor": 1.0},
).json()

current_step = apply_response["next_step"]
```

### SFT with Tool Use

Define tools at the trajectory level and include `tool_use` / `tool_result` content blocks:

```python
fwd_bwd_response = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/forward_backward",
    json={
        "step": current_step,
        "batch": [
            {
                "tools": [
                    {
                        "name": "get_weather",
                        "description": "Get the current weather for a location.",
                        "input_schema": {
                            "type": "object",
                            "properties": {
                                "location": {"type": "string"}
                            },
                            "required": ["location"],
                        },
                    }
                ],
                "messages": [
                    {"role": "user", "content": "What's the weather in London?"},
                    {
                        "role": "assistant",
                        "content": [
                            {
                                "type": "tool_use",
                                "id": "call_001",
                                "name": "get_weather",
                                "input": {"location": "London"},
                            }
                        ],
                    },
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "tool_result",
                                "tool_use_id": "call_001",
                                "content": "Partly cloudy, 15C",
                            }
                        ],
                    },
                    {
                        "role": "assistant",
                        "content": "It's currently partly cloudy and 15C in London.",
                    },
                ],
            }
        ],
    },
).json()

apply_response = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/apply_grads",
    json={"step": current_step, "lr_factor": 1.0},
).json()

current_step = apply_response["next_step"]
```

### Key Differences from RL Trajectories

- `messages` is a flat conversation array (same as `/v1/messages`), not a trajectory ID
- `system` is an optional top-level field on each trajectory (string or array of content blocks)
- `tools` is an optional top-level field for tool definitions
- `max_tokens` is not needed (the model is not generating completions)
- Per-turn weights are not supported — only trajectory-level weights
- All trajectories in a batch must be the same type (all SFT or all RL)

---

## Advanced Features

### Multi-turn Trajectory with Per-Turn Weights (RL Only)

```python
# Create a two-turn trajectory
response1 = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/rlsample",
    json={
        "snapshot_id": snapshot_id,
        "messages": [{"role": "user", "content": "Step 1"}],
        "max_tokens": 100,
        "system": SYSTEM_PROMPT,
    },
).json()

# Continue — do NOT pass system prompt on later turns
response2 = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/rlsample",
    json={
        "snapshot_id": snapshot_id,
        "previous_message_id": response1["id"],
        "messages": [{"role": "user", "content": "Step 2"}],
        "max_tokens": 100,
    },
).json()

# Train with different weights per turn
fwd_bwd_response = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/forward_backward",
    json={
        "step": current_step,
        "batch": [{
            "messages": response2["trajectory_id"],
            "weight": {
                "application": "per_turn",
                "per_turn_weight": [
                    {"message_id": response1["id"], "weight": 0.5},
                    {"message_id": response2["id"], "weight": 1.5},
                ],
            },
        }],
    },
).json()

apply_response = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/apply_grads",
    json={"step": current_step, "lr_factor": 1.0},
).json()

current_step = apply_response["next_step"]
```

### Saving and Resuming from a Checkpoint

Checkpoints (`ft_ckpt_...`) save full trainer state (weights + optimizer). Snapshots (`ft_snap_...`) are for inference only and cannot be used to resume training.

```python
# Save a checkpoint (requires at least one forward_backward call)
checkpoint = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/checkpoints",
).json()
checkpoint_id = checkpoint["id"]  # e.g., ft_ckpt_abc123
# IMPORTANT: Save this ID! There are no list/get endpoints for checkpoints.

# Also save a snapshot for inference evaluation
snapshot = client.post(
    url=f"/v1/finetuning/trainers/{trainer_id}/snapshots",
).json()

# Later, resume training from the checkpoint
new_trainer = client.post(
    url="/v1/finetuning/trainers",
    json={
        "model_name": "claude-haiku-4-5-20251001",
        "initial_checkpoint_id": checkpoint_id,  # ft_ckpt_..., NOT ft_snap_...
    },
).json()
# New trainer starts at step 0 with previous weights and optimizer state
```

### Batch Validation Rules

- At least 1 trajectory must be included
- No mixing trajectory types: all RL (trajectory ID strings) or all SFT (inline messages)
- No duplicate RL trajectory IDs in a single batch
- RL: `step` must match the trainer's current step (409 on mismatch)
- RL: `tool_choice` must be `auto` if specified. Explicit `cache_control` markers are not allowed.
- SFT: per-turn weights are not supported
- Distillation: either all or no RL trajectories must set `ref_logprob_id`. `distillation_weight > 0` requires it on every trajectory.
