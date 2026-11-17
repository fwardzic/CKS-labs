# Day 6: System hardening (AppArmor, seccomp, host footprint)

Suggested time: 40 minutes.

## Start

```sh
../cluster/reset.sh
./setup.sh
./check.sh
```

Reference solution: `solution.md`.

---

## Task 1 (6%) - AppArmor

On `cks-worker` an AppArmor profile is stored in `/opt/profiles/k8s-deny-write`.

1. Load it on `cks-worker` in **enforce** mode.
2. Create a Pod `writer` in namespace `secure` (image `busybox:1.37`, command `sleep 1d`) that runs on `cks-worker` and is confined by this profile. Use the current API field, not the deprecated annotation.

## Task 2 (6%) - seccomp

1. On `cks-worker`, a seccomp profile is stored in `/opt/profiles/no-chmod.json`. Install it where the kubelet looks for local profiles, under a `profiles/` subdirectory.
2. Create a Pod `no-chmod` in namespace `secure` (image `busybox:1.37`, command `sleep 1d`) on `cks-worker` using that profile.
3. Deployment `api` in namespace `secure` must use the container runtime's default seccomp profile for all its containers (set it at pod level).

## Task 3 (6%) - Reduce the host attack surface

On `cks-worker`:

1. Something listens on TCP port `4444` and hands out a root shell. Find what starts it, stop it, make sure it won't come back after a reboot, delete its systemd unit file, and remove the package that provides the listening binary.
2. User `contractor` has full root access through `sudo`. Remove all of their sudo privileges (keep the user).

---

## Exam habits to practise today

- **AppArmor** profiles are loaded **per node**: run `apparmor_parser` on the node where the pod will be scheduled, and pin the pod there (`nodeName` or `nodeSelector`). Check with `aa-status | grep <name>`.
- The profile name to use in the pod is the name after `profile` *inside* the file, not the file name. Here they happen to be the same: always check.
- Pod field (since 1.30): `securityContext.appArmorProfile: {type: Localhost, localhostProfile: <name>}`. The old `container.apparmor.security.beta.kubernetes.io/...` annotation is deprecated.
- **seccomp** `localhostProfile` is a path **relative to `/var/lib/kubelet/seccomp/`**, e.g. `profiles/no-chmod.json`. A wrong path leaves the pod in `CreateContainerError`: `k describe pod` shows why.
- Prove confinement: `k exec <pod> -- cat /proc/1/attr/current` shows the AppArmor profile; `k exec <pod> -- grep Seccomp /proc/1/status` shows `2` (filter) under seccomp.
- Finding listeners: `ss -tlpn` (process name + PID) → `systemctl status <PID>` tells you which unit owns it → `systemctl disable --now`. `dpkg -S $(which socat)` finds the package, `apt purge` removes it.
- Sudo rights come from groups (`id <user>`) **and** files in `/etc/sudoers.d/`. Check both, then `sudo -l -U <user>`.
- Docs: kubernetes.io tutorials "Restrict a Container's Access to Resources with AppArmor" and "Restrict a Container's Syscalls with seccomp". The AppArmor docs are **not** on the allowed list: learn `apparmor_parser` and `aa-status` by heart.
