# 🚨 Alerting & Notifications
# Prometheus + Alertmanager + Telegram + Azure Key Vault

## Overview

This phase adds proactive monitoring and alerting to the Kubernetes homelab.

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
Alertmanager
Azure Key Vault
External Secrets Operator
Telegram Notifications
Custom Alert Rules
```

The goal is to automatically receive notifications when infrastructure, workloads, storage, or Kubernetes resources experience problems.

---

# Architecture

```text
Prometheus
      │
      ▼

PrometheusRule
      │
      ▼

Alertmanager
      │
      ▼

Kubernetes Secret
      │
      ▼

External Secrets Operator
      │
      ▼

Azure Key Vault
      │
      ▼

Telegram Bot
      │
      ▼

Telegram Notifications
```

---

# Goals

This setup provides:

✅ Node Monitoring

✅ Kubernetes Monitoring

✅ Longhorn Monitoring

✅ Storage Monitoring

✅ Telegram Notifications

✅ Secure Secret Management

✅ No Secrets Stored In Git

✅ Azure Key Vault Integration

✅ GitOps Friendly Configuration

---

# Prerequisites

The following components must already be deployed:

```text
K3s
MetalLB
Longhorn
Prometheus Stack
Grafana
External Secrets Operator
Azure Key Vault
```

Verify:

```bash
kubectl get nodes

kubectl get pods -n monitoring

kubectl get pods -n external-secrets-system

helm list -n monitoring
```

---

# Telegram Bot Creation

## Create Bot

Open Telegram.

Search:

```text
@BotFather
```

Create a bot:

```text
/newbot
```

Example:

```text
homelab-alert-bot
```

BotFather returns:

```text
123456789:AAxxxxxxxxxxxxxxxxxxxxxxxx
```

Save the token securely.

---

# Obtain Chat ID

Open your bot.

Send:

```text
/start
```

Send:

```text
hello
```

Retrieve updates:

```bash
curl \
"https://api.telegram.org/bot<TOKEN>/getUpdates"
```

Example:

```json
{
  "chat": {
    "id": 12345
  }
}
```

Save:

```text
123456
```

This is your Chat ID.

---

# Azure Key Vault

## Create Resource Group

```bash
az group create \
  --name rg-homelab \
  --location westeurope
```

---

## Create Key Vault

```bash
az keyvault create \
  --name kv-homelab \
  --resource-group rg-homelab \
  --location westeurope \
  --enable-rbac-authorization true
```

Verify:

```bash
az keyvault list -o table
```

---

# Store Telegram Secrets

Store Bot Token:

```bash
az keyvault secret set \
  --vault-name kv-homelab \
  --name telegram-bot-token \
  --value "<REAL_BOT_TOKEN>"
```

Store Chat ID:

```bash
az keyvault secret set \
  --vault-name kv-homelab \
  --name telegram-chat-id \
  --value "<CHAT_ID>"
```

Verify:

```bash
az keyvault secret list \
  --vault-name kv-homelab \
  -o table
```

Expected:

```text
telegram-bot-token
telegram-chat-id
```

---

# External Secrets Operator

## Create Azure Authentication Secret

File:

```text
azure-keyvault-auth.yaml
```

Do NOT commit.

```yaml
apiVersion: v1
kind: Secret

metadata:
  name: azure-keyvault-auth
  namespace: external-secrets-system

type: Opaque

stringData:
  ClientID: "<APP_ID>"
  ClientSecret: "<CLIENT_SECRET>"
```

Apply:

```bash
kubectl apply -f azure-keyvault-auth.yaml
```

---

# Create ClusterSecretStore

File:

```text
clustersecretstore.yaml
```

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore

metadata:
  name: azure-keyvault

spec:
  provider:
    azurekv:
      authType: ServicePrincipal

      tenantId: "<TENANT_ID>"

      vaultUrl: "https://kv-homelab.vault.azure.net"

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
READY=True
```

---

# Create Telegram External Secret

File:

```text
telegram-external-secret.yaml
```

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret

metadata:
  name: telegram-alerts
  namespace: monitoring

spec:
  refreshInterval: 24h

  secretStoreRef:
    name: azure-keyvault
    kind: ClusterSecretStore

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
kubectl apply \
-f telegram-external-secret.yaml
```

---

# Verify Secret Synchronization

Check:

```bash
kubectl get externalsecret \
-n monitoring
```

Expected:

```text
Ready=True
```

Verify secret:

```bash
kubectl get secret telegram-alerts \
-n monitoring
```

Inspect:

```bash
kubectl describe secret telegram-alerts \
-n monitoring
```

Expected:

```text
bot-token
chat-id
```

---

# Alertmanager Configuration

## values-alertmanager.yaml

File:

```text
values-alertmanager.yaml
```

```yaml
alertmanager:
  enabled: true

  alertmanagerSpec:

    secrets:
      - telegram-alerts

  config:

    global:
      resolve_timeout: 5m

    route:

      receiver: telegram

      group_by:
        - alertname

      group_wait: 30s

      group_interval: 5m

      repeat_interval: 12h

      routes:
        - matchers:
            - alertname="Watchdog"
          receiver: "null"

    receivers:

      - name: telegram

        telegram_configs:

          - api_url: https://api.telegram.org

            bot_token_file: /etc/alertmanager/secrets/telegram-alerts/bot-token

            chat_id: 12345

            send_resolved: true

            parse_mode: HTML

      - name: "null"
```

---

# Deploy Alertmanager Configuration

```bash
helm upgrade monitoring \
prometheus-community/kube-prometheus-stack \
-n monitoring \
-f values.yaml \
-f values-alertmanager.yaml
```

Verify:

```bash
helm get values monitoring \
-n monitoring
```

---

# Verify Alertmanager Configuration

```bash
kubectl exec -it \
-n monitoring \
alertmanager-monitoring-kube-prometheus-alertmanager-0 \
-- cat \
/etc/alertmanager/config_out/alertmanager.env.yaml
```

Expected:

```yaml
receiver: telegram
```

and

```yaml
telegram_configs:
```

---

# Verify Secret Mount

```bash
kubectl exec -it \
-n monitoring \
alertmanager-monitoring-kube-prometheus-alertmanager-0 \
-- ls \
/etc/alertmanager/secrets/telegram-alerts
```

Expected:

```text
bot-token
chat-id
```

---

# Prometheus Rules

PrometheusRule resources define firing conditions.

Structure:

```text
PrometheusRule
      │
      ▼

Group
      │
      ▼

Rule
      │
      ▼

Alert
```

---

# Node Alerts

File:

```text
prometheusrules/node-alerts.yaml
```

Monitors:

```text
Node Down
CPU Usage
Memory Usage
```

Examples:

```text
High CPU
High Memory
Node Down
```

---

# Kubernetes Alerts

File:

```text
prometheusrules/kubernetes-alerts.yaml
```

Monitors:

```text
CrashLoopBackOff
Deployments
Replicas
Pod Restarts
```

Examples:

```text
DeploymentUnavailable
PodCrashLoopBackOff
FrequentPodRestarts
```

---

# Storage Alerts

File:

```text
prometheusrules/storage-alerts.yaml
```

Monitors:

```text
PVC Usage
PVC Capacity
Pending Claims
```

Examples:

```text
PVCUsage80
PVCUsage90
PVCPending
```

---

# Longhorn Alerts

File:

```text
prometheusrules/longhorn-alerts.yaml
```

Monitors:

```text
Volume Health
Replica Health
Disk Capacity
```

Examples:

```text
LonghornVolumeDegraded
LonghornReplicaFailure
LonghornDiskPressure
```

---

# Deploy Prometheus Rules

Apply:

```bash
kubectl apply \
-f prometheusrules/node-alerts.yaml

kubectl apply \
-f prometheusrules/kubernetes-alerts.yaml

kubectl apply \
-f prometheusrules/storage-alerts.yaml

kubectl apply \
-f prometheusrules/longhorn-alerts.yaml
```

Verify:

```bash
kubectl get prometheusrule \
-n monitoring
```

---

# Test Alert

Create:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule

metadata:
  name: forced-alert
  namespace: monitoring

spec:
  groups:
    - name: forced-alert

      rules:

        - alert: ForcedTelegramAlert

          expr: vector(1)

          labels:
            severity: critical

          annotations:
            summary: Forced Telegram Alert

            description: Telegram integration works.
```

Apply:

```bash
kubectl apply \
-f forced-alert.yaml
```

---

# Verify In Prometheus

Open:

```text
Prometheus → Alerts
```

Search:

```text
ForcedTelegramAlert
```

Expected:

```text
FIRING
```

---

# Verify In Alertmanager

Open:

```text
Alertmanager → Alerts
```

Search:

```text
ForcedTelegramAlert
```

Expected:

```text
telegram receiver
```

---

# Example Telegram Notification

```text
🚨 CRITICAL ALERT

Alert:
NodeDown

Severity:
critical

Namespace:
monitoring

Description:
Node k3s-worker1 is unreachable.

Status:
firing
```

---

# Recommended Alerts

Deploy immediately:

```text
NodeDown
HighCPUUsage
HighMemoryUsage
PVCUsage80
PVCUsage90
PVCPending
PodCrashLoopBackOff
DeploymentUnavailable
LonghornVolumeDegraded
LonghornReplicaFailure
```

These alerts cover most real-world homelab failures.

---

# Useful Commands

## Alertmanager Logs

```bash
kubectl logs \
-n monitoring \
alertmanager-monitoring-kube-prometheus-alertmanager-0
```

---

## Operator Logs

```bash
kubectl logs \
-n monitoring \
deployment/monitoring-kube-prometheus-operator
```

---

## Alertmanager Configuration

```bash
kubectl exec -it \
-n monitoring \
alertmanager-monitoring-kube-prometheus-alertmanager-0 \
-- cat \

