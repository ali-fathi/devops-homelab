# ☸️ Kubernetes / K3s Homelab Notes

This directory contains Kubernetes manifests, infrastructure components, applications, and platform services for the DevOps homelab.

The cluster is based on **K3s** and is managed from the DevContainer using:

- kubectl
- helm
- terraform
- ansible

---

# 🏗️ Cluster Nodes

| Node | Role | IP |
|---|---|---|
| k3s-master | Control Plane | 192.168.178.80 |
| k3s-worker1 | Worker | 192.168.178.81 |
| k3s-worker2 | Worker | 192.168.178.82 |

---

# ⚙️ Recommended K3s Base Configuration

After installing K3s, apply the following configuration on the **master node**.

File:

```bash
/etc/rancher/k3s/config.yaml
```

Recommended content:

```yaml
disable-network-policy: true
flannel-backend: host-gw
disable:
  - servicelb
```

---

# 🧠 Why This Configuration Is Used

## 1. Disable K3s Network Policy Controller

```yaml
disable-network-policy: true
```

K3s includes a built-in Network Policy controller. In this homelab, stale or conflicting `KUBE-ROUTER`, `KUBE-NWPLCY`, and `KUBE-POD-FW` iptables/nftables rules caused cross-node pod networking problems. K3s documentation describes the built-in Network Policy controller as part of K3s networking services. [1](https://github.com/k3s-io/k3s/issues/7261)

Symptoms included:

```text
Pod on master     → DNS works
Pod on worker     → DNS fails
Worker pod        → cannot reach CoreDNS pod on master
Longhorn webhook  → timeout
MetalLB webhook   → timeout
PVC               → Pending
```

Example failed DNS test from worker pod:

```bash
nslookup kubernetes.default.svc.cluster.local
```

Failure:

```text
;; communications error to 10.43.0.10#53: timed out
;; no servers could be reached
```

---

## 2. Use Flannel `host-gw` Instead of `vxlan`

```yaml
flannel-backend: host-gw
```

The default Flannel backend was `vxlan`. In this homelab, VXLAN cross-node pod traffic was not working correctly between workers and the master node.

Because all nodes are on the same LAN:

```text
192.168.178.80
192.168.178.81
192.168.178.82
```

`host-gw` is simpler and more reliable.

With `host-gw`, pod traffic is routed directly over the LAN instead of using VXLAN encapsulation.

Expected route example on worker1:

```text
10.42.0.0/24 via 192.168.178.80 dev ens18
10.42.2.0/24 via 192.168.178.82 dev ens18
10.42.1.0/24 dev cni0
```

---

## 3. Disable K3s ServiceLB Because MetalLB Is Used

```yaml
disable:
  - servicelb
```

K3s includes a built-in ServiceLB load balancer controller. This homelab uses **MetalLB** instead, because MetalLB provides proper bare-metal `LoadBalancer` support using an IP pool. K3s documents ServiceLB as a built-in networking service, and MetalLB is designed for bare-metal Kubernetes load balancer functionality. [1](https://github.com/k3s-io/k3s/issues/7261)[2](https://www.bookstack.cn/read/k3s-1.33-en/37dcd96a7785228e.md)

MetalLB IP pool used in this homelab:

```text
192.168.178.210 - 192.168.178.220
```

---

# 🚀 Apply Configuration

## Step 1 — Edit K3s Config on Master

On `k3s-master`:

```bash
sudo mkdir -p /etc/rancher/k3s
sudo nano /etc/rancher/k3s/config.yaml
```

Add:

```yaml
disable-network-policy: true
flannel-backend: host-gw
disable:
  - servicelb
```

Save the file.

---

## Step 2 — Stop Worker Agents

On `k3s-worker1`:

```bash
sudo systemctl stop k3s-agent
```

On `k3s-worker2`:

```bash
sudo systemctl stop k3s-agent
```

---

## Step 3 — Stop Master

On `k3s-master`:

```bash
sudo systemctl stop k3s
```

---

## Step 4 — Clean K3s Networking State

Run on **all nodes**:

```bash
sudo /usr/local/bin/k3s-killall.sh
```

The K3s killall script stops K3s containers and cleans networking components and iptables chains without deleting cluster data. [3](https://documentation.suse.com/cloudnative/k3s/latest/en/upgrades/killall.html)

Run it on:

```text
k3s-master
k3s-worker1
k3s-worker2
```

---

## Step 5 — Start Master

On `k3s-master`:

```bash
sudo systemctl start k3s
```

Wait around 60 seconds.

---

## Step 6 — Start Workers

On `k3s-worker1`:

```bash
sudo systemctl start k3s-agent
```

On `k3s-worker2`:

```bash
sudo systemctl start k3s-agent
```

---

# ✅ Verify Cluster

From the DevContainer:

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

# ✅ Verify Flannel Backend

On the master:

```bash
sudo cat /var/lib/rancher/k3s/agent/etc/flannel/net-conf.json
```

Expected:

```json
{
  "Network": "10.42.0.0/16",
  "EnableIPv6": false,
  "EnableIPv4": true,
  "Backend": {
    "Type": "host-gw"
  }
}
```

---

# ✅ Verify Routes

On worker1:

```bash
ip route | grep 10.42
```

Expected style:

```text
10.42.0.0/24 via 192.168.178.80 dev ens18
10.42.1.0/24 dev cni0
10.42.2.0/24 via 192.168.178.82 dev ens18
```

On worker2:

```bash
ip route | grep 10.42
```

Expected style:

```text
10.42.0.0/24 via 192.168.178.80 dev ens18
10.42.1.0/24 via 192.168.178.81 dev ens18
10.42.2.0/24 dev cni0
```

---

# ✅ Verify DNS From Worker Pod

Create a test pod on worker1:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dns-worker1-test
spec:
  nodeSelector:
    kubernetes.io/hostname: k3s-worker1
  containers:
    - name: test
      image: busybox:1.36
      command:
        - sleep
        - "3600"
```

Apply:

```bash
kubectl apply -f dns-worker1-test.yaml
```

Exec into it:

```bash
kubectl exec -it dns-worker1-test -- sh
```

Test DNS:

```sh
nslookup kubernetes.default.svc.cluster.local
```

Expected:

```text
Name: kubernetes.default.svc.cluster.local
Address: 10.43.0.1
```

If this works, cross-node pod networking and CoreDNS are healthy.

---

# ✅ Verify Service Networking

Inside the test pod:

```sh
nc -zv 10.43.0.10 53
```

Expected:

```text
open
```

Check CoreDNS endpoint:

```bash
kubectl get endpoints -n kube-system kube-dns
```

Example:

```text
10.42.0.6:53
```

Then test direct pod connectivity:

```sh
ping 10.42.0.6
```

Expected:

```text
64 bytes from 10.42.0.6
```

---

# ✅ Verify MetalLB

Check MetalLB pods:

```bash
kubectl get pods -n metallb-system
```

Expected:

```text
controller   Running
speaker      Running
speaker      Running
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

# ✅ Test MetalLB LoadBalancer

Create test deployment:

```bash
kubectl create deployment nginx-metallb-test --image=nginx
```

Expose it:

```bash
kubectl expose deployment nginx-metallb-test \
  --type=LoadBalancer \
  --port=80
```

Check service:

```bash
kubectl get svc
```

Expected:

```text
nginx-metallb-test   LoadBalancer   192.168.178.210
```

Open in browser:

```text
http://192.168.178.210
```

Cleanup:

```bash
kubectl delete svc nginx-metallb-test
kubectl delete deployment nginx-metallb-test
```

---

# ✅ Verify Longhorn After Networking Fix

After DNS works from worker pods, restart Longhorn:

```bash
kubectl delete pods -n longhorn-system --all
```

Watch status:

```bash
kubectl get pods -n longhorn-system -w
```

Expected:

```text
longhorn-manager       Running
longhorn-csi-plugin    Running
longhorn-ui            Running
```

Check PVCs:

```bash
kubectl get pvc
```

Expected:

```text
test-pvc   Bound
```

---

# 🧪 Troubleshooting Checklist

## DNS Fails From Worker Pod

Test:

```bash
kubectl run netshoot \
  --image=nicolaka/netshoot \
  -it --rm --restart=Never -- bash
```

Inside:

```bash
nslookup kubernetes.default.svc.cluster.local
```

If this fails, test from master pod.

---

## DNS Works on Master Pod but Not Worker Pod

This means:

```text
worker pod → master pod networking is broken
```

Recommended fix:

```yaml
flannel-backend: host-gw
```

Then reset K3s networking with:

```bash
sudo /usr/local/bin/k3s-killall.sh
```

---

## Check Stale Kube-Router Rules

Run on all nodes:

```bash
sudo iptables-save | grep -E "KUBE-ROUTER|KUBE-NWPLCY|KUBE-POD-FW"
```

Expected:

```text
no output
```

If output exists, clean stale rules:

```bash
sudo iptables-save \
  | grep -v KUBE-ROUTER \
  | grep -v KUBE-NWPLCY \
  | grep -v KUBE-POD-FW \
  | sudo iptables-restore
```

Then restart K3s.

---

## Check Flannel Routes

```bash
ip route | grep 10.42
```

With `host-gw`, routes should go through real node IPs:

```text
via 192.168.178.x dev ens18
```

---

## Check CoreDNS

```bash
kubectl get pods -n kube-system -o wide
kubectl get svc -n kube-system kube-dns
kubectl get endpoints -n kube-system kube-dns
```

Expected:

```text
kube-dns ClusterIP 10.43.0.10
CoreDNS endpoint 10.42.x.x:53
```

---

# ✅ Final Recommended Baseline

For this homelab, the recommended K3s baseline is:

```yaml
disable-network-policy: true
flannel-backend: host-gw
disable:
  - servicelb
```

This gives the cluster:

```text
Stable pod networking
Direct LAN routing
No stale kube-router network policy rules
MetalLB as the only LoadBalancer provider
```

This configuration should be applied immediately after installing K3s, before deploying:

- MetalLB
- Longhorn
- Harbor
- Forgejo
- Woodpecker CI
- ArgoCD
- Prometheus/Grafana
- Loki/Grafana Alloy
