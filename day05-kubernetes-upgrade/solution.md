# Day 5 solution

## Task 1 - cks-cp

```sh
multipass shell cks-cp; sudo -i
sed -i 's#/v1.35/#/v1.36/#' /etc/apt/sources.list.d/kubernetes.list
# the key is per repo too; re-download it if apt-get update complains about signatures:
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
apt-get update && apt-cache madison kubeadm | head -3

apt-mark unhold kubeadm && apt-get install -y kubeadm='1.36.5-*' && apt-mark hold kubeadm
kubeadm version
kubeadm upgrade plan
kubeadm upgrade apply v1.36.5

kubectl drain cks-cp --ignore-daemonsets
apt-mark unhold kubelet kubectl && apt-get install -y kubelet='1.36.5-*' kubectl='1.36.5-*' && apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet
kubectl uncordon cks-cp
kubectl get nodes
```

## Task 2 - cks-worker

On `cks-cp`:

```sh
kubectl drain cks-worker --ignore-daemonsets --delete-emptydir-data
```

On `cks-worker` (`multipass shell cks-worker; sudo -i`):

```sh
sed -i 's#/v1.35/#/v1.36/#' /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
apt-get update
apt-mark unhold kubeadm && apt-get install -y kubeadm='1.36.5-*' && apt-mark hold kubeadm
kubeadm upgrade node
apt-mark unhold kubelet kubectl && apt-get install -y kubelet='1.36.5-*' kubectl='1.36.5-*' && apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet
```

On `cks-cp`:

```sh
kubectl uncordon cks-worker
kubectl get nodes; kubectl -n prod get pods
```

In this 2-node lab the `shop` pods are `Pending` while the worker is drained (the control plane is tainted). That's expected; they start again after `uncordon`.
