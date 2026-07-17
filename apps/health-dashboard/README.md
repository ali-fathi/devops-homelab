# Health Dashboard

A **lightweight, privacy‑first** web application that aggregates Garmin and Oura Ring health data, visualises it in a modern glass‑morphic UI, generates a deterministic weekly narrative, and produces a premium PDF monthly report.  The app is designed to run **inside your own K3s homelab** – no third‑party SaaS, no AI, and all data stays private.

---

## Table of Contents
1. [Features](#features)
2. [Architecture Overview](#architecture-overview)
3. [Quick Start – Local Development](#quick-start--local-development)
4. [Running in K3s (Production)](#running-in-k3s-production)
5. [Configuration & Environment Variables](#configuration--environment-variables)
6. [API Endpoints](#api-endpoints)
7. [Docker Image](#docker-image)
8. [Testing the PDF Export](#testing-the-pdf-export)
9. [CI/CD Integration (GitOps/ArgoCD)](#cicd-integration-gitopsargocd)
10. [Screenshots & Design System](#screenshots--design-system)
11. [Troubleshooting](#troubleshooting)
12. [License](#license)

---

## Features
- **Unified Dashboard** – shows recovery/readiness, HR, HRV, SpO₂, stress, sleep, steps, calories, distance, active minutes, and latest Garmin stats.
- **Deterministic Weekly Narrative** – rule‑based health insights that are reproducible (useful for version‑controlled reporting).
- **Monthly PDF Report** – elegant, vector‑drawn chart, summary tables, and narrative using **ReportLab** (no external binaries like wkhtmltopdf).
- **Responsive Glass‑morphic UI** – vanilla HTML/CSS/JS, dark mode, custom colour palette, smooth micro‑animations.
- **Mock‑data fallback** – works out‑of‑the‑box without any external databases (set `MOCK_DATA=true`).
- **Dockerised & K3s ready** – small (~80 MB) image, health‑checks, and easy Helm/ArgoCD integration.

---

## Architecture Overview
```text
+----------------+      +-------------------+      +-------------------+
|  Browser (UI) | <--> | Flask (app.py)    | <--> | InfluxDB (Garmin) |
+----------------+      +-------------------+      +-------------------+
                               |
                               v
                     +-------------------+
                     | VictoriaMetrics    |
                     | (Ring health)      |
                     +-------------------+
```
- The **frontend** (`index.html`, `dashboard.js`, `style.css`) calls the Flask API.
- **Flask** loads data from:
  - **InfluxDB** (Garmin) via the `influxdb` client.
  - **VictoriaMetrics** (Ring) via HTTP PromQL.
- If any connection fails **or** `MOCK_DATA=true`, the app generates deterministic mock data (stable across months for the same seed).
- The **PDF** endpoint builds a ReportLab document on‑the‑fly, matching the UI colour scheme.

---

## Quick Start – Local Development
```bash
# 1️⃣ Clone the repo (if not already in the workspace)
cd /Users/alifathi/w/devops-homelab/apps/health-dashboard

# 2️⃣ (Re)create a virtual environment
python3 -m venv .venv
source .venv/bin/activate

# 3️⃣ Install Python dependencies
pip install -r requirements.txt

# 4️⃣ Optional – force mock mode (useful when you have no DBs yet)
export MOCK_DATA=true

# 5️⃣ Run the server (development mode with auto‑reload)
flask run --host 0.0.0.0 --port 8080   # or use gunicorn for prod
```
Open your browser at **http://localhost:8080/**. You should see the *Health Command Center* banner indicating **Demo / Mock Mode**.

### Verifying the PDF endpoint locally
```bash
curl -L "http://localhost:8080/api/report/download?month=$(date +%Y-%m)" -o health_report.pdf
file health_report.pdf   # should report PDF document
```
The generated PDF will be ~5 KB (mock data) and open in any PDF viewer.

---

## Running in K3s (Production)
### 1️⃣ Build & push the image
```bash
# From the health‑dashboard directory
docker build -t <your‑registry>/health-dashboard:latest .
# Push to a private registry reachable from your cluster
docker push <your‑registry>/health-dashboard:latest
```
Replace `<your‑registry>` with e.g. `registry.local:5000`.

### 2️⃣ Create ConfigMap & Secret (replace with your real values)
```yaml
# config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: health-dashboard-config
  namespace: health
data:
  INFLUXDB_HOST: "garmin-influxdb.garmin.svc.cluster.local"
  INFLUXDB_PORT: "8086"
  INFLUXDB_DATABASE: "GarminStats"
---
apiVersion: v1
kind: Secret
metadata:
  name: health-dashboard-secret
  namespace: health
type: Opaque
stringData:
  INFLUXDB_USERNAME: "myuser"
  INFLUXDB_PASSWORD: "mypassword"
  VM_URL: "http://victoriametrics.ring-health.svc.cluster.local:8428"
```
Apply with `kubectl apply -f config.yaml`.

### 3️⃣ Deploy the application (Deployment + Service + Ingress)
```yaml
# health-dashboard.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: health-dashboard
  namespace: health
spec:
  replicas: 1
  selector:
    matchLabels:
      app: health-dashboard
  template:
    metadata:
      labels:
        app: health-dashboard
    spec:
      containers:
        - name: app
          image: <your‑registry>/health-dashboard:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: health-dashboard-config
            - secretRef:
                name: health-dashboard-secret
          env:
            - name: MOCK_DATA
              value: "false"   # real data mode
          readinessProbe:
            httpGet:
              path: /api/health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 30
---
apiVersion: v1
kind: Service
metadata:
  name: health-dashboard
  namespace: health
spec:
  selector:
    app: health-dashboard
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: health-dashboard
  namespace: health
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  rules:
    - host: health.myhomelab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: health-dashboard
                port:
                  number: 80
  tls:
    - hosts:
        - health.myhomelab.local
      secretName: health-dashboard-tls
```
Apply: `kubectl apply -f health-dashboard.yaml`.

### 4️⃣ Verify inside the cluster
```bash
kubectl -n health port-forward svc/health-dashboard 8080:80
# then browse http://localhost:8080
```
If your real InfluxDB/VictoriaMetrics are reachable, the banner will show *Verified Homelab Dataset*.

---

## Configuration & Environment Variables
| Variable | Required? | Default | Description |
|----------|-----------|---------|-------------|
| `INFLUXDB_HOST` | yes (prod) | `garmin-influxdb.garmin.svc.cluster.local` |
| `INFLUXDB_PORT` | yes | `8086` |
| `INFLUXDB_DATABASE` | yes | `GarminStats` |
| `INFLUXDB_USERNAME` | no (optional) | empty |
| `INFLUXDB_PASSWORD` | no (optional) | empty |
| `VM_URL` | yes (prod) | `http://victoriametrics.ring-health.svc.cluster.local:8428` |
| `MOCK_DATA` | no | `false` | Set to `true` to bypass DB connections and use deterministic mock data.
| `PYTHONUNBUFFERED` | no | `1` | Ensures logs appear in real‑time (useful for Kubernetes).

All variables can be supplied via a **ConfigMap** (non‑secret) or a **Secret** for credentials.

---

## API Endpoints
| Method | Path | Query Params | Description |
|--------|------|--------------|-------------|
| `GET` | `/` | – | Serves the HTML UI. |
| `GET` | `/api/health` | `month=YYYY‑MM` (optional) | Returns JSON with latest daily metrics, chart arrays (last 14 days), weekly narrative, month‑over‑month comparison. |
| `GET` | `/api/report/download` | `month=YYYY‑MM` (optional) | Streams a PDF report. Content‑Disposition forces download. |
| `GET` | `/api/report/export` | `month=YYYY‑MM`, `format=csv|json` (default=`csv`) | Returns raw month data as CSV or JSON. |
| `POST` | `/api/report/regenerate` | – | Stub endpoint that would trigger a background refresh in a full system. |

All responses include a boolean `mocked` flag letting the front‑end display **Demo Mode** when real data is unavailable.

---

## Docker Image
- **Base**: `python:3.9-slim` (≈ 120 MB).
- **Multi‑stage** build installs only runtime dependencies (Flask, InfluxDB‑client, ReportLab, etc.).
- **Entry‑point**: `gunicorn -w 2 -b 0.0.0.0:8080 app:app`
- **Health checks** are defined in the Kubernetes manifest; the image itself does not need extra scripts.

You can run the image locally for a quick smoke test:
```bash
docker run -p 8080:8080 \
  -e MOCK_DATA=true \
  <your‑registry>/health-dashboard:latest
```
Then open **http://localhost:8080**.

---

## Testing the PDF Export
1. Start the app (local or in‑cluster).
2. Open the UI and click **Download PDF** → the browser should download `health_report_YYYY-MM.pdf`.
3. Or use `curl` as shown earlier.  Verify:
   - HTTP 200
   - `Content‑Type: application/pdf`
   - The file size > 1 KB (indicates content).  Open the PDF to see the title banner, summary table, vector chart, and narrative.

---

## CI/CD Integration (GitOps / ArgoCD)
1. **Repository layout** – the `apps/health-dashboard` folder is a self‑contained microservice.
2. **GitOps pipeline** – your existing ArgoCD application can target the `health-dashboard.yaml` manifest directory.
3. **Automated image build** – use a GitHub Actions workflow or a local CI that runs:
   ```yaml
   - name: Build & push Docker image
     run: |
       docker build -t ${{ env.REGISTRY }}/health-dashboard:${{ github.sha }} .
       docker push ${{ env.REGISTRY }}/health-dashboard:${{ github.sha }}
   ```
   The image tag can be injected into the Kubernetes manifest via Kustomize or Helm values.
4. **Rollback** – because the app is stateless and reads data from your homelab DBs, rolling back simply means redeploying the previous image tag.
5. **Observability** – the Flask app logs to stdout; collect with Loki/Promtail or the built‑in K3s log aggregation.

---

## Screenshots & Design System
The UI follows a **premium glass‑morphic design**:
- Primary colour palette (`--accent‑*`) generated from cool blues and purples.
- Dark background with subtle radial gradients (`--bg-color`).
- Cards have a semi‑transparent background (`--card-bg`) and a faint border (`--card-border`).
- Hover states use the `--accent‑*` gradients for a lively feel.
- Font: **Outfit** from Google Fonts (weights 300‑700).

> *If you need the actual screenshots, see the artifact images `tab1_command_center_…`, `tab2_weekly_narrative_…`, and `tab3_monthly_report_…` stored in the `.gemini` artifact directory.*

---

## Troubleshooting
| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| UI shows **Demo / Mock Mode** even though `MOCK_DATA=false` | DB host cannot be resolved or connection timeout. Check DNS, service names, and network policies. | Verify `INFLUXDB_HOST` and `VM_URL` point to reachable services. Use `kubectl exec` into the pod and `curl $INFLUXDB_HOST:8086/ping`. |
| PDF download returns **0 KB** or hangs | Out‑of‑memory in tiny containers (unlikely) or missing `reportlab` library. | Ensure the image built successfully (check Docker build logs). Re‑install `reportlab` in the `requirements.txt`. |
| `curl` returns *“Failed to resolve host”* | Wrong registry URL or missing `/etc/hosts` entry for intra‑cluster services. | Use the fully qualified service name `garmin-influxdb.garmin.svc.cluster.local`. |
| Flask logs disappear after a restart | Running with `debug=True` may reload and wipe log buffers. | Use Gunicorn or set `FLASK_ENV=production`. |

---

## License
MIT – feel free to fork, extend, and adapt to your own homelab.

---

*Happy hacking!  Your private health‑command center is now ready to run locally, docked, and orchestrated in K3s.*
