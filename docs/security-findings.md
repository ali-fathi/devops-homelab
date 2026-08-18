# Security Findings

This document tracks security findings from automated scans and manual security reviews for the `devops-homelab` repository.

The goal is to make security review part of the normal GitOps workflow instead of treating scan output as temporary noise.

---

## Purpose

The repository now includes automated CI checks such as:

```text
Gitleaks secret scanning
Trivy configuration and IaC scanning
Kubernetes manifest validation
```

These tools may report findings that need review, remediation, or documented acceptance.

This file provides a single place to track those findings over time.

---

## Scope

This document is used for findings related to:

```text
Kubernetes manifests
Argo CD Application definitions
ExternalSecret manifests
Terraform configuration
Ansible configuration
GitHub Actions workflows
Dockerfiles
Container image build configuration
Cloudflare-related configuration notes
Secret handling patterns
SecurityContext and pod hardening gaps
Public exposure and LoadBalancer risk
```

---

## Current Security Tools

Current or planned security tools:

```text
Gitleaks
Trivy
kubeconform
yamllint
Future: Kyverno
Future: OPA/Gatekeeper
Future: Cosign
Future: Syft/Grype
```

---

## Finding Decision Types

Every finding should be classified as one of the following:

```text
Fix now
Fix later
Accepted risk
False positive
Needs investigation
```

---

## Decision Definitions

### Fix now

Use this when a finding is important and should be remediated immediately.

Examples:

```text
Real secret committed to Git
Public endpoint exposes private data
Privileged container without justification
Critical infrastructure misconfiguration
```

---

### Fix later

Use this when the finding is valid, but not urgent enough to block the current phase.

Examples:

```text
Missing readOnlyRootFilesystem
Missing resource limits on a low-risk internal workload
Missing non-root user on a demo service
```

A `Fix later` finding should eventually become a planned task.

---

### Accepted risk

Use this when the finding is real, but intentionally accepted for the homelab.

Accepted risks must include a clear reason.

Example:

```text
The service is internal-only and protected by Cloudflare/WARP.
The workload is a temporary demo app.
The configuration is required by an upstream chart.
```

Accepted risks should be reviewed periodically.

---

### False positive

Use this when the tool reported something that is not actually a security problem.

Examples:

```text
Fake example token in documentation
Test value that is not a real secret
Scanner misinterprets a public identifier as a secret
```

False positives should be narrowly allowlisted if they repeatedly fail automated checks.

---

### Needs investigation

Use this when the finding needs more analysis before a decision can be made.

Examples:

```text
Unclear Trivy Kubernetes misconfiguration
Unknown default value from Helm chart
Potentially sensitive endpoint exposure
```

---

## Open Findings

Use this table for findings that are not yet resolved.

| Date | Tool | Severity | Finding | Path | Decision | Owner | Notes |
|------|------|----------|---------|------|----------|-------|-------|
| 2026-08-14 | Manual Phase 4.1 inventory | HIGH | Longhorn management UI is directly exposed by a LAN LoadBalancer Service | `kubernetes/infrastructure/longhorn/longhorn-ui-lb.yaml` | Needs investigation | Ali | `192.168.178.211` is an administration plane. Confirm approved operators and authenticated/private access before NetworkPolicy or ingress changes. Review by 2026-09-14. |
| 2026-08-14 | Manual Phase 4.1 inventory | HIGH | VictoriaMetrics query/write API is directly exposed by a LAN LoadBalancer Service | `kubernetes/applications/ring-health-tracker/service.yaml` | Needs investigation | Ali | `192.168.178.214:8428` must have a documented external client and access control. Otherwise migrate it to `ClusterIP` through Git. Review by 2026-09-14. |
| 2026-08-14 | Manual Phase 4.1 inventory | MEDIUM | Traefik has a LAN LoadBalancer Service while direct MetalLB Services remain in use | Live `kube-system/traefik` Service; Git ingress configuration is incomplete | Needs investigation | Ali | Confirm active routes and intended ownership. Restrict or remove the exposure only after dependency review. Review by 2026-09-14. |
| 2026-08-14 | Manual Phase 4.1 inventory | HIGH | Traefik Helm reconciliation ServiceAccounts are bound to `cluster-admin` | Live bindings `helm-kube-system-traefik` and `helm-kube-system-traefik-crd` | Needs investigation | Ali | Bound subjects have token automount enabled and were used by completed K3s bundled Traefik/CRD Helm install Jobs. Charts are `39.0.7`; no current running Pod used either identity. Confirm controller recreation/least-privilege behavior before narrowing or deleting. Review by 2026-09-14. |
| 2026-08-14 | Manual Phase 4.1 inventory | HIGH | Longhorn support-bundle ServiceAccount is bound to `cluster-admin` | Live binding `longhorn-support-bundle` | Needs investigation | Ali | Bound subject is `longhorn-system/longhorn-support-bundle`. No support-bundle Job was found; token automount is unset and therefore inherits the Kubernetes default when used by a Pod. Confirm version-specific vendor purpose before changing it. Review by 2026-09-14. |
| 2026-08-14 | Manual Phase 4.1 inventory | MEDIUM | Wildcard controller ClusterRoles are bound to named expected control-plane or installed-controller identities | `artifacts/platform-security-baseline/20260814144328-31798/clusterroles.json` (local evidence) | Fix later | Ali | Argo CD, Longhorn, MetalLB, Prometheus Operator, local-path provisioner, K3s, and Kubernetes controllers have no unexpected subject in the initial mapping. Revalidate on controller upgrades; do not grant similar wildcard access to application identities. Review by 2027-08-14. |
| 2026-08-14 | Disposable NetworkPolicy enforcement probe | HIGH | Ingress deny NetworkPolicy remained reachable after 60 seconds | K3s `/etc/rancher/k3s/config.yaml` (live configuration; no values committed) | Fix now, controlled maintenance | Ali | Root cause confirmed: `disable-network-policy: true`; `flannel-backend: host-gw` remains intentional. The flag was a historical cross-node networking recovery choice. Do not deploy default-deny or rely on existing policies. Use the Ansible-owned remediation runbook only after restore/maintenance gates, then rerun `reachable -> denied -> reachable`. Review by 2026-08-21. |
| 2026-08-14 | Manual Phase 4.1 inventory | MEDIUM | Stateful InfluxDB ownership init container lacks resource settings | `kubernetes/applications/garmin/influxdb.yaml` | Fix later | Ali | It runs as UID 0 only to repair PVC ownership. Updating the `Recreate` Deployment would restart a stateful Pod, so defer the template change until the Synology Longhorn restore rehearsal passes and a maintenance window is approved. Review by 2026-09-14. |
| 2026-08-17 | Phase 4.4 GitHub audit | HIGH | Active all-branch rule prevents deletion/force pushes only; `main` has no required PR, approval, status-check, or conversation-resolution rule | GitHub ruleset `new_branch_protect` | Fix now, approved settings change | Ali | Public-repository delivery controls are insufficient. Configure a main-only ruleset after confirming exact required-check names and a recovery/rollback path. Evidence: `docs/security/phase-4.4-ci-governance-audit.md`. Review by 2026-08-24. |
| 2026-08-17 | Phase 4.4 GitHub audit | HIGH | All 20 GitHub Actions `uses:` references are mutable tags and repository SHA pinning is disabled; all actions/workflows are allowed | `.github/workflows/` and GitHub Actions policy | Fix now | Ali | Pin reviewed actions to full commit SHAs, add update automation, then require SHA pinning and restrict allowed actions. Do not enable the setting before workflow pins are merged. Review by 2026-08-31. |
| 2026-08-17 | Phase 4.4 GitHub audit | HIGH | Health Dashboard workflow has workflow-wide `contents: write` and pushes image-digest commits directly to `main` | `.github/workflows/health-dashboard-build.yaml` | Fix later, before Task 4.5/4.7 enforcement | Ali | Separate read-only PR validation from protected publication/promotion. The current direct-main pattern conflicts with protected-main review goals. Review by 2026-09-14. |
| 2026-08-17 | Phase 4.4 GitHub audit | MEDIUM | CODEOWNERS and Dependabot/Renovate configuration are absent; Dependabot security updates are disabled | Repository settings and root/.github governance files | Fix now | Ali | Add path ownership and conservative reviewable dependency-update PRs; enable Dependabot security updates. Do not auto-merge initially. Review by 2026-08-31. |
| 2026-08-17 | Phase 4.4 GitHub audit | MEDIUM | Trivy configuration scan and Homelab API image scan report CRITICAL/HIGH findings without failing CI | `.github/workflows/trivy-config-scan.yaml`, `.github/workflows/homelab-api-build.yaml` | Fix later, progressive enforcement | Ali | Keep SARIF upload; make gates blocking only after baseline review, narrow exceptions, and a deliberately failing fixture prove the behavior. Review by 2026-09-14. |

---

## Resolved Findings

Use this table for findings that were fixed or closed.

| Date | Tool | Severity | Finding | Path | Resolution | Notes |
|------|------|----------|---------|------|------------|-------|
| 2026-08-13 | Trivy | CRITICAL | KSV-0046: ClusterRole could manage all resources through wildcard API groups and resources | `kubernetes/ci/terraform-ci/rbac.yaml` | Replaced wildcard ClusterRole permissions with exact MetalLB and AppProject read permissions plus a namespace-scoped Longhorn Helm Secret read Role | Validate required permissions are `yes`, unrelated/write permissions are `no`, then confirm the Terraform CI plan succeeds. |
| 2026-08-14 | Manual Phase 4.1 inventory | MEDIUM | Garmin fetcher lacked CPU/memory requests and limits | `kubernetes/applications/garmin/garmin-fetch-data.yaml` | Added evidence-based initial requests/limits through Git | Fetcher baseline is 25m/128Mi request and 250m/256Mi limit after an observed 73Mi idle footprint. Observe an actual fetch post-sync. |
| 2026-08-14 | Disposable NetworkPolicy enforcement probe | MEDIUM | Isolated probe namespace deletion exceeded its original 60-second cleanup wait | Isolated namespace `networkpolicy-probe-20260814151536-16664` | Namespace deletion completed; cleanup wait separated and increased to 180 seconds | Follow-up confirmed no namespace, Pods, NetworkPolicies, or Events remained. No finalizers were force-removed. |
| 2026-08-17 | Trivy image scan | HIGH | CVE-2026-53615 in Debian `util-linux` packages inherited by the Health Dashboard Python slim base image | `apps/health-dashboard/Dockerfile` | Added `apt-get upgrade -y` before runtime package installation | Rebuilt with `--pull`; Debian packages updated to `2.41.5-0+deb13u1`. All 12 application tests passed and the same Trivy 0.70 CRITICAL/HIGH gate returned zero findings locally. |
| 2026-08-18 | Trivy config scan | HIGH | DS-0002: Homelab API Dockerfile had no explicit non-root runtime user | `apps/homelab-api/Dockerfile` | Added fixed numeric user/group `10001:10001`, copied application source with that ownership, and set `USER 10001:10001` | Local image build confirmed the configured runtime user and `/healthz` response. Targeted Trivy 0.70 config scan returned no DS-0002 finding. |
| 2026-08-18 | Trivy config scan | HIGH | DS-0029: DevContainer `apt-get install` omitted `--no-install-recommends` | `.devcontainer/Dockerfile` | Added `--no-install-recommends` while retaining the explicit package list | Full DevContainer build and targeted Trivy config scan must confirm the package set still builds and DS-0029 is absent before merge. |

---

## Accepted Risks

Use this table for findings that are real but intentionally accepted.

| Date | Tool | Severity | Risk | Path | Reason | Review Date |
|------|------|----------|------|------|--------|-------------|
| 2026-08-13 | Trivy | CRITICAL | KSV-0114: MetalLB controller can manage webhook configurations | `kubernetes/infrastructure/metallb/metallb-native.yaml` | The vendor controller must update only the named `ValidatingWebhookConfiguration` `metallb-webhook-configuration` to rotate the webhook TLS CA. `mutatingwebhookconfigurations` access was removed because MetalLB does not use it. The path-scoped exception in `.trivyignore.yaml` is limited to this vendor manifest; replacing the remaining validating-webhook permission would break automated certificate rotation. | 2027-08-13 |
| YYYY-MM-DD | Trivy | MEDIUM | Example accepted risk | path/to/file.yaml | Homelab-only temporary exception | YYYY-MM-DD |

---

## Review Process

When a new finding appears in CI:

```text
1. Open the failed or warning workflow run.
2. Identify the tool that produced the finding.
3. Identify the file path and line number.
4. Decide whether the finding is real.
5. Classify the finding.
6. Fix immediately if it is sensitive or high risk.
7. Document accepted or deferred findings in this file.
8. Re-run the workflow.
9. Commit the fix or documentation update.
```

---

## Secret Finding Process

If Gitleaks detects a real secret:

```text
1. Treat the secret as compromised.
2. Rotate the secret in the real system.
3. Remove the secret from the repository.
4. Replace the secret with ExternalSecret, GitHub Secret, or a placeholder.
5. Consider Git history cleanup if the secret was pushed to GitHub.
6. Document the resolution in the Resolved Findings table.
```

Do not simply add the secret to an allowlist.

---

## Trivy Finding Process

If Trivy detects a configuration issue:

```text
1. Read the finding and affected file.
2. Decide whether the issue applies to the homelab context.
3. Fix high-signal issues first.
4. Document accepted risks.
5. Avoid blindly ignoring entire directories unless they are generated or vendor-owned.
```

Common Trivy findings may include:

```text
Container runs as root
Missing securityContext
Missing resource limits
Privileged container
Writable root filesystem
HostPath usage
LoadBalancer exposure
Plain Kubernetes Secret usage
```

---

## Kubernetes Manifest Finding Process

If kubeconform detects an invalid manifest:

```text
1. Check whether the file is a real Kubernetes manifest.
2. If it is a Helm values file, exclude it from kubeconform.
3. If it is a raw dashboard JSON file, move it under a non-manifest folder or wrap it in a ConfigMap.
4. If it is a real manifest, fix the schema issue.
5. Re-run the CI workflow.
```

---

## Risk Severity Guidance

### Critical

Fix immediately.

Examples:

```text
Real secret committed to Git
Public unauthenticated access to private health data
Privilege escalation risk on a sensitive workload
Destructive deletion risk for storage components
```

---

### High

Fix soon or document a strong reason for temporary acceptance.

Examples:

```text
Container runs privileged
Sensitive service exposed through public endpoint
Missing authentication on write endpoint
Dangerous hostPath mount
```

---

### Medium

Review and prioritize.

Examples:

```text
Missing readOnlyRootFilesystem
Missing runAsNonRoot
Missing resource limits
Weak network isolation
```

---

### Low

Track if useful, but do not let low-priority noise block learning progress.

Examples:

```text
Style warnings
Non-critical hardening improvements
Documentation-only concerns
```

---

## Current Policy

Current Week 3 policy:

```text
Gitleaks findings should block merges.
Trivy findings are reviewed and tracked.
Trivy may be made blocking for CRITICAL/HIGH findings after initial review.
Security findings must be documented if not fixed immediately.
```

---

## Future Policy Target

Future target policy:

```text
Gitleaks blocks all real secret findings.
Trivy blocks CRITICAL and HIGH findings.
Accepted risks require a documented reason.
Container images are scanned before push.
Images are signed before production-like use.
SBOMs are generated for owned images.
Policy-as-code validates Kubernetes manifests.
```

---

## Related Files

```text
.github/workflows/secrets-scan.yaml
.github/workflows/trivy-config-scan.yaml
.gitleaks.toml
trivy.yaml
docs/security-scanning.md
docs/ci-manifest-validation.md
```

---

## Useful Commands

Run Gitleaks locally if installed:

```bash
gitleaks detect --source . --verbose
```

Run Gitleaks with Docker:

```bash
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:latest detect --source /repo --verbose
```

Run Trivy config scan locally if installed:

```bash
trivy config .
```

Run Trivy config scan with repository config:

```bash
trivy config --config trivy.yaml .
```

Run Trivy with Docker:

```bash
docker run --rm -v "$PWD:/repo" aquasec/trivy:latest config /repo
```

---

## Maintenance

This document should be updated whenever:

```text
A new security workflow is added.
A Gitleaks finding is detected.
A Trivy finding is accepted or fixed.
A public endpoint security decision changes.
A new class of risk is discovered.
A scanner configuration changes.
```

---

## Success Criteria

Security finding management is working when:

```text
[ ] Security scan results are reviewed.
[ ] Real secrets are rotated and removed.
[ ] Findings are not ignored silently.
[ ] Accepted risks have reasons.
[ ] Fix-later items are tracked.
[ ] High-risk findings are fixed or explicitly documented.
[ ] CI security workflows are visible in GitHub Actions.
```
