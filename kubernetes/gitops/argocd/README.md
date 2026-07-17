# Argo CD GitOps Deployment - Homelab K3s

This README documents the complete Argo CD GitOps setup for the `devops-homelab` project.

The goal is to use Argo CD as the GitOps controller for the K3s homelab cluster, expose the Argo CD UI/API through MetalLB, and gradually move workloads from manual `kubectl apply` / `helm upgrade` workflows into declarative Git-managed deployments.

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. Current Homelab Context](#2-current-homelab-context)
- [3. Target Architecture](#3-target-architecture)
- [4. Repository Structure](#4-repository-structure)
- [5. Prerequisites](#5-prerequisites)
- [6. MetalLB Requirements](#6-metallb-requirements)
- [7. Argo CD Installation](#7-argo-cd-installation)
- [8. Access Argo CD Through MetalLB](#8-access-argo-cd-through-metallb)
- [9. Argo CD CLI Setup](#9-argo-cd-cli-setup)
- [10. Repository Access](#10-repository-access)
- [11. Azure Key Vault Integration for Private Git Repositories](#11-azure-key-vault-integration-for-private-git-repositories)
- [12. AppProject Setup](#12-appproject-setup)
- [13. First GitOps Application - Garmin](#13-first-gitops-application---garmin)
- [14. GitOps Workflow](#14-gitops-workflow)
- [15. Drift Detection and Self-Healing](#15-drift-detection-and-self-healing)
- [16. Rollback Workflow](#16-rollback-workflow)
- [17. Day-2 Operations](#17-day-2-operations)
- [18. Troubleshooting](#18-troubleshooting)
- [19. Useful Argo CD Command Cheatsheet](#19-useful-argo-cd-command-cheatsheet)
- [20. Recommended Migration Order](#20-recommended-migration-order)
- [21. Security Notes](#21-security-notes)
- [22. Success Criteria](#22-success-criteria)
- [23. References](#23-references)

---

## 1. Overview

Argo CD is used as the GitOps continuous delivery controller for this homelab Kubernetes platform.

With Argo CD:

```text
Git repository = desired state
Kubernetes cluster = actual state
Argo CD = reconciliation controller
```

Argo CD watches the Git repository, compares the manifests in Git with the live Kubernetes cluster, and reports whether applications are `Synced`, `OutOfSync`, `Healthy`, or `Degraded`.

The first GitOps-managed workload in this setup is:

```text
garmin
```

The Garmin integration is a good first GitOps target because it is isolated, already working, uses Azure Key Vault through External Secrets, and contains practical Kubernetes resources such as a namespace, PVCs, InfluxDB, and application Deployment.

---

## 2. Current Homelab Context

Existing platform components:

```text
K3s
MetalLB
Longhorn
Prometheus
Grafana
Alertmanager
Telegram alerts
Loki
Grafana Alloy
Azure Key Vault
External Secrets Operator
Garmin integration
Strava integration
Custom Grafana dashboards
```

Argo CD will become the GitOps layer on top of this platform.

The current repository root is:

```text
devops-homelab
```

Important existing directories:

```text
ansible/
docs/
kubernetes/
scripts/
terraform/
```

The Argo CD GitOps files live under:

```text
kubernetes/gitops/argocd/
```

---

## 3. Target Architecture

```text
Developer workstation / code-server / devcontainer
        |
        | git commit + git push
        v
Git repository: devops-homelab
        |
        | Argo CD reads desired state
        v
Argo CD
        |
        | sync / self-heal / drift detection
        v
K3s cluster
        |
        +-- garmin namespace
        +-- strava namespace
        +-- monitoring namespace
        +-- logging namespace
        +-- future GitOps-managed workloads
```

Argo CD UI/API is exposed through MetalLB:

```text
http://192.168.178.213
```

Optional local hostname:

```text
http://argocd.homelab.local
```

---

## 4. Repository Structure

Recommended Argo CD folder structure:

```text
kubernetes/gitops/argocd/
├── README.md
├── values.yaml
├── projects/
│   └── homelab-platform-project.yaml
├── repositories/
│   └── external-secret-git-repo.yaml
└── applications/
    └── garmin.yaml
```

Create the folders:

```bash
mkdir -p kubernetes/gitops/argocd/projects
mkdir -p kubernetes/gitops/argocd/repositories
mkdir -p kubernetes/gitops/argocd/applications
mkdir -p kubernetes/gitops/argocd/docs
```

---

## 5. Prerequisites

Required local tools:

```text
kubectl
helm
argocd CLI
git
az CLI
jq
yq optional
k9s optional
```

Verify Kubernetes access:

```bash
kubectl get nodes
kubectl get pods -A
```

Verify Helm:

```bash
helm version
```

Verify Azure CLI:

```bash
az version
```

Verify Argo CD CLI:

```bash
argocd version --client
```

---

## 6. MetalLB Requirements

Argo CD is exposed using a Kubernetes `LoadBalancer` Service.

Because this is a bare-metal / homelab K3s cluster, MetalLB provides the LoadBalancer implementation.

Check MetalLB pods:

```bash
kubectl get pods -n metallb-system
```

Expected:

```text
controller   Running
speaker      Running
```

Check MetalLB address pools:

```bash
kubectl get ipaddresspool -n metallb-system
```

Current pool:

```text
NAME           AUTO ASSIGN   ADDRESSES
homelab-pool   true          192.168.178.210-192.168.178.220
```

Argo CD uses:

```text
192.168.178.213
```

Verify the pool YAML:

```bash
kubectl get ipaddresspool homelab-pool \
  -n metallb-system \
  -o yaml
```

Expected address range:

```yaml
spec:
  addresses:
    - 192.168.178.210-192.168.178.220
```

Check Argo CD service:

```bash
kubectl get svc argocd-server -n argocd
```

Expected:

```text
argocd-server   LoadBalancer   10.43.x.x   192.168.178.213
```

---

## 7. Argo CD Installation

Argo CD is installed using Helm.

Add the Argo Helm repository:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

Create or update:

```text
kubernetes/gitops/argocd/values.yaml
```

Recommended values:

```yaml
global:
  domain: argocd.homelab.local

configs:
  params:
    server.insecure: true

server:
  service:
    type: LoadBalancer
    loadBalancerIP: 192.168.178.213
    annotations:
      metallb.universe.tf/address-pool: homelab-pool

  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

controller:
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi

repoServer:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

applicationSet:
  enabled: true

notifications:
  enabled: false

dex:
  enabled: false

redis:
  enabled: true
```

Install or upgrade Argo CD:

```bash
helm upgrade --install argocd \
  argo/argo-cd \
  -n argocd \
  --create-namespace \
  -f kubernetes/gitops/argocd/values.yaml
```

Watch pods:

```bash
kubectl get pods -n argocd -w
```

Expected components:

```text
argocd-application-controller
argocd-applicationset-controller
argocd-redis
argocd-repo-server
argocd-server
```

---

## 8. Access Argo CD Through MetalLB

Check the service:

```bash
kubectl get svc argocd-server -n argocd
```

Expected:

```text
EXTERNAL-IP = 192.168.178.213
```

Open in browser:

```text
http://192.168.178.213
```

Optional `/etc/hosts` entry:

```bash
sudo nano /etc/hosts
```

Add:

```text
192.168.178.213 argocd.homelab.local
```

Then open:

```text
http://argocd.homelab.local
```

Get the initial admin password:

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Login:

```text
Username: admin
Password: output from command
```

Change the admin password after first login.

---

## 9. Argo CD CLI Setup

Install the Argo CD CLI inside your devcontainer or code-server image.

Verify:

```bash
argocd version --client
```

Login:

```bash
argocd login 192.168.178.213 \
  --username admin \
  --password '<ARGOCD_PASSWORD>' \
  --insecure
```

Check connection:

```bash
argocd account get-user-info
```

List apps:

```bash
argocd app list
```

---

## 10. Repository Access

Argo CD must be able to read the Git repository:

```text
devops-homelab
```

Repository URL example:

```text
https://github.com/YOUR_USER_OR_ORG/devops-homelab.git
```

There are two options:

```text
Public repository  -> no credentials required
Private repository -> use Azure Key Vault + External Secrets
```

The recommended homelab pattern is private repository with credentials stored in Azure Key Vault.

---

## 11. Azure Key Vault Integration for Private Git Repositories

Azure Key Vault name:

```text
kv-homelab-k3s
```

External Secrets ClusterSecretStore:

```text
azure-keyvault
```

Create a GitHub fine-grained token with:

```text
Repository: devops-homelab
Contents: Read-only
Metadata: Read-only
```

Store GitHub username:

```bash
az keyvault secret set \
  --vault-name kv-homelab-k3s \
  --name github-username \
  --value "YOUR_GITHUB_USERNAME"
```

Store GitHub token:

```bash
az keyvault secret set \
  --vault-name kv-homelab-k3s \
  --name github-token \
  --value "YOUR_GITHUB_TOKEN"
```

Verify:

```bash
az keyvault secret list \
  --vault-name kv-homelab-k3s \
  --query "[].name" \
  -o table
```

Create:

```text
kubernetes/gitops/argocd/repositories/external-secret-git-repo.yaml
```

Content:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: argocd-repo-devops-homelab
  namespace: argocd
spec:
  refreshInterval: 48h

  secretStoreRef:
    name: azure-keyvault
    kind: ClusterSecretStore

  target:
    name: argocd-repo-devops-homelab
    creationPolicy: Owner
    template:
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repository
      data:
        type: git
        url: https://github.com/YOUR_USER_OR_ORG/devops-homelab.git
        username: "{{ .username }}"
        password: "{{ .password }}"

  data:
    - secretKey: username
      remoteRef:
        key: github-username

    - secretKey: password
      remoteRef:
        key: github-token
```

Apply:

```bash
kubectl apply -f kubernetes/gitops/argocd/repositories/external-secret-git-repo.yaml
```

Verify:

```bash
kubectl get externalsecret -n argocd
kubectl get secret argocd-repo-devops-homelab -n argocd
```

Restart repo server if needed:

```bash
kubectl rollout restart deployment argocd-repo-server -n argocd
```

Check repository:

```bash
argocd repo list
```

---

## 12. AppProject Setup

`AppProject` defines allowed repositories, cluster destinations, and resource permissions.

Create:

```text
kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
```

Content:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: homelab-platform
  namespace: argocd
spec:
  description: Homelab platform and observability workloads

  sourceRepos:
    - https://github.com/YOUR_USER_OR_ORG/devops-homelab.git

  destinations:
    - namespace: garmin
      server: https://kubernetes.default.svc

    - namespace: strava
      server: https://kubernetes.default.svc

    - namespace: monitoring
      server: https://kubernetes.default.svc

    - namespace: logging
      server: https://kubernetes.default.svc

    - namespace: external-secrets-system
      server: https://kubernetes.default.svc

    - namespace: argocd
      server: https://kubernetes.default.svc

  clusterResourceWhitelist:
    - group: ""
      kind: Namespace

  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
```

Apply:

```bash
kubectl apply -f kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
```

Verify:

```bash
kubectl get appproject -n argocd
```

Expected:

```text
homelab-platform
```

---

## 13. First GitOps Application - Garmin

Create:

```text
kubernetes/gitops/argocd/applications/garmin.yaml
```

Content:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: garmin
  namespace: argocd
spec:
  project: homelab-platform

  source:
    repoURL: https://github.com/ali-fathi/devops-homelab.git
    targetRevision: main
    path: kubernetes/applications/garmin

    directory:
      include: "{*.yaml,*.yml}"
      recurse: true

  destination:
    server: https://kubernetes.default.svc
    namespace: garmin

  syncPolicy:
    automated:
      enabled: true
      prune: false
      selfHeal: true

    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

Apply:

```bash
kubectl apply -f kubernetes/gitops/argocd/applications/garmin.yaml
```

Commit and push:

```bash
git add kubernetes/gitops/argocd
git commit -m "Bootstrap Argo CD GitOps with MetalLB access"
git push origin main
```

Check app:

```bash
argocd app get garmin
```

Expected:

```text
Status: Synced
Health: Healthy
```

If not synced:

```bash
argocd app diff garmin
argocd app sync garmin
```

---

## 14. GitOps Workflow

Standard workflow:

```text
1. Edit manifests in Git
2. Commit and push
3. Argo CD detects change
4. Argo CD syncs application
5. Kubernetes cluster matches Git
```

Example:

```bash
nano kubernetes/applications/garmin/namespace.yaml
```

Add annotation:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: garmin
  annotations:
    gitops.argocd.dev/managed: "true"
```

Commit:

```bash
git add kubernetes/applications/garmin/namespace.yaml
git commit -m "Mark Garmin namespace as GitOps managed"
git push origin main
```

Refresh and sync:

```bash
argocd app refresh garmin
argocd app sync garmin
```

Verify:

```bash
kubectl get namespace garmin -o yaml | grep gitops.argocd.dev -A2
```

---

## 15. Drift Detection and Self-Healing

Drift means the live cluster differs from Git.

Test drift:

```bash
kubectl scale deployment garmin-fetch-data \
  -n garmin \
  --replicas=0
```

Check Argo CD:

```bash
argocd app get garmin
```

Expected:

```text
OutOfSync
```

Because `selfHeal: true`, Argo CD may restore the resource automatically.

Watch:

```bash
kubectl get deployment garmin-fetch-data -n garmin -w
```

Important note:

If the Git manifest does not define `replicas`, Kubernetes may default the replica count. If you want Argo CD to manage replicas, define `replicas` explicitly. If HPA manages replicas later, do not let Argo CD and HPA fight over the same field.

---

## 16. Rollback Workflow

Rollback is done through Git.

Revert the last commit:

```bash
git revert HEAD
git push origin main
```

Sync:

```bash
argocd app refresh garmin
argocd app sync garmin
```

Verify rollback:

```bash
kubectl get namespace garmin -o yaml | grep gitops.argocd.dev
```

Expected:

```text
no output
```

---

## 17. Day-2 Operations

### Upgrade Argo CD

Update chart repo:

```bash
helm repo update
```

Upgrade:

```bash
helm upgrade argocd \
  argo/argo-cd \
  -n argocd \
  -f kubernetes/gitops/argocd/values.yaml
```

### Check Argo CD pods

```bash
kubectl get pods -n argocd
```

### Check Argo CD service

```bash
kubectl get svc argocd-server -n argocd
```

### Restart Argo CD repo server

```bash
kubectl rollout restart deployment argocd-repo-server -n argocd
```

### Restart Argo CD server

```bash
kubectl rollout restart deployment argocd-server -n argocd
```

### Check logs

```bash
kubectl logs -n argocd deployment/argocd-server --tail=100
kubectl logs -n argocd deployment/argocd-repo-server --tail=100
kubectl logs -n argocd statefulset/argocd-application-controller --tail=100
```

---

## 18. Troubleshooting

### Argo CD service has no external IP

Check service:

```bash
kubectl describe svc argocd-server -n argocd
```

Check MetalLB pool:

```bash
kubectl get ipaddresspool -n metallb-system
```

If you see:

```text
requested loadBalancer IP is not compatible with requested address pool
```

Make sure the service annotation matches the real pool name:

```yaml
metallb.universe.tf/address-pool: homelab-pool
```

### Cannot open Argo CD UI

Check:

```bash
curl -I http://192.168.178.213
kubectl get endpoints argocd-server -n argocd
kubectl get pods -n argocd
```

### Cannot login with CLI

Use:

```bash
argocd login 192.168.178.213 \
  --username admin \
  --password '<PASSWORD>' \
  --insecure
```

### Repository not visible

Check ExternalSecret:

```bash
kubectl get externalsecret -n argocd
kubectl describe externalsecret argocd-repo-devops-homelab -n argocd
```

Check Argo CD repo secret:

```bash
kubectl get secret argocd-repo-devops-homelab -n argocd
```

Restart repo server:

```bash
kubectl rollout restart deployment argocd-repo-server -n argocd
```

Check repo list:

```bash
argocd repo list
```

### Application is OutOfSync

Check diff:

```bash
argocd app diff garmin
```

Sync manually:

```bash
argocd app sync garmin
```

### Application is Degraded

Check app details:

```bash
argocd app get garmin
```

Check Kubernetes resources:

```bash
kubectl get pods -n garmin
kubectl describe pod -n garmin <pod-name>
kubectl logs -n garmin <pod-name>
```

### Resource already exists

Because Garmin existed before Argo CD, resources may already exist.

Use:

```bash
argocd app diff garmin
```

If the live state is safe to adopt:

```bash
argocd app sync garmin
```

Keep pruning disabled until ownership is understood.

---

## 19. Useful Argo CD Command Cheatsheet

### Authentication

```bash
argocd login 192.168.178.213 --username admin --password '<PASSWORD>' --insecure
argocd logout 192.168.178.213
argocd account get-user-info
argocd account update-password
```

### Applications

```bash
argocd app list
argocd app get garmin
argocd app resources garmin
argocd app manifests garmin
argocd app history garmin
```

### Sync

```bash
argocd app sync garmin
argocd app sync garmin --prune
argocd app refresh garmin
argocd app wait garmin --health --sync
```

### Diff

```bash
argocd app diff garmin
argocd app diff garmin --local kubernetes/applications/garmin
```

### Rollback

```bash
argocd app history garmin
argocd app rollback garmin <REVISION_ID>
```

Preferred GitOps rollback is usually:

```bash
git revert <commit>
git push origin main
argocd app sync garmin
```

### Repositories

```bash
argocd repo list
argocd repo get https://github.com/YOUR_USER_OR_ORG/devops-homelab.git
```

### Projects

```bash
argocd proj list
argocd proj get homelab-platform
```

### Kubernetes-native checks

```bash
kubectl get applications -n argocd
kubectl get appproject -n argocd
kubectl describe application garmin -n argocd
kubectl get pods -n argocd
kubectl get svc argocd-server -n argocd
```

### Logs

```bash
kubectl logs -n argocd deployment/argocd-server --tail=100
kubectl logs -n argocd deployment/argocd-repo-server --tail=100
kubectl logs -n argocd statefulset/argocd-application-controller --tail=100
```

### Hard refresh

```bash
argocd app get garmin --hard-refresh
```

### Delete an application without deleting resources

```bash
kubectl patch application garmin -n argocd \
  -p '{"metadata":{"finalizers":null}}' \
  --type=merge

kubectl delete application garmin -n argocd
```

Use this carefully.

---

## 20. Recommended Migration Order

Do not move everything to Argo CD at once.

Recommended order:

```text
1. Garmin
2. Strava
3. Grafana dashboards
4. Loki alert rules
5. Alloy values
6. Loki values
7. Monitoring values
8. Alertmanager values
9. External Secrets
10. MetalLB
11. Longhorn
```

Reason:

```text
Start with isolated apps.
Then move observability configuration.
Move platform-critical components last.
```

---

## 21. Security Notes

Do not commit secrets.

Use Azure Key Vault for:

```text
GitHub token
Telegram bot token
Garmin credentials
Strava credentials
InfluxDB credentials
Grafana admin credentials if externalized later
```

Use External Secrets with:

```yaml
refreshInterval: 48h
```

Keep Argo CD repository access read-only.

Recommended GitHub token permissions:

```text
Contents: Read-only
Metadata: Read-only
```

Do not enable automatic pruning globally until each application is validated.

For Week 1:

```yaml
prune: false
```

Later, after validation:

```yaml
prune: true
```

---

## 22. Success Criteria

Week 1 is complete when:

```text
[ ] Argo CD is installed.
[ ] Argo CD UI opens at http://192.168.178.213.
[ ] Argo CD CLI can login successfully.
[ ] Argo CD can read the devops-homelab Git repository.
[ ] AppProject homelab-platform exists.
[ ] Garmin Application exists.
[ ] Garmin appears in Argo CD UI.
[ ] Garmin resources are Synced or diff is understood.
[ ] Drift detection has been tested.
[ ] Self-heal behavior has been observed.
[ ] Git rollback workflow has been tested.
[ ] No secrets are committed to Git.
```

---

cd ~/workspace/devops-homelab

# Validate app manifests
kubectl apply --dry-run=server -f kubernetes/applications/ring-health-tracker/

# Commit app manifests
git add kubernetes/applications/ring-health-tracker
git commit -m "Add Ring Health Tracker VictoriaMetrics backend"
git push origin main

# Update Argo CD project
kubectl apply -f kubernetes/gitops/argocd/projects/homelab-platform-project.yaml

git add kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
git commit -m "Allow ring-health namespace in Argo CD project"
git push origin main

# Create/apply Argo CD application
kubectl apply -f kubernetes/gitops/argocd/applications/ring-health-tracker.yaml

git add kubernetes/gitops/argocd/applications/ring-health-tracker.yaml
git commit -m "GitOps Ring Health Tracker with Argo CD"
git push origin main

# Refresh/sync
argocd app refresh ring-health-tracker --hard
argocd app sync ring-health-tracker
argocd app get ring-health-tracker
argocd app resources ring-health-tracker


## Related Docs

Recommended related files:

```text
docs/gitops.md
docs/runbooks/argocd-app-outofsync.md
docs/runbooks/argocd-comparison-error.md
docs/runbooks/external-secrets-debug.md
kubernetes/gitops/argocd/docs/argocd-cheatsheet.md
```

## 23. References

- Argo CD documentation: https://argo-cd.readthedocs.io/
- Argo CD getting started: https://argo-cd.readthedocs.io/en/stable/getting_started/
- Argo CD declarative setup: https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/
- Argo CD automated sync policy: https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/
- Argo Helm chart repository: https://github.com/argoproj/argo-helm
- MetalLB documentation: https://metallb.io/
- External Secrets Operator Azure Key Vault provider: https://external-secrets.io/latest/provider/azure-key-vault/
