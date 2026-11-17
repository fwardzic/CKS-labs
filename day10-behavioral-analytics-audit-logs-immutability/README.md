# Day 10: Runtime security (Falco, audit logs, immutability)

Suggested time: 45 minutes.

## Start

```sh
../cluster/reset.sh
./setup.sh
./check.sh
```

Reference solution: `solution.md`. Falco runs on both nodes as `falco-modern-bpf.service`; all workloads run on `cks-worker`.

---

## Task 1 (8%) - Falco

1. One Deployment in namespace `ops` keeps reading sensitive files. Use Falco on `cks-worker` to find it and scale it to **0** replicas. Don't touch the other Deployments.
2. On `cks-worker`, add a Falco rule `Package manager in container` (priority `WARNING`) that fires when `apk`, `apt`, `apt-get`, `dpkg`, `yum` or `dnf` is started inside a container. Output must be exactly:

   ```
   Package manager in container | time=%evt.time container=%container.name pod=%k8s.pod.name ns=%k8s.ns.name cmd=%proc.cmdline
   ```

   Don't change `/etc/falco/falco_rules.yaml`.
3. Configure Falco to also write its alerts to `/var/log/falco/alerts.log`.
4. Using those alerts, write the name of the pod that runs a package manager into `/root/day10/pkg-pod.txt` on `cks-worker`.

## Task 2 (7%) - Audit logging

Enable audit logging on the API server:

- Policy file `/etc/kubernetes/audit/policy.yaml`, log file `/var/log/kubernetes/audit/audit.log`, keep logs at most **7** days and at most **2** old files.
- Policy:
  - `secrets` in any namespace: `Metadata` level,
  - `configmaps` in namespace `ops`: `RequestResponse` level,
  - nothing else is logged,
  - don't log the `RequestReceived` stage.

## Task 3 (5%) - Immutable container

Make Deployment `ops/frontend` (nginx) immutable: its container's root filesystem must be read-only. nginx must keep serving on port 80.

---

## Exam habits to practise today

- **Finding Falco alerts**: `journalctl -u falco-modern-bpf | grep <rule text>` (or `-f` to follow). The alert names the pod (`k8s_pod_name=`) and namespace: go from pod → ReplicaSet → Deployment (`k get pod X -o jsonpath='{.metadata.ownerReferences}'`).
- Custom rules go in `/etc/falco/falco_rules.local.yaml` (or `rules.d/`), loaded **after** the defaults, so you can use their macros (`spawned_process`, `container`, `open_read`). To change an existing rule, copy it into the local file with the same name, or use `override:` (Falco docs → Concepts → Rules → Overriding).
- `falco --validate falco_rules.local.yaml` alone fails with "Undefined macro": validate with the defaults too, or `falco --dry-run`. After a change: `systemctl restart falco-modern-bpf` and check `journalctl` for load errors.
- Output fields: Falco docs → Reference → Rules → Supported Fields (`%evt.time`, `%container.name`, `%k8s.pod.name`, `%proc.cmdline`, `%user.name`). File output: `file_output.enabled: true` + `filename:` in `/etc/falco/falco.yaml`.
- **Audit**: four flags at least (`--audit-policy-file`, `--audit-log-path`, `--audit-log-maxage`, `--audit-log-maxbackup`; `--audit-log-maxsize` is common too) **plus two mounts** (policy file read-only, log directory read-write). Docs: "Auditing" has the volume snippet: copy it.
- Audit rules are evaluated **top-down, first match wins**: specific rules first, the catch-all `- level: None` last. An empty or broken policy keeps the API server down: `crictl logs` shows why.
- Read the log with `tail -f audit.log | jq -c '{level, verb, user: .user.username, res: .objectRef.resource, ns: .objectRef.namespace, name: .objectRef.name}'`.
- **Immutability**: `readOnlyRootFilesystem: true` usually breaks the app until you mount `emptyDir` on the paths it writes. For nginx: `/var/cache/nginx`, `/var/run`, and `/tmp`. Read the container logs: they tell you which path failed.
