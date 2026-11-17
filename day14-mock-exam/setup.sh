#!/usr/bin/env bash
# Run on the Mac. Day 14: mock exam (all domains).
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

echo "[worker] kubelet, profiles"
remote "$WORKER" <<'EOF'
set -euo pipefail
mkdir -p /root/mock /opt/mock/apparmor /opt/mock/seccomp
python3 - <<'PY'
import yaml
p = "/var/lib/kubelet/config.yaml"
c = yaml.safe_load(open(p))
c["authentication"]["anonymous"]["enabled"] = True
c["authorization"]["mode"] = "AlwaysAllow"
c["readOnlyPort"] = 10255
yaml.safe_dump(c, open(p, "w"), default_flow_style=False)
PY
chmod 666 /var/lib/kubelet/config.yaml
systemctl restart kubelet

cat > /opt/mock/apparmor/deny-etc-write <<'A'
#include <tunables/global>

profile mock-deny-etc flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  file,
  network,
  capability,
  deny /etc/** wl,
}
A
cat > /opt/mock/seccomp/block-mkdir.json <<'S'
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "syscalls": [
    { "names": ["mkdir", "mkdirat"], "action": "SCMP_ACT_ERRNO" }
  ]
}
S
EOF

echo "[cp] workloads and files"
remote "$CP" <<'EOF'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /root/mock
for ns in mock-ops mock-db mock-app mock-debug mock-sys mock-runtime mock-scan mock-legacy mock-prod; do kubectl create ns $ns; done
kubectl label ns mock-prod env=prod
kubectl label ns mock-debug pod-security.kubernetes.io/enforce=restricted

# T1 RBAC
kubectl -n mock-ops create sa automation
kubectl -n mock-ops create sa viewer
kubectl -n mock-ops create role automation --verb='*' --resource='*.*'
kubectl -n mock-ops create rolebinding automation --role automation --serviceaccount mock-ops:automation
kubectl create clusterrolebinding viewer-view --clusterrole view --serviceaccount mock-ops:viewer
kubectl -n mock-ops create deployment worker --image=busybox:1.37 -- sleep 1d
kubectl -n mock-ops create secret generic ops-token --from-literal=token=0ps

# T2/T3 netpol + PSA
for p in db cache; do
  kubectl -n mock-db run $p --image=nginx:1.29-alpine --labels app=$p --port 80
  kubectl -n mock-db expose pod $p --port 80
done
kubectl -n mock-app create deployment backend --image=busybox:1.37 -- sleep 1d
cat <<'Y' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: mock-app
  labels: {app: frontend}
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile: {type: RuntimeDefault}
  containers:
  - name: frontend
    image: busybox:1.37
    command: ["sleep", "1d"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities: {drop: ["ALL"]}
---
apiVersion: v1
kind: Pod
metadata:
  name: legacy-api
  namespace: mock-debug
  labels: {app: legacy-api}
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65535
    seccompProfile: {type: RuntimeDefault}
  containers:
  - name: app
    image: registry.k8s.io/pause:3.10
    securityContext:
      allowPrivilegeEscalation: false
      capabilities: {drop: ["ALL"]}
Y

# T8 Falco
kubectl -n mock-runtime create deployment probe --image=busybox:1.37 -- \
  sh -c 'while true; do nc -z -w 1 db.mock-db 80; sleep 5; done'
kubectl -n mock-runtime create deployment ticker --image=busybox:1.37 -- \
  sh -c 'while true; do date >/tmp/now; sleep 5; done'
kubectl -n mock-runtime create deployment web --image=nginx:1.29-alpine

# T9 trivy
run() { kubectl -n mock-scan run "$1" --image "$2" ${3:+--command -- $3}; }
run proxy nginx:1.21-alpine
run base alpine:3.22 "sleep 1d"
run memcache memcached:1.6-alpine
run tools busybox:1.37 "sleep 1d"

# T12 VAP
kubectl -n mock-prod create deployment api --image=nginx:1.29-alpine --replicas 2

# T13 risky workloads
cat <<'Y' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: metrics, namespace: mock-legacy}
spec:
  selector: {matchLabels: {app: metrics}}
  template:
    metadata: {labels: {app: metrics}}
    spec:
      hostPID: true
      containers:
      - {name: metrics, image: busybox:1.37, command: ["sleep", "1d"]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: fs-agent, namespace: mock-legacy}
spec:
  selector: {matchLabels: {app: fs-agent}}
  template:
    metadata: {labels: {app: fs-agent}}
    spec:
      containers:
      - name: agent
        image: busybox:1.37
        command: ["sleep", "1d"]
        securityContext: {privileged: true}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: mock-legacy}
spec:
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers:
      - {name: nginx, image: nginx:1.29-alpine}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: debug-shell, namespace: mock-runtime}
spec:
  selector: {matchLabels: {app: debug-shell}}
  template:
    metadata: {labels: {app: debug-shell}}
    spec:
      containers:
      - name: shell
        image: busybox:1.37
        command: ["sleep", "1d"]
        securityContext:
          privileged: false
          capabilities: {add: ["SYS_ADMIN"]}
Y
kubectl -n mock-runtime patch deploy debug-shell --type json -p '[{"op":"add","path":"/spec/template/spec/hostPID","value":true}]'

# T10 cosign
d=/opt/mock/release; mkdir -p $d; cd $d
export COSIGN_PASSWORD=
w=$(mktemp -d)
( cd $w && cosign generate-key-pair >/dev/null 2>&1 && mkdir other && cd other && cosign generate-key-pair >/dev/null 2>&1 )
cp $w/cosign.pub $d/cosign.pub
for v in 1 2 3; do
  cp /usr/bin/jq kube-tool-v1.$v
  printf 'build-%s' $v >> kube-tool-v1.$v
done
sgn() { cosign sign-blob --key "$1" --tlog-upload=false --use-signing-config=false --bundle "$2.bundle" "$2" -y >/dev/null 2>&1; }
sgn $w/cosign.key kube-tool-v1.1
sgn $w/cosign.key kube-tool-v1.2
sgn $w/other/cosign.key kube-tool-v1.3
printf 'x' >> kube-tool-v1.1
rm -rf $w

kubectl wait --for=condition=Ready pod --all -A --timeout=300s
EOF
echo "Setup done. Read README.md and start. Grade with ./check.sh"
