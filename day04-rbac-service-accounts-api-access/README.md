# Day 4: RBAC, ServiceAccounts, API access

Suggested time: 40 minutes.

## Start

```sh
../cluster/reset.sh
./setup.sh
./check.sh
```

Reference solution: `solution.md`.

---

## Task 1 (6%) - Least privilege for report-bot

ServiceAccount `report-bot` in namespace `finance` has far more permissions than it needs. It only has to read pods, pod logs and configmaps in `finance`.

- Remove every permission it has today.
- Create a Role `report-reader` in `finance` with `get`, `list`, `watch` on exactly `pods`, `pods/log` and `configmaps`.
- Bind it to `report-bot` with a RoleBinding named `report-bot`.

## Task 2 (5%) - ServiceAccount hygiene

In namespace `finance`:

1. Create a ServiceAccount `legacy-sa` that does not automount API credentials, and make Deployment `legacy` use it. The `legacy` pods must not have a ServiceAccount token mounted.
2. Make sure pods using the `default` ServiceAccount in `finance` do not get a token automatically either.
3. There is a long-lived, non-expiring ServiceAccount token stored as a Secret in `finance`. Find it and delete it.

## Task 3 (7%) - New user jane

Create user `jane` with a client certificate signed by the cluster CA:

1. Private key and CSR with CN `jane` in `/root/day4/` on `cks-cp`.
2. Submit it as a Kubernetes CertificateSigningRequest named `jane` (signer `kubernetes.io/kube-apiserver-client`), approve it.
3. Write a working kubeconfig to `/root/day4/jane.kubeconfig` (embed the certs).
4. `jane` may `get`, `list`, `watch`, `create`, `update`, `patch` Deployments in namespace `dev`, nothing else.

## Task 4 (5%) - Restrict API access

1. Unauthenticated users can currently read cluster resources. Stop that. Health endpoints (`/livez`, `/readyz`) must keep working for the kubelet probes.
2. Someone removed the admission plugin that limits what kubelets may modify on Node and Pod objects. Enable it again.

---

## Exam habits to practise today

- **Find all bindings of a subject** before you fix permissions: `k get rolebindings,clusterrolebindings -A -o wide | grep <name>`. Over-privilege is often in a ClusterRoleBinding you didn't look at.
- **Verify with `can-i`**: `k auth can-i list pods -n finance --as system:serviceaccount:finance:report-bot`, and `--list` to see everything. Test the things that must be *denied* too.
- Imperative RBAC is faster and typo-free: `k create role ... --verb --resource`, `k create rolebinding ... --role --serviceaccount ns:name` (or `--user`, `--group`). Subresources are written `pods/log`.
- `k set serviceaccount deploy/<name> <sa>` changes the SA without editing YAML.
- **CSR flow** is on the docs page "Certificate Signing Requests" → "How to issue a certificate for a user". Copy it; remember `base64 -w0` and `usages: [client auth]`.
- Never "fix" anonymous access with `--anonymous-auth=false` on a kubeadm cluster: the probes break, the pod shows `0/1`, and after ~4 minutes the API server restarts in a loop. Always check `READY 1/1` on the API server pod, not only that `kubectl` answers.
