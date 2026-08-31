# Dashboard Catalog

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
├── Node Exporter Full
└── Cluster Monitoring

Storage
└── Longhorn Dashboard

Applications
└── Kubernetes Views Global
```

