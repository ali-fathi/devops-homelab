# Enterprise-Style DevOps Roadmap

> This roadmap turns the homelab into a production-like internal platform through progressive, evidenced controls. It deliberately avoids adopting technology merely because large companies use it. Every component must have a clear threat model, owner, resource budget, operational runbook, upgrade path, and restore path.

## Current position

```text
Phase 1  Operator workstation and baseline automation       complete
Phase 2  Terraform bootstrap ownership and CI planning       complete with documented safety boundaries
Phase 3  GitOps maturity and health gates                    implemented; Synology restore rehearsal pending
Phase 4  Platform security and delivery automation           planned
Phase 5  Resilience, operations, and data governance         planned
Phase 6  Internal developer platform and service delivery    planned
Phase 7  Scale, zero trust, and advanced assurance            conditional/planned
```

The current NAS setup resume point is:

```text
docs/runbooks/NAS-Backup-setup.md
```

## Enterprise control model

```text
Plan and review
  -> build and validate
  -> scan and produce evidence
  -> sign immutable artifact
  -> approve promotion
  -> GitOps deployment
  -> admission verification
  -> runtime observation
  -> backup and recovery evidence
  -> post-incident learning
```

No single tool provides this chain. GitHub Actions, Argo CD, Kyverno, Harbor, Longhorn, Synology, Prometheus, Loki, and operational runbooks each cover a defined part of it.

## Technology selection rules

Before adding a platform component, answer these questions in an ADR or task design:

```text
What concrete risk or manual operation does it remove?
Who owns upgrades, credentials, RBAC, and incident response?
What is the resource footprint on the five-node cluster?
What happens when it is unavailable?
How is its state backed up and restored?
Can an existing component safely provide the same control?
How is it tested in CI and in the live cluster?
```

Avoid installing overlapping tools without a boundary. Examples:

```text
Use Kyverno OR OPA/Gatekeeper as the primary admission engine.
Use one defined dependency-update tool: Dependabot OR Renovate.
Use one designated image scan result as the promotion gate.
Use one authoritative GitOps deployment path: Argo CD.
Use one registry lifecycle owner: Harbor once installed.
```

## Phase 5 — Resilience, Operations, and Data Governance

> **Entry gate:** Synology Longhorn backup/restore rehearsal passed; Phase 4 baseline policies and delivery controls are operating.

### Goal

Make operational recovery, capacity management, upgrades, and data retention routine rather than emergency-only procedures.

Current backup baseline: Longhorn volume backups run every Sunday at 01:00 and retain two recovery points per volume; Longhorn system backups run at 01:30 and retain two configuration bundles. Prometheus monitors Longhorn scrape health, backup failures, stuck backups, and stale volume backups. Application PVC restore drills and Ansible-managed K3s etcd snapshot copies to the same NAS are implemented and tested. The homelab intentionally accepts one external NAS copy; NAS/site-loss protection is outside the current risk boundary.

### Task map

| Task | Outcome | Technologies/patterns |
|---|---|---|
| **5.1** Backup service levels | Recurring backups, explicit workload RPO/RTO, backup freshness alerts | Longhorn recurring jobs, Prometheus, Alertmanager, Synology NFS |
| **5.2** Application restore drills | Recover Harbor, monitoring, and selected application data to isolated targets | Longhorn, workload-specific consistency checks |
| **5.3** Kubernetes and platform upgrades | Repeatable maintenance windows, prechecks, rollback, and postchecks | Ansible, K3s, Helm, Argo CD, health gate |
| **5.4** Capacity and performance management | Forecast storage, CPU, memory, and backup capacity before saturation | Prometheus, Grafana, Longhorn metrics |
| **5.5** Configuration and data governance | Retention, classification, ownership, and evidence lifecycle | Git, Harbor retention, Synology replication/snapshots |
| **5.6** Incident management | Severity model, communication template, incident timeline, postmortem process | Runbooks, GitHub Issues/Projects, alert routing |

### Required practices

```text
Quarterly restore rehearsal for every stateful tier.
Documented maintenance windows for K3s, Longhorn, Argo CD, Harbor, and observability upgrades.
PodDisruptionBudgets and graceful shutdown review for stateful workloads.
Capacity alerting before Longhorn disk, NAS share, or node filesystem exhaustion.
Synology second-copy/off-site recovery plan tested separately from Longhorn restore.
Blameless postmortem for material failed change or recovery exercise.
```

### Completion criteria

```text
[x] Backup age/failure alert is tested for Prometheus and Alertmanager routing.
[x] All current stateful application PVCs have isolated restore evidence.
[ ] K3s upgrade rehearsal and rollback are documented.
[ ] Capacity dashboards and actionable thresholds exist.
[ ] Synology has a separately tested second-copy strategy.
[ ] Incident and postmortem templates are used in a tabletop exercise.
```

## Phase 6 — Internal Developer Platform and Service Delivery

> **Entry gate:** Signed artifact path, Harbor, network/security baseline, and restoration process are operational.

### Goal

Provide a repeatable "golden path" for applications so delivery quality does not depend on an operator remembering manual Kubernetes details.

### Task map

| Task | Outcome | Technologies/patterns |
|---|---|---|
| **6.1** Application golden path | Template repository with test, image build, SBOM, signing, GitOps manifest, policy tests, and runbook skeleton | GitHub template, reusable Actions, Helm/Kustomize |
| **6.2** Service catalog | Discoverable ownership, runbooks, dependencies, APIs, dashboards, and lifecycle metadata | Backstage evaluation or Git-based catalog first |
| **6.3** Ephemeral preview environments | Isolated PR environment for safe web-service review where resources permit | Argo CD ApplicationSet, Kustomize, GitHub Environments |
| **6.4** Infrastructure self-service | Controlled namespace/database/queue requests through reviewed APIs/templates | GitOps pull requests, Crossplane evaluation only if justified |
| **6.5** Release engineering | Versioning, changelogs, progressive delivery, rollback evidence, and DORA-style measures | Conventional commits, semantic release, Argo Rollouts evaluation |
| **6.6** Developer security experience | Fast local/PR feedback for policy, secrets, dependency, and image issues | pre-commit, Gitleaks, Trivy, Kyverno CLI |

### Design guidance

Start with Git-based templates and reusable workflows. Do not install Backstage, Crossplane, Argo Rollouts, or a service mesh before a specific repeated workflow proves the platform needs them. Enterprise platforms reduce cognitive load; they do not create an additional control plane for every possible feature.

### Completion criteria

```text
[ ] A new service can be created from a reviewed golden-path template.
[ ] The template delivers a signed image digest through GitOps with policy validation.
[ ] Ownership, runbook, dashboard, dependency, and recovery information are discoverable.
[ ] At least one safe preview/promotion flow is proven.
[ ] Release and rollback evidence can be retrieved from source commit to deployed digest.
```

## Phase 7 — Scale, Zero Trust, and Advanced Assurance

> **Entry gate:** There is a real business/operational need beyond the current five-node homelab, plus capacity and support ownership for each new control plane.

### Goal

Evaluate advanced controls that larger enterprises use when they operate multiple teams, clusters, environments, or compliance boundaries.

### Conditional task map

| Task | Outcome | Candidate technologies | Adoption condition |
|---|---|---|---|
| **7.1** Central identity and RBAC | SSO, group-based access, short-lived identities, audited break-glass | OIDC, Keycloak/Entra ID, Kubernetes RBAC | More than one operator/team or a formal access-review need |
| **7.2** Workload identity | Remove static cloud credentials from Pods | Azure workload federation patterns, External Secrets | Workloads need cloud APIs beyond current ESO boundary |
| **7.3** Advanced network security | eBPF visibility, encrypted pod traffic, advanced policy | Cilium, Hubble | Existing CNI cannot meet documented policy/visibility needs; migration rehearsal exists |
| **7.4** Multi-cluster continuity | Recover/run selected workloads in a second cluster | Argo CD multi-cluster, Harbor replication, backup restore | A second cluster/site exists and restore objectives require it |
| **7.5** Security event correlation | Central alert triage and long-term audit evidence | SIEM integration, OpenTelemetry, Loki | Alert/event volume exceeds practical Grafana/Loki workflows |
| **7.6** Compliance automation | Measurable controls and evidence collection | OpenSCAP/CIS tooling, policy reports, evidence archive | External compliance or customer requirement exists |

### Completion criteria

```text
[ ] Every adopted advanced component has an ADR, owner, upgrade plan, resource budget, and tested recovery procedure.
[ ] Identity access is least-privilege, reviewable, and revocable.
[ ] Multi-cluster or zero-trust controls have a tested failure and rollback path.
[ ] Compliance evidence is automated only where it maps to a real requirement.
```

## Cross-phase non-negotiable controls

```text
No secrets in Git, terminal transcripts, CI output, images, or dashboards.
No direct CI deployment credentials; CI validates/builds and Argo CD deploys Git.
No mutable image tag promotion after the signed-digest path is enforced.
No permanent wildcard RBAC or unbounded policy exception.
No stateful service is treated as recoverable without a successful restore rehearsal.
No forced upgrade, CNI migration, or destructive prune without precheck, backup, maintenance window, rollback, and postcheck.
No security finding is silently ignored; each is fixed, time-bound accepted risk, false positive, or investigated.
```

## Recommended immediate sequence

```text
Now:     Complete and commit Phase 4 planning.
Next:    Phase 4.1 security baseline and threat model (read-only/audit-first).
Later:   Complete NAS-Backup-setup and verify Longhorn recovery.
Then:    Phase 4.2 Kyverno audit rollout -> 4.3 network policy -> 4.4 CI governance.
After:   Phase 4.5 supply chain -> 4.6 Harbor -> 4.7 promotion -> 4.8 response.
Finally: Phase 5 operational resilience before considering Phase 6/7 complexity.
```
