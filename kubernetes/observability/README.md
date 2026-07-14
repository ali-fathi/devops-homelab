
```markdown
# Observability

This directory contains observability platform configuration.

## Includes

- monitoring
- logging
- alerting

## Purpose

This folder is for platform observability components and configuration such as:

- Prometheus values
- Grafana dashboards
- Grafana datasources
- PrometheusRules
- Loki values
- Alloy values
- Alertmanager values

## Not for

Application workloads should not live here. For example, Garmin and Ring Health Tracker belong under:

```text
kubernetes/applications/
