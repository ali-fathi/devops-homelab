# CI Manifest Validation

This document explains the CI manifest validation setup for the `devops-homelab` repository.

The goal of Week 2 is to validate Kubernetes and repository configuration before Argo CD tries to sync changes into the cluster.

---

## Purpose

The repository is now GitOps-driven. Argo CD watches Kubernetes manifests in Git and reconciles the cluster to match the desired state.

Because of that, invalid YAML or invalid Kubernetes manifests should be caught before they reach Argo CD.

This CI validation layer helps catch problems such as:

```text
Broken YAML syntax
Bad indentation
Missing newline at end of file
Invalid Kubernetes resource structure
Raw JSON files accidentally scanned as Kubernetes manifests
Helm values files accidentally scanned as Kubernetes manifests
Vendor/generated manifests producing unnecessary lint noise
```

---

## Current Validation Workflow

The validation workflow is stored here:

```text
.github/workflows/kubernetes-validate.yaml
```

The workflow name is:

```text
Kubernetes Manifest Validation
```

It currently runs on:

```text
push to main
pull_request
manual workflow_dispatch
```

---

## Workflow Jobs

The workflow has three main jobs:

```text
1. YAML syntax and style
2. Kubernetes schema validation
3. Helm render validation for GitOps-managed observability charts
```

---

## Job 1: YAML Syntax and Style

The first job uses:

```text
yamllint
```

This validates YAML formatting and catches common syntax/style issues.

Examples of issues it can detect:

```text
Wrong indentation
Missing newline at end of file
Too many blank lines
Invalid truthy values
Very long lines
Unexpected YAML formatting
```

---

## Job 2: Kubernetes Schema Validation

The second job uses:

```text
kubeconform
```

This validates selected Kubernetes manifests against Kubernetes resource schemas.

Examples of issues it can detect:

```text
Invalid Kubernetes fields
Wrong field types
Missing required fields
Broken manifest structure
Invalid Kubernetes object definitions
```

The workflow intentionally skips files that are not plain Kubernetes manifests, such as:

```text
Helm values files
Grafana raw dashboard JSON files
Generated/vendor install bundles
Documentation files
```

---

## Job 3: Helm Render Validation

The third job installs Helm, adds the Prometheus Community and Grafana chart repositories, and renders the exact chart versions used by the Argo CD Applications:

```text
kube-prometheus-stack 88.2.0
loki 7.2.0
alloy 1.11.1
```

It uses the same release names, namespaces, and local values files that Argo CD uses:

```text
monitoring + monitoring/values.yaml + alerting/values-alertmanager.yaml
loki       + logging/loki-values.yaml
alloy      + logging/alloy-values.yaml
```

This is a render gate, not a deployment. It does not need cluster credentials and it does not contact the homelab Kubernetes API.

It catches errors such as:

```text
Invalid Helm values structure
Invalid Alertmanager configuration rendered by the chart
A removed or renamed chart value
A chart repository/version that cannot be resolved
Helm template failures before Argo CD attempts a sync
```

The values are rendered from the checked-out pull request or branch, rather than raw GitHub URLs, so CI validates the exact proposed change.

### Verified execution

GitHub Actions run [`31790818607`](https://github.com/ali-fathi/devops-homelab/actions/runs/31790818607) completed successfully on 2026-08-14 for commit `83fd0cad4357106b33042f4fc08f4a2683db6fbe`. Its `Helm render validation` job passed alongside the YAML syntax/style and Kubernetes schema-validation jobs. This verifies the pinned monitoring `88.2.0`, Loki `7.2.0`, and Alloy `1.11.1` render path without deploying to the cluster.

---

## Why This Is Important

Without CI validation, mistakes are only discovered after:

```text
Git push
Argo CD refresh
Argo CD manifest generation
Argo CD sync failure
```

With CI validation, many mistakes are detected earlier:

```text
Git push
GitHub Actions validation
Failure before Argo CD sync
```

This makes the GitOps workflow safer.

---

## Current Workflow File

The workflow file should be located at:

```text
.github/workflows/kubernetes-validate.yaml
```

Recommended content:

```yaml
name: Kubernetes Manifest Validation

on:
  push:
    branches:
      - main
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  yaml-lint:
    name: YAML syntax and style
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v5

      - name: Install yamllint
        run: |
          python -m pip install --upgrade pip
          pip install yamllint

      - name: Run yamllint
        run: |
          yamllint kubernetes docs ansible .github

  kubeconform:
    name: Kubernetes schema validation
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v5

      - name: Set up Kubeconform
        uses: bmuschko/setup-kubeconform@v1

      - name: Build manifest file list
        shell: bash
        run: |
          set -euo pipefail

          find kubernetes -type f \( -name "*.yaml" -o -name "*.yml" \) \
            ! -name "values.yaml" \
            ! -name "values-*.yaml" \
            ! -name "*-values.yaml" \
            ! -path "*/docs/*" \
            ! -path "*/dashboards/*" \
            ! -path "*/grafana/*" \
            ! -path "kubernetes/infrastructure/metallb/metallb-native.yaml" \
            > /tmp/kubernetes-manifests.txt

          echo "Files selected for kubeconform:"
          cat /tmp/kubernetes-manifests.txt

          echo "Total files:"
          wc -l /tmp/kubernetes-manifests.txt

      - name: Validate Kubernetes manifests
        shell: bash
        run: |
          set -euo pipefail

          if [ ! -s /tmp/kubernetes-manifests.txt ]; then
            echo "No Kubernetes manifests found for validation."
            exit 0
          fi

          kubeconform \
            -summary \
            -verbose \
            -strict \
            -ignore-missing-schemas \
            $(cat /tmp/kubernetes-manifests.txt)
```

---

## Current yamllint Configuration

The yamllint configuration is stored here:

```text
.yamllint
```

Recommended content:

```yaml
---
extends: default

rules:
  line-length:
    max: 160
    level: warning

  comments:
    min-spaces-from-content: 1

  truthy:
    allowed-values:
      - "true"
      - "false"
      - "on"
      - "off"

  document-start: disable

  indentation:
    spaces: 2
    indent-sequences: true
    check-multi-line-strings: false

  empty-lines:
    max: 1
    max-start: 0
    max-end: 0

ignore: |
  kubernetes/observability/monitoring/dashboards/
  kubernetes/applications/ring-health-tracker/grafana/
  kubernetes/infrastructure/metallb/metallb-native.yaml
  **/*.json
```

---

## Why Some Files Are Ignored

Not every YAML or JSON file in the repository is a Kubernetes manifest.

Some files are intentionally excluded from linting or schema validation.

---

### `kubernetes/infrastructure/metallb/metallb-native.yaml`

This file is treated as a vendor/generated install manifest.

It may contain formatting that does not match the repository linting style.

Reason for exclusion:

```text
Do not manually reformat generated or upstream vendor manifests unless necessary.
```

---

### `kubernetes/observability/monitoring/dashboards/`

This directory contains Grafana dashboard files and dashboard-related content.

These are not plain Kubernetes manifests.

Reason for exclusion:

```text
Raw Grafana dashboards are not Kubernetes resources unless wrapped in ConfigMaps.
```

---

### `kubernetes/applications/ring-health-tracker/grafana/`

This directory contains the raw Ring Health Grafana dashboard JSON.

Reason for exclusion:

```text
Argo CD and kubeconform should not treat raw dashboard JSON as Kubernetes manifests.
```

The deployable dashboard should be wrapped in:

```text
grafana-dashboard.yaml
```

---

### `**/*.json`

Raw JSON files are ignored by yamllint.

Reason:

```text
yamllint is for YAML files.
Raw JSON dashboards should not be linted as YAML.
```

---

## Files That Should Be Validated by kubeconform

The `kubeconform` job should validate plain Kubernetes manifests such as:

```text
kubernetes/applications/garmin/namespace.yaml
kubernetes/applications/garmin/influxdb.yaml
kubernetes/applications/garmin/garmin-fetch-data.yaml
kubernetes/applications/garmin/external-secret-garmin.yaml

kubernetes/applications/ring-health-tracker/namespace.yaml
kubernetes/applications/ring-health-tracker/deployment.yaml
kubernetes/applications/ring-health-tracker/service.yaml
kubernetes/applications/ring-health-tracker/pvc.yaml
kubernetes/applications/ring-health-tracker/grafana-datasource.yaml
kubernetes/applications/ring-health-tracker/grafana-dashboard.yaml

kubernetes/gitops/argocd/applications/garmin.yaml
kubernetes/gitops/argocd/applications/ring-health-tracker.yaml
kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
```

---

## Files That Should Not Be Validated by kubeconform

The `kubeconform` job should not validate Helm values files such as:

```text
kubernetes/gitops/argocd/values.yaml
kubernetes/observability/monitoring/values.yaml
kubernetes/observability/logging/loki-values.yaml
kubernetes/observability/logging/alloy-values.yaml
kubernetes/observability/alerting/values-alertmanager.yaml
```

Reason:

```text
Helm values files are YAML, but they are not Kubernetes API objects.
They do not contain apiVersion and kind.
```

---

## Local Validation Commands

Run yamllint locally:

```bash
yamllint kubernetes docs ansible .github
```

Run the same file selection logic used by kubeconform:

```bash
find kubernetes -type f \( -name "*.yaml" -o -name "*.yml" \) \
  ! -name "values.yaml" \
  ! -name "values-*.yaml" \
  ! -name "*-values.yaml" \
  ! -path "*/docs/*" \
  ! -path "*/dashboards/*" \
  ! -path "*/grafana/*" \
  ! -path "kubernetes/infrastructure/metallb/metallb-native.yaml"
```

This prints the list of files that kubeconform will validate in CI.

---

## Common Issues and Fixes

---

### Issue: Missing newline at end of file

Example error:

```text
no new line character at the end of file
```

Fix one file manually:

```bash
echo >> path/to/file.yaml
```

Fix multiple known files with Python:

```bash
python3 - <<'PY'
from pathlib import Path

for path in Path(".").rglob("*"):
    if path.is_file() and path.suffix in [".yaml", ".yml", ".md"]:
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

        if content and not content.endswith("\n"):
            path.write_text(content.rstrip() + "\n", encoding="utf-8")
            print(f"fixed: {path}")
PY
```

---

### Issue: Wrong indentation

Example error:

```text
wrong indentation: expected 4 but found 2
```

Fix the YAML indentation.

Example correct Kubernetes list indentation:

```yaml
spec:
  addresses:
    - 192.168.178.210-192.168.178.220
```

---

### Issue: Long line warnings

Example warning:

```text
line too long
```

This is currently configured as a warning only:

```yaml
line-length:
  max: 160
  level: warning
```

Long PromQL or LogQL expressions may trigger this warning.

Current policy:

```text
Long lines are allowed as warnings.
They do not fail the workflow.
```

If a specific file is noisy, the file can be excluded later.

---

### Issue: Raw dashboard JSON breaks validation

Example error:

```text
Object 'Kind' is missing
```

Cause:

```text
A raw Grafana dashboard JSON file was scanned as a Kubernetes manifest.
```

Fix:

```text
Keep raw JSON under a grafana/ directory.
Wrap dashboard JSON in a ConfigMap YAML.
Make Argo CD process only YAML manifests.
```

Recommended Argo CD Application setting:

```yaml
directory:
  include: "{*.yaml,*.yml}"
```

---

### Issue: Helm values files fail kubeconform

Cause:

```text
values.yaml files are not Kubernetes resources.
```

Fix:

```text
Exclude Helm values files from kubeconform.
```

Current workflow excludes:

```text
values.yaml
values-*.yaml
*-values.yaml
```

---

## Current Warnings

The workflow may still show warnings such as:

```text
Node.js 20 is deprecated
line too long in loki-log-alert-rules.yaml
```

These warnings are acceptable.

The pipeline is considered successful when both jobs are green:

```text
YAML syntax and style: success
Kubernetes schema validation: success
```

---

## Merge Criteria

Before merging a validation branch into `main`, confirm:

```text
[ ] GitHub Actions workflow is green.
[ ] YAML syntax and style job passed.
[ ] Kubernetes schema validation job passed.
[ ] Remaining annotations are warnings only.
[ ] No actual errors remain.
[ ] Argo CD apps are still healthy.
```

Check Argo CD apps:

```bash
argocd app get garmin
argocd app get ring-health-tracker
```

Expected:

```text
Synced
Healthy
```

---

## Merge Procedure

From the feature branch:

```bash
git status
git push origin fix/week2-ci-validation
```

Switch to main:

```bash
git checkout main
git pull origin main
```

Merge:

```bash
git merge fix/week2-ci-validation
```

Push main:

```bash
git push origin main
```

Optionally delete the branch:

```bash
git branch -d fix/week2-ci-validation
git push origin --delete fix/week2-ci-validation
```

---

## Success Criteria for Week 2

Week 2 CI manifest validation is complete when:

```text
[ ] .yamllint exists.
[ ] .github/workflows/kubernetes-validate.yaml exists.
[x] GitHub Actions workflow runs on main (run 31790818607).
[x] yamllint job passes.
[x] kubeconform job passes.
[x] Helm render validation passes for monitoring, Loki, and Alloy.
[ ] Raw dashboard JSON is not scanned.
[ ] Helm values files are not schema-validated as Kubernetes manifests.
[ ] Vendor/generated MetalLB manifest is ignored.
[ ] Argo CD applications still sync successfully.
```

---

## Future Improvements

Possible future improvements:

```text
Add kubeconform schema locations for CRDs.
Add conftest or OPA policy checks.
Add Kyverno policy validation.
Add kube-score.
Add rendered Helm output schema validation.
Add markdown linting.
Make line-length warnings stricter after cleanup.
```

---

## Related Files

```text
.yamllint
.github/workflows/kubernetes-validate.yaml
kubernetes/gitops/argocd/applications/garmin.yaml
kubernetes/gitops/argocd/applications/ring-health-tracker.yaml
docs/runbooks/argocd-comparison-error.md
docs/runbooks/argocd-app-outofsync.md
```
