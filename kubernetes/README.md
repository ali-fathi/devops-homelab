# Kubernetes

This folder contains all Kubernetes manifests and Helm configurations.

Structure:

- bootstrap
- infrastructure
- gitops
- observability
- registry
- ci
- applications

Everything deployed to the cluster should be stored here.

# ☸️ Kubernetes

This directory contains Kubernetes manifests, platform infrastructure, applications, and GitOps resources for the DevOps Homelab.

The cluster is based on **K3s** and is managed from the DevContainer using:

- kubectl
- helm
- terraform
- ansible

---

## Cluster Nodes

| Node | Role | IP |
|---|---|---|
| k3s-master | Control Plane | 192.168.178.80 |
| k3s-worker1 | Worker | 192.168.178.81 |
| k3s-worker2 | Worker | 192.168.178.82 |

---

## Recommended K3s Baseline Configuration

After installing K3s, configure the master node with the following baseline (more info under docs/k3s-baseline-networking.md)

File:
```bash
/etc/rancher/k3s/config.yaml
```


```yaml
disable-network-policy: true
flannel-backend: host-gw
disable:
  - servicelb