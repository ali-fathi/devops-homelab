# Harbor Registry

For the repository-wide platform study guide, read:

```text
docs/homelab-study-guide.md
```

This directory contains preparation files for deploying Harbor as the private container registry for the homelab.

Harbor will be used to store, scan, and manage container images for homelab applications.

In this homelab, Harbor should be exposed on the LAN with MetalLB using this reserved IP address:

```text
192.168.178.215
```

---

## Purpose

Harbor will provide:

```text
Private container registry
Project-based image organization
Image vulnerability scanning
Registry user and robot account management
Immutable tag policies
Future image signing workflows
Future SBOM workflows
```

---

## Planned Hostname

Planned hostname:

```text
harbor.greyneo.com
```

Planned MetalLB IP:

```text
192.168.178.215
```

MetalLB pool context:

```text
192.168.178.210-192.168.178.220
```

Reserved known service IPs:

```text
192.168.178.213   Argo CD
192.168.178.214   Ring Health VictoriaMetrics
192.168.178.215   Harbor Registry
```

---

## Deployment Method

Harbor will be deployed with the official Harbor Helm chart.

Helm repository:

```bash
helm repo add harbor https://helm.goharbor.io
helm repo update
```

Initial deployment should be manual first.

After Harbor is stable, backed up, and tested, it can be moved to Argo CD.

---

## Exposure Model

The selected homelab exposure model is:

```text
MetalLB LoadBalancer
```

Target service IP:

```text
192.168.178.215
```

Harbor should not receive a random LoadBalancer address. Harbor should use the reserved MetalLB IP above.

---

## Why Use MetalLB for Harbor

Harbor is a core homelab service.

Using a fixed MetalLB IP gives:

```text
Stable LAN endpoint
Predictable DNS mapping
Simple Docker login target
Consistent registry URL
Easy firewall and routing documentation
```

---

## Storage Notes

Harbor is stateful.

It requires persistent storage for components such as:

```text
registry data
database
Redis
job service data
scanner data
chart or artifact data, if enabled
```

Before production-like use:

```text
Confirm Longhorn storage is healthy.
Confirm Harbor PVCs are Bound.
Plan backup and restore.
Do not enable Argo CD pruning.
Do not store critical images only in Harbor until restore has been tested.
```

---

## GitOps Safety

Initial Argo CD policy for Harbor, if adopted later, should use:

```yaml
syncPolicy:
  automated:
    enabled: true
    prune: false
    selfHeal: true
```

Harbor must not be accidentally pruned because it stores container images and registry metadata.

Do not enable pruning until:

```text
Harbor backup is configured.
Restore has been tested.
PVC ownership is documented.
The Helm release migration path is understood.
```

---

## Planned Repository Files

Current planned structure:

```text
kubernetes/registry/harbor/
├── docs/
│   ├── exposure-options.md
│   └── metallb-ip-allocation.md
├── README.md
└── values.yaml
```

Future possible structure:

```text
kubernetes/registry/harbor/
├── namespace.yaml
├── values.yaml
├── README.md
└── docs/
    ├── exposure-options.md
    ├── metallb-ip-allocation.md
    ├── backup-restore.md
    └── operations.md
```

---

## Initial Manual Deployment Plan

High-level manual plan:

```text
1. Confirm MetalLB pool includes 192.168.178.215.
2. Confirm no existing service uses 192.168.178.215.
3. Create Harbor namespace.
4. Review values.yaml.
5. Deploy Harbor using Helm.
6. Confirm Harbor services and PVCs.
7. Confirm LoadBalancer IP is 192.168.178.215.
8. Test Harbor UI.
9. Test docker login.
10. Push and pull a test image.
11. Document backup and restore.
12. Move to Argo CD only after stable.
```

---

## Preflight Checks

Check MetalLB services:

```bash
kubectl get svc -A | grep 192.168.178
```

Check whether Harbor IP is free:

```bash
kubectl get svc -A | grep 192.168.178.215 || true
```

Check Longhorn:

```bash
kubectl get pods -n longhorn-system
kubectl get storageclass
```

Check available nodes:

```bash
kubectl get nodes -o wide
```

---

## Initial Helm Commands

Add repository:

```bash
helm repo add harbor https://helm.goharbor.io
helm repo update
```

Create namespace:

```bash
kubectl create namespace harbor
```

Install example:

```bash
helm upgrade --install harbor harbor/harbor \
  --namespace harbor \
  --values kubernetes/registry/harbor/values.yaml
```

After install:

```bash
kubectl get pods -n harbor
kubectl get svc -n harbor
kubectl get pvc -n harbor
```

Expected service IP:

```text
192.168.178.215
```

---

## DNS Expectation

The planned DNS record should resolve:

```text
harbor.greyneo.com -> 192.168.178.215
```

This README does not define DNS implementation.

---

## Initial Test Commands

After Harbor is running, test from a workstation that can reach the LAN IP:

```bash
curl -k https://harbor.greyneo.com
```

Login test:

```bash
docker login harbor.greyneo.com
```

Tag test image:

```bash
docker tag homelab-api:local harbor.greyneo.com/homelab/homelab-api:test
```

Push test image:

```bash
docker push harbor.greyneo.com/homelab/homelab-api:test
```

Pull test image:

```bash
docker pull harbor.greyneo.com/homelab/homelab-api:test
```

---

## Important Safety Notes

```text
Do not enable pruning for Harbor initially.
Do not delete Harbor PVCs unless performing a planned restore test.
Do not make Harbor the only copy of important images until backups are tested.
Do not expose Harbor anonymously.
Document robot accounts and registry credentials.
Keep admin credentials in a secret manager.
```

---

## Week 4 Success Criteria

Harbor preparation is complete when:

```text
[ ] Harbor folder exists.
[ ] README.md exists.
[ ] values.yaml exists.
[ ] MetalLB IP 192.168.178.215 is documented.
[ ] exposure-options.md documents MetalLB as the selected approach.
[ ] metallb-ip-allocation.md documents IP ownership.
[ ] Harbor is not yet blindly GitOps-managed.
[ ] Backup and restore are identified as required before production-like use.
```

---

## Future Improvements

```text
Add Harbor backup and restore runbook.
Add Harbor Argo CD Application after manual validation.
Add robot account ExternalSecret.
Add image push workflow to Harbor.
Add vulnerability scanning policy.
Add immutable tag policy.
Add image signing and SBOM generation.
```
