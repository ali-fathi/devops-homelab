# Kyverno Audit-Only Policy Source

This directory stages the Phase 4.2 Kyverno configuration before installation. It is deliberately outside the root Argo CD Application's watched `kubernetes/gitops/argocd/applications/` directory, so committing these files does **not** install Kyverno, create admission webhooks, or apply policies.

## Contents

```text
values-audit.yaml                 Conservative initial Helm values
policies/audit-workload-security.yaml
                                  Three Audit-only ClusterPolicies
application.yaml.template         Future Argo CD Application; not deployable as-is
```

The initial policies target only the application namespaces `garmin`, `health`, and `ring-health`:

```text
Explicit non-root / no privilege escalation / non-privileged container security context
CPU and memory requests and limits
No mutable :latest image tag
```

Platform namespaces, Longhorn, MetalLB, K3s, monitoring, logging, and `kube-system` are intentionally out of scope. No PolicyException resource is present; exceptions are unavailable until the documented exception process and audit evidence justify an exact scope.

## Current safety properties

```text
All policy actions are Audit, never Enforce.
No mutation or generation rules exist.
The planned chart values force webhook failurePolicy Ignore.
Cleanup controller and PolicyException support are disabled.
The first resource footprint is one admission, background, and reports replica.
No file in this directory is currently reconciled by Argo CD.
```

## Installation gate

Do not move `application.yaml.template` into the watched applications directory or enable automated sync until all conditions are true:

```text
[ ] K3s version and node resource headroom are recorded.
[ ] Existing Kyverno CRDs/webhooks are absent or an upgrade plan is approved.
[ ] Platform GitOps health gate passes after the latest storage incident.
[ ] AppProject changes are reviewed with the exact Kyverno source, destination,
    CRDs, RBAC, webhook, and Kyverno policy kinds required by the chart.
[ ] The chart and values render successfully at the pinned version in CI.
[ ] A webhook availability/rollback observation window is approved.
[ ] The initial audit scope and expected violations are documented.
```

The 2026-08-17 preflight has satisfied the first three gates; all remaining gates are intentionally open.

## Related documentation

```text
docs/security/phase-4.2-kyverno-preflight.md
docs/security/kubernetes-security-baseline.md
docs/security/policy-exception-process.md
docs/runbooks/kyverno-policy-violation.md
```
