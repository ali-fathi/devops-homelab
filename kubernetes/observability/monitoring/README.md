# 📊 Phase 4 – Monitoring & Observability
# Prometheus + Grafana for K3s Homelab

For the broad platform study guide, read:

```text
docs/homelab-study-guide.md
```

## Overview

This phase introduces monitoring and observability into the Kubernetes platform.

Before this phase, the cluster already provides:

```text
✅ K3s
✅ MetalLB
✅ Longhorn
✅ Persistent Storage
✅ LoadBalancer Services
```

However, there is no visibility into:

- Cluster health
- Node performance
- Resource consumption
- Pod failures
- Storage usage
- Application performance
- Historical metrics

This phase solves these problems using:

```text
Prometheus
Grafana
Alertmanager
Node Exporter
kube-state-metrics
Prometheus Operator
```

All of these components are installed through:

```text
kube-prometheus-stack
```

---

# 🎯 Goals

After completing this phase you will have:

✅ Cluster Monitoring

✅ Node Monitoring

✅ Pod Monitoring

✅ Workload Monitoring

✅ Longhorn Monitoring

✅ Historical Metrics

✅ Dashboards

✅ Alerting Foundation

✅ Prometheus Query Language (PromQL)

✅ Production-Style Observability

---

# 🏗️ Architecture

```text
                  Kubernetes Cluster
                           │
                           ▼

                    kube-state-metrics
                           │
                           ▼

Node Exporter ───► Prometheus ◄─── Longhorn Metrics
                           │
                           ▼
                      Alertmanager
                           │
                           ▼
                        Grafana
                           │
                           ▼
                      Dashboards
```

---

# 📚 Components

## Prometheus

Prometheus is the monitoring engine.

Responsibilities:

```text
Collect metrics
Store metrics
Query metrics
Generate alerts
Feed Grafana dashboards
```

Examples:

```text
CPU Usage
Memory Usage
Disk Usage
Container Restarts
Network Traffic
PVC Usage
Storage Availability
```

---

## Grafana

Grafana visualizes data from Prometheus.

Provides:

```text
Dashboards
Charts
Panels
Alerts
Visual Metrics
```

Examples:

```text
CPU = 37%
RAM = 42%
Disk = 61%
```

displayed graphically.

---

## Node Exporter

Runs on every node.

Provides:

```text
CPU
Memory
Disk
Filesystem
Load Average
Network Statistics
```

---

## kube-state-metrics

Reads Kubernetes objects and exposes metrics.

Examples:

```text
Pods
Deployments
Namespaces
PVCs
StatefulSets
DaemonSets
Nodes
```

---

## Prometheus Operator

Manages Prometheus lifecycle.

Creates:

```text
Prometheus
ServiceMonitors
PodMonitors
Alertmanager
```

Automatically.

---

## Alertmanager

Responsible for alert routing.

Can send notifications through:

```text
Email
Discord
Slack
Microsoft Teams
Telegram
Webhook
```

---

# 📂 Repository Structure

Create:

```text
kubernetes/
└── observability/
    └── monitoring/
        ├── README.md
        ├── values.yaml
        ├── grafana-lb.yaml
        └── dashboards/
```

---

# 📍 Current MetalLB Address Plan

Current reserved services:

```text
192.168.178.210 → Traefik
192.168.178.211 → Longhorn UI
192.168.178.212 → Grafana
```

Recommended future reservations:

```text
192.168.178.213 → Harbor
192.168.178.214 → Forgejo
192.168.178.215 → ArgoCD
192.168.178.216 → MinIO
```

---

# ✅ Prerequisites

Verify K3s:

```bash
kubectl get nodes
```

Expected:

```text
k3s-master    Ready
k3s-master2   Ready
k3s-master3   Ready
k3s-worker1   Ready
k3s-worker2   Ready
```

---

Verify MetalLB:

```bash
kubectl get pods -n metallb-system
```

Expected:

```text
controller
speaker
speaker
speaker
```

---

Verify Longhorn:

```bash
kubectl get pods -n longhorn-system
```

Expected:

```text
Running
```

---

Verify DNS:

```bash
kubectl run netshoot \
  --image=nicolaka/netshoot \
  -it --rm --restart=Never -- bash
```

Inside:

```bash
nslookup kubernetes.default.svc.cluster.local
```

Expected:

```text
Name: kubernetes.default.svc.cluster.local
Address: 10.43.0.1
```

---

# 🚀 Step 1 – Create Monitoring Namespace

```bash
kubectl create namespace monitoring
```

Verify:

```bash
kubectl get ns monitoring
```

---

# 🚀 Step 2 – Add Helm Repository

Add repository:

```bash
helm repo add prometheus-community \
https://prometheus-community.github.io/helm-charts
```

Update:

```bash
helm repo update
```

Verify:

```bash
helm search repo kube-prometheus-stack
```

Expected:

```text
prometheus-community/kube-prometheus-stack
```

---

# 🚀 Step 3 – Create values.yaml

Create:

```text
kubernetes/observability/monitoring/values.yaml
```

Content:

```yaml
grafana:
  persistence:
    enabled: true
    storageClassName: longhorn
    size: 5Gi

prometheus:
  prometheusSpec:
    retention: 30d

    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 20Gi

alertmanager:
  enabled: true

  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 5Gi
```

---

# Why Use Longhorn?

Without persistence:

```text
Pod Restart
     ↓
Metrics Lost
```

With Longhorn:

```text
Pod Restart
     ↓
Metrics Preserved
```

Stored data:

```text
Prometheus Metrics
Grafana Dashboards
Alert History
```

---

# 🚀 Step 4 – Install Monitoring Stack

From the monitoring directory:

```bash
helm install monitoring \
prometheus-community/kube-prometheus-stack \
-n monitoring \
-f values.yaml
```

---

# 🚀 Step 5 – Watch Deployment

```bash
kubectl get pods -n monitoring -w
```

Wait until everything is:

```text
Running
```

---

# 🚀 Step 6 – Verify Components

Check:

```bash
kubectl get pods -n monitoring
```

Expected:

```text
monitoring-grafana
monitoring-kube-state-metrics
monitoring-prometheus-node-exporter
alertmanager-monitoring
prometheus-monitoring
prometheus-operator
```

---

# 🚀 Step 7 – Verify Longhorn Volumes

```bash
kubectl get pvc -n monitoring
```

Expected:

```text
storage-prometheus-0
storage-alertmanager-0
grafana-storage
```

Status:

```text
Bound
```

---

# 🚀 Step 8 – Create Grafana LoadBalancer

Create:

```text
grafana-lb.yaml
```

Content:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana-lb
  namespace: monitoring

spec:
  type: LoadBalancer

  loadBalancerIP: 192.168.178.212

  selector:
    app.kubernetes.io/name: grafana

  ports:
    - name: http
      port: 80
      targetPort: 3000
```

Apply:

```bash
kubectl apply -f grafana-lb.yaml
```

---

# 🚀 Step 9 – Verify MetalLB Assignment

```bash
kubectl get svc -n monitoring
```

Expected:

```text
grafana-lb
```

External IP:

```text
192.168.178.212
```

---

# 🚀 Step 10 – Access Grafana

Open:

```text
http://192.168.178.212
```

---

# 🚀 Step 11 – Obtain Grafana Password

```bash
kubectl get secret monitoring-grafana \
-n monitoring \
-o jsonpath="{.data.admin-password}" \
| base64 -d
```

Username:

```text
admin
```

---

# 🚀 Step 12 – Verify Prometheus

```bash
kubectl get prometheus -n monitoring
```

Expected:

```text
Running
```

Verify services:

```bash
kubectl get svc -n monitoring
```

Look for:

```text
prometheus-operated
```

---

# 📊 Import Dashboards

## Node Exporter Full

Dashboard ID:

```text
1860
```

Most important dashboard.

Displays:

```text
CPU
RAM
Disk
Filesystem
Network
Load
```

---

## Kubernetes Cluster Monitoring

Dashboard ID:

```text
7249
```

Displays:

```text
Nodes
Pods
Namespaces
Deployments
Resource Consumption
```

---

## Kubernetes Views

Dashboard ID:

```text
15757
```

Displays:

```text
CPU
Memory
Workloads
Containers
```

---

# 💾 Longhorn Monitoring

Verify Longhorn Service:

```bash
kubectl get svc -n longhorn-system
```

Look for:

```text
longhorn-backend
```

Metrics collected:

```text
Volume Health
Replica Count
Disk Usage
Capacity Usage
Node Storage
Backups
```

---

# 📈 Useful PromQL Queries

## Node CPU Usage

```promql
100 -
(
avg by(instance)
(rate(node_cpu_seconds_total{mode="idle"}[5m]))
* 100
)
```

---

## Memory Usage

```promql
(
node_memory_MemTotal_bytes
-
node_memory_MemAvailable_bytes
)
/
node_memory_MemTotal_bytes
*
100
```

---

## Running Pods

```promql
count(
kube_pod_status_phase{
phase="Running"
}
)
```

---

## Pod Restarts

```promql
increase(
kube_pod_container_status_restarts_total[24h]
)
```

---

## Node Filesystem Usage

```promql
100 -
(
node_filesystem_avail_bytes
/
node_filesystem_size_bytes
*100
)
```

---

# 🚨 Recommended Alerts

## Node Down

Severity:

```text
Critical
```

---

## Disk Usage Above 80%

Severity:

```text
Warning
```

---

## Disk Usage Above 90%

Severity:

```text
Critical
```

---

## Longhorn Replica Failure

Severity:

```text
Critical
```

---

## Pod CrashLoopBackOff

Severity:

```text
Warning
```

---

## Memory Usage Above 90%

Severity:

```text
Warning
```

---

# ✅ Validation Checklist

Verify all of the following:

```text
✓ Grafana reachable
✓ Prometheus running
✓ PVCs Bound
✓ Longhorn volumes healthy
✓ Node metrics visible
✓ Pod metrics visible
✓ Dashboards working
✓ Cluster visible in Grafana
```

---

# 🔧 Troubleshooting

## Grafana Not Accessible

Check:

```bash
kubectl get svc -n monitoring
```

Expected:

```text
192.168.178.212
```

---

Verify MetalLB:

```bash
kubectl get pods -n metallb-system
```

---

## Grafana Pod Not Running

```bash
kubectl describe pod -n monitoring
```

Common causes:

```text
PVC Pending
Longhorn Issue
Insufficient RAM
```

---

## Prometheus Pending

Check:

```bash
kubectl get pvc -n monitoring
```

Expected:

```text
Bound
```

---

## Empty Dashboards

Verify Grafana datasource:

```text
Prometheus
```

Datasource Health:

```text
Healthy
```

---

## Metrics Missing

Verify:

```bash
kubectl get servicemonitors -A
```

Check:

```bash
kubectl logs -n monitoring \
deployment/monitoring-kube-prometheus-operator
```

---

# 📋 Operations Cheat Sheet

## Nodes

```bash
kubectl get nodes
```

---

## Pods

```bash
kubectl get pods -n monitoring
```

---

## Services

```bash
kubectl get svc -n monitoring
```

---

## PVCs

```bash
kubectl get pvc -n monitoring
```

---

## Secrets

```bash
kubectl get secrets -n monitoring
```

---

## Prometheus

```bash
kubectl get prometheus -n monitoring
```

---

## Alertmanager

```bash
kubectl get alertmanager -n monitoring
```

---

## Grafana Password

```bash
kubectl get secret monitoring-grafana \
-n monitoring \
-o jsonpath="{.data.admin-password}" \
| base64 -d
```

---

## Grafana Logs

```bash
kubectl logs -n monitoring deployment/monitoring-grafana
```

---

## Prometheus Logs

```bash
kubectl logs -n monitoring \
statefulset/prometheus-monitoring-kube-prometheus-prometheus
```

---

# 🎓 Learning Outcomes

After completing Phase 4 you should understand:

✅ Prometheus

✅ Grafana

✅ Alertmanager

✅ Node Exporter

✅ kube-state-metrics

✅ Longhorn Monitoring

✅ Storage Monitoring

✅ Kubernetes Monitoring

✅ PromQL

✅ Dashboards

✅ Alerting

✅ Observability

---

# 🔮 Next Phase

Phase 5 introduces centralized logging:

```text
Loki
Grafana Alloy
Grafana Logs
```

After Phase 5 the platform provides:

```text
Networking  → MetalLB
Storage     → Longhorn
Metrics     → Prometheus
Dashboards  → Grafana
Logs        → Loki
GitOps      → ArgoCD
```

and becomes a complete production-style Kubernetes platform.
