# Runbook: Solo-Maintainer GitHub Pull-Request Workflow

Use this workflow for every repository change. You are the sole developer and sole merge decision-maker. GitHub requires a pull request and the core validation/security checks before a normal merge to `main`.

```text
Edit locally
  -> commit to a feature branch
  -> push the feature branch
  -> open a pull request
  -> wait for checks
  -> review the diff and results yourself
  -> squash-merge, or close the PR without merging
  -> GitHub Actions / Argo CD reconcile the approved main change
```

## Current protection model

```text
main direct push: blocked
pull request: required
required approvals: 0 (solo maintainer)
required Code Owner review: disabled (ownership is documented only)
required conversations: resolved
required merge methods: squash or rebase
normal required checks: YAML lint, Kubernetes schema validation, Helm render,
Gitleaks, and Trivy configuration scan
emergency bypass: your GitHub account, through a pull request only
```

Do not use an emergency bypass for ordinary work. A bypass skips intended protection and must be recorded in `docs/security-findings.md` or an incident record immediately afterward.

## Prerequisites

Run these from the repository root before starting work:

```bash
git switch main && git pull --ff-only && git status --short --branch
```

Expected:

```text
## main...origin/main
```

If `git status` lists changed files, either commit them through the workflow below, stash them intentionally, or inspect them before changing branches. Do not discard an unknown change.

Confirm GitHub CLI access if you use `gh` commands:

```bash
gh auth status
```

## Standard change workflow

Replace `<type>/<short-description>` with a short branch name, for example `fix/health-dashboard-cve` or `docs/update-pr-runbook`.

### 1. Start a feature branch

```bash
git switch -c <type>/<short-description>
```

Confirm you are not on `main`:

```bash
git branch --show-current
```

### 2. Edit and inspect the change

After editing files, inspect exactly what will be committed:

```bash
git status --short && git diff --check && git diff
```

`git diff --check` must show no output. Read the diff before committing, especially changes to `.github/`, `terraform/`, `ansible/`, `kubernetes/gitops/`, `kubernetes/infrastructure/`, `kubernetes/security/`, and `docs/security/`.

### 3. Run relevant local checks

Use the checks relevant to the files you changed. Do not skip a failing check; understand and fix it first.

| Changed area | Local check |
|---|---|
| Kubernetes/Argo manifests | `yamllint kubernetes .github ansible docs` when available; CI also runs kubeconform and Helm rendering |
| Terraform | `cd terraform && terraform fmt -check -recursive && terraform init -backend=false && terraform validate` |
| Health Dashboard | `python -m unittest discover -s apps/health-dashboard/tests -v` or use the container/CI workflow |
| Cluster/GitOps state after an approved merge | `./scripts/verify-gitops-health.sh` |
| Security-sensitive repository change | `./scripts/audit-ci-repository-governance.sh` when repository settings/workflows are involved |

### 4. Commit only the intended files

Prefer explicit paths instead of `git add .`:

```bash
git add <path-1> <path-2> && git commit -m "type(scope): concise description"
```

Examples:

```bash
git add .github/workflows/health-dashboard-build.yaml && git commit -m "fix(ci): remove direct main writes from dashboard build"
```

```bash
git add docs/runbooks/github-pr-workflow.md && git commit -m "docs: add solo PR workflow"
```

Confirm the commit content:

```bash
git show --stat --oneline HEAD
```

### 5. Push the feature branch

```bash
git push -u origin HEAD
```

Do **not** run `git push origin main`. The branch rules intentionally block it.

### 6. Create and open the pull request

```bash
gh pr create --fill --web
```

The browser opens the new PR. Confirm before submitting:

```text
Base branch: main
Compare branch: your feature branch
Title: describes the intended change
Description: explains purpose, risk, validation, and rollback where relevant
```

A PR must exist before the repository's pull-request-triggered checks can run.

### 7. Wait for checks and review the PR

Watch checks from the terminal:

```bash
gh pr checks --watch
```

Or open the PR in GitHub and use the **Checks** tab. Required checks must pass:

```text
YAML syntax and style
Kubernetes schema validation
Helm render validation
Gitleaks secret scan
Trivy configuration scan
```

Additional relevant checks may run, for example Health Dashboard tests and its blocking image Trivy scan. Treat every visible failed check as a stop signal even when it is not a globally required status check.

Before merging, review:

```text
Files changed
Full diff
All required checks are green
All relevant optional/application checks are green
No unresolved conversations
No unexpected image, secret, infrastructure, GitOps, or permission change
```

### 8. Decide whether to merge

If the PR is correct and all checks are green, use GitHub's normal **Squash and merge** button. Do not use an admin/bypass merge for normal work.

Alternatively, merge from the terminal after you have reviewed the GitHub PR:

```bash
gh pr merge --squash --delete-branch
```

If the change is not ready, do not merge. Push further commits to the same feature branch; the PR checks rerun automatically. Or close the PR without merging.

### 9. Update your local main branch after merge

```bash
git switch main && git pull --ff-only && git branch -d <type>/<short-description>
```

Use `git branch -d` only after the PR is merged. If Git refuses deletion, inspect why rather than force-deleting the branch.

## Health Dashboard image deployment

The Health Dashboard build workflow builds, Trivy-scans, and publishes a GHCR image after a source PR is merged. It does **not** modify `main` or deploy the image automatically.

1. Merge the source-code PR normally.
2. Open the successful workflow run.
3. Copy the immutable image reference from its job summary:

```text
ghcr.io/ali-fathi/health-dashboard@sha256:<digest>
```

4. Start a separate GitOps branch:

```bash
git switch main && git pull --ff-only && git switch -c chore/deploy-health-dashboard-image
```

5. Update only `kubernetes/applications/health-dashboard/kustomization.yaml` to use that digest.
6. Commit, push, create a PR, wait for checks, review, and squash-merge using the standard workflow above.
7. After Argo CD reconciles the approved change, run:

```bash
./scripts/verify-gitops-health.sh
```

This separation ensures that CI produces artifacts while you alone approve GitOps deployment changes.

## Emergency bypass

Use only for a genuine outage or recovery incident where waiting for checks would cause more harm than the bypass risk.

```text
Create a PR anyway.
Use the bypass only through that PR; do not direct-push to main.
Record the reason, timestamp, affected resources, and follow-up validation.
Run normal checks and remediation immediately afterward.
```

The emergency bypass is not a normal release mechanism.

## Troubleshooting

| Symptom | Meaning | Safe response |
|---|---|---|
| `git push origin main` is rejected | Expected branch protection | Create/use a feature branch and PR. |
| Required check is pending | PR is waiting for CI | Wait; inspect Actions if it exceeds normal duration. Do not bypass solely for convenience. |
| Required check fails | CI found an issue | Open the failed job logs, fix the branch, push a new commit, and wait for rerun. |
| Health Dashboard Trivy scan fails | Image has CRITICAL/HIGH finding | Fix the Dockerfile/dependency/base-image issue; do not weaken the gate or add a broad ignore. |
| Gitleaks detects a real secret | Secret is compromised | Rotate it first, remove it from Git, and follow `docs/security-findings.md`. |
| Argo CD is unhealthy after a GitOps merge | Deployment needs investigation | Use `./scripts/verify-gitops-health.sh`; rollback with a reviewed Git revert when necessary. |

## Quick reference

```bash
# Start work
git switch main && git pull --ff-only && git switch -c <type>/<short-description>

# Inspect and commit
git status --short && git diff --check && git diff
git add <intended-paths> && git commit -m "type(scope): description"

# Create PR
git push -u origin HEAD && gh pr create --fill --web

# Watch checks
gh pr checks --watch

# Merge only after review and green checks
gh pr merge --squash --delete-branch

# Refresh local main
git switch main && git pull --ff-only
```
