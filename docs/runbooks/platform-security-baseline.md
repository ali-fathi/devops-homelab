# Runbook: Platform Security Baseline Collection

Use this runbook to establish the factual input for Phase 4.1. It is read-only and safe to run before Kyverno, NetworkPolicies, Harbor, or admission enforcement are installed.

## Script

```text
scripts/collect-platform-security-inventory.sh
```

## Safety boundary

The script does not invoke `apply`, `create`, `patch`, `delete`, `rollout`, `exec`, Helm, Terraform, or Argo CD synchronization commands. It does not query Kubernetes Secret or ConfigMap data, preserve annotations, Pod environment variables, or raw manifests.

The report contains names, namespaces, image references, security-context fields, RBAC rules/bindings, exposed-Service metadata, NetworkPolicy metadata, CNI discovery evidence, and Kubernetes version information. Treat it as internal operational metadata and keep it on the operator workstation.

## Run

Confirm the active Kubernetes context:

```bash
kubectl config current-context
```

Run the inventory from the repository root:

```bash
./scripts/collect-platform-security-inventory.sh
```

Expected completion:

```text
[PASS] Read-only platform security inventory collected.
[INFO] Report directory: .../artifacts/platform-security-baseline/<run-id>
```

Review the summary first:

```bash
find artifacts/platform-security-baseline -name summary.json -print -exec jq . {} \;
```

## Review sequence

```text
1. summary.json: count exposures and security-context exceptions.
2. services.json: classify every LoadBalancer, NodePort, and external-IP Service.
3. pods.json: confirm host network, host path, privilege, added capabilities, root, and resource gaps.
4. clusterroles.json, roles.json, and bindings: identify wildcard or unexpected access.
5. networkpolicies.json and cni-pods.json: prepare the enforcement-capability test.
6. Record findings in docs/security-findings.md.
7. Update the threat model, baseline, and network-flow inventory with observed evidence.
```

## Required classification

For every externally exposed Service, record one of:

```text
Required internal LAN endpoint
Required private tunnel endpoint
Temporary/demo endpoint with expiry
Deprecated endpoint to remove
Needs investigation
```

For every privileged/host-network/host-path/capability exception, record:

```text
Exact workload and namespace
Technical requirement/evidence
Owner
Policy control affected
Expiry/review date
Removal condition
```

Do not create Kyverno exceptions or NetworkPolicies solely from this inventory. The next task validates expected traffic and policy compatibility in audit/disposable test mode.

## Failure handling

| Symptom | Meaning | Safe action |
|---|---|---|
| `kubectl` unavailable | Operator environment is incomplete | Use the DevContainer or install the approved CLI; do not bypass with copied credentials. |
| `Forbidden` for a resource | Current operator identity lacks read access | Use an approved operator identity or record the missing visibility; do not grant broad permissions to the script. |
| Kubernetes API unreachable | Context, network, Tailscale, or cluster issue | Resolve access first; the script makes no changes. |
| Empty CNI discovery | Discovery is not proof of no enforcement | Use the future disposable NetworkPolicy test before policy rollout. |

## Next step

After a reviewed live inventory, update Phase 4.1 evidence and begin Task 4.2 with Kyverno in Audit mode only. Do not install Harbor until the NAS backup/restore gate is verified.
