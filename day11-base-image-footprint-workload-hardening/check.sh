#!/usr/bin/env bash
# Run on the Mac. Grades Day 11.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh
H="$K -n hardening"
DF=/root/day11/image/Dockerfile
R=/root/day11/review
I=/root/day11/insecure

section "Task 1: Dockerfile"
check "base image pinned to ubuntu:24.04" "grep -E '^FROM ' $DF | grep -Eqx 'FROM +(docker.io/library/)?ubuntu:24.04( +AS +\\S+)?'"
check "apt-get update and install in one RUN, package lists removed" \
  "[ \$(grep -c 'apt-get' $DF) -ge 1 ] && [ \$(grep -E '^RUN' $DF | grep -c apt-get) -eq 1 ] && grep -E '^RUN' $DF | grep apt-get | grep 'apt-get update' | grep 'apt-get install' | grep -q 'rm -rf /var/lib/apt/lists'"
check "no hard-coded token in the Dockerfile" "! grep -q 2e064aad $DF && ! grep -Eq '^(ENV|ARG)[[:space:]]+TOKEN' $DF"
check "user app (UID 10001) created and used" \
  "grep -E '^RUN' $DF | grep -Eq '(useradd|adduser).*(-u|--uid) *10001' && grep -E '^USER' $DF | tail -1 | grep -Eqx 'USER +(app|10001)(:[^ ]+)?'"
check "bash removed from the image (before switching user)" \
  "L=\$(grep -nE '^RUN.*rm .*(/usr)?/bin/bash' $DF | tail -1 | cut -d: -f1); U=\$(grep -nE '^USER' $DF | tail -1 | cut -d: -f1); [ -n \"\$L\" ] && [ -n \"\$U\" ] && [ \$L -lt \$U ]"
check "CMD still calls the API with \$TOKEN" "grep -E '^CMD' $DF | grep -q 'TOKEN'"

section "Task 2: static review"
check "insecure files moved: app1-b, app2-a, app3-b" \
  "[ \"\$(ls $I | sort | tr '\\n' ' ')\" = 'app1-b.Dockerfile app2-a.yaml app3-b.yaml ' ]"
check "secure files left in review/" \
  "[ \"\$(ls $R | sort | tr '\\n' ' ')\" = 'app1-a.Dockerfile app2-b.yaml app3-a.yaml ' ]"

section "Task 3: image digest"
D="$(on "$CP" 'cat /root/.day11-digest' 2>/dev/null)"
check "deployment web uses nginx by digest (no tag)" \
  "$H get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -Eqx '(docker.io/library/)?nginx@$D'"
check "web rolled out with 2 ready pods" "$H get deploy web -o json | jq -e '.status.updatedReplicas == 2 and .status.readyReplicas == 2'"

section "Task 4: securityContext"
check "logger: allowPrivilegeEscalation false, drop ALL" \
  "$H get deploy logger -o json | jq -e '.spec.template.spec.containers[0].securityContext | .allowPrivilegeEscalation == false and (.capabilities.drop | index(\"ALL\"))'"
check "logger logs show NoNewPrivs 1 and uid=1000 gid=3000" \
  "$H rollout status deploy logger --timeout=60s && for i in \$(seq 40); do [ \$($H get pod -l app=logger --no-headers | wc -l) -eq 1 ] && break; sleep 2; done && sleep 6 && L=\$($H logs deploy/logger --tail 4) && echo \"\$L\" | grep -Eq 'NoNewPrivs:\\s+1' && echo \"\$L\" | grep -q 'uid=1000 gid=3000'"
check "statefulset infra/node-tuner running" "$K -n infra get sts node-tuner -o jsonpath='{.status.readyReplicas}' | grep -qx 1"
check "node-tuner container runs privileged" \
  "$K -n infra exec node-tuner-0 -- grep CapEff /proc/1/status | grep -q 'ffffffffff'"
check "/root/day11/sts.yaml fixed in place" "$K apply --dry-run=server -f /root/day11/sts.yaml"

summary
