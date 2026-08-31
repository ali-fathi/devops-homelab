
# 🚀 DevOps Homelab Platform

A portable, reproducible DevOps learning and operations environment built around a remote K3s Kubernetes cluster and managed from a VS Code DevContainer.

The goal of this repository is simple:

> Clone the repository, open it in VS Code, start the DevContainer, connect to the cluster, and immediately begin working from a consistent environment on any Mac or Linux machine.

---

# 🎯 What Is This Repository?

This repository serves as the central source of truth for my homelab platform.

It contains:

- DevContainer configuration
- Kubernetes manifests
- Terraform code
- Ansible automation
- Infrastructure documentation
- GitOps configuration
- Bootstrap scripts

The repository is designed to be:

- Portable
- Reproducible
- Version controlled
- GitOps friendly
- Easy to rebuild on a new machine

---

# 🏗️ Architecture

```text
┌─────────────────────────────────────┐
│         Local Workstation           │
│                                     │
│  macOS / Linux                      │
│  VS Code                            │
│  Docker                             │
│  DevContainer                       │
│                                     │
│  Tools:                             │
│  - kubectl                          │
│  - helm                             │
│  - terraform                        │
│  - ansible                          │
│  - kustomize                        │
└─────────────────┬───────────────────┘
                  │
                  │ kubeconfig
                  │
                  ▼
┌─────────────────────────────────────┐
│          K3s Kubernetes Cluster     │
│                                     │
│  API VIP: 192.168.178.85            │
│  Server:  192.168.178.80             │
│  Server:  192.168.178.83             │
│  Server:  192.168.178.84             │
│  Workers: 192.168.178.81, .82        │
│                                     │
│  Platform Services:                 │
│  - Argo CD                          │
│  - Longhorn                         │
│  - MetalLB                          │
│  - Prometheus/Grafana               │
│  - Alertmanager                     │
│  - Loki/Grafana Alloy               │
│  - Garmin InfluxDB                  │
│  - Ring VictoriaMetrics             │
│  - Health Dashboard                 │
│  Planned: Harbor/Forgejo/Jenkins    │
└─────────────────────────────────────┘
```

---

# 🧠 How It Works

The DevContainer runs locally on your workstation.

The Kubernetes cluster runs remotely in your homelab.

The DevContainer contains only the tools required to manage the cluster:

- kubectl
- helm
- terraform
- ansible
- git
- kustomize

The connection between the DevContainer and the Kubernetes cluster is made using a kubeconfig file.

```text
DevContainer
    ↓
kubectl
    ↓
kubeconfig
    ↓
https://192.168.178.85:6443 (Kube-VIP)
    ↓
K3s API Server
    ↓
Cluster
```

No Kubernetes components run locally.

Your workstation is only used as a management environment.

---

# 📂 Repository Structure

```text
devops-homelab/
│
├── README.md
│
├── .devcontainer/
│
├── docs/
│
├── apps/
│   ├── health-dashboard/
│   └── homelab-api/
│
├── .github/workflows/
│
├── ansible/
│
├── terraform/
│
├── kubernetes/
│
└── scripts/
```

## 📖 Recommended reading order

```text
1. docs/homelab-study-guide.md
2. .devcontainer/README.md
3. ansible/README.md
4. kubernetes/README.md
5. kubernetes/infrastructure/README.md
6. kubernetes/observability/README.md
7. kubernetes/gitops/argocd/README.md
8. apps/health-dashboard/README.md
9. kubernetes/applications/health-dashboard/README.md
10. terraform/README.md
```

The documentation distinguishes implemented components from planned/scaffolded components. Do not treat a future design section as proof that a service is currently installed.

---

# ✅ Prerequisites

Before starting, install the following:

## macOS

- Docker Desktop
- Visual Studio Code
- Dev Containers Extension

## Linux

- Docker Engine
- Visual Studio Code
- Dev Containers Extension

Verify:

```bash
docker --version
code --version
```

---

# 🚀 First Time Setup

Follow these steps exactly.

---

## Step 1 — Clone the Repository

```bash
git clone https://github.com/ali-fathi/devops-homelab.git

cd devops-homelab
```

---

## Step 2 — Obtain the K3s kubeconfig

Connect to the master node:

```bash
ssh root@192.168.178.80
```

Display the K3s configuration:

```bash
sudo cat /etc/rancher/k3s/k3s.yaml
```

Copy the entire file.

---

## Step 3 — Update the Kubernetes API Address

Inside the copied file find:

```yaml
server: https://127.0.0.1:6443
```

Replace it with the Kube-VIP endpoint:

```yaml
server: https://192.168.178.85:6443
```

Why?

The default K3s configuration only works locally on the server itself.

Changing the address allows your workstation and DevContainer to reach the Kubernetes API remotely.

---

## Step 4 — Save kubeconfig on Your Workstation

Create the Kubernetes directory:

```bash
mkdir -p ~/.kube
```

Create the configuration file:

```bash
nano ~/.kube/k3s-config
```

Paste the modified kubeconfig.

Save the file.

Set permissions:

```bash
chmod 600 ~/.kube/k3s-config
```

---

## Step 5 — Verify Cluster Connectivity

Before using the DevContainer, verify that your workstation can communicate with the cluster.

Run:

```bash
kubectl --kubeconfig ~/.kube/k3s-config get nodes
```

Expected result:

```text
k3s-master
k3s-master2
k3s-master3
k3s-worker1
k3s-worker2
```

If this fails:

- Verify the IP address
- Verify network connectivity
- Verify firewall settings
- Verify the kubeconfig file

Network tests:

```bash
ping 192.168.178.85
```

```bash
kubectl --kubeconfig ~/.kube/k3s-config --server=https://192.168.178.85:6443 get --raw=/readyz
```

Do not continue until this step succeeds.

---

## Step 6 — Open the Project

```bash
code .
```

---

## Step 7 — Start the DevContainer

Inside VS Code:

```text
F1
→ Dev Containers: Reopen in Container
```

VS Code will automatically:

- Build the container image
- Create the development environment
- Install required tools
- Mount the kubeconfig
- Configure the workspace

The first build may take several minutes.

Subsequent starts are much faster.

---

## Step 8 — Verify the Environment

Open a terminal inside the DevContainer.

Verify Kubernetes:

```bash
kubectl get nodes
```

Verify Helm:

```bash
helm version
```

Verify Terraform:

```bash
terraform version
```

Verify Ansible:

```bash
ansible --version
```

If all commands succeed, the environment is ready.

🎉 Congratulations!

Your DevOps workstation is now connected to the Kubernetes cluster.

---

# 🔄 Daily Usage

Open the repository:

```bash
code .
```

Start the DevContainer:

```text
Dev Containers: Reopen in Container
```

Verify the cluster:

```bash
kubectl get nodes
```

Start working.

---

# 🔁 Rebuilding the Environment

If the DevContainer configuration changes:

```text
F1
→ Dev Containers: Rebuild Container
```

This recreates the environment using the latest Dockerfile and configuration.

---

# 🛠️ Available Tools

Inside the DevContainer:

```bash
kubectl
```

```bash
helm
```

```bash
terraform
```

```bash
ansible
```

```bash
git
```

```bash
kustomize
```

---

# 🎯 Platform Components

Implemented or actively configured:

- Argo CD
- MetalLB
- Longhorn
- Prometheus
- Grafana
- Alertmanager
- Loki
- Grafana Alloy
- External Secrets Operator integration
- Garmin data platform
- Ring Health Tracker
- Health Dashboard

Planned or scaffolded:

- Forgejo
- Woodpecker CI
- Jenkins
- Harbor deployment
- Traefik configuration
- Sealed Secrets usage
- Terraform-managed infrastructure

All infrastructure and configuration for these services is documented and managed from this repository. See `docs/homelab-study-guide.md` for ownership and current status.

---

# 📚 Study Guides

The broad platform study guide is:

```text
docs/homelab-study-guide.md
```

The Health Dashboard is the complete example application for learning the repository's application delivery path:

```text
Application code
  → unit tests
  → Docker image
  → Trivy vulnerability scan
  → GHCR image registry
  → immutable image digest
  → Kustomize
  → Argo CD
  → Kubernetes Deployment
  → MetalLB LAN Service
```

Read the detailed guide here:

```text
apps/health-dashboard/README.md
```

Read the Kubernetes operations runbook here:

```text
kubernetes/applications/health-dashboard/README.md
```

The current Health Dashboard deployment uses:

```text
Namespace: health
MetalLB IP: 192.168.178.216
Argo CD app: health-dashboard
Data sources: Garmin InfluxDB and Ring VictoriaMetrics
```

# 👨‍💻 Author

Ali Fathi

DevOps Homelab Project

---

# 📌 Project Goal

Create a portable, reproducible, GitOps-friendly DevOps platform that can be deployed, managed, and rebuilt from a single repository on any supported workstation.
