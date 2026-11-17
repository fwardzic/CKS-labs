# Day 13 solution

## Task 1

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: vault-client
spec:
  serviceAccountName: app
  automountServiceAccountToken: false
  containers:
  - name: client
    image: busybox:1.37
    command: ["sleep", "1d"]
    volumeMounts:
    - name: vault-token
      mountPath: /var/run/secrets/tokens
      readOnly: true
  volumes:
  - name: vault-token
    projected:
      sources:
      - serviceAccountToken:
          path: vault-token
          audience: vault
          expirationSeconds: 3600
```

```sh
k -n vault-client exec client -- cat /var/run/secrets/tokens/vault-token | cut -d. -f2 | base64 -d 2>/dev/null; echo
# {"aud":["vault"],"exp":...,"iat":...,...}   exp - iat = 3600
k -n vault-client exec client -- ls /var/run/secrets/kubernetes.io/serviceaccount   # No such file or directory
```

## Task 2

```sh
k -n one get secrets --field-selector type=Opaque -o json | jq -r '.items[].data[] | @base64d' > /root/day13/one.txt
cat /root/day13/one.txt      # 3f9a-alpha, Gr33n!Lake, svc-report

k -n ns-secure create sa secret-manager
k -n ns-secure get secret sec-a1 -o jsonpath='{.data}'; echo    # key: token
k -n ns-secure run secret-manager --image httpd:alpine --dry-run=client -o yaml > sm.yaml
```

Edit `sm.yaml`:

```yaml
spec:
  serviceAccountName: secret-manager
  containers:
  - name: secret-manager
    image: httpd:alpine
    env:
    - name: SEC_A1
      valueFrom:
        secretKeyRef:
          name: sec-a1
          key: token
    volumeMounts:
    - name: sec-a2
      mountPath: /etc/sec-a2
      readOnly: true
  volumes:
  - name: sec-a2
    secret:
      secretName: sec-a2
```

```sh
k apply -f sm.yaml
k -n ns-secure exec secret-manager -- sh -c 'echo $SEC_A1; cat /etc/sec-a2/config.ini; touch /etc/sec-a2/x'
```

## Task 3

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: np
  namespace: space1
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: space2
  - ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: np
  namespace: space2
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: space1
```

"DNS for every Pod" only matters on the egress side: `space2` has no egress restriction, and its ingress rule doesn't affect DNS responses (they are reply traffic).

```sh
k -n space1 exec client -- wget -qO- -T 2 web.space2    # ok
k -n space1 exec client -- wget -qO- -T 2 web.other     # timeout
k -n other  exec client -- wget -qO- -T 2 web.space2    # timeout
k -n space2 exec client -- wget -qO- -T 2 web.other     # ok
```

## Task 4

```sh
k get svc kubernetes        # NodePort 443:31000
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
sed -i '/--kubernetes-service-node-port/d' /etc/kubernetes/manifests/kube-apiserver.yaml
watch crictl ps            # wait for the new kube-apiserver, then k -n kube-system get pod kube-apiserver-cks-cp shows 1/1
k delete svc kubernetes    # recreated by the API server as ClusterIP
k get svc kubernetes

k get clusterrolebindings -o wide | grep system:authenticated
# secret-auditor   ClusterRole/secret-auditor ... system:authenticated
k delete clusterrolebinding secret-auditor
k auth can-i list secrets -A --as nobody --as-group system:authenticated   # no
```

## Task 5

```sh
cd /root/day13
openssl genrsa -out bob.key 2048
openssl req -new -key bob.key -out bob.csr -subj "/CN=bob/O=platform"
openssl x509 -req -in bob.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial -out bob.crt -days 30
openssl x509 -in bob.crt -noout -subject -issuer -enddate

K=bob.kubeconfig
k config --kubeconfig $K set-cluster cks --server https://$(hostname -I | cut -d" " -f1):6443 \
  --certificate-authority /etc/kubernetes/pki/ca.crt --embed-certs
k config --kubeconfig $K set-credentials bob --client-certificate bob.crt --client-key bob.key --embed-certs
k config --kubeconfig $K set-context bob@cks --cluster cks --user bob
k config --kubeconfig $K use-context bob@cks

k create clusterrolebinding platform-view --clusterrole view --group platform
k --kubeconfig $K auth whoami         # bob, groups [platform system:authenticated]
k --kubeconfig $K get pods -A
```

The server address is the one in `/etc/kubernetes/admin.conf` (`grep server /etc/kubernetes/admin.conf`).
