# Day 12 solution

## Task 1

On `cks-worker`:

```sh
ss -tlpn | grep 6666
# LISTEN 0 9 *:6666 *:* users:(("kworker",pid=2543,fd=3))
P=2543
ls -l /proc/$P/exe                 # -> /tmp/.cache/kworker
tr '\0' ' ' < /proc/$P/cmdline; echo   # httpd -f -p 6666 -h /   (a renamed busybox)
CID=$(grep -o 'cri-containerd-[0-9a-f]*' /proc/$P/cgroup | head -1 | cut -d- -f3)
crictl inspect $CID | grep -E '"io.kubernetes.pod.(name|namespace)"'
# "io.kubernetes.pod.name": "node-metrics-7cf57b887-bqsg4"
# "io.kubernetes.pod.namespace": "monitoring"
echo monitoring/node-metrics-7cf57b887-bqsg4 > /root/day12/listener.txt
echo /tmp/.cache/kworker > /root/day12/binary.txt
```

Note that pod `apps/queue` also runs a process called `kworker`: only the port tells you which one.

On `cks-cp`:

```sh
k -n monitoring get pod node-metrics-7cf57b887-bqsg4 -o jsonpath='{.metadata.ownerReferences[0].name}'   # ReplicaSet
k -n monitoring delete deploy node-metrics
```

## Task 2

On `cks-cp`:

```sh
cd /var/log/kubernetes/audit
grep '"name":"db-password"' audit.log | jq -c '{u: .user.username, v: .verb, ns: .objectRef.namespace}'
# {"u":"kubernetes-admin","v":"create",...}   <- setup
# {"u":"system:serviceaccount:ci:deployer","v":"get","ns":"prod"}
echo system:serviceaccount:ci:deployer > /root/day12/secret-reader.txt

grep '"username":"system:serviceaccount:ci:deployer"' audit.log |
  jq -c 'select(.verb=="create") | {r: .objectRef.resource, ns: .objectRef.namespace, n: .objectRef.name}'
# {"r":"serviceaccounts","ns":"kube-system","n":"node-debugger"}
# {"r":"clusterrolebindings","ns":null,"n":"node-debug"}
k delete clusterrolebinding node-debug
k -n kube-system delete sa node-debugger

# where do deployer's rights come from?
k get clusterrolebindings,rolebindings -A -o wide | grep deployer
# clusterrolebinding/ci-deployer  ClusterRole/cluster-admin ... ci/deployer
k delete clusterrolebinding ci-deployer
k auth can-i get secrets -n prod --as system:serviceaccount:ci:deployer   # no
```

Leave `rolebinding ci/builder` alone.

## Task 3

On `cks-worker`:

```sh
lsmod | grep -E 'sctp|tipc'
modprobe -r tipc
cat > /etc/modprobe.d/cks-disable.conf <<'E'
install sctp /bin/false
install tipc /bin/false
blacklist sctp
blacklist tipc
E
modprobe -n -v tipc        # install /bin/false

grep -ri -E 'PermitRootLogin|PasswordAuthentication' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
rm /etc/ssh/sshd_config.d/10-legacy.conf      # loaded first, so its "yes" values won
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sshd -t && systemctl restart ssh
sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication)'   # no / no

awk -F: '$3==0{print $1}' /etc/passwd      # root, svc-backup
userdel svc-backup                         # "currently used by process 1"
userdel -f svc-backup
```
