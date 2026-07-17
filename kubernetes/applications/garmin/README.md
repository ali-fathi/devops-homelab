# Garmin Grafana Integration

This README documents the Garmin watch integration for the homelab Grafana platform.

The integration uses:

```text
Garmin Watch
Garmin Connect
Garmin Fetch Data Container
InfluxDB
Grafana
Azure Key Vault
External Secrets Operator
Longhorn
```

The goal is to collect Garmin health and activity data, store it locally in InfluxDB, and visualize it directly inside the existing Grafana instance.

---

## Overview

Garmin watches do not send data directly to Grafana.

The data flow is:

```text
Garmin Watch
    ↓
Garmin Connect Mobile App
    ↓
Garmin Connect Cloud
    ↓
garmin-fetch-data container
    ↓
InfluxDB
    ↓
Grafana Dashboard
```

The Garmin fetcher pulls data from Garmin Connect and writes it to InfluxDB. Grafana then reads from InfluxDB and displays the data in dashboards.

---

## Repository Structure

Recommended folder structure:

```text
kubernetes/
└── observability/
    └── garmin/
        ├── README.md
        ├── namespace.yaml
        ├── external-secret-garmin.yaml
        ├── influxdb.yaml
        ├── influxdb-init-job.yaml
        ├── garmin-fetch-data.yaml
        └── dashboards/
            └── garmin-stats-dashboard.json
```

Do not commit files that contain real Garmin credentials or passwords.

---

## Components

### Garmin Watch

The Garmin watch records health and activity metrics such as:

```text
Steps
Heart rate
Sleep
Stress
Body Battery
Calories
Activities
GPS activity data
Training metrics
```

The watch must sync with Garmin Connect before the homelab can fetch new data.

---

### Garmin Connect

Garmin Connect is the source of the health and activity data.

The Garmin watch syncs data to Garmin Connect through the Garmin mobile app. The homelab fetcher then retrieves that synced data.

---

### garmin-fetch-data

The `garmin-fetch-data` container logs into Garmin Connect, fetches data, and writes it into InfluxDB.

Important environment variables:

```text
GARMINCONNECT_EMAIL
GARMINCONNECT_BASE64_PASSWORD
GARMINCONNECT_IS_CN
INFLUXDB_HOST
INFLUXDB_PORT
INFLUXDB_DATABASE
INFLUXDB_USERNAME
INFLUXDB_PASSWORD
TZ
```

---

### InfluxDB

InfluxDB stores Garmin data as time-series data.

This setup uses:

```text
InfluxDB version: 1.11
Database: GarminStats
Port: 8086
Storage: Longhorn PVC
```

---

### Grafana

Grafana visualizes the Garmin data by querying the InfluxDB datasource.

Recommended Garmin dashboard:

```text
Garmin Stats
Grafana dashboard ID: 23245
```

---

### Azure Key Vault

Azure Key Vault stores all sensitive Garmin and InfluxDB values.

Secrets stored in Azure Key Vault:

```text
garmin-connect-email
garmin-connect-password-base64
garmin-influxdb-username
garmin-influxdb-password
```

---

### External Secrets Operator

External Secrets Operator synchronizes secrets from Azure Key Vault into Kubernetes Secrets.

Flow:

```text
Azure Key Vault
    ↓
ClusterSecretStore
    ↓
ExternalSecret
    ↓
Kubernetes Secret: garmin-secrets
```

---

## Security Design

Sensitive information is not stored in Git.

These values must stay in Azure Key Vault:

```text
Garmin email
Garmin password base64 value
InfluxDB username
InfluxDB password
```

The repository should only contain references to Kubernetes secrets:

```yaml
secretKeyRef:
  name: garmin-secrets
  key: GARMINCONNECT_EMAIL
```

Never commit real values such as:

```text
GARMINCONNECT_EMAIL
GARMINCONNECT_BASE64_PASSWORD
INFLUXDB_PASSWORD
```

---

## Azure Key Vault Cost Optimization

Recommended low-cost settings:

```text
Use existing Key Vault
Use Standard tier
Use ExternalSecret refreshInterval: 48h
Avoid frequent force-sync
Avoid reading Key Vault directly from application pods
Use one ExternalSecret for Garmin-related secrets
```

The Garmin ExternalSecret uses:

```yaml
refreshInterval: 48h
```

Garmin and InfluxDB credentials rarely change, so there is no need to refresh them every few minutes.

---

## Prerequisites

Before deploying the Garmin integration, verify the homelab already has:

```text
K3s running
Longhorn running
Grafana running
External Secrets Operator running
Azure Key Vault configured
ClusterSecretStore for Azure Key Vault configured
```

---

## Verify External Secrets Operator

```bash
kubectl get pods -n external-secrets-system
```

Expected:

```text
Running
```

---

## Verify ClusterSecretStore

```bash
kubectl get clustersecretstore
```

Expected:

```text
azure-keyvault
```

Inspect:

```bash
kubectl get clustersecretstore azure-keyvault -o yaml
```

Expected provider:

```yaml
provider:
  azurekv:
    vaultUrl: https://<your-keyvault-name>.vault.azure.net
```

---

## Verify Longhorn

```bash
kubectl get pods -n longhorn-system
```

Expected:

```text
Running
```

---

## Verify Grafana

```bash
kubectl get pods -n monitoring | grep grafana
```

Expected:

```text
3/3 Running
```

Grafana URL:

```text
http://192.168.178.212
```

---

# Deployment Steps

## Step 1 – Create Namespace

File:

```text
namespace.yaml
```

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: garmin
```

Apply:

```bash
kubectl apply -f namespace.yaml
```

Verify:

```bash
kubectl get namespace garmin
```

---

## Step 2 – Store Secrets in Azure Key Vault

Encode Garmin password:

```bash
echo -n 'YOUR_GARMIN_PASSWORD' | base64
```

Store Garmin email:

```bash
az keyvault secret set \
  --vault-name kv-homelab-k3s \
  --name garmin-connect-email \
  --value "your-garmin-email@example.com"
```

Store Garmin base64 password:

```bash
az keyvault secret set \
  --vault-name kv-homelab-k3s \
  --name garmin-connect-password-base64 \
  --value "BASE64_ENCODED_GARMIN_PASSWORD"
```

Store InfluxDB username:

```bash
az keyvault secret set \
  --vault-name kv-homelab-k3s \
  --name garmin-influxdb-username \
  --value "influxdb_user"
```

Store InfluxDB password:

```bash
az keyvault secret set \
  --vault-name kv-homelab-k3s \
  --name garmin-influxdb-password \
  --value "STRONG_RANDOM_PASSWORD"
```

Verify:

```bash
az keyvault secret list \
  --vault-name kv-homelab-k3s \
  --query "[].name" \
  -o table
```

Expected secrets:

```text
garmin-connect-email
garmin-connect-password-base64
garmin-influxdb-username
garmin-influxdb-password
```

---

## Step 3 – Create ExternalSecret

File:

```text
external-secret-garmin.yaml
```

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: garmin-secrets
  namespace: garmin
spec:
  refreshInterval: 48h

  secretStoreRef:
    name: azure-keyvault
    kind: ClusterSecretStore

  target:
    name: garmin-secrets
    creationPolicy: Owner

  data:
    - secretKey: GARMINCONNECT_EMAIL
      remoteRef:
        key: garmin-connect-email

    - secretKey: GARMINCONNECT_BASE64_PASSWORD
      remoteRef:
        key: garmin-connect-password-base64

    - secretKey: INFLUXDB_USERNAME
      remoteRef:
        key: garmin-influxdb-username

    - secretKey: INFLUXDB_PASSWORD
      remoteRef:
        key: garmin-influxdb-password
```

Apply:

```bash
kubectl apply -f external-secret-garmin.yaml
```

Verify:

```bash
kubectl get externalsecret -n garmin
```

Expected:

```text
SecretSynced
```

Verify Kubernetes Secret exists:

```bash
kubectl get secret garmin-secrets -n garmin
```

Check only the key names:

```bash
kubectl describe secret garmin-secrets -n garmin
```

Expected keys:

```text
GARMINCONNECT_EMAIL
GARMINCONNECT_BASE64_PASSWORD
INFLUXDB_USERNAME
INFLUXDB_PASSWORD
```

---

## Step 4 – Deploy InfluxDB

File:

```text
influxdb.yaml
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: garmin-influxdb-data
  namespace: garmin
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: garmin-influxdb
  namespace: garmin
spec:
  replicas: 1

  strategy:
    type: Recreate

  selector:
    matchLabels:
      app: garmin-influxdb

  template:
    metadata:
      labels:
        app: garmin-influxdb

    spec:
      securityContext:
        fsGroup: 1000
        fsGroupChangePolicy: "OnRootMismatch"

      initContainers:
        - name: init-influxdb-permissions
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              echo "Preparing InfluxDB data directory..."
              mkdir -p /var/lib/influxdb/meta
              mkdir -p /var/lib/influxdb/data
              mkdir -p /var/lib/influxdb/wal
              chown -R 1000:1000 /var/lib/influxdb
              chmod -R 775 /var/lib/influxdb
              echo "InfluxDB data directory permissions fixed."
          securityContext:
            runAsUser: 0
          volumeMounts:
            - name: data
              mountPath: /var/lib/influxdb

      containers:
        - name: influxdb
          image: influxdb:1.11
          imagePullPolicy: IfNotPresent

          ports:
            - name: http
              containerPort: 8086

          env:
            - name: INFLUXDB_DB
              value: GarminStats

            - name: INFLUXDB_USER
              valueFrom:
                secretKeyRef:
                  name: garmin-secrets
                  key: INFLUXDB_USERNAME

            - name: INFLUXDB_USER_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: garmin-secrets
                  key: INFLUXDB_PASSWORD

            - name: INFLUXDB_DATA_INDEX_VERSION
              value: tsi1

          readinessProbe:
            httpGet:
              path: /ping
              port: 8086
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 12

          livenessProbe:
            httpGet:
              path: /ping
              port: 8086
            initialDelaySeconds: 60
            periodSeconds: 30
            timeoutSeconds: 3
            failureThreshold: 5

          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi

          volumeMounts:
            - name: data
              mountPath: /var/lib/influxdb

      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: garmin-influxdb-data
---
apiVersion: v1
kind: Service
metadata:
  name: garmin-influxdb
  namespace: garmin
spec:
  type: ClusterIP

  selector:
    app: garmin-influxdb

  ports:
    - name: http
      port: 8086
      targetPort: 8086
```

Apply:

```bash
kubectl apply -f influxdb.yaml
```

Verify:

```bash
kubectl get pods -n garmin
kubectl get pvc -n garmin
kubectl get svc -n garmin
```

Expected:

```text
garmin-influxdb   1/1   Running
```

---

## Step 5 – Initialize InfluxDB Database

InfluxDB should contain the database:

```text
GarminStats
```

Create it if missing:

```bash
kubectl exec -it \
  -n garmin \
  deployment/garmin-influxdb \
  -- influx -execute 'CREATE DATABASE GarminStats'
```

Verify:

```bash
kubectl exec -it \
  -n garmin \
  deployment/garmin-influxdb \
  -- influx -execute 'SHOW DATABASES'
```

Expected:

```text
_internal
GarminStats
```

---

## Step 6 – Optional Init Job for Database Creation

File:

```text
influxdb-init-job.yaml
```

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: garmin-influxdb-init
  namespace: garmin
spec:
  template:
    spec:
      restartPolicy: OnFailure

      containers:
        - name: influxdb-init
          image: influxdb:1.11
          command:
            - sh
            - -c
            - |
              echo "Waiting for InfluxDB..."
              until influx -host garmin-influxdb -port 8086 -execute 'SHOW DATABASES'; do
                echo "InfluxDB is not ready yet..."
                sleep 5
              done

              echo "Creating GarminStats database if missing..."
              influx -host garmin-influxdb -port 8086 -execute 'CREATE DATABASE GarminStats'

              echo "Current databases:"
              influx -host garmin-influxdb -port 8086 -execute 'SHOW DATABASES'

              echo "InfluxDB initialization completed."
```

Apply when needed:

```bash
kubectl apply -f influxdb-init-job.yaml
```

Check logs:

```bash
kubectl logs -n garmin job/garmin-influxdb-init
```

---

## Step 7 – Deploy Garmin Fetcher

File:

```text
garmin-fetch-data.yaml
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: garminconnect-tokens
  namespace: garmin
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: garmin-fetch-data
  namespace: garmin
spec:
  replicas: 1

  strategy:
    type: Recreate

  selector:
    matchLabels:
      app: garmin-fetch-data

  template:
    metadata:
      labels:
        app: garmin-fetch-data

    spec:
      securityContext:
        fsGroup: 1000

      initContainers:
        - name: wait-for-influxdb
          image: curlimages/curl:latest
          command:
            - sh
            - -c
            - |
              echo "Waiting for InfluxDB..."
              until curl -s -f http://garmin-influxdb:8086/ping >/dev/null; do
                echo "InfluxDB is not ready yet..."
                sleep 5
              done
              echo "InfluxDB is ready."

      containers:
        - name: garmin-fetch-data
          image: thisisarpanghosh/garmin-fetch-data:latest
          imagePullPolicy: IfNotPresent

          env:
            - name: INFLUXDB_HOST
              value: garmin-influxdb

            - name: INFLUXDB_PORT
              value: "8086"

            - name: INFLUXDB_DATABASE
              value: GarminStats

            - name: INFLUXDB_USERNAME
              valueFrom:
                secretKeyRef:
                  name: garmin-secrets
                  key: INFLUXDB_USERNAME

            - name: INFLUXDB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: garmin-secrets
                  key: INFLUXDB_PASSWORD

            - name: GARMINCONNECT_EMAIL
              valueFrom:
                secretKeyRef:
                  name: garmin-secrets
                  key: GARMINCONNECT_EMAIL

            - name: GARMINCONNECT_BASE64_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: garmin-secrets
                  key: GARMINCONNECT_BASE64_PASSWORD

            - name: GARMINCONNECT_IS_CN
              value: "False"

            - name: TZ
              value: "Europe/Berlin"

          volumeMounts:
            - name: garminconnect-tokens
              mountPath: /home/appuser/.garminconnect

      volumes:
        - name: garminconnect-tokens
          persistentVolumeClaim:
            claimName: garminconnect-tokens
```

Apply:

```bash
kubectl apply -f garmin-fetch-data.yaml
```

Verify:

```bash
kubectl get pods -n garmin
```

Watch logs:

```bash
kubectl logs -n garmin deployment/garmin-fetch-data -f
```

---

## Step 8 – Verify Data Is Written

Check InfluxDB measurements:

```bash
kubectl exec -it \
  -n garmin \
  deployment/garmin-influxdb \
  -- influx -database GarminStats -execute 'SHOW MEASUREMENTS'
```

At first, there may be few or no measurements until Garmin authentication succeeds and data is fetched.

---

## Step 9 – Add InfluxDB Datasource to Grafana

Open Grafana:

```text
http://192.168.178.212
```

Go to:

```text
Connections
  → Data sources
  → Add data source
  → InfluxDB
```

Use:

```text
Query language: InfluxQL
URL: http://garmin-influxdb.garmin.svc.cluster.local:8086
Database: GarminStats
User: influxdb_user
Password: value from Azure Key Vault
HTTP Method: GET
```

Click:

```text
Save & test
```

Expected:

```text
Data source is working
```

---

## Step 10 – Import Garmin Dashboard

In Grafana:

```text
Dashboards
  → New
  → Import
```

Use dashboard ID:

```text
23245
```

Select the InfluxDB datasource:

```text
GarminStats
```

Import the dashboard.

---

# Troubleshooting

## InfluxDB Permission Denied

Error:

```text
mkdir /var/lib/influxdb/meta: permission denied
```

Fix:

```text
Use the init-influxdb-permissions init container.
```

The init container creates the required folders and fixes permissions before InfluxDB starts.

---

## Database Not Found

Error:

```text
database not found: "GarminStats"
```

Fix:

```bash
kubectl exec -it \
  -n garmin \
  deployment/garmin-influxdb \
  -- influx -execute 'CREATE DATABASE GarminStats'
```

Verify:

```bash
kubectl exec -it \
  -n garmin \
  deployment/garmin-influxdb \
  -- influx -execute 'SHOW DATABASES'
```

---

## Garmin Fetcher Connection Refused

Error:

```text
Connection refused
```

Cause:

```text
InfluxDB is not ready or crashed.
```

Check:

```bash
kubectl get pods -n garmin
kubectl logs -n garmin deployment/garmin-influxdb
```

---

## Garmin Authentication Fails

Check:

```bash
kubectl logs -n garmin deployment/garmin-fetch-data -f
```

Common causes:

```text
Wrong Garmin email
Wrong Garmin password
Wrong base64 encoding
Garmin MFA required
Garmin temporary rate limit
Garmin token PVC permission issue
```

---

## ExternalSecret Not Syncing

Check:

```bash
kubectl get externalsecret -n garmin
kubectl describe externalsecret garmin-secrets -n garmin
```

Check ClusterSecretStore:

```bash
kubectl get clustersecretstore azure-keyvault
kubectl describe clustersecretstore azure-keyvault
```

---

## InfluxDB Service Has No Endpoints

Check:

```bash
kubectl get endpoints garmin-influxdb -n garmin
```

If empty, InfluxDB is not ready.

Check:

```bash
kubectl get pods -n garmin
kubectl logs -n garmin deployment/garmin-influxdb
```

---

# Useful Commands

## Pods

```bash
kubectl get pods -n garmin
```

## PVCs

```bash
kubectl get pvc -n garmin
```

## Services

```bash
kubectl get svc -n garmin
```

## ExternalSecret

```bash
kubectl get externalsecret -n garmin
```

## Garmin Fetcher Logs

```bash
kubectl logs -n garmin deployment/garmin-fetch-data -f
```

## InfluxDB Logs

```bash
kubectl logs -n garmin deployment/garmin-influxdb
```

## Show Databases

```bash
kubectl exec -it \
  -n garmin \
  deployment/garmin-influxdb \
  -- influx -execute 'SHOW DATABASES'
```

## Show Measurements

```bash
kubectl exec -it \
  -n garmin \
  deployment/garmin-influxdb \
  -- influx -database GarminStats -execute 'SHOW MEASUREMENTS'
```

---

# Secret Rotation

If the Garmin password changes:

```bash
echo -n 'NEW_GARMIN_PASSWORD' | base64
```

Update Key Vault:

```bash
az keyvault secret set \
  --vault-name kv-homelab-k3s \
  --name garmin-connect-password-base64 \
  --value "NEW_BASE64_PASSWORD"
```

Force ExternalSecret refresh:

```bash
kubectl annotate externalsecret garmin-secrets \
  -n garmin force-sync=$(date +%s) --overwrite
```

Restart Garmin fetcher:

```bash
kubectl rollout restart deployment garmin-fetch-data -n garmin
```

Watch logs:

```bash
kubectl logs -n garmin deployment/garmin-fetch-data -f
```

---

# Security Checklist

```text
[ ] Garmin credentials stored only in Azure Key Vault
[ ] InfluxDB credentials stored only in Azure Key Vault
[ ] No real secrets committed to Git
[ ] ExternalSecret refreshInterval set to 48h
[ ] ESO identity has least-privilege Key Vault access
[ ] InfluxDB service is ClusterIP only
[ ] Garmin namespace is not exposed externally
[ ] Garmin token PVC is persistent
[ ] Garmin token PVC is not committed or exported
[ ] Grafana datasource password is not stored in Git
```

---

# Cost Checklist

```text
[ ] Use existing Azure Key Vault
[ ] Use Standard Key Vault
[ ] Avoid Premium/HSM for this use case
[ ] Use refreshInterval: 48h
[ ] Avoid frequent force-sync
[ ] Avoid reading Key Vault directly from application pods
[ ] Use one ExternalSecret for Garmin secrets
```

---

# Git Ignore

Do not commit local secret files.

Recommended `.gitignore` entries:

```gitignore
kubernetes/applications/garmin/secret-garmin.yaml
*.env
.env
```

Safe to commit:

```text
namespace.yaml
external-secret-garmin.yaml
influxdb.yaml
influxdb-init-job.yaml
garmin-fetch-data.yaml
README.md
```

---

# Final Expected State

```bash
kubectl get pods -n garmin
```

Expected:

```text
garmin-influxdb       1/1   Running
garmin-fetch-data     1/1   Running
```

```bash
kubectl get pvc -n garmin
```

Expected:

```text
garmin-influxdb-data   Bound
garminconnect-tokens   Bound
```

Final flow:

```text
Azure Key Vault
   ↓
External Secrets Operator
   ↓
garmin-secrets
   ↓
garmin-fetch-data
   ↓
InfluxDB GarminStats
   ↓
Grafana Garmin Dashboard
```

When everything is working, open Grafana:

```text
http://192.168.178.212
```

Then open:

```text
Garmin Stats
```

The dashboard should show Garmin health and activity metrics from the Garmin watch.
