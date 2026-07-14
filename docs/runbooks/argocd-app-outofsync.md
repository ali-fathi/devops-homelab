# Runbook: Argo CD Application OutOfSync

This runbook explains how to troubleshoot an Argo CD application that shows `OutOfSync`.

Use this runbook for applications such as:

```text
garmin
ring-health-tracker
future GitOps-managed apps
```

---

## Symptoms

Argo CD shows:

```text
Sync Status: OutOfSync
```

The application may still show:

```text
Health Status: Healthy
```

This means the live Kubernetes resources may still be running, but Argo CD detected a difference between Git desired state and live cluster state.

---

## First Checks

Check the application status:

```bash
argocd app get <app-name>
```

Example:

```bash
argocd app get garmin
argocd app get ring-health-tracker
```

Check the diff:

```bash
argocd app diff <app-name>
```

Check managed resources:

```bash
argocd app resources <app-name>
```

Check live Kubernetes resources:

```bash
kubectl get all -n <namespace>
```

Example:

```bash
kubectl get all -n garmin
kubectl get all -n ring-health
```

---

## Common Causes

### 1. Git changed but application has not synced yet

This is normal after a commit is pushed.

Check:

```bash
argocd app get <app-name>
```

If the target revision is newer than the synced revision, run:

```bash
argocd app sync <app-name>
```

---

### 2. Live resource was manually changed

Someone may have run:

```bash
kubectl edit ...
kubectl patch ...
kubectl scale ...
```

Argo CD sees this as drift from Git.

Check diff:

```bash
argocd app diff <app-name>
```

If Git is correct, sync the app:

```bash
argocd app sync <app-name>
```

If the live change is correct, update the manifest in Git instead.

---

### 3. Controller-added runtime fields

Some controllers add default fields or runtime metadata after resources are applied.

Examples:

```text
metadata.managedFields
status
controller-added annotations
defaulted CRD fields
```

If the diff is harmless, use Argo CD `ignoreDifferences` carefully.

Do not ignore important spec fields unless you fully understand the impact.

---

### 4. Argo CD is reading non-manifest files

If the application folder contains non-Kubernetes files such as:

```text
README.md
raw Grafana dashboard JSON
scripts
notes
```

Argo CD may try to process them if the Application is not restricted.

Recommended Application setting:

```yaml
directory:
  include: "{*.yaml,*.yml}"
```

---

### 5. Application source path is wrong

If an app was moved in the repo and Argo CD still points to the old path, Argo CD may show errors.

Check:

```bash
argocd app get <app-name>
```

Check live Application source path:

```bash
kubectl get application <app-name> -n argocd -o yaml | grep path -A3
```

Fix the path in:

```text
kubernetes/gitops/argocd/applications/<app-name>.yaml
```

Apply the fixed Application:

```bash
kubectl apply -f kubernetes/gitops/argocd/applications/<app-name>.yaml
```

---

## Standard Recovery Procedure

Use this safe sequence:

```bash
argocd app get <app-name>
argocd app diff <app-name>
argocd app resources <app-name>
```

If the diff is expected:

```bash
argocd app sync <app-name>
```

If the app still shows stale/cached state:

```bash
argocd app get <app-name> --hard-refresh
argocd app sync <app-name>
```

Wait for health and sync:

```bash
argocd app wait <app-name> --health --sync
```

---

## Garmin Examples

Check Garmin:

```bash
argocd app get garmin
argocd app diff garmin
argocd app resources garmin
```

Check Kubernetes side:

```bash
kubectl get pods -n garmin
kubectl get pvc -n garmin
kubectl get externalsecret -n garmin
kubectl get secret garmin-secrets -n garmin
```

Sync if needed:

```bash
argocd app sync garmin
```

---

## Ring Health Tracker Examples

Check Ring Health:

```bash
argocd app get ring-health-tracker
argocd app diff ring-health-tracker
argocd app resources ring-health-tracker
```

Check Kubernetes side:

```bash
kubectl get pods -n ring-health
kubectl get pvc -n ring-health
kubectl get svc -n ring-health
```

Check VictoriaMetrics:

```bash
curl -s http://192.168.178.214:8428/-/ready
```

Expected:

```text
OK
```

---

## What Not To Do

Do not randomly delete resources.

Do not enable pruning as a quick fix.

Do not rename PVCs or namespaces while troubleshooting.

Do not manually patch live resources and leave Git unchanged.

Do not ignore Argo CD diffs without understanding what changed.

---

## Success Criteria

The issue is resolved when:

```text
[ ] argocd app get <app-name> shows Synced.
[ ] Health Status is Healthy.
[ ] argocd app diff <app-name> shows no unexpected diff.
[ ] Kubernetes pods are Running.
[ ] PVCs are Bound if the app is stateful.
[ ] ExternalSecrets are Ready if the app uses secrets.
```
