#!/usr/bin/env bash
# Run on the Mac. Grades Day 14 (mock exam). Score is weighted like the exam: each task's
# weight x the share of its checks that pass. Pass mark 67%.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh

tw=0; tp=0; tt=0; got=0; max=0; tname=""
task() {
  [ -n "$tname" ] && flush
  tname="$1"; tw="$2"; tp=$pass; tt=$total
  section "$1 ($2%)"
}
flush() {
  local n=$((total - tt)) p=$((pass - tp))
  got=$(python3 -c "print($got + $tw * $p / $n)"); max=$((max + tw))
}
ETCD="etcdctl --endpoints https://127.0.0.1:2379 --cacert /etc/kubernetes/pki/etcd/ca.crt --cert /etc/kubernetes/pki/etcd/server.crt --key /etc/kubernetes/pki/etcd/server.key"
M=/etc/kubernetes/manifests/kube-apiserver.yaml
LOG=/var/log/kubernetes/audit/audit.log
STAMP="mock$RANDOM"
WIP="$(node_ip $WORKER)"

# test manifests for Task 12
_t="$(remote "$CP" <<'EOF'
cat > /tmp/mock-nolimit.yaml <<'Y'
apiVersion: v1
kind: Pod
metadata: {name: vap-test}
spec:
  containers:
  - {name: a, image: nginx:1.29-alpine}
  - name: b
    image: busybox:1.37
    resources: {limits: {cpu: 100m, memory: 64Mi}}
Y
cat > /tmp/mock-limit.yaml <<'Y'
apiVersion: v1
kind: Pod
metadata: {name: vap-test}
spec:
  containers:
  - name: a
    image: nginx:1.29-alpine
    resources: {limits: {cpu: 100m, memory: 64Mi}}
Y
EOF
)"

task "Task 1: RBAC" 4
A="--as system:serviceaccount:mock-ops:automation -n mock-ops"
V="--as system:serviceaccount:mock-ops:viewer"
check "Role automation has no wildcards" "! $K -n mock-ops get role automation -o json | jq -e '.rules[] | (.verbs + .resources + .apiGroups)[] | select(. == \"*\")'"
check "automation: get,list,watch,update,patch deployments" \
  "for v in get list watch update patch; do $K auth can-i \$v deployments.apps $A | grep -qx yes || exit 1; done"
check "automation: get,list pods" "$K auth can-i get pods $A | grep -qx yes && $K auth can-i list pods $A | grep -qx yes"
check "automation: nothing else (delete deploy, create pods, secrets)" \
  "$K auth can-i delete deployments.apps $A | grep -qx no && $K auth can-i create pods $A | grep -qx no && $K auth can-i get secrets $A | grep -qx no && $K auth can-i watch pods $A | grep -qx no"
check "ClusterRoleBinding viewer-view removed" "! $K get clusterrolebinding viewer-view"
check "RoleBinding mock-ops/viewer-view -> ClusterRole view" \
  "$K -n mock-ops get rolebinding viewer-view -o json | jq -e '.roleRef.kind == \"ClusterRole\" and .roleRef.name == \"view\" and .subjects[0].name == \"viewer\"'"
check "viewer can view mock-ops only" "$K auth can-i list pods -n mock-ops $V | grep -qx yes && $K auth can-i list pods -n default $V | grep -qx no"

task "Task 2: NetworkPolicy" 6
X="$K -n mock-app exec"
check "default-deny in mock-db denies ingress and egress" \
  "$K -n mock-db get netpol default-deny -o json | jq -e '.spec.podSelector == {} and (.spec.policyTypes | sort) == [\"Egress\",\"Ingress\"] and (.spec.ingress // [] | length) == 0 and (.spec.egress // [] | length) == 0'"
check "backend -> db:80 allowed" "$X deploy/backend -- wget -qO- -T 3 http://db.mock-db"
check "backend -> cache denied" "! $X deploy/backend -- wget -qO- -T 3 http://cache.mock-db"
check "frontend -> db denied" "! $X frontend -- wget -qO- -T 3 http://db.mock-db"
check "db can resolve DNS" "$K -n mock-db exec db -- nslookup kubernetes.default.svc.cluster.local"
check "db egress elsewhere denied" "! $K -n mock-db exec db -- wget -qO- -T 3 http://cache.mock-db"

task "Task 3: Pod Security" 5
check "mock-app enforces restricted (latest) and warns restricted" \
  "$K get ns mock-app -o json | jq -e '.metadata.labels[\"pod-security.kubernetes.io/enforce\"] == \"restricted\" and .metadata.labels[\"pod-security.kubernetes.io/enforce-version\"] == \"latest\" and .metadata.labels[\"pod-security.kubernetes.io/warn\"] == \"restricted\"'"
check "backend rolled out under restricted" \
  "$K get ns mock-app -o jsonpath='{.metadata.labels.pod-security\\.kubernetes\\.io/enforce}' | grep -qx restricted && $K -n mock-app get deploy backend -o json | jq -e '.status.readyReplicas >= 1 and .status.updatedReplicas == .spec.replicas and .status.replicas == .spec.replicas'"
check "backend pods pass restricted" "! $K label --dry-run=server --overwrite ns mock-app pod-security.kubernetes.io/enforce=restricted 2>&1 | grep -qi warning"
check "backend pods have no ServiceAccount token" \
  "$K -n mock-app get pod -l app=backend -o json | jq -e '[.items[].spec.volumes[]?.name | select(startswith(\"kube-api-access\"))] | length == 0'"

task "Task 4: API server and audit" 7
check "--profiling=false and --tls-min-version=VersionTLS12" "grep -q -- '--profiling=false' $M && grep -q -- '--tls-min-version=VersionTLS12' $M"
check "audit flags (policy, path, maxage 10, maxbackup 3, maxsize 100)" \
  "for f in audit-policy-file=/etc/kubernetes/audit/policy.yaml audit-log-path=$LOG audit-log-maxage=10 audit-log-maxbackup=3 audit-log-maxsize=100; do grep -q -- \"--\$f\" $M || exit 1; done"
check "API server healthy" "$K get --raw /readyz && $K -n kube-system get pod kube-apiserver-cks-cp -o jsonpath='{.status.containerStatuses[0].ready}' | grep -qx true"
_g="$(on "$CP" "$K -n mock-ops get secret ops-token -o name; $K -n mock-ops create role $STAMP --verb get --resource pods; $K -n mock-ops delete role $STAMP; $K -n mock-ops get pods; $K -n mock-ops exec deploy/worker -- true; sleep 3" 2>&1)"
check "secrets logged at Metadata" "grep '\"name\":\"ops-token\"' $LOG | tail -1 | jq -e '.level == \"Metadata\"'"
check "RBAC changes logged at RequestResponse" "grep '\"name\":\"$STAMP\"' $LOG | jq -s -e 'map(select(.verb==\"create\")) | .[0].level == \"RequestResponse\" and (.[0].requestObject != null)'"
check "pods/exec logged" "tail -300 $LOG | jq -c 'select(.objectRef.subresource==\"exec\" and .objectRef.namespace==\"mock-ops\")' | grep -q ."
check "pod list not logged, no RequestReceived" \
  "[ -s $LOG ] && ! tail -500 $LOG | jq -c 'select(.objectRef.resource==\"pods\" and .verb==\"list\" and (.objectRef.subresource // \"\") == \"\")' | grep -q . && ! tail -500 $LOG | grep -q '\"stage\":\"RequestReceived\"'"

task "Task 5: Encryption at rest" 6
check "encryption config wired into kube-apiserver" "grep -q -- '--encryption-provider-config=/etc/kubernetes/enc/enc.yaml' $M"
check "config: aesgcm first with key k1, identity last" \
  "python3 -c \"import yaml,sys; c=yaml.safe_load(open('/etc/kubernetes/enc/enc.yaml')); r=[x for x in c['resources'] if 'secrets' in x['resources']][0]['providers']; sys.exit(0 if 'aesgcm' in r[0] and r[0]['aesgcm']['keys'][0]['name']=='k1' and 'identity' in r[-1] else 1)\""
check "all Secrets in etcd encrypted with aesgcm:k1" \
  "$ETCD get --prefix /registry/secrets/ -w json | python3 -c \"import sys,json,base64; kv=json.load(sys.stdin)['kvs']; bad=[base64.b64decode(k['key']) for k in kv if not base64.b64decode(k['value']).startswith(b'k8s:enc:aesgcm:v1:k1:')]; print(len(kv), bad[:3]); sys.exit(1 if bad or not kv else 0)\""

task "Task 6: AppArmor and seccomp" 6
S="$K -n mock-sys"
check "profile mock-deny-etc loaded in enforce mode on cks-worker" "aa-status | sed -n '/enforce mode/,/complain mode/p' | grep -qx '   mock-deny-etc'" "$WORKER"
check "pod guarded on cks-worker confined by mock-deny-etc (field, not annotation)" \
  "$S get pod guarded -o json | jq -e '.spec.nodeName == \"cks-worker\" and ([.spec.securityContext.appArmorProfile, .spec.containers[0].securityContext.appArmorProfile][] | select(. != null) | .localhostProfile == \"mock-deny-etc\")' && $S exec guarded -- cat /proc/1/attr/current | grep -q 'mock-deny-etc (enforce)'"
check "guarded cannot write to /etc" "! $S exec guarded -- touch /etc/x && $S exec guarded -- touch /tmp/x"
check "seccomp profile installed in /var/lib/kubelet/seccomp/profiles/" "cmp /opt/mock/seccomp/block-mkdir.json /var/lib/kubelet/seccomp/profiles/block-mkdir.json" "$WORKER"
check "pod nomkdir uses it and cannot mkdir" \
  "$S get pod nomkdir -o json | jq -e '[.spec.securityContext.seccompProfile, .spec.containers[0].securityContext.seccompProfile][] | select(. != null) | .localhostProfile == \"profiles/block-mkdir.json\"' && ! $S exec nomkdir -- mkdir /tmp/d && $S exec nomkdir -- touch /tmp/f"

task "Task 7: gVisor" 5
check "RuntimeClass sandbox with handler runsc" "$K get runtimeclass sandbox -o jsonpath='{.handler}' | grep -qx runsc"
check "pod untrusted uses it and runs in gVisor" \
  "$S get pod untrusted -o jsonpath='{.spec.runtimeClassName}' | grep -qx sandbox && $S exec untrusted -- dmesg | grep -qi gvisor"
check "other pods still use runc" "[ -z \"\$($S get pod guarded -o jsonpath='{.spec.runtimeClassName}')\" ] && $S get pod guarded && ! $S exec guarded -- dmesg 2>&1 | grep -qi gvisor"

task "Task 8: Falco" 6
R="$K -n mock-runtime"
check "rule 'Netcat in container' (CRITICAL) in local rules" \
  "grep -A8 'rule: Netcat in container' /etc/falco/falco_rules.local.yaml | grep -qi 'priority: *critical'" "$WORKER"
check "Falco running" "systemctl is-active -q falco-modern-bpf" "$WORKER"
check "alerts in the requested format" \
  "journalctl -u falco-modern-bpf --no-pager | grep -E 'Netcat in container \\| pod=probe-[a-z0-9-]+ ns=mock-runtime image=docker.io/library/busybox cmd=nc -z -w 1 db.mock-db 80' | grep -q ." "$WORKER"
check "probe scaled to 0" "$R get deploy probe -o jsonpath='{.spec.replicas}' | grep -qx 0"
check "ticker and web untouched" "$R get deploy ticker web -o jsonpath='{.items[*].status.readyReplicas}' | grep -qx '1 1'"

task "Task 9: Trivy" 4
for p in proxy:nginx:1.21-alpine base:alpine:3.22 memcache:memcached:1.6-alpine tools:busybox:1.37; do
  name="${p%%:*}"; image="${p#*:}"
  crit="$(on "$CP" "trivy image -q --scanners vuln --severity CRITICAL --format json $image 2>/dev/null | jq '[.Results[]?.Vulnerabilities[]?] | length'" 2>/dev/null)"
  if [ "${crit:-0}" -gt 0 ]; then
    check "pod $name ($image, $crit CRITICAL) deleted" "$K -n mock-scan get pod $name 2>&1 | grep -q NotFound"
  else
    check "pod $name ($image, no CRITICAL) still running" "$K -n mock-scan get pod $name -o jsonpath='{.status.phase}' | grep -qx Running"
  fi
done

task "Task 10: Signed binaries" 4
check "only kube-tool-v1.2 (+ bundle, key) left" \
  "[ \"\$(ls /opt/mock/release | sort | tr '\\n' ' ')\" = 'cosign.pub kube-tool-v1.2 kube-tool-v1.2.bundle ' ]"
check "kube-tool-v1.2 still verifies" \
  "cd /opt/mock/release && cosign verify-blob --key cosign.pub --bundle kube-tool-v1.2.bundle --insecure-ignore-tlog=true kube-tool-v1.2"
check "/root/mock/kube-tool.sha512 = sha512sum of it" "cd /opt/mock/release && grep -q \$(sha512sum kube-tool-v1.2 | cut -d' ' -f1) /root/mock/kube-tool.sha512"

task "Task 11: Ephemeral debug container" 4
check "ephemeral container debugger (busybox:1.37) targets app" \
  "$K -n mock-debug get pod legacy-api -o json | jq -e '[.spec.ephemeralContainers[]? | select(.name==\"debugger\" and .image==\"busybox:1.37\" and .targetContainerName==\"app\")] | length == 1'"
check "debugger started" "$K -n mock-debug get pod legacy-api -o json | jq -e '.status.ephemeralContainerStatuses[]? | select(.name==\"debugger\") | .state.running or .state.terminated'"
check "/root/mock/legacy-cmdline.txt = /pause" "tr -d '\\0\\n' < /root/mock/legacy-cmdline.txt | grep -qx /pause"

task "Task 12: ValidatingAdmissionPolicy" 6
check "policy require-limits + binding require-limits (Deny)" \
  "$K get validatingadmissionpolicy require-limits && $K get validatingadmissionpolicybinding require-limits -o json | jq -e '.spec.validationActions | index(\"Deny\")'"
check "pod with a container lacking limits denied in mock-prod" "! $K -n mock-prod apply --dry-run=server -f /tmp/mock-nolimit.yaml"
check "pod with limits allowed in mock-prod" "$K -n mock-prod apply --dry-run=server -f /tmp/mock-limit.yaml"
check "other namespaces not affected" "$K -n mock-ops apply --dry-run=server -f /tmp/mock-nolimit.yaml"
check "deployment api runs 2 pods with cpu 200m / memory 128Mi limits" \
  "$K -n mock-prod get deploy api -o json | jq -e '.status.readyReplicas == 2 and .status.updatedReplicas == 2 and .spec.template.spec.containers[0].resources.limits.cpu == \"200m\" and .spec.template.spec.containers[0].resources.limits.memory == \"128Mi\"'"

task "Task 13: Risky workloads, immutability" 5
check "/root/mock/risky.txt lists exactly the risky Deployments" \
  "[ \"\$(sort /root/mock/risky.txt | grep -v '^\$' | tr '\\n' ' ')\" = 'mock-legacy/fs-agent mock-legacy/metrics mock-runtime/debug-shell ' ]"
check "they are scaled to 0" "for d in mock-legacy/fs-agent mock-legacy/metrics mock-runtime/debug-shell; do $K -n \${d%/*} get deploy \${d#*/} -o jsonpath='{.spec.replicas}' | grep -qx 0 || exit 1; done"
check "mock-legacy/web: readOnlyRootFilesystem, serving" \
  "$K -n mock-legacy get deploy web -o json | jq -e '.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem == true and .status.readyReplicas == 1 and .status.updatedReplicas == 1' && ! $K -n mock-legacy exec deploy/web -- touch /usr/share/nginx/html/x && $K -n mock-legacy exec deploy/web -- wget -qO- -T 3 http://127.0.0.1"

task "Task 14: kubelet" 6
check "anonymous requests to the kubelet rejected" "curl -sk -m 3 -o /dev/null -w '%{http_code}' https://$WIP:10250/pods | grep -qx 401"
check "kubelet authorization mode Webhook" "grep -A1 '^authorization:' /var/lib/kubelet/config.yaml | grep -q 'mode: Webhook'" "$WORKER"
check "read-only port 10255 closed" "! curl -s -m 3 http://$WIP:10255/pods"
check "kubelet config file mode 600 or stricter" "[ \$(( 0\$(stat -c %a /var/lib/kubelet/config.yaml) & 077 )) -eq 0 ]" "$WORKER"
check "cks-worker Ready, kubectl logs works" "$K get node cks-worker | grep -qw Ready && $K -n mock-runtime logs deploy/web --tail 1"

task "Task 15: User via CSR API" 5
check "CSR auditor approved and issued" "$K get csr auditor -o json | jq -e '.spec.signerName == \"kubernetes.io/kube-apiserver-client\" and (.status.conditions[]? | .type == \"Approved\") and (.status.certificate | length > 0)'"
check "auditor.kubeconfig authenticates as auditor" \
  "kubectl --kubeconfig /root/mock/auditor.kubeconfig auth whoami -o json | jq -e '.status.userInfo.username == \"auditor\"'"
check "auditor can get/list pods and events everywhere" \
  "for r in pods events; do for v in get list; do kubectl --kubeconfig /root/mock/auditor.kubeconfig auth can-i \$v \$r -A | grep -qx yes || exit 1; done; done"
check "auditor can do nothing else" \
  "U='kubectl --kubeconfig /root/mock/auditor.kubeconfig auth can-i'; \$U get secrets -A | grep -qx no && \$U delete pods -n default | grep -qx no && \$U watch pods -A | grep -qx no"

flush
summary
python3 -c "g=$got; m=$max; print(f'Weighted: {g:.1f}/{m}% = {100*g/m:.0f}% (pass mark 67%)')"
