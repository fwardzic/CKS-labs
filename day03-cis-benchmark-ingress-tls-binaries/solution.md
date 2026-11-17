# Day 3 solution

## Task 1

```sh
multipass shell cks-cp; sudo -i
kube-bench run --targets master --check 1.1.1,1.1.11,1.1.12,1.2.6,1.2.7,1.2.8,1.2.15,1.3.2,1.4.1
cd /etc/kubernetes/manifests
cp kube-apiserver.yaml kube-controller-manager.yaml kube-scheduler.yaml /root/
```

| Check | Fix |
|---|---|
| 1.1.1 | `chmod 600 /etc/kubernetes/manifests/kube-apiserver.yaml` |
| 1.1.11 | `chmod 700 /var/lib/etcd` |
| 1.1.12 | `useradd -r -s /usr/sbin/nologin etcd; chown -R etcd:etcd /var/lib/etcd` |
| 1.2.6 / 1.2.7 / 1.2.8 | kube-apiserver: `- --authorization-mode=Node,RBAC` (was `AlwaysAllow`) |
| 1.2.15 | kube-apiserver: add `- --profiling=false` |
| 1.3.2 | kube-controller-manager: add `- --profiling=false` |
| 1.4.1 | kube-scheduler: add `- --profiling=false` |

Wait for `crictl ps` to show all four control plane containers running, then re-run kube-bench.

## Task 2

```sh
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout shop.key -out shop.crt \
  -subj "/CN=shop.cks.local" -addext "subjectAltName=DNS:shop.cks.local"
k -n shop create secret tls shop-tls --cert shop.crt --key shop.key
k -n shop create ingress shop --class nginx --rule "shop.cks.local/*=shop:80,tls=shop-tls"
```

Equivalent YAML:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  namespace: shop
spec:
  ingressClassName: nginx
  tls:
  - hosts: [shop.cks.local]
    secretName: shop-tls
  rules:
  - host: shop.cks.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: shop
            port:
              number: 80
```

The HTTP → HTTPS redirect (308) is ingress-nginx's default once an Ingress has `tls` (`ssl-redirect: true`). To set it explicitly: annotation `nginx.ingress.kubernetes.io/ssl-redirect: "true"`.

## Task 3

```sh
multipass shell cks-worker; sudo -i
cd /opt/binaries
curl -LO https://dl.k8s.io/release/v1.35.9/bin/linux/arm64/kubectl.sha512
cat kubectl.sha512; sha512sum kubectl-*
# or per file:
echo "$(cat kubectl.sha512)  kubectl-1" | sha512sum -c
rm kubectl-2 kubectl-3        # kubectl-2 is v1.35.8, kubectl-3 is tampered (one extra byte)
```
