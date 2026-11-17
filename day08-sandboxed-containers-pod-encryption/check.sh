#!/usr/bin/env bash
# Run on the Mac. Grades Day 8.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh
AGENT="$K -n kube-system exec ds/cilium -c cilium-agent --"
WAGENT="$K -n kube-system exec \$($K -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=cks-worker -o name) -c cilium-agent --"

section "Task 1: gVisor"
check "RuntimeClass gvisor with handler runsc" "$K get runtimeclass gvisor -o jsonpath='{.handler}' | grep -qx runsc"
check "pod isolated/sandboxed Running on cks-worker with runtimeClassName gvisor" \
  "$K -n isolated get pod sandboxed -o json | jq -e '.spec.runtimeClassName == \"gvisor\" and .spec.nodeName == \"cks-worker\" and .status.phase == \"Running\"'"
check "sandboxed really runs in gVisor (dmesg)" "$K -n isolated exec sandboxed -- dmesg | grep -qi gvisor"
check "normal pods on cks-worker still start (runc)" \
  "$K -n mesh get deploy web -o jsonpath='{.status.readyReplicas}' | grep -qx 1"

section "Task 2: Cilium transparent encryption"
check "cilium-config enables WireGuard" "$K -n kube-system get cm cilium-config -o jsonpath='{.data.enable-wireguard}' | grep -qx true"
check "agent on cks-cp reports Wireguard encryption" "$AGENT cilium-dbg status | grep -E '^Encryption:' | grep -q Wireguard"
check "agent on cks-worker has a WireGuard peer" "$WAGENT cilium-dbg encrypt status | grep -qE 'Number of peers: *[1-9]'"
check "Cilium healthy on both nodes" "cilium status --wait --wait-duration 60s"

section "Task 3: Istio mTLS"
check "namespace mesh has sidecar injection enabled" \
  "$K get ns mesh -o jsonpath='{.metadata.labels.istio-injection}' | grep -qx enabled"
check "all running pods in mesh have an istio-proxy sidecar" \
  "$K -n mesh get pods --field-selector status.phase=Running -o json | jq -e '(.items | length) >= 2 and all(.items[]; [.spec.containers[].name, .spec.initContainers[]?.name] | index(\"istio-proxy\") != null)'"
check "PeerAuthentication in mesh is STRICT" \
  "$K -n mesh get peerauthentication -o json | jq -e 'any(.items[]; (.spec.selector == null) and .spec.mtls.mode == \"STRICT\")'"
check "mesh/client -> web works (mTLS)" "$K -n mesh exec deploy/client -- curl -sf -m 5 -o /dev/null http://web.mesh"
check "outside/client (no sidecar) -> web rejected" \
  "$K -n outside exec deploy/client -- true && ! $K -n outside exec deploy/client -- curl -sf -m 5 -o /dev/null http://web.mesh"

summary
