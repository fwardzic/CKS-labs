# Day 8 solution

## Task 1

On `cks-worker`:

```sh
head -1 /etc/containerd/config.toml             # version = 3
cp /etc/containerd/config.toml /root/
vim /etc/containerd/config.toml
```

Next to the existing `runc` block add:

```toml
        [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc]
          runtime_type = 'io.containerd.runsc.v1'
```

```sh
systemctl restart containerd
crictl info | grep -A2 runsc
```

On `cks-cp`:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
---
apiVersion: v1
kind: Pod
metadata:
  name: sandboxed
  namespace: isolated
spec:
  runtimeClassName: gvisor
  nodeName: cks-worker
  containers:
  - name: c
    image: nginx:1.27-alpine
```

```sh
k -n isolated exec sandboxed -- dmesg | head -2     # Starting gVisor...
```

## Task 2

Either with the cilium CLI:

```sh
cilium upgrade --version 1.20.3 --reuse-values --set encryption.enabled=true --set encryption.type=wireguard
```

or with Helm:

```sh
helm repo add cilium https://helm.cilium.io && helm repo update
helm upgrade cilium cilium/cilium -n kube-system --version 1.20.3 --reuse-values \
  --set encryption.enabled=true --set encryption.type=wireguard
```

Then restart the agents and verify:

```sh
k -n kube-system rollout restart ds/cilium
k -n kube-system rollout status ds/cilium
k -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep Encryption
# Encryption: Wireguard [... cilium_wg0 (... Peers: 1)]
```

## Task 3

```sh
k label ns mesh istio-injection=enabled
k -n mesh rollout restart deploy
k -n mesh get pods                       # 2/2
```

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: mesh
spec:
  mtls:
    mode: STRICT
```

```sh
k -n mesh exec deploy/client -- curl -s http://web.mesh          # works
k -n outside exec deploy/client -- curl -s http://web.mesh       # connection reset
```
