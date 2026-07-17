# Health Dashboard

A privacy-focused Flask application that combines Garmin data from InfluxDB with Colmi R02 Ring Health Tracker data from VictoriaMetrics.

```text
Garmin watch → Garmin Connect → garmin-fetch-data → InfluxDB
Colmi R02 ring → Android app → VictoriaMetrics
                                            ↓
                                  Health Dashboard
```

The dashboard runs inside the homelab. Garmin collection still depends on Garmin Connect, and Ring ingestion uses the configured Cloudflare Tunnel.

## Features

- Readiness/recovery, HR, HRV, sleep, stress, SpO₂, steps, calories, distance, and workouts.
- Deterministic weekly narrative based on available measurements.
- Monthly comparison, CSV/JSON export, and ReportLab PDF export.
- Responsive vanilla HTML/CSS/JavaScript interface.
- Explicit deterministic mock mode for local development.
- Production container running Gunicorn as a non-root user.

## Data integrity behavior

Production mode is enabled with:

```text
MOCK_DATA=false
```

In production mode:

- database failures return HTTP 503;
- the application never silently converts an outage into mock data;
- future days are not generated;
- missing measurements remain `null` rather than being replaced with invented defaults;
- readiness is calculated only when the measurements required by its formula exist;
- the API reports `mocked: false` for real data and `mocked: true` only when mock mode was explicitly enabled.

Mock mode is useful for development:

```bash
MOCK_DATA=true gunicorn --workers 2 --threads 2 --timeout 60 --bind 0.0.0.0:8080 app:app
```

## Local development

```bash
cd apps/health-dashboard
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
MOCK_DATA=true gunicorn --workers 2 --threads 2 --timeout 60 --bind 0.0.0.0:8080 app:app
```

Open:

```text
http://localhost:8080
```

Test the process endpoint:

```bash
curl http://localhost:8080/healthz
```

Test the API:

```bash
curl -s http://localhost:8080/api/health | jq
```

Test a PDF:

```bash
curl -L http://localhost:8080/api/report/download -o health-report.pdf
file health-report.pdf
```

Run unit tests:

```bash
python -m unittest discover -s tests -v
```

## Docker

The Docker image uses Python 3.11, installs the pinned dependencies, runs as a non-root user, and starts Gunicorn with two workers and two threads.

```bash
docker build -t health-dashboard:local .
docker run --rm -p 8080:8080 -e MOCK_DATA=true health-dashboard:local
```

The image does not contain health data or credentials.

## GitHub Actions

Workflow:

```text
.github/workflows/health-dashboard-build.yaml
```

The workflow:

1. runs the unit tests;
2. builds the image;
3. scans it with Trivy for HIGH and CRITICAL vulnerabilities;
4. publishes the image to GHCR on pushes to `main`.

Image name:

```text
ghcr.io/ali-fathi/health-dashboard:<commit-sha>
```

Kubernetes uses the immutable commit SHA tag rather than `latest`.

## Kubernetes deployment

Canonical manifests:

```text
kubernetes/applications/health-dashboard/
```

Argo CD Application:

```text
kubernetes/gitops/argocd/applications/health-dashboard.yaml
```

The application is deployed into namespace `health` and exposed by MetalLB at:

```text
http://192.168.178.216
```

Before deployment, confirm the address is unused:

```bash
kubectl get svc -A -o wide | grep 192.168.178.216 || true
```

The Kubernetes configuration uses:

```text
INFLUXDB_HOST=garmin-influxdb.garmin.svc.cluster.local
INFLUXDB_DATABASE=GarminStats
VM_URL=http://victoriametrics.ring-health.svc.cluster.local:8428
RING_DEVICE=colmi_r02
MOCK_DATA=false
```

InfluxDB credentials are loaded through an Azure Key Vault-backed ExternalSecret. They must not be committed to Git.

Deploy through Argo CD:

```bash
kubectl apply -f kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
kubectl apply -f kubernetes/gitops/argocd/applications/health-dashboard.yaml
argocd app sync health-dashboard
argocd app wait health-dashboard --health --sync
```

The image in `kubernetes/applications/health-dashboard/deployment.yaml` must be changed from:

```text
ghcr.io/ali-fathi/health-dashboard:REPLACE_WITH_GITHUB_SHA
```

to the SHA of a successful GitHub Actions build before syncing.

## Real-data verification

Check the application:

```bash
kubectl get pods,svc -n health
kubectl get externalsecret -n health
kubectl logs -n health deployment/health-dashboard --tail=100
```

Check the Service:

```bash
curl http://192.168.178.216/healthz
```

Check the data API:

```bash
curl -s http://192.168.178.216/api/health \
  | jq '{status, mocked, daily: {date, recovery_score, hrv, sleep_score, steps}}'
```

A valid real-data response must contain:

```json
{
  "status": "ok",
  "mocked": false
}
```

If data sources are unavailable, the API returns `503` with `status: data_unavailable`. This is intentional and prevents fake values from being presented as real health measurements.

## API endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | Web dashboard |
| `GET` | `/healthz` | Process health endpoint |
| `GET` | `/api/health?month=YYYY-MM` | Dashboard data and narratives |
| `GET` | `/api/report/export?format=csv` | CSV export |
| `GET` | `/api/report/export?format=json` | JSON export |
| `GET` | `/api/report/download` | PDF report |
| `POST` | `/api/report/regenerate` | Confirms the next request reads current data |

## Operations

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

Update flow:

```text
Change application code
→ push to main
→ GitHub Actions tests/builds/scans/publishes image
→ update Deployment to the new SHA
→ push manifest change
→ Argo CD syncs the new image
```

The application is stateless. Garmin and Ring data remain in their existing Longhorn-backed databases and must be backed up independently.

This dashboard is not a medical device and does not provide medical advice.
