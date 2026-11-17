# Day 9: Supply chain security

Suggested time: 50 minutes (five tasks).

## Start

```sh
../cluster/reset.sh
./setup.sh               # ~2 min
./check.sh               # ~2 min (runs trivy for task 1)
```

Reference solution: `solution.md`. All tools are on `cks-cp`: `trivy`, `bom`, `kubesec`, `kube-linter`.

---

## Task 1 (4%) - Image vulnerabilities

Namespace `team-x` runs five pods. Use `trivy` to scan the image of each pod and delete every pod whose image has at least one **CRITICAL** vulnerability. Leave the others running.

## Task 2 (4%) - SBOM

Write all files to `/root/day9/` on `cks-cp`:

1. With `bom`, generate an SPDX JSON SBOM of image `nginx:1.29-alpine` → `nginx.spdx.json`.
2. With `trivy`, generate a CycloneDX SBOM of the same image → `nginx.cdx.json`.
3. Write the version of the `libssl3` package in that image (only the version string) → `libssl3.txt`.

## Task 3 (5%) - Static analysis

`/root/day9/tools.yaml` defines Deployment `supply/tools`. Fix the manifest **in place** so that:

- `kubesec scan` reports no critical issues and a score of at least 4,
- `kube-linter lint` reports no findings,
- the container still runs `sleep 1d` with the same image.

Then apply it. The pod must be running.

## Task 4 (7%) - ImagePolicyWebhook

An image policy backend runs on `cks-cp` at `https://127.0.0.1:8443/image_policy`. Everything needed is in `/etc/kubernetes/policywebhook/` (`admission_config.yaml`, `kubeconf`, certs).

1. Enable the `ImagePolicyWebhook` admission plugin on the API server (keep `NodeRestriction`), using `admission_config.yaml`.
2. If the backend is unreachable, pod creation must be **denied**.

Test: `k run t --image nginx:latest` is rejected, `k run t --image nginx:1.29-alpine` works.

## Task 5 (5%) - Permitted registries

Create a ValidatingAdmissionPolicy `allowed-registries` and a binding so that in namespace `supply` only pods whose container images start with `registry.k8s.io/` or `docker.io/library/` are admitted. Other namespaces must not be affected.

---

## Exam habits to practise today

- **trivy**: `trivy image --severity CRITICAL nginx:1.19-alpine`. For many images: `k get pods -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[*].image}{"\n"}{end}'`. Add `-q` to hide progress, `--format json | jq` to count. Trivy docs are **not** allowed in the exam: know `image`, `--severity`, `--format`, `--output`, `sbom`.
- **trivy SBOM**: `trivy image --format cyclonedx --output x.cdx.json <img>` (or `spdx-json`). `trivy sbom x.cdx.json` scans an existing SBOM.
- **bom**: `bom generate --image <img> --format json --output x.spdx.json`. The bom CLI reference *is* allowed (kubernetes-sigs.github.io/bom).
- **kubesec**: `kubesec scan file.yaml` → `score` and `scoring.critical`. **kube-linter**: `kube-linter lint file.yaml`; each finding names the check and the fix.
- **ImagePolicyWebhook** needs three things in the API server manifest: plugin in `--enable-admission-plugins`, `--admission-control-config-file=...`, and a **volume + volumeMount** for the directory (paths inside the config must exist *inside* the container). `defaultAllow: false` = deny when the backend is down.
- Test admission without creating anything: `k run t --image X --dry-run=server`.
- **ValidatingAdmissionPolicy** = policy (CEL `validations`) + binding (`validationActions: [Deny]`, scope via `matchResources.namespaceSelector`). Without a binding the policy does nothing. Docs: "Validating Admission Policy".
- Image strings are checked **as written**: `nginx:1.29` does not start with `docker.io/library/` even though that's where it comes from.
