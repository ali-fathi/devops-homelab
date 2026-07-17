# Homelab Architecture

The homelab is split into an operator plane and a workload plane.

```text
Operator plane:
  Mac/Linux workstation
    → VS Code DevContainer
    → kubectl / Helm / Ansible / Terraform / Argo CD
    → K3s API

Workload plane:
  K3s control plane and workers
    → infrastructure
    → storage/networking/secrets
    → observability
    → applications
```

## Nodes

```text
k3s-master   192.168.178.80   control plane
k3s-worker1  192.168.178.81   worker
k3s-worker2  192.168.178.82   worker
```

## Platform layers

```text
K3s
  → MetalLB and Longhorn
  → External Secrets and Argo CD
  → Prometheus/Grafana/Loki/Alertmanager
  → Garmin and Ring data applications
  → Health Dashboard and other workloads
```

## Data flows

Garmin:

```text
Garmin watch
  → Garmin Connect
  → garmin-fetch-data
  → InfluxDB GarminStats
  → Grafana / Health Dashboard
```

Ring:

```text
Colmi R02
  → Android Ring Health Tracker
  → Cloudflare Tunnel
  → VictoriaMetrics
  → Grafana / Health Dashboard
```

Application delivery:

```text
GitHub
  → GitHub Actions
  → container registry
  → immutable image digest in Git
  → Argo CD
  → Kubernetes
```

## Network addresses

MetalLB pool:

```text
192.168.178.210-192.168.178.220
```

Important services:

```text
Longhorn UI              192.168.178.211
Grafana                  192.168.178.212
Argo CD                  192.168.178.213
Ring VictoriaMetrics     192.168.178.214
Harbor reservation       192.168.178.215
Health Dashboard         192.168.178.216
```

## Ownership boundaries

```text
Ansible  → hosts and operating system
Terraform → future infrastructure resources
Helm     → third-party platform installation
Argo CD  → GitOps reconciliation
Kubernetes → workload lifecycle
Longhorn → persistent storage
MetalLB  → LAN LoadBalancer addresses
```

Do not allow multiple tools to manage the same resource fields without documenting ownership.

## Study guide

For the detailed explanation of every layer:

```text
docs/homelab-study-guide.md
```
