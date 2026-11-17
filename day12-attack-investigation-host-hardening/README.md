# Day 12: Investigation and host hardening

Suggested time: 40 minutes.

## Start

```sh
../cluster/reset.sh
./setup.sh
./check.sh
```

Reference solution: `solution.md`. Audit logging is already enabled on the API server: log in `/var/log/kubernetes/audit/audit.log` on `cks-cp`.

---

## Task 1 (6%) - Who is listening?

A process on `cks-worker` listens on TCP port `6666` and serves files to anyone who connects. It runs inside a container.

1. Write the namespace and name of the Pod it belongs to into `/root/day12/listener.txt` on `cks-worker`, in the format `<namespace>/<pod>`.
2. Write the absolute path of the executable of that process, as seen inside the container, into `/root/day12/binary.txt` on `cks-worker`.
3. Remove the workload so that the pod doesn't come back. Don't touch any other workload.

## Task 2 (7%) - Audit log investigation

The security team suspects a stolen ServiceAccount token. Use the audit log on `cks-cp`.

1. Find the ServiceAccount that read Secret `db-password` in namespace `prod`. Write its full username (as it appears in the audit log) to `/root/day12/secret-reader.txt` on `cks-cp`.
2. Using the same identity, the attacker created two objects to keep access to the cluster. Find and delete both.
3. Make sure that ServiceAccount can no longer read Secrets in `prod`. Don't delete the ServiceAccount, and don't change the permissions of other ServiceAccounts.

## Task 3 (6%) - Harden cks-worker

1. Kernel modules `sctp` and `tipc` are not needed. Make sure neither is loaded now, and that neither can be loaded in future (not even explicitly with `modprobe`).
2. SSH must not allow root logins at all, and must not allow password authentication. The SSH server must stay reachable.
3. Only `root` may have UID `0`. Delete any other account with UID `0`.

---

## Exam habits to practise today

- **Port → process → container → pod**: `ss -tlpn | grep 6666` gives the PID. The process name (`comm`) can be a lie (`kworker` here): check `ls -l /proc/<PID>/exe` and `tr '\0' ' ' < /proc/<PID>/cmdline`. `/proc/<PID>/exe` shows the path inside the container's mount namespace.
- From a PID to its container: `grep -o 'cri-containerd-[0-9a-f]*' /proc/<PID>/cgroup` gives the container ID, then `crictl inspect <id> | grep -E 'pod.name|pod.namespace'` (or `crictl ps --id <id>` + `crictl pods --id <pod-id>`). The other way round: `crictl inspect <id> | jq .info.pid`.
- A `hostNetwork: true` pod shows its sockets in the node's `ss` output. Without it, use `nsenter -t <PID> -n ss -tlpn`.
- Removing a pod "so it doesn't come back" means removing its owner: pod → `ownerReferences` → ReplicaSet → Deployment (or a DaemonSet, StatefulSet, Job, static pod manifest).
- **Audit log queries with jq**: `grep db-password audit.log | jq -c '{t: .requestReceivedTimestamp, u: .user.username, v: .verb, r: .objectRef.resource, ns: .objectRef.namespace, n: .objectRef.name}'`. Then search everything that username did: `grep '"username":"system:serviceaccount:ci:deployer"' audit.log | jq -c 'select(.verb=="create") | ...'`.
- Persistence usually means **RBAC objects or ServiceAccounts** (also CronJobs, DaemonSets, static pod manifests). Find how the attacker got the rights: `k get clusterrolebindings,rolebindings -A -o wide | grep deployer`. Then remove that binding, not the identity.
- **Kernel modules**: `blacklist <mod>` only stops auto-loading. `install <mod> /bin/false` in `/etc/modprobe.d/*.conf` also blocks an explicit `modprobe`. Unload with `rmmod`/`modprobe -r`, and test with `modprobe -n -v <mod>`.
- **sshd config**: the first value read wins, and `/etc/ssh/sshd_config.d/*.conf` is included at the **top** of `sshd_config`. Check the effective config with `sshd -T | grep -Ei 'permitrootlogin|passwordauthentication'`, then `systemctl restart ssh`. "No root login at all" means `no`, not the default `prohibit-password`.
- Duplicate UID 0 accounts: `awk -F: '$3==0' /etc/passwd`. `userdel` refuses ("currently used by process 1") because root processes share the UID: use `userdel -f`.
