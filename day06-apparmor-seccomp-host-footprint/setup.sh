#!/usr/bin/env bash
# Run on the Mac. Day 6: AppArmor, seccomp, host footprint.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

echo "[worker] profiles, backdoor service, over-privileged user"
remote "$WORKER" <<'EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
mkdir -p /opt/profiles
cat >/opt/profiles/k8s-deny-write <<'P'
#include <tunables/global>

profile k8s-deny-write flags=(attach_disconnected) {
  #include <abstractions/base>

  file,

  # Deny all file writes.
  deny /** w,
}
P
cat >/opt/profiles/no-chmod.json <<'P'
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "syscalls": [
    {
      "names": ["chmod", "fchmod", "fchmodat", "fchmodat2"],
      "action": "SCMP_ACT_ERRNO"
    }
  ]
}
P

apt-get install -y -q socat >/dev/null
cat >/etc/systemd/system/node-agent.service <<'U'
[Unit]
Description=Node agent
After=network.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:4444,reuseaddr,fork EXEC:/bin/bash
Restart=always

[Install]
WantedBy=multi-user.target
U
systemctl daemon-reload
systemctl enable --now node-agent.service

id contractor >/dev/null 2>&1 || useradd -m -s /bin/bash contractor
usermod -aG sudo contractor
echo 'contractor ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/contractor
chmod 440 /etc/sudoers.d/contractor
EOF

echo "[cp] namespace + deployment"
remote "$CP" <<'EOF'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl create ns secure
kubectl -n secure create deployment api --image=nginx:1.27-alpine --replicas 2
kubectl -n secure rollout status deploy api --timeout=180s
EOF
echo "Setup done. Read README.md and start. Grade with ./check.sh"
