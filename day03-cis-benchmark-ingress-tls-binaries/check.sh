#!/usr/bin/env bash
# Run on the Mac. Grades Day 3.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh
WORKER_IP="$(node_ip "$WORKER")"
HOST=shop.cks.local

section "Task 1: CIS benchmark on cks-cp"
for id in 1.1.1 1.1.11 1.1.12 1.2.6 1.2.7 1.2.8 1.2.15 1.3.2 1.4.1; do
  check "kube-bench $id passes" \
    "kube-bench run --targets master --check $id --json 2>/dev/null | jq -e '.Totals.total_pass == 1'"
done
check "API server healthy" "$K get --raw /readyz"
check "etcd healthy" "$K -n kube-system get pod etcd-cks-cp -o jsonpath='{.status.containerStatuses[0].ready}' | grep -qx true"
check "controller-manager and scheduler running" \
  "$K -n kube-system get pod kube-controller-manager-cks-cp kube-scheduler-cks-cp -o jsonpath='{.items[*].status.containerStatuses[0].ready}' | grep -qx 'true true'"

section "Task 2: Ingress with TLS"
check "secret shop/shop-tls is type kubernetes.io/tls" \
  "$K -n shop get secret shop-tls -o jsonpath='{.type}' | grep -qx kubernetes.io/tls"
check "certificate in shop-tls has CN=$HOST" \
  "$K -n shop get secret shop-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject | grep -q 'CN *= *$HOST'"
check "ingress shop uses class nginx and secret shop-tls" \
  "$K -n shop get ingress shop -o json | jq -e '.spec.ingressClassName == \"nginx\" and .spec.tls[0].secretName == \"shop-tls\" and (.spec.tls[0].hosts | index(\"$HOST\") != null)'"
check "https://$HOST serves the shop app" \
  "curl -sk -m 5 --resolve $HOST:30443:$WORKER_IP https://$HOST:30443/ | grep -qx 'shop ok'"
check "https://$HOST presents the shop-tls certificate" \
  "echo | openssl s_client -connect $WORKER_IP:30443 -servername $HOST 2>/dev/null | openssl x509 -noout -subject | grep -q 'CN *= *$HOST'"
check "http://$HOST redirects to https (308)" \
  "[ \$(curl -s -o /dev/null -m 5 -w '%{http_code}' --resolve $HOST:30080:$WORKER_IP http://$HOST:30080/) = 308 ]"

section "Task 3: verify binaries on cks-worker"
check "the genuine v1.35.9 binary is kept" \
  "[ -f /opt/binaries/kubectl-1 ] && [ \$(sha512sum /opt/binaries/kubectl-1 | cut -d' ' -f1) = \$(curl -fsSL https://dl.k8s.io/release/v1.35.9/bin/linux/arm64/kubectl.sha512) ]" "$WORKER"
check "non-matching binaries deleted" "[ ! -e /opt/binaries/kubectl-2 ] && [ ! -e /opt/binaries/kubectl-3 ]" "$WORKER"

summary
