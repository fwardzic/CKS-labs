#!/usr/bin/env bash
# Run on the Mac. Grades Day 7.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh
P="$K -n payments"
ETCD="etcdctl --endpoints https://127.0.0.1:2379 --cacert /etc/kubernetes/pki/etcd/ca.crt --cert /etc/kubernetes/pki/etcd/server.crt --key /etc/kubernetes/pki/etcd/server.key"
label() { echo "$K get ns $1 -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/$2}' | grep -qx $3"; }
encrypted() { # etcd key -> stored with an encryption provider prefix
  echo "$ETCD get $1 --print-value-only | head -c 40 | grep -aqE '^k8s:enc:(aescbc|aesgcm|secretbox|kms)'"
}

section "Task 1: Pod Security Admission"
check "payments enforces restricted" "$(label payments enforce restricted)"
check "legacy enforces baseline" "$(label legacy enforce baseline)"
check "legacy warns on restricted" "$(label legacy warn restricted)"
check "legacy audits restricted" "$(label legacy audit restricted)"
check "pay pods pass restricted (server dry-run shows no warnings)" \
  "out=\$($K label --dry-run=server --overwrite ns payments pod-security.kubernetes.io/enforce=restricted 2>&1); ! echo \"\$out\" | grep -qi warning"
check "deployment pay fully rolled out (2/2)" \
  "$P get deploy pay -o json | jq -e '.status.updatedReplicas == 2 and .status.readyReplicas == 2 and .status.replicas == 2'"

section "Task 2: Secrets"
check "/root/day7/password.txt holds legacy/admin-creds password" \
  "[ \"\$(cat /root/day7/password.txt)\" = 'Tr0ub4dor&3' ]"
check "secret payments/db-creds has user=pay and pass=S3cr3t!" \
  "$P get secret db-creds -o json | jq -e '(.data.user | @base64d) == \"pay\" and (.data.pass | @base64d) == \"S3cr3t!\"'"
check "pay no longer has DB_PASSWORD in plain env" \
  "! $P get deploy pay -o jsonpath='{.spec.template.spec.containers[*].env[*].name}' | grep -qw DB_PASSWORD"
check "db-creds mounted read-only at /etc/db" \
  "$P get deploy pay -o json | jq -e '.spec.template.spec as \$s | (\$s.volumes[] | select(.secret.secretName == \"db-creds\") | .name) as \$v | \$s.containers[0].volumeMounts[] | select(.name == \$v and .mountPath == \"/etc/db\" and .readOnly == true)'"
check "pay pod can read /etc/db/pass" "$P exec deploy/pay -- cat /etc/db/pass | grep -qx 'S3cr3t!'"

section "Task 3: encryption at rest"
check "kube-apiserver uses --encryption-provider-config" \
  "grep -q -- '--encryption-provider-config=' /etc/kubernetes/manifests/kube-apiserver.yaml"
check "API server healthy" "$K get --raw /readyz"
check "new secret payments/db-creds encrypted in etcd" "$(encrypted /registry/secrets/payments/db-creds)"
check "old secret legacy/admin-creds encrypted in etcd" "$(encrypted /registry/secrets/legacy/admin-creds)"
check "secrets still readable through the API" \
  "$K -n legacy get secret admin-creds -o jsonpath='{.data.password}' | base64 -d | grep -qx 'Tr0ub4dor&3'"
check "no secret in the cluster left unencrypted" \
  "for k in \$($ETCD get /registry/secrets --prefix --keys-only); do $ETCD get \$k --print-value-only | head -c 9 | grep -aq '^k8s:enc:' || exit 1; done"

summary
