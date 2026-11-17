# Day 1 solution

## Task 1

```sh
sudo -i
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
crictl ps -a --name kube-apiserver          # Exited, restarting
tail /var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/*.log
#  "command failed" err="enable-admission-plugins plugin \"PodSecurityPolicy\" is unknown"
```

PodSecurityPolicy was removed in Kubernetes 1.25 (replaced by Pod Security Admission). Remove it:

```
- --enable-admission-plugins=NodeRestriction
```

Wait for the next restart and read the newest log file again (`ls -t .../kube-apiserver/`):

```
Error creating leases: error creating storage factory: open /etc/kubernetes/pki/etcd/apiserver-etcd-client.crt: no such file or directory
```

The etcd **client** cert for the API server lives in `/etc/kubernetes/pki/`, not `pki/etcd/` (`ls /etc/kubernetes/pki/`):

```
- --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
```

Save both lines in `/root/day1/apiserver-errors.txt`. Wait until `kubectl get --raw /readyz` returns `ok`.

## Task 2

```sh
multipass shell cks-worker; sudo -i
systemctl cat kubelet | grep -- --config     # /var/lib/kubelet/config.yaml
vim /var/lib/kubelet/config.yaml
```

```yaml
authentication:
  anonymous:
    enabled: false        # was true
authorization:
  mode: Webhook           # was AlwaysAllow
readOnlyPort: 0           # or delete the line (default 0)
```

```sh
systemctl restart kubelet && systemctl status kubelet
# from cks-cp:
curl -sk https://<worker-ip>:10250/pods     # 401 Unauthorized
curl -s  http://<worker-ip>:10255/pods      # connection refused
```

Docs: "Kubelet authentication/authorization" (`reference/access-authn-authz/kubelet-authn-authz/`).

## Task 3

```sh
k get pods -A -o json | jq -r '.items[] | select(.spec.volumes[]?.hostPath.path=="/") | "\(.metadata.namespace)/\(.metadata.name) \(.spec.nodeName)"'
# default/node-debugger-cks-worker cks-worker
```

The `-cks-worker` suffix means it is a **mirror pod** of a static pod: `k delete` only recreates it. On `cks-worker`:

```sh
grep -l node-debugger /etc/kubernetes/manifests/*     # or: staticPodPath in the kubelet config
mv /etc/kubernetes/manifests/node-debugger.yaml /root/
```
