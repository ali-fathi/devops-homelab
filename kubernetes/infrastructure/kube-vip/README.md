# Kube-VIP Control-Plane Endpoint

Kube-VIP provides the Kubernetes API virtual IP only:

```text
VIP:       192.168.178.85
DNS name:  k3s-api.home.arpa
port:      6443
mode:      ARP with leader election
interface: ens18
```

It runs only on nodes labelled `node-role.kubernetes.io/control-plane`. One
leader advertises the VIP; leadership can move to another control-plane node.

## Scope and safety boundary

This component **does not** manage Kubernetes `Service` resources. MetalLB
remains the sole Service `LoadBalancer` implementation. Do not enable the
Kube-VIP `services` feature or add a Kube-VIP cloud controller.

The DaemonSet requires `hostNetwork`, `NET_ADMIN`, and `NET_RAW` to add/remove
and advertise the VIP on the LAN. Its image is pinned to the reviewed
Kube-VIP `v1.2.3` manifest-list digest. Its RBAC is the reviewed upstream role
for the in-cluster DaemonSet and is deliberately not `cluster-admin`.

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

The first sync occurs while only `k3s-master` exists; this is expected. The
DaemonSet expands to `k3s-master2` and `k3s-master3` as they join.

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

Do not join new control-plane nodes through the VIP until every command
succeeds.

## Rollback

If the first sync does not announce the VIP or affects API health, revert the
reviewed Git change and manually sync the child Application to remove the
DaemonSet/RBAC. The existing direct API endpoint `192.168.178.80:6443` remains
available until the new server nodes are joined. Do not delete Longhorn
resources or modify the K3s datastore as part of this rollback.

## Failover test

Test failover only after all three control-plane nodes are Ready and a fresh
etcd snapshot and GitOps health verification have passed. During an approved
maintenance window, stop K3s only on the current VIP leader and prove API
access through `192.168.178.85:6443`; then restore that server and rerun the
health gate.
