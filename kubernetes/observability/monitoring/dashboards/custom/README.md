# 📊 Homelab Grafana Dashboards

This folder contains custom Grafana dashboards for monitoring, alerting, and log analysis within the Kubernetes homelab platform.

The dashboards are designed to work with:

```text
K3s
MetalLB
Longhorn
Prometheus
Grafana
Alertmanager
Telegram Notifications
Loki
Grafana Alloy
Azure Key Vault
External Secrets Operator
```

---

# 📂 Dashboard Files

```text
dashboards/
├── README.md
├── homelab-kubernetes-overview.json
├── homelab-alerting-overview.json
├── homelab-cluster-health.json
└── homelab-loki-critical-error.json
```

---

# 🎯 Dashboard Purpose

The dashboards provide visibility into:

```text
Cluster health
Node availability
Pod health
Resource usage
Persistent volumes
Alerts
Critical logs
Error logs
Storage problems
Grafana issues
Loki issues
Grafana Alloy issues
```

These dashboards answer questions such as:

```text
Is Kubernetes healthy?
Are nodes available?
Which pods are restarting?
Are volumes filling up?
Which alerts are active?
Which namespace is producing errors?
Did Loki detect a critical log?
Is Longhorn experiencing problems?
```

---

# 🔌 Required Datasources

## Prometheus

Used by:

```text
homelab-kubernetes-overview.json
homelab-alerting-overview.json
```

Verify:

```text
Grafana
→ Connections
→ Data Sources
→ Prometheus
→ Save & Test
```

Expected:

```text
Successfully queried the Prometheus API
```

---

## Loki

Used by:

```text
homelab-loki-critical-error.json
```

Verify:

```text
Grafana
→ Connections
→ Data Sources
→ Loki
→ Save & Test
```

Expected:

```text
Successfully queried the Loki API
```

---

# 🚀 Import Dashboard

Open Grafana:

```text
http://192.168.178.212
```

Navigate to:

```text
Dashboards
→ New
→ Import
```

Paste the contents of the dashboard JSON file.

Select the correct datasource:

```text
Prometheus
```

or

```text
Loki
```

Click:

```text
Import
```

---

# 📊 Dashboard 1 – Kubernetes Overview

File:

```text
homelab-kubernetes-overview.json
```

Datasource:

```text
Prometheus
```

Purpose:

```text
Cluster health monitoring
```

## Panels

### Ready Nodes

Shows the number of healthy Kubernetes nodes.

Healthy example:

```text
3
```

Check manually:

```bash
kubectl get nodes
```

---

### Running Pods

Shows the number of running pods.

Check manually:

```bash
kubectl get pods -A
```

---

### Pods Not Running

Shows:

```text
Pending
Failed
Unknown
```

Check manually:

```bash
kubectl get pods -A | grep -v Running
```

---

### PVCs Pending

Shows storage claims waiting for provisioning.

Check manually:

```bash
kubectl get pvc -A
```

---

### Cluster CPU Usage %

Recommended interpretation:

```text
0–70%      Healthy
70–85%     Warning
85–100%    Investigate
```

---

### Cluster Memory Usage %

Recommended interpretation:

```text
0–75%      Healthy
75–90%     Warning
90–100%    Investigate
```

---

### PVC Usage %

Recommended interpretation:

```text
80%+       Warning
90%+       Critical
```

---

### Pod Restarts by Namespace

Highlights unstable workloads.

---

### Top Restarting Pods

Shows containers that may be crashing repeatedly.

Useful command:

```bash
kubectl describe pod <pod>
kubectl logs <pod>
```

---

# 🚨 Dashboard 2 – Alerting Overview

File:

```text
homelab-alerting-overview.json
```

Datasource:

```text
Prometheus
```

### Homelab Cluster Health & Recovery

File:

```text
homelab-cluster-health.json
```

This dashboard is provisioned automatically from the GitOps-managed
`homelab-cluster-health-dashboard` ConfigMap. It is the operational view for
cluster health and backup recovery:

```text
Ready nodes, firing/pending alerts, critical alerts, unavailable deployments,
non-ready pods, Bound PVCs, BackupTarget availability, system-backup age,
oldest volume-backup age, healthy Longhorn volumes, volume backup age by PVC,
system-backup state, node CPU/memory, Longhorn disk usage, and backup-age trends
```

Open it in Grafana under the **Homelab** folder. The alert table uses Prometheus
`ALERTS` series, so it shows every active firing or pending alert with its name,
state, severity, namespace, pod, and volume when those labels exist.

Purpose:

```text
Alert visibility
```

Recommended time range:

```text
Last 6 hours
```

---

## Panels

### Firing Alerts

Total active alerts.

---

### Critical Alerts

Shows currently active critical alerts.

Examples:

```text
Node Down
Longhorn Degraded
OOM Detected
Critical Loki Alert
```

---

### Error Alerts

Currently firing error-level alerts.

---

### Warning Alerts

Currently firing warning alerts.

Useful for observation without spamming Telegram.

---

### Firing Alerts by Severity

Grouped by:

```text
critical
error
warning
info
```

---

### Firing Alerts by Namespace

Shows which namespaces generate alerts.

Useful for finding noisy workloads.

---

### Current Firing Alerts

Displays active alerts with labels such as:

```text
alertname
namespace
severity
pod
container
instance
```

---

# 📜 Dashboard 3 – Loki Critical & Error Logs

File:

```text
homelab-loki-critical-error.json
```

Datasource:

```text
Loki
```

Purpose:

```text
High-signal log monitoring
```

Recommended time range:

```text
Last 1 hour
```

---

## Dashboard Variables

The dashboard supports:

```text
namespace
pod
container
```

Default:

```text
All
```

Important:

```text
All value = .+
```

Do NOT use:

```text
.*
```

Otherwise Loki may return query parser errors.

---

## Panels

### Critical Logs – Last 5m

Matches:

```text
critical
fatal
panic
segmentation fault
corruption detected
```

---

### Real Error-Level Logs

Matches:

```text
level=error
severity=error
level=err
```

This avoids false positives.

---

### OOM / Memory Exhaustion

Matches:

```text
OOMKilled
Out of Memory
OOM Killer
Cannot Allocate Memory
```

---

### Longhorn Critical Logs

Matches storage issues:

```text
Volume Degraded
Volume Faulted
Replica Failed
Failed To Attach
Disk Pressure
Insufficient Storage
```

---

### Critical Logs By Namespace

Shows which namespace is generating critical logs.

---

### Error Logs By Namespace

Shows which namespace is generating structured errors.

---

### Top Pods With Critical Logs

Highlights bad actors quickly.

---

### Top Pods With Error Logs

Shows pods producing repeated errors.

---

### Grafana Critical Logs

Focuses on:

```text
error
fatal
panic
HTTP 5xx
```

Intentionally ignores:

```text
400 responses
info logs
query noise
```

---

### Loki & Alloy Critical Logs

Tracks issues related to:

```text
Loki
Grafana Alloy
```

Examples:

```text
Permission problems
Config errors
Corruption
Out of space
Fatal startup errors
```

---

### Recent Critical & Error Logs

Shows actual matching log lines.

Useful when investigating incidents.

---

### Loki Ruler / Alertmanager Activity

Shows log lines related to:

```text
Rule evaluation
Alert generation
Alert delivery
Alertmanager communication
Notification failures
```

---

# 🧪 Dashboard Tests

## Test Critical Logging

Create a test pod:

```bash
kubectl run dashboard-critical-test \
  --image=busybox:1.36 \
  --restart=Never \
  -- sh -c 'echo "fatal: dashboard critical log validation"; sleep 300'
```

Verify:

```bash
kubectl logs dashboard-critical-test
```

Expected:

```text
fatal: dashboard critical log validation
```

Open:

```text
Homelab – Loki Critical & Error Logs
```

Expected activity in:

```text
Critical Logs
Critical Logs By Namespace
Top Critical Pods
Recent Critical Logs
```

Delete test pod:

```bash
kubectl delete pod dashboard-critical-test
```

---

## Test Kubernetes Dashboard

Create a temporary pod:

```bash
kubectl run dashboard-test \
  --image=busybox:1.36 \
  --restart=Never \
  -- sleep 300
```

Expected:

```text
Running Pods increases
```

Delete:

```bash
kubectl delete pod dashboard-test
```

---

# 🔧 Troubleshooting

## Dashboard Shows No Data

Verify:

```text
Correct datasource
Correct time range
Prometheus healthy
Loki healthy
Metrics or logs actually exist
```

Try:

```text
Last 6 Hours
```

instead of:

```text
Last 15 Minutes
```

---

## Loki Query Error

Error:

```text
queries require at least one regexp or equality matcher that does not have an empty-compatible value
```

Fix:

```text
All value must be .+
```

Not:

```text
.*
```

---

## Loki Dashboard Shows No Logs

Check Alloy:

```bash
kubectl logs -n logging deployment/alloy
```

Check Loki datasource:

```text
Connections
→ Data Sources
→ Loki
→ Save & Test
```

Test query:

```logql
{namespace=~".+"}
```

---

## Missing Metrics

Verify:

```bash
kubectl get pods -n monitoring | grep kube-state-metrics
kubectl get pods -n monitoring | grep node-exporter
```

---

## Alert Dashboard Empty

Check Prometheus alerts:

```bash
kubectl port-forward \
-n monitoring \
svc/monitoring-kube-prometheus-prometheus \
9090
```

Open:

```text
http://localhost:9090/alerts
```

---

# ✅ Best Practices

## Store Dashboards In Git

```text
kubernetes/observability/monitoring/dashboards/
```

---

## Dashboard Naming

Recommended:

```text
Homelab - Kubernetes Overview
Homelab - Alerting Overview
Homelab - Loki Critical and Error Logs
```

---

## Avoid Noisy Loki Queries

Avoid:

```logql
{} |= "error"
```

Prefer:

```logql
| logfmt | level=~"error|fatal|panic"
```

or:

```logql
|~ "(?i)critical|fatal|panic|oomkilled|out of memory"
```

---

## Use Dashboard Variables

Use:

```text
namespace
pod
container
```

to narrow investigations quickly.

---

## Import → Validate → Commit

Recommended workflow:

```text
1. Import dashboard
2. Validate panels
3. Export final dashboard
4. Commit JSON into Git
5. Automate later with Grafana sidecar / ArgoCD
```

---

# ✅ Daily Monitoring Flow

Every day:

```text
1. Open Kubernetes Overview
2. Verify nodes and pods are healthy
3. Check Alerting Overview
4. Investigate active critical alerts
5. Open Loki Critical & Error Dashboard
6. Review critical logs
7. Investigate storage issues
8. Confirm Loki/Alloy/Grafana are healthy
```

This provides complete coverage of:

```text
Infrastructure
Storage
Applications
Metrics
Logs
Alerts
Notifications
```