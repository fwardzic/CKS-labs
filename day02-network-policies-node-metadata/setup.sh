#!/usr/bin/env bash
# Run on the Mac. Day 2: NetworkPolicy and CiliumNetworkPolicy workloads.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

remote "$CP" <<'EOF'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: team-web}
---
apiVersion: v1
kind: Namespace
metadata: {name: team-api}
---
apiVersion: v1
kind: Namespace
metadata: {name: team-db}
---
apiVersion: v1
kind: Namespace
metadata: {name: other}
YAML

pod() { # ns name app
  kubectl -n "$1" run "$2" --image=nginx:1.27-alpine --labels "app=$3" --port 80
}
pod team-web web web
pod team-web intruder intruder
pod team-api api api
pod team-db db db
pod other tester web          # same label as the real frontend, wrong namespace
kubectl -n team-api expose pod api --port 80
kubectl -n team-db expose pod db --port 80
kubectl wait --for=condition=Ready pod --all -n team-web --timeout=180s
kubectl wait --for=condition=Ready pod --all -n team-api --timeout=180s
kubectl wait --for=condition=Ready pod --all -n team-db --timeout=180s
kubectl wait --for=condition=Ready pod --all -n other --timeout=180s
EOF
echo "Setup done. Read README.md and start. Grade with ./check.sh"
