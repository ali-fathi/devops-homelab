# Observability

This directory contains observability platform configuration for the homelab Kubernetes cluster.

The purpose of this directory is to manage monitoring, logging, alerting, dashboards, and operational visibility.

---

## Purpose

The `observability/` directory is for platform-level observability configuration.

This includes:

```text
Prometheus
Grafana
Alertmanager
Loki
Grafana Alloy
PrometheusRules
Alert rules
Grafana dashboards
Grafana datasources
Notification configuration
```

This folder should not contain normal application workloads.

Application workloads belong under:

```text
kubernetes/applications/
```

For example:

```text
kubernetes/applications/garmin
kubernetes/applications/ring-health-tracker
```

---

## Current Structure

```text
observability/
├── alerting/
├── garmin/        # legacy location, should be moved to applications/
├── logging/
└── monitoring/
```

Target structure:

```text
observability/
├── alerting/
├── logging/
└── monitoring/
```

---

## Directory Responsibilities

### `monitoring/`

Contains Prometheus and Grafana related configuration.

Examples:

```text
kube-prometheus-stack values
Grafana LoadBalancer service
Grafana dashboards
Grafana dashboard catalog
Monitoring README files
```

Current path:

```text
kubernetes/observability/monitoring
```

---

### `logging/`

Contains Loki and Grafana Alloy related configuration.

Examples:

```text
Loki Helm values
Grafana Alloy values
Loki datasource
Loki alert rules
Log query cheatsheet
Logging README files
```

Current path:

```text
kubernetes/observability/logging
```

---

### `alerting/`

Contains alerting and notification configuration.

Examples:

```text
PrometheusRules
Alertmanager values
Telegram notification configuration
ExternalSecret for Telegram token
Alert runbooks
Alert message templates
```

Current path:

```text
kubernetes/observability/alerting
```

---

## What Belongs Here

The following belong in this directory:

```text
Grafana dashboards
Grafana datasources
PrometheusRules
Alertmanager configuration
Loki configuration
Alloy configuration
Monitoring Helm values
Logging Helm values
Alerting templates
Observability runbooks
```

---

## What Does Not Belong Here

The following should not live in `observability/`:

```text
Application Deployments
Application Services
Application PVCs
Application-specific databases
Application-specific worker pods
```

For example, Garmin and Ring Health Tracker are application workloads because they run services and store application-specific data.

They should live under:

```text
kubernetes/applications/
```

---

## GitOps Strategy

Do not move the full monitoring and logging stack into Argo CD all at once.

Recommended adoption order:

```text
1. Grafana dashboards
2. Grafana datasources
3. PrometheusRules
4. Loki alert rules
5. Alertmanager templates
6. Logging values
7. Monitoring values
8. Full Helm releases later
```

Start with low-risk configuration before moving full platform components.

---

## Why Start with Dashboards and Rules?

Dashboards and alert rules are relatively low risk.

If a dashboard fails, the cluster keeps running.

If a full monitoring Helm release fails, Prometheus, Grafana, Alertmanager, or CRDs may be affected.

Recommended principle:

```text
Move low-risk observability config into GitOps first.
Move platform-critical components later.
```

---

## Current Important Files

### Monitoring

```text
kubernetes/observability/monitoring/values.yaml
kubernetes/observability/monitoring/grafana-lb.yaml
kubernetes/observability/monitoring/dashboards/
```

### Logging

```text
kubernetes/observability/logging/loki-values.yaml
kubernetes/observability/logging/alloy-values.yaml
kubernetes/observability/logging/grafana-loki-datasource.yaml
kubernetes/observability/logging/loki-log-alert-rules.yaml
```

### Alerting

```text
kubernetes/observability/alerting/values-alertmanager.yaml
kubernetes/observability/alerting/telegram-external-secret.yaml
kubernetes/observability/alerting/prometheusrules/
```

---

## Recommended Future GitOps Apps

Later, create Argo CD Applications such as:

```text
monitoring-dashboards
monitoring-prometheusrules
logging-datasources
logging-alert-rules
alertmanager-config
```

Example future Argo CD Application names:

```text
observability-monitoring-config
observability-alerting-rules
observability-logging-config
```

---

## Validation Commands

Check monitoring resources:

```bash
kubectl get pods -n monitoring
kubectl get prometheusrule -A
kubectl get svc -n monitoring
```

Check logging resources:

```bash
kubectl get pods -n logging
kubectl get configmap -n logging
```

Check alerting rules:

```bash
kubectl get prometheusrule -A
```

Check Grafana dashboards ConfigMaps:

```bash
kubectl get configmap -n monitoring --show-labels | grep grafana_dashboard
```

Check Grafana datasources ConfigMaps:

```bash
kubectl get configmap -n monitoring --show-labels | grep grafana_datasource
```

---

## Observability Quality Rules

A good observability setup should have:

```text
Relevant dashboards
Actionable alerts
Runbooks for every critical alert
Low alert noise
Clear service health signals
Useful log queries
SLO-style metrics
```

Avoid:

```text
Too many noisy alerts
Dashboards with no owner
Metrics without action
Alerts without runbooks
Public access to sensitive dashboards
```

---

## Planned Improvements

Future improvements:

```text
Add SLO alerts for Garmin.
Add SLO alerts for Ring Health Tracker.
Add runbook links to alert annotations.
Move dashboards into GitOps.
Move PrometheusRules into GitOps.
Add dashboard validation in CI.
Add alert rule validation in CI.
```

---

## Related Documentation

Recommended related docs:

```text
docs/sre.md
docs/runbooks/
docs/gitops.md
docs/troubleshooting.md
```