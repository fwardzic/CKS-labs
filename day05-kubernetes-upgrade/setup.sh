#!/usr/bin/env bash
# Run on the Mac. Day 5: kubeadm upgrade 1.35 -> 1.36 (start from a clean cluster).
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

remote "$CP" <<'EOF'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl create ns prod
kubectl -n prod create deployment shop --image=nginx:1.27-alpine --replicas 3
kubectl -n prod rollout status deploy shop --timeout=180s
EOF
echo "Setup done. Read README.md and start. Grade with ./check.sh"
