#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract values from JSON
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')
output_style=$(echo "$input" | jq -r '.output_style.name')
version=$(echo "$input" | jq -r '.version')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')

# Get git branch if in a repo (skip optional locks for cluster stability)
git_info=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null || echo "detached")
    # Get git status
    if [[ -n $(git -C "$cwd" --no-optional-locks status -s 2>/dev/null) ]]; then
        git_status="*"
    else
        git_status=""
    fi
    git_info=" $(printf '\033[36m')git:$(printf '\033[33m')$branch$git_status$(printf '\033[0m')"
fi

# Format context usage with color coding
context_info=""
if [ -n "$used_pct" ]; then
    # Color code based on usage
    if (( $(echo "$used_pct > 80" | bc -l 2>/dev/null || echo 0) )); then
        color="\033[31m" # Red for >80%
    elif (( $(echo "$used_pct > 60" | bc -l 2>/dev/null || echo 0) )); then
        color="\033[33m" # Yellow for >60%
    else
        color="\033[32m" # Green otherwise
    fi
    context_info=" $(printf "${color}")ctx:${used_pct}%$(printf '\033[0m')"
fi

# Token counts
tokens_info=""
if [ -n "$total_input" ] && [ "$total_input" != "null" ]; then
    tokens_info=" $(printf '\033[90m')in:${total_input} out:${total_output}$(printf '\033[0m')"
fi

# Vim mode indicator
vim_info=""
if [ -n "$vim_mode" ]; then
    if [ "$vim_mode" = "NORMAL" ]; then
        vim_info=" $(printf '\033[34m')[N]$(printf '\033[0m')"
    else
        vim_info=" $(printf '\033[32m')[I]$(printf '\033[0m')"
    fi
fi

# Get hostname for cluster identification
hostname=$(hostname -s)

# Build status line
printf '\033[35m'
printf "%s" "$hostname"
printf '\033[0m:'
printf '\033[32m'
printf "%s" "$cwd"
printf '\033[0m'
printf "%s" "$git_info"
printf ' | '
printf '\033[36m'
printf "%s" "$model"
printf '\033[0m'
if [ "$output_style" != "null" ] && [ -n "$output_style" ]; then
    printf ' ('
    printf '\033[33m'
    printf "%s" "$output_style"
    printf '\033[0m)'
fi
printf "%s" "$context_info"
printf "%s" "$tokens_info"
printf "%s" "$vim_info"
printf ' | '
printf '\033[90m'
printf "v%s" "$version"
printf '\033[0m'

