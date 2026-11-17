#!/usr/bin/env bash
# Run on the Mac. Day 3: CIS benchmark, Ingress TLS, binary verification.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

INGRESS_NGINX=controller-v1.15.1

echo "[cp] CIS regressions"
remote "$CP" <<'EOF'
set -euo pipefail
chmod 644 /etc/kubernetes/manifests/kube-apiserver.yaml
chmod 755 /var/lib/etcd
sed -i 's#--authorization-mode=Node,RBAC#--authorization-mode=AlwaysAllow#' /etc/kubernetes/manifests/kube-apiserver.yaml
grep -q -- '--authorization-mode=AlwaysAllow' /etc/kubernetes/manifests/kube-apiserver.yaml
EOF
echo "[cp] waiting for kube-apiserver restart"
sleep 20
wait_for "$K get --raw /readyz" 80

echo "[cp] ingress-nginx + shop app"
remote "$CP" <<EOF
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX}/deploy/static/provider/baremetal/deploy.yaml >/dev/null
kubectl -n ingress-nginx patch svc ingress-nginx-controller --type=json -p '[
  {"op":"replace","path":"/spec/ports/0/nodePort","value":30080},
  {"op":"replace","path":"/spec/ports/1/nodePort","value":30443}]'
kubectl -n ingress-nginx rollout status deploy ingress-nginx-controller --timeout=300s
kubectl create ns shop
kubectl -n shop create configmap shop-page --from-literal=index.html='shop ok'
kubectl -n shop create deployment shop --image=nginx:1.27-alpine --port 80
kubectl -n shop set volume deploy/shop --add --name page --type configmap --configmap-name shop-page --mount-path /usr/share/nginx/html >/dev/null 2>&1 ||
  kubectl -n shop patch deploy shop --type=json -p '[
    {"op":"add","path":"/spec/template/spec/volumes","value":[{"name":"page","configMap":{"name":"shop-page"}}]},
    {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts","value":[{"name":"page","mountPath":"/usr/share/nginx/html"}]}]'
kubectl -n shop expose deploy shop --port 80
kubectl -n shop rollout status deploy shop --timeout=180s
EOF

echo "[worker] candidate binaries in /opt/binaries"
remote "$WORKER" <<'EOF'
set -euo pipefail
d=/opt/binaries
rm -rf "$d"; mkdir -p "$d"; cd "$d"
base=https://dl.k8s.io/release
curl -fsSL -o kubectl-1 "$base/v1.35.9/bin/linux/arm64/kubectl"
curl -fsSL -o kubectl-2 "$base/v1.35.8/bin/linux/arm64/kubectl"
cp kubectl-1 kubectl-3 && printf '\0' >>kubectl-3
chmod +x kubectl-*
EOF
echo "Setup done. Read README.md and start. Grade with ./check.sh"
