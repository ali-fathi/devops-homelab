# Dashboard Catalog

## Homelab Cluster Health & Recovery

File:

```text
custom/homelab-cluster-health.json
```

Purpose:

```text
Cluster readiness and critical system indicators
Active and pending alert names, severity, and workload labels
Longhorn BackupTarget and system-backup status
Volume backup age and backup-age trends
Node CPU, memory, and Longhorn disk usage
```

Provisioning:

```text
GitOps ConfigMap: homelab-cluster-health-dashboard
Grafana folder: Homelab
Refresh: 30 seconds
```

---

## Node Exporter Full

Dashboard ID:

```text
1860
```

Purpose:

```text
Node CPU
Node RAM
Disk Usage
Network Usage
Filesystem Usage
Load Average
```

Recommended for:

```text
k3s-master
k3s-master2
k3s-master3
k3s-worker1
k3s-worker2
```

---

## Kubernetes Cluster Monitoring

Dashboard ID:

```text
7249
```

Purpose:

```text
Cluster Health
Nodes
Namespaces
Deployments
Pods
```

---

## Kubernetes Views Global

Dashboard ID:

```text
15757
```

Purpose:

```text
Container Usage
Namespace Resources
Pod CPU
Pod Memory
Workloads
```

---

## Longhorn Dashboard

Source:

```text
Longhorn Official Dashboard
```

Purpose:

```text
Volumes
Replicas
Capacity
Disk Usage
Node Storage
Backup Status
```

Monitor closely:

```text
Volume Health
Replica Count
Storage Capacity
```

---

# Homelab Dashboard Map

```text
Infrastructure
├── Homelab Cluster Health & Recovery
├── Node Exporter Full
└── Cluster Monitoring

Storage
└── Longhorn Dashboard

Applications
└── Kubernetes Views Global
```

