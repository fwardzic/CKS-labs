# Day 13: API access, tokens, Secrets, namespace isolation

Suggested time: 50 minutes. Work on `cks-cp`.

## Start

```sh
../cluster/reset.sh
./setup.sh
./check.sh
```

Reference solution: `solution.md`.

---

## Task 1 (5%) - Projected ServiceAccount token

An application in namespace `vault-client` authenticates to Vault with a Kubernetes token. Create a Pod `client` (image `busybox:1.37`, command `sleep 1d`) in that namespace:

- it uses ServiceAccount `app`,
- the default API credentials are **not** mounted,
- a ServiceAccount token for audience `vault`, valid for **1 hour**, is available at `/var/run/secrets/tokens/vault-token`.

## Task 2 (4%) - Secrets

1. Write the decoded values of all Secrets of type `Opaque` in namespace `one` to `/root/day13/one.txt`, one value per line.
2. In namespace `ns-secure`:
   - create ServiceAccount `secret-manager`,
   - create Pod `secret-manager` (image `httpd:alpine`) that uses this ServiceAccount,
   - make the value of Secret `sec-a1` available as environment variable `SEC_A1`,
   - mount Secret `sec-a2` read-only at `/etc/sec-a2`.

## Task 3 (6%) - Namespace isolation

Namespaces `space1`, `space2` and `other` each run Pods `web` (Service `web`, port 80) and `client`.

1. Create a NetworkPolicy `np` in `space1` so that Pods in `space1` can only send traffic to Pods in namespace `space2`. Incoming traffic is not affected.
2. Create a NetworkPolicy `np` in `space2` so that Pods in `space2` only accept traffic from Pods in namespace `space1`. Outgoing traffic is not affected.

Both must still allow DNS (port 53, TCP and UDP) for every Pod.

## Task 4 (5%) - API server exposure

1. The Kubernetes API is reachable from outside the cluster on NodePort `31000` of every node. Make it available only inside the cluster again, through the `kubernetes` Service of type `ClusterIP`.
2. Every authenticated identity in the cluster can read Secrets in all namespaces. Find what grants this and remove it. Don't touch the default `system:` bindings.

## Task 5 (6%) - User certificate signed with the cluster CA

Create user `bob` in group `platform` **without** the CertificateSigningRequest API. Write all files to `/root/day13/` on `cks-cp`:

1. Private key `bob.key` and CSR `bob.csr` with CN `bob` and organization `platform`.
2. Certificate `bob.crt`, signed directly with the cluster CA, valid for **30 days**.
3. Kubeconfig `bob.kubeconfig` with cluster `cks`, user `bob` and context `bob@cks` as current context, all certificates **embedded**.
4. ClusterRoleBinding `platform-view` granting the ClusterRole `view` to the **group** `platform`.

---

## Exam habits to practise today

- **Projected tokens**: docs "Configure Service Accounts for Pods" → "ServiceAccount token volume projection" has the exact volume. `automountServiceAccountToken: false` removes only the default `kube-api-access-*` volume, your projected one stays. Check the claims: `cut -d. -f2 <token> | base64 -d` (add `=` padding if it complains) shows `aud`, `iat`, `exp`.
- **Opaque only**: `k get secrets --field-selector type=Opaque`. `jq -r '.items[].data[] | @base64d'` decodes every value in one go. Secrets of type `kubernetes.io/tls` and `dockerconfigjson` are not `Opaque`.
- Secret as env: `env[].valueFrom.secretKeyRef` (one key) vs `envFrom.secretRef` (all keys, named after the keys: wrong here). Secret as volume: `readOnly: true` goes on the **volumeMount**.
- **Namespace selectors**: every namespace has the label `kubernetes.io/metadata.name=<name>`, so no labelling is needed. In a policy with `policyTypes: [Egress]` only, ingress stays open, and the other way round. A DNS rule with only `ports:` (no `to:`) allows port 53 to anywhere.
- Test NetworkPolicies from both sides, and test what must still work: `k -n space1 exec client -- wget -qO- -T 2 web.space2`. A `-T` timeout means the policy dropped the traffic. A DNS error means you blocked DNS.
- **`--kubernetes-service-node-port`**: removing the flag is not enough. The existing `kubernetes` Service stays `NodePort` until you `k delete svc kubernetes`, after which the API server recreates it as `ClusterIP`. Wait for the API server to be `1/1` again first.
- Over-broad access via groups: `k get clusterrolebindings -o wide | grep -E 'system:(authenticated|unauthenticated)'`, then compare with the defaults (`system:basic-user`, `system:discovery`, `system:public-info-viewer`). Verify with `k auth can-i list secrets -A --as nobody --as-group system:authenticated`.
- **Manual cert**: `openssl req -new -key bob.key -subj "/CN=bob/O=platform"`, then `openssl x509 -req -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -days 30`. In Kubernetes, `O` is the group. `k config set-credentials ... --embed-certs`, and check with `k --kubeconfig bob.kubeconfig auth whoami`.
