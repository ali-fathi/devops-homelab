# 🚀 MetalLB for K3s Homelab

MetalLB provides LoadBalancer functionality for bare-metal Kubernetes clusters.

---

# 🎯 Purpose

- Enable `type: LoadBalancer`
- Provide external IPs inside local network
- Make services accessible like cloud environments

---

# 🧠 Architecture

```text
Service (LoadBalancer)
        ↓
MetalLB
        ↓
Assigned External IP
        ↓
Network (LAN)
```

---

# 📦 Installation

```bash
kubectl create namespace metallb-system
```

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
```

---

# ⚙️ Configuration

## IP Pool

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

## L2 Advertisement

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-advertisement
  namespace: metallb-system
```

---

# ✅ Usage

Expose service:

```bash
kubectl expose deployment nginx \
  --type=LoadBalancer \
  --port=80
```

Check:

```bash
kubectl get svc
```

---

# 🔧 Troubleshooting

## Service stuck in Pending

```bash
kubectl get svc
```

Fix:

- Check IP pool range
- Check MetalLB pods

---

## Verify MetalLB Pods

```bash
kubectl get pods -n metallb-system
```

---

## Restart MetalLB

```bash
kubectl delete pod -n metallb-system --all
```

---

# 📌 Key Concepts

- LoadBalancer services
- External IP allocation
- Layer2 networking
- Bare-metal Kubernetes networking

