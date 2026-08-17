# Phase 4.2 Kyverno Preflight

> **Collection:** 2026-08-17
>
> **Status:** Read-only live preflight and offline Audit-policy staging complete. Kyverno is **not installed** and no admission webhook, Argo CD Application, AppProject, or policy resource has been applied.

## Live preflight evidence

| Check | Result | Decision |
|---|---|---|
| Existing Kyverno namespace | Absent | New installation path; no upgrade/migration detected. |
| Kyverno CRDs | None detected | No existing policy API ownership to preserve. |
| Kyverno webhooks | None detected | No existing webhook behavior to preserve. |
| K3s server version | `v1.35.5+k3s1` | Compatible with the selected stable Kyverno Helm chart `3.8.2` requirement of Kubernetes `>=1.25`. Revalidate before installation. |
| Nodes | Three Ready nodes | `k3s-master`, `k3s-worker1`, and `k3s-worker2` were Ready. |
| Observed node memory | Master 66%; worker1 23%; worker2 32% | Start with one replica per required Kyverno controller and explicit resource requests. Avoid control-plane affinity. |
| Post-incident GitOps health | 35 checks, 0 failures, 0 warnings | Prometheus, PVCs, application endpoints, ExternalSecrets, and all Argo CD Applications were healthy after the Longhorn incident recovery. |

The live evidence was obtained with read-only `kubectl get`, `kubectl top`, `kubectl version`, and `scripts/verify-gitops-health.sh` commands. It contains no Secret data.

## Staged, non-deployed policy source

```text
kubernetes/security/kyverno/values-audit.yaml
kubernetes/security/kyverno/policies/audit-workload-security.yaml
kubernetes/security/kyverno/application.yaml.template
```

The three staged policies have `validationFailureAction: Audit`, target only `garmin`, `health`, and `ring-health`, and cover:

```text
Explicit runAsNonRoot / allowPrivilegeEscalation=false / privileged=false
CPU and memory requests and limits
No :latest image tag
```

Expected audit findings include existing `:latest` references in the Garmin fetcher and Health Dashboard. Those reports are intentional evidence for a later remediation; they do not authorize an exception or enforcement change.

## GitOps installation design

The proposed Application template uses the pinned official Helm repository and Argo CD multiple sources so values remain in Git rather than being copied into an Application manifest:

```text
Chart source:  https://kyverno.github.io/kyverno/ (chart kyverno, 3.8.2)
Values source: this repository, kubernetes/security/kyverno/values-audit.yaml
Destination:   kyverno namespace
```

The initial values use resource requests of `100m/128Mi` for the admission controller and `100m/64Mi` for the background and reports controllers. Cleanup controller and PolicyException support remain disabled. `forceFailurePolicyIgnore` is enabled so an unavailable policy webhook cannot block API requests during audit observation.

## Required installation change

A future approved GitOps change must make these coupled changes together:

```text
1. Add https://kyverno.github.io/kyverno/ to AppProject sourceRepos.
2. Add the kyverno namespace as an AppProject destination.
3. Add only the Kyverno chart's required cluster-scoped CRD, RBAC, webhook,
   and Kyverno policy kinds to the AppProject cluster-resource whitelist.
4. Add a CI Helm render for the exact chart and values file.
5. Move the reviewed Application template into the watched applications path.
6. Sync once with prune disabled and failurePolicy Ignore.
7. Verify controller readiness, webhook failure policy, PolicyReport creation,
   and expected Audit findings before changing scope or enforcement.
```

Do not add broad cluster-resource wildcards, enable policy exceptions, change failure policy to `Fail`, or add platform namespaces in the initial change. Do not mix this work with NetworkPolicy enablement, Longhorn maintenance, Harbor, or stateful pruning.

## Remaining gates

```text
[ ] Verify Argo CD multiple-source support against the installed version.
[ ] Render Kyverno 3.8.2 and values-audit.yaml in CI.
[ ] Inventory exact chart-created cluster-scoped kinds and AppProject additions.
[ ] Approve admission-webhook installation/change window and rollback owner.
[ ] Install with automated sync disabled for the first observation cycle.
[ ] Prove Kyverno controllers and webhooks are Healthy with failurePolicy Ignore.
[ ] Review PolicyReports and remediate the first application findings.
[ ] Add Kyverno CLI policy tests to CI before any policy reaches Enforce.
```
