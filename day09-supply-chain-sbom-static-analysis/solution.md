# Day 9 solution

## Task 1

```sh
k -n team-x get pods -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[*].image}{"\n"}{end}'
for img in nginx:1.19-alpine httpd:2.4.46-alpine nginx:1.29-alpine redis:7.4-alpine busybox:1.37; do
  echo "$img $(trivy image -q --severity CRITICAL --format json $img | jq '[.Results[]?.Vulnerabilities[]?] | length')"
done
k -n team-x delete pod web-old httpd        # on 2026-10-23: nginx:1.19-alpine 9, httpd:2.4.46-alpine 13
```

The vulnerability DB changes daily; trust your scan, not this list.

## Task 2

```sh
cd /root/day9
bom generate --image nginx:1.29-alpine --format json --output nginx.spdx.json
trivy image --format cyclonedx --output nginx.cdx.json nginx:1.29-alpine
jq -r '.components[] | select(.name=="libssl3") | .version' nginx.cdx.json > libssl3.txt
# or: grep -A3 '"name": "libssl3"' nginx.cdx.json
```

## Task 3

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tools
  namespace: supply
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tools
  template:
    metadata:
      labels:
        app: tools
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: tools
        image: docker.io/library/busybox:1.37
        command: ["sleep", "1d"]
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 100m
            memory: 32Mi
```

`hostPID`, `privileged` and `SYS_ADMIN` are gone. kubesec score 11, kube-linter "No lint errors found!".

## Task 4

```sh
sed -i 's/defaultAllow: true/defaultAllow: false/' /etc/kubernetes/policywebhook/admission_config.yaml
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

```yaml
    - --enable-admission-plugins=NodeRestriction,ImagePolicyWebhook
    - --admission-control-config-file=/etc/kubernetes/policywebhook/admission_config.yaml
...
    volumeMounts:
    - name: policywebhook
      mountPath: /etc/kubernetes/policywebhook
      readOnly: true
...
  volumes:
  - name: policywebhook
    hostPath:
      path: /etc/kubernetes/policywebhook
      type: DirectoryOrCreate
```

```sh
k run t1 --image nginx:latest --dry-run=server        # denied: uses the latest tag
k run t2 --image nginx:1.29-alpine --dry-run=server   # allowed
```

## Task 5

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: allowed-registries
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  validations:
  - expression: "object.spec.containers.all(c, c.image.startsWith('registry.k8s.io/') || c.image.startsWith('docker.io/library/'))"
    message: "images must come from registry.k8s.io/ or docker.io/library/"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: allowed-registries
spec:
  policyName: allowed-registries
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: supply
```
