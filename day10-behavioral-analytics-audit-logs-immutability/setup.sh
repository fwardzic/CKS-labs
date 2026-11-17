#!/usr/bin/env bash
# Run on the Mac. Day 10: Falco, audit logs, immutable containers.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

remote "$WORKER" <<'EOF'
mkdir -p /root/day10
EOF

remote "$CP" <<'EOF'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl create ns ops
kubectl -n ops create deployment collector --image=busybox:1.37 --replicas 2 -- \
  sh -c 'while true; do cat /etc/shadow >/dev/null; sleep 10; done'
kubectl -n ops create deployment updater --image=alpine:3.22 -- \
  sh -c 'while true; do apk info >/dev/null; sleep 10; done'
kubectl -n ops create deployment idle --image=busybox:1.37 -- sleep 1d
kubectl -n ops create deployment frontend --image=nginx:1.29-alpine --port 80
kubectl -n ops expose deploy frontend --port 80
kubectl -n ops create configmap app-config --from-literal=mode=prod
kubectl -n ops create secret generic app-secret --from-literal=token=abc123
kubectl -n ops rollout status deploy --timeout=180s
EOF
echo "Setup done. Read README.md and start. Grade with ./check.sh"
