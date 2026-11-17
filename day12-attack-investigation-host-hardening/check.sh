#!/usr/bin/env bash
# Run on the Mac. Grades Day 12.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh

section "Task 1: container forensics"
POD="$(on "$CP" 'cat /root/.day12-pod' 2>/dev/null)"
check "/root/day12/listener.txt = monitoring/$POD" "grep -qx 'monitoring/$POD' /root/day12/listener.txt" "$WORKER"
check "/root/day12/binary.txt = path of the binary inside the container" "grep -qx '/tmp/.cache/kworker' /root/day12/binary.txt" "$WORKER"
check "workload removed, nothing listens on 6666" \
  "! $K -n monitoring get deploy node-metrics && ! $K -n monitoring get pods --no-headers | grep -q node-metrics"
check "port 6666 closed on cks-worker" "! ss -tln | grep -q ':6666 '" "$WORKER"
check "other workloads untouched (node-exporter, frontend, queue)" \
  "$K -n monitoring get deploy node-exporter -o jsonpath='{.status.readyReplicas}' | grep -qx 1 && $K -n apps get deploy frontend -o jsonpath='{.status.readyReplicas}' | grep -qx 2 && $K -n apps get deploy queue -o jsonpath='{.status.readyReplicas}' | grep -qx 1"

section "Task 2: audit investigation"
check "/root/day12/secret-reader.txt names the ServiceAccount" \
  "grep -qx 'system:serviceaccount:ci:deployer' /root/day12/secret-reader.txt"
check "ClusterRoleBinding node-debug deleted" "! $K get clusterrolebinding node-debug"
check "ServiceAccount kube-system/node-debugger deleted" "! $K -n kube-system get sa node-debugger"
check "ci:deployer can no longer read secrets in prod" \
  "$K auth can-i get secrets -n prod --as system:serviceaccount:ci:deployer | grep -qx no"
check "ServiceAccount ci/deployer still exists" "$K -n ci get sa deployer"
check "ci:builder keeps its permissions in ci" \
  "$K auth can-i get secrets -n ci --as system:serviceaccount:ci:builder | grep -qx yes"

section "Task 3: host hardening (cks-worker)"
check "tipc not loaded" "! lsmod | grep -q '^tipc '" "$WORKER"
check "sctp and tipc cannot be loaded" \
  "for m in sctp tipc; do modprobe -n -v \$m 2>&1 | grep -Eq '^install (/usr)?/bin/(false|true)' || exit 1; done" "$WORKER"
check "sshd: root login and password auth disabled" \
  "sshd -T | grep -qx 'permitrootlogin no' && sshd -T | grep -qx 'passwordauthentication no'" "$WORKER"
check "SSH still accepts connections on port 22" "ss -tln | grep -q ':22 '" "$WORKER"
check "only root has UID 0, svc-backup gone" \
  "[ \"\$(awk -F: '\$3==0{print \$1}' /etc/passwd)\" = root ] && ! getent passwd svc-backup" "$WORKER"

summary
