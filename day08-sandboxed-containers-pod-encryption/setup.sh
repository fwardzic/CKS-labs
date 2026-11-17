#!/usr/bin/env bash
# Run on the Mac. Day 8: sandboxed runtime (gVisor), Cilium WireGuard, Istio mTLS.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

echo "[cp] Istio (minimal profile) + workloads, ~2 min"
remote "$CP" <<'EOF'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
istioctl install --set profile=minimal -y >/dev/null
kubectl -n istio-system rollout status deploy istiod --timeout=300s
kubectl create ns isolated
kubectl create ns mesh
kubectl create ns outside
kubectl -n mesh create deployment web --image=nginx:1.27-alpine --port 80
kubectl -n mesh expose deploy web --port 80
kubectl -n mesh create deployment client --image=nginx:1.27-alpine
kubectl -n outside create deployment client --image=nginx:1.27-alpine
for ns in mesh outside; do kubectl -n $ns rollout status deploy --timeout=180s; done
EOF
echo "Setup done. Read README.md and start. Grade with ./check.sh"
