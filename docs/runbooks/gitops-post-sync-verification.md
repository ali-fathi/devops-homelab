# Runbook: GitOps Post-Sync Health Verification

Use this runbook after an Argo CD synchronization, Helm chart version change, observability configuration change, or GitOps migration step.

Its purpose is to distinguish these two questions:

```text
Did Argo CD reconcile the desired state?        Argo CD Application status
Is the platform actually ready to serve work?   Pods, PVCs, endpoints, CRs, and ExternalSecrets
```

A `Synced` Application is necessary but not sufficient. For example, an Application can be Synced while a Pod is Pending because a PVC cannot attach, or while a Service has no endpoints because its Pods are not Ready.

## Scope

The read-only health gate verifies:

```text
Argo CD root and child Applications
Pod readiness in core platform and application namespaces
PersistentVolumeClaim binding
Endpoints for important Services
ExternalSecret Ready conditions
Prometheus and Alertmanager custom resources
Loki StatefulSet readiness
Alloy DaemonSet coverage
```

It does not:

```text
apply resources
synchronize Applications
restart Pods
rotate credentials
print Secret values
modify Kubernetes resources
```

## Script

The script is:

```text
scripts/verify-gitops-health.sh
```

Run it from the repository root:

```bash
./scripts/verify-gitops-health.sh
```

The script exits with:

```text
0  all required checks passed
1  one or more health checks failed
2  required CLI tools are missing or the Kubernetes API is unreachable
```

The script is deliberately read-only. A non-zero result is a signal to investigate, not permission to run a blind Argo CD sync or delete a resource.

## Prerequisites

Run from the DevContainer or an operator environment with:

```text
kubectl
jq
Kubernetes API access
permission to read applications, Pods, PVCs, Services, Endpoints, CRs, and ExternalSecrets
```

Before running it, check the active Kubernetes context:

```bash
kubectl config current-context
```

Confirm access:

```bash
kubectl get nodes
```

## Expected successful result

The final lines should look like:

```text
Checks: <number> | Failures: 0 | Warnings: <number>
GitOps health gate PASSED.
```

Warnings do not necessarily fail the gate. They identify optional or currently absent resources such as a namespace with no Pods or an unavailable optional CRD. Review warnings; do not permanently ignore them without understanding the reason.

## Checks performed

### 1. Argo CD Applications

Expected Applications:

```text
homelab-applications
kube-vip
monitoring
loki
alloy
observability-config
garmin
ring-health-tracker
health-dashboard
```

For each Application, the gate reads its Kubernetes `Application` CR status and requires:

```text
sync.status   = Synced
health.status = Healthy
```

Manual inspection:

```bash
argocd app get homelab-applications
```

```bash
argocd app get monitoring
```

If an Application is OutOfSync or Degraded, start with:

```bash
argocd app diff <application-name> --hard-refresh --diff-exit-code 0
```

### 2. Control-plane networking

The gate also requires the Kube-VIP DaemonSet in `kube-system` to be available
on every control-plane server scheduled by its affinity rule. This proves the
GitOps-managed API endpoint is present after a server join.

Manual inspection:

```bash
kubectl -n kube-system get daemonset kube-vip-ds
```

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-vip-ds -o wide
```

Then use:

```text
docs/runbooks/argocd-app-outofsync.md
docs/runbooks/argocd-comparison-error.md
```

### 2. Pod readiness

Namespaces checked:

```text
argocd
monitoring
logging
garmin
ring-health
health
```

A non-completed Pod is healthy only when:

```text
phase = Running
all normal containers are Ready
```

A completed Job Pod is allowed. Pods in `Pending`, `Failed`, `Unknown`, `CrashLoopBackOff`, or with unready normal containers cause a failure.

Manual inspection:

```bash
kubectl get pods -n monitoring
```

```bash
kubectl get pods -n logging
```

For a failing Pod:

```bash
kubectl describe pod <pod-name> -n <namespace>
```

```bash
kubectl logs <pod-name> -n <namespace> --all-containers --tail=100
```

### 3. PersistentVolumeClaims

Namespaces checked:

```text
monitoring
logging
garmin
ring-health
```

Every existing PVC must be:

```text
Bound
```

Manual inspection:

```bash
kubectl get pvc -n monitoring
```

```bash
kubectl get pvc -n logging
```

Do not delete a Pending PVC as a first troubleshooting action. Inspect its events:

```bash
kubectl describe pvc <pvc-name> -n <namespace>
```

For Longhorn, also inspect volume state before modifying a workload:

```bash
kubectl get volumes.longhorn.io -n longhorn-system
```

### 4. Service endpoints

The script checks these workload-facing Services:

```text
monitoring/monitoring-grafana
monitoring/monitoring-kube-prometheus-prometheus
monitoring/monitoring-kube-prometheus-alertmanager
logging/loki
logging/loki-gateway
logging/alloy
garmin/garmin-influxdb
ring-health/victoriametrics
health/health-dashboard
```

A Service is considered usable when its `discovery.k8s.io/v1` EndpointSlice has at least one ready address. This verifies selector-to-Pod routing without making an external request and avoids the deprecated v1 `Endpoints` API.

Manual inspection:

```bash
kubectl get endpointslices.discovery.k8s.io -n health -l kubernetes.io/service-name=health-dashboard
```

A Service with zero endpoints commonly means:

```text
Pods are not Ready
Service selector labels do not match Pod labels
Workload has zero replicas
Namespace or Service name is incorrect
```

### 5. External Secrets

The gate checks that every discovered `ExternalSecret` has a condition:

```text
type: Ready
status: "True"
```

It checks status only. It does not display Secret data.

Manual inspection:

```bash
kubectl get externalsecret -A
```

For Telegram:

```bash
kubectl get externalsecret telegram-alerts -n monitoring
```

Inspect only Secret key names:

```bash
kubectl get secret telegram-alerts -n monitoring -o json | jq '{keys: (.data | keys)}'
```

Use the dedicated troubleshooting guide for failures:

```text
docs/runbooks/external-secrets-debug.md
```

### 6. Observability custom resources and workloads

The gate verifies:

```text
Prometheus/monitoring-kube-prometheus-prometheus has at least one available replica
Alertmanager/monitoring-kube-prometheus-alertmanager has at least one available replica
StatefulSet/logging/loki has at least one ready replica
DaemonSet/logging/alloy is available on every scheduled node
```

Manual inspection:

```bash
kubectl get prometheus,alertmanager -n monitoring
```

```bash
kubectl get statefulset loki -n logging
```

```bash
kubectl get daemonset alloy -n logging
```

## Standard post-sync procedure

1. Review Argo CD’s diff before synchronization, especially for stateful resources.
2. Synchronize only after the diff is understood.
3. Wait for the Application to finish reconciling.
4. Run the read-only health gate.
5. Investigate every failure from the lowest failed dependency upward.
6. Record the incident or learning point in the relevant runbook.

Example:

```bash
argocd app diff monitoring --hard-refresh --diff-exit-code 0
```

```bash
argocd app sync monitoring
```

```bash
argocd app wait monitoring --health --sync
```

```bash
./scripts/verify-gitops-health.sh
```

## Troubleshooting order

Use this dependency order:

```text
1. Operator kubeconfig and Kubernetes API access
2. Argo CD Application source, permissions, and desired/live diff
3. Namespace existence and Pod scheduling
4. PVC and Longhorn state
5. Pod readiness and logs
6. Service selectors and endpoints
7. ExternalSecret status
8. Prometheus, Loki, Alloy, and Alertmanager-specific checks
9. External integrations such as Telegram
```

Do not change multiple layers at once. Confirm one failure, correct its declared owner, rerun the health gate, and proceed.

## Known safety rules

```text
Do not delete PVCs to clear a health failure.
Do not enable pruning to clear OutOfSync state.
Do not print Secret values in terminals, documentation, or CI logs.
Do not patch a live resource without recording the durable Git or Terraform change.
Do not use Terraform and Argo CD to manage the same workload resource.
```

## Telegram delivery test

The health gate verifies the Kubernetes side of the Telegram secret pipeline, not message delivery. Use the documented synthetic alert test to verify delivery:

```text
docs/observability-gitops-convergence.md
```

That test proves:

```text
Azure Key Vault -> ExternalSecret -> mounted Alertmanager files -> Telegram
```

## Completion criteria

Task 3.7 is verified when:

```text
[ ] The script is executable.
[ ] It is validated with shell syntax checking.
[ ] It is run from the DevContainer against the homelab.
[ ] It returns 0 when the platform is healthy.
[ ] At least one intentional non-destructive failure case is understood.
[ ] The script changes no Kubernetes resource.
[ ] This runbook is linked from Phase 3 and the scripts index.
```
