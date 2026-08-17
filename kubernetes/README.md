# Kubernetes Platform Study Guide

This directory contains the Kubernetes resources that run on the remote K3s homelab cluster.

The repository separates Kubernetes configuration into four layers:

```text
kubernetes/
├── bootstrap/       First-time Helm repository setup
├── applications/    User-facing and data workloads
├── infrastructure/  Networking, storage, ingress, and platform services
├── observability/   Metrics, logs, dashboards, and alerts
├── registry/        Harbor registry preparation
├── security/        Staged admission-policy and security controls
├── gitops/          Argo CD and Flux configuration
└── ci/              Future in-cluster CI systems
```

The workstation does not run Kubernetes. The DevContainer only provides management tools and connects to the remote K3s API using kubeconfig.

For the complete repository-wide learning path, read:

```text
docs/homelab-study-guide.md
```

---

## 1. Cluster architecture

```text
Developer workstation
  → VS Code DevContainer
  → kubectl / Helm / Kustomize / Argo CD
  → kubeconfig
  → K3s API server: 192.168.178.80:6443
  → K3s cluster
```

Current nodes:

| Node | Role | Address |
|---|---|---|
| `k3s-master` | Control plane | `192.168.178.80` |
| `k3s-worker1` | Worker | `192.168.178.81` |
| `k3s-worker2` | Worker | `192.168.178.82` |

Check access:

```bash
kubectl config current-context
kubectl get nodes -o wide
```

---

## 2. K3s networking baseline

The live cluster currently uses the following **historical recovery** configuration:

```yaml
disable-network-policy: true
flannel-backend: host-gw
disable:
  - servicelb
```

`disable-network-policy: true` means Kubernetes NetworkPolicies are not enforced. The Phase 4 disposable probe confirmed this on 2026-08-14. The setting was introduced after a historical stale kube-router/cross-node connectivity incident; it is not the target security baseline. Follow [K3s Embedded NetworkPolicy Controller Remediation](../docs/runbooks/k3s-networkpolicy-controller-remediation.md) for the gated Ansible-owned enablement and rollback procedure.

### Why use `host-gw`?

All nodes are on the same LAN. `host-gw` routes pod networks directly through node interfaces instead of encapsulating traffic in VXLAN.

### Why disable K3s ServiceLB?

MetalLB is the selected LoadBalancer implementation. Running both controllers can create confusing or conflicting LoadBalancer behavior.

Detailed networking procedures:

```text
docs/k3s-baseline-networking.md
docs/networking.md
```

Basic checks:

```bash
kubectl get pods -n kube-system -o wide
kubectl get svc -n kube-system
kubectl get endpoints -n kube-system kube-dns
```

---

## 3. Kubernetes resource concepts

### Namespace

A Namespace provides logical separation:

```text
garmin
ring-health
health
monitoring
logging
argocd
```

### Pod

A Pod is the smallest schedulable Kubernetes unit. It contains one or more containers that share networking and volumes.

### Deployment

A Deployment describes the desired number and version of stateless Pods. Kubernetes creates ReplicaSets and replaces old Pods during a rollout.

### Service

A Service gives Pods a stable virtual address and selects them using labels.

### PersistentVolumeClaim

A PVC requests storage from a StorageClass. Longhorn dynamically provisions the backing volume.

### ConfigMap

A ConfigMap stores non-secret configuration.

### Secret

A Secret stores sensitive values. In this repository, real sensitive values should come from External Secrets rather than plain YAML in Git.

### Custom Resource

Tools such as MetalLB, External Secrets, Prometheus Operator, and Argo CD extend Kubernetes with custom resources.

Examples:

```text
IPAddressPool
ExternalSecret
PrometheusRule
Application
AppProject
```

---

## 4. Infrastructure layer

Infrastructure components are services other workloads depend on.

```text
kubernetes/infrastructure/
├── longhorn/
├── metallb/
├── sealed-secrets/
└── traefik/
```

### MetalLB

MetalLB assigns LAN IPs to `type: LoadBalancer` Services.

Current pool:

```text
192.168.178.210-192.168.178.220
```

Known assignments:

```text
192.168.178.211   Longhorn UI
192.168.178.212   Grafana
192.168.178.213   Argo CD
192.168.178.214   Ring VictoriaMetrics
192.168.178.215   Harbor reservation
192.168.178.216   Health Dashboard
```

Check:

```bash
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl get svc -A -o wide
```

### Longhorn

Longhorn provides distributed persistent block storage, replicas, snapshots, and backups.

Used by:

```text
Garmin InfluxDB
Garmin token storage
Ring VictoriaMetrics
Grafana
Prometheus
Alertmanager
Loki
```

Check:

```bash
kubectl get pods -n longhorn-system
kubectl get storageclass
kubectl get pvc -A
```

Never casually delete a stateful PVC or Longhorn volume.

### Traefik

Traefik is intended to provide Kubernetes ingress and HTTP routing. The repository currently contains a placeholder manifest, so existing LAN applications use direct MetalLB Services instead of relying on a completed Traefik configuration.

### Sealed Secrets

Sealed Secrets can encrypt Kubernetes Secret data for Git storage. This repository primarily uses Azure Key Vault plus External Secrets for dynamic credentials. Do not use both approaches for the same secret without documenting ownership.

---

## 5. Application layer

Applications live under:

```text
kubernetes/applications/
```

Current workloads:

```text
garmin
health-dashboard
nginx-longhorn-metallb
ring-health-tracker
```

Application resources should normally include:

```text
Namespace
Deployment or Stateful workload
Service
PVC when required
ConfigMap
ExternalSecret when required
README
Kustomization when needed
```

### Garmin

Namespace:

```text
garmin
```

Components:

```text
garmin-fetch-data
InfluxDB 1.11
Longhorn PVCs
ExternalSecret
```

Data path:

```text
Garmin Connect → garmin-fetch-data → InfluxDB GarminStats
```

### Ring Health Tracker

Namespace:

```text
ring-health
```

Components:

```text
VictoriaMetrics
Longhorn PVC
MetalLB Service: 192.168.178.214
Grafana datasource
Grafana dashboard
```

### Health Dashboard

Namespace:

```text
health
```

Components:

```text
Flask/Gunicorn Deployment
ExternalSecret for InfluxDB credentials
MetalLB Service: 192.168.178.216
Kustomize image management
Argo CD Application
```

Study guide:

```text
apps/health-dashboard/README.md
kubernetes/applications/health-dashboard/README.md
```

### Nginx storage demo

The Nginx demo proves that:

```text
Kubernetes scheduling works
Longhorn provisions PVCs
MetalLB assigns LoadBalancer IPs
Data survives Pod recreation
```

It is a foundation validation workload, not a production application.

---

## 6. Observability layer

Observability lives under:

```text
kubernetes/observability/
```

It contains:

```text
Prometheus
Grafana
Alertmanager
Loki
Grafana Alloy
PrometheusRules
LogQL alert rules
Datasources
Dashboards
```

The three observability signals are:

```text
Metrics → Prometheus/VictoriaMetrics → Grafana/PrometheusRules
Logs   → Alloy → Loki → Grafana/Loki rules
Alerts → Alertmanager → Telegram
```

Check:

```bash
kubectl get pods -n monitoring
kubectl get pods -n logging
kubectl get prometheusrule -A
kubectl get configmap -n monitoring --show-labels
```

Detailed documentation:

```text
kubernetes/observability/README.md
kubernetes/observability/monitoring/README.md
kubernetes/observability/logging/README.md
kubernetes/observability/alerting/README.md
```

---

## 7. GitOps layer

GitOps resources live under:

```text
kubernetes/gitops/
```

Argo CD is the active GitOps controller. FluxCD documentation is retained as an alternative learning path but is not the current deployment controller for these applications.

Argo CD flow:

```text
Git commit
  → Argo CD reads repository
  → renders YAML/Kustomize/Helm
  → compares desired and live state
  → syncs resources
  → self-heals drift
```

Current Argo applications:

```text
garmin
ring-health-tracker
health-dashboard
```

Check:

```bash
argocd app list
argocd app get health-dashboard
argocd app get garmin
argocd app get ring-health-tracker
```

The GitOps rule is:

```text
Change Git, not the live object.
```

Emergency manual changes should be documented and reconciled back into Git.

---

## 8. Registry and container delivery

Harbor is prepared under:

```text
kubernetes/registry/harbor/
```

Current owned-image flow:

```text
GitHub Actions → GHCR
```

Planned future flow:

```text
GitHub Actions or CI → Harbor → Kubernetes
```

Harbor is stateful and should be manually validated, backed up, and restore-tested before moving it fully under GitOps.

Registry documentation:

```text
kubernetes/registry/README.md
docs/container-build-pipeline-harbor.md
```

---

## 9. Bootstrap and installation order

The recommended order is:

```text
1. Install K3s
2. Apply K3s networking baseline
3. Connect DevContainer kubeconfig
4. Add Helm repositories
5. Install MetalLB
6. Configure MetalLB pool
7. Install Longhorn
8. Install External Secrets
9. Install monitoring/logging
10. Install Argo CD
11. Deploy Garmin and Ring workloads
12. Deploy application workloads
13. Add Harbor after storage and backup validation
```

The current bootstrap script only adds Helm repositories:

```bash
./kubernetes/bootstrap/bootstrap.sh
```

It does not install every platform component automatically. This is intentional until installation ownership and ordering are formalized.

---

## 10. Validation workflow

### Client and cluster

```bash
kubectl get nodes
kubectl get pods -A
kubectl get events -A --sort-by=.metadata.creationTimestamp
```

### Networking

```bash
kubectl get svc -A -o wide
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

### Storage

```bash
kubectl get storageclass
kubectl get pvc -A
kubectl get pv
```

### GitOps

```bash
argocd app list
argocd app diff <app>
argocd app sync <app>
```

### Manifest rendering

```bash
kubectl kustomize kubernetes/applications/health-dashboard
kubectl apply --dry-run=server -f kubernetes/applications/garmin/
```

### CI checks

```bash
yamllint kubernetes docs ansible .github
```

GitHub Actions additionally runs kubeconform, Gitleaks, Trivy configuration scanning, and application image tests/scans.

---

## 11. Change management rules

For a stateless application:

```text
Edit manifest or application source
Commit
Push
CI validates/builds
Argo CD syncs
Verify rollout
```

For a stateful application:

```text
Back up first
Review Argo CD diff
Avoid renaming PVCs
Keep prune=false initially
Apply one change at a time
Test restore after major changes
```

Never commit:

```text
Passwords
API tokens
Private keys
Kubeconfig files
Unencrypted Kubernetes Secrets
```

---

## 12. Troubleshooting method

Use the dependency order:

```text
Workstation/kubeconfig
  ↓
Kubernetes API
  ↓
Node readiness
  ↓
Pod scheduling
  ↓
PVC/storage
  ↓
Service endpoints
  ↓
MetalLB/Ingress
  ↓
Application logs
  ↓
External data source
```

Useful commands:

```bash
kubectl get <resource>
kubectl describe <resource>
kubectl logs <pod>
kubectl get events
argocd app get <app>
argocd app diff <app>
```

Do not start by changing application code when the pod has no endpoint or the PVC is Pending.

---

## 13. Related study material

```text
docs/homelab-study-guide.md
docs/k3s-baseline-networking.md
docs/storage.md
docs/gitops.md
docs/ci-manifest-validation.md
docs/security-findings.md
docs/security/phase-4.2-kyverno-preflight.md
kubernetes/security/kyverno/README.md
kubernetes/README-kubectl-cheatsheet.md
```
