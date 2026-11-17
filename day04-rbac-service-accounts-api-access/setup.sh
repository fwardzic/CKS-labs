#!/usr/bin/env bash
# Run on the Mac. Day 4: RBAC, ServiceAccounts, API access, users via CSR.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

remote "$CP" <<'EOF'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /root/day4

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: finance}
---
apiVersion: v1
kind: Namespace
metadata: {name: dev}
---
apiVersion: v1
kind: ServiceAccount
metadata: {name: report-bot, namespace: finance}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: report-bot-admin}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cluster-admin}
subjects:
- {kind: ServiceAccount, name: report-bot, namespace: finance}
---
apiVersion: v1
kind: ServiceAccount
metadata: {name: old-ci, namespace: finance}
---
apiVersion: v1
kind: Secret
metadata:
  name: old-ci-token
  namespace: finance
  annotations:
    kubernetes.io/service-account.name: old-ci
type: kubernetes.io/service-account-token
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: legacy, namespace: finance}
spec:
  replicas: 1
  selector: {matchLabels: {app: legacy}}
  template:
    metadata: {labels: {app: legacy}}
    spec:
      containers:
      - name: app
        image: nginx:1.27-alpine
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: dev}
spec:
  replicas: 1
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers:
      - name: app
        image: nginx:1.27-alpine
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: anon-view}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: view}
subjects:
- {apiGroup: rbac.authorization.k8s.io, kind: User, name: system:anonymous}
YAML

# NodeRestriction "accidentally" replaced
sed -i 's#--enable-admission-plugins=NodeRestriction#--enable-admission-plugins=PodNodeSelector#' \
  /etc/kubernetes/manifests/kube-apiserver.yaml
grep -q -- '--enable-admission-plugins=PodNodeSelector' /etc/kubernetes/manifests/kube-apiserver.yaml
EOF
echo "[cp] waiting for kube-apiserver restart"
sleep 20
wait_for "$K get --raw /readyz" 80
wait_for "$K -n finance rollout status deploy legacy --timeout=5s" 40
echo "Setup done. Read README.md and start. Grade with ./check.sh"
