#!/usr/bin/env bash
# Run on the Mac. Builds a 2-node kubeadm cluster in Multipass and snapshots it as "clean".
set -euo pipefail
cd "$(dirname "$0")"

CP=cks-cp
WORKER=cks-worker
NODES=("$CP" "$WORKER")

for n in "${NODES[@]}"; do
  multipass launch 24.04 --name "$n" --cpus 2 --memory 4G --disk 20G
  multipass transfer node-setup.sh cp-init.sh tools.sh "$n:/home/ubuntu/"
  multipass exec "$n" -- sudo bash /home/ubuntu/node-setup.sh
done

multipass exec "$CP" -- sudo bash /home/ubuntu/cp-init.sh
JOIN="$(multipass exec "$CP" -- sudo cat /root/join.sh)"
multipass exec "$WORKER" -- sudo bash -c "$JOIN"

multipass exec "$CP" -- sudo bash /home/ubuntu/tools.sh cp
multipass exec "$WORKER" -- sudo bash /home/ubuntu/tools.sh node

multipass exec "$CP" -- kubectl wait --for=condition=Ready node --all --timeout=300s
multipass exec "$CP" -- kubectl get nodes -o wide

# Kubeconfig for kubectl on the Mac (practise on the node itself, like the exam)
multipass exec "$CP" -- sudo cat /etc/kubernetes/admin.conf >kubeconfig
chmod 600 kubeconfig

multipass stop "${NODES[@]}"
for n in "${NODES[@]}"; do
  multipass snapshot "$n" --name clean --comment "fresh cluster + tools"
done
multipass start "${NODES[@]}"
echo "Done. multipass shell $CP | reset with ./reset.sh"
