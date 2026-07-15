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
| YYYY-MM-DD | Trivy | HIGH | Example finding | path/to/file.yaml | Needs investigation | Ali | Replace this example with real findings. |

---

## Resolved Findings

Use this table for findings that were fixed or closed.

| Date | Tool | Severity | Finding | Path | Resolution | Notes |
|------|------|----------|---------|------|------------|-------|
| YYYY-MM-DD | Gitleaks | HIGH | Example secret finding | path/to/file | Secret rotated and removed | Replace this example with real resolved findings. |

---

## Accepted Risks

Use this table for findings that are real but intentionally accepted.

| Date | Tool | Severity | Risk | Path | Reason | Review Date |
|------|------|----------|------|------|--------|-------------|
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
