# Grafana Dashboards

This folder documents all dashboards used in the homelab.

The project follows the approach:

- Community dashboards are imported using Grafana Dashboard IDs.
- Custom dashboards are documented and version controlled in Git.
- Dashboard JSON exports are not stored unless modified.

---

# Dashboard Import

Open Grafana:

```text
Dashboards
  → New
  → Import
```

Enter the Dashboard ID.

Grafana will automatically download the dashboard.

---

# Current Dashboard Set

| Dashboard | ID | Purpose |
|------------|------------|------------|
| Homelab Cluster Health & Recovery | `homelab-cluster-health-recovery` | Cluster, alerts, backups, and critical system status |
| Node Exporter Full | 1860 | Node metrics |
| Kubernetes Cluster Monitoring | 7249 | Cluster overview |
| Kubernetes Views Global | 15757 | Workloads and namespaces |
| Longhorn Dashboard | Official Longhorn Dashboard | Storage monitoring |

---

# Recommended Import Order

1. Node Exporter Full
2. Kubernetes Cluster Monitoring
3. Kubernetes Views Global
4. Longhorn Dashboard

---

# Custom Dashboards

Custom dashboards are stored in:

```text
custom/
```

`homelab-cluster-health.json` is also wrapped as the GitOps-managed
`homelab-cluster-health-dashboard` ConfigMap, so Grafana provisions it
automatically in the **Homelab** folder. It is the primary dashboard for
cluster status, active/pending alerts, Longhorn backup state and age, node
resources, and storage capacity.

Documentation includes:

- panels
- PromQL queries
- thresholds
- visualizations

This makes dashboards reproducible and GitOps-friendly.
