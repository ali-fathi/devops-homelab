# 📜 Phase 5 – Centralized Logging with Loki + Grafana Alloy

This phase adds centralized logging and log-based alerting to the DevOps Homelab Kubernetes platform.

Promtail has been replaced with **Grafana Alloy** because Promtail is EOL as of **March 2, 2026**, and Grafana states that future development for this log collection path continues in Grafana Alloy. [1](https://azure.microsoft.com/en-us/pricing/details/key-vault/)

Before this phase, the platform already includes:

```text
K3s
MetalLB
Longhorn
Prometheus
Grafana
Alertmanager
Telegram Alerts
Azure Key Vault
External Secrets Operator
```

After this phase, the platform also includes:

```text
Loki
Grafana Alloy
Grafana Log Explorer
Centralized Kubernetes Logs
LogQL Querying
Log Retention
Loki Ruler
Log-Based Alerts
Telegram Notifications from Logs
```

---

# 🎯 Goal

The goal of this phase is to collect logs from Kubernetes workloads, make those logs searchable in Grafana, and trigger useful Telegram alerts when important log patterns appear.

Metrics answer:

```text
What is broken?
```

Logs answer:

```text
Why is it broken?
```

Log-based alerts answer:

```text
Something important appeared in logs and needs attention now.
```

Loki supports alerting and recording rules through its Ruler component, which evaluates LogQL queries and can send alerts to Alertmanager. [2](https://www.suse.com/c/grafana-alloy-part-1-replacing-promtail/)[3](https://grafana.com/docs/loki/latest/alert/)

---

# 🧠 What Is Loki?

Loki is a log aggregation system from Grafana Labs.

It is often described as:

```text
Prometheus for logs
```

Unlike traditional full-text logging systems, Loki indexes labels such as:

```text
namespace
pod
container
node_name
app
```

Loki stores compressed log content and indexes metadata labels, which makes it lighter than full-text indexed logging systems. [4](https://github.com/grafana/alloy-scenarios/tree/main/k8s/logs)[5](https://grafana.com/docs/alloy/latest/collect/logs-in-kubernetes/)

---

# 🧠 What Is Grafana Alloy?

Grafana Alloy is Grafana’s telemetry collector.

In this phase, Alloy replaces Promtail and is responsible for collecting Kubernetes logs and forwarding those logs to Loki.

Grafana Alloy can collect Kubernetes pod logs using `loki.source.kubernetes`, which tails logs from Kubernetes containers through the Kubernetes API. [6](https://dev.to/seewhy/using-helm-chart-to-deploy-grafana-prometheus-and-loki-data-source-on-your-kubernetes-cluster-1287)

Grafana Alloy can forward collected logs to Loki using `loki.write`, and Grafana documents this as part of the Kubernetes logs collection workflow. [7](https://github.com/grafana/helm-charts/blob/main/charts/promtail/README.md)

---

# 🧠 Why Replace Promtail?

Promtail is EOL as of March 2, 2026.

Promtail should be replaced with Grafana Alloy or another supported log collector. [1](https://azure.microsoft.com/en-us/pricing/details/key-vault/)

The new logging pipeline becomes:

```text
Old:
Kubernetes Pods
  ↓
Promtail
  ↓
Loki

New:
Kubernetes Pods
  ↓
Grafana Alloy
  ↓
Loki
```

---

# 🧠 What Is LogQL?

LogQL is the query language used by Loki.

Example:

```logql
{namespace="monitoring"} |= "error"
```

This means:

```text
Show logs from namespace monitoring that contain the word error.
```

---

# 🧠 What Is Loki Ruler?

Loki Ruler evaluates LogQL alerting rules on a schedule.

It can create:

```text
Recording Rules
Alerting Rules
```

Alerting rules can be sent to Alertmanager, and Alertmanager can forward those alerts to Telegram.

---

# 🏗️ Architecture

## Logging Pipeline

```text
Kubernetes Pods
      │
      ▼
Grafana Alloy
      │
      ▼
Loki Gateway
      │
      ▼
Loki
      │
      ▼
Grafana Explore
```

## Log-Based Alerting Pipeline

```text
Kubernetes Logs
      │
      ▼
Grafana Alloy
      │
      ▼
Loki
      │
      ▼
Loki Ruler
      │
      ▼
Alertmanager
      │
      ▼
Telegram
```

---

# 🧩 Components

## Loki

Responsible for:

```text
Receiving logs
Storing logs
Indexing labels
Running LogQL queries
Applying retention
Evaluating log alert rules
Sending log alerts to Alertmanager
```

---

## Grafana Alloy

Responsible for:

```text
Discovering Kubernetes Pods
Collecting Pod logs
Adding useful labels
Processing log entries
Forwarding logs to Loki
```

---

## Grafana

Responsible for:

```text
Querying Loki
Displaying logs
Filtering logs
Correlating metrics and logs
Exploring errors
```

---

## Alertmanager

Responsible for:

```text
Receiving alerts from Prometheus
Receiving alerts from Loki Ruler
Grouping alerts
Deduplicating alerts
Sending Telegram notifications
```

---

# ✅ Why This Phase Is Important

With this phase, troubleshooting becomes much easier.

Examples:

```text
Why is Harbor not starting?
Why did Forgejo crash?
Why did Longhorn report an error?
Why did ArgoCD fail to sync?
Why did Prometheus restart?
What happened before the alert fired?
Which pod generated the error?
Which namespace is noisy?
```

After Loki and Alloy are deployed, logs from Kubernetes workloads can be searched from Grafana.

After Loki alerting is configured, important log patterns can trigger Telegram messages.

---

# 📍 Current Homelab Platform State

Current infrastructure services:

```text
192.168.178.210 → Traefik
192.168.178.211 → Longhorn UI
192.168.178.212 → Grafana
```

Loki should normally remain internal.

Grafana is already exposed through MetalLB:

```text
http://192.168.178.212
```

Loki does not need a MetalLB IP because Grafana reaches Loki internally through Kubernetes DNS.

Recommended access model:

```text
User
  ↓
Grafana LoadBalancer
  ↓
Grafana Loki Datasource
  ↓
Loki internal service
```

---

# 📂 Repository Structure

Use this folder structure:

```text
kubernetes/
└── observability/
    └── logging/
        ├── README.md
        ├── loki-values.yaml
        ├── alloy-values.yaml
        ├── grafana-loki-datasource.yaml
        ├── loki-log-alert-rules.yaml
        └── queries-cheatsheet.md
```

Create the directory:

```bash
mkdir -p kubernetes/observability/logging
cd kubernetes/observability/logging
```

---

# ✅ Prerequisites

Before installing Loki and Alloy, verify:

```text
K3s is healthy
Longhorn is healthy
Grafana is running
Prometheus is running
Alertmanager is running
Telegram alerting works
DNS works inside the cluster
MetalLB is working
```

---

## Verify Nodes

```bash
kubectl get nodes
```

Expected:

```text
k3s-master    Ready
k3s-worker1   Ready
k3s-worker2   Ready
```

---

## Verify DNS

```bash
kubectl run netshoot \
  --image=nicolaka/netshoot \
  -it --rm --restart=Never -- bash
```

Inside the pod:

```bash
nslookup kubernetes.default.svc.cluster.local
```

Expected:

```text
Name: kubernetes.default.svc.cluster.local
Address: 10.43.0.1
```

Exit:

```bash
exit
```

Delete the test pod if needed:

```bash
kubectl delete pod netshoot
```

---

## Verify Longhorn

```bash
kubectl get pods -n longhorn-system
```

Expected:

```text
longhorn-manager       Running
longhorn-csi-plugin    Running
longhorn-ui            Running
```

Check StorageClass:

```bash
kubectl get storageclass
```

Expected:

```text
longhorn
```

---

## Verify Grafana

```bash
kubectl get pods -n monitoring | grep grafana
```

Expected:

```text
monitoring-grafana   Running
```

Access Grafana:

```text
http://192.168.178.212
```

---

## Verify Alertmanager

```bash
kubectl get pods -n monitoring | grep alertmanager
```

Expected:

```text
alertmanager-monitoring-kube-prometheus-alertmanager-0   Running
```

---

# 🚀 Step 1 – Add Grafana Helm Repository

Add the Grafana Helm repository:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
```

Update repositories:

```bash
helm repo update
```

Verify Loki chart is available:

```bash
helm search repo grafana/loki
```

Verify Alloy chart is available:

```bash
helm search repo grafana/alloy
```

---

# 🚀 Step 2 – Create Logging Namespace

```bash
kubectl create namespace logging
```

Verify:

```bash
kubectl get namespace logging
```

---

# 🚀 Step 3 – Remove Promtail If Already Installed

If Promtail was previously installed, remove it to avoid duplicate logs.

```bash
helm uninstall promtail -n logging
```

Verify Promtail is gone:

```bash
kubectl get pods -n logging | grep promtail
```

Expected:

```text
# no output
```

Do not run Promtail and Alloy together long-term because duplicate collectors can ship duplicate log entries to Loki.

---

# 🚀 Step 4 – Create Loki Values File

Create:

```bash
nano loki-values.yaml
```

Content:

```yaml
deploymentMode: SingleBinary

loki:
  auth_enabled: false

  commonConfig:
    replication_factor: 1

  storage:
    type: filesystem

    bucketNames:
      chunks: loki-chunks
      ruler: loki-ruler
      admin: loki-admin

  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h

  limits_config:
    retention_period: 720h
    reject_old_samples: true
    reject_old_samples_max_age: 168h

  compactor:
    retention_enabled: true
    delete_request_store: filesystem

  rulerConfig:
    enable_api: true
    enable_alertmanager_v2: true

    alertmanager_url: http://monitoring-kube-prometheus-alertmanager.monitoring.svc.cluster.local:9093

    evaluation_interval: 1m

    storage:
      type: local
      local:
        directory: /var/loki/rules

    rule_path: /tmp/loki-rules

    ring:
      kvstore:
        store: inmemory

singleBinary:
  replicas: 1

  persistence:
    enabled: true
    storageClass: longhorn
    size: 20Gi

  extraVolumes:
    - name: loki-alert-rules
      configMap:
        name: loki-log-alert-rules

  extraVolumeMounts:
    - name: loki-alert-rules
      mountPath: /var/loki/rules/fake
      readOnly: true

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi

gateway:
  enabled: true

read:
  replicas: 0

write:
  replicas: 0

backend:
  replicas: 0

chunksCache:
  enabled: false

resultsCache:
  enabled: false

monitoring:
  serviceMonitor:
    enabled: true

test:
  enabled: false
```

---

# 🧠 Loki Values Explanation

## SingleBinary Mode

```yaml
deploymentMode: SingleBinary
```

This runs Loki as a single application.

This is ideal for a homelab because it is:

```text
Simple
Lightweight
Easy to operate
Easy to troubleshoot
```

---

## No Authentication

```yaml
auth_enabled: false
```

Authentication is disabled because Loki remains internal to the Kubernetes cluster.

Grafana is the user-facing interface.

---

## Filesystem Storage

```yaml
storage:
  type: filesystem
```

Logs are stored on a Loki filesystem volume.

For this homelab, the filesystem volume is backed by Longhorn.

---

## Longhorn Persistence

```yaml
storageClass: longhorn
size: 20Gi
```

This creates a Longhorn-backed PVC for Loki.

Without persistence:

```text
Loki pod deleted
    ↓
Logs lost
```

With Longhorn:

```text
Loki pod deleted
    ↓
Loki pod recreated
    ↓
Logs still available
```

---

## Retention

```yaml
retention_period: 720h
```

This keeps logs for:

```text
30 days
```

---

## Gateway

```yaml
gateway:
  enabled: true
```

The Loki Gateway provides a stable internal endpoint:

```text
http://loki-gateway.logging.svc.cluster.local
```

Grafana and Alloy use this endpoint.

---

## Ruler

```yaml
rulerConfig:
  enable_api: true
  enable_alertmanager_v2: true
```

This enables Loki alerting rules.

The Loki Ruler evaluates LogQL rules and sends alerts to Alertmanager.

---

## Alertmanager URL

```yaml
alertmanager_url: http://monitoring-kube-prometheus-alertmanager.monitoring.svc.cluster.local:9093
```

This tells Loki where to send log-based alerts.

---

## Rules Mount

```yaml
extraVolumes:
  - name: loki-alert-rules
    configMap:
      name: loki-log-alert-rules
```

This mounts the log alert rules into the Loki container.

The mount path uses:

```text
/var/loki/rules/fake
```

because `auth_enabled: false` means Loki uses the `fake` tenant for rules.

---

# 🚀 Step 5 – Create Loki Log Alert Rules

Create:

```bash
nano loki-log-alert-rules.yaml
```

Content:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-log-alert-rules
  namespace: logging

data:
  log-alerts.yaml: |
    groups:
      - name: log-alerts
        interval: 1m

        rules:

          - alert: LokiCriticalLogsDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace!=""}
                  |~ "(?i)critical|fatal|panic|segmentation fault|segfault"
                  [5m]
                )
              ) > 0
            for: 1m
            labels:
              severity: critical
              source: loki
              category: logs
            annotations:
              summary: "Critical log detected"
              description: "Critical/fatal/panic log detected in namespace={{ $labels.namespace }}, pod={{ $labels.pod }}, container={{ $labels.container }}."

          - alert: LokiRealErrorLevelLogsDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace!=""}
                  |~ "(?i)level=error|level=\"error\"|severity=error|severity=\"error\"|level=err|level=\"err\""
                  [5m]
                )
              ) > 0
            for: 2m
            labels:
              severity: error
              source: loki
              category: logs
            annotations:
              summary: "Real error-level log detected"
              description: "A real error-level log was detected in namespace={{ $labels.namespace }}, pod={{ $labels.pod }}, container={{ $labels.container }}."

          - alert: LokiErrorBurstDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace!=""}
                  |~ "(?i)error|exception|failed|failure"
                  !~ "level=info"
                  !~ "msg=\"Request Completed\""
                  !~ "plugins.update.checker"
                  !~ "flag evaluation succeeded"
                  [10m]
                )
              ) > 15
            for: 5m
            labels:
              severity: error
              source: loki
              category: logs
            annotations:
              summary: "Error burst detected"
              description: "More than 15 error-related log entries detected in namespace={{ $labels.namespace }}, pod={{ $labels.pod }}, container={{ $labels.container }} during the last 10 minutes."

          - alert: LokiTimeoutBurstDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace!=""}
                  |~ "(?i)timeout|timed out|deadline exceeded|context deadline exceeded"
                  !~ "level=info"
                  [10m]
                )
              ) > 5
            for: 5m
            labels:
              severity: error
              source: loki
              category: logs
            annotations:
              summary: "Timeout burst detected"
              description: "More than 5 timeout-related log entries detected in namespace={{ $labels.namespace }}, pod={{ $labels.pod }}, container={{ $labels.container }} during the last 10 minutes."

          - alert: LokiLonghornCriticalLogsDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace="longhorn-system"}
                  |~ "(?i)degraded|faulted|replica failed|replica failure|volume .* faulted|volume .* degraded|failed to attach|failed to detach|disk pressure|no available disk|insufficient storage"
                  [5m]
                )
              ) > 0
            for: 1m
            labels:
              severity: critical
              source: loki
              component: longhorn
              category: storage
            annotations:
              summary: "Critical Longhorn log detected"
              description: "Critical Longhorn storage log detected in pod={{ $labels.pod }}, container={{ $labels.container }}."

          - alert: LokiLonghornErrorBurstDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace="longhorn-system"}
                  |~ "(?i)error|failed|failure|timeout"
                  !~ "level=info"
                  [10m]
                )
              ) > 10
            for: 5m
            labels:
              severity: error
              source: loki
              component: longhorn
              category: storage
            annotations:
              summary: "Longhorn error burst detected"
              description: "More than 10 Longhorn error-related logs detected in pod={{ $labels.pod }}, container={{ $labels.container }} during the last 10 minutes."

          - alert: LokiMonitoringStackErrorBurstDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace="monitoring", pod!~".*grafana.*"}
                  |~ "(?i)error|failed|failure|panic|exception|timeout"
                  !~ "level=info"
                  [10m]
                )
              ) > 10
            for: 5m
            labels:
              severity: error
              source: loki
              component: monitoring
              category: observability
            annotations:
              summary: "Monitoring stack error burst detected"
              description: "More than 10 monitoring stack error-related logs detected in pod={{ $labels.pod }}, container={{ $labels.container }} during the last 10 minutes."

          - alert: LokiGrafanaCriticalLogsDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace="monitoring", pod=~".*grafana.*"}
                  | logfmt
                  | level=~"error|fatal|panic"
                  [5m]
                )
              ) > 0
            for: 1m
            labels:
              severity: critical
              source: loki
              component: grafana
              category: observability
            annotations:
              summary: "Critical Grafana log detected"
