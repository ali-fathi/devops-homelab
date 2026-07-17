# FluxCD Study Notes

This directory documents FluxCD as an alternative GitOps controller.

The active GitOps controller in this homelab is Argo CD:

```text
kubernetes/gitops/argocd/
```

FluxCD is not currently the controller deploying the Health Dashboard, Garmin, or Ring applications. Do not install both controllers to manage the same resources without an explicit ownership plan.

For the complete platform study guide:

```text
docs/homelab-study-guide.md
```

## GitOps concept

Both Argo CD and FluxCD implement the same high-level model:

```text
Git desired state
  → GitOps controller
  → Kubernetes reconciliation
```

The controller watches Git, renders manifests, compares live state, and applies changes.

## Tool ownership rule

Use one controller for a resource set:

```text
Argo CD → current homelab applications
FluxCD  → future isolated experiment only
```

Never allow Argo CD and FluxCD to fight over the same Deployment, Service, or namespace.

## Learning exercise

Before experimenting with FluxCD:

```text
Create a separate namespace.
Use a separate test application.
Use a separate Git path.
Disable automatic pruning initially.
Document ownership.
Remove the experiment after testing.
```

Compare the controllers using:

```text
installation model
source authentication
manifest rendering
health reporting
sync policies
rollback behavior
secret handling
```
