#!/usr/bin/env bash
# Run on the Mac. Restores both nodes to the "clean" snapshot.
set -euo pipefail
NODES=(cks-cp cks-worker)
multipass stop "${NODES[@]}"
for n in "${NODES[@]}"; do
  multipass restore "$n.clean" --destructive
done
multipass start "${NODES[@]}"
