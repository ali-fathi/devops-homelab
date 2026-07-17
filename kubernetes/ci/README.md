# In-Cluster CI Systems

This directory is reserved for CI servers that may eventually run inside Kubernetes.

Current files:

```text
kubernetes/ci/forgejo/forgejo.yaml
kubernetes/ci/jenkins/jenkins.yaml
kubernetes/ci/woodpecker/weedpecker.yaml
```

These manifests are currently preparation or learning material, not the active CI pipeline for this repository.

The active image CI runs in GitHub Actions:

```text
.github/workflows/
```

For the complete platform study guide:

```text
docs/homelab-study-guide.md
```

## Why keep CI options separate?

Forgejo, Jenkins, and Woodpecker have overlapping responsibilities:

```text
source control
build execution
credentials
artifact storage
webhooks
worker agents
```

Running all of them without clear ownership creates unnecessary complexity.

Current model:

```text
GitHub repository
  → GitHub Actions
  → GHCR
  → Argo CD
  → Kubernetes
```

Future self-hosted model may be:

```text
Forgejo
  → Woodpecker or Jenkins
  → Harbor
  → Argo CD
  → Kubernetes
```

Choose one source-control system and one primary CI system before deploying these components.

## Stateful safety

CI servers are stateful and may contain:

```text
source repositories
build history
credentials
webhooks
worker configuration
artifacts
```

Before deployment:

```text
Choose a storage class.
Define PVC sizes.
Protect credentials with External Secrets.
Define backup and restore.
Choose ingress and TLS.
Document runner isolation.
```
