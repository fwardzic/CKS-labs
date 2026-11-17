#!/usr/bin/env bash
# Run on the Mac. Grades Day 6.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh
S="$K -n secure"

section "Task 1: AppArmor"
check "profile k8s-deny-write loaded in enforce mode on cks-worker" \
  "aa-status --json | jq -e '.profiles[\"k8s-deny-write\"] == \"enforce\"'" "$WORKER"
check "pod writer runs on cks-worker" \
  "$S get pod writer -o jsonpath='{.spec.nodeName} {.status.phase}' | grep -qx 'cks-worker Running'"
check "writer uses securityContext.appArmorProfile Localhost k8s-deny-write" \
  "$S get pod writer -o json | jq -e '[.spec.securityContext.appArmorProfile, .spec.containers[].securityContext.appArmorProfile] | map(select(. != null)) | any(.type == \"Localhost\" and .localhostProfile == \"k8s-deny-write\")'"
check "writes inside writer are denied" "$S exec writer -- true && ! $S exec writer -- touch /tmp/test"
check "process in writer is confined by k8s-deny-write" \
  "$S exec writer -- cat /proc/1/attr/current | grep -q 'k8s-deny-write (enforce)'"

section "Task 2: seccomp"
check "profile installed at /var/lib/kubelet/seccomp/profiles/no-chmod.json" \
  "jq -e '.defaultAction == \"SCMP_ACT_ALLOW\"' /var/lib/kubelet/seccomp/profiles/no-chmod.json" "$WORKER"
check "pod no-chmod runs on cks-worker with Localhost profile" \
  "$S get pod no-chmod -o json | jq -e '.spec.nodeName == \"cks-worker\" and .status.phase == \"Running\" and ([.spec.securityContext.seccompProfile, .spec.containers[].securityContext.seccompProfile] | map(select(. != null)) | any(.type == \"Localhost\" and .localhostProfile == \"profiles/no-chmod.json\"))'"
check "chmod fails inside no-chmod" "$S exec no-chmod -- true && ! $S exec no-chmod -- chmod 700 /tmp"
check "other syscalls still work in no-chmod" "$S exec no-chmod -- touch /tmp/ok"
check "deployment api uses RuntimeDefault at pod level" \
  "$S get deploy api -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}' | grep -qx RuntimeDefault"
check "deployment api fully rolled out" \
  "$S get deploy api -o json | jq -e '.status.updatedReplicas == 2 and .status.readyReplicas == 2 and .status.replicas == 2'"

section "Task 3: host footprint on cks-worker"
check "nothing listens on TCP 4444" "! ss -Htln 'sport = :4444' | grep -q ."  "$WORKER"
check "node-agent service stopped and disabled" \
  "! systemctl is-active -q node-agent && ! systemctl is-enabled -q node-agent" "$WORKER"
check "node-agent unit file removed" "[ ! -e /etc/systemd/system/node-agent.service ]" "$WORKER"
check "socat package removed" "! dpkg -s socat 2>/dev/null | grep -q 'Status: install ok installed'" "$WORKER"
check "contractor not in sudo group" "id -nG contractor && ! id -nG contractor | grep -qw sudo" "$WORKER"
check "contractor has no sudo rights" "id contractor && sudo -l -U contractor | grep -q 'not allowed'" "$WORKER"

summary
