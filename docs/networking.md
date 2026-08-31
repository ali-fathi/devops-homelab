# Networking

## K3s nodes and control-plane endpoint

| Purpose | Address |
|---|---|
| Kube-VIP Kubernetes API endpoint | `192.168.178.85` |
| `k3s-master` control-plane/etcd server | `192.168.178.80` |
| `k3s-master2` control-plane/etcd server | `192.168.178.83` |
| `k3s-master3` control-plane/etcd server | `192.168.178.84` |
| `k3s-worker1` worker | `192.168.178.81` |
| `k3s-worker2` worker | `192.168.178.82` |

Kubernetes clients use `https://192.168.178.85:6443` or
`https://k3s-api.home.arpa:6443`. Kube-VIP advertises this control-plane VIP
on `ens18`; it does not manage Service LoadBalancer addresses.

## Service LoadBalancer addresses

MetalLB is the sole Service `LoadBalancer` implementation. Its address pool is:

```text
192.168.178.210-192.168.178.220
```

The API VIP `.85` is reserved outside DHCP and outside this MetalLB pool.

## Pod networking baseline

```text
Flannel backend:          host-gw
K3s NetworkPolicy:        disabled (historical recovery baseline)
K3s ServiceLB:            disabled
LAN interface:            ens18
```

Do not change the NetworkPolicy-controller setting as part of ordinary network
or HA work. Follow `docs/runbooks/k3s-networkpolicy-controller-remediation.md`
for its separately gated process.
