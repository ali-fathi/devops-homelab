# Phase 4.1 Live Inventory Review

> **Collection:** 2026-08-14
>
> **Report ID:** `20260814143740-27325`
>
> **Status:** Initial live inventory collected. Privileged-access and exposure/RBAC review remains in progress; do not enforce Kyverno or broad NetworkPolicies yet.

## Collected baseline

The read-only collector completed successfully against Kubernetes context `default`. The full redacted workstation evidence remains outside Git under:

```text
artifacts/platform-security-baseline/20260814143740-27325/
```

| Measure | Observed value | Interpretation |
|---|---:|---|
| Namespaces | 13 | Classify each namespace as platform, application, stateful, or temporary. |
| Running/observed Pods | 65 | Inventory includes live Pod security context; rerun before enforcement because Pods change. |
| Externally exposed Services | 6 | Every LoadBalancer/NodePort/external-IP Service needs owner and exposure classification. |
| NetworkPolicies | 4 | Existing policy count is not proof of enforcement or sufficient segmentation. |
| ClusterRoles | 93 | Expected with Kubernetes/controllers; review high-risk wildcard/binding paths rather than treating count as a finding. |
| Containers without requests | 61 | Capacity/reliability governance review required. |
| Containers without limits | 69 | Capacity/reliability governance review required; do not impose global limits without workload testing. |
| Detected CNI Pods | 0 | Inconclusive. K3s can run network components as integrated processes; a disposable allow/deny test is required before relying on NetworkPolicy. |

## Observed platform exceptions

The first inventory found host access and added Linux capabilities in platform namespaces only. These are expected candidates for exact future policy exceptions, not automatically approved permanent exceptions.

| Component | Observed behavior | Initial assessment | Required follow-up |
|---|---|---|---|
| MetalLB speaker | Three Pods use `hostNetwork`; speaker adds `NET_RAW` | Expected for Layer 2 advertisements | Confirm chart/version and create an exact Kyverno exception after audit policy exists. |
| Prometheus node exporter | Three Pods use `hostNetwork` and host paths (`proc`, `sys`, `root`) | Expected for node-level host metrics | Restrict to the generated node-exporter workload; verify read-only mounts and chart security settings. |
| Longhorn | CSI, manager, engine-image, and instance-manager Pods use host paths; Longhorn engine/CSI/manager Pods are privileged; CSI adds `SYS_ADMIN` | Expected class of storage-driver requirement, but highest local node-escape blast radius | Verify against Longhorn 1.12.0 documentation, scope exact policy exceptions, retain separate upgrade/restore testing. |
| CoreDNS | Adds `NET_BIND_SERVICE` | Expected to bind DNS service port | Exact platform exception if policy requires drop-all capabilities. |

No application namespace privilege, host networking, host paths, or added capability was shown in this summary. That conclusion must be rechecked from `pods.json` before policy enforcement because the summary is not a long-term source of truth.

## Security interpretation

```text
Expected vendor privilege is not the same as safe-by-default application access.
Longhorn and node-level monitoring are intentionally powerful platform components.
Application workloads should not inherit their exceptions.
Kyverno must begin in Audit mode and target application namespaces first.
NetworkPolicy must be proven with a disposable connectivity test before deployment.
```

The Longhorn results reinforce the Phase 3 decision to defer stateful pruning until the Synology restore rehearsal passes. Storage components require privileged node integration and must have a tested recovery path before major policy or upgrade changes.

## Required review commands

Classify the six externally exposed Services:

```bash
jq . artifacts/platform-security-baseline/20260814143740-27325/services.json
```

Group containers missing resource requests or limits by namespace:

```bash
jq '[.[] | . as $pod | $pod.containers[] | select((.resourceRequests | length) == 0 or (.resourceLimits | length) == 0) | $pod.namespace] | sort | group_by(.) | map({namespace: .[0], containers: length})' artifacts/platform-security-baseline/20260814143740-27325/pods.json
```

List containers that may run as root or do not explicitly set non-root execution:

```bash
jq -r '.[] | . as $pod | $pod.containers[] | select(.runAsNonRoot != true) | "\($pod.namespace)/\($pod.name) \(.containerType):\(.name) runAsNonRoot=\(.runAsNonRoot) runAsUser=\(.runAsUser)"' artifacts/platform-security-baseline/20260814143740-27325/pods.json
```

Review NetworkPolicy coverage without printing Secret data:

```bash
jq . artifacts/platform-security-baseline/20260814143740-27325/networkpolicies.json
```

## Remaining Phase 4.1 gates

```text
[ ] Classify all six external Services and identify owner/exposure purpose.
[ ] Review wildcard/high-risk ClusterRole and binding assignments.
[ ] Group and prioritize missing resource requests/limits.
[ ] Confirm the active CNI and prove NetworkPolicy allow/deny behavior in a disposable namespace.
[ ] Verify Longhorn, MetalLB, node-exporter, and CoreDNS exception scope/version evidence.
[ ] Add concrete findings, owners, dates, and decisions to docs/security-findings.md.
[ ] Update this review after the above evidence is collected.
```
