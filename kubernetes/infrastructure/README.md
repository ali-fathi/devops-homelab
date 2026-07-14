```markdown
# Infrastructure

This directory contains Kubernetes infrastructure components.

## Includes

- MetalLB
- Longhorn
- Traefik
- Sealed Secrets

## Rules

- Platform-critical components should be moved to Argo CD slowly.
- Keep pruning disabled during first GitOps adoption.
- Backup and restore procedures must exist before GitOps-managing storage-sensitive components.
