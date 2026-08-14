# Kubernetes Policy Exception Process

> Applies to future Kyverno admission policies, Pod Security labels, NetworkPolicy exceptions, image-verification exceptions, and equivalent platform security controls.

## Default rule

A policy exception is a temporary, narrowly scoped engineering decision. It is not a way to silence a failed deployment or turn off a control for a whole namespace.

```text
Remediate first.
Use Audit mode while compatibility is understood.
Add an exception only when the exact required deviation is proven.
Set an owner, expiry, and removal condition.
Review and remove it.
```

## Required exception record

Each exception must be represented in Git and contain:

| Field | Requirement |
|---|---|
| Policy/control | Exact Kyverno policy or security control name |
| Scope | Exact resource kind/name/namespace; selector scope only when unavoidable |
| Reason | Technical requirement, not "it fails" |
| Evidence | Upstream documentation, issue, test output, or architecture record |
| Owner | Named responsible operator/team |
| Expiry | Calendar date; no indefinite exception |
| Removal condition | Version upgrade, migration, or configuration change that will remove it |
| Review | Link to `docs/security-findings.md` or tracked issue |

## Approval workflow

```text
1. Confirm the finding is real and identify the exact affected resource.
2. Check whether workload configuration can meet the policy instead.
3. Create a proposed time-bound exception in Git.
4. Review the exception as a security-sensitive change.
5. Keep policy in Audit or use exact exception while remediation proceeds.
6. Verify unrelated workloads remain enforced.
7. Review before expiry; remove or renew with new evidence.
```

## Prohibited exception patterns

```text
Namespace-wide exemption for convenience
Cluster-wide wildcard policy bypass
No owner or no expiry
Exception containing secret values
Console-only exception not represented in Git
Exception that bypasses image signature verification for all images
Permanent hostNetwork, privileged, hostPath, or cluster-admin exception without exact resource scope
```

## Break-glass changes

A genuine incident may require a temporary operator action outside normal GitOps. Record it immediately after service restoration:

```text
Timestamp and operator
Reason and impact
Exact command/resource change
Evidence that normal controls were restored
Follow-up Git change or incident issue
Expiry/review date
```

Break-glass is not a normal deployment method. CI still does not receive direct cluster write access.

## Existing examples

```text
MetalLB speaker requiring NET_RAW and hostNetwork for Layer 2 advertisement
MetalLB validating-webhook certificate rotation access, scoped to one named resource
Longhorn storage-controller host/device requirements, after live inventory confirms them
```

These examples require separate exception records once Kyverno policies are introduced. Existing Trivy documentation does not automatically create a Kyverno exception.
