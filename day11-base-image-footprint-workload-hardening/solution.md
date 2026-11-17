# Day 11 solution

## Task 1

`/root/day11/image/Dockerfile`:

```dockerfile
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y curl ca-certificates && rm -rf /var/lib/apt/lists/*
RUN useradd -u 10001 -m app && rm -f /usr/bin/bash /bin/bash
ENV API_URL=https://api.example.com/v1/report
USER app
CMD ["sh", "-c", "curl -s -H \"Authorization: Bearer $TOKEN\" $API_URL"]
```

The token is passed at runtime: `docker run -e TOKEN=... img`, or in Kubernetes `env` from a Secret (`valueFrom.secretKeyRef`). `rm` comes before `USER app`, because user `app` can't delete `/usr/bin/bash`. On Ubuntu 24.04 `/bin` is a symlink to `/usr/bin`.

## Task 2

```sh
cd /root/day11/review
diff app1-a.Dockerfile app1-b.Dockerfile   # b: full ubuntu final stage plus curl and netcat
diff app2-a.yaml app2-b.yaml               # a: hostPID: true
diff app3-a.yaml app3-b.yaml               # b: hostPath /var/run/containerd (the runtime socket)
mv app1-b.Dockerfile app2-a.yaml app3-b.yaml /root/day11/insecure/
```

## Task 3

```sh
k -n hardening get pod -l app=web -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'; echo
# docker.io/library/nginx@sha256:<digest>
k -n hardening set image deploy/web nginx=nginx@sha256:<digest>
k -n hardening rollout status deploy web
```

## Task 4

```sh
k -n hardening edit deploy logger
```

```yaml
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 3000
      containers:
      - name: busybox
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
```

```sh
k -n hardening logs deploy/logger --tail 2
# uid=1000 gid=3000 groups=3000
# NoNewPrivs:	1
```

StatefulSet:

```sh
k apply -f /root/day11/sts.yaml
# error: ... strict decoding error: unknown field "spec.template.spec.securityContext.privileged"
```

Move `privileged` to the container:

```yaml
    spec:
      containers:
      - name: tuner
        image: busybox:1.37
        command: ["sleep", "1d"]
        securityContext:
          privileged: true
```

```sh
k apply -f /root/day11/sts.yaml
k -n infra exec node-tuner-0 -- grep CapEff /proc/1/status   # 000001ffffffffff
```
