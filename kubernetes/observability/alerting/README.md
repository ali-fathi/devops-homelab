# 🚨 Phase 4.1 – Azure Key Vault + External Secrets Operator + Alertmanager + Telegram

## Overview

This phase extends the monitoring stack by introducing secure secret management and alerting.

Before this phase:

```text
K3s
MetalLB
Longhorn
Prometheus
Grafana
```

After this phase:

```text
K3s
MetalLB
Longhorn
Prometheus
Grafana
Azure Key Vault
External Secrets Operator
Alertmanager
Telegram Alerting
```

---

# 🎯 Goals

After completing this phase you will have:

✅ Centralized Secret Management

✅ No Secrets Stored in GitHub

✅ Azure Key Vault Integration

✅ External Secrets Operator (ESO)

✅ Alertmanager

✅ Telegram Notifications

✅ Infrastructure Alerts

✅ Kubernetes Alerts

✅ Longhorn Alerts

✅ Production-Style Secret Management

---

# 🏗️ Architecture

```text
GitHub Repository
        │
        ▼

ExternalSecret
ClusterSecretStore
        │
        ▼

Azure Key Vault
        │
        ▼

External Secrets Operator
        │
        ▼

Kubernetes Secret
        │
        ▼

Alertmanager
        │
        ▼

Telegram Bot
        │
        ▼

Telegram Notifications
```

---

# Why Azure Key Vault?

Never commit secrets to Git.

Bad:

```yaml
password: MySecretPassword
bot-token: 123456789
```

Good:

```text
Azure Key Vault
```

Benefits:

```text
Centralized Secret Storage
Access Control
Key Rotation
Audit Logs
GitHub Safe
RBAC Support
```

---

# 💰 Cost Optimization

For a homelab:

Use:

```text
Azure Key Vault Standard
```

Do NOT use:

```text
Premium
Managed HSM
```

Store only:

```text
Bot Tokens
Passwords
Certificates
API Keys
SMTP Credentials
```

Do NOT store:

```text
Hostnames
IPs
Namespaces
Configuration
```

Set External Secrets refresh interval:

```yaml
refreshInterval: 48h
```

This minimizes API calls and keeps Azure costs extremely low.

---

# 📂 Repository Structure

```text
kubernetes/
└── observability/
    └── alerting/
        ├── README.md
        ├── clustersecretstore.yaml
        ├── telegram-external-secret.yaml
        ├── prometheusrules/
        │   ├── node-alerts.yaml
        │   ├── kubernetes-alerts.yaml
        │   ├── storage-alerts.yaml
        │   └── longhorn-alerts.yaml
        └── templates/
            └── telegram-message-template.md
```

---

# Step 1 – Install Azure CLI

Verify:

```bash
az version
```

Login:

```bash
az login
```

Verify:

```bash
az account show
```

---

# Step 2 – Create Azure Resource Group

```bash
az group create \
  --name rg-homelab \
  --location westeurope
```

Verify:

```bash
az group show \
  --name rg-homelab
```

---

# Step 3 – Create Azure Key Vault

```bash
az keyvault create \
  --name kv-homelab-k3s \
  --resource-group rg-homelab \
  --location westeurope \
  --enable-rbac-authorization true
```

Verify:

```bash
az keyvault list -o table
```

Expected:

```text
kv-homelab-k3s
```

---

# Step 4 – Create Service Principal

Since K3s is not AKS, Service Principal authentication is simplest.

Create:

```bash
az ad sp create-for-rbac \
  --name homelab-eso
```

Example output:

```json
{
  "appId": "11111111-2222-3333-4444-555555555555",
  "password": "XXXXXXXXXXXXXXXXXXXXXXXX",
  "tenant": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
}
```

Save:

```text
appId    = CLIENT_ID
password = CLIENT_SECRET
tenant   = TENANT_ID
```

Store these somewhere secure:

```text
1Password
Bitwarden
KeePassXC
```

---

# Step 5 – Grant Key Vault Permissions

Get Key Vault ID:

```bash
az keyvault show \
  --name kv-homelab-k3s \
  --query id \
  -o tsv
```

Assign role:

```bash
az role assignment create \
  --assignee CLIENT_ID \
  --role "Key Vault Secrets User" \
  --scope KEYVAULT_ID
```

---

# Step 6 – Create Telegram Bot

Open Telegram.

Search:

```text
@BotFather
```

Run:

```text
/newbot
```

Example:

```text
homelab-alert-bot
```

BotFather returns:

```text
1234567890:AAAXXXXXXXXXXXXXXXX
```

Save:

```text
BOT_TOKEN
```

---

# Step 7 – Obtain Telegram Chat ID

Send message:

```text
hello
```

to the bot.

Then visit:

```text
https://api.telegram.org/bot<BOT_TOKEN>/getUpdates
```

Example response:

```json
{
  "chat": {
    "id": 123456789
  }
}
```

Save:

```text
CHAT_ID
```

---

# Step 8 – Store Telegram Secrets in Azure Key Vault

Bot Token:

```bash
az keyvault secret set \
  --vault-name kv-homelab-k3s \
  --name telegram-bot-token \
  --value "YOUR_REAL_BOT_TOKEN"
```

Chat ID:

```bash
az keyvault secret set \
  --vault-name kv-homelab-k3s \
  --name telegram-chat-id \
  --value "YOUR_CHAT_ID"
```

Verify:

```bash
az keyvault secret list \
  --vault-name kv-homelab-k3s \
  -o table
```

Expected:

```text
telegram-bot-token
telegram-chat-id
```

---

# Step 9 – Install External Secrets Operator

Add repository:

```bash
helm repo add external-secrets \
https://charts.external-secrets.io

helm repo update
```

Install:

```bash
helm install external-secrets \
external-secrets/external-secrets \
-n external-secrets-system \
--create-namespace \
--set installCRDs=true
```

Verify:

```bash
kubectl get pods \
-n external-secrets-system
```

Expected:

```text
external-secrets
external-secrets-webhook
external-secrets-cert-controller
```

---

# Step 10 – Create Local Authentication Secret

File:

```text
azure-keyvault-auth.yaml
```

⚠️ NEVER COMMIT THIS FILE

Add to:

```gitignore
azure-keyvault-auth.yaml
```

Content:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: azure-keyvault-auth
  namespace: external-secrets-system
type: Opaque

stringData:
  ClientID: "YOUR_APP_ID"
  ClientSecret: "YOUR_CLIENT_SECRET"
```

Apply:

```bash
kubectl apply -f azure-keyvault-auth.yaml
```

---

# Step 11 – Create ClusterSecretStore

File:

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore

metadata:
  name: azure-keyvault

spec:
  provider:
    azurekv:
      authType: ServicePrincipal

      tenantId: "YOUR_TENANT_ID"

      vaultUrl: "https://kv-homelab-k3s.vault.azure.net"

      authSecretRef:
        clientId:
          name: azure-keyvault-auth
          namespace: external-secrets-system
          key: ClientID

        clientSecret:
          name: azure-keyvault-auth
          namespace: external-secrets-system
          key: ClientSecret
```

Apply:

```bash
kubectl apply -f clustersecretstore.yaml
```

Verify:

```bash
kubectl get clustersecretstore
```

Expected:

```text
READY True
```

---

# Step 12 – Create Telegram External Secret

File:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret

metadata:
  name: telegram-alerts
  namespace: monitoring

spec:
  refreshInterval:48h

  secretStoreRef:
    kind: ClusterSecretStore
    name: azure-keyvault

  target:
    name: telegram-alerts

  data:
    - secretKey: bot-token
      remoteRef:
        key: telegram-bot-token

    - secretKey: chat-id
      remoteRef:
        key: telegram-chat-id
```

Apply:

```bash
kubectl apply -f telegram-external-secret.yaml
```

Verify:

```bash
kubectl get externalsecret -n monitoring
```

---

# Step 13 – Verify Secret Synchronization

Verify:

```bash
kubectl get secret telegram-alerts \
  -n monitoring
```

Expected:

```text
telegram-alerts
```

---

# Alert Categories

The following alerts are recommended.

```text
Infrastructure
Kubernetes
Storage
Longhorn
Application
```

---

# 🚨 Infrastructure Alerts

---

## Node Down

```yaml
alert: NodeDown
expr: up == 0
for: 2m
```

Telegram:

```text
🚨 Node Down

Node:
k3s-worker1

Status:
Unreachable
```

---

## Node Not Ready

```yaml
alert: NodeNotReady

expr:
kube_node_status_condition{
condition="Ready",
status="true"
} == 0

for: 5m
```

---

## High CPU Usage

```yaml
alert: HighCPUUsage

expr:
(
100 -
(
avg by(instance)
(
rate(node_cpu_seconds_total{
mode="idle"
}[5m])
)
*100
)
) > 85

for: 10m
```

---

## High Memory Usage

```yaml
alert: HighMemoryUsage

expr:
(
(
node_memory_MemTotal_bytes
-
node_memory_MemAvailable_bytes
)
/
node_memory_MemTotal_bytes
)
*100 > 90

for: 10m
```

---

## Disk Usage Warning

```yaml
alert: DiskUsage80

expr:
100 -
(
node_filesystem_avail_bytes
/
node_filesystem_size_bytes
*100
)
> 80

for: 15m
```

---

## Disk Usage Critical

```yaml
alert: DiskUsage90

expr:
100 -
(
node_filesystem_avail_bytes
/
node_filesystem_size_bytes
*100
)
> 90

for: 5m
```

---

# ☸️ Kubernetes Alerts

---

## Pod CrashLoopBackOff

```yaml
alert: PodCrashLoopBackOff

expr:
kube_pod_container_status_waiting_reason{
reason="CrashLoopBackOff"
} > 0

for: 5m
```

---

## Frequent Pod Restarts

```yaml
alert: PodRestarts

expr:
increase(
kube_pod_container_status_restarts_total[1h]
) > 5
```

---

## Deployment Not Available

```yaml
alert: DeploymentUnavailable

expr:
kube_deployment_status_replicas_available
<
kube_deployment_spec_replicas

for: 5m
```

---

# 💾 Storage Alerts

---

## PVC Usage Above 80%

```yaml
alert: PVCUsage80

expr:
(
kubelet_volume_stats_used_bytes
/
kubelet_volume_stats_capacity_bytes
) *100 >80

for: 15m
```

---

## PVC Pending

```yaml
alert: PVCPending

expr:
kube_persistentvolumeclaim_status_phase{
phase="Pending"
} > 0

for: 5m
```

---

# 🏗️ Longhorn Alerts

---

## Volume Degraded

```yaml
alert: LonghornVolumeDegraded

expr:
longhorn_volume_robustness != 2

for: 5m
```

---

## Replica Failure

```yaml
alert: LonghornReplicaFailure

expr:
longhorn_volume_number_of_replicas
<
longhorn_volume_spec_number_of_replicas

for: 5m
```

---

## Longhorn Disk Usage Critical

```yaml
alert: LonghornDiskUsage90

expr:
longhorn_disk_usage_bytes
/
longhorn_disk_capacity_bytes
*100 >90

for:10m
```

---

# 🎯 Recommended Production Alert Set

Deploy first:

```text
✅ NodeDown
✅ NodeNotReady
✅ HighCPUUsage
✅ HighMemoryUsage
✅ DiskUsage80
✅ DiskUsage90
✅ PodCrashLoopBackOff
✅ PVCUsage80
✅ LonghornVolumeDegraded
✅ LonghornReplicaFailure
```

These cover roughly 90% of real homelab failures.

---

# 📱 Telegram Message Format

Example:

```text
🚨 CRITICAL

Cluster:
homelab-k3s

Alert:
LonghornReplicaFailure

Namespace:
longhorn-system

Description:
Volume replica count below expected value

Started:
2026-07-06 20:15

Status:
Active
```

---

# ✅ Validation Checklist

```text
✓ Azure Key Vault created
✓ Service Principal created
✓ Secrets stored in Key Vault
✓ External Secrets Operator installed
✓ ClusterSecretStore working
✓ ExternalSecret synced
✓ Alertmanager configured
✓ Telegram Bot working
✓ Test Alert received
✓ No secrets stored in GitHub
```

---

# 🔐 Security Best Practices

Never commit:

```text
azure-keyvault-auth.yaml
.env
passwords
tokens
certificates
private keys
```

Commit only:

```text
clustersecretstore.yaml
telegram-external-secret.yaml
PrometheusRule files
Alertmanager configuration
```

Everything stored in Git should be safe if the repository becomes public.

---

# 🎓 Learning Outcomes

After completing this phase you should understand:

✅ Azure Key Vault

✅ Service Principals

✅ External Secrets Operator

✅ ClusterSecretStore

✅ ExternalSecret

✅ Kubernetes Secret Synchronization

✅ Alertmanager

✅ Telegram Integration

✅ Infrastructure Alerting

✅ Kubernetes Alerting

✅ Longhorn Alerting

✅ Production Secret Management

✅ GitOps-Safe Secret Handling
