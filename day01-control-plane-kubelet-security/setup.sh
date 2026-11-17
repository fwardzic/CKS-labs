#!/usr/bin/env bash
# Run on the Mac. Day 1: breaks the cluster for tasks in README.md.
# Start from a clean cluster: ../cluster/reset.sh
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

echo "[worker] insecure kubelet + rogue static pod"
remote "$WORKER" <<'EOF'
set -euo pipefail
python3 - <<'PY'
import yaml
p = "/var/lib/kubelet/config.yaml"
c = yaml.safe_load(open(p))
c["authentication"]["anonymous"]["enabled"] = True
c["authorization"]["mode"] = "AlwaysAllow"
c["readOnlyPort"] = 10255
yaml.safe_dump(c, open(p, "w"), default_flow_style=False)
PY
systemctl restart kubelet

cat >/etc/kubernetes/manifests/node-debugger.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: node-debugger
  namespace: default
  labels:
    app: debug
spec:
  containers:
  - name: shell
    image: busybox:1.37
    command: ["sh", "-c", "sleep infinity"]
    securityContext:
      privileged: true
    volumeMounts:
    - name: host
      mountPath: /host
  volumes:
  - name: host
    hostPath:
      path: /
YAML
EOF

echo "[cp] waiting for node-debugger mirror pod"
wait_for "$K get pod node-debugger-cks-worker"

echo "[cp] breaking kube-apiserver"
remote "$CP" <<'EOF'
set -euo pipefail
mkdir -p /root/day1
m=/etc/kubernetes/manifests/kube-apiserver.yaml
sed -i 's#--enable-admission-plugins=NodeRestriction$#--enable-admission-plugins=NodeRestriction,PodSecurityPolicy#' "$m"
sed -i 's#--etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt#--etcd-certfile=/etc/kubernetes/pki/etcd/apiserver-etcd-client.crt#' "$m"
grep -q PodSecurityPolicy "$m" && grep -q 'pki/etcd/apiserver-etcd-client.crt' "$m"
EOF

echo "Setup done. Read README.md and start. Grade with ./check.sh"
