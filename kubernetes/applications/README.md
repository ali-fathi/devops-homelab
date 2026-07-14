Application deployment in Kubernetes cluster
# Kubernetes Applications

This directory contains application workloads that run on the homelab Kubernetes cluster.

Applications in this directory are GitOps-managed by Argo CD.

## Current applications

- garmin
- ring-health-tracker
- nginx-longhorn-metallb

## Rules

- Each app should have its own folder.
- Each app should include a README.md.
- Stateful apps must keep `prune: false` until backup/restore is tested.
- Raw dashboard JSON files should not be scanned directly by Argo CD.
- Argo CD Applications should use `directory.include` when non-manifest files exist.

## App structure

```text
app-name/
├── namespace.yaml
├── deployment.yaml
├── service.yaml
├── pvc.yaml                    # if needed
├── external-secret.yaml        # if needed
├── grafana-dashboard.yaml      # if needed
└── README.md