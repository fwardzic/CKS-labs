# Day 11: Workload and image hardening

Suggested time: 35 minutes. Work on `cks-cp` (`multipass shell cks-cp`, then `sudo -i`).

## Start

```sh
../cluster/reset.sh
./setup.sh
./check.sh
```

Reference solution: `solution.md`.

---

## Task 1 (5%) - Harden a Dockerfile

`/root/day11/image/Dockerfile` builds a small client that calls an internal API with a token. Fix it **in place**:

- Use base image `ubuntu` with the specific version `24.04`.
- Install the packages in a single layer and don't leave the apt package lists in the image.
- Remove the hard-coded token. The value is passed in at runtime as environment variable `TOKEN`.
- The container must run as a new user `app` with UID `10001`.
- Nobody must be able to `kubectl exec` into the container with `bash`.

There is no image builder on the nodes: the file is graded as written.

## Task 2 (4%) - Manual static review

`/root/day11/review/` contains three pairs of files: `app1-*` (Dockerfiles), `app2-*` and `app3-*` (manifests). For each pair, move the **less secure** file to `/root/day11/insecure/`. Leave the other one where it is.

## Task 3 (3%) - Image digest

Tags can be overwritten, digests can't. Change Deployment `web` in namespace `hardening` to use the **digest** of the image it runs right now instead of the tag (no tag in the image reference). The Deployment must roll out.

## Task 4 (6%) - securityContext

1. Deployment `logger` in namespace `hardening` prints its user and its `NoNewPrivs` flag every 5 seconds. Change it so that:
   - privilege escalation is disabled,
   - the container runs as UID `1000` and GID `3000`,
   - all Linux capabilities are dropped.

   The logs must show the change.
2. `/root/day11/sts.yaml` describes a StatefulSet that must run **privileged** in namespace `infra`, but it can't be applied. Fix the file in place and create the StatefulSet.

---

## Exam habits to practise today

- **Dockerfile checklist** (what graders look for): pinned base tag (never `latest` or none), fewer layers (`apt-get update && apt-get install -y ... && rm -rf /var/lib/apt/lists/*` in one `RUN`), no secrets in `ENV`/`ARG`/`COPY` (they stay in the image history), non-root `USER` at the end, no shells or package managers you don't need. `rm` needs root, so do it **before** `USER`.
- **Comparing two files** (`diff a b` or `vimdiff`): read the diff first, then decide. Common tells: `hostPID`/`hostNetwork`/`hostIPC`, `hostPath` (especially the container runtime socket), `privileged`, added capabilities, `USER root` or no `USER`, `latest` tag, big base image with extra tools, secrets in the image.
- **Digest of a running image**: `k get pod X -o jsonpath='{.status.containerStatuses[0].imageID}'` (or `crictl images --digests` on the node). `k set image deploy/web nginx=nginx@sha256:...` is the fastest edit.
- **`NoNewPrivs`** in `/proc/<pid>/status` is the kernel flag set by `allowPrivilegeEscalation: false`. Verify a change from the *logs* or with `k exec ... -- grep NoNewPrivs /proc/1/status`, not only from the spec.
- `runAsUser`/`runAsGroup` work at pod or container level; `privileged`, `capabilities`, `allowPrivilegeEscalation` and `readOnlyRootFilesystem` exist **only at container level**. `kubectl apply` says so: `strict decoding error: unknown field "spec.template.spec.securityContext.privileged"`. Read the error, and `k explain pod.spec.securityContext` / `k explain pod.spec.containers.securityContext` to see which fields go where.
- Docs: "Configure a Security Context for a Pod or Container".
