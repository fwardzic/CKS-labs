#!/usr/bin/env bash
# Run on the Mac. Day 7: Pod Security Admission, Secrets, encryption at rest.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

remote "$CP" <<'EOF'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /root/day7
kubectl create ns payments
kubectl create ns legacy
kubectl -n legacy create secret generic admin-creds --from-literal=username=admin --from-literal=password='Tr0ub4dor&3'
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: {name: pay, namespace: payments}
spec:
  replicas: 2
  selector: {matchLabels: {app: pay}}
  template:
    metadata: {labels: {app: pay}}
    spec:
      containers:
      - name: app
        image: nginxinc/nginx-unprivileged:1.27-alpine
        ports: [{containerPort: 8080}]
        env:
        - {name: DB_PASSWORD, value: "S3cr3t!"}
YAML
kubectl -n payments rollout status deploy pay --timeout=180s
EOF
echo "Setup done. Read README.md and start. Grade with ./check.sh"
