# Phase 4 — Platform Security and Delivery Automation

> **Status:** Planned
>
> **Goal:** Turn the homelab from a functioning GitOps platform into a controlled internal platform with policy enforcement, network isolation, protected change delivery, software supply-chain evidence, and an enterprise-style private registry path.
>
> **Prerequisite:** Phase 3 Task 3.8 remains a hard gate for stateful services. Do not install Harbor, enable stateful Argo CD pruning, or treat the platform as recoverable until `NAS-Backup-setup` is completed and the Longhorn restore rehearsal returns `[PASS]`.

## Why Phase 4 exists

Phase 3 made desired state Git-managed and observable. That alone does not prevent unsafe workloads, unrestricted lateral movement, unreviewed dependency changes, or untraceable container images.

Phase 4 adds the controls used by mature platform teams:

```text
Policy as code               -> documented, testable workload guardrails
Network segmentation         -> explicit service-to-service communication
Protected delivery           -> reviewed and reproducible changes
Supply-chain evidence        -> image scan, SBOM, provenance, and signature path
Registry governance          -> private, authenticated Harbor image distribution
Operational auditability     -> actionable security and delivery evidence
```

The objective is not to claim that a three-node homelab is a regulated enterprise production environment. The objective is to use the same control patterns, make deviations explicit, and prove the controls work before relying on them.

## Engineering principles

Every task follows these principles:

| Principle | Implementation meaning |
|---|---|
| Least privilege | Restrict Kubernetes RBAC, GitHub workflow permissions, Harbor robot accounts, cloud access, and network paths to the minimum required scope. |
| Secure by default | New namespaces begin with policy/network guardrails in audit mode, then move to enforcement only after observed compatibility. |
| Immutable, traceable artifacts | Deploy only versioned images. Generate an SBOM, scan it/image, sign it, and retain build evidence. |
| Separation of duties | GitHub Actions validates/builds; Argo CD deploys approved Git; Terraform owns bootstrap resources; operators alone approve exceptional break-glass changes. |
| Policy as code | Security controls, exceptions, and tests live in Git and go through review. No permanent console-only exemptions. |
| Evidence over assumptions | A green scan, policy report, signature verification, restore test, and alert test are recorded before marking a task verified. |
| Progressive enforcement | Observe -> remediate -> enforce -> monitor. Do not enable a broad blocking policy without an inventory and rollback path. |
| Recovery first | Backups and a tested restoration path precede stateful platform services such as Harbor. |

## Reference standards and target maturity

Phase 4 uses these as engineering references, not as unsupported compliance claims:

```text
CIS Kubernetes Benchmark                Kubernetes configuration hardening
Kubernetes Pod Security Standards       Baseline/restricted workload controls
NIST SSDF                               Secure software-development practices
SLSA Build Level 2 target               Hosted build provenance and tamper resistance
OWASP Kubernetes Top 10                Threat-model and control coverage
OpenSSF Scorecard practices             Repository and dependency hygiene
```

The target is an internal **production-like** platform: reproducible, auditable, policy-governed, and recoverable. Formal certification, 24x7 staffing, multi-region availability, and external compliance attestation are out of scope for a homelab.

## Ownership model

```text
Terraform
  -> cluster bootstrap, Longhorn, MetalLB configuration, Argo CD AppProject

Argo CD
  -> approved application and policy manifests from Git

GitHub Actions
  -> validate, scan, build, attest/sign, publish evidence; never deploy directly

Harbor
  -> authenticated OCI registry, retention, replication, vulnerability metadata

Kyverno
  -> Kubernetes admission and background policy reports

Synology NAS + Longhorn
  -> external backup target and restore evidence

Operator
  -> NAS administration, break-glass decisions, policy-exception approval,
     disaster recovery, and destructive maintenance windows
```

No controller may take ownership of another layer's resources without a documented migration and rollback plan.

## Task map

| Task | Status | Primary outcome | Key technologies | Dependency |
|---|---|---|---|---|
| **4.1** Platform security baseline | Live inventory captured; review in progress | Read-only inventory, threat model, privileged-access review, and policy rollout design | CIS, PSS, Kyverno | None; audit-only first |
| **4.2** Admission policy as code | Planned | Audit then enforce workload security standards with narrow exceptions | Kyverno, PolicyReports | 4.1 |
| **4.3** Network segmentation | Blocked: live deny-policy test failed; CNI enforcement remediation required | Default-deny application namespaces and explicit required flows | NetworkPolicy, DNS/metrics rules | 4.1 and CNI capability check |
| **4.4** CI and repository governance | Planned | Protected main, reviewed ownership, immutable action pinning, dependency updates, blocking security gates | GitHub Actions, CODEOWNERS, Dependabot/Renovate, Trivy | None |
| **4.5** Artifact supply chain | Planned | Build -> scan -> SBOM -> provenance -> sign -> verify path | Syft, Trivy/Grype, Cosign, SLSA provenance | 4.4 |
| **4.6** Harbor private registry | Blocked by Phase 3.8 | Recoverable authenticated registry with robot accounts, TLS, scan/retention/replication plan | Harbor, Longhorn, MetalLB/Ingress | Verified Synology restore |
| **4.7** GitOps promotion and deployment control | Planned | Environment overlays, controlled sync, image-digest deployment, and release evidence | Argo CD, Kustomize, GitHub Environments | 4.2, 4.4, 4.5 |
| **4.8** Security observability and response | Planned | Runtime/image findings, audit logs, SLOs, tested alerts, and incident exercises | Trivy Operator, K3s audit logs, Loki, Prometheus | 4.2, 4.3 |

## Task 4.1 — Platform security baseline

### Goal

Establish a factual baseline before enforcing controls. This task is mostly inventory, threat modelling, ownership confirmation, and audit-mode planning.

### Required work

```text
1. Record namespaces, workloads, ServiceAccounts, ClusterRoles, RoleBindings, and externally exposed Services.
2. Classify workloads as platform, application, stateful, privileged exception, or deprecated/demo.
3. Identify hostNetwork, hostPath, privileged, NET_RAW, root-user, writable-root filesystem, and missing-resource-limit usage.
4. Verify which Kubernetes NetworkPolicy implementation is active before creating enforcement policies.
5. Define the change-control and break-glass process for policy exceptions.
6. Create a risk register with remediation owner, due date, and accepted-risk expiry.
```

### Deliverables

```text
docs/security/platform-threat-model.md
docs/security/kubernetes-security-baseline.md
docs/security/policy-exception-process.md
docs/security/network-flow-inventory.md
docs/security/phase-4.1-inventory-review.md
docs/runbooks/platform-security-baseline.md
docs/runbooks/networkpolicy-enforcement-test.md
scripts/collect-platform-security-inventory.sh
scripts/verify-networkpolicy-enforcement.sh
```

The inventory script is implemented as `scripts/collect-platform-security-inventory.sh`. It is read-only, excludes Secret/ConfigMap data, annotations, Pod environment values, and raw manifests, and produces ignored local evidence only. The first live inventory was captured on 2026-08-14; its reviewed non-secret findings and remaining gates are in [Phase 4.1 Live Inventory Review](security/phase-4.1-inventory-review.md). Follow [Platform Security Baseline Collection](runbooks/platform-security-baseline.md) for repeat runs and review order.

### Validation and exit gate

```text
[ ] All namespaces and externally exposed Services are classified.
[ ] Existing privileged exceptions are documented with owner and review date.
[ ] The active NetworkPolicy enforcement capability is proven, not assumed.
[ ] No Secret data is included in the inventory.
[ ] Security findings are recorded in docs/security-findings.md.
```

## Task 4.2 — Kyverno admission policy as code

### Technology decision

Use **Kyverno** for this platform's first admission-policy engine. It is Kubernetes-native, works directly with YAML resources, supports validation/mutation/generation, produces policy reports, and can be tested in CI with `kyverno test`.

OPA/Gatekeeper remains a valid enterprise alternative. Do not run both policy engines for the same controls without a clear reason; duplicate enforcement produces confusing failures and policy drift.

### Rollout stages

```text
Stage A: Install Kyverno with pinned chart version and resource limits.
Stage B: Apply ClusterPolicies in Audit mode only.
Stage C: Review PolicyReports and remediate affected workloads.
Stage D: Add narrow, time-bound PolicyException resources where technically required.
Stage E: Enforce one policy family at a time, namespace by namespace.
Stage F: Add CI policy tests and prevent unreviewed exceptions.
```

### Initial policy families

| Policy | Desired standard | Known exception pattern |
|---|---|---|
| Pod Security Standards | `restricted` where workload-compatible | MetalLB speaker host networking/capabilities; documented vendor exception only |
| Non-root execution | `runAsNonRoot: true`; numeric non-root UID where possible | Upstream controller image proven unable to run non-root |
| Privilege escalation | `allowPrivilegeEscalation: false` | None without security review |
| Linux capabilities | Drop `ALL`; add only named requirement | MetalLB speaker `NET_RAW`, limited to its namespace/workload |
| Host namespaces and paths | No `hostNetwork`, `hostPID`, `hostIPC`, or hostPath by default | MetalLB and Longhorn vendor requirements, exact resource exception |
| Resource governance | CPU/memory requests and limits for managed workloads | Temporary audit-only exception with owner/due date |
| Image hygiene | No `latest`; allowed registries and immutable digest preferred | Bootstrap/vendor exception with review date |
| Secret hygiene | Disallow literal credentials in ConfigMaps/manifests | External Secrets / mounted Secret references only |

### Required files

```text
kubernetes/security/kyverno/application.yaml
kubernetes/security/kyverno/policies/
kubernetes/security/kyverno/exceptions/
kubernetes/security/kyverno/tests/
docs/runbooks/kyverno-policy-violation.md
```

Kyverno must be deployed through a dedicated Argo CD Application only after the AppProject permits its required CRDs, webhooks, RBAC, and namespace.

### Exit gate

```text
[ ] Kyverno pods are Healthy and admission webhooks are available.
[ ] All initial policies are Audit-only and report expected results.
[ ] Every exception is exact-resource scoped, documented, and time-bound.
[ ] CI runs policy tests against repository manifests.
[ ] At least one remediated policy moves from Audit to Enforce without platform regression.
```

## Task 4.3 — Network segmentation

### Decision rule

First validate the current K3s CNI's NetworkPolicy enforcement with a disposable test namespace. `scripts/verify-networkpolicy-enforcement.sh` implements the required isolated `reachable -> denied -> reachable` ingress test and requires `--confirm`; follow [Disposable NetworkPolicy Enforcement Test](runbooks/networkpolicy-enforcement-test.md). The 2026-08-14 live test failed because the K3s server explicitly sets `disable-network-policy: true`; controlled remediation is documented in [K3s Embedded NetworkPolicy Controller Remediation](runbooks/k3s-networkpolicy-controller-remediation.md). Do not migrate the CNI merely to obtain policies. A Cilium evaluation is a later architectural decision only if eBPF observability, encrypted pod networking, or advanced Layer 7 policy has a documented need and a tested migration plan.

### Design

```text
Namespace default-deny ingress + egress
  -> permit kube-dns/CoreDNS egress
  -> permit explicit application-to-database traffic
  -> permit Prometheus scrape paths
  -> permit Alloy/Loki telemetry paths
  -> permit Argo CD GitOps/controller paths
  -> permit approved ingress/LoadBalancer traffic
```

System namespaces are not blanket-denied initially. Begin with application namespaces and an audit-tested traffic-flow inventory.

### Required controls

```text
No unrestricted cross-namespace traffic for application workloads.
No direct database access except from declared client workloads.
No unrestricted egress from workloads that do not need it.
DNS, metrics, log shipping, GitOps, and External Secrets flows explicitly allowed.
Network-policy tests prove both required allow and unwanted deny behavior.
```

### Exit gate

```text
[ ] Default-deny is enforced in at least one non-critical application namespace.
[ ] Health dashboard, Garmin, Ring, monitoring, and logging traffic dependencies are documented.
[ ] Prometheus, Loki, Alloy, and Argo CD health checks still pass.
[ ] A rollback command exists for each policy bundle.
```

## Task 4.4 — CI and repository governance

### Required controls

```text
Protected main branch: pull request, required checks, and no force push.
CODEOWNERS: infrastructure, security policies, Terraform, GitHub workflows, and runbooks have reviewers.
GitHub Actions: minimum permissions, immutable commit-SHA action pinning, and restricted secrets.
Dependency automation: Dependabot or Renovate creates reviewable update PRs.
IaC scanning: Trivy CRITICAL/HIGH findings fail the required check after documented narrow exceptions.
Secret scanning: Gitleaks remains blocking; a real secret means rotate first, then remove.
Reusable workflows: centralize validation/build/signing behavior instead of duplicating it per app.
```

`trivy config` currently uploads findings for review. Phase 4 changes this progressively: first remove high-signal remediable findings, then make the security job blocking. Vendor exceptions must stay path-scoped and expire; never exclude a whole source tree to make CI green.

### Exit gate

```text
[ ] Main cannot merge without required validation, security, and review checks.
[ ] Workflow action references are immutable SHA pins with update automation.
[ ] Dependency update PRs are generated on a defined schedule.
[ ] A deliberately vulnerable/misconfigured fixture proves the security gate blocks a merge.
[ ] Break-glass bypasses are logged and reviewed.
```

## Task 4.5 — Artifact supply chain

### Target delivery path

```text
Source commit
  -> unit/integration tests
  -> reproducible container build
  -> image vulnerability scan
  -> SPDX or CycloneDX SBOM
  -> SLSA-compatible build provenance / GitHub attestation
  -> Cosign keyless signature using GitHub OIDC
  -> publish immutable image digest
  -> Argo CD deploys image digest, not a mutable tag
  -> Kyverno verifies signature/attestation before admission
```

### Technology choices

| Concern | Selected technology | Reason |
|---|---|---|
| Image and filesystem scan | Trivy | Already used in this repository; supports CI, IaC, image, SBOM, and operator use cases. |
| SBOM | Syft | Mature SPDX/CycloneDX generation and broad OCI support. |
| Signature | Cosign keyless signing with GitHub OIDC | Avoids long-lived signing keys in GitHub secrets and provides identity-bound transparency-log evidence. |
| Provenance | GitHub artifact attestations/SLSA-compatible provenance | Ties published artifact digest to a protected build workflow and source commit. |
| Admission verification | Kyverno `verifyImages` | Enforces the trust policy at Kubernetes admission rather than relying only on CI convention. |

Image tags may remain human-readable release labels, but Argo CD manifests must resolve to immutable digest references after this task is enforced.

### Exit gate

```text
[ ] One non-critical application image has an SBOM, scan result, provenance, and Cosign signature.
[ ] Signature verification rejects an unsigned test image in a controlled namespace.
[ ] The same signed digest deploys through Argo CD successfully.
[ ] No signing private key is stored in GitHub Secrets.
```

## Task 4.6 — Harbor private registry

### Hard prerequisite

```text
Phase 3 NAS-Backup-setup complete
Longhorn Synology backup/restore rehearsal passed
Harbor-specific storage, database, and registry recovery plan approved
```

### Harbor design

```text
Harbor core, portal, jobservice, registry, Trivy adapter
  -> Longhorn PVCs
  -> PostgreSQL and Redis state
  -> TLS endpoint through the selected ingress path
  -> authenticated users and least-privilege robot accounts
  -> project quotas, retention, vulnerability scan, audit logs
  -> optional replication to a second registry or off-site target
```

Harbor is a stateful security service, not merely a Docker cache. Its PostgreSQL, Redis, registry storage, and configuration require an application-specific restore rehearsal after the generic Longhorn test passes.

### Required controls

```text
Dedicated Harbor project per trust boundary/team.
Robot account per CI workload with project-scoped push/pull permissions.
No administrator credentials in Git or CI logs.
TLS required for registry clients; do not use insecure registry configuration.
Immutable tag rule for promoted release repositories.
Retention policy protects active digests and does not delete deployed images.
Trivy scanning enabled with severity policy and remediation workflow.
Audit logs retained and shipped to Loki where practical.
Replication/second-copy plan documented before Harbor becomes a primary registry.
```

### Exit gate

```text
[ ] Harbor is restored successfully to a new test namespace or test instance.
[ ] CI pushes only with a project-scoped robot account.
[ ] Pull, scan, SBOM attach, signature, and digest deployment work end to end.
[ ] Harbor retention cannot remove an image currently referenced by GitOps manifests.
[ ] Registry credentials are rotated through the approved secret-management path.
```

## Task 4.7 — GitOps promotion and deployment control

### Desired promotion model

```text
feature branch
  -> PR validation, policy test, scan, SBOM, signature evidence
  -> protected main
  -> development overlay / controlled sync
  -> promotion pull request with immutable image digest
  -> production-like overlay / approval gate / controlled sync
```

The homelab may use `development` and `production-like` rather than claim a real production environment. The controls are still valuable: the promoted digest must be identical, and environment differences must be explicit Kustomize overlays rather than ad-hoc live edits.

### Required controls

```text
Separate base and environment-overlay directories.
Argo CD projects restrict sources, destinations, and cluster resources.
Sync windows/maintenance controls for stateful services.
GitHub Environment approval for production-like promotion.
Argo CD notifications/status evidence linked to the deployment commit.
No direct kubectl deployment except documented bootstrap or break-glass procedure.
```

### Exit gate

```text
[ ] A non-critical application is promoted using the same signed digest across two overlays.
[ ] Approval and commit evidence identify who approved the promotion.
[ ] Rollback is a Git revert to a known good digest.
[ ] Argo CD and post-sync health-gate evidence are attached to the release record.
```

## Task 4.8 — Security observability and response

### Controls

```text
Trivy Operator or equivalent reports running-image vulnerabilities and Kubernetes misconfigurations.
K3s audit logs record high-value API activity and are shipped/retained securely.
Prometheus alerts on backup target unavailable, backup failure/freshness, PVC/volume degradation, policy violations, and certificate expiry.
Blackbox probes verify critical internal endpoints from a controlled location.
Alertmanager delivery is tested with a documented synthetic alert.
Runbooks cover policy denials, image verification denials, Harbor outage, backup failure, and node compromise triage.
```

Runtime tools must be introduced with resource sizing and RBAC review. A monitoring agent that is unavailable, over-privileged, or unactionable is not a security control.

### Exit gate

```text
[ ] At least one image/vulnerability finding and one policy violation are visible through the approved response path.
[ ] Audit-log access is restricted and retention is documented.
[ ] Backup freshness/target failure alert is tested after Synology setup.
[ ] An incident tabletop exercise validates a runbook and escalation path.
```

## Phase 4 implementation order

```text
4.1 Baseline and threat model
  -> 4.2 Kyverno audit policies
    -> 4.3 application network policies
      -> 4.4 repository and CI governance
        -> 4.5 signed artifact path
          -> 4.6 Harbor after NAS restore proof
            -> 4.7 promotion controls
              -> 4.8 security observability and response
```

Tasks 4.1, 4.2 audit mode, and 4.4 can begin before the NAS is configured. Task 4.6 is explicitly blocked. Task 4.8 backup-freshness alerting is partially blocked until the target exists.

## Phase 4 completion criteria

```text
[ ] Security baseline, threat model, and policy-exception process are reviewed.
[ ] Kyverno policies are enforced for at least the remediated baseline set.
[ ] Application namespaces have tested default-deny network segmentation.
[ ] Main branch has required review, validation, and security gates.
[ ] Dependency update automation is active.
[ ] One application follows the complete signed-image digest deployment path.
[ ] Synology restore rehearsal has passed before Harbor is installed.
[ ] Harbor has a tested application-level restore path.
[ ] GitOps promotion uses immutable digests and approval evidence.
[ ] Security, backup, and platform alerts have tested response runbooks.
```

## Related roadmap

The enterprise-style sequence after this phase is in:

```text
docs/enterprise-devops-roadmap.md
```
