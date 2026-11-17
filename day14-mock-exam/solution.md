# Day 14 solution (mock exam)

## Task 1 - RBAC

```sh
k -n mock-ops delete role automation
k -n mock-ops create role automation --verb get,list,watch,update,patch --resource deployments.apps $do > r.yaml
```

Add a second rule to `r.yaml`, then `k apply -f r.yaml`:

```yaml
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
```

```sh
k auth can-i --list -n mock-ops --as system:serviceaccount:mock-ops:automation
k delete clusterrolebinding viewer-view
k -n mock-ops create rolebinding viewer-view --clusterrole view --serviceaccount mock-ops:viewer
```

A RoleBinding can reference a ClusterRole: the permissions then only apply in the RoleBinding's namespace.

## Task 2 - NetworkPolicy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny, namespace: mock-db}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: db-access, namespace: mock-db}
spec:
  podSelector:
    matchLabels: {app: db}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:            # one element: namespace AND pod label
        matchLabels: {kubernetes.io/metadata.name: mock-app}
      podSelector:
        matchLabels: {app: backend}
    ports:
    - {protocol: TCP, port: 80}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-dns, namespace: mock-db}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels: {kubernetes.io/metadata.name: kube-system}
      podSelector:
        matchLabels: {k8s-app: kube-dns}
    ports:
    - {protocol: UDP, port: 53}
    - {protocol: TCP, port: 53}
```

## Task 3 - Pod Security

```sh
k label ns mock-app pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest pod-security.kubernetes.io/warn=restricted
k -n mock-app edit deploy backend
```

```yaml
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile: {type: RuntimeDefault}
      containers:
      - name: busybox
        securityContext:
          allowPrivilegeEscalation: false
          capabilities: {drop: ["ALL"]}
```

```sh
k -n mock-app get rs        # new RS has pods; FailedCreate events if something is missing
k label --dry-run=server --overwrite ns mock-app pod-security.kubernetes.io/enforce=restricted   # no warnings
```

## Task 4 - API server

`/etc/kubernetes/audit/policy.yaml`:

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: ["RequestReceived"]
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets", "configmaps"]
- level: RequestResponse
  resources:
  - group: rbac.authorization.k8s.io
- level: Metadata
  resources:
  - group: ""
    resources: ["pods/exec", "pods/attach"]
- level: None
```

kube-apiserver manifest (back it up first, outside `manifests/`):

```yaml
    - --profiling=false
    - --tls-min-version=VersionTLS12
    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit/audit.log
    - --audit-log-maxage=10
    - --audit-log-maxbackup=3
    - --audit-log-maxsize=100
...
    volumeMounts:
    - {mountPath: /etc/kubernetes/audit/policy.yaml, name: audit-policy, readOnly: true}
    - {mountPath: /var/log/kubernetes/audit, name: audit-log}
...
  volumes:
  - {name: audit-policy, hostPath: {path: /etc/kubernetes/audit/policy.yaml, type: File}}
  - {name: audit-log, hostPath: {path: /var/log/kubernetes/audit, type: DirectoryOrCreate}}
```

## Task 5 - Encryption at rest

```sh
mkdir -p /etc/kubernetes/enc
head -c 32 /dev/urandom | base64
```

`/etc/kubernetes/enc/enc.yaml`:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources: ["secrets"]
  providers:
  - aesgcm:
      keys:
      - name: k1
        secret: <base64 key>
  - identity: {}
```

Manifest: `- --encryption-provider-config=/etc/kubernetes/enc/enc.yaml`, plus mount `/etc/kubernetes/enc` (hostPath + volumeMount, readOnly). When the API server is back:

```sh
k get secrets -A -o json | k replace -f -
etcdctl --endpoints https://127.0.0.1:2379 --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/server.crt --key /etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/mock-ops/ops-token | hexdump -C | head -3     # k8s:enc:aesgcm:v1:k1:
```

## Task 6 - AppArmor and seccomp

On `cks-worker`:

```sh
grep ^profile /opt/mock/apparmor/deny-etc-write      # name is mock-deny-etc, not the file name
apparmor_parser -r /opt/mock/apparmor/deny-etc-write
aa-status | grep mock-deny-etc
mkdir -p /var/lib/kubelet/seccomp/profiles
cp /opt/mock/seccomp/block-mkdir.json /var/lib/kubelet/seccomp/profiles/
```

```yaml
apiVersion: v1
kind: Pod
metadata: {name: guarded, namespace: mock-sys}
spec:
  nodeName: cks-worker
  containers:
  - name: c
    image: busybox:1.37
    command: ["sleep", "1d"]
    securityContext:
      appArmorProfile: {type: Localhost, localhostProfile: mock-deny-etc}
---
apiVersion: v1
kind: Pod
metadata: {name: nomkdir, namespace: mock-sys}
spec:
  nodeName: cks-worker
  securityContext:
    seccompProfile: {type: Localhost, localhostProfile: profiles/block-mkdir.json}
  containers:
  - name: c
    image: busybox:1.37
    command: ["sleep", "1d"]
```

## Task 7 - Sandbox

On `cks-worker`, in `/etc/containerd/config.toml` next to the `runc` runtime block:

```toml
        [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc]
          runtime_type = 'io.containerd.runsc.v1'
```

```sh
systemctl restart containerd
```

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: {name: sandbox}
handler: runsc
---
apiVersion: v1
kind: Pod
metadata: {name: untrusted, namespace: mock-sys}
spec:
  runtimeClassName: sandbox
  nodeName: cks-worker
  containers:
  - name: c
    image: nginx:1.29-alpine
```

```sh
k -n mock-sys exec untrusted -- dmesg | head -1     # Starting gVisor...
```

## Task 8 - Falco

On `cks-worker`, append to `/etc/falco/falco_rules.local.yaml`:

```yaml
- rule: Netcat in container
  desc: netcat started inside a container
  condition: spawned_process and container and proc.name in (nc, ncat, netcat)
  output: "Netcat in container | pod=%k8s.pod.name ns=%k8s.ns.name image=%container.image.repository cmd=%proc.cmdline"
  priority: CRITICAL
```

```sh
systemctl restart falco-modern-bpf
journalctl -u falco-modern-bpf -f | grep Netcat     # pod=probe-... ns=mock-runtime
k -n mock-runtime scale deploy probe --replicas 0
```

## Task 9 - Trivy

```sh
for i in $(k -n mock-scan get pods -o jsonpath='{range .items[*]}{.metadata.name}={.spec.containers[0].image}{"\n"}{end}'); do
  echo "$i $(trivy image -q --severity CRITICAL --format json ${i#*=} | jq '[.Results[]?.Vulnerabilities[]?] | length')"
done
k -n mock-scan delete pod proxy      # nginx:1.21-alpine
```

## Task 10 - Signed binaries

```sh
cd /opt/mock/release
for f in kube-tool-v1.1 kube-tool-v1.2 kube-tool-v1.3; do
  echo "== $f"; cosign verify-blob --key cosign.pub --bundle $f.bundle --insecure-ignore-tlog=true $f
done
# v1.1: invalid signature (file modified after signing), v1.3: signed with a different key
rm kube-tool-v1.1 kube-tool-v1.1.bundle kube-tool-v1.3 kube-tool-v1.3.bundle
sha512sum kube-tool-v1.2 > /root/mock/kube-tool.sha512
```

## Task 11 - Ephemeral container

```sh
k -n mock-debug debug legacy-api -it -c debugger --image busybox:1.37 --target app --profile restricted -- sh
# inside: cat /proc/1/cmdline      -> /pause
```

Without `--profile restricted`, PSA rejects the ephemeral container (`allowPrivilegeEscalation`, `capabilities`). Non-interactive variant:

```sh
k -n mock-debug debug legacy-api -c debugger --image busybox:1.37 --target app --profile restricted -- sleep 1d
k -n mock-debug exec legacy-api -c debugger -- cat /proc/1/cmdline > /root/mock/legacy-cmdline.txt
```

## Task 12 - ValidatingAdmissionPolicy

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata: {name: require-limits}
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  validations:
  - expression: "object.spec.containers.all(c, has(c.resources.limits) && 'cpu' in c.resources.limits && 'memory' in c.resources.limits)"
    message: "every container needs cpu and memory limits"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata: {name: require-limits}
spec:
  policyName: require-limits
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels: {env: prod}
```

```sh
k -n mock-prod set resources deploy api --limits=cpu=200m,memory=128Mi
k -n mock-prod run t --image nginx --dry-run=server     # denied
```

## Task 13 - Risky workloads

```sh
k get deploy -A -o json | jq -r '.items[] | select(.metadata.namespace != "kube-system")
  | select(.spec.template.spec.hostPID == true or any(.spec.template.spec.containers[]; .securityContext.privileged == true))
  | .metadata.namespace + "/" + .metadata.name' | tee /root/mock/risky.txt
# mock-legacy/fs-agent, mock-legacy/metrics, mock-runtime/debug-shell (hostPID; its SYS_ADMIN is a distraction)
while read d; do k -n ${d%/*} scale deploy ${d#*/} --replicas 0; done < /root/mock/risky.txt
```

`mock-legacy/web`: `readOnlyRootFilesystem: true` plus `emptyDir` on `/var/cache/nginx`, `/var/run` and `/tmp` (as on Day 10).

## Task 14 - kubelet

On `cks-worker`, `/var/lib/kubelet/config.yaml`:

```yaml
authentication:
  anonymous:
    enabled: false
authorization:
  mode: Webhook
readOnlyPort: 0
```

```sh
chmod 600 /var/lib/kubelet/config.yaml
systemctl restart kubelet
curl -sk https://localhost:10250/pods     # 401 Unauthorized
```

## Task 15 - CSR API

```sh
cd /root/mock
openssl genrsa -out auditor.key 2048
openssl req -new -key auditor.key -out auditor.csr -subj /CN=auditor
cat <<Y | k apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: auditor
spec:
  request: $(base64 -w0 auditor.csr)
  signerName: kubernetes.io/kube-apiserver-client
  usages: [client auth]
Y
k certificate approve auditor
k get csr auditor -o jsonpath='{.status.certificate}' | base64 -d > auditor.crt

K=auditor.kubeconfig
k config --kubeconfig $K set-cluster cks --server https://$(hostname -I | cut -d" " -f1):6443 --certificate-authority /etc/kubernetes/pki/ca.crt --embed-certs
k config --kubeconfig $K set-credentials auditor --client-certificate auditor.crt --client-key auditor.key --embed-certs
k config --kubeconfig $K set-context auditor --cluster cks --user auditor
k config --kubeconfig $K use-context auditor

k create clusterrole auditor --verb get,list --resource pods,events
k create clusterrolebinding auditor --clusterrole auditor --user auditor
```
