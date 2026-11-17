#!/usr/bin/env bash
# Runs as root on a node. Usage: tools.sh node|cp
#   node: Falco (modern eBPF, systemd), gVisor runsc (installed, NOT wired into containerd), AppArmor utils
#   cp:   node tools + trivy, kube-bench, bom, kubesec, kube-linter, etcdctl, cosign, istioctl
set -euo pipefail
ROLE="${1:-node}"
export DEBIAN_FRONTEND=noninteractive
BIN=/usr/local/bin

TRIVY_VERSION=0.76.1
KUBE_BENCH_VERSION=0.16.0
BOM_VERSION=v0.8.0
KUBESEC_VERSION=v2.15.0
KUBE_LINTER_VERSION=v0.8.3
COSIGN_VERSION=v3.1.4
ISTIO_VERSION=1.31.3
HELM_VERSION=v3.22.1

apt-get install -y -q apparmor-utils

# Falco from the official apt repo, modern eBPF driver, no automatic rule updates
curl -fsSL https://falco.org/repo/falcosecurity-packages.asc |
  gpg --batch --yes --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main" \
  >/etc/apt/sources.list.d/falcosecurity.list
# gVisor from the official apt repo
curl -fsSL https://gvisor.dev/archive.key |
  gpg --batch --yes --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" \
  >/etc/apt/sources.list.d/gvisor.list
apt-get update -q
FALCO_FRONTEND=noninteractive FALCO_DRIVER_CHOICE=modern_ebpf FALCOCTL_ENABLED=no \
  apt-get install -y -q falco
apt-get install -y -q runsc

[ "$ROLE" = cp ] || exit 0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/trivy.deb" \
  "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-ARM64.deb"
curl -fsSL -o "$tmp/kube-bench.deb" \
  "https://github.com/aquasecurity/kube-bench/releases/download/v${KUBE_BENCH_VERSION}/kube-bench_${KUBE_BENCH_VERSION}_linux_arm64.deb"
apt-get install -y -q "$tmp/trivy.deb" "$tmp/kube-bench.deb"

curl -fsSL -o "$BIN/bom" "https://github.com/kubernetes-sigs/bom/releases/download/${BOM_VERSION}/bom-arm64-linux"
curl -fsSL -o "$BIN/kube-linter" "https://github.com/stackrox/kube-linter/releases/download/${KUBE_LINTER_VERSION}/kube-linter-linux_arm64"
curl -fsSL -o "$BIN/cosign" "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-arm64"
curl -fsSL "https://github.com/controlplaneio/kubesec/releases/download/${KUBESEC_VERSION}/kubesec_linux_arm64.tar.gz" |
  tar -xz -C "$BIN" kubesec
curl -fsSL "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-linux-arm64.tar.gz" |
  tar -xz -C "$BIN" istioctl
curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-arm64.tar.gz" |
  tar -xz -C "$BIN" --strip-components 1 linux-arm64/helm
chmod +x "$BIN/bom" "$BIN/kube-linter" "$BIN/cosign"

# etcdctl matching the etcd version kubeadm deployed
ETCD_VERSION="$(kubeadm config images list 2>/dev/null | awk -F: '/etcd/{print $2}' | cut -d- -f1)"
curl -fsSL "https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-arm64.tar.gz" |
  tar -xz -C "$tmp"
install -m 0755 "$tmp/etcd-v${ETCD_VERSION}-linux-arm64/etcdctl" "$BIN/etcdctl"
