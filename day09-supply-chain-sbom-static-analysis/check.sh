#!/usr/bin/env bash
# Run on the Mac. Grades Day 9.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh
D=/root/day9
M=/etc/kubernetes/manifests/kube-apiserver.yaml
dry() { # ns name image -> server-side dry-run pod create
  echo "$K -n $1 run $2 --image $3 --dry-run=server -o name"
}

section "Task 1: trivy"
for p in web-old:nginx:1.19-alpine httpd:httpd:2.4.46-alpine web-new:nginx:1.29-alpine cache:redis:7.4-alpine toolbox:busybox:1.37; do
  name=${p%%:*}; image=${p#*:}
  crit="$(on "$CP" "trivy image -q --scanners vuln --severity CRITICAL --format json $image 2>/dev/null | jq '[.Results[]?.Vulnerabilities[]?] | length'" 2>/dev/null)"
  if [ "${crit:-0}" -gt 0 ]; then
    check "pod $name ($image, $crit CRITICAL) deleted" "$K -n team-x get pod $name 2>&1 | grep -q NotFound"
  else
    check "pod $name ($image, no CRITICAL) still running" "$K -n team-x get pod $name -o jsonpath='{.status.phase}' | grep -qx Running"
  fi
done

section "Task 2: SBOM"
check "$D/nginx.spdx.json is SPDX JSON for nginx:1.29-alpine (bom)" \
  "jq -e '(.spdxVersion | startswith(\"SPDX-\")) and ([.packages[].name] | index(\"libssl3\") != null) and (tostring | test(\"nginx\"))' $D/nginx.spdx.json"
check "$D/nginx.cdx.json is CycloneDX JSON" "jq -e '.bomFormat == \"CycloneDX\" and (.components | length > 0)' $D/nginx.cdx.json"
check "$D/libssl3.txt holds the libssl3 version from the SBOM" \
  "v=\$(jq -r '.components[] | select(.name==\"libssl3\") | .version' $D/nginx.cdx.json | head -1); [ -n \"\$v\" ] && [ \"\$(tr -d '[:space:]' < $D/libssl3.txt)\" = \"\$v\" ]"

section "Task 3: static analysis"
check "kubesec: no critical findings in $D/tools.yaml" "kubesec scan $D/tools.yaml | jq -e '(.[0].scoring.critical // []) | length == 0'"
check "kubesec: score >= 4" "kubesec scan $D/tools.yaml | jq -e '.[0].score >= 4'"
check "kube-linter: no findings in $D/tools.yaml" "kube-linter lint $D/tools.yaml"
check "deployment supply/tools running from that manifest" \
  "$K -n supply get deploy tools -o json | jq -e '.status.readyReplicas == 1 and .spec.template.spec.hostPID != true and (.spec.template.spec.containers[0].securityContext.privileged != true)'"

section "Task 4: ImagePolicyWebhook"
check "ImagePolicyWebhook enabled" "grep -E -- '--enable-admission-plugins=.*ImagePolicyWebhook' $M"
check "NodeRestriction still enabled" "grep -E -- '--enable-admission-plugins=.*NodeRestriction' $M"
check "--admission-control-config-file points to the policywebhook config" \
  "grep -q -- '--admission-control-config-file=/etc/kubernetes/policywebhook/admission_config.yaml' $M"
check "defaultAllow is false" "grep -E 'defaultAllow: *false' /etc/kubernetes/policywebhook/admission_config.yaml"
check "API server healthy" "$K get --raw /readyz"
check "pod with nginx:latest is denied" "! $(dry default t-latest nginx:latest)"
check "pod with untagged image is denied" "! $(dry default t-untagged busybox)"
check "pod with nginx:1.29-alpine is allowed" "$(dry default t-ok nginx:1.29-alpine)"
tag="1.29.$RANDOM"   # fresh image: not in the webhook's decision cache
check "backend down -> pods denied (defaultAllow false)" \
  "systemctl stop image-policy; sleep 2; ! $(dry default t-down nginx:$tag); r=\$?; systemctl start image-policy; exit \$r"

section "Task 5: ValidatingAdmissionPolicy"
check "ValidatingAdmissionPolicy allowed-registries exists" "$K get validatingadmissionpolicy allowed-registries"
check "binding scoped to namespace supply with Deny" \
  "$K get validatingadmissionpolicybindings -o json | jq -e 'any(.items[]; .spec.policyName == \"allowed-registries\" and (.spec.validationActions | index(\"Deny\") != null))'"
check "supply: quay.io image denied" "! $(dry supply t-quay quay.io/prometheus/busybox:latest-x)"
check "supply: docker.io/library image allowed" "$(dry supply t-dh docker.io/library/nginx:1.29-alpine)"
check "supply: registry.k8s.io image allowed" "$(dry supply t-k8s registry.k8s.io/pause:3.10)"
check "supply: short name nginx:1.29-alpine denied" "! $(dry supply t-short nginx:1.29-alpine)"
check "other namespaces unaffected (quay.io allowed in default)" "$(dry default t-quay2 quay.io/prometheus/busybox:glibc)"

summary
