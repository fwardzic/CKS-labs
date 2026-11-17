#!/usr/bin/env bash
# Run on the Mac. Grades Day 10.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh
O="$K -n ops"
M=/etc/kubernetes/manifests/kube-apiserver.yaml
LOG=/var/log/kubernetes/audit/audit.log
ALERTS=/var/log/falco/alerts.log
STAMP="day10-$RANDOM"

section "Task 1: Falco"
check "deployment collector scaled to 0" "$O get deploy collector -o jsonpath='{.spec.replicas}' | grep -qx 0"
check "other deployments untouched (updater, idle, frontend running)" \
  "for d in updater idle frontend; do [ \"\$($O get deploy \$d -o jsonpath='{.status.readyReplicas}')\" -ge 1 ] || exit 1; done"
check "rule 'Package manager in container' in falco_rules.local.yaml" \
  "grep -qE \"rule:[[:space:]]*[\\\"']?Package manager in container\" /etc/falco/falco_rules.local.yaml" "$WORKER"
check "Falco running on cks-worker" "systemctl is-active -q falco-modern-bpf" "$WORKER"
check "Falco writes alerts to $ALERTS" "grep -A3 '^file_output:' /etc/falco/falco.yaml | grep -q 'enabled: true' && [ -s $ALERTS ]" "$WORKER"
check "alerts file has the custom rule in the requested format" \
  "grep -E 'Package manager in container \\| time=[0-9:.]+ container=[^ ]+ pod=updater-[^ ]+ ns=ops cmd=apk info' $ALERTS" "$WORKER"
UPD="$(on "$CP" "$O get pod -l app=updater -o jsonpath='{.items[0].metadata.name}'" 2>/dev/null)"
check "/root/day10/pkg-pod.txt names the updater pod" "grep -qx '$UPD' /root/day10/pkg-pod.txt" "$WORKER"

section "Task 2: audit logging"
check "audit flags set (policy, path, maxage 7, maxbackup 2)" \
  "grep -q -- '--audit-policy-file=/etc/kubernetes/audit/policy.yaml' $M && grep -q -- '--audit-log-path=$LOG' $M && grep -q -- '--audit-log-maxage=7' $M && grep -q -- '--audit-log-maxbackup=2' $M"
check "API server healthy" "$K get --raw /readyz"
# generate fresh events, then inspect them
_gen="$(on "$CP" "$K -n ops get secret app-secret -o name; $K -n ops patch configmap app-config -p '{\"data\":{\"stamp\":\"$STAMP\"}}'; $K -n default get pods; $K -n default create configmap $STAMP; $K -n default delete configmap $STAMP; sleep 3" 2>&1)"
check "secret access logged at Metadata (no payload)" \
  "grep '\"resource\":\"secrets\"' $LOG | grep '\"name\":\"app-secret\"' | tail -1 | jq -e '.level == \"Metadata\" and (has(\"responseObject\") | not)'"
check "configmap change in ops logged at RequestResponse" \
  "grep '$STAMP' $LOG | grep '\"namespace\":\"ops\"' | tail -1 | jq -e '.level == \"RequestResponse\" and .verb == \"patch\"'"
check "configmaps in other namespaces not logged" "[ -s $LOG ] && ! grep '\"name\":\"$STAMP\"' $LOG | grep -q '\"namespace\":\"default\"'"
check "no RequestReceived stage entries" "[ -s $LOG ] && ! tail -200 $LOG | grep -q '\"stage\":\"RequestReceived\"'"
check "pod list in default not logged" \
  "[ -s $LOG ] && ! tail -500 $LOG | jq -c 'select(.objectRef.resource==\"pods\" and .objectRef.namespace==\"default\" and .verb==\"list\")' | grep -q ."

section "Task 3: immutable frontend"
check "frontend container has readOnlyRootFilesystem: true" \
  "$O get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' | grep -qx true"
check "frontend fully rolled out" "$O get deploy frontend -o json | jq -e '.status.updatedReplicas == .spec.replicas and .status.readyReplicas == .spec.replicas'"
check "writing to the image filesystem fails" "$O exec deploy/frontend -- true && ! $O exec deploy/frontend -- touch /usr/share/nginx/html/x"
check "frontend serves HTTP 200" "$O exec deploy/idle -- wget -qO- -T 3 http://frontend.ops >/dev/null"

summary
