# Platform Threat Model

> **Phase 4.1 status:** Initial design complete; validate assumptions against the live read-only inventory before treating this as a verified threat model.

## Scope

This threat model covers the K3s homelab platform, its GitOps control plane, CI, private-network access, future Harbor registry, external secret synchronization, Longhorn storage, and the planned Synology backup target.

It does not claim to model the Synology DSM operating system, home-router firmware, GitHub infrastructure, Azure control plane, or third-party Helm/chart source code in full. Those remain external dependencies that require patching, least-privilege access, and vendor security monitoring.

## Protected assets

| Asset | Why it matters | Primary protections |
|---|---|---|
| Kubernetes API credentials | Can control the cluster | Read-only CI ServiceAccount, local operator access, revocation, no kubeconfig in Git |
| GitHub repository and `main` | Defines desired state and automation | Protected-branch/review plan, Gitleaks, CI validation, code ownership |
| Argo CD control plane | Deploys Git desired state | AppProject restrictions, Git source control, health checks, no CI deploy credentials |
| Azure Key Vault secrets | External integrations and credentials | External Secrets Operator, least-privilege cloud identity, no secret values in Git |
| Longhorn volumes and backups | Stateful application data | Replication, Synology external target, tested restore, no stateful pruning before proof |
| Synology NFS backup share | Recovery evidence and data | Dedicated share, NFSv4.1, node-only ACL, NAS second-copy plan |
| Future Harbor registry | Trusted image distribution | TLS, robot accounts, scan, retention, signature verification, restore test |
| Observability data | Security/operational investigation | Restricted access, retention design, integrity of alerting configuration |

## Trust boundaries

```text
GitHub contributor / pull request
  -> GitHub Actions validation and build boundary
  -> protected main boundary
  -> Argo CD Git source and Kubernetes admission boundary
  -> Kubernetes namespace / NetworkPolicy boundary
  -> workload, Longhorn, and external-secret boundary
  -> LAN boundary to Synology and other internal services
  -> Azure Key Vault / external internet boundary
```

A change crossing a trust boundary requires reviewable Git, least privilege, and a testable rollback path. A controller should not receive broad access merely because it is internal.

## Threat scenarios and controls

| Threat | Likely path | Existing/Phase 4 control | Evidence required |
|---|---|---|---|
| Secret leaks to Git or logs | Manifest, shell history, CI output | Gitleaks, External Secrets, no-secret script design | Scan result; no Secret values in artifacts |
| Malicious or unsafe workload | PR introduces privileged/root/host access Pod | Kyverno audit -> enforce, PSS baseline, review | PolicyReport and policy test |
| Lateral movement | Compromised Pod reaches unrelated Service | Default-deny NetworkPolicy and explicit egress | Connectivity deny/allow test |
| CI credential misuse | Workflow token gains cluster write access | Read-only Terraform CI RBAC; Argo deploys Git | `auth can-i` proof, workflow permissions review |
| Compromised image | Vulnerable or substituted image is deployed | Scan, SBOM, provenance, Cosign signature, digest deployment | Signed digest and admission-verification test |
| Registry credential overreach | Shared admin credentials used by builds | Harbor project-scoped robot account per CI path | Harbor audit event and permission test |
| GitOps blast radius | Bad desired state syncs widely | AppProject restrictions, overlays, health gates, sync controls | Argo diff and post-sync health evidence |
| Data loss | Node/volume/cluster failure | Longhorn replication, Synology backup, restore rehearsal | Successful checksum and workload-specific restore |
| Backup compromise | NAS share broadly writable/deleted | Dedicated share, node ACL, Longhorn retention ownership, second copy | Synology ACL review and restore evidence |
| Undetected security event | No actionable telemetry/audit trail | Security observability, audit logs, tested alerts | Alert and incident tabletop evidence |

## Threat assumptions to validate

```text
The private LAN is not automatically trusted; node-only NAS ACLs still matter.
GitHub Actions runners reach the private cluster only through the documented Tailscale route.
The active CNI may enforce NetworkPolicy, but this must be proven with a test.
Upstream charts can require privileged/network exceptions; each must be exact and time-bound.
Longhorn replication is not a backup and does not replace Synology restore proof.
Harbor will be a stateful dependency and must not be installed before recovery is proven.
```

## Risk treatment

Every identified issue belongs in `docs/security-findings.md` as one of:

```text
Fix now
Fix later with owner/date
Accepted risk with narrow rationale and review expiry
False positive with narrow scanner scope
Needs investigation
```

A policy exception is not an accepted risk by itself. It must reference a specific workload/control, have an owner and expiry, and be removed once the exception is no longer required.

## Review cadence

```text
After a new platform controller, external endpoint, or stateful workload
After a material RBAC, network, registry, or secret-management change
After a security incident or failed recovery drill
At least quarterly during backup/restore review
```
