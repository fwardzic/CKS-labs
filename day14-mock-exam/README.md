# Day 14: Mock exam

**Time limit: 2 hours.** 15 tasks, weighted like the real exam. Pass mark: **67%**. Set a timer, don't open `solution.md` until it rings, and skip tasks that take too long. `check.sh` prints a weighted score at the end.

## Start

```sh
../cluster/reset.sh
./setup.sh        # ~5 min
./check.sh
```

Nodes: `cks-cp` (control plane) and `cks-worker`. Unless a task says otherwise, work on `cks-cp` as root. Files you write go to `/root/mock/` on the node named in the task.

---

## Task 1 (4%) - RBAC

Namespace `mock-ops`:

1. Role `automation` (bound to ServiceAccount `automation`) allows everything. Change it so the ServiceAccount can only `get`, `list`, `watch`, `update` and `patch` Deployments, and `get` and `list` Pods in `mock-ops`. Nothing else.
2. ServiceAccount `viewer` must have the permissions of the ClusterRole `view` in namespace `mock-ops` only. Right now it has them cluster-wide through ClusterRoleBinding `viewer-view`. Replace that with a RoleBinding `viewer-view`.

## Task 2 (6%) - NetworkPolicy

Namespace `mock-db` runs Pods `db` and `cache` (nginx, port 80, Services with the same names).

1. NetworkPolicy `default-deny`: denies all ingress and egress for every Pod in `mock-db`.
2. NetworkPolicy `db-access`: Pods with `app=db` accept traffic only from Pods with `app=backend` in namespace `mock-app`, on TCP 80.
3. NetworkPolicy `allow-dns`: all Pods in `mock-db` can reach the cluster DNS (the `kube-dns` Pods in `kube-system`) on port 53, TCP and UDP.

## Task 3 (5%) - Pod Security

1. Namespace `mock-app` must **enforce** the `restricted` Pod Security Standard pinned to version `latest`, and **warn** at `restricted`.
2. Deployment `backend` in `mock-app` must keep running under that policy (keep its image and command), and its Pods must not get a ServiceAccount token.

## Task 4 (7%) - API server

On `cks-cp`, configure kube-apiserver:

1. Disable profiling. Accept TLS 1.2 as minimum version.
2. Enable audit logging: policy `/etc/kubernetes/audit/policy.yaml`, log `/var/log/kubernetes/audit/audit.log`, keep at most 10 days and 3 old files of at most 100 MB.
3. Policy:
   - `secrets` and `configmaps`: `Metadata`,
   - everything in API group `rbac.authorization.k8s.io`: `RequestResponse`,
   - `pods/exec` and `pods/attach`: `Metadata`,
   - nothing else, and never the `RequestReceived` stage.

## Task 5 (6%) - Encryption at rest

Encrypt Secrets in etcd with the `aesgcm` provider, key name `k1`, config file `/etc/kubernetes/enc/enc.yaml`. Unencrypted data must stay readable. Every existing Secret in the cluster must end up encrypted.

## Task 6 (6%) - AppArmor and seccomp

All Pods in namespace `mock-sys`, image `busybox:1.37`, command `sleep 1d`, scheduled on `cks-worker`.

1. Load the AppArmor profile in `/opt/mock/apparmor/deny-etc-write` on `cks-worker` (enforce mode). Create Pod `guarded` confined by it.
2. Install the seccomp profile `/opt/mock/seccomp/block-mkdir.json` on `cks-worker` as `profiles/block-mkdir.json`. Create Pod `nomkdir` using it.

## Task 7 (5%) - Sandbox

`runsc` (gVisor) is installed on `cks-worker` but containerd doesn't know about it yet.

1. Make containerd on `cks-worker` support the `runsc` handler.
2. Create RuntimeClass `sandbox` for it.
3. Create Pod `untrusted` in `mock-sys` (image `nginx:1.29-alpine`) running in the sandbox.

## Task 8 (6%) - Falco

On `cks-worker`, add a Falco rule `Netcat in container`, priority `CRITICAL`, that fires when a process named `nc`, `ncat` or `netcat` starts inside a container. Output must be exactly:

```
Netcat in container | pod=%k8s.pod.name ns=%k8s.ns.name image=%container.image.repository cmd=%proc.cmdline
```

Then find the Deployment in `mock-runtime` that runs netcat and scale it to 0.

## Task 9 (4%) - Image scanning

Delete every Pod in namespace `mock-scan` whose image has at least one `CRITICAL` vulnerability (use `trivy`). Leave the others.

## Task 10 (4%) - Signed binaries

`/opt/mock/release/` on `cks-cp` holds three builds of `kube-tool`, each with a cosign bundle (`<file>.bundle`), and the release public key `cosign.pub`. The signatures were not uploaded to a transparency log.

1. Delete every binary (and its bundle) whose signature doesn't verify against `cosign.pub`.
2. Write the `sha512sum` of the remaining binary to `/root/mock/kube-tool.sha512`.

## Task 11 (4%) - Debugging without a shell

Pod `legacy-api` in namespace `mock-debug` runs an image without a shell. Attach an ephemeral container named `debugger` (image `busybox:1.37`) that shares the process namespace of container `app`. From it, write the command line of the `app` process to `/root/mock/legacy-cmdline.txt`. Don't recreate the Pod.

## Task 12 (6%) - ValidatingAdmissionPolicy

1. Create ValidatingAdmissionPolicy `require-limits` and a binding `require-limits` that **denies** Pods in which any container lacks a CPU **and** memory limit. Apply it only to namespaces labelled `env=prod`.
2. Deployment `api` in `mock-prod` must run 2 Pods with limits `cpu: 200m`, `memory: 128Mi`.

## Task 13 (5%) - Risky workloads

1. Find every Deployment outside `kube-system` whose Pods run **privileged** or share the **host PID** namespace. Write them to `/root/mock/risky.txt` on `cks-cp`, one `<namespace>/<deployment>` per line, and scale them to 0.
2. Make Deployment `web` in `mock-legacy` immutable (read-only root filesystem). It must keep serving on port 80.

## Task 14 (6%) - kubelet

Fix the kubelet on `cks-worker`:

- anonymous requests rejected, authorization delegated to the API server,
- read-only port disabled,
- its config file only readable and writable by root.

The node must stay `Ready`.

## Task 15 (5%) - New user via the CSR API

1. Create key `/root/mock/auditor.key` and a CertificateSigningRequest `auditor` (CN `auditor`) for a client certificate. Approve it.
2. Write kubeconfig `/root/mock/auditor.kubeconfig` (certs embedded) for user `auditor`.
3. `auditor` may only `get` and `list` Pods and Events in all namespaces.

---

## Exam habits to practise today

- **Triage first**: skim all 15 tasks (2 min), do the quick ones (RBAC, Trivy, cosign, risky workloads) first, and leave API server edits for when you're focused. Flag what you skip and come back.
- **One API server change at a time**: back up the manifest, edit, wait for `1/1`, test, then the next change. Tasks 4 and 5 both edit it: if it doesn't come back, `crictl ps -a | grep apiserver` and `crictl logs <id>`, or `/var/log/pods/kube-system_kube-apiserver-*`.
- **Read every requirement twice.** "Pinned to version latest" means a second label. "Unencrypted data must stay readable" means `identity` last. "Don't recreate the Pod" means `kubectl debug`, not `--copy-to`.
- **`kubectl debug` in a restricted namespace**: the ephemeral container must pass PSA too. `--profile=restricted` sets the securityContext for you, and `--target=app` shares the container's PID namespace.
- **VAP CEL for limits**: `object.spec.containers.all(c, has(c.resources.limits) && 'cpu' in c.resources.limits && 'memory' in c.resources.limits)`. Match by namespace with `matchResources.namespaceSelector` in the binding (or policy).
- **cosign offline verification**: `cosign verify-blob --key cosign.pub --bundle <f>.bundle --insecure-ignore-tlog=true <f>`.
- Finding risky pods fast: `k get deploy -A -o json | jq -r '.items[] | select(.spec.template.spec.hostPID == true or any(.spec.template.spec.containers[]; .securityContext.privileged == true)) | .metadata.namespace + "/" + .metadata.name'`.
- Before time runs out: `k get pods -A | grep -v Running`, and check `cks-worker` is `Ready`.
