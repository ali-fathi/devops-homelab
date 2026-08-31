# DevOps Homelab Platform — Broad Study Guide

This document explains the whole `devops-homelab` repository as a learning platform.

It is intentionally broader than a command cheat sheet. The objective is to understand the responsibilities of each tool, why it exists, how the tools connect, and how to troubleshoot the system in dependency order.

---

## 1. The platform in one sentence

This repository manages a remote three-node K3s cluster from a reproducible DevContainer using Ansible, Terraform, Helm, Kubernetes manifests, GitHub Actions, Argo CD, Longhorn, MetalLB, External Secrets, Prometheus, Grafana, Loki, and application workloads.

---

## 2. The platform layers

```text
Layer 1: Physical / operating system nodes
Layer 2: K3s Kubernetes cluster
Layer 3: Kubernetes infrastructure
Layer 4: Storage, networking, secrets, and ingress
Layer 5: Observability
Layer 6: Applications and data collectors
Layer 7: CI/CD and GitOps
Layer 8: Documentation, security, and operations
```

The important DevOps principle is separation of responsibility:

```text
Ansible        manages remote hosts and operating-system access
Terraform      describes future infrastructure resources
K3s            provides the Kubernetes control plane and workers
Helm           installs third-party Kubernetes platforms
Kubernetes     describes desired workloads
Longhorn       provides persistent storage
MetalLB        provides bare-metal LoadBalancer addresses
ExternalSecret retrieves secrets from Azure Key Vault
Prometheus     stores/queries platform metrics
Loki           stores/queries logs
Grafana        visualizes metrics and logs
Alertmanager   routes alerts
GitHub Actions builds and scans images
Argo CD        reconciles Git into Kubernetes
```

---

## 3. Repository map

```text
devops-homelab/
├── .devcontainer/       Reproducible operator workstation
├── .github/workflows/    CI, validation, security, and image pipelines
├── ansible/              SSH-based host automation
├── apps/                 Application source and Dockerfiles
├── docs/                 Architecture, operations, runbooks, and study guides
├── kubernetes/           Cluster manifests and platform configuration
├── scripts/              Local helper scripts
├── terraform/            Infrastructure-as-code scaffold
├── .gitleaks.toml        Secret scanner configuration
├── .yamllint             YAML style rules
└── trivy.yaml            Trivy configuration scanner settings
```

Main entry points:

```text
README.md
.devcontainer/README.md
kubernetes/README.md
apps/health-dashboard/README.md
ansible/README.md
```

---

## 4. Workstation and DevContainer

### Why use a DevContainer?

Without a DevContainer, every operator workstation can have different versions of:

```text
kubectl
Helm
Terraform
Ansible
Kustomize
Argo CD CLI
yq
kubeseal
k9s
```

That creates “works on my machine” problems.

The DevContainer defines one management environment. It runs on the local Mac/Linux workstation, while Kubernetes runs remotely.

```text
Local Docker container
  → mounted kubeconfig
  → kubectl
  → remote K3s API
```

The DevContainer does not run a local Kubernetes cluster.

### Mounted credentials

The DevContainer mounts:

```text
~/.kube/k3s-config → /home/vscode/.kube/config
~/.ssh             → /home/vscode/.ssh
```

This makes the container an operator workstation. Kubeconfig and SSH keys should remain outside Git.

### Daily verification

```bash
kubectl get nodes
helm version
terraform version
ansible --version
argocd version --client
kustomize version
```

Read:

```text
.devcontainer/README.md
```

---

## 4.5. Scripts and local helpers

The `scripts/` directory contains small operator helpers. Currently only `verify-cluster.sh` has an implementation; `backup-kubeconfig.sh` and `install-tools.sh` are placeholders and should not be mistaken for completed automation.

```text
scripts/verify-cluster.sh
  Checks basic Kubernetes and CLI availability.

scripts/backup-kubeconfig.sh
  Planned secure kubeconfig backup helper.

scripts/install-tools.sh
  Planned host-tool installation helper; DevContainer is currently preferred.
```

Read:

```text
scripts/README.md
```

---

## 5. Ansible: host automation

Ansible connects over SSH to the three nodes:

```text
DevContainer
  → SSH
  → ansible user
  → sudo
  → K3s nodes
```

Inventory:

```text
ansible/inventory/hosts.yml
```

Group variables:

```text
ansible/inventory/group_vars/k3s_cluster.yml
```

Configuration:

```text
ansible/ansible.cfg
```

Current playbook:

```text
ansible/playbooks/check-cluster.yml
```

Run:

```bash
cd ansible
ansible-inventory --list
ansible k3s_cluster -m ping
ansible-playbook playbooks/check-cluster.yml
```

### What Ansible is and is not

Ansible is good for:

```text
OS packages
users and SSH
sudo configuration
K3s installation and upgrades
OS patching
node hardening
host facts
```

Ansible is not the preferred controller for application Pods after Kubernetes is running. Kubernetes and Argo CD should manage Kubernetes workloads.

### Security model

The intended model is:

```text
ansible user
  → SSH key authentication
  → passwordless sudo
```

Avoid direct root SSH for normal automation.

### Troubleshooting

```bash
ansible-inventory --graph
ansible k3s_cluster -m ping -vvv
ssh -i ~/.ssh/my_ansible_homelab ansible@192.168.178.80
```

Common problems:

```text
wrong private-key path
SSH key not copied
ansible user missing
sudoers configuration invalid
Python missing on a node
host key or network failure
```

Read:

```text
ansible/README.md
```

---

## 6. Terraform: infrastructure as code

Terraform describes infrastructure declaratively:

```text
variables → resources/providers → plan → apply → state
```

Current Terraform status:

```text
Provider configuration exists.
Environment variable exists.
Output exists.
No meaningful infrastructure resources are currently defined.
```

Files:

```text
terraform/providers.tf
terraform/variables.tf
terraform/outputs.tf
terraform/modules/modules.yaml
```

Terraform is currently a scaffold, not the active Kubernetes deployment mechanism.

Commands when resources are added:

```bash
cd terraform
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

### Terraform versus Kubernetes GitOps

Terraform is normally appropriate for:

```text
cloud resources
networks
DNS
VMs
Kubernetes bootstrap resources
```

Argo CD is better for continuously reconciling application manifests:

```text
Deployments
Services
ConfigMaps
PrometheusRules
application configuration
```

Avoid having Terraform and Argo CD manage the same resource fields without a clear ownership model.

Read:

```text
terraform/README.md
```

---

## 7. K3s cluster foundation

The cluster has:

```text
1 control-plane node
2 worker nodes
```

The DevContainer connects to the API server at:

```text
https://192.168.178.80:6443
```

Current K3s recovery baseline:

```yaml
disable-network-policy: true
flannel-backend: host-gw
disable:
  - servicelb
```

This setting is historical, not the Phase 4 security target: disabling the controller means Kubernetes NetworkPolicies do not enforce. It was retained after a cross-node networking incident and must be changed only through the gated Ansible procedure in:

```text
docs/runbooks/k3s-networkpolicy-controller-remediation.md
```

The historical incident record remains in:

```text
docs/k3s-baseline-networking.md
```

Validate:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get events -A --sort-by=.metadata.creationTimestamp
```

---

## 8. Helm and bootstrap

Helm is a package manager for Kubernetes. It installs third-party platforms from charts.

The bootstrap script currently adds repositories and runs `helm repo update`:

```bash
./kubernetes/bootstrap/bootstrap.sh
```

Repositories include:

```text
MetalLB
Longhorn
Argo CD
Prometheus Community
Grafana
External Secrets
```

The script currently does not install every chart. Installation should remain explicit until ownership and ordering are fully automated.

Why this matters:

```text
Adding a Helm repository is safe.
Installing a chart can create CRDs, PVCs, controllers, and cluster-wide behavior.
```

Read:

```text
kubernetes/bootstrap/README.md
```

---

## 9. Networking: MetalLB and future Traefik

K3s on bare metal cannot request a cloud LoadBalancer. MetalLB provides LAN addresses.

Pool:

```text
192.168.178.210-192.168.178.220
```

Known services:

```text
Argo CD              192.168.178.213
Ring VictoriaMetrics 192.168.178.214
Harbor reservation   192.168.178.215
Health Dashboard     192.168.178.216
```

MetalLB flow:

```text
Kubernetes Service type LoadBalancer
  → MetalLB controller assigns IP
  → MetalLB speaker advertises IP using Layer 2
  → LAN clients reach the Service
```

Traefik is intended for hostname/TLS routing but is not fully configured yet. Direct MetalLB Services are therefore used for current exposed tools.

Read:

```text
docs/networking.md
kubernetes/infrastructure/metallb/README.md
```

---

## 10. Storage: Longhorn

Kubernetes separates storage requests from storage implementation:

```text
Pod → PVC → StorageClass → PersistentVolume → Longhorn volume
```

Longhorn provides:

```text
replicated block storage
snapshots
backups
volume attachment
```

Stateful resources:

```text
Garmin InfluxDB
Garmin token PVC
Ring VictoriaMetrics
Grafana
Prometheus
Alertmanager
Loki
```

Storage rules:

```text
Do not casually delete PVCs.
Do not rename PVCs in GitOps migrations.
Back up before upgrades.
Test restore procedures.
Keep prune=false during adoption.
```

Read:

```text
docs/storage.md
kubernetes/infrastructure/longhorn/README.md
kubernetes/applications/nginx-longhorn-metallb/README.md
```

---

## 11. Secrets: Azure Key Vault and External Secrets

The desired secret flow is:

```text
Azure Key Vault
  → ClusterSecretStore
  → ExternalSecret
  → Kubernetes Secret
  → Pod environment variables or volume
```

Advantages:

```text
no real secrets in Git
central rotation
least-privilege external access
Kubernetes-native consumption
```

The repository uses this pattern for:

```text
Garmin credentials
InfluxDB credentials
Argo CD Git repository credentials
Telegram credentials
Health Dashboard InfluxDB credentials
```

Debug:

```bash
kubectl get clustersecretstore
kubectl describe clustersecretstore azure-keyvault
kubectl get externalsecret -A
kubectl describe externalsecret <name> -n <namespace>
```

Do not print Secret values into logs or terminal history.

Read:

```text
docs/runbooks/external-secrets-debug.md
kubernetes/applications/garmin/README.md
```

---

## 12. Applications and data platforms

### Garmin application

```text
Garmin Connect
  → fetcher
  → InfluxDB GarminStats
  → Grafana / Health Dashboard
```

### Ring Health Tracker

```text
Colmi R02
  → Android application
  → Cloudflare Tunnel
  → VictoriaMetrics
  → Grafana / Health Dashboard
```

### Health Dashboard

```text
Browser
  → Flask API
  → InfluxDB + VictoriaMetrics
  → charts, narrative, CSV, JSON, PDF
```

### Homelab API

The small Flask API is a CI/CD learning workload:

```text
source
  → Docker build
  → Trivy scan
  → GHCR
  → future Kubernetes deployment
```

It is intentionally simpler than the Health Dashboard so that container delivery can be learned first.

Read:

```text
apps/homelab-api/README.md
apps/health-dashboard/README.md
kubernetes/applications/README.md
```

---

## 13. Observability

Observability answers three questions:

```text
Are services available?       Metrics
What happened?               Logs
Should someone act?          Alerts
```

Current flow:

```text
Kubernetes metrics
  → Prometheus
  → Grafana dashboards
  → PrometheusRules
  → Alertmanager
  → Telegram

Pod logs
  → Grafana Alloy DaemonSet
  → Loki
  → Grafana LogQL
  → Loki alert rules
  → Alertmanager
```

Responsibilities:

```text
monitoring/  Prometheus and Grafana
logging/     Loki and Alloy
alerting/    rules, Alertmanager, Telegram
```

Good alerts should be:

```text
actionable
low-noise
linked to runbooks
owned
```

Read:

```text
kubernetes/observability/README.md
kubernetes/observability/monitoring/README.md
kubernetes/observability/logging/README.md
kubernetes/observability/alerting/README.md
```

---

## 14. CI, security, and validation

GitHub Actions currently provides:

```text
Kubernetes YAML linting
Kubernetes schema validation
Gitleaks secret scanning
Trivy configuration scanning
Homelab API image build
Health Dashboard tests/build/scan/publish
```

The quality gate is:

```text
source change
  → tests
  → YAML validation
  → security scan
  → container scan
  → registry publish
  → GitOps deployment
```

Security policy:

```text
Gitleaks findings are treated as serious failures.
Trivy HIGH/CRITICAL image findings block Health Dashboard builds.
Configuration findings are reviewed and tracked.
Accepted risks must be documented.
```

Read:

```text
docs/ci-manifest-validation.md
docs/security-findings.md
.github/workflows/
```

---

## 15. GitOps operating model

The repository is the desired state.

```text
Git
  → Argo CD
  → Kubernetes
```

Normal change:

```text
Create branch
Edit source/manifests
Run local tests
Open Pull Request
CI validates
Merge
Argo CD syncs
Verify health
```

Stateful change:

```text
Back up
Review diff
Change one component
Sync carefully
Verify PVCs and Pods
Test restore if necessary
```

Never use `kubectl edit` as a permanent workflow. Manual changes create drift.

---

## 16. Registry strategy

Current registry:

```text
GitHub Container Registry
```

Planned registry:

```text
Harbor at 192.168.178.215
```

Harbor adds:

```text
private image storage
projects and robot accounts
vulnerability scanning
immutability policies
future SBOM/signing workflows
```

Harbor is stateful. Deploy manually first, test push/pull, configure backup/restore, then adopt through Argo CD.

Read:

```text
kubernetes/registry/README.md
docs/container-build-pipeline-harbor.md
```

---

## 17. Day-2 troubleshooting order

Always troubleshoot from the bottom of the dependency tree upward:

```text
1. Workstation and kubeconfig
2. Kubernetes API
3. Node Ready state
4. Pod scheduling
5. PVC and storage
6. Pod readiness
7. Service endpoints
8. MetalLB/Ingress
9. Application logs
10. External database or API
11. Argo desired/live diff
```

Useful commands:

```bash
kubectl get nodes
kubectl get pods -A
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace>
kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp
kubectl get endpoints <service> -n <namespace>
argocd app get <app>
argocd app diff <app>
```

Do not change five layers at once. Record the symptom, test one dependency, make one change, and retest.

---

## 18. What is implemented versus planned

Implemented:

```text
DevContainer management environment
K3s cluster documentation
Ansible connectivity automation
MetalLB configuration
Longhorn usage
Garmin data ingestion
Ring VictoriaMetrics backend
Grafana/Loki/Alertmanager configuration
Argo CD applications for Garmin, Ring, and Health Dashboard
GitHub Actions validation and security scans
Health Dashboard CI/CD and immutable image write-back
```

Scaffold or planned:

```text
Terraform resources and reusable modules
Traefik configuration
Sealed Secrets usage
Harbor deployment
Forgejo deployment
Jenkins deployment
Woodpecker deployment
Health Dashboard authentication/TLS
Automatic backup/restore runbooks
```

Documentation should distinguish “implemented” from “planned” so a learner does not mistake a design document for a deployed service.

---

## 19. Recommended learning sequence

```text
Week 1: Linux, SSH, DevContainer, kubeconfig
Week 2: kubectl, Namespaces, Pods, Deployments, Services
Week 3: K3s networking and MetalLB
Week 4: Longhorn PVCs and persistence demo
Week 5: Helm and platform installation
Week 6: Garmin and Ring data pipelines
Week 7: Prometheus, Grafana, Loki, and alerts
Week 8: Dockerfiles, GHCR, Trivy, and CI
Week 9: Kustomize and Argo CD GitOps
Week 10: Secrets, backups, rollback, and security
Week 11: Harbor and private registry delivery
Week 12: authentication, TLS, SLOs, and disaster recovery
```

For each topic:

```text
Read the concept
Inspect the manifest
Run a safe validation command
Deploy a small example
Break it intentionally
Read logs/events
Recover it
Document the lesson
```

---

## 20. Related documents

```text
README.md
docs/architecture.md
docs/gitops.md
docs/networking.md
docs/storage.md
docs/troubleshooting.md
docs/security-findings.md
docs/runbooks/
```
