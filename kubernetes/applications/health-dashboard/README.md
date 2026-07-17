# Health Dashboard Kubernetes Application

This directory contains the production Kubernetes resources for the self-hosted Health Dashboard.

The dashboard combines:

```text
Garmin data  -> InfluxDB in namespace garmin
Ring data    -> VictoriaMetrics in namespace ring-health
Dashboard   -> Flask application in namespace health
```

The application is exposed on the LAN through MetalLB:

```text
http://192.168.178.216
```

The dashboard is intentionally not exposed publicly. It contains personal health information.

## Resources

```text
namespace.yaml        Namespace: health
configmap.yaml        Non-secret runtime configuration
external-secret.yaml  InfluxDB credentials from Azure Key Vault
deployment.yaml       Flask/Gunicorn Deployment
service.yaml          MetalLB LoadBalancer Service
```

## Prerequisites

The cluster must already have:

```text
K3s
MetalLB with the homelab-pool address pool
External Secrets Operator
Azure Key Vault ClusterSecretStore named azure-keyvault
Garmin InfluxDB
Ring VictoriaMetrics
Argo CD
```

Verify:

```bash
kubectl get nodes
kubectl get ipaddresspool -n metallb-system
kubectl get clustersecretstore azure-keyvault
kubectl get pods -n garmin
kubectl get pods -n ring-health
```

The Azure Key Vault must contain:

```text
garmin-influxdb-username
garmin-influxdb-password
```

The ExternalSecret copies those values into the `health` namespace. Kubernetes Secrets cannot be referenced across namespaces.

## Container image

GitHub Actions builds:

```text
ghcr.io/ali-fathi/health-dashboard:<commit-sha>
```

The Deployment is rendered with Kustomize. The base Deployment uses `latest`, but GitHub Actions automatically replaces it with the immutable registry digest after a successful image build.

The GHCR package must be public, or the namespace must have an image-pull Secret for a private package.

## GitOps deployment

The Argo CD Application is:

```text
kubernetes/gitops/argocd/applications/health-dashboard.yaml
```

The Argo CD project must allow the `health` namespace. That destination is configured in:

```text
kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
```

Deploy or sync:

```bash
kubectl apply -f kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
kubectl apply -f kubernetes/gitops/argocd/applications/health-dashboard.yaml
argocd app sync health-dashboard
argocd app wait health-dashboard --health --sync
```

Check status:

```bash
argocd app get health-dashboard
kubectl get all -n health
kubectl get externalsecret -n health
```

## MetalLB access

The Service requests:

```yaml
loadBalancerIP: 192.168.178.216
```

Confirm that the address is unused before deployment:

```bash
kubectl get svc -A -o wide | grep 192.168.178.216 || true
```

After deployment:

```bash
kubectl get svc health-dashboard -n health
curl http://192.168.178.216/healthz
```

Expected:

```json
{"status":"healthy"}
```

## Real-data verification

The application uses real data only when:

```text
MOCK_DATA=false
```

It reads:

```text
InfluxDB:
  garmin-influxdb.garmin.svc.cluster.local:8086
  database: GarminStats

VictoriaMetrics:
  victoriametrics.ring-health.svc.cluster.local:8428
```

Verify connectivity from the application pod:

```bash
kubectl exec -n health deployment/health-dashboard -- \
  curl -fsS http://garmin-influxdb.garmin.svc.cluster.local:8086/ping \
  -o /dev/null -w '%{http_code}\n'
```

Expected InfluxDB status:

```text
204
```

```bash
kubectl exec -n health deployment/health-dashboard -- \
  curl -fsS http://victoriametrics.ring-health.svc.cluster.local:8428/-/ready
```

Expected:

```text
OK
```

Check the Health API:

```bash
curl -s 'http://192.168.178.216/api/health' \
  | jq '{status, mocked, daily: {date, recovery_score, hrv, sleep_score, steps}}'
```

A real-data response must contain:

```json
{
  "status": "ok",
  "mocked": false
}
```

If the databases are unavailable, production mode returns HTTP 503. It does **not** silently display mock data. Mock data is available only when `MOCK_DATA=true` is explicitly configured.

## Operations

Logs:

```bash
kubectl logs -n health deployment/health-dashboard --tail=100 -f
```

Restart after a configuration or Secret update:

```bash
kubectl rollout restart deployment health-dashboard -n health
kubectl rollout status deployment health-dashboard -n health
```

Force ExternalSecret synchronization after changing Azure Key Vault:

```bash
kubectl annotate externalsecret health-dashboard-secrets \
  -n health force-sync="$(date +%s)" --overwrite
```

Export data:

```bash
curl -L 'http://192.168.178.216/api/report/export?format=csv' -o health-report.csv
curl -L 'http://192.168.178.216/api/report/export?format=json' -o health-report.json
curl -L 'http://192.168.178.216/api/report/download' -o health-report.pdf
```

## Image update workflow

```text
1. Change apps/health-dashboard.
2. Push to main.
3. GitHub Actions runs tests, builds, and scans the image.
4. GitHub Actions pushes the image and captures its immutable digest.
5. GitHub Actions updates kustomization.yaml and commits the digest.
6. Argo CD detects the Git change and syncs the new Deployment.
```

Example:

```bash
git add apps/health-dashboard
git commit -m "Update health dashboard"
git push origin main
```

After GitHub Actions succeeds, monitor the automatic deployment commit:

```bash
git log --oneline -5
argocd app refresh health-dashboard
argocd app wait health-dashboard --health --sync
```

## Safety notes

- This is a personal health-data application, not a medical device.
- Keep the Service LAN-only unless authentication and TLS are added.
- Do not commit InfluxDB credentials.
- Do not manually change the image tag; GitHub Actions writes the immutable digest to `kustomization.yaml`.
- The dashboard is stateless; Garmin and Ring data remain in their own PVC-backed databases.
- Back up the Garmin and VictoriaMetrics Longhorn volumes independently.
