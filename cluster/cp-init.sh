#!/usr/bin/env bash
# Runs as root on the control plane: kubeadm init, kubeconfig, Cilium.
set -euo pipefail

CILIUM_VERSION="${CILIUM_VERSION:-1.20.3}"
CILIUM_CLI_VERSION="${CILIUM_CLI_VERSION:-v0.20.1}"
NODE_IP="$(hostname -I | awk '{print $1}')"

kubeadm init \
  --apiserver-advertise-address "$NODE_IP" \
  --pod-network-cidr 10.244.0.0/16 \
  --node-name "$(hostname)"

for home in /root /home/ubuntu; do
  mkdir -p "$home/.kube"
  cp /etc/kubernetes/admin.conf "$home/.kube/config"
done
chown -R ubuntu:ubuntu /home/ubuntu/.kube
export KUBECONFIG=/etc/kubernetes/admin.conf

curl -fsSL "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-arm64.tar.gz" |
  tar -xz -C /usr/local/bin cilium
# ipam.mode=kubernetes: use the per-node podCIDRs allocated by kubeadm's --pod-network-cidr
cilium install --version "$CILIUM_VERSION" --set ipam.mode=kubernetes
cilium status --wait

# The Multipass node resolvers (192.168.252.1 refuses, IPv6 link-local unusable from pods)
# do not work for CoreDNS, so forward external names to public resolvers.
kubectl -n kube-system get cm coredns -o yaml |
  sed 's#forward . /etc/resolv.conf#forward . 1.1.1.1 8.8.8.8#' | kubectl apply -f -
kubectl -n kube-system rollout restart deploy coredns

kubeadm token create --print-join-command >/root/join.sh
