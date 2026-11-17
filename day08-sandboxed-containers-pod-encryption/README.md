# Day 8: Isolation and Pod-to-Pod encryption (gVisor, Cilium, Istio)

Suggested time: 40 minutes.

## Start

```sh
../cluster/reset.sh
./setup.sh               # ~3 min (installs Istio)
./check.sh
```

Reference solution: `solution.md`.

---

## Task 1 (6%) - Sandboxed containers

gVisor (`runsc`, `containerd-shim-runsc-v1`) is installed on `cks-worker` but containerd does not know about it.

1. Register a containerd runtime handler `runsc` on `cks-worker`.
2. Create a RuntimeClass `gvisor` that uses it.
3. Create a Pod `sandboxed` in namespace `isolated` (image `nginx:1.27-alpine`) on `cks-worker` that runs in gVisor.

All other pods must keep using the default runtime.

## Task 2 (6%) - Cilium transparent encryption

Enable Cilium's transparent encryption with **WireGuard** for all pod traffic between nodes. Cilium was installed with Helm (release `cilium` in `kube-system`, chart version `1.20.3`). Verify that both agents report WireGuard with a peer.

## Task 3 (6%) - Istio mTLS

Istio is installed. Namespace `mesh` has Deployments `web` (Service `web:80`) and `client`.

1. Enable automatic sidecar injection for namespace `mesh` and make sure all its pods get a sidecar.
2. Enforce **STRICT** mutual TLS for every workload in `mesh`.

`mesh/client` must still reach `http://web.mesh`. Pods outside the mesh (e.g. `outside/client`) must be rejected.

---

## Exam habits to practise today

- **containerd config version matters.** Look at the top of `/etc/containerd/config.toml`:
  - `version = 2` (containerd 1.x): `[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]`
  - `version = 3` (containerd 2.x, this lab): `[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc]`

  Copy the neighbouring `runc` block and change the name and `runtime_type = 'io.containerd.runsc.v1'`. Then `systemctl restart containerd` and `crictl info | grep runsc`.
- The RuntimeClass `handler` must equal the containerd runtime name (`runsc`), not the RuntimeClass name.
- Prove gVisor: `k exec <pod> -- dmesg` prints `Starting gVisor...`; under runc, `dmesg` fails or shows the host kernel.
- Cilium config changes through Helm or `cilium upgrade` update the ConfigMap but **the agents only read it on start**: `k -n kube-system rollout restart ds/cilium`. Verify with `k -n kube-system exec ds/cilium -- cilium-dbg status | grep Encryption` or `cilium-dbg encrypt status`.
- Docs: docs.cilium.io → Security → Transparent Encryption → WireGuard (Helm values `encryption.enabled=true`, `encryption.type=wireguard`).
- Istio: label `istio-injection=enabled` only affects **new** pods: `k rollout restart deploy -n <ns>`. Check for `2/2` READY.
- `PeerAuthentication` named `default` without a `selector` in a namespace = namespace-wide policy. In `istio-system` = mesh-wide. Docs: istio.io → Tasks → Security → Authentication → "Mutual TLS Migration".
