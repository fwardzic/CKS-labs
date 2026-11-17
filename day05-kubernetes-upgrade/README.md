# Day 5: Upgrade Kubernetes (kubeadm)

Suggested time: 30 minutes. Do this one twice if you can: speed matters, the steps never change.

## Start

```sh
../cluster/reset.sh      # required: the cluster must be on v1.35.9
./setup.sh
./check.sh
```

Reference solution: `solution.md`.

---

## Task 1 (8%) - Upgrade the control plane

The cluster runs v1.35.9, which has known vulnerabilities. Upgrade `cks-cp` to **v1.36.5**: control plane components, kubelet and kubectl. Drain the node before upgrading kubelet and make it schedulable again afterwards. The packages must be held again when you're done.

## Task 2 (6%) - Upgrade the worker

Upgrade `cks-worker` to the same version (kubeadm, kubelet, kubectl). The node must be `Ready` and schedulable afterwards, and Deployment `prod/shop` must have all 3 replicas running.

---

## Exam habits to practise today

- **The docs follow the latest release.** "Upgrading kubeadm clusters" on kubernetes.io is written for the newest minor version (1.37 today). Replace the version numbers in every command you copy.
- **Change the package repository first** (`/etc/apt/sources.list.d/kubernetes.list`, `v1.35` → `v1.36`): pkgs.k8s.io has one repo per minor version, so `apt-cache madison kubeadm` won't show 1.36 until you do. Docs: "Changing The Kubernetes Package Repository".
- Order: kubeadm → `kubeadm upgrade plan` → `kubeadm upgrade apply v1.36.5` (control plane) / `kubeadm upgrade node` (workers) → drain → kubelet + kubectl → `systemctl daemon-reload && systemctl restart kubelet` → uncordon.
- `drain` runs from a machine with admin kubeconfig (here `cks-cp`), the package upgrade runs on the node itself. Keep two terminals open.
- `apt-mark unhold` before and `apt-mark hold` after: forgetting the hold is a lost point.
- A drain that hangs is usually a PodDisruptionBudget, or pods with nowhere to go. Read the drain output. `--ignore-daemonsets` is always needed, `--delete-emptydir-data` often.
