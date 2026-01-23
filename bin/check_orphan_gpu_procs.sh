#!/bin/bash
# Check for orphaned GPU processes belonging to current user across all nodes
# Usage: ./scripts/check_orphan_gpu_procs.sh [--kill]

set -e

USER_TO_CHECK="${USER:?USER environment variable must be set}"
KILL_MODE=false

if [[ "$1" == "--kill" ]]; then
    KILL_MODE=true
    echo "⚠️  KILL MODE: Will kill orphaned processes"
fi

echo "Checking for orphaned GPU processes for user: $USER_TO_CHECK"
echo "============================================================"

# Get list of nodes (adjust range as needed)
NODES="node-0 node-1 node-3 node-4 node-5 node-6 node-7 node-8 node-9 node-10 node-11 node-12 node-13 node-14 node-15 node-16 node-17 node-18 node-19 node-20 node-21 node-22"

found_orphans=false

for node in $NODES; do
    # Try to check the node (skip if unavailable)
    result=$(srun -p general,overflow --nodelist=$node --time=00:01:00 --mem=1G \
        bash -c "nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv 2>/dev/null | grep -i $USER_TO_CHECK || true" 2>/dev/null) || continue

    if [[ -n "$result" ]]; then
        found_orphans=true
        echo ""
        echo "🔴 Found on $node:"
        echo "$result"

        if [[ "$KILL_MODE" == true ]]; then
            # Extract PIDs and kill them
            pids=$(echo "$result" | grep -v "^pid" | cut -d',' -f1 | tr -d ' ')
            for pid in $pids; do
                echo "   Killing PID $pid..."
                srun -p general,overflow --nodelist=$node --time=00:01:00 --mem=1G \
                    bash -c "kill -9 $pid 2>/dev/null && echo '   ✓ Killed' || echo '   ✗ Already dead'" 2>/dev/null || true
            done
        fi
    fi
done

echo ""
if [[ "$found_orphans" == false ]]; then
    echo "✅ No orphaned GPU processes found for $USER_TO_CHECK"
else
    if [[ "$KILL_MODE" == false ]]; then
        echo ""
        echo "To kill these processes, run:"
        echo "  ./scripts/check_orphan_gpu_procs.sh --kill"
    fi
fi