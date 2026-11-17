#!/usr/bin/env bash
# Run on the Mac. Grades Day 1.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh
WORKER_IP="$(node_ip "$WORKER")"
M=/etc/kubernetes/manifests/kube-apiserver.yaml

section "Task 1: kube-apiserver"
check "API server answers /readyz" "$K get --raw /readyz"
check "PodSecurityPolicy not in admission plugins" "! grep -q PodSecurityPolicy $M"
check "NodeRestriction still enabled" "grep -qE -- '--enable-admission-plugins=.*NodeRestriction' $M"
check "etcd client cert path correct" "grep -q -- '--etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt' $M"
check "no backup/extra manifests left in manifests dir" "[ \$(ls /etc/kubernetes/manifests | wc -l) -eq 4 ]"
check "/root/day1/apiserver-errors.txt mentions the admission plugin" "grep -q PodSecurityPolicy /root/day1/apiserver-errors.txt"
check "/root/day1/apiserver-errors.txt mentions the etcd cert" "grep -q apiserver-etcd-client /root/day1/apiserver-errors.txt"

section "Task 2: kubelet on cks-worker"
check "cks-worker is Ready" "$K get node cks-worker -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -qx True"
check "anonymous request to :10250 gets 401" "[ \$(curl -sk -o /dev/null -w '%{http_code}' https://$WORKER_IP:10250/pods) = 401 ]"
check "read-only port 10255 closed" "! curl -s -m 3 http://$WORKER_IP:10255/pods"
check "API server can still reach kubelet (kubectl logs works)" "$K -n kube-system logs \$($K -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=cks-worker -o name) -c cilium-agent --tail 1"

section "Task 3: privileged static pod"
check "no pod mounts host / anywhere" "$K get pods -A -o json >/tmp/pods.json && ! grep -q '\"path\": \"/\"' /tmp/pods.json"
check "node-debugger mirror pod gone" "$K get pod node-debugger-cks-worker 2>&1 | grep -q NotFound"
check "node-debugger manifest removed from cks-worker" "! grep -rq node-debugger /etc/kubernetes/manifests" "$WORKER"

summary
