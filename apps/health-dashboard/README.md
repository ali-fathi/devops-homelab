# Health Dashboard — DevOps Study Guide

This README is both the application manual and a study guide for the complete delivery path of the Health Dashboard.

It explains:

- what the application does;
- how Garmin and Ring data reach the application;
- how the Python application is structured;
- how containers are built;
- how GitHub Actions tests and scans the image;
- why immutable image digests are used;
- how Kustomize and Argo CD deploy the application;
- how MetalLB exposes it on the homelab LAN;
- how secrets are delivered without storing credentials in Git;
- how to operate and troubleshoot the whole system.

This application is a personal health-data dashboard, not a medical device and not a source of medical advice.

---

## 1. Project goal

The goal is to take data already collected by the homelab and provide a private web dashboard:

```text
Garmin and Ring data
        ↓
Private time-series databases
        ↓
Flask API and web UI
        ↓
Kubernetes Deployment
        ↓
MetalLB LAN address
        ↓
Private browser access
```

The application does not communicate directly with a Garmin watch or a Ring.

The existing collectors do that work:

```text
Garmin watch
  → Garmin Connect mobile application
  → Garmin Connect cloud
  → garmin-fetch-data Kubernetes workload
  → InfluxDB

Colmi R02 ring
  → Ring Health Tracker Android application over BLE
  → Cloudflare Tunnel
  → VictoriaMetrics
```

The Health Dashboard is a read-only consumer of those two data stores.

---

## 2. Complete architecture

```text
┌─────────────────────────────────────────────────────────────────────┐
│                           GitHub repository                         │
│                                                                     │
│  apps/health-dashboard       Application source and Dockerfile       │
│  .github/workflows/          Test, build, scan, publish, write-back  │
│  kubernetes/applications/    Kubernetes resources and Kustomize     │
│  kubernetes/gitops/argocd/   Argo CD Application and AppProject      │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                │ Git push
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         GitHub Actions                              │
│                                                                     │
│  1. Install Python dependencies                                     │
│  2. Run unit tests                                                  │
│  3. Build OCI container image                                       │
│  4. Scan image with Trivy                                           │
│  5. Push image to GHCR                                              │
│  6. Capture immutable image digest                                  │
│  7. Update Kustomize image digest                                   │
│  8. Commit the deployment change                                    │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                │ Git commit containing digest
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                              Argo CD                                │
│                                                                     │
│  Reads the repository, renders Kustomize, compares desired/live     │
│  state, and synchronizes the Kubernetes cluster.                    │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          K3s Kubernetes                              │
│                                                                     │
│  namespace: health                                                  │
│    Deployment: health-dashboard                                     │
│    Service: health-dashboard                                        │
│    ExternalSecret: health-dashboard-secrets                         │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                │ MetalLB fixed LAN IP
                                ▼
                         192.168.178.216
                                │
                                ▼
                              Browser
```

At runtime, the Dashboard pod reads:

```text
InfluxDB:
  garmin-influxdb.garmin.svc.cluster.local:8086
  database: GarminStats

VictoriaMetrics:
  victoriametrics.ring-health.svc.cluster.local:8428
  device label: colmi_r02
```

---

## 3. Repository map

### Application source

```text
apps/health-dashboard/
├── app.py                 Flask API, database queries, reports
├── requirements.txt       Pinned Python dependencies
├── Dockerfile             Production container image
├── .dockerignore          Files excluded from image build context
├── tests/test_app.py      Unit and safety tests
├── templates/index.html   Dashboard HTML
└── static/
    ├── dashboard.js       Browser API calls and charts
    ├── style.css          UI styling
    └── chart.min.js       Chart.js browser library
```

### Kubernetes application

```text
kubernetes/applications/health-dashboard/
├── namespace.yaml         Namespace definition
├── configmap.yaml         Non-secret configuration
├── external-secret.yaml   Azure Key Vault → Kubernetes Secret
├── deployment.yaml        Pod and container configuration
├── service.yaml            MetalLB LoadBalancer Service
├── kustomization.yaml     Kustomize resource and image definition
└── README.md              Kubernetes operations guide
```

### GitOps definition

```text
kubernetes/gitops/argocd/
├── applications/health-dashboard.yaml
└── projects/homelab-platform-project.yaml
```

### CI/CD definition

```text
.github/workflows/health-dashboard-build.yaml
```

---

## 4. Runtime data flow

### 4.1 Garmin data flow

The Garmin collector is deployed separately in the `garmin` namespace.

```text
Garmin watch
  → Garmin Connect mobile synchronization
  → Garmin Connect cloud
  → garmin-fetch-data container
  → garmin-influxdb Service
  → InfluxDB database GarminStats
  → Health Dashboard query
```

The Dashboard expects these InfluxDB measurements and fields:

```text
SleepSummary:
  avgOvernightHrv
  sleepDuration
  sleepScore

DailyStats:
  totalSteps
  restingHeartRate
  activeMinutes
  caloriesBurned

ActivitySummary:
  type
  duration
  calories
  distance
  name
```

The Dashboard does not store Garmin credentials. Those credentials belong to the Garmin collector and are managed through External Secrets.

### 4.2 Ring data flow

```text
Colmi R02 ring
  → Android Ring Health Tracker app over Bluetooth
  → HTTPS Cloudflare Tunnel
  → VictoriaMetrics import endpoint
  → victoriametrics Service
  → Health Dashboard PromQL query
```

The Dashboard filters Ring metrics using:

```text
device="colmi_r02"
```

Expected metric names:

```text
biometric_hr_bpm
biometric_hrv_rmssd
biometric_spo2_pct
biometric_stress
ring_battery_pct
```

The public Cloudflare endpoint is used by the Android collector. The Dashboard uses the internal Kubernetes Service and does not need to traverse Cloudflare.

---

## 5. Application behavior and data integrity

### Production mode

Kubernetes sets:

```text
MOCK_DATA=false
```

In production mode:

- InfluxDB and VictoriaMetrics are queried directly.
- Database connection failures return HTTP `503`.
- The application never silently changes a production outage into mock data.
- Missing measurements remain `null`.
- Future dates are not generated.
- The current month ends on today’s date.
- Historical months end on their actual calendar month end.
- Recovery is calculated only when sleep score, HRV, and stress are available.
- `mocked: false` means the response came from production data access.

This is important because a dashboard must never display invented measurements while looking healthy.

### Mock mode

For local development only:

```bash
MOCK_DATA=true gunicorn --workers 2 --threads 2 --timeout 60 --bind 0.0.0.0:8080 app:app
```

Mock mode is deterministic for the same month. It is useful for UI work, PDF testing, and offline development.

It must not be enabled in Kubernetes.

### Missing data

A day may contain partial data:

- Garmin sleep but no Ring stress;
- Ring HRV but no Garmin workout;
- steps but no sleep record;
- no data at all.

The API represents unavailable fields as `null` and marks the row with:

```json
{
  "has_data": false,
  "data_status": "no-data"
}
```

Real rows use:

```json
{
  "has_data": true,
  "data_status": "real"
}
```

Mock rows use:

```json
{
  "has_data": true,
  "data_status": "mock"
}
```

---

## 6. Application code walkthrough

### Configuration

At startup, `app.py` reads:

```text
INFLUXDB_HOST
INFLUXDB_PORT
INFLUXDB_DATABASE
INFLUXDB_USERNAME
INFLUXDB_PASSWORD
VM_URL
RING_DEVICE
MOCK_DATA
DB_TIMEOUT_SECONDS
```

Credentials come from environment variables injected by Kubernetes. They are not hardcoded in the source.

### Date handling

The API accepts:

```text
YYYY-MM
```

If no month is supplied, it uses the current month.

Future months are rejected with HTTP `400` because they cannot contain real measurements.

### InfluxDB queries

The application executes three InfluxQL queries:

```text
SleepSummary
DailyStats
ActivitySummary
```

Results are grouped by calendar date and merged with Ring values.

### VictoriaMetrics queries

The application uses the range query API and PromQL functions:

```promql
avg_over_time(biometric_hrv_rmssd{device="colmi_r02"}[24h])
avg_over_time(biometric_hr_bpm{device="colmi_r02"}[24h])
avg_over_time(biometric_spo2_pct{device="colmi_r02"}[24h])
avg_over_time(biometric_stress{device="colmi_r02"}[24h])
last_over_time(ring_battery_pct{device="colmi_r02"}[24h])
```

The values are mapped to UTC calendar dates.

### Recovery calculation

The current deterministic formula is:

```text
recovery =
    0.4 × sleep_score
  + 0.4 × (HRV × 1.3)
  + 0.2 × (100 - stress)
```

The result is limited to the range `20–100`.

This is a project-specific heuristic. It is not clinically validated.

### Weekly narrative

The narrative engine:

1. Takes the last seven available calendar days.
2. Calculates monthly baselines from non-null measurements.
3. Compares the weekly values with those baselines.
4. Produces deterministic text.
5. Produces a score only when recovery data exists.

It does not call an AI service.

### Reports

PDF reports are generated in memory using ReportLab. The application is stateless and does not write reports to a persistent volume.

CSV and JSON exports are generated from the same database response used by the Dashboard.

---

## 7. Local development

### Requirements

Install:

```text
Python 3.11+
Docker
Git
```

### Run locally with mock data

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

### Test endpoints

```bash
curl http://localhost:8080/healthz
```

```bash
curl -s http://localhost:8080/api/health | jq
```

```bash
curl -L http://localhost:8080/api/report/download -o health-report.pdf
file health-report.pdf
```

### Run tests

```bash
python -m unittest discover -s tests -v
```

The tests verify:

- `/healthz` works;
- mock mode is explicit;
- current-month data does not extend into the future;
- production failures return `503` rather than mock data;
- missing real values remain empty.

---

## 8. Container concepts

A container image packages:

```text
Python runtime
Application source
Python dependencies
Runtime command
```

It does not package:

```text
Garmin credentials
Ring credentials
InfluxDB data
VictoriaMetrics data
Kubernetes configuration
```

Build locally:

```bash
docker build -t health-dashboard:local .
```

Run locally:

```bash
docker run --rm \
  -p 8080:8080 \
  -e MOCK_DATA=true \
  health-dashboard:local
```

The Dockerfile:

- uses `python:3.11-slim`;
- installs only required runtime packages;
- creates the fixed numeric non-root user/group `10001`;
- runs Gunicorn with two workers and two threads;
- uses the numeric identity so Kubernetes can verify `runAsNonRoot`;
- exposes port `8080`;
- does not contain health data.

The `.dockerignore` prevents virtual environments, tests, Git metadata, and temporary files from entering the image context.

---

## 9. GitHub Actions CI/CD pipeline

Workflow:

```text
.github/workflows/health-dashboard-build.yaml
```

### Trigger conditions

The workflow runs when:

```text
apps/health-dashboard/** changes
.github/workflows/health-dashboard-build.yaml changes
```

It runs for:

```text
push to main
pull requests
manual workflow dispatch
```

The automatic GitOps write-back happens only on pushes to `main`, never on pull requests.

### Test job

The test job:

1. Checks out the repository.
2. Installs Python 3.11.
3. Installs pinned dependencies.
4. Runs `unittest`.

A failed test stops the image build.

### Build job

The build job:

1. Waits for the test job.
2. Builds the Docker image.
3. Adds OCI metadata labels.
4. Scans the local image with Trivy.
5. Logs in to GHCR on main pushes.
6. Pushes the commit tag and `latest` tag.

Image tags:

```text
ghcr.io/ali-fathi/health-dashboard:<git-commit-sha>
ghcr.io/ali-fathi/health-dashboard:latest
```

### Trivy scan

The scan checks:

```text
Debian packages
Python packages
Known vulnerabilities
```

The workflow fails on:

```text
HIGH
CRITICAL
```

Unfixed vulnerabilities are ignored temporarily using `ignore-unfixed: true`. This should be reviewed periodically.

A Trivy message saying a newer Trivy version exists is informational. The important result is the vulnerability summary and exit code.

### Why the digest is captured

Tags are mutable:

```text
latest can point to different images over time
```

A digest identifies one exact image:

```text
sha256:abc123...
```

The workflow updates Kustomize to use:

```text
ghcr.io/ali-fathi/health-dashboard@sha256:abc123...
```

This gives:

- reproducible deployments;
- reliable rollbacks;
- protection from tag reuse;
- clear audit history;
- no manual image editing.

### GitOps write-back

After pushing the image, GitHub Actions updates:

```text
kubernetes/applications/health-dashboard/kustomization.yaml
```

It changes:

```yaml
newTag: latest
```

to:

```yaml
digest: sha256:...
```

Then the GitHub Actions bot commits the file to `main`.

This is the key GitOps principle:

```text
The cluster deploys what Git declares.
```

The workflow does not call `kubectl apply` directly. Argo CD performs the deployment.

### Branch protection improvement

The current workflow commits directly to `main`, which is convenient for this homelab.

For stricter production use:

```text
GitHub Actions creates a Pull Request instead.
A reviewer approves the image update.
The Pull Request merges into main.
Argo CD syncs the merged commit.
```

This provides a security approval gate while retaining automation.

---

## 10. Kustomize concepts

Kustomize is a Kubernetes configuration tool. It lets you keep a stable base manifest while changing deployment-specific values without editing the base Deployment every release.

The file is:

```text
kubernetes/applications/health-dashboard/kustomization.yaml
```

It lists resources:

```yaml
resources:
  - namespace.yaml
  - configmap.yaml
  - external-secret.yaml
  - deployment.yaml
  - service.yaml
```

It also defines the image transformation:

```yaml
images:
  - name: ghcr.io/ali-fathi/health-dashboard
    newName: ghcr.io/ali-fathi/health-dashboard
    digest: sha256:...
```

The base Deployment may contain `:latest`, but Kustomize renders the final resource with the digest.

Render locally:

```bash
kubectl kustomize kubernetes/applications/health-dashboard
```

Find the final image:

```bash
kubectl kustomize kubernetes/applications/health-dashboard | grep -A1 -B1 'image:'
```

Expected after CI write-back:

```text
image: ghcr.io/ali-fathi/health-dashboard@sha256:...
```

Argo CD detects `kustomization.yaml` automatically because the Argo Application uses:

```yaml
kustomize: {}
```

---

## 11. Kubernetes concepts

### Namespace

The application runs in:

```text
health
```

Namespaces provide logical separation from:

```text
garmin
ring-health
monitoring
logging
argocd
```

### Deployment

The Deployment manages the Health Dashboard pods.

It defines:

- desired replica count;
- pod labels;
- container image;
- environment variables;
- security settings;
- resource requests and limits;
- readiness probe;
- liveness probe.

### Readiness probe

The readiness probe calls:

```text
GET /healthz
```

A pod that fails readiness is removed from the Service endpoints.

This endpoint checks application process health only. Database freshness is checked separately through `/api/health`.

### Liveness probe

The liveness probe also calls `/healthz`.

If the process stops responding, Kubernetes restarts the pod.

### Service

The Service provides a stable endpoint for the pods. It selects pods using:

```yaml
app.kubernetes.io/name: health-dashboard
```

The Service exposes port `80` and forwards to container port `8080`.

### Resource requests and limits

Requests help Kubernetes schedule the pod:

```text
CPU: 100m
Memory: 256Mi
```

Limits prevent unlimited resource consumption:

```text
CPU: 500m
Memory: 768Mi
```

If PDF generation becomes memory intensive, inspect container memory usage before increasing limits.

---

## 12. MetalLB concepts

A normal cloud Kubernetes cluster can ask a cloud provider for a LoadBalancer IP. Bare-metal K3s cannot do that automatically.

MetalLB provides LoadBalancer behavior on the LAN.

The homelab pool is:

```text
192.168.178.210-192.168.178.220
```

The Health Dashboard requests:

```text
192.168.178.216
```

The Service includes:

```yaml
type: LoadBalancer
loadBalancerIP: 192.168.178.216
```

Access:

```text
http://192.168.178.216
```

The Service also restricts source traffic to:

```text
192.168.178.0/24
```

Change that range if the real LAN subnet differs.

Verify MetalLB:

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl get svc health-dashboard -n health
```

If the external IP is pending, check for:

- an IP conflict;
- an exhausted pool;
- a wrong address-pool annotation;
- MetalLB controller or speaker failure;
- K3s ServiceLB still being enabled.

---

## 13. Secrets and External Secrets

Credentials must not be committed to Git.

The desired flow is:

```text
Azure Key Vault
  → ClusterSecretStore: azure-keyvault
  → ExternalSecret in namespace health
  → Secret: health-dashboard-secrets
  → Deployment environment variables
```

The Dashboard needs:

```text
INFLUXDB_USERNAME
INFLUXDB_PASSWORD
```

The ExternalSecret reads:

```text
garmin-influxdb-username
garmin-influxdb-password
```

Verify the controller:

```bash
kubectl get pods -n external-secrets-system
kubectl get clustersecretstore azure-keyvault
```

Verify synchronization without printing secret values:

```bash
kubectl get externalsecret -n health
kubectl describe externalsecret health-dashboard-secrets -n health
kubectl describe secret health-dashboard-secrets -n health
```

Kubernetes Secrets are namespace-scoped. The Dashboard cannot reference `garmin-secrets` from the `garmin` namespace, which is why a separate ExternalSecret exists in `health`.

After rotating Azure Key Vault values:

```bash
kubectl annotate externalsecret health-dashboard-secrets \
  -n health force-sync="$(date +%s)" --overwrite
kubectl rollout restart deployment health-dashboard -n health
```

---

## 14. Argo CD and GitOps

The Argo CD Application is:

```text
kubernetes/gitops/argocd/applications/health-dashboard.yaml
```

It declares:

```text
Source repository: devops-homelab
Branch: main
Path: kubernetes/applications/health-dashboard
Project: homelab-platform
Destination namespace: health
```

The sync policy is:

```yaml
automated:
  enabled: true
  prune: false
  selfHeal: true
```

### Meaning of the sync policy

`automated` means Argo CD syncs detected Git changes.

`selfHeal` means Argo CD corrects manual drift.

`prune: false` means Argo CD does not automatically delete resources removed from Git. This is conservative and protects stateful infrastructure during adoption.

The Dashboard is stateless, but the same safety policy is used consistently in this homelab.

Check the application:

```bash
argocd app get health-dashboard
argocd app resources health-dashboard
argocd app diff health-dashboard
```

Refresh:

```bash
argocd app refresh health-dashboard --hard
```

Sync:

```bash
argocd app sync health-dashboard
```

Wait:

```bash
argocd app wait health-dashboard --health --sync
```

### Desired state versus live state

```text
Git manifests = desired state
Kubernetes resources = live state
Argo CD = reconciliation controller
```

Do not manually edit the Deployment as a permanent change. Edit Git, commit, and let Argo CD reconcile it.

---

## 15. First deployment procedure

### Prerequisites

```bash
kubectl get nodes
kubectl get pods -n metallb-system
kubectl get clustersecretstore azure-keyvault
kubectl get pods -n garmin
kubectl get pods -n ring-health
```

Confirm the GHCR package is public or configure an image-pull Secret.

Confirm the IP is free:

```bash
kubectl get svc -A -o wide | grep 192.168.178.216 || true
```

### Push the automation

```bash
git add apps/health-dashboard \
  .github/workflows/health-dashboard-build.yaml \
  kubernetes/applications/health-dashboard \
  kubernetes/gitops/argocd

git commit -m "Deploy health dashboard through automated GitOps"
git push origin main
```

### Wait for CI write-back

The first workflow should:

```text
Test
Build
Scan
Push image
Commit digest to Kustomize
```

Pull the bot commit:

```bash
git pull origin main
git log --oneline -5
```

Confirm:

```bash
grep -n "digest\|newTag" kubernetes/applications/health-dashboard/kustomization.yaml
```

### Register Argo CD

Run once:

```bash
kubectl apply -f kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
kubectl apply -f kubernetes/gitops/argocd/applications/health-dashboard.yaml
```

Sync:

```bash
argocd app sync health-dashboard
argocd app wait health-dashboard --health --sync
```

### Verify deployment

```bash
kubectl get pods,svc -n health
kubectl get externalsecret -n health
```

Expected:

```text
health-dashboard-xxxxx   1/1   Running
health-dashboard         LoadBalancer   ...   192.168.178.216
```

---

## 16. Real-data verification

### Check process health

```bash
curl http://192.168.178.216/healthz
```

Expected:

```json
{"status":"healthy"}
```

### Check InfluxDB network access

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

### Check VictoriaMetrics network access

```bash
kubectl exec -n health deployment/health-dashboard -- \
  curl -fsS \
  http://victoriametrics.ring-health.svc.cluster.local:8428/-/ready
```

Expected:

```text
OK
```

### Check the Dashboard API

```bash
curl -s http://192.168.178.216/api/health \
  | jq '{status, mocked, daily: {date, recovery_score, hrv, sleep_score, steps}}'
```

A real response must include:

```json
{
  "status": "ok",
  "mocked": false
}
```

`mocked: true` means explicit mock mode is active.

HTTP `503` means the application cannot access its production data sources. This is safer than showing fabricated values.

### Check exports

```bash
curl -L 'http://192.168.178.216/api/report/export?format=csv' -o health-report.csv
curl -L 'http://192.168.178.216/api/report/export?format=json' -o health-report.json
curl -L 'http://192.168.178.216/api/report/download' -o health-report.pdf
```

---

## 17. Day-2 operations

### Logs

```bash
kubectl logs -n health deployment/health-dashboard --tail=100
kubectl logs -n health deployment/health-dashboard -f
```

### Rollout status

```bash
kubectl rollout status deployment/health-dashboard -n health
kubectl rollout history deployment/health-dashboard -n health
```

### Restart

Use only for operational recovery or secret/configuration changes:

```bash
kubectl rollout restart deployment/health-dashboard -n health
```

### Scale

The application is stateless:

```bash
kubectl scale deployment health-dashboard -n health --replicas=2
```

Do not keep this manual change as the permanent configuration. Update `deployment.yaml` in Git if replicas should permanently change.

### Current image

```bash
kubectl get deployment health-dashboard -n health \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Expected:

```text
ghcr.io/ali-fathi/health-dashboard@sha256:...
```

### Rollback

Preferred rollback:

```text
Revert the Git commit that updated kustomization.yaml.
Push the revert.
Let Argo CD sync the previous digest.
```

Commands:

```bash
git log --oneline -10 -- kubernetes/applications/health-dashboard/kustomization.yaml
git revert <deployment-digest-commit>
git push origin main
argocd app sync health-dashboard
```

The application is stateless, so rollback does not modify Garmin or Ring data.

---

## 18. Troubleshooting

### GitHub Actions fails during tests

Check the test job first:

```text
Python syntax error
Dependency installation failure
Unit test failure
```

Run locally:

```bash
cd apps/health-dashboard
python -m unittest discover -s tests -v
```

### Trivy fails

Read the final vulnerability table, not only the download logs.

Typical fix:

```text
Upgrade the affected package in requirements.txt.
Rebuild the image.
Run the scan again.
```

Do not solve a real vulnerability by changing `exit-code` from `1` to `0`.

The message about a newer Trivy version is not itself a failure.

### Image does not push

Check:

```text
permissions.packages: write
GitHub token permissions
GHCR package name
repository owner spelling
```

### Automatic digest commit fails

Check:

```text
permissions.contents: write
main branch protection rules
GitHub Actions allowed to push
kustomization.yaml exists
```

If `main` is protected, change the workflow to create a Pull Request instead of pushing directly.

### Argo CD says comparison error

Check:

```bash
argocd app get health-dashboard
argocd app diff health-dashboard
kubectl describe application health-dashboard -n argocd
```

Common causes:

- invalid YAML;
- missing Kustomization file;
- invalid ExternalSecret API version;
- Argo CD cannot read the repository;
- `health` namespace is not allowed in the AppProject.

### Argo CD is OutOfSync

```bash
argocd app diff health-dashboard
argocd app refresh health-dashboard --hard
argocd app sync health-dashboard
```

If the live image is different from Git, check:

```bash
kubectl get deployment health-dashboard -n health \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

### Pod is `ImagePullBackOff`

Inspect:

```bash
kubectl describe pod -n health -l app.kubernetes.io/name=health-dashboard
```

Likely causes:

- GHCR package is private;
- image digest does not exist;
- package name is wrong;
- Kubernetes has no GHCR image-pull Secret;
- registry access is unavailable.

### Pod is `CrashLoopBackOff`

```bash
kubectl logs -n health deployment/health-dashboard --previous
kubectl describe pod -n health -l app.kubernetes.io/name=health-dashboard
```

Check:

- missing Secret;
- invalid `RING_DEVICE`;
- invalid environment variable;
- Python import failure;
- resource limit too low.

### ExternalSecret is not ready

```bash
kubectl get externalsecret -n health
kubectl describe externalsecret health-dashboard-secrets -n health
kubectl get clustersecretstore azure-keyvault
kubectl describe clustersecretstore azure-keyvault
kubectl get pods -n external-secrets-system
```

Check that these Azure Key Vault names exist:

```text
garmin-influxdb-username
garmin-influxdb-password
```

### API returns HTTP 503

Read logs:

```bash
kubectl logs -n health deployment/health-dashboard --tail=100
```

Test dependencies:

```bash
kubectl exec -n health deployment/health-dashboard -- \
  curl -fsS http://garmin-influxdb.garmin.svc.cluster.local:8086/ping
```

```bash
kubectl exec -n health deployment/health-dashboard -- \
  curl -fsS http://victoriametrics.ring-health.svc.cluster.local:8428/-/ready
```

Then verify:

- InfluxDB is Running;
- `GarminStats` exists;
- InfluxDB credentials are correct;
- VictoriaMetrics is Running;
- Ring metrics use `device="colmi_r02"`;
- Kubernetes DNS works.

### API reports `mocked: true`

Check:

```bash
kubectl get configmap health-dashboard-config -n health -o yaml
```

It must contain:

```yaml
MOCK_DATA: "false"
```

Check the running pod environment:

```bash
kubectl exec -n health deployment/health-dashboard -- printenv MOCK_DATA
```

### Service has no MetalLB address

```bash
kubectl describe svc health-dashboard -n health
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl get pods -n metallb-system
```

Check that `192.168.178.216` is inside the configured pool and not used by another Service.

### Dashboard shows no real measurements

Check Garmin measurements:

```bash
kubectl exec -n garmin deployment/garmin-influxdb -c influxdb -- /usr/bin/influx -host 127.0.0.1 -port 8086 -database GarminStats -execute 'SHOW MEASUREMENTS'
```

Check Ring metrics:

```bash
curl -G -s \
  --data-urlencode 'query=biometric_hr_bpm{device="colmi_r02"}' \
  http://192.168.178.214:8428/api/v1/query | jq
```

The dashboard cannot display data that has not been collected into the source databases.

---

## 19. Security model

Current protections:

- credentials are not stored in Git;
- credentials come from Azure Key Vault through External Secrets;
- the container runs as non-root;
- Linux capabilities are dropped;
- privilege escalation is disabled;
- the Kubernetes service is restricted to the LAN subnet;
- API responses are marked `no-store`;
- security response headers are set;
- image vulnerabilities are scanned before publication;
- image deployment uses immutable digests.

Current limitations:

- the dashboard has no user authentication;
- the LAN HTTP endpoint is not encrypted with TLS;
- users on the permitted LAN can access health data;
- the GHCR package may be public for easier cluster pulls.

Before exposing the Dashboard outside the trusted LAN, add:

```text
HTTPS
Authentication or Cloudflare Access
Authorization
Audit logging
NetworkPolicy where compatible with the cluster networking design
```

Do not expose this application publicly in its current form.

---

## 20. Backups and disaster recovery

The Dashboard itself is stateless and has no PVC.

The important data is stored elsewhere:

```text
Garmin InfluxDB PVC
Ring VictoriaMetrics PVC
```

Back up those Longhorn volumes:

```bash
kubectl get pvc -n garmin
kubectl get pvc -n ring-health
kubectl get volumes -n longhorn-system
```

A Dashboard image rollback does not restore lost health data. Data protection belongs to the InfluxDB and VictoriaMetrics storage layers.

Test restores periodically, not only backups.

---

## 21. Recommended future improvements

For stronger production operation:

```text
Create Pull Requests for image digest write-back.
Protect the main branch.
Make GHCR private and configure imagePullSecrets through External Secrets.
Add HTTPS through Traefik.
Add authentication with Cloudflare Access or an internal identity provider.
Add Prometheus metrics for request count, latency, and data-source failures.
Add a dedicated readiness endpoint that checks dependency availability separately.
Add request rate limiting.
Add structured JSON logging.
Add API response caching with a short TTL.
Add a scheduled data freshness alert.
Add restore-tested Longhorn backups.
```

---

## 22. Glossary

### Container image

A packaged filesystem and metadata used to create containers.

### OCI image

The open container image format used by Docker, GHCR, and Kubernetes registries.

### GHCR

GitHub Container Registry. It stores the built Health Dashboard image.

### Tag

A human-readable image reference such as `latest` or a Git SHA. Tags can move.

### Digest

A cryptographic immutable identifier such as `sha256:...`. It identifies exactly one image.

### Kubernetes Deployment

A controller that creates and updates pods according to a declared specification.

### Kubernetes Service

A stable network endpoint that routes traffic to selected pods.

### MetalLB

A bare-metal LoadBalancer implementation that assigns LAN IP addresses to Services.

### Kustomize

A Kubernetes manifest customization and rendering tool built into `kubectl`.

### Argo CD

A GitOps controller that reconciles Kubernetes resources with Git.

### ExternalSecret

A custom Kubernetes resource that copies secret values from an external secret manager into a Kubernetes Secret.

### InfluxDB

The Garmin time-series database used by this application.

### VictoriaMetrics

The Prometheus-compatible Ring time-series database used by this application.

### PromQL

The query language used to read metrics from VictoriaMetrics.

### InfluxQL

The query language used to read measurements from InfluxDB 1.x.

---

## 23. Quick command reference

```bash
# application status
kubectl get pods,svc -n health

# Argo CD status
argocd app get health-dashboard

# logs
kubectl logs -n health deployment/health-dashboard --tail=100

# LAN health check
curl http://192.168.178.216/healthz

# real-data check
curl -s http://192.168.178.216/api/health | jq '{status, mocked}'

# current deployed image
kubectl get deployment health-dashboard -n health \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

# force a sync
argocd app refresh health-dashboard --hard
argocd app sync health-dashboard

# inspect MetalLB
kubectl get svc health-dashboard -n health
kubectl get ipaddresspool -n metallb-system

# inspect secrets without printing values
kubectl describe externalsecret health-dashboard-secrets -n health
kubectl describe secret health-dashboard-secrets -n health
```
