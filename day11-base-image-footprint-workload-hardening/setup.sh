#!/usr/bin/env bash
# Run on the Mac. Day 11: Dockerfile hardening, static review, image digests, securityContext.
set -euo pipefail
cd "$(dirname "$0")"
source ../lib.sh

remote "$CP" <<'EOF'
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /root/day11/image /root/day11/review /root/day11/insecure

cat > /root/day11/image/Dockerfile <<'D'
FROM ubuntu
RUN apt-get update
RUN apt-get install -y curl ca-certificates
ENV TOKEN=2e064aad-3a90-4cde-ad86-16fad1f8943e
ENV API_URL=https://api.example.com/v1/report
CMD ["sh", "-c", "curl -s -H \"Authorization: Bearer $TOKEN\" $API_URL"]
D

cat > /root/day11/review/app1-a.Dockerfile <<'D'
FROM golang:1.25 AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -o /out/app .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/app /app
USER 65532:65532
ENTRYPOINT ["/app"]
D
cat > /root/day11/review/app1-b.Dockerfile <<'D'
FROM golang:1.25 AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -o /out/app .

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y curl netcat-openbsd && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/app /app
USER 65532:65532
ENTRYPOINT ["/app"]
D

cat > /root/day11/review/app2-a.yaml <<'D'
apiVersion: v1
kind: Pod
metadata:
  name: app2
spec:
  hostPID: true
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: registry.example.com/app2:1.4.2
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
D
cat > /root/day11/review/app2-b.yaml <<'D'
apiVersion: v1
kind: Pod
metadata:
  name: app2
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: registry.example.com/app2:1.4.2
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
D

cat > /root/day11/review/app3-a.yaml <<'D'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app3
spec:
  replicas: 2
  selector:
    matchLabels: {app: app3}
  template:
    metadata:
      labels: {app: app3}
    spec:
      automountServiceAccountToken: false
      containers:
      - name: app
        image: registry.example.com/app3:2.0.1
        securityContext:
          runAsNonRoot: true
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: cache
          mountPath: /var/cache/app
      volumes:
      - name: cache
        emptyDir: {}
D
cat > /root/day11/review/app3-b.yaml <<'D'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app3
spec:
  replicas: 2
  selector:
    matchLabels: {app: app3}
  template:
    metadata:
      labels: {app: app3}
    spec:
      automountServiceAccountToken: false
      containers:
      - name: app
        image: registry.example.com/app3:2.0.1
        securityContext:
          runAsNonRoot: true
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: cache
          mountPath: /var/run/containerd
      volumes:
      - name: cache
        hostPath:
          path: /var/run/containerd
D

cat > /root/day11/sts.yaml <<'D'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: node-tuner
  namespace: infra
spec:
  serviceName: node-tuner
  replicas: 1
  selector:
    matchLabels:
      app: node-tuner
  template:
    metadata:
      labels:
        app: node-tuner
    spec:
      securityContext:
        privileged: true
      containers:
      - name: tuner
        image: busybox:1.37
        command: ["sleep", "1d"]
D

kubectl create ns hardening
kubectl create ns infra
kubectl -n hardening create deployment web --image=nginx:1.29-alpine --replicas 2
kubectl -n hardening create deployment logger --image=busybox:1.37 -- \
  sh -c 'while true; do id; grep NoNewPrivs /proc/self/status; sleep 5; done'
kubectl -n hardening rollout status deploy --timeout=180s
# remember the digest of the image the web pods run (used by check.sh)
kubectl -n hardening get pod -l app=web -o jsonpath='{.items[0].status.containerStatuses[0].imageID}' \
  | sed 's/.*@//' > /root/.day11-digest
EOF
echo "Setup done. Read README.md and start. Grade with ./check.sh"
