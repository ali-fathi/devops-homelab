# ☸️ Kubernetes kubectl Cheat Sheet

This document contains the most important `kubectl` commands used for daily Kubernetes administration, troubleshooting, debugging, and learning.

---

# 🎯 Prerequisites

Verify cluster connectivity:

```bash
kubectl get nodes
```

Expected:

```text
NAME          STATUS   ROLES
k3s-master    Ready    control-plane
k3s-worker1   Ready
k3s-worker2   Ready
```

---

# 📋 Cluster Information

View cluster information:

```bash
kubectl cluster-info
```

View nodes:

```bash
kubectl get nodes
```

View node details:

```bash
kubectl describe node k3s-master
```

View Kubernetes version:

```bash
kubectl version
```

View API resources:

```bash
kubectl api-resources
```

---

# 📦 Namespaces

List namespaces:

```bash
kubectl get namespaces
```

Create namespace:

```bash
kubectl create namespace learning
```

Delete namespace:

```bash
kubectl delete namespace learning
```

View resources in namespace:

```bash
kubectl get all -n learning
```

Set default namespace:

```bash
kubectl config set-context --current --namespace=learning
```

---

# 🚀 Pods

List pods:

```bash
kubectl get pods
```

List pods in all namespaces:

```bash
kubectl get pods -A
```

Wide output:

```bash
kubectl get pods -o wide
```

Describe pod:

```bash
kubectl describe pod nginx
```

Delete pod:

```bash
kubectl delete pod nginx
```

Watch pods:

```bash
kubectl get pods -w
```

---

# 📄 Deployments

List deployments:

```bash
kubectl get deployments
```

Describe deployment:

```bash
kubectl describe deployment nginx
```

Scale deployment:

```bash
kubectl scale deployment nginx --replicas=5
```

Restart deployment:

```bash
kubectl rollout restart deployment nginx
```

View rollout status:

```bash
kubectl rollout status deployment nginx
```

View rollout history:

```bash
kubectl rollout history deployment nginx
```

Undo deployment:

```bash
kubectl rollout undo deployment nginx
```

Delete deployment:

```bash
kubectl delete deployment nginx
```

---

# 🌐 Services

List services:

```bash
kubectl get svc
```

Describe service:

```bash
kubectl describe svc nginx
```

Delete service:

```bash
kubectl delete svc nginx
```

---

# 🌍 Ingress

List ingress resources:

```bash
kubectl get ingress
```

Describe ingress:

```bash
kubectl describe ingress nginx
```

Delete ingress:

```bash
kubectl delete ingress nginx
```

---

# ⚙️ ConfigMaps

List ConfigMaps:

```bash
kubectl get configmaps
```

Create ConfigMap:

```bash
kubectl create configmap app-config \
--from-literal=APP_ENV=development
```

Describe ConfigMap:

```bash
kubectl describe configmap app-config
```

Delete ConfigMap:

```bash
kubectl delete configmap app-config
```

---

# 🔐 Secrets

List secrets:

```bash
kubectl get secrets
```

Create secret:

```bash
kubectl create secret generic db-password \
--from-literal=password=supersecret
```

Describe secret:

```bash
kubectl describe secret db-password
```

Delete secret:

```bash
kubectl delete secret db-password
```

---

# 💾 Storage

List Persistent Volumes:

```bash
kubectl get pv
```

List Persistent Volume Claims:

```bash
kubectl get pvc
```

Describe PVC:

```bash
kubectl describe pvc my-pvc
```

Describe PV:

```bash
kubectl describe pv my-pv
```

Storage classes:

```bash
kubectl get storageclass
```

---

# 📜 Logs

View pod logs:

```bash
kubectl logs nginx
```

Follow logs:

```bash
kubectl logs -f nginx
```

View logs from specific container:

```bash
kubectl logs nginx -c app
```

View previous logs:

```bash
kubectl logs --previous nginx
```

---

# 🖥️ Execute Commands Inside Pods

Open shell:

```bash
kubectl exec -it nginx -- sh
```

For Ubuntu-based containers:

```bash
kubectl exec -it nginx -- bash
```

Run command:

```bash
kubectl exec nginx -- hostname
```

---

# 🔍 Troubleshooting

---

## View Events

Most Kubernetes problems can be identified here:

```bash
kubectl get events
```

Sort by newest:

```bash
kubectl get events --sort-by=.metadata.creationTimestamp
```

---

## Describe Resource

Inspect pod:

```bash
kubectl describe pod nginx
```

Inspect deployment:

```bash
kubectl describe deployment nginx
```

Inspect node:

```bash
kubectl describe node k3s-worker1
```

---

## Common Pod States

Healthy:

```text
Running
Completed
```

Problems:

```text
Pending
CrashLoopBackOff
ImagePullBackOff
ErrImagePull
CreateContainerError
OOMKilled
```

---

## Find Why a Pod Is Failing

Step 1:

```bash
kubectl get pods
```

Step 2:

```bash
kubectl describe pod POD_NAME
```

Step 3:

```bash
kubectl logs POD_NAME
```

---

# 📂 Apply and Delete Resources

Apply file:

```bash
kubectl apply -f deployment.yaml
```

Apply folder:

```bash
kubectl apply -f kubernetes/
```

Delete file:

```bash
kubectl delete -f deployment.yaml
```

Delete folder:

```bash
kubectl delete -f kubernetes/
```

---

# 📑 YAML Validation

Preview changes:

```bash
kubectl apply -f deployment.yaml --dry-run=client
```

Generate YAML:

```bash
kubectl create deployment nginx \
--image=nginx \
--dry-run=client \
-o yaml
```

---

# 🔎 Resource Discovery

View everything:

```bash
kubectl get all
```

View everything in all namespaces:

```bash
kubectl get all -A
```

View all resources:

```bash
kubectl api-resources
```

Explain resource:

```bash
kubectl explain deployment
```

Explain field:

```bash
kubectl explain deployment.spec
```

---

# 📊 Useful Filters

Show pods on specific node:

```bash
kubectl get pods -o wide
```

Show only names:

```bash
kubectl get pods -o name
```

Output YAML:

```bash
kubectl get deployment nginx -o yaml
```

Output JSON:

```bash
kubectl get deployment nginx -o json
```

---

# 🔄 Context and Configuration

Show current context:

```bash
kubectl config current-context
```

Show contexts:

```bash
kubectl config get-contexts
```

View config:

```bash
kubectl config view
```

Switch context:

```bash
kubectl config use-context my-context
```

---

# 🚑 Emergency Troubleshooting Workflow

When something is broken:

### 1. Check nodes

```bash
kubectl get nodes
```

### 2. Check pods

```bash
kubectl get pods -A
```

### 3. Describe failing pod

```bash
kubectl describe pod POD_NAME
```

### 4. View logs

```bash
kubectl logs POD_NAME
```

### 5. Check events

```bash
kubectl get events --sort-by=.metadata.creationTimestamp
```

### 6. Verify deployment

```bash
kubectl describe deployment APP_NAME
```

### 7. Verify service

```bash
kubectl get svc
```

### 8. Verify ingress

```bash
kubectl get ingress
```

---

# 🎓 Kubernetes Learning Path

Master these concepts before moving to GitOps and CI/CD:

✅ Namespaces

✅ Pods

✅ Deployments

✅ Services

✅ Ingress

✅ ConfigMaps

✅ Secrets

✅ Persistent Volumes

✅ Logs

✅ Events

✅ Troubleshooting

✅ kubectl

Once comfortable with these topics, continue to:

- Helm
- MetalLB
- Longhorn
- Monitoring
- Harbor
- Forgejo
- Woodpecker CI
- ArgoCD
- GitOps