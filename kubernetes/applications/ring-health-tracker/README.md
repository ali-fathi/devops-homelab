# Ring Health Tracker Backend

Self-hosted VictoriaMetrics backend for the Ring Health Tracker Android app and Colmi R02 smart ring.

This setup stores biometric data in the homelab instead of sending the data to a vendor cloud. The Android app connects to the ring over BLE/GATT, collects biometric samples, and pushes Prometheus-style metrics to VictoriaMetrics. Grafana then queries VictoriaMetrics using PromQL.

---

## Overview

This deployment provides the server-side backend for:

```text
Colmi R02 ring
  -> Android Ring Health Tracker app
  -> Cloudflare Zero Trust Tunnel
  -> VictoriaMetrics on Kubernetes
  -> Grafana
```

External endpoint used by the Android app:

```text
https://ring-health.greyneo.com/api/v1/import/prometheus
```

Internal homelab endpoint exposed by MetalLB:

```text
http://192.168.178.214:8428
```

Internal Kubernetes service used by Grafana:

```text
http://victoriametrics.ring-health.svc.cluster.local:8428
```

VictoriaMetrics supports the `/api/v1/import/prometheus` endpoint for importing Prometheus text exposition format metrics, which is the endpoint used by the Android app.

---

## Architecture

```text
+----------------+
| Colmi R02 Ring |
+----------------+
        |
        | BLE / GATT
        v
+-----------------------------+
| Ring Health Tracker Android |
| app                         |
+-----------------------------+
        |
        | HTTPS
        v
+-----------------------------------------------+
| https://ring-health.greyneo.com               |
| /api/v1/import/prometheus                     |
+-----------------------------------------------+
        |
        | Cloudflare Zero Trust Tunnel
        v
+----------------------------------+
| http://192.168.178.214:8428      |
| MetalLB LoadBalancer service     |
+----------------------------------+
        |
        v
+------------------------------+
| VictoriaMetrics              |
| namespace: ring-health       |
+------------------------------+
        |
        | PromQL
        v
+------------------------------+
| Grafana                      |
| namespace: monitoring        |
+------------------------------+
```

The Ring Health Tracker project documents metrics such as heart rate, HRV, stress, SpO2, steps, calories, distance, sleep stages, ring battery, and charging state. The metrics include the label `device="colmi_r02"`.

---

## Components

This deployment creates:

```text
Namespace: ring-health
PVC: victoriametrics-data
Deployment: victoriametrics
Service: victoriametrics
Grafana datasource ConfigMap
Optional Grafana dashboard ConfigMap
Argo CD Application
```

---

## Directory Structure

Recommended repository structure:

```text
kubernetes/applications/ring-health-tracker/
├── namespace.yaml
├── pvc.yaml
├── deployment.yaml
├── service.yaml
├── grafana-datasource.yaml
├── grafana-dashboard.yaml        # optional after dashboard import
├── README.md
└── grafana/
    └── ring-health-dashboard.json # optional after dashboard import

kubernetes/gitops/argocd/applications/
└── ring-health-tracker.yaml
```

---

## Prerequisites

Required cluster components:

```text
K3s
MetalLB
Longhorn
Grafana
Argo CD
Cloudflare Zero Trust Tunnel
```

Required local tools:

```text
kubectl
argocd CLI
git
curl
jq
```

Verify Kubernetes access:

```bash
kubectl get nodes
kubectl get pods -A
```

Verify Argo CD CLI:

```bash
argocd version --client
```

Verify MetalLB pool:

```bash
kubectl get ipaddresspool -n metallb-system
```

Expected pool example:

```text
homelab-pool   true   192.168.178.210-192.168.178.220
```

The Ring Health Tracker backend uses:

```text
192.168.178.214
```

---

## Cloudflare Tunnel Assumption

Cloudflare Zero Trust Tunnel handles public HTTPS:

```text
https://ring-health.greyneo.com
```

The tunnel origin should point to the internal MetalLB endpoint:

```text
http://192.168.178.214:8428
```

Recommended Cloudflare public hostname mapping:

```text
Public hostname:
  ring-health.greyneo.com

Service:
  http://192.168.178.214:8428
```

The Kubernetes deployment itself only serves plain HTTP.

---

## Security Notes

This endpoint accepts biometric metrics:

```text
https://ring-health.greyneo.com/api/v1/import/prometheus
```

Because this endpoint receives personal health data, the public endpoint should not be left open without access control.

Recommended protections:

```text
Cloudflare Zero Trust Access policy
VPN-only access
Identity-based access rules
Device posture rules
IP allowlisting if applicable
```

The goal of this project is to avoid vendor-cloud telemetry and keep biometric data under local control.

---

## Kubernetes Manifests

### `namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ring-health
  labels:
    app.kubernetes.io/name: ring-health-tracker
    app.kubernetes.io/part-of: health-observability
```

---

### `pvc.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: victoriametrics-data
  namespace: ring-health
  labels:
    app.kubernetes.io/name: victoriametrics
    app.kubernetes.io/part-of: ring-health-tracker
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 5Gi
```

---

### `deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: victoriametrics
  namespace: ring-health
  labels:
    app.kubernetes.io/name: victoriametrics
    app.kubernetes.io/part-of: ring-health-tracker
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: victoriametrics
  template:
    metadata:
      labels:
        app.kubernetes.io/name: victoriametrics
        app.kubernetes.io/part-of: ring-health-tracker
    spec:
      securityContext:
        fsGroup: 65534

      containers:
        - name: victoriametrics
          image: victoriametrics/victoria-metrics:v1.119.0
          imagePullPolicy: IfNotPresent

          args:
            - "-storageDataPath=/storage"
            - "-retentionPeriod=12"
            - "-httpListenAddr=:8428"

          ports:
            - name: http
              containerPort: 8428

          readinessProbe:
            httpGet:
              path: /-/ready
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10

          livenessProbe:
            httpGet:
              path: /-/healthy
              port: http
            initialDelaySeconds: 30
            periodSeconds: 30

          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi

          volumeMounts:
            - name: data
              mountPath: /storage

      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: victoriametrics-data
```

---

### `service.yaml`

This service exposes VictoriaMetrics internally through MetalLB:

```text
http://192.168.178.214:8428
```

Cloudflare Tunnel should use this endpoint as the origin.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: victoriametrics
  namespace: ring-health
  labels:
    app.kubernetes.io/name: victoriametrics
    app.kubernetes.io/part-of: ring-health-tracker
  annotations:
    metallb.universe.tf/address-pool: homelab-pool
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.178.214

  selector:
    app.kubernetes.io/name: victoriametrics

  ports:
    - name: http
      port: 8428
      targetPort: http
```

---

### `grafana-datasource.yaml`

This ConfigMap provisions VictoriaMetrics as a Prometheus-compatible datasource in Grafana.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-ring-health-victoriametrics
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  ring-health-victoriametrics.yaml: |
    apiVersion: 1
    datasources:
      - name: Ring Health VictoriaMetrics
        type: prometheus
        uid: ring-health-victoriametrics
        access: proxy
        url: http://victoriametrics.ring-health.svc.cluster.local:8428
        isDefault: false
        editable: true
```

---

## Manual Deployment Before GitOps

Apply the manifests manually first to validate the setup:

```bash
kubectl apply -f kubernetes/applications/ring-health-tracker/namespace.yaml
kubectl apply -f kubernetes/applications/ring-health-tracker/pvc.yaml
kubectl apply -f kubernetes/applications/ring-health-tracker/deployment.yaml
kubectl apply -f kubernetes/applications/ring-health-tracker/service.yaml
kubectl apply -f kubernetes/applications/ring-health-tracker/grafana-datasource.yaml
```

Verify namespace:

```bash
kubectl get namespace ring-health
```

Verify pods:

```bash
kubectl get pods -n ring-health
```

Expected:

```text
victoriametrics-xxxxx   1/1   Running
```

Verify PVC:

```bash
kubectl get pvc -n ring-health
```

Expected:

```text
victoriametrics-data   Bound
```

Verify service:

```bash
kubectl get svc -n ring-health
```

Expected:

```text
victoriametrics   LoadBalancer   ...   192.168.178.214   8428/TCP
```

---

## Local HTTP Validation

Check readiness:

```bash
curl -s http://192.168.178.214:8428/-/ready
```

Expected:

```text
OK
```

Check health:

```bash
curl -s http://192.168.178.214:8428/-/healthy
```

Expected:

```text
OK
```

---

## Test Metric Ingestion Over HTTP

Push a test metric directly to VictoriaMetrics:

```bash
cat <<'EOF' | curl -s -X POST \
  --data-binary @- \
  http://192.168.178.214:8428/api/v1/import/prometheus
ring_health_test_metric{device="test"} 1
EOF
```

Query the test metric:

```bash
curl -G -s \
  --data-urlencode 'query=ring_health_test_metric' \
  http://192.168.178.214:8428/api/v1/query | jq
```

Expected result:

```json
{
  "status": "success"
}
```

---

## Cloudflare Tunnel Validation

After configuring Cloudflare Zero Trust Tunnel, validate the public endpoint:

```bash
curl -s https://ring-health.greyneo.com/-/ready
```

Expected:

```text
OK
```

Push a test metric through Cloudflare:

```bash
cat <<'EOF' | curl -s -X POST \
  --data-binary @- \
  https://ring-health.greyneo.com/api/v1/import/prometheus
ring_health_cloudflare_test_metric{device="test"} 1
EOF
```

Query the metric through Cloudflare:

```bash
curl -G -s \
  --data-urlencode 'query=ring_health_cloudflare_test_metric' \
  https://ring-health.greyneo.com/api/v1/query | jq
```

Expected result:

```json
{
  "status": "success"
}
```

---

## Android App Configuration

Configure the Ring Health Tracker Android app with:

```text
https://ring-health.greyneo.com/api/v1/import/prometheus
```

The Android app connects to the Colmi R02 ring over BLE, reads buffered biometric data, and pushes the samples to VictoriaMetrics.

After manual sync in the Android app, validate incoming metrics:

```bash
curl -G -s \
  --data-urlencode 'query=biometric_hr_bpm' \
  https://ring-health.greyneo.com/api/v1/query | jq
```

---

## Expected Metrics

The project documents the following metrics:

```text
biometric_hr_bpm
biometric_hrv_rmssd
biometric_stress
biometric_spo2_pct
biometric_steps
biometric_calories
biometric_distance_meters
biometric_sleep_total_min
biometric_sleep_deep_min
biometric_sleep_rem_min
biometric_sleep_light_min
ring_battery_pct
ring_charging
```

All metrics are expected to include:

```text
device="colmi_r02"
```

Useful test queries:

```promql
biometric_hr_bpm{device="colmi_r02"}
```

```promql
ring_battery_pct{device="colmi_r02"}
```

```promql
biometric_steps{device="colmi_r02"}
```

```promql
min_over_time(biometric_hr_bpm{device="colmi_r02"}[8h])
```

The project README recommends doing aggregations such as overnight resting heart rate in Grafana/PromQL instead of calculating those values before ingestion.

---

## Grafana Datasource Validation

Open Grafana:

```text
Grafana -> Connections -> Data sources
```

Look for:

```text
Ring Health VictoriaMetrics
```

If the datasource does not appear, restart Grafana:

```bash
kubectl rollout restart deployment monitoring-grafana -n monitoring
```

Then open Grafana Explore and select:

```text
Ring Health VictoriaMetrics
```

Run:

```promql
ring_health_test_metric
```

Then run:

```promql
biometric_hr_bpm{device="colmi_r02"}
```

---

## Grafana Dashboard

The upstream Ring Health Tracker repository includes a Grafana dashboard.

Recommended process:

1. Import the dashboard manually first.
2. Confirm that the dashboard works with the `Ring Health VictoriaMetrics` datasource.
3. Export the working dashboard JSON.
4. Save the dashboard JSON into Git.

Recommended path:

```text
kubernetes/applications/ring-health-tracker/grafana/ring-health-dashboard.json
```

Create a dashboard ConfigMap:

```bash
kubectl create configmap ring-health-dashboard \
  -n monitoring \
  --from-file=ring-health-dashboard.json=kubernetes/applications/ring-health-tracker/grafana/ring-health-dashboard.json \
  --dry-run=client -o yaml > kubernetes/applications/ring-health-tracker/grafana-dashboard.yaml
```

Edit the generated file:

```bash
nano kubernetes/applications/ring-health-tracker/grafana-dashboard.yaml
```

Add the Grafana dashboard sidecar label:

```yaml
metadata:
  labels:
    grafana_dashboard: "1"
```

Apply:

```bash
kubectl apply -f kubernetes/applications/ring-health-tracker/grafana-dashboard.yaml
```

---

## Commit Manifests

After validating the manual deployment:

```bash
git add kubernetes/applications/ring-health-tracker
git commit -m "Add Ring Health Tracker VictoriaMetrics backend"
git push origin main
```

---

## Argo CD Project Update

Allow Argo CD to deploy to the `ring-health` namespace.

Edit:

```text
kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
```

Add this under `spec.destinations`:

```yaml
    - namespace: ring-health
      server: https://kubernetes.default.svc
```

Apply:

```bash
kubectl apply -f kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
```

Commit:

```bash
git add kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
git commit -m "Allow ring-health namespace in Argo CD project"
git push origin main
```

---

## Argo CD Application

Create:

```text
kubernetes/gitops/argocd/applications/ring-health-tracker.yaml
```

Content:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ring-health-tracker
  namespace: argocd
spec:
  project: homelab-platform

  source:
    repoURL: https://github.com/ali-fathi/devops-homelab.git
    targetRevision: main
    path: kubernetes/applications/ring-health-tracker
    directory:
      recurse: true

  destination:
    server: https://kubernetes.default.svc
    namespace: ring-health

  syncPolicy:
    automated:
      enabled: true
      prune: false
      selfHeal: true

    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

Apply:

```bash
kubectl apply -f kubernetes/gitops/argocd/applications/ring-health-tracker.yaml
```

Commit:

```bash
git add kubernetes/gitops/argocd/applications/ring-health-tracker.yaml
git commit -m "GitOps Ring Health Tracker with Argo CD"
git push origin main
```

Refresh and sync:

```bash
argocd app refresh ring-health-tracker --hard
argocd app sync ring-health-tracker
```

Check:

```bash
argocd app get ring-health-tracker
```

Expected:

```text
Sync Status: Synced
Health Status: Healthy
```

---

## Argo CD Validation

List app resources:

```bash
argocd app resources ring-health-tracker
```

Expected resources:

```text
Namespace/ring-health
PersistentVolumeClaim/victoriametrics-data
Deployment/victoriametrics
Service/victoriametrics
ConfigMap/grafana-datasource-ring-health-victoriametrics
ConfigMap/ring-health-dashboard     # optional
```

Check app status:

```bash
argocd app get ring-health-tracker
```

Check diff:

```bash
argocd app diff ring-health-tracker
```

---

## Day-2 Operations

### Check VictoriaMetrics

```bash
kubectl get pods -n ring-health
kubectl logs -n ring-health deployment/victoriametrics --tail=100
```

### Check PVC

```bash
kubectl get pvc -n ring-health
```

### Check service

```bash
kubectl get svc -n ring-health
```

### Check readiness

```bash
curl -s http://192.168.178.214:8428/-/ready
```

### Check Cloudflare endpoint

```bash
curl -s https://ring-health.greyneo.com/-/ready
```

### Query metrics

```bash
curl -G -s \
  --data-urlencode 'query=biometric_hr_bpm{device="colmi_r02"}' \
  https://ring-health.greyneo.com/api/v1/query | jq
```

### Sync app

```bash
argocd app sync ring-health-tracker
```

### Refresh app

```bash
argocd app refresh ring-health-tracker --hard
```

---

## Troubleshooting

### MetalLB IP does not appear

Check service:

```bash
kubectl describe svc victoriametrics -n ring-health
```

Check MetalLB pool:

```bash
kubectl get ipaddresspool -n metallb-system
```

Make sure this service annotation matches the actual MetalLB pool name:

```yaml
metallb.universe.tf/address-pool: homelab-pool
```

---

### VictoriaMetrics pod does not start

Check pod:

```bash
kubectl get pods -n ring-health
kubectl describe pod -n ring-health -l app.kubernetes.io/name=victoriametrics
```

Check logs:

```bash
kubectl logs -n ring-health deployment/victoriametrics --tail=100
```

Check PVC:

```bash
kubectl get pvc -n ring-health
```

---

### `/api/v1/import/prometheus` does not accept data

Test locally first:

```bash
cat <<'EOF' | curl -v -X POST \
  --data-binary @- \
  http://192.168.178.214:8428/api/v1/import/prometheus
ring_health_debug_metric{device="debug"} 1
EOF
```

Then query:

```bash
curl -G -s \
  --data-urlencode 'query=ring_health_debug_metric' \
  http://192.168.178.214:8428/api/v1/query | jq
```

If local works but Cloudflare does not work, troubleshoot the Cloudflare Tunnel configuration.

---

### Grafana datasource does not appear

Check ConfigMap:

```bash
kubectl get configmap grafana-datasource-ring-health-victoriametrics -n monitoring
```

Check Grafana sidecar labels:

```bash
kubectl get configmap -n monitoring --show-labels | grep grafana_datasource
```

Restart Grafana:

```bash
kubectl rollout restart deployment monitoring-grafana -n monitoring
```

---

### No biometric metrics after Android sync

Check test metrics first:

```bash
curl -G -s \
  --data-urlencode 'query=ring_health_test_metric' \
  https://ring-health.greyneo.com/api/v1/query | jq
```

Then check real metrics:

```bash
curl -G -s \
  --data-urlencode 'query=biometric_hr_bpm' \
  https://ring-health.greyneo.com/api/v1/query | jq
```

If no real metrics exist:

```text
Check Android app endpoint.
Check Cloudflare Tunnel access policy.
Check phone network/VPN.
Check ring pairing and manual sync.
Check app logs if available.
```

---

## Backup Notes

VictoriaMetrics data is stored in:

```text
PVC: victoriametrics-data
Namespace: ring-health
StorageClass: longhorn
```

Recommended backup:

```text
Enable Longhorn recurring backup for the victoriametrics-data volume.
```

Optional future improvement:

```text
Add Velero backup for namespace ring-health.
```

---

## GitOps Rules

After Argo CD manages this app:

```text
Do not manually edit Kubernetes resources unless debugging.
Make changes in Git.
Commit.
Push.
Let Argo CD sync.
```

Recommended workflow:

```bash
nano kubernetes/applications/ring-health-tracker/deployment.yaml
git add kubernetes/applications/ring-health-tracker/deployment.yaml
git commit -m "Update Ring Health Tracker backend"
git push origin main
argocd app sync ring-health-tracker
```

Keep pruning disabled initially:

```yaml
prune: false
```

Enable pruning only after the app has been stable and you are confident Argo CD owns all resources safely.

---

## Useful Commands

### Kubernetes

```bash
kubectl get all -n ring-health
kubectl get pvc -n ring-health
kubectl get svc -n ring-health
kubectl logs -n ring-health deployment/victoriametrics --tail=100
kubectl describe deployment victoriametrics -n ring-health
```

### VictoriaMetrics local endpoint

```bash
curl -s http://192.168.178.214:8428/-/ready
curl -s http://192.168.178.214:8428/-/healthy
```

### VictoriaMetrics Cloudflare endpoint

```bash
curl -s https://ring-health.greyneo.com/-/ready
curl -s https://ring-health.greyneo.com/-/healthy
```

### Push test metric

```bash
cat <<'EOF' | curl -s -X POST \
  --data-binary @- \
  https://ring-health.greyneo.com/api/v1/import/prometheus
ring_health_cloudflare_test_metric{device="test"} 1
EOF
```

### Query test metric

```bash
curl -G -s \
  --data-urlencode 'query=ring_health_cloudflare_test_metric' \
  https://ring-health.greyneo.com/api/v1/query | jq
```

### Query biometric metrics

```bash
curl -G -s \
  --data-urlencode 'query=biometric_hr_bpm{device="colmi_r02"}' \
  https://ring-health.greyneo.com/api/v1/query | jq
```

```bash
curl -G -s \
  --data-urlencode 'query=ring_battery_pct{device="colmi_r02"}' \
  https://ring-health.greyneo.com/api/v1/query | jq
```

### Argo CD

```bash
argocd app get ring-health-tracker
argocd app resources ring-health-tracker
argocd app diff ring-health-tracker
argocd app sync ring-health-tracker
argocd app refresh ring-health-tracker --hard
```

---

## Success Criteria

The setup is complete when:

```text
[ ] Namespace ring-health exists.
[ ] VictoriaMetrics pod is Running.
[ ] PVC victoriametrics-data is Bound.
[ ] Service victoriametrics has EXTERNAL-IP 192.168.178.214.
[ ] http://192.168.178.214:8428/-/ready returns OK.
[ ] https://ring-health.greyneo.com/-/ready returns OK.
[ ] Test metric can be pushed to /api/v1/import/prometheus.
[ ] Test metric can be queried from /api/v1/query.
[ ] Android app is configured with https://ring-health.greyneo.com/api/v1/import/prometheus.
[ ] Real biometric metrics appear in VictoriaMetrics.
[ ] Grafana datasource Ring Health VictoriaMetrics exists.
[ ] Grafana can query biometric metrics.
[ ] Argo CD app ring-health-tracker is Synced and Healthy.
```

---

## References

- Ring Health Tracker GitHub repository: https://github.com/jonas-werner/ring-health-tracker
- Ring Health Tracker blog post: https://jonamiki.com/posts/ring-health-tracker-no-subscriptions/
- VictoriaMetrics API examples: https://docs.victoriametrics.com/victoriametrics/url-examples/
