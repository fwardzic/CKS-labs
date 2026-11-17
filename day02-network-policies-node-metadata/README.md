# Day 2: NetworkPolicy and CiliumNetworkPolicy

Suggested time: 35 minutes. The cluster CNI is Cilium 1.20.

## Start

```sh
../cluster/reset.sh      # optional, clean cluster
./setup.sh
./check.sh
```

Reference solution: `solution.yaml` (don't peek).

Workloads (all `nginx` on port 80):

| Namespace | Pod (label) | Service |
|---|---|---|
| `team-web` | `web` (`app=web`), `intruder` (`app=intruder`) | |
| `team-api` | `api` (`app=api`) | `api` |
| `team-db` | `db` (`app=db`) | `db` |
| `other` | `tester` (`app=web`) | |

---

## Task 1 (3%) - Default deny

In namespace `team-api` create a NetworkPolicy `default-deny` that denies all ingress and all egress traffic for every pod in the namespace.

## Task 2 (7%) - Allow the API path

In namespace `team-api` create a NetworkPolicy `api-policy` for pods with `app=api`:

- Ingress: only from pods with `app=web` **in namespace `team-web`**, only TCP 80.
- Egress: only to pods with `app=db` in namespace `team-db` on TCP 80, and DNS (UDP and TCP 53) to the `kube-dns` pods in `kube-system`.

Keep `default-deny` in place.

## Task 3 (5%) - Protect the metadata endpoint

In namespace `team-web` create a NetworkPolicy `deny-metadata` that applies to all pods and denies egress to `169.254.169.254`. All other egress, including to the internet, to DNS and to every pod in the cluster, must keep working.

## Task 4 (6%) - CiliumNetworkPolicy with L7

In namespace `team-db` create a CiliumNetworkPolicy `db-ingress` for endpoints with `app=db`:

- allow ingress only from `app=api` pods in namespace `team-api`, on TCP 80,
- of those requests, allow only HTTP `GET`. Other methods must be rejected by the policy.

---

## Exam habits to practise today

- **AND vs OR**: `namespaceSelector` and `podSelector` in the *same* `from`/`to` item = both must match. As two separate items (`- namespaceSelector` / `- podSelector`) = either matches. This is the most common NetworkPolicy mistake.
- Select namespaces by the automatic label `kubernetes.io/metadata.name: <ns>`, not a label you hope exists (`k get ns --show-labels`).
- As soon as a pod has an Egress policy, **DNS breaks** unless you allow port 53. Test by name *and* by IP to tell DNS from policy problems.
- `ipBlock` is for traffic leaving the cluster. Cilium does not match pod IPs with `ipBlock`, so `0.0.0.0/0` does not cover in-cluster traffic: add a `namespaceSelector: {}` peer when pods must stay reachable.
- After applying a CiliumNetworkPolicy run `k get cnp`: an invalid policy shows `VALID False` and is **not enforced at all**. Common cause: L7 `rules` with a port that has no `protocol: TCP` ("L7 rules can only apply to TCP (not ANY)").
- Don't set `enableDefaultDeny.ingress: false` when the task says "only": it makes the policy allow-only, so unmatched sources and unmatched HTTP methods still get through. Leave the field out (default `true`).
- Test from the source pod: `k -n team-web exec web -- curl -s -m 3 http://api.team-api`. `-m` keeps a blocked connection from hanging your terminal.
- Docs: kubernetes.io "Network Policies" (concepts) has a full example with `ipBlock` + `except` and the selector rules. docs.cilium.io → Network Policy → "Layer 7 Policies" → HTTP for the HTTP rules, and "Using Kubernetes Constructs In Policy" for the `k8s:io.kubernetes.pod.namespace` label.
