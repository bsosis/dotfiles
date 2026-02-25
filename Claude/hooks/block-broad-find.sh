#!/bin/bash
# PreToolUse hook: block find commands targeting overly broad directories.
# Receives tool call JSON on stdin.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

BLOCKED=(
    "/workspace-vast"
    "/workspace-vast/bsosis"
    "/workspace-vast/bsosis/git"
)

for dir in "${BLOCKED[@]}"; do
    if echo "$COMMAND" | grep -qP "\bfind\s+\Q${dir}\E/?(\s|$)"; then
        echo "BLOCKED: 'find' in '$dir' is too broad and will be very slow." >&2
        echo "Please target a specific subdirectory (e.g., the current project repo)." >&2
        exit 2
    fi
done

exit 0
