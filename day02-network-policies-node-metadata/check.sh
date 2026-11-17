#!/usr/bin/env bash
# Run on the Mac. Grades Day 2.
set -uo pipefail
cd "$(dirname "$0")"
source ../lib.sh

# Connectivity helpers, run on cks-cp. ok/no: from-ns from-pod url
ok() { echo "$K -n $1 exec $2 -- curl -s -o /dev/null -m 4 -f $3"; }
no() { echo "! $K -n $1 exec $2 -- curl -s -o /dev/null -m 4 $3"; }
pod_ip() { on "$CP" "$K -n $1 get pod $2 -o jsonpath='{.status.podIP}'"; }
DB_IP="$(pod_ip team-db db)"
WEB_IP="$(pod_ip team-web web)"
TESTER_IP="$(pod_ip other tester)"

section "Task 1: default deny in team-api"
check "NetworkPolicy default-deny selects all pods" \
  "$K -n team-api get netpol default-deny -o jsonpath='{.spec.podSelector}' | grep -qx '{}'"
check "default-deny has policyTypes Ingress and Egress" \
  "$K -n team-api get netpol default-deny -o jsonpath='{.spec.policyTypes}' | grep -q Ingress && $K -n team-api get netpol default-deny -o jsonpath='{.spec.policyTypes}' | grep -q Egress"
check "default-deny has no ingress/egress rules" \
  "$K -n team-api get netpol default-deny -o json | jq -e '((.spec.ingress // []) == []) and ((.spec.egress // []) == [])'"

section "Task 2: api-policy"
check "team-web/web -> api:80 allowed" "$(ok team-web web http://api.team-api)"
check "team-web/intruder -> api blocked" "$(no team-web intruder http://api.team-api)"
check "other/tester (app=web, wrong ns) -> api blocked" "$(no other tester http://api.team-api)"
check "api -> db service allowed (DNS + egress)" "$(ok team-api api http://db.team-db)"
check "api -> team-web/web pod blocked" "$(no team-api api http://$WEB_IP)"
check "api -> internet blocked" "$(no team-api api http://1.1.1.1)"

section "Task 3: deny-metadata in team-web"
check "deny-metadata excepts 169.254.169.254/32 from 0.0.0.0/0" \
  "$K -n team-web get netpol deny-metadata -o json | jq -e '[.spec.egress[].to[]?.ipBlock | select(.cidr==\"0.0.0.0/0\") | .except[]?] | index(\"169.254.169.254/32\") != null'"
check "deny-metadata applies to all pods in team-web" \
  "$K -n team-web get netpol deny-metadata -o jsonpath='{.spec.podSelector}' | grep -qx '{}'"
check "team-web/web -> internet still allowed" "$(ok team-web web http://example.com)"
check "team-web/web -> other/tester pod still allowed" "$(ok team-web web http://$TESTER_IP)"
check "team-web/intruder -> other/tester pod still allowed" "$(ok team-web intruder http://$TESTER_IP)"

section "Task 4: CiliumNetworkPolicy db-ingress in team-db"
check "CiliumNetworkPolicy db-ingress exists" "$K -n team-db get cnp db-ingress"
check "api -> db GET / allowed" "$(ok team-api api http://db.team-db/)"
check "api -> db POST denied by L7 policy (403)" \
  "[ \$($K -n team-api exec api -- curl -s -o /dev/null -m 4 -w '%{http_code}' -X POST http://db.team-db/) = 403 ]"
check "team-web/web -> db pod blocked" "$(no team-web web http://$DB_IP)"
check "other/tester -> db pod blocked" "$(no other tester http://$DB_IP)"

summary
