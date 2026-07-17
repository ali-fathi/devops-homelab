# GitOps Study Guide

GitOps treats Git as the desired state of the Kubernetes platform.

```text
Git repository
  → Argo CD
  → Kubernetes API
  → live cluster state
```

## Desired state and live state

```text
Desired state: what manifests in Git declare
Live state:    what Kubernetes currently runs
Argo CD:       controller that compares and reconciles them
```

If someone manually changes a Deployment, the live state differs from Git. Argo CD reports `OutOfSync` and, when self-healing is enabled, restores the declared state.

## Current controller

Argo CD is the active GitOps controller:

```text
kubernetes/gitops/argocd/
```

FluxCD documentation exists as an alternative learning path but is not the current controller for the Health Dashboard, Garmin, or Ring applications.

## Application flow

```text
1. Developer changes code or manifests.
2. GitHub Actions validates the change.
3. Code changes build and scan a container image.
4. The image is pushed to a registry.
5. CI writes the immutable digest into Kustomize.
6. GitHub Actions commits the digest to Git.
7. Argo CD detects the Git commit.
8. Argo CD renders Kustomize.
9. Argo CD compares desired and live resources.
10. Argo CD syncs Kubernetes.
11. Kubernetes performs a rollout.
```

The Health Dashboard does not require a manual image edit after every build.

## Application definitions

```text
kubernetes/gitops/argocd/applications/garmin.yaml
kubernetes/gitops/argocd/applications/ring-health-tracker.yaml
kubernetes/gitops/argocd/applications/health-dashboard.yaml
```

## AppProject

The AppProject controls:

```text
allowed source repositories
allowed destination namespaces
allowed resource kinds
```

File:

```text
kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
```

## Safe GitOps workflow

```bash
git checkout -b change/my-update
# edit files
git diff
git status
# run tests and validation
git add <files>
git commit -m "Describe the change"
git push origin change/my-update
```

After review and merge:

```bash
argocd app refresh <app> --hard
argocd app diff <app>
argocd app sync <app>
argocd app wait <app> --health --sync
```

## Sync policy

The current applications use:

```yaml
automated:
  enabled: true
  prune: false
  selfHeal: true
```

`prune: false` is intentional for stateful applications and gradual adoption. It prevents Argo CD from deleting resources simply because they are not yet represented correctly in Git.

## Drift testing

For a safe stateless test, inspect the application before changing a live resource:

```bash
argocd app get health-dashboard
argocd app diff health-dashboard
```

A manual scale change can demonstrate drift, but restore it immediately and do not use manual edits as normal operations.

## Rollback

Preferred rollback:

```text
Revert the Git commit.
Push the revert.
Allow Argo CD to sync.
```

This preserves audit history and makes the rollback reproducible.

For the full platform explanation:

```text
docs/homelab-study-guide.md
kubernetes/gitops/argocd/README.md
```
