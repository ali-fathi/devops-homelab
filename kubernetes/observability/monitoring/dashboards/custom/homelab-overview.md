# Homelab Overview Dashboard

Purpose:

Single-pane-of_avail_bytesSingle-pane-of-glass dashboard for the entire homelab.
/
node_filesystem_size_bytes
*100
)
```

---

# Dashboard Layout

```text
+----------------------------------------+
| CPU %         | Memory %              |
+----------------------------------------+
| Running Pods  | PVC Usage             |
+----------------------------------------+
| Longhorn Health                       |
+----------------------------------------+
| Node Filesystem Usage                 |
+----------------------------------------+
```

---

# Future Panels

Later phases may add:

```text
Harbor Registry
Forgejo
Woodpecker CI
ArgoCD
Loki
MinIO
```

---

# Panel 1

Title:

```text
Cluster CPU Usage
```

Visualization:

```text
Gauge
```

PromQL:

```promql
100 -
(
avg(
rate(
node_cpu_seconds_total{mode="idle"}[5m]
)
)
* 100
)
```

Thresholds:

```text
Green < 60%
Yellow > 60%
Orange > 80%
Red > 90%
```

---

# Panel 2

Title:

```text
Cluster Memory Usage
```

Visualization:

```text
Gauge
```

PromQL:

```promql
(
sum(node_memory_MemTotal_bytes)
-
sum(node_memory_MemAvailable_bytes)
)
/
sum(node_memory_MemTotal_bytes)
*
100
```

Thresholds:

```text
Green < 70%
Yellow > 70%
Orange > 85%
Red > 95%
```

---

# Panel 3

Title:

```text
Running Pods
```

Visualization:

```text
Stat
```

PromQL:

```promql
count(
kube_pod_status_phase{
phase="Running"
}
)
```

---

# Panel 4

Title:

```text
PVC Usage
```

Visualization:

```text
Table
```

PromQL:

```promql
kubelet_volume_stats_used_bytes
```

---

# Panel 5

Title:

```text
Longhorn Volume Health
```

Visualization:

```text
Table
```

Metric:

```text
Longhorn volume health metrics
```

---

# Panel 6

Title:

```text
Node Filesystem Usage
```

Visualization:

```text
Bar Gauge
```

PromQL:

```promql
100 -
(

