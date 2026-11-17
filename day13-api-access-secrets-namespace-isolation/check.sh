#!/usr/bin/env bash
# Run on the Mac. Grades Day 13.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh
V="$K -n vault-client"
S="$K -n ns-secure"
# reach FROM_NS TARGET -> HTTP from pod 'client' in FROM_NS to TARGET succeeds
reach() { echo "$K -n $1 exec client -- wget -qO- -T 3 http://$2"; }
TOKEN=/var/run/secrets/tokens/vault-token
JWT="$V exec client -- cat $TOKEN | cut -d. -f2 | python3 -c 'import sys,base64,json; s=sys.stdin.read().strip(); print(json.dumps(json.loads(base64.urlsafe_b64decode(s+\"=\"*(-len(s)%4)))))'"

section "Task 1: projected ServiceAccount token"
check "pod client running with ServiceAccount app" "$V get pod client -o jsonpath='{.status.phase} {.spec.serviceAccountName}' | grep -qx 'Running app'"
check "no default API token mounted" \
  "$V get pod client -o json | jq -e '.spec.automountServiceAccountToken == false and ([.spec.volumes[]?.name | select(startswith(\"kube-api-access\"))] | length == 0)' && ! $V exec client -- ls /var/run/secrets/kubernetes.io/serviceaccount"
check "token at $TOKEN has audience vault" "$JWT | jq -e '.aud == [\"vault\"]'"
check "token is valid for 1 hour" "$JWT | jq -e '.exp - .iat == 3600'"

section "Task 2: Secrets"
check "/root/day13/one.txt has exactly the Opaque values" \
  "[ \"\$(sort /root/day13/one.txt | grep -v '^\$' | tr '\\n' ' ')\" = '3f9a-alpha Gr33n!Lake svc-report ' ]"
check "ServiceAccount secret-manager exists" "$S get sa secret-manager"
check "pod secret-manager (httpd:alpine) runs with that ServiceAccount" \
  "$S get pod secret-manager -o jsonpath='{.status.phase} {.spec.serviceAccountName} {.spec.containers[0].image}' | grep -qx 'Running secret-manager httpd:alpine'"
check "env SEC_A1 = sec-a1 value, from the Secret" \
  "$S exec secret-manager -- printenv SEC_A1 | grep -qx a1-7d2c9e && $S get pod secret-manager -o json | jq -e '[.spec.containers[0].env[]? | select(.name==\"SEC_A1\") | .valueFrom.secretKeyRef.name] == [\"sec-a1\"]'"
check "sec-a2 mounted read-only at /etc/sec-a2" \
  "$S exec secret-manager -- grep -q host=db.internal /etc/sec-a2/config.ini && $S get pod secret-manager -o json | jq -e '[.spec.containers[0].volumeMounts[] | select(.mountPath==\"/etc/sec-a2\") | .readOnly] == [true]'"

section "Task 3: NetworkPolicies"
check "NetworkPolicy np exists in space1 and space2" "$K -n space1 get netpol np && $K -n space2 get netpol np"
check "space1 -> space2 allowed" "$(reach space1 web.space2)"
check "space1 -> other denied" "! $(reach space1 web.other)"
check "space1 -> space1 denied (egress only to space2)" "! $(reach space1 web.space1)"
check "space1 DNS works" "$K -n space1 exec client -- nslookup web.space2.svc.cluster.local"
check "other -> space2 denied" "! $(reach other web.space2)"
check "space2 -> space2 denied (ingress only from space1)" "! $(reach space2 web.space2)"
check "space2 egress not restricted (space2 -> other)" "$(reach space2 web.other)"
check "space1 ingress not restricted (other -> space1)" "$(reach other web.space1)"

section "Task 4: API exposure"
M=/etc/kubernetes/manifests/kube-apiserver.yaml
check "no --kubernetes-service-node-port in the manifest" "! grep -q kubernetes-service-node-port $M"
check "API server healthy" "$K get --raw /readyz && $K -n kube-system get pod kube-apiserver-cks-cp -o jsonpath='{.status.containerStatuses[0].ready}' | grep -qx true"
check "service kubernetes is ClusterIP" "$K get svc kubernetes -o jsonpath='{.spec.type}' | grep -qx ClusterIP"
check "port 31000 closed on the nodes" "! curl -sk -m 3 https://$(node_ip $CP):31000/version && ! curl -sk -m 3 https://$(node_ip $WORKER):31000/version"
check "authenticated users can't read secrets" \
  "$K auth can-i list secrets -A --as nobody --as-group system:authenticated | grep -qx no"
check "default system bindings kept" "$K get clusterrolebinding system:basic-user system:discovery system:public-info-viewer"

section "Task 5: user bob (manual certificate)"
D=/root/day13
check "bob.crt: CN=bob, O=platform" "openssl x509 -in $D/bob.crt -noout -subject | grep -Eq 'CN ?= ?bob' && openssl x509 -in $D/bob.crt -noout -subject | grep -Eq 'O ?= ?platform'"
check "bob.crt signed by the cluster CA, valid <= 31 days" \
  "openssl verify -CAfile /etc/kubernetes/pki/ca.crt $D/bob.crt && [ \$(( (\$(date -d \"\$(openssl x509 -in $D/bob.crt -noout -enddate | cut -d= -f2)\" +%s) - \$(date +%s)) / 86400 )) -le 31 ]"
check "bob.kubeconfig: context bob@cks, certs embedded" \
  "kubectl --kubeconfig $D/bob.kubeconfig config current-context | grep -qx bob@cks && grep -q client-certificate-data $D/bob.kubeconfig && grep -q client-key-data $D/bob.kubeconfig && ! grep -Eq 'client-(certificate|key):' $D/bob.kubeconfig"
check "bob authenticates as bob in group platform" \
  "kubectl --kubeconfig $D/bob.kubeconfig auth whoami -o json | jq -e '.status.userInfo.username == \"bob\" and (.status.userInfo.groups | index(\"platform\"))'"
check "group platform bound to ClusterRole view (ClusterRoleBinding platform-view)" \
  "$K get clusterrolebinding platform-view -o json | jq -e '.roleRef.name == \"view\" and ([.subjects[] | select(.kind==\"Group\" and .name==\"platform\")] | length == 1)'"
check "bob can list pods everywhere but not create or read secrets" \
  "kubectl --kubeconfig $D/bob.kubeconfig get pods -A && kubectl --kubeconfig $D/bob.kubeconfig auth can-i create pods -n default | grep -qx no && kubectl --kubeconfig $D/bob.kubeconfig auth can-i get secrets -n one | grep -qx no"

summary
