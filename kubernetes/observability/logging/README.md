# 📜 Phase 5 – Centralized Logging with Loki + Promtail

This phase adds centralized logging to the DevOps Homelab Kubernetes platform.

Before this phase, the platform already includes:

```text
K3s
MetalLB
Longhorn
Prometheus
Grafana
Alertmanager
Telegram Alerts
```

After this phase, the platform will also include:

```text
Loki
Promtail
Grafana Log Explorer
Centralized Kubernetes Logs
LogQL Querying
Log Retention
```

---

# 🎯 Goal

The goal of this phase is to collect logs from all Kubernetes workloads and make them searchable from Grafana.

Metrics answer:

```text
What is broken?
```

Logs answer:

```text
Why is it broken?
```

Prometheus and Grafana already provide metrics and dashboards. Loki and Promtail extend the observability stack with centralized logs. Loki is designed for log aggregation and can be installed with Helm. Grafana documents monolithic Loki as suitable for smaller meta-monitoring stacks, while larger production environments should consider distributed or microservices mode. [1](https://github.com/grafana/helm-charts/blob/main/charts/promtail/README.md)

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

This makes Loki lighter and cheaper to operate than full-text indexed logging systems. Loki is commonly used in Kubernetes environments because it indexes metadata labels and stores compressed log content. [2](https://grafana.com/docs/loki/latest/send-data/k8s-monitoring-helm/)[3](https://github.com/grafana/helm-charts/blob/main/charts/loki-stack/README.md)

---

# 🧠 What Is Promtail?

Promtail is a log shipping agent.

Promtail runs on every Kubernetes node as a DaemonSet and collects logs from:

```text
/var/log/pods/
/var/log/containers/
```

Promtail then adds Kubernetes metadata such as namespace, pod, container, and node labels before sending logs to Loki. Promtail normally runs as a DaemonSet for cluster-wide log collection from every node. [4](https://external-secrets.io/latest/provider/azure-key-vault/)[5](https://ranari.com/2025/04/09/azure-key-vault-kubernetes-secrets-terraform/)

> Note: The Promtail Helm chart is marked as deprecated upstream. It is still useful for learning and for existing deployments, but a future migration to Grafana Alloy may be recommended. [4](https://external-secrets.io/latest/provider/azure-key-vault/)[5](https://ranari.com/2025/04/09/azure-key-vault-kubernetes-secrets-terraform/)

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
Show logs from namespace monitoring that contain the word error
```

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

---

# 🧩 Components

## Loki

Responsible for:

```text
Receiving logs
Storing logs
Indexing labels
Applying retention
Serving LogQL queries
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
```

After Loki is deployed, all of those questions can be investigated from Grafana.

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

Loki does not need a MetalLB IP because Grafana can reach Loki internally through the Kubernetes service DNS.

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
        └── queries-cheatsheet.md
```

Create the directory:

```bash
mkdir -p kubernetes/observability/logging
cd kubernetes/observability/logging
```

---

# ✅ Prerequisites

Before installing Loki and Promtail, verify the following:

```text
K3s is healthy
Longhorn is healthy
Grafana is running
Prometheus is running
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

Grafana provides Helm charts for Loki and Promtail through the Grafana Helm repository. [4](https://external-secrets.io/latest/provider/azure-key-vault/)[6](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)

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

singleBinary:
  replicas: 1

  persistence:
    enabled: true
    storageClass: longhorn
    size: 20Gi

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

Grafana and Promtail will use this endpoint.

---

# 🚀 Step 4 – Install Loki

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

---

# 🚀 Step 5 – Verify Loki PVC

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

# 🚀 Step 6 – Verify Loki Services

```bash
kubectl get svc -n logging
```

Expected services include:

```text
loki
loki-gateway
```

---

# 🚀 Step 7 – Test Loki Internally

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

# 🚀 Step 8 – Create Promtail Values File

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

This parses Kubernetes container logs generated by the container runtime.

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

The initial resource settings are:

```text
CPU request: 50m
Memory request: 64Mi
CPU limit: 300m
Memory limit: 256Mi
```

---

# 🚀 Step 9 – Install Promtail

```bash
helm install promtail \
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

# 🚀 Step 10 – Verify Promtail Logs

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

# 🚀 Step 11 – Add Loki Datasource to Grafana Manually

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

# 🚀 Step 12 – Add Loki Datasource with GitOps-Friendly ConfigMap

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

# 🚀 Step 13 – Verify Logs in Grafana

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

Loki is efficient when labels are low-cardinality. High-cardinality labels can make Loki slower and more expensive because Loki indexes labels. [2](https://grafana.com/docs/loki/latest/send-data/k8s-monitoring-helm/)[3](https://github.com/grafana/helm-charts/blob/main/charts/loki-stack/README.md)

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
```

---

## Do Not

```text
Expose Loki publicly
Store logs forever
Use high-cardinality labels
Use Loki as a database
Send secrets into logs
Use unlimited retention
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
Troubleshooting with logs
Difference between metrics and logs
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
```

This gives the homelab a complete observability foundation:

```text
Metrics + Logs + Alerts + Dashboards
```

This is the same core observability pattern used in many production Kubernetes platforms.