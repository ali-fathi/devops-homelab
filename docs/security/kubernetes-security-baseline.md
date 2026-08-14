# Kubernetes Security Baseline

> **Phase 4.1 status:** Intended baseline. Do not enforce these controls globally until the read-only inventory, audit-mode policies, workload remediation, and rollback procedures are complete.

## Baseline objective

This is the target minimum for Git-managed workloads. It maps the Kubernetes Pod Security Standards `restricted` profile and CIS-style hardening practices into gradual, operationally safe controls.

```text
Observe current state -> audit violations -> remediate -> enforce by namespace -> monitor exceptions
```

## Workload baseline

| Control | Required target | Validation source | Exception handling |
|---|---|---|---|
| Non-root | `runAsNonRoot: true`; numeric non-zero UID where image supports it | Pod spec, Kyverno report | Exact workload/image exception only |
| Privilege escalation | `allowPrivilegeEscalation: false` | Container security context | No default exception |
| Linux capabilities | Drop `ALL`; add named capability only when justified | Container security context | Vendor/workload specific, time-bound |
| Root filesystem | `readOnlyRootFilesystem: true` where application supports it | Container security context | Document writable paths/volume requirement |
| Privileged mode | `privileged: false` | Container security context | Break-glass only; no general allow policy |
| Host namespaces | No `hostNetwork`, `hostPID`, `hostIPC` | Pod spec | MetalLB/Longhorn vendor resources only if proven required |
| Host paths | No `hostPath` | Pod volume spec | Exact path and controller exception only |
| Resource requests | CPU and memory requests set | Container resources | Temporary audit exception with owner/due date |
| Resource limits | CPU and memory limits set when workload-compatible | Container resources | Stateful workload review if limit creates instability |
| Image reference | No `latest`; version pin now, immutable digest after Phase 4.5 | Image string / GitOps manifest | Bootstrap exception with expiry |
| Secrets | ExternalSecret/mounted Secret reference; no literal secret material | Manifest/scan | None for production-like workloads |
| Service account | Explicit dedicated identity when API access is needed; otherwise disable token automount | Pod/service account spec | Document controller requirement |

## Namespace baseline

| Control | Target |
|---|---|
| Pod Security labels | Begin `warn`/`audit`; enforce only after compatible workload migration |
| Network policy | Application namespaces gain default-deny then explicit DNS/required flows in Phase 4.3 |
| RBAC | Dedicated ServiceAccounts, no wildcard access, no cluster-admin for applications |
| Quotas/limits | Evaluate ResourceQuota and LimitRange after actual resource inventory; do not invent values |
| Ownership | Namespace and workload owner documented in catalog/runbook |

## Platform exception classes

The following components may legitimately deviate from an application baseline, but never receive a blanket namespace exemption:

```text
MetalLB speaker: hostNetwork and NET_RAW are required for Layer 2 announcements.
Longhorn: host/device/mount-related access may be required by storage controllers.
CNI and kube-system components: host networking and privileged operations may be upstream requirements.
Admission webhooks: narrowly scoped cluster permissions may be required for certificate rotation.
```

The Phase 4.1 inventory must identify the exact live resource and spec field before an exception is proposed. An exception must not be inferred from chart names alone.

## Policy rollout order

```text
1. Require no mutable latest tag.
2. Require allowPrivilegeEscalation=false.
3. Require dropped capabilities and prohibit privileged Pods.
4. Require non-root execution.
5. Require requests/limits after capacity review.
6. Restrict host namespaces/hostPath with documented platform exceptions.
7. Verify signed images after Phase 4.5.
```

This order starts with high-signal controls and avoids breaking storage/network platform components before they are inventoried.

## Evidence and rollback

```text
Policy source, tests, PolicyReports, and exceptions are Git-managed.
Audit mode is the rollback-safe first state.
Each Enforce change has a documented affected namespace/workload list.
Rollback is a reviewed Git revert to Audit mode or a narrow exception, never a broad global disable.
Every exception has owner, ticket/reference, expiry, and removal condition.
```
