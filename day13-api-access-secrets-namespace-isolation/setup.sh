#!/usr/bin/env bash
# Run on the Mac. Day 13: SA tokens, Secrets, namespace NetworkPolicies, API exposure, manual user certs.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

echo "[cp] workloads"
remote "$CP" <<'EOF'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /root/day13
for ns in vault-client one ns-secure space1 space2 other; do kubectl create ns $ns; done

kubectl -n vault-client create sa app

kubectl -n one create secret generic s1 --from-literal=token=3f9a-alpha
kubectl -n one create secret generic s2 --from-literal=user=svc-report --from-literal=pass='Gr33n!Lake'
openssl req -x509 -nodes -newkey rsa:2048 -days 30 -keyout /tmp/one.key -out /tmp/one.crt -subj /CN=one.local 2>/dev/null
kubectl -n one create secret tls web-tls --cert /tmp/one.crt --key /tmp/one.key
kubectl -n one create secret docker-registry regcred --docker-server=registry.example.com --docker-username=ci --docker-password=notthisone
rm -f /tmp/one.key /tmp/one.crt

kubectl -n ns-secure create secret generic sec-a1 --from-literal=token=a1-7d2c9e
printf '[db]\nhost=db.internal\nport=5432\n' > /tmp/config.ini
kubectl -n ns-secure create secret generic sec-a2 --from-file=config.ini=/tmp/config.ini
rm -f /tmp/config.ini

for ns in space1 space2 other; do
  kubectl -n $ns run web --image=nginx:1.29-alpine --labels app=web --port 80
  kubectl -n $ns expose pod web --port 80
done
kubectl -n other run client --image=nginx:1.29-alpine --labels app=client
kubectl -n space1 run client --image=nginx:1.29-alpine --labels app=client
kubectl -n space2 run client --image=nginx:1.29-alpine --labels app=client

kubectl create clusterrole secret-auditor --verb get,list,watch --resource secrets
kubectl create clusterrolebinding secret-auditor --clusterrole secret-auditor --group system:authenticated

sed -i 's#    - --authorization-mode=#    - --kubernetes-service-node-port=31000\n    - --authorization-mode=#' /etc/kubernetes/manifests/kube-apiserver.yaml
grep -q -- '--kubernetes-service-node-port=31000' /etc/kubernetes/manifests/kube-apiserver.yaml
EOF
echo "[cp] waiting for kube-apiserver restart"
sleep 25
wait_for "$K get --raw /readyz" 80
wait_for "$K -n kube-system get pod kube-apiserver-cks-cp -o yaml | grep -q kubernetes-service-node-port" 40
on "$CP" "$K delete svc kubernetes" 
wait_for "$K get svc kubernetes -o jsonpath='{.spec.type}' | grep -qx NodePort" 40
wait_for "$K get pods -A --no-headers | grep -v Running | wc -l | grep -qx 0" 40
echo "Setup done. Read README.md and start. Grade with ./check.sh"
