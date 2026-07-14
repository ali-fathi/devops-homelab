# Runbook: Garmin Sync Failed

This runbook explains how to troubleshoot Garmin data sync issues in the homelab.

The Garmin workload fetches data and stores it in InfluxDB. Secrets are provided through External Secrets and Azure Key Vault.

---

## Architecture

```text
Azure Key Vault
  -> ExternalSecret garmin-secrets
  -> Garmin fetcher Deployment
  -> InfluxDB
  -> Grafana dashboards or queries
```

Namespace:

```text
garmin
```

Argo CD app:

```text
garmin
```

Manifest path:

```text
kubernetes/applications/garmin
```

---

## Symptoms

```text
Garmin dashboard is stale
No new data in InfluxDB
garmin-fetch-data pod failing
ExternalSecret not synced
Garmin app OutOfSync or Healthy but data is old
```

---

## Step 1: Check Argo CD

```bash
argocd app get garmin
argocd app diff garmin
argocd app resources garmin
```

Expected:

```text
Sync Status: Synced
Health Status: Healthy
```

If needed:

```bash
argocd app get garmin --hard-refresh
argocd app sync garmin
```

---

## Step 2: Check Garmin Pods

```bash
kubectl get pods -n garmin
```

Check logs from fetcher:

```bash
kubectl logs -n garmin deployment/garmin-fetch-data --tail=100
```

If there are multiple containers:

```bash
kubectl logs -n garmin deployment/garmin-fetch-data --all-containers=true --tail=100
```

Check previous crashed container logs:

```bash
kubectl logs -n garmin deployment/garmin-fetch-data --previous --tail=100
```

---

## Step 3: Check InfluxDB

Check pods:

```bash
kubectl get pods -n garmin | grep influxdb
```

Check service:

```bash
kubectl get svc -n garmin
```

Check PVC:

```bash
kubectl get pvc -n garmin
```

Expected PVCs:

```text
garmin-influxdb-data
garminconnect-tokens
```

Check InfluxDB logs:

```bash
kubectl logs -n garmin deployment/garmin-influxdb --tail=100
```

---

## Step 4: Check Garmin Secrets

Check ExternalSecret:

```bash
kubectl get externalsecret garmin-secrets -n garmin
kubectl describe externalsecret garmin-secrets -n garmin
```

Expected:

```text
Ready=True
Reason=SecretSynced
```

Check generated Kubernetes Secret:

```bash
kubectl get secret garmin-secrets -n garmin
```

Check ClusterSecretStore:

```bash
kubectl get clustersecretstore
kubectl describe clustersecretstore azure-keyvault
```

---

## Step 5: Force Secret Refresh

If credentials were rotated or changed:

```bash
kubectl annotate externalsecret garmin-secrets \
  -n garmin \
  force-sync="$(date +%s)" \
  --overwrite
```

Check again:

```bash
kubectl describe externalsecret garmin-secrets -n garmin
```

Restart Garmin fetcher if needed:

```bash
kubectl rollout restart deployment garmin-fetch-data -n garmin
```

---

## Step 6: Check Token PVC

Garmin may use a token/cache PVC.

Check:

```bash
kubectl get pvc garminconnect-tokens -n garmin
```

If token state is broken, investigate carefully before deleting anything.

Do not delete this PVC unless you understand the login/token consequences.

---

## Step 7: Check InfluxDB Data Path

Exec into InfluxDB pod if needed:

```bash
kubectl exec -n garmin -it deployment/garmin-influxdb -- sh
```

Inside the pod, inspect mounted paths depending on the image configuration.

Exit:

```bash
exit
```

Do not modify database files manually unless doing a planned recovery.

---

## Step 8: Restart Workloads Safely

Restart fetcher:

```bash
kubectl rollout restart deployment garmin-fetch-data -n garmin
kubectl rollout status deployment garmin-fetch-data -n garmin
```

Restart InfluxDB only if necessary:

```bash
kubectl rollout restart deployment garmin-influxdb -n garmin
kubectl rollout status deployment garmin-influxdb -n garmin
```

---

## Step 9: Common Root Causes

```text
Garmin credentials expired or changed.
Azure Key Vault secret value is wrong.
ExternalSecret is not Ready.
Garmin token cache is invalid.
InfluxDB pod is unhealthy.
InfluxDB PVC is full or unavailable.
Network issue from fetcher pod.
Image or environment variable changed.
Argo CD path or manifest drift.
```

---

## Step 10: Argo CD ExternalSecret Drift

If Argo CD shows ExternalSecret OutOfSync but health is Healthy, check for ESO default fields.

Expected defaults may need to exist in Git:

```yaml
remoteRef:
  key: garmin-connect-email
  conversionStrategy: Default
  decodingStrategy: None
  metadataPolicy: None
```

Apply to all `remoteRef` entries if needed.

Then:

```bash
git add kubernetes/applications/garmin/external-secret-garmin.yaml
git commit -m "Fix Garmin ExternalSecret default field drift"
git push origin main
argocd app sync garmin
```

---

## Step 11: Validate Recovery

After fixes:

```bash
kubectl get pods -n garmin
kubectl logs -n garmin deployment/garmin-fetch-data --tail=100
argocd app get garmin
argocd app diff garmin
```

Expected:

```text
Pods Running
No new errors in logs
Argo CD Synced
Argo CD Healthy
```

---

## What Not To Do

```text
Do not delete PVCs during normal troubleshooting.
Do not rotate secrets without updating Azure Key Vault.
Do not manually edit live Deployments without committing to Git.
Do not enable Argo CD pruning until backup and restore are tested.
Do not delete Garmin token PVC unless you accept re-authentication impact.
```

---

## Success Criteria

```text
[ ] Garmin Argo CD app is Synced and Healthy.
[ ] garmin-fetch-data pod is Running or completing as expected.
[ ] InfluxDB pod is Running.
[ ] PVCs are Bound.
[ ] ExternalSecret is Ready.
[ ] garmin-secrets exists.
[ ] Logs show successful Garmin fetch or no active credential error.
[ ] Grafana/InfluxDB data is updating again.
```
