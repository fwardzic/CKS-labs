# Day 4 solution

## Task 1

```sh
k get clusterrolebindings -o wide | grep report-bot      # find every binding of the SA
k delete clusterrolebinding report-bot-admin
k -n finance create role report-reader --verb get,list,watch --resource pods,pods/log,configmaps
k -n finance create rolebinding report-bot --role report-reader --serviceaccount finance:report-bot
k auth can-i --list -n finance --as system:serviceaccount:finance:report-bot
```

## Task 2

```sh
k -n finance create sa legacy-sa
k -n finance patch sa legacy-sa -p '{"automountServiceAccountToken": false}'
k -n finance patch sa default   -p '{"automountServiceAccountToken": false}'
k -n finance set serviceaccount deploy legacy legacy-sa
k -n finance get secret --field-selector type=kubernetes.io/service-account-token
k -n finance delete secret old-ci-token
k -n finance exec deploy/legacy -- ls /var/run/secrets/kubernetes.io/serviceaccount   # must fail
```

`automountServiceAccountToken` can also be set in the pod spec; the pod setting wins over the SA.

## Task 3

```sh
cd /root/day4
openssl genrsa -out jane.key 2048
openssl req -new -key jane.key -out jane.csr -subj "/CN=jane"
cat <<EOF | k apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: jane
spec:
  request: $(base64 -w0 jane.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: [client auth]
EOF
k certificate approve jane
k get csr jane -o jsonpath='{.status.certificate}' | base64 -d > jane.crt

k config set-cluster kubernetes --server https://<cp-ip>:6443 \
  --certificate-authority /etc/kubernetes/pki/ca.crt --embed-certs --kubeconfig jane.kubeconfig
k config set-credentials jane --client-certificate jane.crt --client-key jane.key \
  --embed-certs --kubeconfig jane.kubeconfig
k config set-context jane --cluster kubernetes --user jane --kubeconfig jane.kubeconfig
k config use-context jane --kubeconfig jane.kubeconfig

k -n dev create role deploy-editor --verb get,list,watch,create,update,patch --resource deployments
k -n dev create rolebinding jane --role deploy-editor --user jane
k --kubeconfig jane.kubeconfig auth whoami
```

Docs: "Certificate Signing Requests" → "How to issue a certificate for a user" has every command above.

## Task 4

```sh
k get clusterrolebindings -o json | jq -r '.items[] | select(.subjects[]?.name=="system:anonymous") | .metadata.name'
k delete clusterrolebinding anon-view
```

kube-apiserver manifest:

```
- --enable-admission-plugins=NodeRestriction
```

Do **not** set `--anonymous-auth=false` here. kubeadm's probes call `/livez` and `/readyz` without credentials, so they get 401. Tested on this cluster: the pod goes `READY 0/1` at once, the API keeps answering for ~4 minutes (startupProbe `failureThreshold: 24` x `periodSeconds: 10`), then the kubelet kills it and it restarts in a loop. Easy to miss in the exam if you move on quickly.

RBAC (no bindings for `system:anonymous` beyond the default health/discovery access) is the right fix. To restrict anonymous access to the health endpoints only (stable since v1.34), point `--authentication-config` at an `AuthenticationConfiguration` (add a hostPath volume + volumeMount for the file, like any API server config file) and remove `--anonymous-auth`:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AuthenticationConfiguration
anonymous:
  enabled: true
  conditions:
  - path: /livez
  - path: /readyz
  - path: /healthz
```

Docs: "Authenticating" → anonymous authenticator configuration.
