#!/usr/bin/env bash
# Run on the Mac. Grades Day 4.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh
CP_IP="$(node_ip "$CP")"
BOT="--as system:serviceaccount:finance:report-bot"
JANE="kubectl --kubeconfig /root/day4/jane.kubeconfig"
JANE_OK="$JANE auth whoami >/dev/null"

section "Task 1: least privilege for report-bot"
check "ClusterRoleBinding report-bot-admin removed" "$K get clusterrolebinding report-bot-admin 2>&1 | grep -q NotFound"
check "no ClusterRoleBinding references report-bot" \
  "! $K get clusterrolebindings -o json | jq -e '.items[].subjects[]? | select(.name==\"report-bot\")'"
check "Role finance/report-reader exists" "$K -n finance get role report-reader"
check "RoleBinding finance/report-bot -> report-reader" \
  "$K -n finance get rolebinding report-bot -o jsonpath='{.roleRef.kind}/{.roleRef.name}' | grep -qx Role/report-reader"
check "report-bot can list pods in finance" "$K auth can-i list pods -n finance $BOT"
check "report-bot can watch configmaps in finance" "$K auth can-i watch configmaps -n finance $BOT"
check "report-bot can get pods/log in finance" "$K auth can-i get pods --subresource=log -n finance $BOT"
check "report-bot cannot get secrets in finance" "! $K auth can-i get secrets -n finance $BOT"
check "report-bot cannot delete pods in finance" "! $K auth can-i delete pods -n finance $BOT"
check "report-bot cannot list pods in dev" "! $K auth can-i list pods -n dev $BOT"

section "Task 2: ServiceAccount hygiene"
check "SA finance/legacy-sa has automountServiceAccountToken=false" \
  "$K -n finance get sa legacy-sa -o jsonpath='{.automountServiceAccountToken}' | grep -qx false"
check "SA finance/default has automountServiceAccountToken=false" \
  "$K -n finance get sa default -o jsonpath='{.automountServiceAccountToken}' | grep -qx false"
check "deployment legacy uses legacy-sa" \
  "$K -n finance get deploy legacy -o jsonpath='{.spec.template.spec.serviceAccountName}' | grep -qx legacy-sa"
check "legacy pod running without a token mount" \
  "p=\$($K -n finance get pod -l app=legacy --field-selector status.phase=Running -o name | head -1); [ -n \"\$p\" ] && ! $K -n finance exec \$p -- ls /var/run/secrets/kubernetes.io/serviceaccount/token"
check "long-lived token secret old-ci-token deleted" "$K -n finance get secret old-ci-token 2>&1 | grep -q NotFound"

section "Task 3: user jane via CSR"
check "CSR jane approved and issued" \
  "$K get csr jane -o json | jq -e '([.status.conditions[]?.type] | index(\"Approved\") != null) and (.status.certificate | length > 0)'"
check "CSR jane uses signer kube-apiserver-client" \
  "$K get csr jane -o jsonpath='{.spec.signerName}' | grep -qx kubernetes.io/kube-apiserver-client"
check "jane.kubeconfig authenticates as jane" "$JANE auth whoami -o jsonpath='{.status.userInfo.username}' | grep -qx jane"
check "jane can create deployments in dev" "$JANE auth can-i create deployments -n dev | grep -qx yes"
check "jane can list deployments in dev" "$JANE -n dev get deploy web"
check "jane cannot list pods in finance" "$JANE_OK && ! $JANE -n finance get pods"
check "jane cannot delete deployments in dev" "$JANE_OK && ! $JANE auth can-i delete deployments -n dev"

section "Task 4: restrict API access"
check "ClusterRoleBinding anon-view removed" "$K get clusterrolebinding anon-view 2>&1 | grep -q NotFound"
check "anonymous cannot list pods" \
  "c=\$(curl -sk -o /dev/null -w '%{http_code}' https://$CP_IP:6443/api/v1/namespaces/default/pods); [ \$c = 401 ] || [ \$c = 403 ]"
check "NodeRestriction enabled" "grep -E -- '--enable-admission-plugins=.*NodeRestriction' /etc/kubernetes/manifests/kube-apiserver.yaml"
check "kubelet of cks-worker cannot set node-restriction.kubernetes.io/ labels" \
  "! kubectl --kubeconfig /etc/kubernetes/kubelet.conf label node cks-worker node-restriction.kubernetes.io/day4=test --overwrite" "$WORKER"
_cleanup="$(on "$CP" "$K label node cks-worker node-restriction.kubernetes.io/day4-" 2>&1)"
check "kube-apiserver pod Ready (probes succeed)" \
  "$K -n kube-system get pod kube-apiserver-cks-cp -o jsonpath='{.status.containerStatuses[0].ready}' | grep -qx true"
check "API server stable (no restarts in the last 60s)" \
  "a=\$(crictl ps --name kube-apiserver -q | head -1); [ -n \"\$a\" ] && [ \$(( \$(date +%s) - \$(date -d \"\$(crictl inspect \$a | jq -r .status.startedAt)\" +%s) )) -gt 60 ]"

summary
