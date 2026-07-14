# Runbook: Argo CD ComparisonError

This runbook explains how to troubleshoot Argo CD `ComparisonError` conditions.

A `ComparisonError` means Argo CD cannot correctly compare the desired state from Git with the live Kubernetes state.

---

## Symptoms

Argo CD may show:

```text
ComparisonError
```

Common messages:

```text
Failed to load target state
failed to generate manifest
app path does not exist
Object 'Kind' is missing
Failed to unmarshal
```

The application may show:

```text
Sync Status: Unknown
Health Status: Healthy
```

This means the live app might still be running, but Argo CD cannot render or compare the desired manifests from Git.

---

## First Checks

Check the app:

```bash
argocd app get <app-name>
```

Check the live Argo CD Application object:

```bash
kubectl get application <app-name> -n argocd -o yaml
```

Check source path:

```bash
kubectl get application <app-name> -n argocd -o yaml | grep path -A3
```

Check the Git repo path locally:

```bash
ls -la <path-from-argocd>
```

Example:

```bash
ls -la kubernetes/applications/garmin
ls -la kubernetes/applications/ring-health-tracker
```

---

## Case 1: App Path Does Not Exist

### Error

```text
app path does not exist
```

Example:

```text
kubernetes/observability/garmin: app path does not exist
```

### Cause

The Argo CD Application points to an old or incorrect Git path.

This often happens after moving an application folder.

Example:

Old path:

```text
kubernetes/observability/garmin
```

New path:

```text
kubernetes/applications/garmin
```

### Fix

Edit the Argo CD Application manifest:

```bash
nano kubernetes/gitops/argocd/applications/<app-name>.yaml
```

Update:

```yaml
path: kubernetes/applications/<app-name>
```

Apply the fixed Application:

```bash
kubectl apply -f kubernetes/gitops/argocd/applications/<app-name>.yaml
```

Hard refresh:

```bash
argocd app get <app-name> --hard-refresh
```

Sync:

```bash
argocd app sync <app-name>
```

---

## Case 2: Object Kind Is Missing

### Error

```text
Object 'Kind' is missing
```

or:

```text
Failed to unmarshal "file.json": Object 'Kind' is missing
```

### Cause

Argo CD is trying to process a non-Kubernetes file as a Kubernetes manifest.

Common examples:

```text
raw Grafana dashboard JSON
README files
application config JSON
notes or examples
```

Argo CD expects Kubernetes manifests to include:

```yaml
apiVersion: ...
kind: ...
```

Raw Grafana dashboard JSON does not include those fields.

### Fix

Restrict the Argo CD Application to YAML manifests only:

```yaml
source:
  directory:
    include: "{*.yaml,*.yml}"
```

Example full source block:

```yaml
source:
  repoURL: https://github.com/ali-fathi/devops-homelab.git
  targetRevision: main
  path: kubernetes/applications/ring-health-tracker
  directory:
    include: "{*.yaml,*.yml}"
```

Move raw JSON files into a subfolder if needed:

```bash
mkdir -p kubernetes/applications/ring-health-tracker/grafana
mv kubernetes/applications/ring-health-tracker/*.json kubernetes/applications/ring-health-tracker/grafana/
```

Wrap the dashboard JSON into a Kubernetes ConfigMap YAML:

```bash
kubectl create configmap ring-health-dashboard \
  -n monitoring \
  --from-file=ring-health-dashboard.json=kubernetes/applications/ring-health-tracker/grafana/ring-health-dashboard.json \
  --dry-run=client -o yaml > kubernetes/applications/ring-health-tracker/grafana-dashboard.yaml
```

Add Grafana sidecar label:

```yaml
metadata:
  labels:
    grafana_dashboard: "1"
```

---

## Case 3: Invalid YAML

### Error

```text
failed to generate manifest
yaml: line X: did not find expected key
```

### Cause

A YAML file contains invalid indentation or syntax.

### Fix

Validate locally:

```bash
yamllint kubernetes
```

Or use server-side dry run:

```bash
kubectl apply --dry-run=server -f <manifest.yaml>
```

Fix the YAML and commit again.

---

## Case 4: Missing CRD Schema or Unknown Kind

### Error

```text
no matches for kind
```

or:

```text
unknown resource type
```

### Cause

The cluster does not know the resource kind yet.

Examples:

```text
ExternalSecret without External Secrets Operator CRDs
Application without Argo CD CRDs
PrometheusRule without Prometheus Operator CRDs
```

### Fix

Check CRDs:

```bash
kubectl get crd | grep external-secrets
kubectl get crd | grep argoproj
kubectl get crd | grep monitoring.coreos.com
```

Install or restore the missing operator/CRD first.

---

## Standard Recovery Procedure

Use this sequence:

```bash
argocd app get <app-name>
kubectl get application <app-name> -n argocd -o yaml | grep path -A4
ls -la <app-source-path>
```

If the path is wrong:

```bash
nano kubernetes/gitops/argocd/applications/<app-name>.yaml
kubectl apply -f kubernetes/gitops/argocd/applications/<app-name>.yaml
```

Then:

```bash
argocd app get <app-name> --hard-refresh
argocd app sync <app-name>
```

---

## Git Commit After Fix

After fixing an Application manifest:

```bash
git add kubernetes/gitops/argocd/applications/<app-name>.yaml
git commit -m "Fix <app-name> Argo CD application path"
git push origin main
```

If files were moved:

```bash
git add -A
git commit -m "Move <app-name> manifests to applications directory"
git push origin main
```

---

## Success Criteria

The issue is resolved when:

```text
[ ] Argo CD no longer shows ComparisonError.
[ ] Application source path exists in Git.
[ ] Application renders manifests successfully.
[ ] App is Synced.
[ ] App is Healthy.
```
