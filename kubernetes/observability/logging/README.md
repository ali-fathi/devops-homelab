# 📜 Phase 5 – Centralized Logging with Loki + Promtail

This phase adds centralized logging and log-based alerting to the DevOps Homelab Kubernetes platform.

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
Promtail
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

The goal of this phase is to collect logs from all Kubernetes workloads, make them searchable in Grafana, and optionally trigger alerts when important log patterns appear.

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
Something important appeared in the logs and needs attention now.
```

Loki is designed for log aggregation and supports alerting and recording rules through its ruler component. [1](https://oneuptime.com/blog/post/2026-02-09-external-secrets-operator-azure-key-vault/view)

---

# 🧠 What Is Loki?

Loki is a log aggregation system from Grafana Labs.

It is often described as:

```text
Prometheus for logs
```

Unlike Elasticsearch, Loki does not index every word in every log line. Instead, Loki indexes labels such as:

```text
namespace
pod
container
node_name
app
```

This makes Loki lighter and cheaper to operate than traditional full-text indexed logging systems. Loki is commonly used in Kubernetes environments because it indexes metadata labels and stores compressed log content. [2](https://computingforgeeks.com/deploy-loki-kubernetes/)[3](https://dasroot.net/posts/2026/04/observability-stack-prometheus-grafana-loki/)

---

# 🧠 What Is Promtail?

Promtail is a log shipping agent.

Promtail runs on every Kubernetes node as a DaemonSet and collects logs from Kubernetes log paths such as:

```text
/var/log/pods/
/var/log/containers/
```

Promtail then adds Kubernetes metadata such as namespace, pod, container, and node labels before sending logs to Loki. Promtail commonly runs as a DaemonSet for cluster-wide log collection from every node. [4](https://github.com/grafana/helm-charts/blob/main/charts/promtail/README.md)[5](https://deepwiki.com/grafana/helm-charts/3.2-loki-stack)

> Note: The Promtail Helm chart is marked as deprecated upstream. It is still useful for learning and existing deployments, but a future migration to Grafana Alloy should be considered. [4](https://github.com/grafana/helm-charts/blob/main/charts/promtail/README.md)[5](https://deepwiki.com/grafana/helm-charts/3.2-loki-stack)

---

# 🧠 What Is LogQL?

LogQL is the query language used by Loki.

It is similar in style to PromQL but is used for logs.

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

Loki Ruler evaluates LogQL rules periodically.

It can create:

```text
Recording Rules
Alerting Rules
```

Alerting rules can send alerts to Alertmanager, and Alertmanager can forward those alerts to Telegram. Loki’s ruler is responsible for continually evaluating configured LogQL queries and firing alerts when conditions are met. [1](https://oneuptime.com/blog/post/2026-02-09-external-secrets-operator-azure-key-vault/view)[6](https://medium.com/@ma.ki.rlene/how-to-use-external-secrets-operator-with-aks-and-azure-key-vault-9c4c093052fe)

---

# 🏗️ Architecture

```text
Kubernetes Pods
      │
      ▼
Container Log Files
      │
      ▼
Promtail DaemonSet
      │
      ▼
Loki
      │
      ▼
Grafana
      │
      ▼
Explore Logs with LogQL
```

With log-based alerting:

```text
Kubernetes Logs
      │
      ▼
Promtail
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

## Promtail

Responsible for:

```text
Reading pod logs
Adding Kubernetes labels
Tracking log positions
Shipping logs to Loki
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

# ✅ Why This Is Important

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

After Loki is deployed, all of those questions can be investigated from Grafana.

After Loki alerting is configured, important log patterns can immediately notify Telegram.

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

Loki does not need a MetalLB IP because Grafana can reach Loki internally through Kubernetes service DNS.

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

Create the following folder structure:

```text
kubernetes/
└── observability/
    └── logging/
        ├── README.md
        ├── loki-values.yaml
        ├── promtail-values.yaml
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

Before installing Loki and Promtail, verify:

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

Verify Promtail chart is available:

```bash
helm search repo grafana/promtail
```

Grafana provides Helm charts for Loki and Promtail through the Grafana Helm repository. [4](https://github.com/grafana/helm-charts/blob/main/charts/promtail/README.md)[7](https://github.com/grafana/helm-charts/blob/main/charts/loki-stack/README.md)

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

# 🚀 Step 3 – Create Loki Values File

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

  ruler:
    enable_api: true

    storage:
      type: local
      local:
        directory: /var/loki/rules

    rule_path: /tmp/loki-rules

    alertmanager_url: http://monitoring-kube-prometheus-alertmanager.monitoring.svc.cluster.local:9093

    ring:
      kvstore:
        store: inmemory

    evaluation_interval: 1m

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

Grafana documents monolithic Loki as suitable for smaller meta-monitoring stacks, while microservices mode is recommended for larger production environments. [8](https://grafana.com/docs/loki/latest/setup/install/helm/)

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

This is a good starting point for a homelab.

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

Grafana and Promtail use this endpoint.

---

## Ruler

```yaml
ruler:
  enable_api: true
```

This enables Loki alerting rules.

The Loki ruler evaluates LogQL rules and sends alerts to Alertmanager. [1](https://oneuptime.com/blog/post/2026-02-09-external-secrets-operator-azure-key-vault/view)[9](https://azure.microsoft.com/en-us/pricing/details/key-vault/)

---

## Alertmanager URL

```yaml
alertmanager_url: http://monitoring-kube-prometheus-alertmanager.monitoring.svc.cluster.local:9093
```

This tells Loki where to send firing log-based alerts.

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

# 🚀 Step 4 – Create Loki Log Alert Rules

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

          - alert: LokiErrorLogsDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace!=""}
                  |= "error"
                  [5m]
                )
              ) > 0
            for: 1m
            labels:
              severity: warning
              source: loki
            annotations:
              summary: "Error log detected"
              description: "Error log detected in namespace={{ $labels.namespace }}, pod={{ $labels.pod }}, container={{ $labels.container }}."

          - alert: LokiExceptionLogsDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace!=""}
                  |~ "(?i)exception"
                  [5m]
                )
              ) > 0
            for: 1m
            labels:
              severity: warning
              source: loki
            annotations:
              summary: "Exception log detected"
              description: "Exception log detected in namespace={{ $labels.namespace }}, pod={{ $labels.pod }}, container={{ $labels.container }}."

          - alert: LokiFailedLogsDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace!=""}
                  |~ "(?i)failed|failure"
                  [5m]
                )
              ) > 3
            for: 2m
            labels:
              severity: warning
              source: loki
            annotations:
              summary: "Repeated failure logs detected"
              description: "More than 3 failure-related log entries detected in namespace={{ $labels.namespace }}, pod={{ $labels.pod }}, container={{ $labels.container }}."

          - alert: LokiTimeoutLogsDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace!=""}
                  |~ "(?i)timeout|timed out"
                  [5m]
                )
              ) > 0
            for: 1m
            labels:
              severity: warning
              source: loki
            annotations:
              summary: "Timeout log detected"
              description: "Timeout log detected in namespace={{ $labels.namespace }}, pod={{ $labels.pod }}, container={{ $labels.container }}."

          - alert: LokiCriticalLogsDetected
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace!=""}
                  |~ "(?i)critical|fatal|panic"
                  [5m]
                )
              ) > 0
            for: 1m
            labels:
              severity: critical
              source: loki
            annotations:
              summary: "Critical log detected"
              description: "Critical/fatal/panic log detected in namespace={{ $labels.namespace }}, pod={{ $labels.pod }}, container={{ $labels.container }}."

          - alert: LokiLonghornErrorLogs
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace="longhorn-system"}
                  |~ "(?i)error|failed|degraded|replica"
                  [5m]
                )
              ) > 0
            for: 1m
            labels:
              severity: critical
              source: loki
              component: longhorn
            annotations:
              summary: "Longhorn error log detected"
              description: "Longhorn-related error log detected in pod={{ $labels.pod }}, container={{ $labels.container }}."

          - alert: LokiMonitoringStackErrors
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace="monitoring"}
                  |~ "(?i)error|failed|panic|exception"
                  [5m]
                )
              ) > 0
            for: 1m
            labels:
              severity: warning
              source: loki
              component: monitoring
            annotations:
              summary: "Monitoring stack error log detected"
              description: "Monitoring stack error detected in pod={{ $labels.pod }}, container={{ $labels.container }}."

          - alert: LokiLoggingStackErrors
            expr: |
              sum by (namespace, pod, container) (
                count_over_time(
                  {namespace="logging"}
                  |~ "(?i)error|failed|panic|exception"
                  [5m]
                )
              ) > 0
            for: 1m
            labels:
              severity: warning
              source: loki
              component: logging
            annotations:
              summary: "Logging stack error log detected"
              description: "Logging stack error detected in pod={{ $labels.pod }}, container={{ $labels.container }}."
```

Apply:

```bash
kubectl apply -f loki-log-alert-rules.yaml
```

Verify:

```bash
kubectl get configmap -n logging loki-log-alert-rules
```

---

# 🚀 Step 5 – Install Loki

From the logging folder:

```bash
helm install loki \
grafana/loki \
-n logging \
-f loki-values.yaml
```

Watch pods:

```bash
kubectl get pods -n logging -w
```

Expected:

```text
loki-0              Running
loki-gateway-xxxxx  Running
```

If Loki is already installed, upgrade instead:

```bash
helm upgrade loki \
grafana/loki \
-n logging \
-f loki-values.yaml
```

---

# 🚀 Step 6 – Verify Loki PVC

```bash
kubectl get pvc -n logging
```

Expected:

```text
storage-loki-0   Bound   20Gi   longhorn
```

If the PVC is Pending:

```bash
kubectl describe pvc -n logging
```

Check Longhorn:

```bash
kubectl get pods -n longhorn-system
```

---

# 🚀 Step 7 – Verify Loki Services

```bash
kubectl get svc -n logging
```

Expected services include:

```text
loki
loki-gateway
```

---

# 🚀 Step 8 – Test Loki Internally

Create a temporary curl pod:

```bash
kubectl run curl-test \
  --image=curlimages/curl \
  -n logging \
  -it --rm --restart=Never -- sh
```

Inside the pod:

```bash
curl http://loki-gateway.logging.svc.cluster.local/ready
```

Expected:

```text
ready
```

Exit the pod:

```bash
exit
```

---

# 🚀 Step 9 – Verify Rule File Is Mounted

```bash
kubectl exec -it -n logging loki-0 -- sh
```

Inside:

```bash
ls -lah /var/loki/rules/fake
```

Expected:

```text
log-alerts.yaml
```

Check content:

```bash
cat /var/loki/rules/fake/log-alerts.yaml
```

Exit:

```bash
exit
```

---

# 🚀 Step 10 – Verify Loki Ruler Logs

```bash
kubectl logs -n logging loki-0 | grep -i ruler
```

Check for errors:

```bash
kubectl logs -n logging loki-0 | grep -i error
```

Check Alertmanager connectivity:

```bash
kubectl logs -n logging loki-0 | grep -i alertmanager
```

---

# 🚀 Step 11 – Create Promtail Values File

Create:

```bash
nano promtail-values.yaml
```

Content:

```yaml
config:
  clients:
    - url: http://loki-gateway.logging.svc.cluster.local/loki/api/v1/push

  snippets:
    pipelineStages:
      - cri: {}

    extraRelabelConfigs:
      - source_labels:
          - __meta_kubernetes_pod_node_name
        target_label: node_name

      - source_labels:
          - __meta_kubernetes_namespace
        target_label: namespace

      - source_labels:
          - __meta_kubernetes_pod_name
        target_label: pod

      - source_labels:
          - __meta_kubernetes_pod_container_name
        target_label: container

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 300m
    memory: 256Mi

serviceMonitor:
  enabled: true
```

---

# 🧠 Promtail Values Explanation

## Loki Client URL

```yaml
url: http://loki-gateway.logging.svc.cluster.local/loki/api/v1/push
```

Promtail sends logs to Loki using this endpoint.

---

## CRI Pipeline Stage

```yaml
pipelineStages:
  - cri: {}
```

This parses Kubernetes container runtime logs.

---

## Labels

Promtail adds labels:

```text
node_name
namespace
pod
container
```

These labels make Grafana LogQL queries much easier.

Example:

```logql
{namespace="monitoring", container="grafana"}
```

---

## Resource Limits

Promtail is lightweight.

Initial settings:

```text
CPU request: 50m
Memory request: 64Mi
CPU limit: 300m
Memory limit: 256Mi
```

---

# 🚀 Step 12 – Install Promtail

```bash
helm install promtail \
grafana/promtail \
-n logging \
-f promtail-values.yaml
```

If Promtail is already installed, upgrade instead:

```bash
helm upgrade promtail \
grafana/promtail \
-n logging \
-f promtail-values.yaml
```

Verify:

```bash
kubectl get pods -n logging
```

Expected:

```text
promtail-xxxxx   Running
promtail-yyyyy   Running
promtail-zzzzz   Running
```

You should have one Promtail pod per Kubernetes node.

Check DaemonSet:

```bash
kubectl get daemonset -n logging
```

Expected:

```text
promtail   DESIRED 3   READY 3
```

---

# 🚀 Step 13 – Verify Promtail Logs

```bash
kubectl logs -n logging daemonset/promtail
```

You should see output showing Promtail starting and pushing logs to Loki.

If needed, check one pod:

```bash
kubectl get pods -n logging -l app.kubernetes.io/name=promtail
```

Then:

```bash
kubectl logs -n logging <promtail-pod-name>
```

---

# 🚀 Step 14 – Add Loki Datasource to Grafana Manually

Open Grafana:

```text
http://192.168.178.212
```

Go to:

```text
Connections
  → Data sources
  → Add data source
  → Loki
```

Configure:

```text
Name: Loki
URL: http://loki-gateway.logging.svc.cluster.local
Access: Server / Proxy
```

Click:

```text
Save & test
```

Expected:

```text
Successfully queried the Loki API
```

---

# 🚀 Step 15 – Add Loki Datasource with GitOps-Friendly ConfigMap

If Grafana is configured with the datasource sidecar, create the datasource as a ConfigMap.

Create:

```bash
nano grafana-loki-datasource.yaml
```

Content:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-loki-datasource
  namespace: monitoring
  labels:
    grafana_datasource: "1"

data:
  loki-datasource.yaml: |
    apiVersion: 1

    datasources:
      - name: Loki
        type: loki
        access: proxy
        url: http://loki-gateway.logging.svc.cluster.local
        isDefault: false
        editable: true
```

Apply:

```bash
kubectl apply -f grafana-loki-datasource.yaml
```

Restart Grafana if the datasource does not appear:

```bash
kubectl rollout restart deployment monitoring-grafana -n monitoring
```

---

# 🚀 Step 16 – Verify Logs in Grafana

Open Grafana:

```text
http://192.168.178.212
```

Go to:

```text
Explore
```

Select datasource:

```text
Loki
```

Run:

```logql
{namespace="monitoring"}
```

Expected logs from:

```text
Grafana
Prometheus
Alertmanager
```

---

# 🚨 Log-Based Alerting

Log-based alerting allows Telegram notifications when important log patterns appear.

Example:

```text
A pod logs "fatal error"
      ↓
Promtail ships log to Loki
      ↓
Loki Ruler evaluates LogQL rule
      ↓
Loki sends alert to Alertmanager
      ↓
Alertmanager sends Telegram notification
```

---

# 🚨 Test Log-Based Alert

Create a pod that logs an error:

```bash
kubectl run loki-error-test \
  --image=busybox:1.36 \
  --restart=Never \
  -- sh -c 'echo "error: this is a Loki alert test"; sleep 300'
```

Check the log:

```bash
kubectl logs loki-error-test
```

Expected:

```text
error: this is a Loki alert test
```

Wait 1–2 minutes.

---

## Check Grafana Explore

Run:

```logql
{pod="loki-error-test"}
```

Then:

```logql
{pod="loki-error-test"} |= "error"
```

---

## Check Alertmanager

Open Alertmanager UI or port-forward:

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093
```

Open:

```text
http://localhost:9093
```

Look for:

```text
LokiErrorLogsDetected
```

---

## Check Telegram

Expected Telegram notification:

```text
LokiErrorLogsDetected

Error log detected in namespace=default, pod=loki-error-test, container=loki-error-test.
```

---

## Cleanup Test Pod

```bash
kubectl delete pod loki-error-test
```

---

# LogQL Query Examples

## All Logs

```logql
{}
```

---

## Monitoring Namespace

```logql
{namespace="monitoring"}
```

---

## Longhorn Logs

```logql
{namespace="longhorn-system"}
```

---

## Logging Stack Logs

```logql
{namespace="logging"}
```

---

## Errors Across All Namespaces

```logql
{} |= "error"
```

---

## Warnings Across All Namespaces

```logql
{} |= "warn"
```

---

## Grafana Logs

```logql
{namespace="monitoring", pod=~".*grafana.*"}
```

---

## Prometheus Logs

```logql
{namespace="monitoring", pod=~".*prometheus.*"}
```

---

## Alertmanager Logs

```logql
{namespace="monitoring", pod=~".*alertmanager.*"}
```

---

## Longhorn Errors

```logql
{namespace="longhorn-system"} |= "error"
```

---

## CrashLoopBackOff Messages

```logql
{} |= "CrashLoopBackOff"
```

---

## OOM Messages

```logql
{} |= "OOM"
```

---

## Timeout Messages

```logql
{} |= "timeout"
```

---

## Failed Messages

```logql
{} |= "failed"
```

---

## Logs From One Node

```logql
{node_name="k3s-worker1"}
```

---

## Logs From One Pod

```logql
{pod="POD_NAME"}
```

---

## Logs From One Container

```logql
{container="grafana"}
```

---

## Count Errors Over Time

```logql
sum by(namespace) (
  count_over_time({namespace!=""} |= "error" [5m])
)
```

---

# Create `queries-cheatsheet.md`

Create:

```bash
nano queries-cheatsheet.md
```

Content:

```markdown
# Loki LogQL Cheatsheet

## All logs

```logql
{}
```

## Namespace logs

```logql
{namespace="monitoring"}
```

## Longhorn logs

```logql
{namespace="longhorn-system"}
```

## Logging stack logs

```logql
{namespace="logging"}
```

## Errors

```logql
{} |= "error"
```

## Warnings

```logql
{} |= "warn"
```

## Failed messages

```logql
{} |= "failed"
```

## Timeout messages

```logql
{} |= "timeout"
```

## OOM messages

```logql
{} |= "OOM"
```

## CrashLoopBackOff messages

```logql
{} |= "CrashLoopBackOff"
```

## Grafana logs

```logql
{pod=~".*grafana.*"}
```

## Prometheus logs

```logql
{pod=~".*prometheus.*"}
```

## Alertmanager logs

```logql
{pod=~".*alertmanager.*"}
```

## Logs from one node

```logql
{node_name="k3s-worker1"}
```

## Logs from one pod

```logql
{pod="POD_NAME"}
```

## Error count over 5 minutes

```logql
sum by(namespace) (
  count_over_time({namespace!=""} |= "error" [5m])
)
```
```

---

# Operational Commands

## Check Loki Pods

```bash
kubectl get pods -n logging
```

---

## Check Loki PVC

```bash
kubectl get pvc -n logging
```

---

## Check Loki Services

```bash
kubectl get svc -n logging
```

---

## Check Promtail DaemonSet

```bash
kubectl get daemonset -n logging
```

---

## Check Promtail Logs

```bash
kubectl logs -n logging daemonset/promtail
```

---

## Check Loki Logs

```bash
kubectl logs -n logging statefulset/loki
```

---

## Check Ruler Logs

```bash
kubectl logs -n logging loki-0 | grep -i ruler
```

---

## Check Logging Events

```bash
kubectl get events -n logging --sort-by=.metadata.creationTimestamp
```

---

# Troubleshooting

## Loki Pod Pending

Check PVC:

```bash
kubectl get pvc -n logging
```

Describe PVC:

```bash
kubectl describe pvc -n logging
```

Common causes:

```text
Longhorn is unhealthy
StorageClass missing
Insufficient storage
```

---

## Loki Not Ready

Check logs:

```bash
kubectl logs -n logging statefulset/loki
```

Check readiness:

```bash
kubectl run curl-test \
  --image=curlimages/curl \
  -n logging \
  -it --rm --restart=Never -- sh
```

Inside:

```bash
curl http://loki-gateway.logging.svc.cluster.local/ready
```

Expected:

```text
ready
```

---

## Promtail Not Running

Check:

```bash
kubectl get daemonset -n logging
```

Describe:

```bash
kubectl describe daemonset promtail -n logging
```

Common causes:

```text
Node scheduling issue
Permission issue
HostPath mount issue
```

---

## Grafana Cannot Connect to Loki

Check service:

```bash
kubectl get svc -n logging
```

Test from monitoring namespace:

```bash
kubectl run curl-test \
  --image=curlimages/curl \
  -n monitoring \
  -it --rm --restart=Never -- sh
```

Inside:

```bash
curl http://loki-gateway.logging.svc.cluster.local/ready
```

Expected:

```text
ready
```

---

## No Logs in Grafana

Check Promtail:

```bash
kubectl logs -n logging daemonset/promtail
```

Check Loki:

```bash
kubectl logs -n logging statefulset/loki
```

Try broad query:

```logql
{}
```

Then narrow:

```logql
{namespace="monitoring"}
```

---

## Loki Alert Rules Not Firing

Check the query manually in Grafana Explore:

```logql
sum by (namespace, pod, container) (
  count_over_time({namespace!=""} |= "error" [5m])
)
```

If this query returns no data, the alert will not fire.

---

## Loki Rule File Not Mounted

Check:

```bash
kubectl exec -it -n logging loki-0 -- ls -lah /var/loki/rules/fake
```

Expected:

```text
log-alerts.yaml
```

---

## Loki Cannot Reach Alertmanager

Test from Loki pod:

```bash
kubectl exec -it -n logging loki-0 -- sh
```

Inside:

```bash
wget -qO- http://monitoring-kube-prometheus-alertmanager.monitoring.svc.cluster.local:9093/api/v2/status
```

If this fails, check service name:

```bash
kubectl get svc -n monitoring | grep alertmanager
```

---

## Alert Reaches Alertmanager But Not Telegram

Check Alertmanager config:

```bash
kubectl exec -it \
-n monitoring \
alertmanager-monitoring-kube-prometheus-alertmanager-0 \
-- cat /etc/alertmanager/config_out/alertmanager.env.yaml
```

Check Telegram receiver exists:

```yaml
receiver: telegram
```

Check Telegram notifications:

```bash
kubectl logs -n monitoring alertmanager-monitoring-kube-prometheus-alertmanager-0
```

---

## Too Many Alerts

Tune thresholds:

```text
> 0    very sensitive
> 3    moderate
> 10   less noisy
```

Increase:

```yaml
for: 5m
```

to avoid short spikes.

---

## Too Many Labels

Do not add high-cardinality labels such as:

```text
request_id
user_id
trace_id
timestamp
full_url
session_id
```

Good labels:

```text
namespace
pod
container
node_name
app
```

Loki is efficient when labels are low-cardinality. High-cardinality labels can make Loki slower and more expensive because Loki indexes labels. [2](https://computingforgeeks.com/deploy-loki-kubernetes/)[3](https://dasroot.net/posts/2026/04/observability-stack-prometheus-grafana-loki/)

---

# Best Practices

## Do

```text
Use Longhorn persistence
Keep Loki internal
Access logs through Grafana
Use 30-day retention
Start with SingleBinary mode
Use namespace/pod/container labels
Use LogQL in Grafana Explore
Monitor Loki through Prometheus
Use Loki Ruler for important log alerts
Alert on error bursts instead of every single error
```

---

## Do Not

```text
Expose Loki publicly
Store logs forever
Use high-cardinality labels
Use Loki as a database
Send secrets into logs
Alert on every harmless warning
Use unlimited retention
```

---

# Recommended Log Alerts

Start with:

```text
Critical:
- LokiCriticalLogsDetected
- LokiLonghornErrorLogs

Warning:
- LokiFailedLogsDetected
- LokiTimeoutLogsDetected
- LokiMonitoringStackErrors
- LokiLoggingStackErrors
```

Be careful with:

```text
LokiErrorLogsDetected
```

because alerting on every single `error` log can be noisy.

A less noisy production-style alert is:

```yaml
- alert: LokiErrorBurstDetected
  expr: |
    sum by (namespace, pod, container) (
      count_over_time(
        {namespace!=""}
        |~ "(?i)error"
        [5m]
      )
    ) > 5
  for: 2m
  labels:
    severity: warning
    source: loki
  annotations:
    summary: "Error burst detected"
    description: "More than 5 error logs detected in namespace={{ $labels.namespace }}, pod={{ $labels.pod }}, container={{ $labels.container }}."
```

---

# Upgrade

Update repositories:

```bash
helm repo update
```

Upgrade Loki:

```bash
helm upgrade loki \
grafana/loki \
-n logging \
-f loki-values.yaml
```

Upgrade Promtail:

```bash
helm upgrade promtail \
grafana/promtail \
-n logging \
-f promtail-values.yaml
```

Update alert rules:

```bash
kubectl apply -f loki-log-alert-rules.yaml
helm upgrade loki grafana/loki -n logging -f loki-values.yaml
```

---

# Cleanup

Uninstall Promtail:

```bash
helm uninstall promtail -n logging
```

Uninstall Loki:

```bash
helm uninstall loki -n logging
```

Delete PVCs if logs should be removed permanently:

```bash
kubectl delete pvc -n logging --all
```

Delete namespace:

```bash
kubectl delete namespace logging
```

---

# Validation Checklist

After deployment, verify:

```text
logging namespace exists
Loki pod is Running
Loki PVC is Bound
Promtail DaemonSet is Ready on all nodes
Loki datasource is available in Grafana
Grafana Explore shows logs
Logs from monitoring namespace are visible
Logs from longhorn-system namespace are visible
LogQL queries return results
Loki ruler is enabled
Loki alert rules are mounted
Loki can reach Alertmanager
Telegram receives log-based alerts
```

---

# Learning Outcomes

After completing Phase 5, you should understand:

```text
Centralized logging
Loki architecture
Promtail log shipping
Grafana Explore
LogQL basics
Log retention
Kubernetes log collection
Loki Ruler
Log-based alerting
Alertmanager integration
Telegram notifications from logs
Difference between metrics and logs
Troubleshooting with logs
```

---

# Final Platform Status

After Phase 5, the homelab includes:

```text
Networking      → MetalLB
Storage         → Longhorn
Metrics         → Prometheus
Dashboards      → Grafana
Alerts          → Alertmanager
Notifications   → Telegram
Logs            → Loki
Log Collector   → Promtail
Log Alerts      → Loki Ruler
```

This gives the homelab a complete observability foundation:

```text
Metrics + Logs + Alerts + Dashboards
```

This is the same core observability pattern used in many production Kubernetes platforms.