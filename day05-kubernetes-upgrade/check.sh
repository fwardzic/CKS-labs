#!/usr/bin/env bash
# Run on the Mac. Grades Day 5.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh
V=1.36.5

for n in "$CP" "$WORKER"; do
  section "$n"
  check "$n kubelet reports v$V" "$K get node $n -o jsonpath='{.status.nodeInfo.kubeletVersion}' | grep -qx v$V"
  check "$n kubeadm is v$V" "kubeadm version -o short | grep -qx v$V" "$n"
  check "$n kubectl is v$V" "kubectl version --client -o json | jq -e '.clientVersion.gitVersion == \"v$V\"'" "$n"
  check "$n packages held again" "apt-mark showhold | grep -q kubelet && apt-mark showhold | grep -q kubeadm" "$n"
  check "$n Ready and schedulable" \
    "$K get node $n -o json | jq -e '([.status.conditions[] | select(.type==\"Ready\")][0].status == \"True\") and (.spec.unschedulable != true)'"
done

section "control plane"
for c in kube-apiserver kube-controller-manager kube-scheduler kube-proxy; do
  check "$c image v$V" "$K -n kube-system get pods -o jsonpath='{..image}' | tr ' ' '\n' | grep -q '$c:v$V'"
done
check "kubeadm-config ClusterConfiguration kubernetesVersion v$V" \
  "$K -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | grep -q 'kubernetesVersion: v$V'"

section "workload"
check "prod/shop has 3 ready replicas" "$K -n prod get deploy shop -o jsonpath='{.status.readyReplicas}' | grep -qx 3"
check "Cilium healthy" "cilium status --wait --wait-duration 60s >/dev/null"

summary
