# Project Documentation Index

This directory contains architecture, operations, security, CI/CD, troubleshooting, and study material for the homelab.

## Start here

```text
docs/homelab-study-guide.md
```

This is the broad learning guide for the complete platform.

## Architecture and foundations

```text
docs/architecture.md
docs/networking.md
docs/k3s-baseline-networking.md
docs/storage.md
```

## Delivery and GitOps

```text
docs/gitops.md
docs/ci-manifest-validation.md
docs/observability-gitops-convergence.md
docs/container-build-pipeline-harbor.md
```

## Security

```text
docs/security-findings.md
```

Security-related decisions should be documented rather than silently ignored.

## Runbooks

```text
docs/runbooks/
```

Runbooks provide symptom-driven procedures for:

```text
Argo CD drift and comparison errors
External Secrets failures
Garmin synchronization failures
```

## Application study guides

```text
apps/health-dashboard/README.md
kubernetes/applications/health-dashboard/README.md
apps/homelab-api/README.md
```

## Platform study guides

```text
.devcontainer/README.md
ansible/README.md
terraform/README.md
kubernetes/README.md
kubernetes/infrastructure/README.md
kubernetes/observability/README.md
kubernetes/gitops/argocd/README.md
kubernetes/registry/README.md
```

## Documentation rule

When a component changes, update:

```text
its local README
related runbooks
architecture diagrams if data flow changes
security findings if exposure or secret handling changes
```
