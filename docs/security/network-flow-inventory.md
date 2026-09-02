# Network Flow Inventory and Segmentation Plan

> **Phase 4.1 status:** Intended flows based on the current architecture. Confirm live selectors, ports, DNS service address, and CNI NetworkPolicy enforcement before creating deny policies.

## Objective

Phase 4.3 will make application namespaces default-deny for ingress and egress, then allow only required paths. This document prevents a policy rollout based on guesses.

The read-only baseline inventory records exposed Services and existing NetworkPolicies. The next validation step must use a disposable namespace to prove that the active K3s network implementation actually enforces deny and allow policies.

## Trust zones

```text
kube-system        DNS, Kubernetes platform components, CNI
argocd             GitOps control plane
longhorn-system    storage platform
monitoring         Prometheus, Grafana, Alertmanager
logging            Loki and Alloy
external-secrets   Azure Key Vault synchronization controller
application zones  health, garmin, ring-health, future Harbor
LAN/NAS            MetalLB endpoints and Synology NFS backup target (Longhorn and host etcd backups)
internet           Git sources, Helm repositories, Azure APIs, image registries
```

## Expected flows to validate

| Source zone | Destination | Direction/purpose | Policy treatment |
|---|---|---|---|
| Any application namespace | CoreDNS/kube-dns in `kube-system` | DNS UDP/TCP 53 | Explicit egress allow |
| Argo CD | Kubernetes API and managed namespaces | Reconciliation | Platform-controlled; validate before restrictions |
| Argo CD repo server | Git/Helm sources | Desired-state fetch/render | Explicit external egress assessment |
| Prometheus | Workload metrics endpoints | Scrape | Explicit ingress to selected metrics ports |
| Alloy | Loki gateway/service | Log ingestion | Explicit egress/ingress allow |
| Applications | Their declared database/backend | Business traffic | Exact namespace/selector/port allow |
| External Secrets Operator | Azure Key Vault | Secret synchronization | Explicit external egress assessment |
| Longhorn manager/CSI and control-plane backup service | Synology NFS | External Longhorn volume/system backups and K3s etcd snapshot copies | Node/platform flow; outside Pod NetworkPolicy scope may apply |
| LAN client | MetalLB LoadBalancer Service | User access to approved apps | Explicit service/workload ingress allow |

No row is an allow policy yet. All selectors and ports must be confirmed from live Services, EndpointSlices, Pods, Helm-rendered manifests, and application documentation.

## Rollout method

```text
1. Deploy a disposable two-Pod test namespace.
2. Prove unrestricted connectivity before policies.
3. Add default-deny ingress/egress and prove connection fails.
4. Add an exact DNS/peer allow policy and prove only required connection succeeds.
5. Delete the test namespace.
6. Apply Audit/observed flow design to one low-risk application namespace.
7. Run GitOps health gate and application functional checks.
8. Expand gradually; do not start with argocd, kube-system, Longhorn, or monitoring.
```

## Required evidence before enforcement

```text
Active CNI/network-policy implementation and version.
Disposable deny/allow test output.
Service/EndpointSlice selector and port evidence.
DNS target namespace/labels/ports.
Prometheus scrape dependencies.
Loki/Alloy telemetry dependencies.
Argo CD and External Secrets traffic requirements.
Rollback command or Git revert for each namespace policy bundle.
```

## Forbidden shortcuts

```text
Do not apply default-deny to every namespace in one change.
Do not allow all egress to avoid understanding dependencies.
Do not use IP allowlists for in-cluster workloads when namespace/pod selectors are available.
Do not restrict kube-system, argocd, longhorn-system, or monitoring first.
Do not assume a manifest is enforced until the deny/allow test proves it.
```
