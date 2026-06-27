# 💾 Longhorn – Distributed Storage for K3s Homelab

Longhorn is a cloud-native distributed block storage platform for Kubernetes.

It provides persistent storage for applications running inside your K3s cluster.

Think of Longhorn as:

```text
MetalLB = Networking
Longhorn = Storage
```

Without Longhorn, most applications lose their data when Pods are deleted or rescheduled.

With Longhorn, data survives Pod restarts, node failures, upgrades, and rescheduling.

---

# 🎯 Purpose

Longhorn provides:

✅ Persistent Volumes (PV)

✅ Persistent Volume Claims (PVC)

✅ Replicated Storage

✅ Snapshots

✅ Backups

✅ Volume Expansion

✅ High Availability

✅ Web Management UI

✅ Kubernetes Native Storage

---

# 🧠 Why Longhorn?

Imagine you deploy:

- PostgreSQL
- MariaDB
- Harbor
- Grafana
- Jenkins
- Forgejo

Without persistent storage:

```text
Pod deleted
    ↓
Data deleted
```

With Longhorn:

```text
Pod deleted
    ↓
Pod recreated
    ↓
Data still exists
```

---

# 🏗️ How Longhorn Works

Example:

```text
Kubernetes Pod
        │
        ▼
Persistent Volume Claim
        │
        ▼
Longhorn Volume
        │
        ▼
Replica #1 → Worker1
Replica #2 → Worker2
Replica #3 → Master
```

Data is replicated across nodes.

If one node fails:

```text
Node Failure
    ↓
Application continues running
```

---

# 🏗️ Architecture

```text
+--------------------------------+
|           Application          |
+--------------------------------+
               │
               ▼
+--------------------------------+
|  Persistent Volume Claim (PVC) |
+--------------------------------+
               │
               ▼
+--------------------------------+
|        Longhorn Volume         |
+--------------------------------+
       │         │         │
       ▼         ▼         ▼
   Replica1  Replica2  Replica3
```

---

# 📚 Core Concepts

Before installation, understand these Kubernetes storage concepts.

---

## Persistent Volume (PV)

Actual storage resource.

Example:

```text
100Gi Volume
```

Created by Longhorn.

---

## Persistent Volume Claim (PVC)

Storage request.

Example:

```yaml
resources:
  requests:
    storage: 10Gi
```

Application requests storage through PVC.

---

## StorageClass

Defines storage behavior.

Example:

```text
longhorn
```

Applications use the StorageClass to obtain storage.

---

# 📂 Repository Structure

```text
kubernetes/
└── infrastructure/
    └── longhorn/
        ├── README.md
        ├── namespace.yaml
        ├── values.yaml
        └── ingress.yaml
```

---

# ⚙️ Prerequisites

Before installing Longhorn:

✅ K3s cluster healthy

✅ MetalLB installed

✅ kubectl working

✅ All nodes have enough free disk space

✅ Open-iSCSI installed on all nodes

---

# 🚨 IMPORTANT REQUIREMENT

Longhorn requires:

```text
open-iscsi
```

on every node.

---

# Step 1 – Install Open-iSCSI

Run on ALL nodes.

Master:

```bash
ssh ansible@192.168.178.80
```

Workers:

```bash
ssh ansible@192.168.178.81
```

```bash
ssh ansible@192.168.178.82
```

Install:

```bash
sudo apt update
sudo apt install -y open-iscsi
```

Enable:

```bash
sudo systemctl enable iscsid
sudo systemctl start iscsid
```

Verify:

```bash
systemctl status iscsid
```

Expected:

```text
active (running)
```

---

# 🚀 Installation

---

## Step 2 – Add Helm Repository

```bash
helm repo add longhorn https://charts.longhorn.io
```

Update:

```bash
helm repo update
```

---

## Step 3 – Create Namespace

```bash
kubectl create namespace longhorn-system
```

---

## Step 4 – Install Longhorn

```bash
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system
```

---

## Step 5 – Verify Installation

```bash
kubectl get pods -n longhorn-system
```

Expected:

```text
longhorn-manager
longhorn-driver-deployer
longhorn-ui
longhorn-csi-plugin
```

All should be:

```text
Running
```

---

# ✅ Verify StorageClass

```bash
kubectl get storageclass
```

Expected:

```text
longhorn
```

Example:

```text
NAME                 PROVISIONER
longhorn (default)   driver.longhorn.io
```

---

# 🌐 Access Longhorn UI

---

## Option 1 – Port Forward

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

Open:

```text
http://localhost:8080
```

---

## Option 2 – LoadBalancer

Create:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: longhorn-ui
  namespace: longhorn-system
spec:
  type: LoadBalancer
  selector:
    app: longhorn-ui
  ports:
  - port: 80
```

Then:

```bash
kubectl get svc -n longhorn-system
```

MetalLB assigns:

```text
192.168.178.212
```

Access:

```text
http://192.168.178.212
```

---

# 🧪 First Test Volume

Create:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc

spec:
  accessModes:
    - ReadWriteOnce

  storageClassName: longhorn

  resources:
    requests:
      storage: 2Gi
```

Apply:

```bash
kubectl apply -f test-pvc.yaml
```

Verify:

```bash
kubectl get pvc
```

Expected:

```text
STATUS: Bound
```

---

# 🧪 Test Application

Create:

```yaml
apiVersion: apps/v1
kind: Deployment

metadata:
  name: nginx-storage

spec:
  replicas: 1

  selector:
    matchLabels:
      app: nginx-storage

  template:
    metadata:
      labels:
        app: nginx-storage

    spec:
      containers:
      - name: nginx
        image: nginx

        volumeMounts:
        - mountPath: /usr/share/nginx/html
          name: storage

      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: test-pvc
```

Deploy:

```bash
kubectl apply -f nginx-storage.yaml
```

Verify:

```bash
kubectl get pods
kubectl get pvc
```

---

# 📸 Snapshots

Longhorn supports snapshots.

Use UI:

```text
Volume
  ↓
Snapshot
```

Benefits:

- Rollback
- Backup
- Recovery

---

# 💾 Backups

Longhorn supports:

- NFS
- S3
- MinIO

Example:

```text
Longhorn
    ↓
MinIO
    ↓
Backup Storage
```

---

# 🔄 Volume Expansion

Expand PVC:

```yaml
resources:
  requests:
    storage: 10Gi
```

Apply:

```bash
kubectl apply -f pvc.yaml
```

Longhorn expands volume automatically.

---

# 🚨 Troubleshooting

---

## Check Longhorn Pods

```bash
kubectl get pods -n longhorn-system
```

---

## Check Longhorn Services

```bash
kubectl get svc -n longhorn-system
```

---

## Check Storage Classes

```bash
kubectl get storageclass
```

---

## Check PVC

```bash
kubectl get pvc
```

---

## Describe PVC

```bash
kubectl describe pvc test-pvc
```

---

## Check Volume Status

Open Longhorn UI.

Verify:

```text
Healthy
Attached
```

---

# ❌ PVC Stuck in Pending

Check:

```bash
kubectl describe pvc
```

Common causes:

- Longhorn not installed
- StorageClass missing
- Node issue

---

# ❌ Volume Detached

Check Longhorn UI.

Possible causes:

- Node offline
- Disk full

---

# ❌ Pod Cannot Mount Volume

Verify:

```bash
kubectl describe pod POD_NAME
```

Check events:

```bash
kubectl get events
```

---

# ❌ Longhorn Pods Crash

Verify:

```bash
systemctl status iscsid
```

Most common cause:

```text
open-iscsi not installed
```

---

# 📊 Useful Commands

View PVCs:

```bash
kubectl get pvc
```

View PVs:

```bash
kubectl get pv
```

View Storage Classes:

```bash
kubectl get storageclass
```

View Longhorn Pods:

```bash
kubectl get pods -n longhorn-system
```

View Longhorn Services:

```bash
kubectl get svc -n longhorn-system
```

View Longhorn Logs:

```bash
kubectl logs -n longhorn-system deployment/longhorn-driver-deployer
```

---

# 🎯 Real-World Use Cases

Applications that should use Longhorn:

✅ PostgreSQL

✅ MariaDB

✅ Harbor

✅ Forgejo

✅ Jenkins

✅ Grafana

✅ Prometheus

✅ MinIO

✅ Nextcloud

✅ Home Assistant

---

# 🔮 Future Integration

Longhorn will provide storage for:

```text
Harbor
Forgejo
Woodpecker
ArgoCD
Prometheus
Grafana
Loki
MinIO
```

Everything deployed later in this homelab will depend on Longhorn.

---

# ✅ Learning Outcomes

After completing this phase you should understand:

✅ Persistent Volumes

✅ Persistent Volume Claims

✅ Storage Classes

✅ Stateful Applications

✅ Snapshots

✅ Backups

✅ Replication

✅ High Availability Storage

---

# ✅ Summary

Longhorn transforms your Kubernetes cluster from:

```text
Stateless Applications Only
```

into:

```text
Production-Ready Platform
```

MetalLB gave your cluster networking.

Longhorn gives your cluster storage.

Together they form the foundation of everything that will be deployed later in this DevOps Homelab.