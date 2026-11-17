# Day 7 solution

## Task 1

```sh
k label ns payments pod-security.kubernetes.io/enforce=restricted
k label ns legacy pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted pod-security.kubernetes.io/audit=restricted
k -n payments edit deploy pay
```

```yaml
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: app
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
```

`nginxinc/nginx-unprivileged` already runs as UID 101 on port 8080, so nothing else is needed.

## Task 2

```sh
k -n legacy get secret admin-creds -o jsonpath='{.data.password}' | base64 -d > /root/day7/password.txt
k -n payments create secret generic db-creds --from-literal=user=pay --from-literal='pass=S3cr3t!'
k -n payments set env deploy/pay DB_PASSWORD-
k -n payments edit deploy pay
```

```yaml
      containers:
      - name: app
        volumeMounts:
        - name: db
          mountPath: /etc/db
          readOnly: true
      volumes:
      - name: db
        secret:
          secretName: db-creds
```

## Task 3

```sh
mkdir -p /etc/kubernetes/enc
head -c 32 /dev/urandom | base64
vim /etc/kubernetes/enc/enc.yaml
```

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <base64 32-byte key>
  - identity: {}
```

kube-apiserver manifest (back it up first):

```yaml
    - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml
...
    volumeMounts:
    - name: enc
      mountPath: /etc/kubernetes/enc
      readOnly: true
...
  volumes:
  - name: enc
    hostPath:
      path: /etc/kubernetes/enc
      type: DirectoryOrCreate
```

```sh
# wait for the API server, then rewrite every secret so it is stored with the new provider
k get secrets -A -o json | k replace -f -

etcdctl --endpoints https://127.0.0.1:2379 \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/server.crt \
  --key /etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/payments/db-creds | hexdump -C | head
# ... k8s:enc:aescbc:v1:key1: ...
```
