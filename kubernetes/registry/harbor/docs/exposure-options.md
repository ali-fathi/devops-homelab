# Harbor Exposure Options

Harbor is a private container registry and should be reachable by Kubernetes nodes and trusted developers.

## Options

### MetalLB LoadBalancer

```text
Harbor Service type LoadBalancer
  → MetalLB
  → fixed LAN address 192.168.178.215
```

Advantages:

```text
stable LAN address
simple Docker login target
works with bare-metal K3s
consistent DNS and firewall rules
```

This is the selected homelab design.

### Ingress through Traefik

```text
Client
  → DNS/TLS
  → Traefik Ingress
  → Harbor Services
```

This is useful when Traefik and TLS are fully configured. The repository's Traefik configuration is not complete yet, so it is not the initial Harbor exposure path.

### NodePort

NodePort exposes Harbor through every node IP and a high port. It is easy to bootstrap but less predictable and less suitable for the planned registry endpoint.

### Cloudflare/public exposure

A registry should not be publicly exposed without:

```text
TLS
strong authentication
access policy
robot accounts
rate limiting
audit logging
```

Public exposure is not the initial design.

## Selected design

```text
Hostname: harbor.greyneo.com
LAN IP: 192.168.178.215
Exposure: MetalLB LoadBalancer
Storage: Longhorn PVCs
Deployment: Harbor Helm chart
Initial operation: manual validation
Future operation: Argo CD after backup/restore testing
```
