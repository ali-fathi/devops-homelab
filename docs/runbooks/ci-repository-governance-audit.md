# Runbook: CI and Repository-Governance Audit

Use this runbook for the Phase 4.4 factual baseline before changing GitHub branch rules, Actions policy, CODEOWNERS, or dependency automation.

## Script

```text
scripts/audit-ci-repository-governance.sh
```

## Safety boundary

The script is read-only. It uses the authenticated `gh` CLI context to retrieve curated repository, branch/ruleset, and Actions policy metadata. It reads local workflow files to inventory action references and declared permissions.

It does **not**:

```text
Change GitHub repository settings, rulesets, branches, or workflows
Read, print, or write GitHub Actions Secrets, tokens, or variables
Create pull requests, issues, comments, releases, or Dependabot configuration
Run GitHub Actions or mutate Kubernetes, Terraform, Argo CD, Longhorn, or NAS resources
```

Evidence is written under ignored `artifacts/ci-repository-governance/`. The report is internal operational metadata; do not commit it.

## Prerequisites

```text
Git checkout of the target repository
GitHub CLI authenticated to the intended GitHub host/account
jq, rg, git, and gh available locally
Read access to repository settings and rulesets
```

Confirm the intended GitHub account without printing a token:

```bash
gh auth status
```

## Run

From the repository root:

```bash
./scripts/audit-ci-repository-governance.sh
```

For an explicit repository and branch:

```bash
./scripts/audit-ci-repository-governance.sh --repo ali-fathi/devops-homelab --branch main
```

Expected completion:

```text
[PASS] Read-only CI and repository-governance audit collected.
[INFO] Repository: <owner/repository>; branch: <branch>
[INFO] Report directory: .../artifacts/ci-repository-governance/<run-id>
```

## Review sequence

```text
1. summary.json
   - Confirm branch protection/ruleset coverage, Actions policy, ownership and
     dependency automation, and action pinning counts.
2. ruleset-details.json and legacy-branch-protection.json
   - Determine whether the default branch requires PRs, reviews, required
     checks, and conversation resolution. Rulesets may replace legacy branch
     protection, so a missing legacy response is not itself a finding.
3. actions-permissions.json and workflow-token-defaults.json
   - Review allowed-action policy, SHA pinning, and default token scope.
4. governance-files.json
   - Confirm CODEOWNERS and Dependabot/Renovate presence.
5. workflow-action-references.json and workflow-permissions.txt
   - Find mutable action tags and workflow-level elevated permissions.
```

Record decisions in `docs/security-findings.md` and update the current Phase 4.4 audit review. A finding is evidence for a reviewed change; do not change repository settings solely because a script reported an observation.

## Remediation guardrails

```text
Protect main before granting more CI privileges.
Add required checks only after confirming their exact displayed names and that
all relevant PR events run them successfully.
Pin action references before enabling GitHub's SHA-pinning requirement.
Use dependency automation to update pins; do not manually drift pins.
Keep Gitleaks blocking and preserve Trivy SARIF uploads when changing scan gates.
Do not make Trivy blocking until existing findings are classified and narrow,
time-bound exceptions are documented.
Do not permit a PR-triggered test job to retain a workflow-wide write token.
```

## Failure handling

| Symptom | Meaning | Safe action |
|---|---|---|
| `gh` is unavailable or unauthenticated | Operator environment cannot read GitHub evidence | Authenticate the approved operator account; do not copy a token into a script. |
| API returns `403` | Token or organization policy lacks settings-read access | Record the visibility gap and use an approved repository administrator account. Do not broaden token scopes casually. |
| Legacy branch protection returns unavailable/404 | Rulesets may own protection | Inspect `ruleset-details.json`; do not conclude the branch is unprotected from that response alone. |
| No report directory | Local filesystem/working-directory issue | Correct local access; the script has not changed GitHub. |
| A report contains unexpected sensitive data | Treat it as local operational evidence | Do not commit it; restrict/delete the report and inspect the script before rerunning. |

## Related evidence

```text
docs/security/phase-4.4-ci-governance-audit.md
docs/security-findings.md
scripts/audit-ci-repository-governance.sh
```
