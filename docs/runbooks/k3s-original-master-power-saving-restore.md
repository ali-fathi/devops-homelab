# Restore `k3s-master` after the power-saving shutdown

Status recorded on 2026-11-16. This runbook describes the **reversible** trial
with `k3s-master` (`192.168.178.80`) powered off, `k3s-master2`
(`192.168.178.83`) and `k3s-master3` (`192.168.178.84`) running K3s/etcd,
and two workers (`192.168.178.81` and `.82`). Recheck live state before
following these steps; do not assume that disk, pod, or etcd status is unchanged.

## Important safety boundary

`k3s-master` was **not deleted from Kubernetes or etcd**. With it offline,
etcd has only 2 of its 3 members available: both remaining servers must stay
online for quorum. Do not restart, upgrade, drain, or shut down either remaining
server until the old master has successfully rejoined and the control plane is
healthy. Do not run `k3s cluster-reset`, `k3s-killall.sh`, uninstall scripts,
manual etcd-member removal, or Longhorn replica deletion to restore this node.

During the shutdown trial:

- All seven Longhorn volumes were verified healthy with three running replicas
  each, and **zero replicas on `k3s-master`**. Its Longhorn node has
  `spec.allowScheduling: false` and `spec.evictionRequested: true`.
- The Kubernetes node is cordoned (`spec.unschedulable: true`) and was drained.
  Its `NotReady` condition while powered off is expected.
- The kube-vip DaemonSet deliberately excludes `k3s-master` in
  [`kubernetes/infrastructure/kube-vip/daemonset.yaml`](../../kubernetes/infrastructure/kube-vip/daemonset.yaml).
  Its Argo CD Application has **manual** child sync. The VIP
  `192.168.178.85:6443` is advertised by one of the other two servers. See
  [PR #72](https://github.com/ali-fathi/devops-homelab/pull/72) for the
  exclusion and [PR #73](https://github.com/ali-fathi/devops-homelab/pull/73)
  for the shutdown safety notes.
- Both workers' `/etc/systemd/system/k3s-agent.service.env` files have
  `K3S_URL='https://192.168.178.85:6443'`; do **not** revert them to `.80`.
  The operator kubeconfig `~/.kube/k3s-config` also uses the VIP; a local
  pre-VIP backup was kept outside Git. No credentials are stored in this repo.
- `k3s-master2`'s expanded Longhorn filesystem was approximately 166.8 GiB
  total and 115 GiB free after the drain. Check capacity again before
  rescheduling replicas.
- A fresh K3s etcd snapshot was copied to the off-node NFS backup target from
  `k3s-master2` using `k3s-etcd-nfs-backup.service`. Longhorn system backups
  are **not** substitutes for an etcd snapshot.
- The powered-off node's `NodeDown` alert, missing scrape targets, and Argo CD
  `monitoring` Application `Progressing` status are expected until the node
  rejoins. Do not silence unrelated alerts.

## 1. Preflight while the old master is still off

Use a kubeconfig that targets the VIP, not the old master's direct address:

```bash
export KUBECONFIG="$HOME/.kube/k3s-config"
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
kubectl get --raw=/readyz
kubectl get nodes -o wide
kubectl -n kube-system get lease plndr-cp-lock -o jsonpath='{.spec.holderIdentity}{"\n"}'
kubectl -n longhorn-system get volumes.longhorn.io \
  -o custom-columns=NAME:.metadata.name,ROBUSTNESS:.status.robustness
```

The VIP must answer `ok`; the two remaining masters and both workers must be
Ready; all volumes must be healthy. Verify a recent off-node etcd backup (on
`k3s-master2`, `sudo systemctl status k3s-etcd-nfs-backup.service` or run
`sudo systemctl start k3s-etcd-nfs-backup.service` and check its result). Do
not expose the server token or snapshot contents in logs or Git.

## 2. Power on and rejoin

Power on `k3s-master` from the hypervisor. K3s was **stopped, not disabled**,
so it should normally start at boot. If the machine boots but does not join,
check it over SSH (adjust the SSH key to your controller's configuration):

```bash
ssh -i ~/.ssh/my_ansible_homelab ansible@192.168.178.80 \
  'sudo systemctl status k3s --no-pager'
```

Only if the service is inactive, start it without changing etcd membership:

```bash
ssh -i ~/.ssh/my_ansible_homelab ansible@192.168.178.80 \
  'sudo systemctl start k3s'
```

Check the node, API servers, and storage:

```bash
kubectl get nodes -o wide
kubectl --server=https://192.168.178.83:6443 get --raw=/readyz
kubectl --server=https://192.168.178.84:6443 get --raw=/readyz
kubectl --server=https://192.168.178.80:6443 get --raw=/readyz
kubectl -n longhorn-system get volumes.longhorn.io \
  -o custom-columns=NAME:.metadata.name,ROBUSTNESS:.status.robustness
kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-vip-ds -o wide
```

Expect three Ready masters, two Ready workers, healthy volumes, and **still
only two kube-vip pods** (on masters 2 and 3). Check etcd member/leader health
before restarting either remaining server. If `k3s-master` is not Ready or
cannot rejoin, leave the other two servers untouched and diagnose K3s/etcd;
do not force a fresh cluster or remove the old member.

## 3. Choose the desired level of restoration

**For three-member etcd quorum only:** stop here. The node may stay cordoned,
excluded from kube-vip, and without Longhorn replicas. It already participates
in etcd once K3s rejoins.

**To schedule ordinary workloads on it again**, after the Ready/health gates:

```bash
kubectl uncordon k3s-master
kubectl get node k3s-master
```

**To make its Longhorn disk eligible for *new* replicas again**, first check
its disk capacity and Longhorn node readiness, then clear the eviction flag
*before* enabling scheduling:

```bash
kubectl -n longhorn-system get nodes.longhorn.io k3s-master -o yaml
kubectl -n longhorn-system patch nodes.longhorn.io k3s-master \
  --type=merge -p '{"spec":{"evictionRequested":false}}'
kubectl -n longhorn-system patch nodes.longhorn.io k3s-master \
  --type=merge -p '{"spec":{"allowScheduling":true}}'
```

The existing three-replica volumes **will not automatically move replicas
back**: Longhorn replica auto-balance was disabled when the trial began. Do not
remove healthy replicas or change replica counts merely to make the old node
appear used. Any redistribution should use a separately reviewed Longhorn
migration plan with verified backups and free space.

**To restore kube-vip candidacy on the old master**, remove the
`kubernetes.io/hostname NotIn [k3s-master]` affinity exclusion from
[`kubernetes/infrastructure/kube-vip/daemonset.yaml`](../../kubernetes/infrastructure/kube-vip/daemonset.yaml)
in a reviewed GitOps PR. After merging, review the `kube-vip` Argo CD diff and
**manually sync** that Application; it does not auto-sync. Confirm a Ready
kube-vip pod on each master, VIP readiness, and a healthy Lease. There is no
need to change the workers' or operator's VIP-based API endpoint. Existing
replicas and kube-vip leadership need not move back to the old master.

## 4. Final verification and rollback

```bash
kubectl get nodes
kubectl get --raw=/readyz
kubectl -n kube-system get lease plndr-cp-lock
kubectl -n longhorn-system get volumes.longhorn.io \
  -o custom-columns=NAME:.metadata.name,ROBUSTNESS:.status.robustness
kubectl -n argocd get applications.argoproj.io
kubectl get pods -A -o wide
```

The old master's `NodeDown` alert should clear after its kubelet and
node-exporter return; `monitoring` should become Healthy after its DaemonSet
is ready. If restoring the old server causes problems, **do not power off or
restart another etcd member**. Diagnose and, if necessary, re-cordon the old
node and stop only its K3s service after checking that the VIP is held by a
remaining server. Keep access through the VIP or a direct healthy-server API
endpoint. Reversing Longhorn scheduling does not delete data.
