# Kube-VIP Control-Plane Endpoint

Kube-VIP provides the Kubernetes API virtual IP only:

```text
VIP:       192.168.178.85
DNS name:  k3s-api.home.arpa
port:      6443
mode:      ARP with leader election
interface: ens18
```

It runs on `node-role.kubernetes.io/control-plane` nodes **except**
`k3s-master`, which is being retired for a two-powered-server trial. The VIP
leader must be `k3s-master2` or `k3s-master3` before stopping K3s on the old
master; otherwise its still-running DaemonSet may keep the VIP while its API
server is unavailable. This does not remove the old etcd member.

## Scope and safety boundary

This component **does not** manage Kubernetes `Service` resources. MetalLB
remains the sole Service `LoadBalancer` implementation. Do not enable the
Kube-VIP `services` feature or add a Kube-VIP cloud controller.

The DaemonSet requires `hostNetwork`, `NET_ADMIN`, and `NET_RAW` to add/remove
and advertise the VIP on the LAN. Its image is pinned to the reviewed
Kube-VIP `v1.2.3` manifest-list digest. Kube-VIP runs as root because its
upstream DaemonSet requires effective host-network capabilities to add the VIP
and open an ARP raw socket; it drops every capability except `NET_ADMIN` and
`NET_RAW`. Its namespaced RBAC is limited to the leader-election Lease in
`kube-system`.

## Prerequisites

Before the first sync:

```text
- 192.168.178.85 is excluded from DHCP and unused by every host and MetalLB.
- Pi-hole resolves k3s-api.home.arpa to 192.168.178.85 for LAN clients.
- Each control-plane node uses ens18 for the 192.168.178.0/24 LAN.
- Every K3s server certificate includes the DNS name and VIP as TLS SANs.
- The existing server has been converted to embedded etcd and its snapshot,
  Longhorn health, and GitOps health gates pass.
```

The first sync occurred while only `k3s-master` existed. It later ran on all
three control-plane servers. During the old-master retirement trial, it runs
only on `k3s-master2` and `k3s-master3`.

## First installation

The Argo CD Application intentionally has no automated child sync. After the
reviewed PR merges, inspect its Argo diff and explicitly sync it. Verify:

```bash
kubectl -n kube-system get daemonset kube-vip-ds
kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-vip-ds -o wide
kubectl -n kube-system logs -l app.kubernetes.io/name=kube-vip-ds --tail=100
ip addr | grep 192.168.178.85
curl -k https://192.168.178.85:6443/readyz
```

The three-server HA expansion is complete. The old server remains available
for rollback, but only the two remaining servers advertise kube-vip. For the reusable staged join,
validation, and rollback procedure, read
`docs/runbooks/k3s-ha-control-plane-ansible-join.md`.

## Rollback

If Kube-VIP does not announce the VIP or affects API health, stop further
control-plane changes and use the direct server endpoint only for emergency
administration while the issue is investigated. Revert the reviewed Git change
and manually sync the child Application only after reviewing the Argo diff. Do
not delete Longhorn resources or modify the K3s datastore as part of rollback.

## Failover test

Test failover only after all three control-plane nodes are Ready and a fresh
etcd snapshot and GitOps health verification have passed. During an approved
maintenance window, stop K3s only on the current VIP leader and prove API
access through `192.168.178.85:6443`; then restore that server and rerun the
health gate.
