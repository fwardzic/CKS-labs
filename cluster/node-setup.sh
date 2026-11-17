#!/usr/bin/env bash
# Runs as root on every node: containerd + kubeadm/kubelet/kubectl (exam-like kubeadm node).
set -euo pipefail

K8S_MINOR="${K8S_MINOR:-v1.35}"
K8S_PATCH="${K8S_PATCH:-1.35.9-1.1}"
export DEBIAN_FRONTEND=noninteractive

# Kernel prerequisites
swapoff -a
sed -i '/\sswap\s/s/^/#/' /etc/fstab
cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat >/etc/sysctl.d/99-k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

# containerd (Ubuntu package, 2.x) with systemd cgroups
apt-get update -q
apt-get install -y -q containerd apt-transport-https ca-certificates curl gpg jq vim bash-completion
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml || {
  echo "SystemdCgroup not set in containerd config" >&2; exit 1; }
systemctl restart containerd
systemctl enable containerd

# Kubernetes packages, pinned and held (upgrade labs unhold them)
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" |
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list
apt-get update -q
apt-get install -y -q "kubelet=${K8S_PATCH}" "kubeadm=${K8S_PATCH}" "kubectl=${K8S_PATCH}" cri-tools
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

cat >/etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF

# Exam-like shell setup for the ubuntu user
cat >>/home/ubuntu/.bashrc <<'EOF'
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
export do="--dry-run=client -o yaml"
export now="--force --grace-period 0"
EOF
cat >/home/ubuntu/.vimrc <<'EOF'
set expandtab tabstop=2 shiftwidth=2
EOF
chown ubuntu:ubuntu /home/ubuntu/.vimrc
