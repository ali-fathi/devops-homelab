# Harbor MetalLB IP Allocation

This document records the MetalLB IP allocation for Harbor.

---

## Assigned Service

Service:

```text
Harbor Registry
```

Assigned MetalLB IP:

```text
192.168.178.215
```

Namespace:

```text
harbor
```

---

## MetalLB Pool Context

Current expected MetalLB pool:

```text
192.168.178.210-192.168.178.220
```

Known assignments:

```text
192.168.178.213   Argo CD
192.168.178.214   Ring Health VictoriaMetrics
192.168.178.215   Harbor Registry
```

Reserved or free addresses should be tracked here as new homelab services are added.

---

## Allocation Policy

For homelab server-style services:

```text
Use MetalLB.
Use a fixed IP from the MetalLB pool.
Document the service and IP assignment.
Avoid random LoadBalancer allocation for important services.
Avoid IP reuse.
```

---

## Pre-Deployment Check

Before deploying Harbor, confirm the IP is unused:

```bash
kubectl get svc -A | grep 192.168.178.215 || true
```

Confirm the current MetalLB service assignments:

```bash
kubectl get svc -A | grep 192.168.178
```

Confirm MetalLB resources:

```bash
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

---

## Expected Harbor Service Result

After Harbor deployment, a Harbor service should show:

```text
EXTERNAL-IP: 192.168.178.215
```

Check with:

```bash
kubectl get svc -n harbor
```

---

## Troubleshooting

### Harbor does not get 192.168.178.215

Check:

```bash
kubectl get svc -n harbor -o wide
kubectl describe svc -n harbor <service-name>
kubectl get events -n harbor --sort-by=.lastTimestamp
```

Possible causes:

```text
Requested IP not configured in service annotations or values.
IP is not inside MetalLB pool.
IP is already used by another service.
MetalLB controller is unhealthy.
Helm chart value path is wrong for the Harbor chart version.
```

---

### Another service already uses 192.168.178.215

Find the service:

```bash
kubectl get svc -A | grep 192.168.178.215
```

Do not deploy Harbor until the conflict is resolved.

---

## Change Control

If the Harbor IP changes in the future, update:

```text
kubernetes/registry/harbor/README.md
kubernetes/registry/harbor/docs/exposure-options.md
kubernetes/registry/harbor/docs/metallb-ip-allocation.md
DNS records
Any CI/CD registry configuration
Any Docker login documentation
```

---

## Current Status

```text
Planned: 192.168.178.215
Deployment status: Not yet deployed / pending validation
```
