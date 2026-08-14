# Runbook: Disposable NetworkPolicy Enforcement Test

## Purpose

This test proves whether the active cluster networking implementation enforces Kubernetes `NetworkPolicy` ingress rules. Resource existence is not proof of enforcement: a CNI may not implement policies, may be disabled, or may require a configuration change.

This is the Phase 4.1 gate before NetworkPolicy rollout. It is independent of Kyverno and must pass before a policy is used to protect an application, an administration UI, or a data API.

## Safety boundary

`scripts/verify-networkpolicy-enforcement.sh` is **mutating**, unlike the Phase 4.1 inventory collector. It requires `--confirm` and creates only:

```text
One unique namespace: networkpolicy-probe-<UTC-run-id>
One BusyBox HTTP server Pod
One BusyBox HTTP client Pod
One deny-ingress NetworkPolicy
One client-only allow NetworkPolicy
One ignored, non-secret local evidence directory
```

It never reads Secret or ConfigMap data, annotations, Pod environment values, or application manifests. It never changes an existing namespace, Service, workload, NetworkPolicy, Helm release, Argo CD Application, Terraform resource, or Longhorn volume.

It deletes its unique namespace on success, failure, or interruption. If cleanup fails, the script exits non-zero and prints the exact test namespace to remove only after investigation.

## Test sequence

```text
1. Create the isolated namespace and two labelled BusyBox Pods.
2. Confirm client-to-server HTTP succeeds without a policy.
3. Apply deny-all ingress for the server Pod and confirm client HTTP fails.
4. Apply an ingress rule allowing only the labelled client on TCP/8080.
5. Confirm client HTTP succeeds again.
6. Delete the isolated namespace.
```

A pass proves the CNI enforces a basic Pod-label ingress allow/deny rule. It does **not** prove application policies are correct, validate egress policy, replace firewall controls, or authorize a default-deny rollout.

## Prerequisites

```text
kubectl is authenticated to the intended cluster context.
The operator may create/delete namespaces and create Pods, NetworkPolicies, and Pod exec sessions in the temporary namespace.
The configured BusyBox-compatible image can be pulled by cluster nodes.
No existing application is used as a test target.
```

Confirm the context first:

```bash
kubectl config current-context
```

Read the script before execution:

```bash
sed -n '1,260p' scripts/verify-networkpolicy-enforcement.sh
```

## Run

Run from the repository root:

```bash
./scripts/verify-networkpolicy-enforcement.sh --confirm
```

The default image is `busybox:1.36`, which is already used by the Garmin InfluxDB ownership-init manifest. To use a different approved BusyBox-compatible image, pass an explicit image reference:

```bash
./scripts/verify-networkpolicy-enforcement.sh --confirm --image <approved-busybox-compatible-image>
```

Expected success sequence:

```text
[PASS] baseline_without_policy: reachable
[PASS] deny_ingress_policy: denied
[PASS] client_allow_policy: reachable
[PASS] NetworkPolicy ingress enforcement is proven by a disposable allow/deny test.
[INFO] Cleaning up isolated namespace: networkpolicy-probe-...
```

## Evidence

The script writes only timestamps, Kubernetes context, selected image reference, and pass/fail state to:

```text
artifacts/networkpolicy-enforcement/<run-id>/
```

This directory is ignored by Git. Review it locally; record only non-secret conclusions in:

```text
docs/security/phase-4.1-inventory-review.md
docs/security-findings.md
```

## Failure handling

| Result | Meaning | Safe response |
|---|---|---|
| Baseline is denied | Pod networking, image startup, or operator access is broken before policy application | Inspect only the disposable namespace and Pod events; do not infer CNI enforcement. |
| Deny policy remains reachable | The active CNI does not enforce this policy or its enforcement is misconfigured | Do not deploy default-deny/application NetworkPolicies. Identify the CNI implementation and configuration first. |
| Allow policy remains denied | Policy is enforcing, but the test selector/traffic path needs investigation | Keep the test isolated; inspect the test namespace, CNI logs, and CNI documentation. |
| Namespace cleanup fails | A test namespace remains | Record its exact generated name, inspect finalizers/events, and delete only that namespace after the cause is understood. |
| Image pull fails | Nodes cannot pull the selected test image | Use an approved image already available to every node; do not use an application Pod as a substitute. |

## What not to do

```text
Do not run this without --confirm.
Do not adapt it to label, exec into, or add policies to application namespaces.
Do not treat a failed deny test as permission to apply more policies.
Do not leave a test namespace intentionally for convenience.
Do not add a broad CNI exception or disable policy enforcement to make the test pass.
Do not start Kyverno enforcement from this result; Kyverno remains Audit-only first.
```

## Exit gate

Phase 4.1 can mark NetworkPolicy capability as proven only when the test exits zero and all three states are observed in order:

```text
reachable → denied → reachable
```

Then document the CNI enforcement conclusion and proceed with audit-first, namespace-scoped NetworkPolicy design. Existing external Service and privileged-RBAC findings remain independently open until their documented review decisions are complete.
