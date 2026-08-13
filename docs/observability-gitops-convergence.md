# Observability GitOps Convergence Runbook

> A complete record of the observability migration from manually managed Helm releases to Argo CD, including AppProject permissions, chart-version reconciliation, External Secrets, Telegram routing, validation, testing, and troubleshooting.

## 1. Purpose

This document explains the work completed to bring the homelab observability platform under GitOps control.

The scope includes:

- Prometheus, Grafana, Alertmanager, kube-state-metrics, and node-exporter
- Loki
- Grafana Alloy
- Grafana/Loki integration configuration
- Alertmanager Telegram configuration
- Azure Key Vault-backed Telegram credentials
- Argo CD project permissions and adoption of existing resources
- Safe diff review before synchronization

The goal is not merely to make Argo CD display these applications. The goal is to make the ownership model understandable and repeatable:

```text
Git
  -> Argo CD Application
  -> Helm chart rendering or Git manifest rendering
  -> Kubernetes resources
  -> External Secrets for secret values
  -> running observability platform
```

## 2. Final ownership model

Each layer has one primary owner.

| Layer | Owner | Responsibility |
|---|---|---|
| Physical hosts and operating system | Ansible | SSH, packages, host configuration, K3s host preparation |
| Cluster bootstrap | Terraform | MetalLB, Longhorn, and the Argo CD AppProject |
| Observability Helm releases | Argo CD | Monitoring, Loki, and Alloy chart releases |
| Observability configuration | Argo CD | Git-backed ConfigMaps, Services, and ExternalSecrets |
| Secret values | Azure Key Vault | Telegram bot token and Telegram chat ID |
| Secret synchronization | External Secrets Operator | Key Vault values into Kubernetes Secrets |
| Notifications | Alertmanager | Routing critical alerts to Telegram |

The important boundary is:

```text
Terraform owns the platform on which applications run.
Argo CD owns applications and observability workloads running on that platform.
Azure Key Vault owns secret values.
```

Terraform must not manage the same monitoring resources that Argo CD manages.

## 3. Repository layout

The relevant files are:

```text
kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
kubernetes/gitops/argocd/applications/monitoring.yaml
kubernetes/gitops/argocd/applications/loki.yaml
kubernetes/gitops/argocd/applications/alloy.yaml
kubernetes/gitops/argocd/applications/observability-config.yaml
kubernetes/observability/monitoring/values.yaml
kubernetes/observability/alerting/values-alertmanager.yaml
kubernetes/observability/logging/loki-values.yaml
kubernetes/observability/logging/alloy-values.yaml
kubernetes/observability/config/telegram-external-secret.yaml
kubernetes/observability/config/grafana-loki-datasource.yaml
kubernetes/observability/config/grafana-lb.yaml
kubernetes/observability/config/loki-log-alert-rules.yaml
```

The configuration directory is intentionally separate from the chart values:

```text
kubernetes/observability/monitoring/   Helm values
kubernetes/observability/logging/      Helm values
kubernetes/observability/alerting/     Alertmanager Helm values and documentation
kubernetes/observability/config/       Git-rendered Kubernetes resources
```

## 4. Starting point

Before convergence, the observability releases already existed in the cluster and had been installed or upgraded with Helm.

The important safety constraint was:

> Do not casually replace a working monitoring stack merely because Argo CD is being introduced.

The stack contains stateful and cluster-wide resources:

- Grafana PVC
- Prometheus PVC
- Alertmanager PVC
- Prometheus Operator CRDs
- ClusterRoles and ClusterRoleBindings
- Admission webhooks
- kube-system Service objects
- PrometheusRules and ServiceMonitors

Therefore the migration used this sequence:

```text
Inspect live releases
  -> reproduce their chart versions and values in Git
  -> create Argo Applications
  -> review generated diffs
  -> fix ownership permissions
  -> adopt resources carefully
```

## 5. Argo CD Applications

### 5.1 Monitoring

File:

```text
kubernetes/gitops/argocd/applications/monitoring.yaml
```

The Application uses the Prometheus Community Helm repository:

```yaml
repoURL: https://prometheus-community.github.io/helm-charts
chart: kube-prometheus-stack
targetRevision: 88.2.0
```

It loads two values files from the Git repository:

```text
kubernetes/observability/monitoring/values.yaml
kubernetes/observability/alerting/values-alertmanager.yaml
```

The monitoring values preserve important existing settings:

- Grafana uses a Longhorn PVC.
- Grafana uses `Recreate` deployment strategy to avoid Longhorn multi-attach conflicts.
- Prometheus retains 30 days of data.
- Prometheus uses a 20 GiB Longhorn PVC.
- Alertmanager uses a 5 GiB Longhorn PVC.
- Alertmanager mounts the `telegram-alerts` Secret.

The final sync policy is:

```yaml
automated:
  enabled: true
  prune: false
  selfHeal: true
```

`prune: false` is deliberate. It prevents an adoption mistake from deleting existing resources while the migration is being verified.

### 5.2 Loki

File:

```text
kubernetes/gitops/argocd/applications/loki.yaml
```

The Application uses:

```yaml
repoURL: https://grafana.github.io/helm-charts
chart: loki
targetRevision: 7.2.0
```

Loki is deployed to the `logging` namespace and uses:

```text
kubernetes/observability/logging/loki-values.yaml
```

### 5.3 Grafana Alloy

File:

```text
kubernetes/gitops/argocd/applications/alloy.yaml
```

The Application uses:

```yaml
repoURL: https://grafana.github.io/helm-charts
chart: alloy
targetRevision: 1.11.1
```

Alloy is deployed to the `logging` namespace and uses:

```text
kubernetes/observability/logging/alloy-values.yaml
```

The Alloy values configure a DaemonSet that:

- Discovers Pods on the local node.
- Reads Kubernetes container logs.
- Relabels namespace, pod, container, node, app, and job labels.
- Drops Alloy and Loki canary self-noise.
- Drops selected known noisy messages.
- Sends logs to Loki at `http://loki.logging.svc.cluster.local:3100/loki/api/v1/push`.

### 5.4 Observability configuration

File:

```text
kubernetes/gitops/argocd/applications/observability-config.yaml
```

This Application reads:

```text
kubernetes/observability/config
```

It manages Git-backed resources that are not chart values:

| Resource | Namespace | Purpose |
|---|---|---|
| `grafana-loki-datasource` ConfigMap | monitoring | Adds Loki as a Grafana data source |
| `grafana-lb` Service | monitoring | Exposes Grafana through MetalLB at `192.168.178.212` |
| `loki-log-alert-rules` ConfigMap | logging | Stores Loki ruler alert rules |
| `telegram-alerts` ExternalSecret | monitoring | Reads Telegram credentials from Azure Key Vault |

## 6. AppProject permissions

File:

```text
kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
```

The AppProject is Terraform-owned. Do not permanently apply it with `kubectl apply` and assume that is the source of truth. The YAML is the shared input, but Terraform applies the live AppProject.

### 6.1 Source repositories

The project allows the Git repository and both external Helm repositories:

```text
https://github.com/ali-fathi/devops-homelab.git
https://prometheus-community.github.io/helm-charts
https://grafana.github.io/helm-charts
```

Without the external Helm repositories, Argo CD reports errors such as:

```text
application repo ... is not permitted in project homelab-platform
```

### 6.2 Allowed destinations

The project allows these namespaces:

```text
garmin
monitoring
kube-system
logging
external-secrets-system
argocd
ring-health
health
```

`kube-system` is required because kube-prometheus-stack creates Service objects for control-plane component monitoring, including CoreDNS, scheduler, controller-manager, kube-proxy, and etcd.

### 6.3 Cluster-scoped resources

The project permits the cluster-scoped resources created by the observability charts:

```text
Namespace
ClusterRole
ClusterRoleBinding
CustomResourceDefinition
MutatingWebhookConfiguration
ValidatingWebhookConfiguration
```

The CRDs include Prometheus Operator resources such as:

```text
Prometheus
Alertmanager
PrometheusRule
ServiceMonitor
PodMonitor
Probe
ScrapeConfig
PrometheusAgent
ThanosRuler
AlertmanagerConfig
```

The admission webhooks are used by the Prometheus Operator for validation and mutation.

## 7. Terraform application of the AppProject

Terraform owns the AppProject through:

```text
terraform/argocd.tf
terraform/modules/argocd/main.tf
```

The module loads the same YAML file using `yamldecode`, which keeps the repository as a single source of truth.

The safe update flow is:

```text
Edit AppProject YAML
  -> commit and push
  -> terraform plan
  -> review only the AppProject change
  -> terraform apply
  -> refresh Argo applications
```

Use these one-line commands from the DevContainer:

```bash
export ARM_ACCESS_KEY="$(az keyvault secret show --vault-name kv-homelab-k3s --name terraform-state-key --query value -o tsv)"
```

```bash
export TF_VAR_kubeconfig_path="/home/vscode/.kube/config"
```

```bash
cd terraform && terraform init -reconfigure
```

```bash
terraform plan
```

```bash
terraform apply
```

Never run `terraform apply` without reviewing the plan first, particularly when the Kubernetes provider is connected to the production homelab cluster.

## 8. Chart-version reconciliation

During the first diff review, two desired versions were found to be older than the live releases.

The original desired values were:

```text
kube-prometheus-stack 87.10.1
Alloy 1.10.0
```

The live versions shown by the Argo diff were:

```text
kube-prometheus-stack 88.2.0
Alloy 1.11.1
```

The Git manifests were corrected to match the live releases:

```text
monitoring.yaml: targetRevision 88.2.0
alloy.yaml:      targetRevision 1.11.1
loki.yaml:       targetRevision 7.2.0
```

This prevented Argo CD from performing an unintended downgrade.

The version labels in diffs are meaningful. For example:

```text
live:    kube-prometheus-stack-88.2.0
desired: kube-prometheus-stack-87.10.1
```

is not an adoption-only difference. It means the desired chart would render older resources and potentially remove newer rules, images, or schema fields.

## 9. Understanding adoption diffs

When Argo CD adopts resources created by Helm, many diffs look like this:

```diff
+ argocd.argoproj.io/tracking-id: monitoring:...
```

This is expected. Argo adds its tracking annotation so it can associate the resource with an Application.

These additions are normally safe when:

- The resource name is unchanged.
- The namespace is unchanged.
- The kind and API group are unchanged.
- The chart version matches the live release.
- No PVC is deleted or renamed.
- No StatefulSet is replaced unexpectedly.

### Dangerous diff patterns

Stop and investigate if the diff contains:

```text
PersistentVolumeClaim deletion
StatefulSet deletion or replacement
storage size reduction
storageClassName change
service loadBalancerIP change
chart downgrade
CRD replacement with an incompatible schema
Secret replacement that changes credentials
```

A checksum change on a Deployment may restart Pods. It is not automatically data loss, but it must be understood, especially for Grafana and Alertmanager.

## 10. Telegram secret architecture

The Telegram flow is:

```text
Azure Key Vault
  -> ExternalSecret telegram-alerts
  -> Kubernetes Secret telegram-alerts
  -> Alertmanager Secret mount
  -> /etc/alertmanager/secrets/telegram-alerts/
  -> Telegram notification
```

Azure Key Vault contains these secret names:

```text
telegram-bot-token
telegram-chat-id
```

The ExternalSecret maps them to Kubernetes Secret keys:

```yaml
telegram-bot-token -> bot-token
telegram-chat-id   -> chat-id
```

The Kubernetes Secret is named:

```text
telegram-alerts
```

The Secret is in:

```text
monitoring
```

### Why the container file path is used

This path is not an Azure Key Vault path:

```text
/etc/alertmanager/secrets/telegram-alerts/chat-id
```

It is a file inside the Alertmanager container. The Prometheus Operator mounts the Kubernetes Secret because the Helm values contain:

```yaml
alertmanagerSpec:
  secrets:
    - telegram-alerts
```

Kubernetes then exposes the Secret keys as files:

```text
/etc/alertmanager/secrets/telegram-alerts/bot-token
/etc/alertmanager/secrets/telegram-alerts/chat-id
```

Alertmanager reads the files using:

```yaml
bot_token_file: /etc/alertmanager/secrets/telegram-alerts/bot-token
chat_id_file: /etc/alertmanager/secrets/telegram-alerts/chat-id
```

This keeps the actual bot token and chat ID out of Git and out of the rendered Helm values.

### Telegram configuration before the fix

The Alertmanager values contained a hard-coded chat ID:

```yaml
chat_id: 123456
```

That was replaced with:

```yaml
chat_id_file: /etc/alertmanager/secrets/telegram-alerts/chat-id
```

The bot token was already file-backed. Now both Telegram credentials use the same secure pattern.

## 11. ExternalSecret default-field drift

The External Secrets Operator defaulted three fields in the live object:

```yaml
conversionStrategy: Default
decodingStrategy: None
metadataPolicy: None
```

The desired Git manifest omitted them, so Argo CD showed the ExternalSecret as `OutOfSync` even though its health was `Healthy` and the Secret was synchronized.

Those fields were made explicit for both remote references:

```yaml
- secretKey: bot-token
  remoteRef:
    key: telegram-bot-token
    conversionStrategy: Default
    decodingStrategy: None
    metadataPolicy: None

- secretKey: chat-id
  remoteRef:
    key: telegram-chat-id
    conversionStrategy: Default
    decodingStrategy: None
    metadataPolicy: None
```

This is a declarative-drift correction. It does not change the values in Azure Key Vault or rotate the Kubernetes Secret.

## 12. Validation commands

All commands in this section are intentionally single-line commands for reliable copy/paste into the VS Code terminal.

Check the working tree:

```bash
git status --short --branch
```

Validate YAML:

```bash
python3 -m yamllint kubernetes/gitops/argocd/projects/homelab-platform-project.yaml kubernetes/gitops/argocd/applications/monitoring.yaml kubernetes/gitops/argocd/applications/loki.yaml kubernetes/gitops/argocd/applications/alloy.yaml kubernetes/gitops/argocd/applications/observability-config.yaml kubernetes/observability/config/telegram-external-secret.yaml kubernetes/observability/alerting/values-alertmanager.yaml
```

Check whitespace errors:

```bash
git diff --check
```

Check the live AppProject permissions without displaying secrets:

```bash
kubectl get appproject homelab-platform -n argocd -o json | jq '{destinations: [.spec.destinations[] | .namespace], clusterResourceWhitelist: .spec.clusterResourceWhitelist}'
```

Check the ExternalSecret:

```bash
kubectl get externalsecret telegram-alerts -n monitoring
```

Inspect only Secret key names:

```bash
kubectl get secret telegram-alerts -n monitoring -o json | jq '{keys: (.data | keys)}'
```

Expected keys:

```text
bot-token
chat-id
```

Verify that the chat ID is numeric without printing its value:

```bash
kubectl get secret telegram-alerts -n monitoring -o jsonpath='{.data.chat-id}' | base64 -d | grep -Eq '^-?[0-9]+$' && echo 'chat-id is numeric' || echo 'chat-id missing or invalid'
```

Check the Alertmanager Pod:

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager
```

Check the mounted file names without printing file contents:

```bash
kubectl exec -n monitoring alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager -- find /etc/alertmanager/secrets/telegram-alerts -maxdepth 1 -type f -printf '%f\n'
```

Check the applications:

```bash
argocd app list
```

Inspect monitoring status:

```bash
argocd app get monitoring
```

Inspect the configuration Application:

```bash
argocd app get observability-config
```

Refresh and diff monitoring using the CLI version available in this environment:

```bash
argocd app diff monitoring --hard-refresh --diff-exit-code 0
```

Refresh and diff the configuration Application:

```bash
argocd app diff observability-config --hard-refresh --diff-exit-code 0
```

Important CLI note:

```text
argocd app refresh monitoring --hard
```

is not supported by the CLI version used in this environment. Use:

```text
argocd app diff monitoring --hard-refresh
```

The `--hard-refresh` flag belongs to `argocd app diff` here.

## 13. GitOps change workflow

For a normal change to observability values:

1. Edit the file in Git.
2. Run YAML validation.
3. Review the local diff.
4. Commit and push.
5. Refresh the relevant Argo Application.
6. Review the server-side diff.
7. Allow automated sync or sync manually.
8. Verify health and running Pods.

Example commit and push command:

```bash
git add kubernetes/observability/alerting/values-alertmanager.yaml kubernetes/observability/config/telegram-external-secret.yaml && git commit -m 'fix(alerting): manage Telegram credentials through Key Vault' && git push origin main
```

Monitoring uses automated synchronization with pruning disabled:

```yaml
automated:
  enabled: true
  prune: false
  selfHeal: true
```

If automation has been paused for safety, re-enable it from the committed Application manifest:

```bash
kubectl apply -f kubernetes/gitops/argocd/applications/monitoring.yaml
```

Do not permanently patch the live Application without committing the equivalent desired state to Git.

## 14. Telegram end-to-end test

The test verifies the complete path:

```text
Azure Key Vault
  -> ExternalSecret
  -> Kubernetes Secret
  -> Alertmanager mounted file
  -> Alertmanager receiver
  -> Telegram chat
```

### 14.1 Preconditions

Confirm the ExternalSecret is healthy:

```bash
kubectl get externalsecret telegram-alerts -n monitoring
```

Confirm the Secret keys exist:

```bash
kubectl get secret telegram-alerts -n monitoring -o json | jq '{keys: (.data | keys)}'
```

Confirm the Application is healthy:

```bash
argocd app get monitoring | grep -E 'Sync Status|Health Status'
```

### 14.2 Port-forward Alertmanager

Run this in one terminal and leave it running:

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

### 14.3 Submit a synthetic critical alert

Run this in a second terminal:

```bash
now=$(date -u +%Y-%m-%dT%H:%M:%SZ); curl -fsS -X POST http://127.0.0.1:9093/api/v2/alerts -H 'Content-Type: application/json' --data "[{\"labels\":{\"alertname\":\"TelegramRoutingTest\",\"severity\":\"critical\",\"instance\":\"manual-test\"},\"annotations\":{\"summary\":\"Telegram routing test\",\"description\":\"Testing Azure Key Vault chat ID delivery.\"},\"startsAt\":\"$now\"}]" && echo 'Alert submitted'
```

The configured `group_wait` is one minute, so wait at least one minute for delivery.

A successful Telegram message proves that:

- The Secret was synchronized from Key Vault.
- The chat ID file was mounted.
- Alertmanager accepted the configuration.
- The `critical` route selected the Telegram receiver.
- Telegram accepted the bot request.

### 14.4 Resolve the test alert

After receiving the message, resolve the synthetic alert:

```bash
now=$(date -u +%Y-%m-%dT%H:%M:%SZ); curl -fsS -X POST http://127.0.0.1:9093/api/v2/alerts -H 'Content-Type: application/json' --data "[{\"labels\":{\"alertname\":\"TelegramRoutingTest\",\"severity\":\"critical\",\"instance\":\"manual-test\"},\"endsAt\":\"$now\"}]" && echo 'Test alert resolved'
```

The current configuration has `send_resolved: false`, so a resolved notification is not expected.

## 15. Troubleshooting

### 15.1 ExternalSecret is OutOfSync but Healthy

Check the diff:

```bash
argocd app diff observability-config --hard-refresh --diff-exit-code 0
```

If the only changes are ESO default fields such as `conversionStrategy`, `decodingStrategy`, or `metadataPolicy`, declare those fields in `telegram-external-secret.yaml` and commit the change.

Do not delete the Secret. The ExternalSecret owns its lifecycle.

### 15.2 ExternalSecret is not Ready

Inspect status and events:

```bash
kubectl describe externalsecret telegram-alerts -n monitoring
```

Check the provider:

```bash
kubectl get clustersecretstore azure-keyvault
```

```bash
kubectl describe clustersecretstore azure-keyvault
```

Check External Secrets logs:

```bash
kubectl logs -n external-secrets-system deployment/external-secrets --since=10m --tail=100
```

Common causes:

```text
Key Vault secret name does not exist
Azure identity lacks secret-read permission
ClusterSecretStore is not Ready
Wrong tenant, vault URL, or client identity
Azure secret was changed but refresh has not occurred yet
```

### 15.3 Secret has only one key

Inspect key names without values:

```bash
kubectl get secret telegram-alerts -n monitoring -o json | jq '{keys: (.data | keys)}'
```

Both keys must exist:

```text
bot-token
chat-id
```

Check that both `data` entries exist in the ExternalSecret and that the remote names are:

```text
telegram-bot-token
telegram-chat-id
```

### 15.4 Alertmanager cannot read the file

Check the Pod:

```bash
kubectl get pod alertmanager-monitoring-kube-prometheus-alertmanager-0 -n monitoring
```

Check the mount directory:

```bash
kubectl exec -n monitoring alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager -- ls -la /etc/alertmanager/secrets/telegram-alerts
```

Expected file names:

```text
bot-token
chat-id
```

If the directory is absent, check that `alertmanagerSpec.secrets` contains `telegram-alerts` in the monitoring values used by the Argo Application.

### 15.5 Alertmanager rejects the configuration

Inspect Alertmanager logs:

```bash
kubectl logs -n monitoring alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager --since=10m --tail=100
```

Search for Telegram, configuration, or notification errors:

```bash
kubectl logs -n monitoring alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager --since=10m --tail=200 | grep -Ei 'telegram|config|notification|error|failed'
```

Typical causes:

```text
chat_id_file path is incorrect
chat-id key is missing from the mounted Secret
chat ID contains whitespace or a non-numeric value
bot token is invalid or revoked
Alertmanager configuration was not reloaded
```

### 15.6 Alert is accepted but no Telegram message arrives

Check Alertmanager's active alerts:

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

```bash
curl -fsS http://127.0.0.1:9093/api/v2/alerts | jq '.[] | {labels, status}'
```

Confirm the synthetic alert has `severity=critical`. The route only sends critical alerts to Telegram.

Remember:

```text
group_wait: 1m
send_resolved: false
```

Check recent logs:

```bash
kubectl logs -n monitoring alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager --since=15m --tail=200 | grep -Ei 'telegram|notify|error|failed'
```

The most common remaining cause is an incorrect Telegram chat ID in Azure Key Vault.

### 15.7 AppProject denies resources

Inspect the live project:

```bash
kubectl get appproject homelab-platform -n argocd -o yaml
```

Check that the project includes:

```text
prometheus-community Helm repository
grafana Helm repository
monitoring destination
logging destination
kube-system destination
ClusterRole
ClusterRoleBinding
CustomResourceDefinition
MutatingWebhookConfiguration
ValidatingWebhookConfiguration
```

Because Terraform owns this object, update the YAML and apply through Terraform rather than treating a direct kubectl patch as a permanent fix.

### 15.8 Argo shows a chart downgrade

Check the Application target revision:

```bash
kubectl get application monitoring -n argocd -o jsonpath='{.spec.source.targetRevision}{"\n"}'
```

Check Git:

```bash
grep -n 'targetRevision' kubernetes/gitops/argocd/applications/monitoring.yaml
```

The final expected monitoring chart is:

```text
88.2.0
```

The final expected Alloy chart is:

```text
1.11.1
```

Never sync a chart downgrade without an explicit upgrade/downgrade plan and a backup/rollback procedure.

## 16. Safe rollback

The preferred rollback is Git-based:

```text
revert the commit
  -> push the revert
  -> let Argo render the previous desired state
  -> verify the application
```

Find recent commits:

```bash
git log --oneline -10
```

Revert the latest change only after confirming it is the change to undo:

```bash
git revert <commit-sha> && git push origin main
```

Refresh and inspect:

```bash
argocd app diff monitoring --hard-refresh --diff-exit-code 0
```

Do not delete monitoring PVCs as a rollback technique.

## 17. Security rules

Never commit any of these values:

```text
Telegram bot token
Telegram chat ID
Grafana admin password
Alertmanager generated configuration Secret
Azure client secret
GitHub token
```

It is safe to commit:

```text
Azure Key Vault secret names
Kubernetes Secret key names
ExternalSecret mappings
file paths inside Pods
Helm chart versions
routing configuration without credential values
```

Do not use commands that print Secret values into shell history or CI logs.

Use key-name-only checks such as:

```bash
kubectl get secret telegram-alerts -n monitoring -o json | jq '{keys: (.data | keys)}'
```

## 18. Completion checklist

The observability convergence is complete when:

```text
[ ] Monitoring Application uses chart 88.2.0.
[ ] Loki Application uses chart 7.2.0.
[ ] Alloy Application uses chart 1.11.1.
[ ] External Helm repositories are allowed by the AppProject.
[ ] monitoring, logging, and kube-system destinations are allowed.
[ ] Required cluster-scoped resources are allowed.
[ ] Monitoring Pods remain Healthy.
[ ] Existing PVCs remain present and bound.
[ ] No unintended StatefulSet replacement appears in the diff.
[ ] Argo tracking annotations are understood as adoption metadata.
[ ] Telegram bot token comes from Azure Key Vault.
[ ] Telegram chat ID comes from Azure Key Vault.
[ ] Alertmanager reads both credentials through mounted files.
[ ] ExternalSecret default fields are declared in Git.
[ ] A synthetic critical Telegram alert has been delivered successfully.
[ ] The synthetic test alert has been resolved.
[ ] Pruning remains disabled until backup and restore are proven.
```

## 19. Useful related documents

```text
docs/homelab-study-guide.md
docs/gitops.md
docs/runbooks/argocd-app-outofsync.md
docs/runbooks/argocd-comparison-error.md
docs/runbooks/external-secrets-debug.md
kubernetes/observability/README.md
kubernetes/observability/alerting/README.md
kubernetes/gitops/argocd/README.md
docs/expansion-plan-phase-2.md
```
