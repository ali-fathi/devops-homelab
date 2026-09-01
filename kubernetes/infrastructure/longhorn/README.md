# 💾 Longhorn – Distributed Storage for K3s Homelab

For the broad platform study guide, read:

```text
docs/homelab-study-guide.md
```

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

- Persistent Volumes (PV)
- Persistent Volume Claims (PVC)
- Replicated Storage
- Snapshots
- Backups
- Volume Expansion
- High Availability
- Web Management UI
- Kubernetes Native Storage

---

# 📂 Repository Structure

```text
kubernetes/
└── infrastructure/
    └── longhorn/
        ├── README.md
        ├── values.yaml
        └── longhorn-ui-lb.yaml
```

---

# ⚙️ Prerequisites

- K3s cluster healthy
- MetalLB installed
- Helm installed
- Open-iSCSI installed on all nodes
- DNS working between Pods and Services

Current K3s configuration (historical recovery baseline):

```yaml
disable-network-policy: true
flannel-backend: host-gw
disable:
  - servicelb
```

The disabled policy controller is not a Longhorn requirement; it is a known Phase 4 security gap retained after a historical cross-node networking incident. Re-enabling it can affect Longhorn traffic, so follow [K3s Embedded NetworkPolicy Controller Remediation](../../../docs/runbooks/k3s-networkpolicy-controller-remediation.md) only after the restore and maintenance gates pass.

---

# 🚨 IMPORTANT REQUIREMENT

Install open-iscsi on all nodes:

```bash
sudo apt update
sudo apt install -y open-iscsi
sudo systemctl enable iscsid
sudo systemctl start iscsid
```

Verify:

```bash
systemctl status iscsid
```

---

# 🚀 Installation

## Add Helm Repository

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
```

## Create Namespace

```bash
kubectl create namespace longhorn-system
```

## Install Longhorn

```bash
helm install longhorn longhorn/longhorn   --namespace longhorn-system
```

## Verify Installation

```bash
kubectl get pods -n longhorn-system
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

---

# 🌐 Access Longhorn UI

## Option 1 – Port Forward

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

Open:

```text
http://localhost:8080
```

## Option 2 – MetalLB LoadBalancer (Recommended)

Create file `longhorn-ui-lb.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: longhorn-frontend-lb
  namespace: longhorn-system
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.178.211
  selector:
    app: longhorn-ui
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
```

Apply:

```bash
kubectl apply -f longhorn-ui-lb.yaml
```

Verify:

```bash
kubectl get svc -n longhorn-system
```

Access:

```text
http://192.168.178.211
```

---

# 🏠 Fritzbox Notes

MetalLB pool:

```text
192.168.178.210 - 192.168.178.220
```

Longhorn UI IP:

```text
192.168.178.211
```

Make sure the Fritzbox DHCP range does not overlap with the MetalLB pool.

Do not use Guest Wi‑Fi when testing MetalLB services.

---

# 🧪 First Test Volume

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
kubectl get pvc
```

---

# 📸 Snapshots

Use Longhorn UI:

```text
Volume → Snapshot
```

Benefits:

- Rollback
- Recovery
- Backup points

---

# 💾 Backups

Supported targets:

- NFS
- S3
- MinIO

---

## Backup and restore rehearsal

Snapshots and backup targets are not sufficient evidence of recoverability. Before enabling stateful GitOps pruning or relying on a recovery target, run the isolated backup-and-restore rehearsal. It creates and restores only a new test PVC and checks its SHA-256 data integrity; it never overwrites an application volume.

```bash
./scripts/rehearse-longhorn-backup-restore.sh --confirm --cleanup
```

The BackupTarget must be external and available before running it. This homelab uses the dedicated NFSv4.1 target `nfs://192.168.178.120:/srv/longhorn_backups`, restricted to the five K3s node IPs; it uses no Kubernetes credential Secret. Complete the NAS, node mount-probe, and guarded target setup first:

```text
docs/runbooks/synology-nfs-longhorn-backup-target-setup.md
```

Then use the rehearsal runbook for recovery limitations, RPO/RTO interpretation, and rollback guidance:

```text
docs/runbooks/longhorn-backup-restore-rehearsal.md
```

# 🔄 Volume Expansion

Increase PVC size and reapply.

---

# 🚨 Troubleshooting

## Longhorn UI LoadBalancer Not Working

```bash
kubectl get svc -n longhorn-system longhorn-frontend-lb
kubectl get endpoints -n longhorn-system longhorn-frontend-lb
kubectl get pods -n longhorn-system -l app=longhorn-ui
```

Expected endpoints:

```text
10.42.x.x:8000
```

Check MetalLB:

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

Test:

```bash
curl -I http://192.168.178.211
```

## PVC Stuck in Pending

```bash
kubectl describe pvc
```

## Pod Cannot Mount Volume

```bash
kubectl describe pod POD_NAME
kubectl get events
```

## Longhorn Pods Crash

```bash
systemctl status iscsid
```

---

# 📊 Useful Commands

```bash
kubectl get pvc
kubectl get pv
kubectl get storageclass
kubectl get pods -n longhorn-system
kubectl get svc -n longhorn-system
kubectl get endpoints -n longhorn-system
kubectl get all -n longhorn-system
```

---

# 🎯 Real-World Use Cases

- PostgreSQL
- MariaDB
- Harbor
- Forgejo
- Jenkins
- Grafana
- Prometheus
- MinIO
- Nextcloud
- Home Assistant

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

---

# ✅ Learning Outcomes

- Persistent Volumes
- Persistent Volume Claims
- Storage Classes
- Stateful Applications
- Snapshots
- Backups
- Replication
- High Availability Storage
- Longhorn UI Exposure Through MetalLB
- Longhorn Troubleshooting

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

MetalLB provides networking.

Longhorn provides storage.

Together they form the foundation of everything that will be deployed later in this DevOps Homelab.
