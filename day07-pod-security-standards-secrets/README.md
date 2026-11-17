# Day 7: Pod Security Admission, Secrets, encryption at rest

Suggested time: 40 minutes.

## Start

```sh
../cluster/reset.sh
./setup.sh
./check.sh
```

Reference solution: `solution.md`.

---

## Task 1 (6%) - Pod Security Admission

1. Namespace `payments` must **enforce** the `restricted` Pod Security Standard.
2. Namespace `legacy` must **enforce** `baseline`, and **warn** and **audit** at `restricted`.
3. Deployment `payments/pay` must keep running with 2 replicas under the new policy. Change only what `restricted` requires; keep the image.

## Task 2 (5%) - Secrets

1. Read the password stored in Secret `admin-creds` in namespace `legacy` and write its plain-text value (no newline needed) to `/root/day7/password.txt` on `cks-cp`.
2. Deployment `pay` keeps its database password in a plain environment variable. Create Secret `db-creds` in `payments` with keys `user=pay` and `pass=S3cr3t!`. Remove the env variable and mount the secret read-only at `/etc/db` instead.

## Task 3 (8%) - Encryption at rest

Secrets are stored in etcd in plain text.

1. Create an `EncryptionConfiguration` at `/etc/kubernetes/enc/enc.yaml` that encrypts `secrets` with the `aescbc` provider (key name `key1`), while still able to read unencrypted data.
2. Configure kube-apiserver to use it.
3. Make sure **all existing** secrets in the cluster are stored encrypted.
4. Verify with `etcdctl` that `/registry/secrets/payments/db-creds` is encrypted.

---

## Exam habits to practise today

- PSA labels: `pod-security.kubernetes.io/<enforce|warn|audit>=<privileged|baseline|restricted>`. `k label ns <ns> ... --overwrite`.
- Enforce only affects **new** pods: existing ones keep running. Restart the Deployment (or let your edit roll it) and watch `k get rs`/`k get events` for `FailedCreate`: PSA rejections show on the ReplicaSet, not the Deployment.
- `k label --dry-run=server --overwrite ns X pod-security.kubernetes.io/enforce=restricted` lists every running pod that would violate the level. Great to check your fix.
- `restricted` needs at least: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault` (or Localhost). Docs: "Pod Security Standards" has the full table.
- Decode a secret: `k get secret X -o jsonpath='{.data.password}' | base64 -d`.
- Encryption config: docs "Encrypting Confidential Data at Rest" has the YAML. Key: `head -c 32 /dev/urandom | base64`. First provider in the list is used for writing, so `identity` must come **last**.
- The API server needs a `hostPath` volume **and** `volumeMount` for the config directory, plus the flag. Missing mount = API server down: `crictl logs` tells you.
- Re-encrypt everything: `k get secrets -A -o json | k replace -f -`.
- etcdctl needs the etcd certs: `--cacert /etc/kubernetes/pki/etcd/ca.crt --cert /etc/kubernetes/pki/etcd/server.crt --key /etc/kubernetes/pki/etcd/server.key` (copy the paths from the etcd manifest). With etcd 3.6+ drop `ETCDCTL_API=3`: v3 is the only API and etcdctl warns about the variable. Encrypted values start with `k8s:enc:aescbc:v1:key1:`; pipe through `hexdump -C | head`.
