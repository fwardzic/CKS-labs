# Day 6 solution

## Task 1

On `cks-worker`:

```sh
grep '^profile' /opt/profiles/k8s-deny-write      # name: k8s-deny-write
apparmor_parser -q /opt/profiles/k8s-deny-write    # loads in enforce mode
aa-status | grep k8s-deny-write
```

On `cks-cp`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: writer
  namespace: secure
spec:
  nodeName: cks-worker
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-deny-write
  containers:
  - name: c
    image: busybox:1.37
    command: ["sh", "-c", "sleep 1d"]
```

```sh
k -n secure exec writer -- touch /tmp/x            # Permission denied
k -n secure exec writer -- cat /proc/1/attr/current   # k8s-deny-write (enforce)
```

## Task 2

On `cks-worker`:

```sh
mkdir -p /var/lib/kubelet/seccomp/profiles
cp /opt/profiles/no-chmod.json /var/lib/kubelet/seccomp/profiles/
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: no-chmod
  namespace: secure
spec:
  nodeName: cks-worker
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/no-chmod.json
  containers:
  - name: c
    image: busybox:1.37
    command: ["sh", "-c", "sleep 1d"]
```

```sh
k -n secure exec no-chmod -- chmod 700 /tmp       # Operation not permitted
k -n secure patch deploy api -p '{"spec":{"template":{"spec":{"securityContext":{"seccompProfile":{"type":"RuntimeDefault"}}}}}}'
```

## Task 3

On `cks-worker`:

```sh
ss -tlpn | grep 4444                     # socat, pid N
systemctl status N                       # node-agent.service
systemctl disable --now node-agent
rm /etc/systemd/system/node-agent.service
systemctl daemon-reload
dpkg -S /usr/bin/socat                   # socat
apt purge -y socat

id contractor                            # ... 27(sudo)
gpasswd -d contractor sudo               # or: deluser contractor sudo
grep -r contractor /etc/sudoers /etc/sudoers.d/
rm /etc/sudoers.d/contractor
sudo -l -U contractor                    # User contractor is not allowed to run sudo
```
