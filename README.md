# CKS labs (Multipass + kubeadm, arm64)

Two Ubuntu 24.04 VMs with their own Ubuntu kernel (AppArmor, BTF for Falco modern eBPF).

| Node | Role |
|---|---|
| `cks-cp` | control plane (kubeadm 1.35.9, static pods in `/etc/kubernetes/manifests`) |
| `cks-worker` | worker |

Stack: containerd 2.2 (Ubuntu package, config `version = 3`), Cilium 1.20.3 (Helm release `cilium`), kube-proxy.

## Requirements

- **Apple Silicon Mac (arm64)**. All downloaded binaries are `linux-arm64`, so the scripts won't work as-is on an Intel Mac or an x86 Linux host.
- [Multipass](https://canonical.com/multipass) (tested with 1.16): `brew install --cask multipass`
- `bash` and `python3` on the Mac (both ship with macOS / Xcode Command Line Tools)
- Free resources for two VMs: **4 vCPU, 8 GB RAM, 40 GB disk** (2 CPU / 4 GB / 20 GB each)
- Internet access from the VMs: packages come from Ubuntu, pkgs.k8s.io, Falco, gVisor and GitHub releases
- Optional: `kubectl` on the Mac, if you want to use the cluster from outside the VMs

## Installation

```sh
git clone <this-repo-url> cks-labs
cd cks-labs
cluster/create.sh
```

`create.sh` does the whole build from the Mac:

1. Launches `cks-cp` and `cks-worker` (Ubuntu 24.04) in Multipass.
2. Installs containerd and kubeadm/kubelet/kubectl 1.35.9 (`node-setup.sh`), held at that version.
3. Runs `kubeadm init` on `cks-cp`, installs Cilium and points CoreDNS at public resolvers (`cp-init.sh`), then joins the worker.
4. Installs the exam tooling (`tools.sh`, see [Preinstalled tooling](#preinstalled-tooling)).
5. Copies the admin kubeconfig to `cluster/kubeconfig` (git-ignored: it holds the cluster-admin key).
6. Stops both VMs, takes a snapshot named `clean`, and starts them again.

Check it worked:

```sh
multipass list                                   # cks-cp and cks-worker Running
multipass exec cks-cp -- kubectl get nodes       # both Ready
multipass info cks-cp --snapshots                # snapshot "clean" exists
```

Versions are pinned at the top of `cluster/node-setup.sh`, `cluster/cp-init.sh` and `cluster/tools.sh`. If a download URL stops working, bump the version there and rebuild.

To rebuild from scratch:

```sh
multipass delete --purge cks-cp cks-worker
cluster/create.sh
```

### Troubleshooting

- **`launch failed: instance already exists`**: the VMs exist from a previous run. Delete them (above) and run `create.sh` again.
- **`create.sh` fails halfway**: usually a network or download error. Delete the VMs and start over; the script isn't idempotent.
- **Pods can't resolve names**: confirm the CoreDNS ConfigMap forwards to `1.1.1.1 8.8.8.8` (see [Lab-specific notes](#lab-specific-notes)).
- **Scripts hang**: always use the `lib.sh` helpers (`on`, `remote`, `check`) rather than bare `multipass exec ... >/dev/null`.

## Daily labs

Each `dayNN-<topic>/` folder has `README.md` (tasks + exam habits), `setup.sh`, `check.sh`, and a solution file. Folder names follow the wording of the [CKS curriculum v1.37](https://github.com/cncf/curriculum). Typical loop, from inside a day folder:

```sh
../cluster/reset.sh   # clean cluster, wait ~1 min for pods to settle
./setup.sh
# work on the nodes: multipass shell cks-cp / multipass shell cks-worker
./check.sh            # grade any time, as often as you like
```

| Day | Tasks | Curriculum domain: competency | Time |
|---|---|---|---|
| [01](day01-control-plane-kubelet-security/) | kube-apiserver / kubelet debugging, static pods, privileged workload | Cluster Setup: CIS review of kubeapi/kubelet config | 30 min |
| [02](day02-network-policies-node-metadata/) | Default deny, NetworkPolicy, metadata endpoint, CiliumNetworkPolicy (L7) | Cluster Setup: network security policies; protect node metadata and endpoints | 35 min |
| [03](day03-cis-benchmark-ingress-tls-binaries/) | kube-bench, Ingress TLS, binary checksums | Cluster Setup: CIS benchmark; Ingress with TLS; verify platform binaries | 40 min |
| [04](day04-rbac-service-accounts-api-access/) | RBAC, ServiceAccounts, CSR users, anonymous access, NodeRestriction | Cluster Hardening: RBAC; service accounts; restrict access to the API | 40 min |
| [05](day05-kubernetes-upgrade/) | kubeadm upgrade 1.35 → 1.36 | Cluster Hardening: upgrade Kubernetes | 30 min |
| [06](day06-apparmor-seccomp-host-footprint/) | AppArmor, seccomp, services/packages/users on the host | System Hardening: AppArmor, seccomp; host OS footprint; least-privilege IAM | 40 min |
| [07](day07-pod-security-standards-secrets/) | Pod Security Admission, Secrets, encryption at rest | Minimize Microservice Vulnerabilities: pod security standards; manage secrets | 40 min |
| [08](day08-sandboxed-containers-pod-encryption/) | gVisor RuntimeClass, Cilium WireGuard, Istio mTLS | Minimize Microservice Vulnerabilities: sandboxed containers; Pod-to-Pod encryption | 40 min |
| [09](day09-supply-chain-sbom-static-analysis/) | trivy, SBOM (bom/trivy), kubesec, kube-linter, ImagePolicyWebhook, ValidatingAdmissionPolicy | Supply Chain Security: SBOM; static analysis; permitted registries | 50 min |
| [10](day10-behavioral-analytics-audit-logs-immutability/) | Falco rules, audit logging, immutable containers | Monitoring, Logging and Runtime Security: behavioral analytics; audit logs; immutability | 45 min |
| [11](day11-base-image-footprint-workload-hardening/) | Dockerfile hardening, manual static review, image digests, securityContext | Supply Chain Security: base image footprint; static analysis | 35 min |
| [12](day12-attack-investigation-host-hardening/) | Port → process → pod forensics, audit log investigation, kernel modules, sshd, UID 0 | Monitoring, Logging and Runtime Security: investigate phases of attack and bad actors; System Hardening | 40 min |
| [13](day13-api-access-secrets-namespace-isolation/) | Projected SA tokens, Secrets, namespace NetworkPolicies, API NodePort exposure, manual user certs | Cluster Hardening: restrict API access; Microservice Vulnerabilities: secrets, multi-tenancy | 50 min |
| [14](day14-mock-exam/) | **Mock exam**: 15 weighted tasks across all domains, weighted score, pass mark 67% | all | 2 h |

Every scenario was run end to end on this cluster: setup → unsolved score → reference solution → full score.

## Cluster commands (run on the Mac)

```sh
cluster/create.sh                  # build from scratch + snapshot "clean"
cluster/reset.sh                   # restore both nodes to "clean"
multipass stop cks-cp cks-worker   # free RAM when not studying
KUBECONFIG=cluster/kubeconfig kubectl get nodes
```

Always reset before a new day: Days 3, 4, 5, 7, 9, 10, 12, 13 and 14 change the API server, Day 5 upgrades the cluster, Day 12 changes sshd and kernel modules on `cks-worker`.

## Preinstalled tooling

| Where | Tool | Notes |
|---|---|---|
| both | Falco (`falco-modern-bpf.service`) | rules in `/etc/falco/` |
| both | gVisor `runsc` | binary only: wiring it into containerd is a lab |
| both | `apparmor_parser`, `aa-status`, `crictl`, `jq` | |
| cp | trivy, kube-bench, bom, kubesec, kube-linter, cosign, istioctl, etcdctl, helm, cilium | |

Not on the exam's allowed-docs list: Trivy and AppArmor. Learn those commands by heart.

## Lab-specific notes

- CoreDNS forwards to 1.1.1.1 / 8.8.8.8: the Multipass DNS (Mac's IPv6 link-local resolver) is not usable from pods.
- Scripts use `lib.sh` helpers because `multipass exec` hangs when its output goes to `/dev/null` or the remote exit code is > 1.
