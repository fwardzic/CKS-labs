#!/usr/bin/env bash
# Run on the Mac. Day 12: container forensics, audit log investigation, host hardening.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

echo "[worker] host state"
remote "$WORKER" <<'EOF'
set -euo pipefail
mkdir -p /root/day12
modprobe tipc
cat > /etc/ssh/sshd_config.d/10-legacy.conf <<'S'
# temporary access for the migration, remove later
PermitRootLogin yes
PasswordAuthentication yes
S
systemctl restart ssh
getent passwd svc-backup || useradd -o -u 0 -g 0 -M -d /var/backups -s /bin/bash -c "backup service" svc-backup
EOF

echo "[cp] audit logging"
remote "$CP" <<'EOF'
set -euo pipefail
mkdir -p /root/day12 /etc/kubernetes/audit /var/log/kubernetes/audit
cat > /etc/kubernetes/audit/policy.yaml <<'P'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
- RequestReceived
rules:
- level: None
  users: ["system:kube-proxy", "system:kube-scheduler", "system:kube-controller-manager"]
- level: None
  nonResourceURLs: ["/healthz*", "/livez*", "/readyz*", "/version"]
- level: RequestResponse
  resources:
  - group: rbac.authorization.k8s.io
  - group: ""
    resources: ["serviceaccounts"]
- level: Metadata
P
python3 - <<'PY'
p = "/etc/kubernetes/manifests/kube-apiserver.yaml"
s = open(p).read()
flags = ("    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml\n"
         "    - --audit-log-path=/var/log/kubernetes/audit/audit.log\n"
         "    - --audit-log-maxsize=50\n"
         "    - --audit-log-maxbackup=2\n")
s = s.replace("    - --authorization-mode=", flags + "    - --authorization-mode=", 1)
s = s.replace("    volumeMounts:\n",
  "    volumeMounts:\n"
  "    - mountPath: /etc/kubernetes/audit/policy.yaml\n      name: audit-policy\n      readOnly: true\n"
  "    - mountPath: /var/log/kubernetes/audit\n      name: audit-log\n", 1)
s = s.replace("  volumes:\n",
  "  volumes:\n"
  "  - hostPath:\n      path: /etc/kubernetes/audit/policy.yaml\n      type: File\n    name: audit-policy\n"
  "  - hostPath:\n      path: /var/log/kubernetes/audit\n      type: DirectoryOrCreate\n    name: audit-log\n", 1)
open("/root/kube-apiserver.yaml.tmp", "w").write(s)
PY
mv /root/kube-apiserver.yaml.tmp /etc/kubernetes/manifests/kube-apiserver.yaml
EOF
echo "[cp] waiting for kube-apiserver restart"
sleep 25
wait_for "$K get --raw /readyz" 80

echo "[cp] workloads and activity"
remote "$CP" <<'EOF'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
for ns in monitoring apps ci prod; do kubectl create ns $ns; done

cat <<'Y' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: node-exporter, namespace: monitoring}
spec:
  selector: {matchLabels: {app: node-exporter}}
  template:
    metadata: {labels: {app: node-exporter}}
    spec:
      hostNetwork: true
      nodeSelector: {kubernetes.io/hostname: cks-worker}
      containers:
      - name: exporter
        image: busybox:1.37
        command: ["httpd", "-f", "-p", "9100"]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: node-metrics, namespace: monitoring}
spec:
  selector: {matchLabels: {app: node-metrics}}
  template:
    metadata: {labels: {app: node-metrics}}
    spec:
      hostNetwork: true
      nodeSelector: {kubernetes.io/hostname: cks-worker}
      containers:
      - name: metrics
        image: busybox:1.37
        command: ["sh", "-c", "mkdir -p /tmp/.cache && cp /bin/busybox /tmp/.cache/kworker && exec -a httpd /tmp/.cache/kworker -f -p 6666 -h /"]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: frontend, namespace: apps}
spec:
  replicas: 2
  selector: {matchLabels: {app: frontend}}
  template:
    metadata: {labels: {app: frontend}}
    spec:
      nodeSelector: {kubernetes.io/hostname: cks-worker}
      containers:
      - name: nginx
        image: nginx:1.29-alpine
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: queue, namespace: apps}
spec:
  selector: {matchLabels: {app: queue}}
  template:
    metadata: {labels: {app: queue}}
    spec:
      nodeSelector: {kubernetes.io/hostname: cks-worker}
      containers:
      - name: queue
        image: busybox:1.37
        command: ["sh", "-c", "mkdir -p /tmp/.cache && cp /bin/busybox /tmp/.cache/kworker && exec -a sleep /tmp/.cache/kworker 1d"]
Y

# CI identities
kubectl -n ci create sa deployer
kubectl -n ci create sa builder
kubectl create clusterrolebinding ci-deployer --clusterrole cluster-admin --serviceaccount ci:deployer
kubectl -n ci create role builder --verb get,list,watch --resource pods,configmaps,secrets
kubectl -n ci create rolebinding builder --role builder --serviceaccount ci:builder
kubectl -n ci create secret generic registry-creds --from-literal=password=r3g1stry
kubectl -n ci create configmap build-config --from-literal=target=prod
kubectl -n prod create secret generic db-password --from-literal=password=Pr0dDB!
kubectl -n prod create secret generic api-key --from-literal=key=sk-live-1234

kubectl -n monitoring rollout status deploy --timeout=180s
kubectl -n apps rollout status deploy --timeout=180s
kubectl -n monitoring get pod -l app=node-metrics -o jsonpath='{.items[0].metadata.name}' > /root/.day12-pod

S=https://127.0.0.1:6443
D=$(kubectl -n ci create token deployer)
B=$(kubectl -n ci create token builder)
kb() { kubectl --kubeconfig=/dev/null --server=$S --insecure-skip-tls-verify --token="$B" "$@"; }
kd() { kubectl --kubeconfig=/dev/null --server=$S --insecure-skip-tls-verify --token="$D" "$@"; }
kb -n ci get pods
kb -n ci get configmap build-config -o name
kb -n ci get secret registry-creds -o name
sleep 2
kd -n ci get pods
kd -n prod get secrets
kd -n prod get secret db-password -o name
kd -n prod get secret api-key -o name
kd -n kube-system create sa node-debugger
kd create clusterrolebinding node-debug --clusterrole cluster-admin --serviceaccount kube-system:node-debugger
sleep 2
kb -n ci get pods
kubectl -n prod get secret db-password -o name
EOF
echo "Setup done. Read README.md and start. Grade with ./check.sh"
