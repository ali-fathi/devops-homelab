# Phase 4.4 CI and Repository-Governance Audit

> **Collection:** 2026-08-17
>
> **Report ID:** `20260817120434-175`
>
> **Status:** Read-only baseline captured. No GitHub repository settings, branch rules, workflows, Secrets, or cluster resources were changed.

## Scope and safety boundary

The audit examined the public GitHub repository metadata, `main` branch rule/ruleset metadata, GitHub Actions policy metadata, and checked-in workflow files. It did not read or print GitHub Actions secrets, tokens, workflow variables, Kubernetes credentials, or Secret data.

The complete local evidence is ignored by Git under:

```text
artifacts/ci-repository-governance/20260817120434-175/
```

Repeat it with:

```bash
./scripts/audit-ci-repository-governance.sh
```

Read [CI and Repository-Governance Audit](../runbooks/ci-repository-governance-audit.md) before making any repository setting change.

## Observed baseline

| Control area | Observed state | Assessment |
|---|---|---|
| Repository visibility | Public | Deliberate public-repository controls are required. Forking is allowed. |
| Default branch | `main` | Branch is marked protected through an active ruleset. |
| Active branch ruleset | `new_branch_protect`, applied to all branches | It prevents deletion and non-fast-forward pushes only. It does **not** require pull requests, approvals, status checks, signed commits, conversation resolution, or linear history. |
| Legacy branch-protection API | Not available | Expected when rulesets are used; the ruleset detail is the source of truth. |
| GitHub secret scanning | Enabled | Positive control. Push protection is also enabled. |
| Dependabot security updates | Disabled | No dependency-update automation or checked-in Dependabot/Renovate configuration exists. |
| Workflow token default | `contents: read` | Positive least-privilege default. Individual workflow permissions still need review. |
| Allowed Actions | All actions/workflows allowed | Third-party action use is unrestricted. |
| SHA pinning policy | Disabled | GitHub does not require immutable action references. |
| Checked-in action references | 20 references; 0 commit-SHA pinned | Every first- or third-party `uses:` reference is mutable (`@v*` or release tag). |
| CODEOWNERS | Absent | No path-based reviewer ownership is configured. |
| Config/IaC Trivy gate | Uploads SARIF but uses `exit-code: "0"` | Findings do not block merges yet; this matches the documented progressive rollout but does not meet the 4.4 exit gate. |
| Image scan gates | Health Dashboard blocks CRITICAL/HIGH findings; Homelab API uses `exit-code: "0"` | Inconsistent enforcement. Image supply-chain work belongs to Task 4.5, but the discrepancy should be resolved during the governance work. |
| GitHub Actions write access | Health Dashboard workflow has workflow-wide `contents: write` and pushes a deployment-digest commit directly to `main` | The publishing/update step needs isolation from PR validation and must operate behind approved branch governance. |

## Evidence-backed findings

### 1. Main lacks reviewed, required-check delivery controls — HIGH

The active ruleset prevents branch deletion and force pushes but does not require a pull request, review, required status checks, or conversation resolution. A user with ordinary push access can therefore bypass the expected validation and review flow.

**Decision:** Fix now, as an approved GitHub repository-settings change. Do not attempt to compensate with documentation or local conventions.

### 2. Third-party GitHub Actions are mutable and unrestricted — HIGH

All 20 `uses:` references are version tags rather than full commit SHAs. Repository policy allows all actions and does not require SHA pinning. A moved tag or compromised action release can alter CI behavior without a repository commit.

**Decision:** Fix now, after branch protection is active. Pin to immutable full commit SHAs and use Dependabot to maintain pins. Restrict allowed actions to GitHub-owned actions plus an approved explicit allowlist where repository policy supports it.

### 3. CODEOWNERS and dependency automation are absent — HIGH/MEDIUM

No CODEOWNERS file, Dependabot configuration, or Renovate configuration exists. GitHub Dependabot security updates are disabled. Infrastructure, workflow, Terraform, and security-policy paths have no enforceable owner review.

**Decision:** Add checked-in CODEOWNERS and Dependabot configuration, then enable Dependabot security updates. Review generated PRs; do not auto-merge workflow or infrastructure updates initially.

### 4. Security gates are not uniformly blocking — MEDIUM

The configuration scan intentionally reports CRITICAL/HIGH findings with `exit-code: "0"`; the Homelab API image scan does the same. The Health Dashboard image scan blocks CRITICAL/HIGH findings. This is a valid audit-first starting point but cannot be a required security gate until high-signal existing findings are classified and the fixtures prove blocking behavior.

**Decision:** Make gates blocking incrementally after documented exception review. Preserve SARIF upload regardless of pass/fail behavior.

### 5. Direct workflow write access to `main` needs redesign — HIGH

The Health Dashboard workflow declares `contents: write` for both test and build jobs and automatically pushes an image-digest deployment commit to `main`. This conflicts with the desired protected-main separation of duties and unnecessarily exposes write capability to PR-triggered workflow execution.

**Decision:** Refactor later in Task 4.5/4.7: separate read-only test/build from a protected publish/attestation workflow, emit a digest artifact, and open a reviewable promotion PR or use a narrowly governed bot exception. Do not retain a broad workflow-wide write token as the long-term pattern.

## Positive controls to retain

```text
GitHub secret scanning is enabled.
GitHub push protection is enabled.
The default GitHub Actions token is read-only.
Gitleaks runs on pull requests, main pushes, manual dispatch, and a weekly schedule.
Health Dashboard image scanning blocks CRITICAL/HIGH vulnerabilities.
Trivy SARIF findings are uploaded to GitHub Security.
Branch deletion and force pushes are blocked by the active ruleset.
```

## Approved remediation sequence

Apply repository changes in this order, through a reviewed operator change. Each step has a rollback/verification point.

```text
1. Configure a main-only ruleset that requires pull requests, one approval,
   code-owner review, conversation resolution, and the existing validation,
   secret-scan, and Trivy checks. Keep deletion/force-push prevention.
2. Add CODEOWNERS for .github/, kubernetes/security/, terraform/, ansible/,
   kubernetes/gitops/, and docs/runbooks/.
3. Add Dependabot with conservative weekly grouped updates; enable Dependabot
   security updates. Do not auto-merge initially.
4. Pin all GitHub Actions to reviewed full commit SHAs; enable repository SHA
   pinning and restrict allowed actions after pins are in place.
5. Make Trivy config scanning blocking only after current CRITICAL/HIGH results
   are remediated or documented as narrow, time-bound exceptions.
6. Split Health Dashboard publishing from PR validation and replace direct main
   writes with a controlled promotion path before signed-digest delivery work.
```

Do not enable required checks until their workflow names, trigger coverage, and passing behavior are verified; an incorrect required-check configuration can block emergency recovery commits. Do not enable a broad blocking Trivy gate before reviewing current findings. Do not alter K3s, Argo CD, Longhorn, or stateful workloads for this task.

## Phase 4.4 exit-gap summary

```text
[ ] Main requires pull request review and required checks.
[ ] CODEOWNERS enforces ownership for sensitive paths.
[ ] All Actions references use immutable commit SHAs.
[ ] Dependabot or Renovate creates reviewable update PRs on a defined schedule.
[ ] Trivy CRITICAL/HIGH policy is a verified blocking gate with narrow exceptions.
[ ] A deliberately misconfigured non-production fixture proves the gate blocks.
[ ] Workflow write access and direct-to-main image promotion are redesigned.
```
