# Kubernetes Applications

This directory contains application workloads that run on the homelab Kubernetes cluster.

Applications in this directory are intended to be managed declaratively through GitOps using Argo CD.

---

## Purpose

The `applications/` directory is for workloads that provide application-level functionality.

These are not core Kubernetes platform components. They are applications, services, data-ingestion workloads, demos, or self-hosted tools that run on top of the platform.

Examples:

```text
garmin
ring-health-tracker
nginx-longhorn-metallb
future demo apps
future internal services
```

---

## Current Applications

```text
applications/
├── garmin/
├── health-dashboard/
├── nginx-longhorn-metallb/
└── ring-health-tracker/
```

---

## Application Directory Rules

Each application should have its own directory:

```text
kubernetes/applications/<app-name>/
```

Each application should include a `README.md` explaining:

```text
What the app does
Which namespace it uses
Which external services it depends on
Which secrets it needs
Which persistent volumes it uses
How to test it
How to troubleshoot it
How Argo CD manages it
```

---

## Recommended Application Structure

A typical application folder should look like this:

```text
app-name/
├── namespace.yaml
├── deployment.yaml
├── service.yaml
├── pvc.yaml                    # optional
├── external-secret.yaml        # optional
├── configmap.yaml              # optional
├── grafana-datasource.yaml     # optional
├── grafana-dashboard.yaml      # optional
├── README.md
└── assets/                     # optional, for raw dashboard JSON or support files
```

For example:

```text
ring-health-tracker/
├── deployment.yaml
├── grafana/
│   └── ring-health-dashboard.json
├── grafana-dashboard.yaml
├── grafana-datasource.yaml
├── namespace.yaml
├── pvc.yaml
├── README.md
└── service.yaml
```

---

## GitOps Rules

All production-like application changes should be made through Git.

Recommended workflow:

```bash
git checkout -b feature/update-app

nano kubernetes/applications/<app-name>/<file>.yaml

git add kubernetes/applications/<app-name>
git commit -m "Update <app-name>"
git push origin feature/update-app
```

Then either:

```bash
argocd app sync <app-name>
```

or let Argo CD auto-sync the app.

---

## Argo CD Application Location

Argo CD Application manifests for apps in this directory live under:

```text
kubernetes/gitops/argocd/applications/
```

Example:

```text
kubernetes/gitops/argocd/applications/garmin.yaml
kubernetes/gitops/argocd/applications/ring-health-tracker.yaml
```

Each Argo CD Application should point to the matching app folder.

Example:

```yaml
source:
  repoURL: https://github.com/ali-fathi/devops-homelab.git
  targetRevision: main
  path: kubernetes/applications/garmin
```

---

## Important Argo CD Directory Rule

If an application folder contains non-Kubernetes files such as:

```text
README.md
JSON dashboards
scripts
notes
raw config files
```

then the Argo CD Application should restrict which files are treated as Kubernetes manifests.

Recommended:

```yaml
directory:
  include: "{*.yaml,*.yml}"
```

This prevents Argo CD from trying to apply non-Kubernetes files such as raw Grafana dashboard JSON.

---

## Stateful Application Rules

Applications with persistent data must be treated carefully.

Examples:

```text
garmin InfluxDB
ring-health-tracker VictoriaMetrics
```

For stateful apps:

```text
Keep prune=false during initial GitOps adoption.
Do not rename PVCs casually.
Do not rename namespaces casually.
Do not rename StatefulSet or Deployment selectors casually.
Back up data before major changes.
Document restore procedures.
```

Recommended Argo CD sync policy for stateful apps:

```yaml
syncPolicy:
  automated:
    enabled: true
    prune: false
    selfHeal: true
```

Only enable pruning after:

```text
Backups are configured.
Restore has been tested.
The app has been stable for several days.
You fully understand all Argo CD diffs.
```

---

## Current GitOps-Managed Applications

### Garmin

Path:

```text
kubernetes/applications/garmin
```

Argo CD app:

```text
kubernetes/gitops/argocd/applications/garmin.yaml
```

Namespace:

```text
garmin
```

Main components:

```text
Garmin data fetcher
InfluxDB
ExternalSecret
PVCs
```

---

### Health Dashboard

Path:

```text
kubernetes/applications/health-dashboard
```

Argo CD app:

```text
kubernetes/gitops/argocd/applications/health-dashboard.yaml
```

Namespace:

```text
health
```

Main components:

```text
Flask/Gunicorn dashboard
ExternalSecret for InfluxDB credentials
LAN-only MetalLB Service at 192.168.178.216
```

The dashboard reads Garmin InfluxDB and Ring VictoriaMetrics data. It must run with `MOCK_DATA=false` in the cluster.

---

### Ring Health Tracker

Path:

```text
kubernetes/applications/ring-health-tracker
```

Argo CD app:

```text
kubernetes/gitops/argocd/applications/ring-health-tracker.yaml
```

Namespace:

```text
ring-health
```

Main components:

```text
VictoriaMetrics
Longhorn PVC
MetalLB service
Grafana datasource
Grafana dashboard
Cloudflare-protected ingest endpoint
```

---

## Validation Commands

Check all application folders:

```bash
tree kubernetes/applications
```

Check Argo CD apps:

```bash
argocd app list
```

Check app status:

```bash
argocd app get garmin
argocd app get ring-health-tracker
```

Check app diffs:

```bash
argocd app diff garmin
argocd app diff ring-health-tracker
```

Check managed resources:

```bash
argocd app resources garmin
argocd app resources ring-health-tracker
```

---

## Troubleshooting

If Argo CD shows:

```text
ComparisonError
Object 'Kind' is missing
```

then Argo CD is probably trying to process a non-Kubernetes file.

Fix the Application manifest with:

```yaml
directory:
  include: "{*.yaml,*.yml}"
```

If Argo CD shows:

```text
app path does not exist
```

then the Application source path is wrong.

Check:

```bash
argocd app get <app-name>
kubectl get application <app-name> -n argocd -o yaml | grep path -A3
```

Fix the path in:

```text
kubernetes/gitops/argocd/applications/<app-name>.yaml
```

---

## Future Application Ideas

Possible future apps for learning:

```text
homelab-api
demo-nginx
demo-api-rollouts
internal-status-page
backup-dashboard
personal-automation-service
```

Each future app should follow the same structure and GitOps workflow.