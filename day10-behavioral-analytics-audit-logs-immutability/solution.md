# Day 10 solution

## Task 1

On `cks-worker`:

```sh
journalctl -u falco-modern-bpf --since "-5min" | grep -i sensitive | tail -2
# ... file=/etc/shadow ... k8s_pod_name=collector-xxxx k8s_ns_name=ops
```

On `cks-cp`:

```sh
k -n ops scale deploy collector --replicas 0
```

On `cks-worker`, append to `/etc/falco/falco_rules.local.yaml`:

```yaml
- rule: Package manager in container
  desc: A package manager was executed inside a container
  condition: spawned_process and container and proc.name in (apk, apt, apt-get, dpkg, yum, dnf)
  output: "Package manager in container | time=%evt.time container=%container.name pod=%k8s.pod.name ns=%k8s.ns.name cmd=%proc.cmdline"
  priority: WARNING
```

In `/etc/falco/falco.yaml`:

```yaml
file_output:
  enabled: true
  keep_alive: false
  filename: /var/log/falco/alerts.log
```

```sh
mkdir -p /var/log/falco
falco --dry-run                        # rules + config load
systemctl restart falco-modern-bpf
sleep 20; grep 'Package manager' /var/log/falco/alerts.log | tail -1
grep 'Package manager' /var/log/falco/alerts.log | tail -1 | grep -o 'pod=[^ ]*' | cut -d= -f2 > /root/day10/pkg-pod.txt
```

## Task 2

```sh
mkdir -p /etc/kubernetes/audit
vim /etc/kubernetes/audit/policy.yaml
```

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
- RequestReceived
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets"]
- level: RequestResponse
  namespaces: ["ops"]
  resources:
  - group: ""
    resources: ["configmaps"]
- level: None
```

kube-apiserver manifest (back it up first):

```yaml
    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit/audit.log
    - --audit-log-maxage=7
    - --audit-log-maxbackup=2
...
    volumeMounts:
    - name: audit-policy
      mountPath: /etc/kubernetes/audit/policy.yaml
      readOnly: true
    - name: audit-log
      mountPath: /var/log/kubernetes/audit
...
  volumes:
  - name: audit-policy
    hostPath:
      path: /etc/kubernetes/audit/policy.yaml
      type: File
  - name: audit-log
    hostPath:
      path: /var/log/kubernetes/audit
      type: DirectoryOrCreate
```

```sh
k -n ops get secret app-secret
tail -3 /var/log/kubernetes/audit/audit.log | jq -c '{level, verb, res: .objectRef.resource, ns: .objectRef.namespace}'
```

## Task 3

```sh
k -n ops edit deploy frontend
```

```yaml
    spec:
      containers:
      - name: nginx
        image: nginx:1.29-alpine
        securityContext:
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
      - name: tmp
        emptyDir: {}
```

Without the `emptyDir`s the pod crashes: `mkdir() "/var/cache/nginx/client_temp" failed (30: Read-only file system)`.
