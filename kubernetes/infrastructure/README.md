# Kubernetes Infrastructure

For the repository-wide platform study guide, read:

```text
docs/homelab-study-guide.md
```

This directory contains Kubernetes infrastructure components for the homelab cluster.

Infrastructure components are platform-level services that other workloads depend on.

---

## Purpose

The `infrastructure/` directory is for foundational cluster capabilities.

These components provide networking, storage, ingress, encryption, and platform services.

Examples:

```text
MetalLB
Longhorn
Traefik
Sealed Secrets
```

These are different from application workloads.

Applications belong under:

```text
kubernetes/applications/
```

Observability configuration belongs under:

```text
kubernetes/observability/
```

---

## Current Structure

```text
infrastructure/
├── longhorn/
├── metallb/
├── sealed-secrets/
└── traefik/
```

---

## Component Responsibilities

### MetalLB

Path:

```text
kubernetes/infrastructure/metallb
```

Purpose:

```text
Provides LoadBalancer IP addresses for bare-metal Kubernetes.
```

Important files:

```text
ip-pool.yaml
l2-advertisement.yaml
metallb-native.yaml
README.md
```

Current known pool:

```text
192.168.178.210-192.168.178.220
```

Important assigned IPs:

```text
192.168.178.213   Argo CD
192.168.178.214   Ring Health VictoriaMetrics
```

---

### Longhorn

Path:

```text
kubernetes/infrastructure/longhorn
```

Purpose:

```text
Provides distributed block storage and persistent volumes.
```

Important files:

```text
longhorn-ui-lb.yaml
README.md
```

Used by:

```text
Garmin InfluxDB
Ring Health VictoriaMetrics
Other PVC-backed workloads
```

Longhorn is stateful and should be treated carefully.

---

### Traefik

Path:

```text
kubernetes/infrastructure/traefik
```

Purpose:

```text
Ingress controller and HTTP routing.
```

Important files:

```text
traefik.yaml
```

---

### Sealed Secrets

Path:

```text
kubernetes/infrastructure/sealed-secrets
```

Purpose:

```text
Encrypt Kubernetes Secrets for safe storage in Git.
```

Current file:

```text
sealed-secrets.yaml
```

Note:

```text
This homelab currently also uses Azure Key Vault and External Secrets.
Use External Secrets for dynamic secrets from Azure Key Vault.
Use Sealed Secrets only when a Git-encrypted Kubernetes Secret is specifically needed.
```

---

## GitOps Strategy

Do not move all infrastructure components into Argo CD at once.

Recommended order:

```text
1. MetalLB configuration
2. Traefik configuration
3. Sealed Secrets
4. External Secrets configuration
5. Longhorn configuration
```

Longhorn should be moved last because it manages persistent storage.

---

## Infrastructure GitOps Safety Rules

When GitOps-managing infrastructure:

```text
Keep prune=false during initial adoption.
Back up before migration.
Use argocd app diff before sync.
Migrate one component at a time.
Verify cluster health after each migration.
Avoid renaming resources.
Avoid changing selectors casually.
Avoid changing storage classes casually.
```

---

## Storage Safety Rules

For storage-related components:

```text
Do not rename PVCs.
Do not rename StorageClasses.
Do not delete Longhorn volumes manually.
Do not enable prune until backup/restore is tested.
Do not GitOps large storage changes without a rollback plan.
```

Before moving Longhorn deeper into Argo CD, complete:

```text
Longhorn recurring backup configuration
Restore test
Disaster recovery runbook
PVC inventory
Volume ownership documentation
```

---

## Networking Safety Rules

For networking-related components:

```text
Track all MetalLB IP assignments.
Avoid IP conflicts.
Document DNS mappings.
Document Cloudflare tunnel mappings.
Keep public endpoints reviewed.
```

Recommended IP tracking table:

```text
192.168.178.210   reserved/free
192.168.178.211   reserved/free
192.168.178.212   reserved/free
192.168.178.213   Argo CD
192.168.178.214   Ring Health VictoriaMetrics
192.168.178.215   reserved/free
192.168.178.216   reserved/free
192.168.178.217   reserved/free
192.168.178.218   reserved/free
192.168.178.219   reserved/free
192.168.178.220   reserved/free
```

---

## Validation Commands

Check MetalLB:

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl get svc -A | grep 192.168.178
```

Check Longhorn:

```bash
kubectl get pods -n longhorn-system
kubectl get storageclass
kubectl get pvc -A
```

Check Traefik:

```bash
kubectl get pods -n kube-system | grep traefik
kubectl get svc -n kube-system | grep traefik
kubectl get ingress -A
```

Check Sealed Secrets:

```bash
kubectl get pods -A | grep sealed
kubectl get sealedsecret -A
```

---

## Planned Improvements

Future improvements:

```text
Document all MetalLB IP allocations.
Add Longhorn backup strategy.
Add disaster recovery runbook.
Move MetalLB config into Argo CD.
Move Traefik config into Argo CD.
Prepare Longhorn GitOps adoption last.
```

---

## Related Documentation

Recommended related docs:

```text
docs/networking.md
docs/storage.md
docs/disaster-recovery.md
docs/runbooks/
```
