# Runbook: Kyverno Audit Policy Violation

This runbook applies only after the Phase 4.2 Kyverno installation gate is approved and Kyverno is running in Audit mode. It does not authorize changing a policy to Enforce, creating a broad exception, or making a live workload change outside GitOps.

## First response

```text
1. Confirm the policy remains Audit and identify the exact policy/rule/resource.
2. Determine whether the report is current and whether the workload is GitOps-managed.
3. Remediate the manifest through Git where possible.
4. Use a narrowly scoped, time-bound exception only after the documented process.
5. Recheck the policy report and GitOps health after the next approved sync.
```

Never silence an audit finding by disabling Kyverno, altering a report, creating a namespace-wide bypass, or granting a workload cluster-admin.

## Read-only triage

List policy reports without printing Secrets:

```bash
kubectl get policyreport,clusterpolicyreport -A
```

Inspect one namespaced report:

```bash
kubectl get policyreport -n <namespace> <report-name> -o json | jq '{scope:.scope,summary:.summary,results:[.results[]? | {policy,rule,result,severity,message,resources}]}'
```

Inspect the policy action and matched scope:

```bash
kubectl get clusterpolicy <policy-name> -o json | jq '{name:.metadata.name,validationFailureAction:.spec.validationFailureAction,background:.spec.background,rules:[.spec.rules[] | {name:.name,match:.match,exclude:.exclude}]}'
```

Confirm the owning Argo CD Application before changing a Git-managed workload:

```bash
kubectl get application -n argocd -o json | jq -r '.items[] | select(.status.resources[]? | .kind == "Deployment" and .namespace == "<namespace>" and .name == "<workload>") | .metadata.name'
```

## Remediation patterns

| Audit rule | Preferred Git remediation | Do not do |
|---|---|---|
| Container security context | Set explicit `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, and `privileged: false`; verify the image supports non-root execution | Set a namespace-wide policy exclusion or change the running Pod directly |
| Missing CPU/memory resources | Add evidence-based requests/limits; schedule stateful workload updates in an approved window | Invent limits without observation or restart stateful workloads incidentally |
| Mutable `:latest` tag | Replace with a tested versioned tag; use an immutable digest after Phase 4.5 | Use an exception as a permanent tag-management strategy |

## Exception process

If remediation is technically impossible, follow `docs/security/policy-exception-process.md` before proposing any exception. The exception must identify the exact policy, rule, namespace, resource, owner, evidence, expiry, and removal condition. During the first audit rollout, PolicyException support remains disabled; record the proposal and keep the policy in Audit.

## Escalation and rollback

| Symptom | Meaning | Safe action |
|---|---|---|
| Audit reports appear | Expected observation behavior | Review and remediate through Git; do not treat this as an outage. |
| Kyverno controllers are unavailable | Admission-policy control plane is unhealthy | Do not change policy actions. Verify webhook failure policy remains `Ignore`, investigate controller health, and use the approved rollback Git revert if required. |
| API requests are unexpectedly denied | Failure policy or an Enforce policy may exist | Stop rollout, identify the policy/webhook, and follow the approved rollback; do not delete CRDs, webhooks, or controller resources manually. |
| Stateful workload would restart | Policy remediation has a storage availability consequence | Defer until restore proof and a maintenance window; keep Audit mode. |

## Exit evidence for Audit mode

```text
Policy source and tests are committed.
Kyverno controller/webhook health is recorded.
Expected audit findings are reviewed.
Each remediation is a Git change with post-sync health evidence.
No broad exemption or platform namespace scope has been introduced.
```
