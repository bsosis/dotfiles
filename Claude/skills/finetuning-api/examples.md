# Finetuning API — Complete Examples

All examples use the same HTTP client setup:

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

## Complete RL Example (GRPO on Multiplication)

```python
import os
import random
import re

import httpx

# Configuration
TRAIN_STEPS = 10
PROMPTS_PER_BATCH = 24
SAMPLES_PER_PROMPT = 4
MAX_TOKENS = 150
MODEL_NAME = "claude-haiku-4-5-20251001"

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

SYSTEM_PROMPT = """You are a calculator. When given a multiplication problem, compute the exact answer.
Think step by step, then provide your final answer in the format: ANSWER: <number>"""


def generate_multiplication_problem() -> tuple[str, int]:
    """Generate a multiplication problem and its answer."""
    a = random.randint(100, 999)
    b = random.randint(100, 999)
    return f"What is {a} x {b}?", a * b


def extract_answer(response_text: str) -> int | None:
    """Extract the numerical answer from model response."""
    match = re.search(r"ANSWER:\s*([0-9,]+)", response_text)
    if match:
        return int(match.group(1).replace(",", ""))
    return None


def calculate_reward(response_text: str, expected: int) -> float:
    """Calculate reward based on correctness."""
    predicted = extract_answer(response_text)
    if predicted is None:
        return 0.0
    if predicted == expected:
        return 1.0
    if abs(predicted - expected) / expected < 0.01:
        return 0.5
    return 0.0


def compute_grpo_advantages(rewards: list[float]) -> list[float]:
    """
    Compute GRPO advantages for a group of samples.
    Advantage = reward - mean(rewards)
    """
    mean_reward = sum(rewards) / len(rewards)
    return [r - mean_reward for r in rewards]


def main():
    # Create trainer
    trainer = client.post(
        url="/v1/finetuning/trainers",
        json={"model_name": MODEL_NAME},
    ).json()

    trainer_id = trainer["id"]
    current_step = trainer["step"]

    print(f"Created trainer: {trainer_id}")
    print(f"Starting from step: {current_step}")
    print(f"Training on multiplication with GRPO\n")

    for train_step in range(TRAIN_STEPS):
        all_trajectories = []
        train_step_rewards = []

        prompts = [generate_multiplication_problem() for _ in range(PROMPTS_PER_BATCH)]

        # Collect samples with GRPO
        for prompt_text, expected_answer in prompts:
            prompt_trajectories = []
            prompt_rewards = []

            for _ in range(SAMPLES_PER_PROMPT):
                response = client.post(
                    url=f"/v1/finetuning/trainers/{trainer_id}/rlsample",
                    json={
                        "step": current_step,
                        "system": SYSTEM_PROMPT,
                        "messages": [{"role": "user", "content": prompt_text}],
                        "max_tokens": MAX_TOKENS,
                    },
                ).json()

                response_text = response["content"][0]["text"]
                reward = calculate_reward(response_text, expected_answer)

                prompt_trajectories.append(response["trajectory_id"])
                prompt_rewards.append(reward)

            advantages = compute_grpo_advantages(prompt_rewards)

            for traj_id, advantage in zip(prompt_trajectories, advantages, strict=True):
                all_trajectories.append(
                    {
                        "messages": traj_id,
                        "weight": {
                            "application": "trajectory",
                            "trajectory_weight": advantage,
                        },
                    }
                )

            train_step_rewards.extend(prompt_rewards)

        # Remove zero-weight trajectories
        training_trajectories = [
            traj
            for traj in all_trajectories
            if traj["weight"]["trajectory_weight"] != 0.0
        ]

        if not training_trajectories:
            print(f"Warning: No trajectories with non-zero weight in step {train_step + 1}, skipping")
            continue

        print(f"Collected {len(training_trajectories)} trajectories for train step {train_step + 1}")
        print(f"Average reward: {sum(train_step_rewards) / len(train_step_rewards):.3f}")

        # Scale learning rate to compensate for filtered batch size
        lr_factor = (
            len(training_trajectories) / len(all_trajectories)
            if all_trajectories
            else 1.0
        )

        # Compute gradients
        fwd_bwd_response = client.post(
            url=f"/v1/finetuning/trainers/{trainer_id}/forward_backward",
            json={"step": current_step, "batch": training_trajectories},
        ).json()

        # Apply gradients
        apply_response = client.post(
            url=f"/v1/finetuning/trainers/{trainer_id}/apply_grads",
            json={"step": current_step, "lr_factor": lr_factor},
        ).json()

        current_step = apply_response["next_step"]
        avg_reward = sum(train_step_rewards) / len(train_step_rewards)
        accuracy = sum(1 for r in train_step_rewards if r == 1.0) / len(train_step_rewards)

        print(f"Train Step {train_step + 1}/{TRAIN_STEPS}")
        print(f"  Loss: {fwd_bwd_response['loss']:.4f}")
        print(f"  Avg Reward: {avg_reward:.3f}")
        print(f"  Accuracy: {accuracy:.1%}")
        print(f"  Step: {current_step}\n")

        # Snapshot every 10 steps
        if (train_step + 1) % 10 == 0:
            snapshot = client.post(
                url=f"/v1/finetuning/trainers/{trainer_id}/snapshots",
                json={"trainer_id": trainer_id},
            ).json()
            print(f"  Created snapshot: {snapshot['id']}\n")

    # Create and promote final snapshot
    final_snapshot = client.post(
        url=f"/v1/finetuning/trainers/{trainer_id}/snapshots",
        json={"trainer_id": trainer_id},
    ).json()

    promoted = client.post(
        url=f"/v1/finetuning/snapshots/{final_snapshot['id']}/promote"
    ).json()

    print(f"Training complete!")
    print(f"Final snapshot: {promoted['id']}")
    print(f"Use with model: {MODEL_NAME}-{promoted['id']}")

    # Evaluate
    print("\n--- Evaluation ---")
    eval_correct = 0
    eval_total = 10

    for _ in range(eval_total):
        prompt_text, expected = generate_multiplication_problem()
        response = client.post(
            url="/v1/messages",
            json={
                "model": f"{MODEL_NAME}-{promoted['id']}",
                "max_tokens": MAX_TOKENS,
                "system": SYSTEM_PROMPT,
                "messages": [{"role": "user", "content": prompt_text}],
            },
        ).json()

        response_text = response["content"][0]["text"]
        predicted = extract_answer(response_text)

        if predicted == expected:
            eval_correct += 1

        print(f"  {prompt_text} = {expected} (predicted: {predicted})")

    print(f"\nEval Accuracy: {eval_correct}/{eval_total} ({eval_correct / eval_total:.1%})")


if __name__ == "__main__":
    main()
```

---

## Complete Distillation Example

```python
import os

import httpx

# Configuration
TRAIN_STEPS = 10
PROMPTS_PER_STEP = 16
MAX_TOKENS = 2048
MODEL_NAME = "claude-haiku-4-5-20251001"
TEACHER_MODEL = "claude-opus-4-6"

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

SYSTEM_PROMPT = "You are a helpful, accurate, and concise assistant."

PROMPTS = [
    "Explain how a transformer attention mechanism works.",
    "Write a Python function to find the longest common subsequence.",
    "What are the tradeoffs between SQL and NoSQL databases?",
    "Describe the CAP theorem and its implications for distributed systems.",
    "Explain the difference between supervised and unsupervised learning.",
    "Write a clear explanation of how public key cryptography works.",
    "What is the halting problem and why is it important?",
    "Explain how garbage collection works in modern programming languages.",
    # ... add more prompts
]


def main():
    trainer = client.post(
        url="/v1/finetuning/trainers",
        json={"model_name": MODEL_NAME},
    ).json()

    trainer_id = trainer["id"]
    current_step = trainer["step"]

    print(f"Created trainer: {trainer_id}")
    print(f"Distilling {TEACHER_MODEL} into {MODEL_NAME}\n")

    for train_step in range(TRAIN_STEPS):
        step_prompts = [
            PROMPTS[i % len(PROMPTS)]
            for i in range(
                train_step * PROMPTS_PER_STEP,
                (train_step + 1) * PROMPTS_PER_STEP,
            )
        ]

        # Sample from the student
        trajectory_ids = []
        for prompt in step_prompts:
            response = client.post(
                url=f"/v1/finetuning/trainers/{trainer_id}/rlsample",
                json={
                    "step": current_step,
                    "system": SYSTEM_PROMPT,
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": MAX_TOKENS,
                },
            ).json()

            if response.get("stop_reason") == "refusal":
                continue
            trajectory_ids.append(response["trajectory_id"])

        if not trajectory_ids:
            print(f"Step {train_step + 1}: No valid trajectories, skipping")
            continue

        # Precompute teacher logprobs
        fwd_resp = client.post(
            url=f"/v1/finetuning/trainers/{trainer_id}/forward",
            json={
                "model": TEACHER_MODEL,
                "trajectory_ids": trajectory_ids,
            },
        ).json()

        logprob_by_traj = {
            r["trajectory_id"]: r["logprob_id"]
            for r in fwd_resp["results"]
        }

        # Build batch with ref_logprob_id
        batch = [
            {
                "messages": tid,
                "weight": {"application": "trajectory", "trajectory_weight": 1.0},
                "ref_logprob_id": logprob_by_traj[tid],
            }
            for tid in trajectory_ids
            if tid in logprob_by_traj
        ]

        # Compute gradients with distillation loss
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

        # Apply gradients
        apply_response = client.post(
            url=f"/v1/finetuning/trainers/{trainer_id}/apply_grads",
            json={"step": current_step, "lr_factor": 1.0},
        ).json()

        current_step = apply_response["next_step"]

        print(f"Step {train_step + 1}/{TRAIN_STEPS}")
        print(f"  Loss: {fwd_bwd_response['loss']:.4f}")
        print(f"  Trajectories: {fwd_bwd_response['training_info']['valid_trajectories']}")
        print(f"  Next step: {current_step}\n")

        if (train_step + 1) % 5 == 0:
            snapshot = client.post(
                url=f"/v1/finetuning/trainers/{trainer_id}/snapshots",
                json={"trainer_id": trainer_id},
            ).json()
            print(f"  Snapshot: {snapshot['id']}\n")

    # Promote final snapshot
    final_snapshot = client.post(
        url=f"/v1/finetuning/trainers/{trainer_id}/snapshots",
        json={"trainer_id": trainer_id},
    ).json()

    promoted = client.post(
        url=f"/v1/finetuning/snapshots/{final_snapshot['id']}/promote"
    ).json()

    print(f"Training complete!")
    print(f"Final snapshot: {promoted['id']}")
    print(f"Use with model: {MODEL_NAME}-{promoted['id']}")


if __name__ == "__main__":
    main()
```

---

## Complete SFT Example

```python
import os

import httpx

# Configuration
MODEL_NAME = "claude-haiku-4-5-20251001"
BATCH_SIZE = 8
EPOCHS = 3

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

TRAINING_DATA = [
    {
        "system": "You are a customer support agent for Acme Corp.",
        "messages": [
            {"role": "user", "content": "How do I reset my password?"},
            {
                "role": "assistant",
                "content": "To reset your password:\n1. Go to acme.com/reset\n2. Enter your email address\n3. Click the reset link in your email\n4. Choose a new password\n\nNeed further help? I'm here!",
            },
        ],
    },
    {
        "system": "You are a customer support agent for Acme Corp.",
        "messages": [
            {"role": "user", "content": "I want a refund for order #12345"},
            {
                "role": "assistant",
                "content": "I'd be happy to help with your refund for order #12345. Let me look that up.\n\nI can see your order was placed 3 days ago. Since it's within our 30-day refund window, I've initiated the refund. You'll see the credit on your statement within 5-7 business days.\n\nIs there anything else I can help with?",
            },
            {"role": "user", "content": "Can I get it faster?"},
            {
                "role": "assistant",
                "content": "Unfortunately, the 5-7 business day timeline is set by your bank's processing time -- it's outside our control once we initiate the refund. However, I've flagged your refund as priority on our end to make sure there are no delays from our side.",
            },
        ],
    },
    # ... add more training examples
]


def main():
    trainer = client.post(
        url="/v1/finetuning/trainers",
        json={"model_name": MODEL_NAME},
    ).json()

    trainer_id = trainer["id"]
    current_step = trainer["step"]

    print(f"Created trainer: {trainer_id}")
    print(f"Training on {len(TRAINING_DATA)} examples, {EPOCHS} epochs\n")

    for epoch in range(EPOCHS):
        for batch_start in range(0, len(TRAINING_DATA), BATCH_SIZE):
            batch_data = TRAINING_DATA[batch_start : batch_start + BATCH_SIZE]

            batch = []
            for example in batch_data:
                trajectory = {"messages": example["messages"]}
                if "system" in example:
                    trajectory["system"] = example["system"]
                batch.append(trajectory)

            fwd_bwd_response = client.post(
                url=f"/v1/finetuning/trainers/{trainer_id}/forward_backward",
                json={"step": current_step, "batch": batch},
            ).json()

            apply_response = client.post(
                url=f"/v1/finetuning/trainers/{trainer_id}/apply_grads",
                json={"step": current_step, "lr_factor": 1.0},
            ).json()

            current_step = apply_response["next_step"]

            print(
                f"Epoch {epoch + 1}/{EPOCHS}, "
                f"Batch {batch_start // BATCH_SIZE + 1}, "
                f"Loss: {fwd_bwd_response['loss']:.4f}"
            )

        snapshot = client.post(
            url=f"/v1/finetuning/trainers/{trainer_id}/snapshots",
            json={"trainer_id": trainer_id},
        ).json()
        print(f"  Epoch {epoch + 1} snapshot: {snapshot['id']}\n")

    promoted = client.post(
        url=f"/v1/finetuning/snapshots/{snapshot['id']}/promote"
    ).json()

    print(f"Training complete!")
    print(f"Final snapshot: {promoted['id']}")
    print(f"Use with model: {MODEL_NAME}-{promoted['id']}")

    # Test
    print("\n--- Test ---")
    response = client.post(
        url="/v1/messages",
        json={
            "model": f"{MODEL_NAME}-{promoted['id']}",
            "max_tokens": 256,
            "system": "You are a customer support agent for Acme Corp.",
            "messages": [
                {"role": "user", "content": "What's your return policy?"}
            ],
        },
    ).json()
    print(response["content"][0]["text"])


if __name__ == "__main__":
    main()
```
