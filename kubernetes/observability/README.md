# Kubernetes Observability

This directory contains platform-level monitoring, logging, dashboards, and alerting configuration.

For the complete repository-wide study guide:

```text
docs/homelab-study-guide.md
```

## Scope

```text
kubernetes/observability/
├── monitoring/
├── logging/
└── alerting/
```

Application workloads do not belong here. Garmin, Ring Health Tracker, and Health Dashboard belong under:

```text
kubernetes/applications/
```

The observability layer observes applications; it should not become a place to store application Deployments or application databases.

## Signal flow

Metrics:

```text
Kubernetes, workloads, and Longhorn
  → ServiceMonitors / kube-state-metrics
  → Prometheus
  → Grafana dashboards and PrometheusRules
  → Alertmanager
  → Telegram
```

Longhorn backup monitoring is defined in:

```text
kubernetes/observability/config/prometheusrules/longhorn-backup-monitoring.yaml
```

It scrapes the Longhorn backend, reads non-secret BackupTarget/SystemBackup
status through kube-state-metrics, and alerts on scrape loss, target failure,
stale volume backups, failed/stuck backups, and stale/failed system backups.

Logs:

```text
Kubernetes Pods
  → Grafana Alloy DaemonSet
  → Loki
  → Grafana LogQL
  → Loki ruler alerts
  → Alertmanager
```

## Directory responsibilities

### Monitoring

```text
kubernetes/observability/monitoring/
```

Contains kube-prometheus-stack values, Grafana LoadBalancer configuration, dashboards, and dashboard catalog documentation.

### Logging

```text
kubernetes/observability/logging/
```

Contains Loki values, Alloy values, Grafana Loki datasource, Loki log alert rules, and LogQL query documentation.

### Alerting

```text
kubernetes/observability/alerting/
```

Contains Alertmanager values, Telegram ExternalSecret, PrometheusRules, Longhorn backup monitoring, alert runbooks, and message templates.

## GitOps adoption order

Move low-risk configuration first:

```text
1. Grafana dashboards
2. Grafana datasources
3. PrometheusRules
4. Loki alert rules
5. Alertmanager templates
6. Alloy/Loki configuration
7. Monitoring Helm values
8. Full platform Helm releases
```

Storage-backed monitoring components require backups and restore testing before enabling aggressive pruning.

## Validation

```bash
kubectl get pods -n monitoring
kubectl get pods -n logging
kubectl get prometheusrule -A
kubectl get svc -n monitoring
kubectl get configmap -n monitoring --show-labels
kubectl get configmap -n logging --show-labels
```

## Quality principles

Good observability is:

```text
relevant
actionable
low-noise
owned
linked to runbooks
```

Avoid:

```text
alerts with no operator action
dashboards with no owner
publicly exposed sensitive data
rules without runbooks
unbounded log retention
```

Related documentation:

```text
kubernetes/observability/monitoring/README.md
kubernetes/observability/logging/README.md
kubernetes/observability/alerting/README.md
kubernetes/observability/logging/queries-cheatsheet.md
docs/runbooks/
```
