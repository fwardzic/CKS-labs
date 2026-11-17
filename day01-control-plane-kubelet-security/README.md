# Day 1: Control plane and node debugging

Suggested time: 30 minutes for the three tasks. Work only on the nodes (`multipass shell cks-cp`, then `ssh`-style hops with `multipass shell cks-worker` from a second terminal), like the exam.

## Start

```sh
../cluster/reset.sh      # clean cluster (wait ~1 min for pods to settle)
./setup.sh               # breaks things
./check.sh               # grade at any time
```

Do not open `solution.md` until you have scored or given up.

---

## Task 1 (7%) - kube-apiserver

Someone "hardened" the kube-apiserver on `cks-cp` and now `kubectl` gets connection refused.

1. Bring the API server back. Keep `NodeRestriction` enabled and do not remove any other existing admission configuration.
2. Write the exact log line(s) that told you what was wrong into `/root/day1/apiserver-errors.txt`, one per problem you fixed.

Leave nothing but the original static pod manifests in `/etc/kubernetes/manifests/`.

## Task 2 (6%) - kubelet on cks-worker

A CIS scan flagged the kubelet on `cks-worker`. Fix it so that:

- anonymous requests to the kubelet API are rejected,
- authorization is delegated to the API server,
- the unauthenticated read-only port is disabled.

The node must stay `Ready` and `kubectl logs` for pods on `cks-worker` must keep working.

## Task 3 (4%) - Privileged workload

A pod in the cluster runs privileged and mounts the host's root filesystem. Find it and make sure it is gone and does not come back.

---

## Exam habits to practise today

- Before editing a static pod manifest, copy it **outside** `/etc/kubernetes/manifests/` (the kubelet runs every file in that directory).
- No API? Use `crictl ps -a`, `crictl logs <id>`, `/var/log/pods/`, `journalctl -u kubelet`.
- Know where kubelet config lives: `systemctl cat kubelet`, then the `--config` file.
- Check `k get node`, `k -n kube-system get pod` after each change.
