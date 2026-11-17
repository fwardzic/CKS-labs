#!/usr/bin/env bash
# Run on the Mac. Day 9: supply chain (trivy, SBOM, static analysis, image admission).
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

multipass transfer image-policy-server.py "$CP:/tmp/image-policy-server.py"

echo "[cp] image policy backend, workloads, manifests"
remote "$CP" <<'EOF'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /root/day9

# ImagePolicyWebhook backend on 127.0.0.1:8443 + client/server certs + webhook kubeconfig
d=/etc/kubernetes/policywebhook
mkdir -p "$d" /opt/image-policy
install -m 0755 /tmp/image-policy-server.py /opt/image-policy/server.py
cd "$d"
openssl req -x509 -nodes -newkey rsa:2048 -days 365 -keyout ca.key -out ca.crt -subj "/CN=image-policy-ca" 2>/dev/null
openssl req -nodes -newkey rsa:2048 -keyout backend.key -out backend.csr -subj "/CN=localhost" 2>/dev/null
openssl x509 -req -in backend.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 -out backend.crt \
  -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1") 2>/dev/null
openssl req -nodes -newkey rsa:2048 -keyout apiserver-client.key -out apiserver-client.csr -subj "/CN=kube-apiserver" 2>/dev/null
openssl x509 -req -in apiserver-client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 -out apiserver-client.crt 2>/dev/null
rm -f ./*.csr ./*.srl
cat >kubeconf <<'K'
apiVersion: v1
kind: Config
clusters:
- name: image-checker
  cluster:
    certificate-authority: /etc/kubernetes/policywebhook/ca.crt
    server: https://127.0.0.1:8443/image_policy
contexts:
- name: image-checker
  context:
    cluster: image-checker
    user: api-server
current-context: image-checker
users:
- name: api-server
  user:
    client-certificate: /etc/kubernetes/policywebhook/apiserver-client.crt
    client-key: /etc/kubernetes/policywebhook/apiserver-client.key
K
cat >admission_config.yaml <<'A'
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: ImagePolicyWebhook
  configuration:
    imagePolicy:
      kubeConfigFile: /etc/kubernetes/policywebhook/kubeconf
      allowTTL: 10
      denyTTL: 10
      retryBackoff: 500
      defaultAllow: true
A
cat >/etc/systemd/system/image-policy.service <<'U'
[Unit]
Description=ImagePolicyWebhook backend (lab)
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/image-policy/server.py /etc/kubernetes/policywebhook/backend.crt /etc/kubernetes/policywebhook/backend.key 8443
Restart=always

[Install]
WantedBy=multi-user.target
U
systemctl daemon-reload
systemctl enable --now image-policy.service

# Task 1 workloads
kubectl create ns team-x
run() { kubectl -n team-x run "$1" --image "$2" ${3:+--command -- $3}; }
run web-old nginx:1.19-alpine
run httpd httpd:2.4.46-alpine
run web-new nginx:1.29-alpine
run cache redis:7.4-alpine
run toolbox busybox:1.37 "sleep 1d"
kubectl -n team-x wait --for=condition=Ready pod --all --timeout=300s

# Task 3 manifest
kubectl create ns supply
cat >/root/day9/tools.yaml <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tools
  namespace: supply
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tools
  template:
    metadata:
      labels:
        app: tools
    spec:
      hostPID: true
      containers:
      - name: tools
        image: docker.io/library/busybox:1.37
        command: ["sleep", "1d"]
        securityContext:
          privileged: true
          capabilities:
            add: ["SYS_ADMIN"]
Y
EOF
echo "Setup done. Read README.md and start. Grade with ./check.sh"
