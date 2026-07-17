# Kubernetes Bootstrap

Bootstrap is the first Kubernetes preparation layer for the homelab.

It is deliberately small and currently performs one safe task: adding the Helm repositories used by the platform.

For the full platform study guide:

```text
docs/homelab-study-guide.md
```

---

## Current files

```text
kubernetes/bootstrap/
├── bootstrap.sh
└── README.md
```

The script adds:

```text
MetalLB
Longhorn
Argo CD
Prometheus Community
Grafana
External Secrets
```

Run:

```bash
./kubernetes/bootstrap/bootstrap.sh
```

It executes:

```bash
helm repo add ...
helm repo update
```

It does not automatically install all charts.

---

## Why bootstrap is separated

Installing a platform component is more dangerous than adding a repository.

A chart installation can create:

```text
CRDs
Deployments
DaemonSets
Services
PVCs
webhooks
cluster-wide RBAC
```

The intended learning sequence is:

```text
1. Add repositories.
2. Inspect chart versions and values.
3. Validate prerequisites.
4. Install one component.
5. Verify its Pods and CRDs.
6. Record ownership.
7. Configure GitOps only after manual validation.
```

---

## Recommended installation order

```text
1. K3s networking baseline
2. MetalLB
3. Longhorn
4. External Secrets Operator
5. Prometheus/Grafana
6. Loki/Alloy
7. Argo CD
8. Application workloads
9. Harbor after backup/restore planning
```

Do not install stateful services before storage is healthy.

Do not install applications before DNS, networking, and storage are verified.

---

## Validation commands

```bash
helm repo list
helm search repo metallb
helm search repo longhorn
helm search repo argo/argo-cd
helm search repo prometheus-community
helm search repo grafana
helm search repo external-secrets
```

Check cluster readiness:

```bash
kubectl get nodes
kubectl get pods -A
kubectl get storageclass
```

---

## Future improvements

```text
Pin Helm chart versions.
Add explicit installation scripts with dry-run support.
Separate bootstrap from day-2 operations.
Document CRD ordering.
Add validation after each installation.
Move safe declarative components into Argo CD.
Add a disaster-recovery bootstrap procedure.
```
