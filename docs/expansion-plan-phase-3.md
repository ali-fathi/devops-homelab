# Expansion Plan — Phase 3: GitOps Convergence and Delivery Maturity

> **The implementation record and learning plan for moving the homelab from individually applied Argo CD Applications toward a self-managing GitOps delivery layer.**

Phase 2 established Terraform ownership for cluster bootstrap resources, an Azure Storage remote Terraform state backend, and a Terraform CI plan gate. Phase 3 builds on that foundation by making the platform workloads and their delivery process consistently GitOps-managed.

## Phase 3 goal

```text
From:
  Individual Argo CD Applications created or updated manually
  Helm-managed observability releases outside the GitOps control loop
  Chart/value errors discovered only at Argo CD sync time

To:
  Git-managed Argo CD child Applications
  A single root Application that reconciles child Applications
  Observability Helm releases rendered by Argo CD
  Helm chart rendering validated in CI before sync
  Explicit ownership, safety gates, and runbooks
```

## Ownership boundary

| Layer | Owner | Scope |
|---|---|---|
| Hosts and operating system | Ansible | Node access, packages, and K3s host configuration |
| Bootstrap platform | Terraform | Remote state, MetalLB, Longhorn, and Argo CD AppProject |
| Application orchestration | Argo CD root Application | Creates and updates child Application resources |
| Platform and application delivery | Argo CD child Applications | Helm releases and Git-rendered manifests |
| Secret values | Azure Key Vault | Credentials and sensitive identifiers |
| Secret delivery | External Secrets Operator | Key Vault values to Kubernetes Secrets |
| Pre-merge checks | GitHub Actions | YAML, schema, Terraform, security, and Helm rendering validation |

> A Kubernetes resource must have one clear owner. Terraform does not manage child Argo CD Applications; the root Application does not directly manage workload resources; child Applications do.

## Task map

| Task | Status | Primary outcome | Key files |
|---|---|---|---|
| **3.1** Observability convergence | Complete | Monitoring, Loki, Alloy, and observability config represented by Argo CD Applications | `kubernetes/gitops/argocd/applications/` |
| **3.2** AppProject permissions | Complete | Allowed Helm sources, destinations, and required cluster resources | `kubernetes/gitops/argocd/projects/homelab-platform-project.yaml` |
| **3.3** Azure Key Vault alert routing | Complete | Telegram bot token and chat ID are mounted from an ESO-managed Secret | `values-alertmanager.yaml`, `telegram-external-secret.yaml` |
| **3.4** Root app-of-apps | Complete | One root Application manages all child Application objects | `bootstrap/root-application.yaml` |
| **3.5** GitOps chain proof | Complete | Metadata-only child Application change reconciled through the root Application | `health-dashboard.yaml` |
| **3.6** Helm render CI gate | Implemented; verify in GitHub Actions | CI renders the exact pinned observability Helm charts and values | `.github/workflows/kubernetes-validate.yaml` |
| **3.7** Deployment health gates | Verified | Reusable post-sync verification for applications, Pods, PVCs, endpoints, metrics, logs, and alerts | `scripts/verify-gitops-health.sh`, `docs/runbooks/gitops-post-sync-verification.md` |
| **3.8** Backup/restore rehearsal | Implemented; live rehearsal required | Prove external-backup recovery before enabling pruning or larger upgrades | `scripts/rehearse-longhorn-backup-restore.sh`, `docs/runbooks/longhorn-backup-restore-rehearsal.md` |

## Task 3.1 — Observability convergence ✅

The observability stack is delivered through four Argo CD Applications:

```text
monitoring             kube-prometheus-stack 88.2.0     -> monitoring namespace
loki                   Loki 7.2.0                        -> logging namespace
alloy                  Grafana Alloy 1.11.1              -> logging namespace
observability-config   Git-backed configuration resources -> monitoring/logging namespaces
```

The monitoring Application uses two values files:

```text
kubernetes/observability/monitoring/values.yaml
kubernetes/observability/alerting/values-alertmanager.yaml
```

The deployment deliberately uses:

```yaml
automated:
  enabled: true
  prune: false
  selfHeal: true
```

`prune: false` protects existing resources while adoption and restore procedures are being validated.

Detailed record:

```text
docs/observability-gitops-convergence.md
```

## Task 3.2 — AppProject permissions ✅

The `homelab-platform` AppProject must permit every source, destination, and cluster resource used by its Applications.

The observability migration required:

```text
Source repositories:
- devops-homelab Git repository
- Prometheus Community Helm repository
- Grafana Helm repository

Destinations:
- monitoring
- logging
- kube-system

Cluster-scoped resources:
- ClusterRole
- ClusterRoleBinding
- CustomResourceDefinition
- MutatingWebhookConfiguration
- ValidatingWebhookConfiguration
```

`kube-system` is required because kube-prometheus-stack renders control-plane monitoring Service objects there. Cluster-scoped permissions are required for Prometheus Operator CRDs, RBAC, and admission webhooks.

Terraform owns the live AppProject, so the permanent workflow is:

```text
Edit committed YAML
  -> terraform plan
  -> review
  -> terraform apply
```

## Task 3.3 — Azure Key Vault Alertmanager credentials ✅

The Telegram notification path is:

```text
Azure Key Vault
  -> ExternalSecret telegram-alerts
  -> Kubernetes Secret telegram-alerts
  -> mounted files in Alertmanager
  -> Telegram Bot API
  -> Telegram chat
```

Secret names in Key Vault:

```text
telegram-bot-token
telegram-chat-id
```

Kubernetes Secret keys:

```text
bot-token
chat-id
```

Alertmanager reads mounted files rather than hard-coded values:

```yaml
bot_token_file: /etc/alertmanager/secrets/telegram-alerts/bot-token
chat_id_file: /etc/alertmanager/secrets/telegram-alerts/chat-id
```

The External Secrets Operator adds default fields to live resources. These fields are explicitly represented in Git so that the ExternalSecret does not remain OutOfSync solely due to defaulting:

```yaml
conversionStrategy: Default
decodingStrategy: None
metadataPolicy: None
```

Never print or commit Secret values. Check only key names:

```bash
kubectl get secret telegram-alerts -n monitoring -o json | jq '{keys: (.data | keys)}'
```

## Task 3.4 — Root app-of-apps ✅

The root Application is:

```text
homelab-applications
```

Manifest:

```text
kubernetes/gitops/argocd/bootstrap/root-application.yaml
```

It watches:

```text
kubernetes/gitops/argocd/applications/
```

and manages these child Application objects:

```text
alloy
garmin
health-dashboard
loki
monitoring
observability-config
ring-health-tracker
```

The root Application must be created once:

```bash
kubectl apply -f kubernetes/gitops/argocd/bootstrap/root-application.yaml
```

After bootstrapping, child Application changes flow from Git through the root Application. The bootstrap manifest is outside the watched directory so the root Application never attempts to manage itself.

Detailed record:

```text
docs/gitops-app-of-apps.md
```

## Task 3.5 — GitOps chain proof ✅

A harmless metadata annotation was added to the `health-dashboard` child Application. The expected delivery path was verified:

```text
Git push
  -> root Application detects child manifest change
  -> root Application updates health-dashboard Application object
  -> health-dashboard workload stays healthy
```

This test deliberately did not modify workloads, images, Services, or PVCs.

## Task 3.6 — Helm render CI gate 🟡

The Kubernetes validation workflow now has three jobs:

```text
1. YAML syntax and style
2. Kubernetes schema validation
3. Helm render validation
```

The Helm job:

1. Installs Helm.
2. Adds Prometheus Community and Grafana Helm repositories.
3. Renders the exact pinned chart versions used by Argo CD.
4. Uses the values files from the checked-out commit or pull request.
5. Fails if Helm cannot resolve a chart, render values, or produce manifests.

The rendered release combinations are:

```text
monitoring + kube-prometheus-stack 88.2.0 + monitoring and Alertmanager values
loki       + Loki 7.2.0 + Loki values
alloy      + Alloy 1.11.1 + Alloy values
```

This is a non-deploying validation gate. It does not receive Kubernetes credentials and does not contact the homelab cluster.

### Verification required

After the CI workflow change is pushed, verify in GitHub Actions that all three jobs pass:

```text
YAML syntax and style
Kubernetes schema validation
Helm render validation
```

Until that run completes successfully, Task 3.6 is implemented but not fully verified.

Detailed record:

```text
docs/ci-manifest-validation.md
```

## Task 3.7 — Deployment health gates 🟡

A repeatable post-sync health gate has been implemented. It creates:

```text
scripts/verify-gitops-health.sh
docs/runbooks/gitops-post-sync-verification.md
```

The full checks, expected output, troubleshooting order, and safety constraints are documented in [GitOps Post-Sync Health Verification](runbooks/gitops-post-sync-verification.md).

The script is read-only. It does not call `kubectl apply`, `helm upgrade`, `argocd app sync`, or delete resources.

### Required checks

| Layer | Check |
|---|---|
| Argo CD | Root and child Applications are Synced/Healthy |
| Kubernetes | Required Pods are Running and Ready |
| Storage | Stateful PVCs are Bound |
| Networking | Required Services have endpoints |
| Monitoring | Prometheus, Grafana, and Alertmanager resources are healthy |
| Logging | Loki and Alloy resources are healthy |
| Secrets | ExternalSecrets report Ready without printing values |
| Alerting | Alertmanager has a valid configuration and Telegram test procedure is documented |

### Proposed command groups

```text
argocd app get <application>
kubectl get pods -n <namespace>
kubectl get pvc -n <namespace>
kubectl get endpoints -n <namespace>
kubectl get externalsecret -A
kubectl get prometheus,alertmanager -n monitoring
```

The script should return a non-zero status when an expected resource is unhealthy, but it should always print enough context for an operator to begin troubleshooting.

## Task 3.8 — Backup and restore rehearsal 🟡

An isolated, opt-in Longhorn rehearsal is implemented in `scripts/rehearse-longhorn-backup-restore.sh`. It records non-secret PVC/Longhorn inventory, writes a deterministic fixture to a new test PVC, creates an external backup with a CSI `VolumeSnapshotClass` (`type: bak`), restores a second new PVC, and verifies equal SHA-256 checksums. The complete procedure, backup-target boundary, cleanup, rollback, and RPO/RTO guidance is in [Longhorn Backup and Restore Rehearsal](runbooks/longhorn-backup-restore-rehearsal.md).

It is not verified until the default external Longhorn `BackupTarget` is available and a live run returns `[PASS]`. Do not enable pruning on stateful Applications before that live evidence is recorded.

The rehearsal should cover at least one non-production or low-risk recovery path:

```text
1. Record PVC and Longhorn volume inventory.
2. Create a Longhorn backup/snapshot.
3. Restore to a new test volume or test workload.
4. Verify data integrity and application health.
5. Record the exact rollback and recovery procedure.
6. Define recovery point and recovery time expectations.
```

Stateful components that need an explicit recovery plan include:

```text
Grafana
Prometheus
Alertmanager
Loki
Garmin InfluxDB
Ring VictoriaMetrics
```

## Documentation standard for every task

Every expansion task must produce or update documentation before it is declared complete.

For each task, record:

```text
1. Goal and non-goals
2. Current state and desired state
3. Architecture/data flow
4. Ownership boundary
5. Files changed and why
6. Versions pinned and why
7. Secrets and sensitive-data handling
8. Exact validation commands
9. Expected success output
10. Failure symptoms and troubleshooting commands
11. Safety constraints and rollback procedure
12. Final status: planned, implemented, or verified
```

Use one-line terminal commands in documents wherever a command may be copied into the VS Code terminal.

A task is only **verified** after its intended end-to-end behavior has been observed. Passing YAML validation alone means the task is implemented, not verified.

## Phase 3 completion criteria

```text
[ ] Observability Applications are Synced and Healthy.
[ ] Telegram routing test is delivered successfully.
[ ] Root Application is Synced and Healthy.
[ ] Git -> root -> child Application reconciliation is proven.
[ ] Helm render CI job is green in GitHub Actions.
[ ] Read-only post-sync health gate exists and is tested.
[ ] Stateful backup and restore rehearsal is documented and tested.
[ ] Pruning remains disabled until restore is proven.
```

## Related documentation

```text
docs/expansion-plan-phase-2.md
docs/observability-gitops-convergence.md
docs/gitops-app-of-apps.md
docs/ci-manifest-validation.md
docs/terraform-ci-runbook.md
docs/runbooks/argocd-app-outofsync.md
docs/runbooks/external-secrets-debug.md
```
