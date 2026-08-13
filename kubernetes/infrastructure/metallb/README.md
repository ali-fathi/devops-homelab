# 🚀 MetalLB – LoadBalancer for K3s Homelab

For the broad platform study guide, read:

```text
docs/homelab-study-guide.md
```

MetalLB is a network load-balancer implementation for **bare-metal Kubernetes clusters** like K3s.

It enables Kubernetes to use:

```yaml
type: LoadBalancer
```

just like in cloud environments (AWS, Azure, GCP).

---

# 🎯 Purpose

Without MetalLB:

- Services use `NodePort`
- Access is complex (`NODE_IP:PORT`)
- Not production-like

With MetalLB:

- Services receive a real IP address
- Clean access (`http://192.168.x.x`)
- Required for real DevOps platforms (ArgoCD, Harbor, Grafana, etc.)

---

# 🧠 How MetalLB Works

```text
Service (LoadBalancer)
        ↓
MetalLB Controller
        ↓
IP assigned from pool
        ↓
MetalLB Speaker advertises IP (ARP)
        ↓
Traffic routed from LAN → Kubernetes service
```

---

# 🏗️ Architecture

```text
+--------------------------+
|     Kubernetes Cluster   |
|                          |
|  Service (LoadBalancer)  |
|            ↓             |
|        MetalLB           |
|            ↓             |
|  External IP (LAN)       |
+------------+-------------+
             ↓
       Your Local Network
```

---

# 📦 Deployment Overview

This setup uses:

- Layer2 mode (recommended for homelab)
- Static IP pool
- Native MetalLB manifests

---

# ⚙️ Prerequisites

✅ K3s cluster running  
✅ kubectl configured  
✅ Same subnet for all nodes  
✅ Free IP range available  

---

# 🌐 Network Planning (IMPORTANT)

Your network:

```text
192.168.178.0/24
```

MetalLB IP Pool:

```text
192.168.178.210 - 192.168.178.220
```

⚠️ Requirements:

- Must be in your LAN subnet
- Must NOT overlap with DHCP range
- Must NOT be used by other devices

---

# 🚀 Installation (Step-by-Step)

---

## ✅ Step 1 — Create Namespace

```bash
kubectl create namespace metallb-system
```

---

## ✅ Step 2 — Install MetalLB

```bash
kubectl apply -f kubernetes/infrastructure/metallb/metallb-native.yaml
```

This repository vendors the upstream MetalLB `v0.14.5` native manifest. Apply the reviewed local copy rather than downloading an unreviewed mutable manifest at install time.

---

## ✅ Step 3 — Verify Installation

```bash
kubectl get pods -n metallb-system
```

Expected:

```text
controller-xxxxx      Running
speaker-xxxxx         Running
speaker-xxxxx         Running
```

---

# 🔐 Controller webhook RBAC

MetalLB's controller automatically creates and rotates its webhook TLS certificate. To publish the resulting CA, it needs to update the single cluster-scoped `ValidatingWebhookConfiguration` named `metallb-webhook-configuration`.

The controller ClusterRole is therefore restricted to that exact named validating webhook. It has **no** permission for `MutatingWebhookConfiguration` resources; MetalLB's native manifest defines no mutating webhook and the controller source configures only the validating webhook plus a CRD conversion webhook.

Trivy rule `KSV-0114` cannot distinguish this required, resource-name-constrained certificate-rotation access from broad webhook administration. The time-bound exception in [`.trivyignore.yaml`](../../../.trivyignore.yaml) applies only to `KSV-0114` in this one vendor manifest; it expires on 2027-08-13. The rationale, validation, and review deadline are recorded in [Security Findings](../../../docs/security-findings.md). Do not remove the remaining validating-webhook access or automatic certificate rotation will fail and MetalLB configuration changes may be rejected after certificate expiry.

Verify the live identity has no mutating-webhook access:

```bash
kubectl auth can-i patch mutatingwebhookconfigurations.admissionregistration.k8s.io --as=system:serviceaccount:metallb-system:controller
```

Expected result: `no`.

# ⚙️ Configuration

---

## ✅ Step 4 — Create IP Pool

File:

```text
kubernetes/infrastructure/metallb/ip-pool.yaml
```

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.178.210-192.168.178.220
```

---

## ✅ Step 5 — Create L2 Advertisement

File:

```text
kubernetes/infrastructure/metallb/l2-advertisement.yaml
```

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-advertisement
  namespace: metallb-system
```

---

## ✅ Step 6 — Apply Configuration

```bash
kubectl apply -f kubernetes/infrastructure/metallb/
```

---

# ✅ Verification

---

## ✅ Step 7 — Deploy Test Application

```bash
kubectl create deployment nginx --image=nginx
```

---

## ✅ Step 8 — Expose via LoadBalancer

```bash
kubectl expose deployment nginx \
  --type=LoadBalancer \
  --port=80
```

---

## ✅ Step 9 — Verify Service

```bash
kubectl get svc
```

Expected:

```text
nginx   LoadBalancer   192.168.178.210
```

---

## ✅ Step 10 — Test Access

Open browser:

```text
http://192.168.178.210
```

✅ Nginx page should appear

---

# 📂 Project Structure

```text
kubernetes/
└── infrastructure/
    └── metallb/
        ├── README.md
        ├── ip-pool.yaml
        └── l2-advertisement.yaml
```

---

# 🔧 Troubleshooting

---

## ❌ Service stuck in `Pending`

```bash
kubectl get svc
```

Fix:

- Check IP pool config
- Verify MetalLB pods
- Ensure correct subnet

---

## ❌ MetalLB Pods Not Running

```bash
kubectl get pods -n metallb-system
```

Fix:

```bash
kubectl delete pod -n metallb-system --all
```

---

## ❌ Cannot Access IP

Test:

```bash
ping 192.168.178.210
```

Check:

- IP is free
- Same subnet
- Firewall rules

---

## ❌ IP Already in Use

Solution:

- Choose another free IP range

---

## ❌ Wrong Network Range

Verify:

```bash
ip a
```

Ensure MetalLB IP pool matches your LAN subnet.

---

## ❌ Debug MetalLB

Controller logs:

```bash
kubectl logs -n metallb-system deployment/controller
```

Speaker logs:

```bash
kubectl logs -n metallb-system daemonset/speaker
```

---

# 📊 Useful Commands

```bash
kubectl get svc
kubectl get pods -n metallb-system
kubectl describe svc nginx
kubectl get events
kubectl logs -n metallb-system deployment/controller
```

---

# 🎯 Concepts Learned

✅ LoadBalancer services  
✅ External IP allocation  
✅ ARP-based routing (Layer2)  
✅ Kubernetes networking  
✅ Real-world infrastructure design  

---

# 🔄 Cleanup

```bash
kubectl delete svc nginx
kubectl delete deployment nginx
```

---

# 🔮 Next Steps

Continue with:

👉 Phase 3 — Longhorn (Persistent Storage)

Then:

- Monitoring (Prometheus + Grafana)
- Logging (Loki)
- Registry (Harbor)
- CI/CD (Forgejo + Woodpecker)
- GitOps (ArgoCD)

---

# ✅ Summary

MetalLB enables:

- External service access
- Clean IP-based routing
- Production-like networking
- LoadBalancer services in homelab

It is the foundation for your DevOps platform.
