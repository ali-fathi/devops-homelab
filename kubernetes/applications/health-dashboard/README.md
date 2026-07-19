# Health Dashboard Kubernetes Runbook

This directory is the Kubernetes/GitOps deployment layer for the Health Dashboard.

For the complete architecture and DevOps study explanation, read:

```text
apps/health-dashboard/README.md
```

This document focuses on operating the Kubernetes application.

---

## 1. Application contract

```text
Namespace: health
Service: health-dashboard
MetalLB IP: 192.168.178.216
Container port: 8080
Service port: 80
Argo CD Application: health-dashboard
```

The application reads:

```text
InfluxDB:
  garmin-influxdb.garmin.svc.cluster.local:8086
  database: GarminStats

VictoriaMetrics:
  victoriametrics.ring-health.svc.cluster.local:8428
  Ring device: colmi_r02
```

The Dashboard must run in production mode:

```text
MOCK_DATA=false
```

---

## 2. File responsibilities

```text
namespace.yaml
  Creates the health namespace.

configmap.yaml
  Stores non-secret runtime settings such as database hosts and RING_DEVICE.

external-secret.yaml
  Reads InfluxDB credentials from Azure Key Vault through External Secrets Operator.

deployment.yaml
  Defines the Deployment, container image, probes, resources, and security context.

service.yaml
  Exposes the Deployment through a fixed MetalLB LAN address.

kustomization.yaml
  Renders all resources and replaces the base image with the immutable digest written by CI.
```

The actual file name is `deployment.yaml`; the space before it above is only for alignment.

The image and Deployment both use numeric user/group ID `10001`. Kubernetes requires a numeric image user when `runAsNonRoot: true` is enabled.

---

## 3. Prerequisites

Verify Kubernetes access:

```bash
kubectl config current-context
kubectl get nodes -o wide
```

Verify MetalLB:

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

The address pool must contain:

```text
192.168.178.216
```

Verify External Secrets:

```bash
kubectl get pods -n external-secrets-system
kubectl get clustersecretstore azure-keyvault
```

Verify data sources:

```bash
kubectl get pods -n garmin
kubectl get pods -n ring-health
kubectl get svc -n garmin
kubectl get svc -n ring-health
```

Azure Key Vault must contain:

```text
garmin-influxdb-username
garmin-influxdb-password
health-dashboard-auth-username
health-dashboard-auth-password-hash
health-dashboard-flask-secret-key
```

Create the authentication values without committing a plaintext password:

```bash
PASSWORD_HASH="$(python3 -c 'from getpass import getpass; from werkzeug.security import generate_password_hash; print(generate_password_hash(getpass("Dashboard password: "), method="pbkdf2:sha256:1000000"))')"
FLASK_SECRET_KEY="$(openssl rand -hex 32)"

az keyvault secret set --vault-name "$KEY_VAULT_NAME" \
  --name health-dashboard-auth-username --value "ali" --output none
az keyvault secret set --vault-name "$KEY_VAULT_NAME" \
  --name health-dashboard-auth-password-hash --value "$PASSWORD_HASH" --output none
az keyvault secret set --vault-name "$KEY_VAULT_NAME" \
  --name health-dashboard-flask-secret-key --value "$FLASK_SECRET_KEY" --output none

unset PASSWORD_HASH FLASK_SECRET_KEY
```

Run the password-hash command from the application virtual environment where Werkzeug is installed. These values are referenced by `external-secret.yaml`; real values must never be committed to Git.

---

## 4. Image delivery model

The image is built by:

```text
.github/workflows/health-dashboard-build.yaml
```

The published image is:

```text
ghcr.io/ali-fathi/health-dashboard:<commit-sha>
```

The workflow also publishes `latest`, but Kubernetes does not permanently rely on that tag.

After the image is pushed, GitHub Actions captures the registry digest and changes `kustomization.yaml` from:

```yaml
newTag: latest
```

to:

```yaml
digest: sha256:...
```

Kustomize then renders the final image as:

```text
ghcr.io/ali-fathi/health-dashboard@sha256:...
```

This means:

- no manual image edit is needed;
- each deployment refers to one exact image;
- rollback is a Git revert;
- Argo CD remains the component that deploys Kubernetes resources.

The GHCR package must be public, or the namespace must have a valid image-pull Secret.

---

## 5. Kustomize rendering

Render the application locally:

```bash
kubectl kustomize kubernetes/applications/health-dashboard
```

Inspect the rendered image:

```bash
kubectl kustomize kubernetes/applications/health-dashboard \
  | grep -A1 -B1 'image:'
```

After the CI write-back commit, expect:

```text
image: ghcr.io/ali-fathi/health-dashboard@sha256:...
```

`kustomization.yaml` includes:

```text
namespace.yaml
configmap.yaml
external-secret.yaml
deployment.yaml
service.yaml
```

The Argo CD Application uses Kustomize and does not try to apply the README as a Kubernetes object.

---

## 6. First deployment

First verify the MetalLB address is unused:

```bash
kubectl get svc -A -o wide | grep 192.168.178.216 || true
```

Push the application and workflow to GitHub:

```bash
git add apps/health-dashboard \
  .github/workflows/health-dashboard-build.yaml \
  kubernetes/applications/health-dashboard \
  kubernetes/gitops/argocd

git commit -m "Deploy health dashboard through automated GitOps"
git push origin main
```

Wait for GitHub Actions to:

```text
Run tests
Build the image
Run Trivy
Push the image
Commit the image digest to kustomization.yaml
```

Pull the automatic bot commit:

```bash
git pull origin main
git log --oneline -5
```

Confirm the digest exists:

```bash
grep -n 'digest\|newTag' kustomization.yaml
```

Register the AppProject and Application once:

```bash
kubectl apply -f ../gitops/argocd/projects/homelab-platform-project.yaml
kubectl apply -f ../gitops/argocd/applications/health-dashboard.yaml
```

Sync:

```bash
argocd app refresh health-dashboard --hard
argocd app sync health-dashboard
argocd app wait health-dashboard --health --sync
```

---

## 7. Verify deployment

```bash
kubectl get all -n health
kubectl get externalsecret -n health
kubectl get secret -n health
```

Expected:

```text
health-dashboard-xxxxx   1/1   Running
health-dashboard         LoadBalancer   ...   192.168.178.216
```

Check Argo CD:

```bash
argocd app get health-dashboard
argocd app resources health-dashboard
```

Expected:

```text
Sync Status: Synced
Health Status: Healthy
```

Check the deployed image:

```bash
kubectl get deployment health-dashboard -n health \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Expected:

```text
ghcr.io/ali-fathi/health-dashboard@sha256:...
```

---

## 8. Verify ExternalSecret

```bash
kubectl get externalsecret health-dashboard-secrets -n health
kubectl describe externalsecret health-dashboard-secrets -n health
```

Check Secret key names without printing values:

```bash
kubectl describe secret health-dashboard-secrets -n health
```

Expected keys:

```text
INFLUXDB_USERNAME
INFLUXDB_PASSWORD
DASHBOARD_USERNAME
DASHBOARD_PASSWORD_HASH
FLASK_SECRET_KEY
```

If synchronization fails:

```bash
kubectl get clustersecretstore azure-keyvault
kubectl describe clustersecretstore azure-keyvault
kubectl get pods -n external-secrets-system
```

---

## 9. Verify MetalLB

```bash
kubectl get svc health-dashboard -n health
kubectl describe svc health-dashboard -n health
```

Expected:

```text
Type: LoadBalancer
External IP: 192.168.178.216
```

Test from the LAN:

```bash
curl http://192.168.178.216/healthz
```

Expected:

```json
{"status":"healthy"}
```

If no IP is assigned, check:

```bash
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl get pods -n metallb-system
kubectl get svc -A -o wide | grep 192.168.178.216
```

---

## 10. Verify source connectivity

InfluxDB connectivity from the Dashboard pod:

```bash
kubectl exec -n health deployment/health-dashboard -- \
  curl -fsS \
  http://garmin-influxdb.garmin.svc.cluster.local:8086/ping \
  -o /dev/null \
  -w '%{http_code}\n'
```

Expected:

```text
204
```

VictoriaMetrics connectivity:

```bash
kubectl exec -n health deployment/health-dashboard -- \
  curl -fsS \
  http://victoriametrics.ring-health.svc.cluster.local:8428/-/ready
```

Expected:

```text
OK
```

Check the API:

```bash
curl -s http://192.168.178.216/api/health \
  | jq '{status, mocked, daily: {date, recovery_score, hrv, sleep_score, steps}}'
```

Real production result:

```json
{
  "status": "ok",
  "mocked": false
}
```

The application returns HTTP `503` when production data sources cannot be read. It does not silently switch to mock values.

---

## 11. Argo CD operations

Refresh:

```bash
argocd app refresh health-dashboard --hard
```

View status:

```bash
argocd app get health-dashboard
```

View resources:

```bash
argocd app resources health-dashboard
```

View differences:

```bash
argocd app diff health-dashboard
```

Sync:

```bash
argocd app sync health-dashboard
```

Wait for health:

```bash
argocd app wait health-dashboard --health --sync
```

View history:

```bash
argocd app history health-dashboard
```

Do not use manual `kubectl edit` as a permanent configuration change. Make changes in Git.

---

## 12. Update and rollback

### Normal update

```text
Edit apps/health-dashboard
→ push main
→ GitHub Actions tests/builds/scans/pushes
→ GitHub Actions updates kustomization.yaml
→ Argo CD detects the Git commit
→ Kubernetes rolls out the digest
```

Monitor:

```bash
git pull origin main
git log --oneline -5
argocd app refresh health-dashboard
argocd app wait health-dashboard --health --sync
kubectl rollout status deployment/health-dashboard -n health
```

### Rollback

Find digest commits:

```bash
git log --oneline -- kustomization.yaml
```

Revert the bad deployment commit:

```bash
git revert <commit>
git push origin main
```

Sync:

```bash
argocd app sync health-dashboard
```

The Dashboard is stateless. Rollback does not change Garmin or Ring database contents.

---

## 13. Logs and runtime diagnostics

Application logs:

```bash
kubectl logs -n health deployment/health-dashboard --tail=100
kubectl logs -n health deployment/health-dashboard -f
```

Previous crashed container:

```bash
kubectl logs -n health deployment/health-dashboard --previous
```

Pod details:

```bash
kubectl describe pod -n health -l app.kubernetes.io/name=health-dashboard
```

Events:

```bash
kubectl get events -n health --sort-by=.metadata.creationTimestamp
```

Deployment status:

```bash
kubectl rollout status deployment/health-dashboard -n health
kubectl rollout history deployment/health-dashboard -n health
```

---

## 14. Troubleshooting table

| Symptom | Check | Common cause |
|---|---|---|
| `ImagePullBackOff` | `kubectl describe pod` | Private GHCR package or wrong digest |
| `CrashLoopBackOff` | `kubectl logs --previous` | Missing Secret, invalid config, import error |
| ExternalSecret not synced | `kubectl describe externalsecret` | Azure key missing or ClusterSecretStore failure |
| Service has no IP | `kubectl describe svc` | MetalLB pool/IP conflict |
| HTTP 503 from API | Application logs | InfluxDB or VictoriaMetrics unavailable |
| `mocked: true` | ConfigMap and pod env | `MOCK_DATA=true` accidentally deployed |
| No Garmin measurements | InfluxDB queries | Garmin collector not synchronized or field mismatch |
| No Ring measurements | VictoriaMetrics query | Ring app not ingesting or wrong device label |
| Argo `OutOfSync` | `argocd app diff` | Git/live drift or pending digest commit |
| Argo comparison error | `argocd app get` | Invalid Kustomize or Kubernetes manifest |
| Rollout stuck | `kubectl describe deployment` | Failed readiness, image pull, or resource issue |

---

## 15. Security and exposure

The Service is LAN-only:

```yaml
loadBalancerSourceRanges:
  - 192.168.178.0/24
```

The Dashboard requires a username and password. Passwords are verified against a Werkzeug password hash from Azure Key Vault; the plaintext password is not stored in Kubernetes or Git. `/healthz` remains public for Kubernetes probes, while the dashboard and all `/api/` endpoints require a valid session.

The LAN endpoint still uses plain HTTP. Do not expose it publicly, and remember that HTTP does not protect credentials from network interception. Before public exposure, add:

```text
HTTPS through Traefik
Cloudflare Access or VPN restriction
Audit logging
```

After HTTPS is enabled, set `SESSION_COOKIE_SECURE=true` in `configmap.yaml`.

Never commit:

```text
InfluxDB username
InfluxDB password
GHCR token
Azure credentials
```

---

## 16. Backups

The Dashboard has no PVC and is stateless.

Back up the data stores instead:

```bash
kubectl get pvc -n garmin
kubectl get pvc -n ring-health
```

Important PVCs:

```text
garmin-influxdb-data
garminconnect-tokens
victoriametrics-data
```

Use Longhorn backup and test restoration. An application image rollback cannot restore deleted health data.
