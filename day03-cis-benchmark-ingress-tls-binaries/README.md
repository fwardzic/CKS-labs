# Day 3: CIS benchmark, Ingress TLS, binary verification

Suggested time: 40 minutes.

## Start

```sh
../cluster/reset.sh      # recommended: setup changes the control plane
./setup.sh               # ~3 min (installs ingress-nginx)
./check.sh
```

Reference solution: `solution.md`.

---

## Task 1 (8%) - CIS benchmark on cks-cp

`kube-bench` is installed on `cks-cp`. Fix the control plane so that these checks pass:

`1.1.1`, `1.1.11`, `1.1.12`, `1.2.6`, `1.2.7`, `1.2.8`, `1.2.15`, `1.3.2`, `1.4.1`

All control plane components must be running and healthy afterwards.

## Task 2 (6%) - Ingress with TLS

Namespace `shop` has a Deployment and Service `shop` (port 80). ingress-nginx is installed and reachable on every node: HTTP on NodePort `30080`, HTTPS on `30443`.

1. Create a self-signed certificate and key for `shop.cks.local` (CN and SAN), valid 365 days.
2. Store them in a TLS secret `shop-tls` in namespace `shop`.
3. Create an Ingress `shop` (class `nginx`) for host `shop.cks.local`, path `/` (Prefix) to Service `shop:80`, terminating TLS with `shop-tls`.
4. Plain HTTP requests must be redirected to HTTPS.

Test: `curl -k --resolve shop.cks.local:30443:<node-ip> https://shop.cks.local:30443` returns `shop ok`.

## Task 3 (4%) - Verify platform binaries

On `cks-worker`, `/opt/binaries/` contains three `kubectl` binaries. Only binaries identical to the official Kubernetes **v1.35.9 linux/arm64** `kubectl` release may stay. Delete the others.

---

## Exam habits to practise today

- **kube-bench**: `kube-bench run --targets master --check 1.2.15` runs one check and prints its *remediation* text. Read it and do what it says, then re-run the same check. Targets: `master`, `node`, `etcd`, `policies`.
- After editing a static pod manifest, wait until **all** control plane pods are `Running` and `READY 1/1` before the next step (`watch crictl ps`). Other components (scheduler, ingress controller) recover a minute after the API server returns: don't panic on a 404 or `0/1` right away.
- add group: `sudo groupadd -r etcd`
- add user: `sudo useradd -r -g etcd -d /var/lib/etcd -s /sbin/nologin -c "etcd user" etcd`
- Manifest flags go in the `command:` list, one per line: `- --profiling=false`. Keep indentation identical to the neighbours.
- `kubectl create secret tls NAME --cert --key` and `kubectl create ingress NAME --class nginx --rule "host/*=svc:80,tls=secret"` save typing. Look at `kubectl create ingress -h` for the rule syntax.
- openssl one-liner for a self-signed cert: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=host" -addext "subjectAltName=DNS:host"`. Check it with `openssl x509 -in tls.crt -noout -subject -ext subjectAltName`.
- Release checksums: `https://dl.k8s.io/release/<version>/bin/linux/<arch>/<binary>.sha512` contains **only the hash**, so `sha512sum -c` cannot read it directly. Compare by eye or with `echo "$(cat kubectl.sha512)  kubectl" | sha512sum -c`.
- Docs: kubernetes.io "Ingress" → TLS section; "Certificates" task page for openssl; "Install and Set Up kubectl on Linux" shows the checksum validation commands.
