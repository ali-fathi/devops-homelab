# Nginx + Longhorn + MetalLB Demo

This demo validates that the Kubernetes homelab foundation is working correctly.

It tests:

- Kubernetes Namespace
- Longhorn PersistentVolumeClaim
- Nginx Deployment
- MetalLB LoadBalancer Service
- Persistent data across Pod recreation

Longhorn provides Kubernetes persistent storage through PersistentVolumes and PersistentVolumeClaims. MetalLB provides `LoadBalancer` functionality for bare-metal Kubernetes clusters. [1](https://longhorn.io/docs/)[2](https://longhorn.io/docs/1.12.0/nodes-and-volumes/volumes/create-volumes/) [3](https://deepwiki.com/k3s-io/docs/4.2-networking-services-%28coredns-servicelb-traefik-kube-router%29)[4](https://www.bookstack.cn/read/k3s-1.33-en/37dcd96a7785228e.md)

---

## Architecture

```text
User Browser
    ↓
MetalLB LoadBalancer IP
    ↓
Kubernetes Service
    ↓
Nginx Pod
    ↓
Longhorn PVC
    ↓
Longhorn Volume
```

---

## Namespace

This demo runs in its own namespace:

```text
nginx-storage-demo
```

This keeps test resources separate from the default namespace and makes cleanup easy.

---

## Files

```text
kubernetes/applications/nginx-longhorn-metallb/
├── README.md
├── namespace.yaml
├── pvc.yaml
├── deployment.yaml
└── service.yaml
```

---

## Components

### 1. Namespace

File:

```text
namespace.yaml
```

Creates:

```text
nginx-storage-demo
```

---

### 2. PVC

File:

```text
pvc.yaml
```

Creates a Longhorn-backed PersistentVolumeClaim:

```text
nginx-html-pvc
```

Storage:

```text
2Gi
```

StorageClass:

```text
longhorn
```

Access mode:

```text
ReadWriteOnce
```

---

### 3. Deployment

File:

```text
deployment.yaml
```

Creates an Nginx Deployment:

```text
nginx-longhorn
```

The Deployment uses:

- `nginx:stable`
- Longhorn PVC mounted at `/usr/share/nginx/html`
- Init container that creates `index.html` only if the file does not already exist

This is important because the init container does not overwrite the file every time the Pod restarts. That allows testing persistence.

---

### 4. Service

File:

```text
service.yaml
```

Creates a LoadBalancer Service:

```text
nginx-longhorn-lb
```

MetalLB assigns an external IP from the configured pool, for example:

```text
192.168.178.210 - 192.168.178.220
```

MetalLB Layer 2 mode assigns addresses from an `IPAddressPool` and advertises those addresses through `L2Advertisement`. [3](https://deepwiki.com/k3s-io/docs/4.2-networking-services-%28coredns-servicelb-traefik-kube-router%29)

---

# Prerequisites

Before deploying this demo, verify the following:

## K3s Nodes

```bash
kubectl get nodes
```

Expected:

```text
k3s-master    Ready
k3s-worker1   Ready
k3s-worker2   Ready
```

---

## DNS

Run a test pod:

```bash
kubectl run netshoot \
  --image=nicolaka/netshoot \
  -it --rm --restart=Never -- bash
```

Inside the pod:

```bash
nslookup kubernetes.default.svc.cluster.local
```

Expected:

```text
Name: kubernetes.default.svc.cluster.local
Address: 10.43.0.1
```

Exit:

```bash
exit
```

Delete if needed:

```bash
kubectl delete pod netshoot
```

---

## Longhorn

```bash
kubectl get pods -n longhorn-system
```

Expected important components:

```text
longhorn-manager       Running
longhorn-csi-plugin    Running
longhorn-ui            Running
```

Check StorageClass:

```bash
kubectl get storageclass
```

Expected:

```text
longhorn
```

---

## MetalLB

```bash
kubectl get pods -n metallb-system
```

Expected:

```text
controller   Running
speaker      Running
```

Check MetalLB config:

```bash
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

Expected:

```text
homelab-pool
homelab-advertisement
```

---

# Deploy

From this folder:

```bash
kubectl apply -f .
```

Expected output:

```text
namespace/nginx-storage-demo created
persistentvolumeclaim/nginx-html-pvc created
deployment.apps/nginx-longhorn created
service/nginx-longhorn-lb created
```

---

# Verify Deployment

## Check Namespace

```bash
kubectl get namespace nginx-storage-demo
```

---

## Check Pod

```bash
kubectl get pods -n nginx-storage-demo
```

Expected:

```text
nginx-longhorn-xxxxx   1/1   Running
```

If the Pod is not running:

```bash
kubectl describe pod -n nginx-storage-demo -l app=nginx-longhorn
```

---

## Check PVC

```bash
kubectl get pvc -n nginx-storage-demo
```

Expected:

```text
nginx-html-pvc   Bound
```

If PVC is stuck in Pending:

```bash
kubectl describe pvc nginx-html-pvc -n nginx-storage-demo
```

---

## Check PV

```bash
kubectl get pv
```

You should see a PV dynamically provisioned by Longhorn.

---

## Check Service

```bash
kubectl get svc -n nginx-storage-demo
```

Expected:

```text
nginx-longhorn-lb   LoadBalancer   10.43.x.x   192.168.178.xxx   80:xxxxx/TCP
```

The `EXTERNAL-IP` should come from the MetalLB pool:

```text
192.168.178.210 - 192.168.178.220
```

---

# Access the Application

Get the external IP:

```bash
kubectl get svc nginx-longhorn-lb -n nginx-storage-demo
```

Example:

```text
192.168.178.210
```

Open in browser:

```text
http://192.168.178.210
```

Or test with curl:

```bash
curl http://192.168.178.210
```

Expected page content:

```text
Nginx with Longhorn Storage and MetalLB
```

---

# Persistence Test

This test proves that the HTML file lives on Longhorn storage and survives Pod deletion.

## Step 1 — Get Pod Name

```bash
POD_NAME=$(kubectl get pod -n nginx-storage-demo -l app=nginx-longhorn -o jsonpath='{.items[0].metadata.name}')
echo $POD_NAME
```

---

## Step 2 — Append a Persistence Marker

```bash
kubectl exec -n nginx-storage-demo "$POD_NAME" -- sh -c \
'echo "<p>Persistence marker added at: $(date)</p>" >> /usr/share/nginx/html/index.html'
```

---

## Step 3 — Verify Marker

Replace the IP with your actual MetalLB IP:

```bash
curl http://192.168.178.210
```

You should see:

```text
Persistence marker added at:
```

---

## Step 4 — Delete the Pod

```bash
kubectl delete pod -n nginx-storage-demo -l app=nginx-longhorn
```

Kubernetes will automatically create a new Pod.

Watch:

```bash
kubectl get pods -n nginx-storage-demo -w
```

Wait until the new Pod is:

```text
Running
```

---

## Step 5 — Check Same Page Again

```bash
curl http://192.168.178.210
```

The persistence marker should still exist.

If the marker still exists, Longhorn persistence works.

---

# Check Longhorn UI

Open the Longhorn UI and check the volume created for:

```text
nginx-html-pvc
```

Expected volume status:

```text
Healthy
Attached
```

You should also see replicas created across available Longhorn nodes, depending on your Longhorn replica settings.

---

# Useful Commands

## All Resources in Namespace

```bash
kubectl get all -n nginx-storage-demo
```

---

## PVC

```bash
kubectl get pvc -n nginx-storage-demo
kubectl describe pvc nginx-html-pvc -n nginx-storage-demo
```

---

## Pod Logs

```bash
kubectl logs -n nginx-storage-demo -l app=nginx-longhorn
```

---

## Pod Details

```bash
kubectl describe pod -n nginx-storage-demo -l app=nginx-longhorn
```

---

## Service Details

```bash
kubectl describe svc nginx-longhorn-lb -n nginx-storage-demo
```

---

## Events

```bash
kubectl get events -n nginx-storage-demo --sort-by=.metadata.creationTimestamp
```

---

# Troubleshooting

## PVC Stuck in Pending

Check PVC:

```bash
kubectl describe pvc nginx-html-pvc -n nginx-storage-demo
```

Check Longhorn:

```bash
kubectl get pods -n longhorn-system
kubectl get storageclass
```

Common causes:

```text
Longhorn not healthy
StorageClass missing
Longhorn CSI not running
Node storage unavailable
```

---

## Pod Stuck in Pending

Check Pod:

```bash
kubectl describe pod -n nginx-storage-demo -l app=nginx-longhorn
```

Common causes:

```text
PVC not Bound
Longhorn volume not attached
Node scheduling issue
```

---

## Service Has No External IP

Check service:

```bash
kubectl get svc nginx-longhorn-lb -n nginx-storage-demo
```

Check MetalLB:

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

Common causes:

```text
MetalLB not running
IPAddressPool missing
L2Advertisement missing
IP pool exhausted
K3s ServiceLB still enabled
```

---

## Browser Cannot Access External IP

Check service:

```bash
kubectl get svc -n nginx-storage-demo
```

Check endpoints:

```bash
kubectl get endpoints -n nginx-storage-demo
```

Check Pod:

```bash
kubectl get pods -n nginx-storage-demo -o wide
```

Try curl:

```bash
curl http://EXTERNAL-IP
```

---

## DNS Problems

Run:

```bash
kubectl run netshoot \
  --image=nicolaka/netshoot \
  -it --rm --restart=Never -- bash
```

Inside:

```bash
nslookup kubernetes.default.svc.cluster.local
```

Expected:

```text
Address: 10.43.0.1
```

If DNS fails from worker Pods but works from master Pods, check the K3s baseline networking configuration:

```yaml
disable-network-policy: true
flannel-backend: host-gw
disable:
  - servicelb
```

---

# Cleanup

## Option 1 — Delete Everything Using Manifests

From this folder:

```bash
kubectl delete -f .
```

---

## Option 2 — Delete Namespace

This removes all resources in the demo namespace:

```bash
kubectl delete namespace nginx-storage-demo
```

---

## Verify Cleanup

```bash
kubectl get namespace nginx-storage-demo
```

Expected:

```text
NotFound
```

Check PVC/PV:

```bash
kubectl get pvc -A | grep nginx-html-pvc
kubectl get pv | grep nginx-html-pvc
```

There should be no remaining resources for this demo.

---

# What This Demo Proves

If this demo works, then the following platform components are healthy:

```text
K3s node networking
CoreDNS
Longhorn StorageClass
Longhorn CSI
PersistentVolumeClaim provisioning
Pod volume attachment
MetalLB LoadBalancer IP assignment
LAN access to Kubernetes services
```

This is an important validation before deploying more advanced services such as:

- Harbor
- Forgejo
- Woodpecker CI
- ArgoCD
- Prometheus/Grafana
- Loki/Promtail
