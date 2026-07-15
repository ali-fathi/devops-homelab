# Week 4: Container Build Pipeline and Harbor Preparation

This document summarizes the Week 4 work for the `devops-homelab` project.

Week 4 focuses on building an owned demo container image and preparing Harbor as the future private homelab registry.

---

## Goals

Week 4 goals:

```text
Create a small demo application.
Build a Docker image.
Scan the image with Trivy.
Push the image to a registry.
Prepare Harbor registry documentation.
Reserve a MetalLB IP for Harbor.
```

---

## Deliverables

Expected files:

```text
apps/homelab-api/app.py
apps/homelab-api/requirements.txt
apps/homelab-api/Dockerfile
apps/homelab-api/README.md
.github/workflows/homelab-api-build.yaml
kubernetes/registry/harbor/README.md
kubernetes/registry/harbor/values.yaml
kubernetes/registry/harbor/docs/exposure-options.md
kubernetes/registry/harbor/docs/metallb-ip-allocation.md
```

---

## Homelab API

The `homelab-api` app is a simple Flask API used for CI/CD learning.

Path:

```text
apps/homelab-api
```

Endpoints:

```text
GET /
GET /healthz
```

Local build:

```bash
docker build -t homelab-api:local apps/homelab-api
```

Local run:

```bash
docker run --rm -p 8080:8080 homelab-api:local
```

Test:

```bash
curl http://localhost:8080/
curl http://localhost:8080/healthz
```

---

## Container Build Workflow

Expected workflow:

```text
.github/workflows/homelab-api-build.yaml
```

The workflow should:

```text
Build the container image.
Scan with Trivy.
Push image on main branch only.
Skip push for pull requests.
```

Initial registry target:

```text
ghcr.io/<github-owner>/homelab-api
```

Future registry target:

```text
harbor.greyneo.com/homelab/homelab-api
```

---

## Harbor Registry Preparation

Harbor path:

```text
kubernetes/registry/harbor
```

Selected exposure model:

```text
MetalLB LoadBalancer
```

Reserved Harbor IP:

```text
192.168.178.215
```

Planned hostname:

```text
harbor.greyneo.com
```

---

## MetalLB IP Policy

For homelab server-style services:

```text
Use MetalLB.
Use a fixed IP from the MetalLB pool.
Document the service and IP assignment.
Avoid random LoadBalancer allocation for important services.
```

Known assignments:

```text
192.168.178.213   Argo CD
192.168.178.214   Ring Health VictoriaMetrics
192.168.178.215   Harbor Registry
```

---

## Harbor Safety Notes

Harbor is stateful.

Before production-like use:

```text
Confirm Longhorn storage.
Confirm Harbor PVCs.
Plan backup and restore.
Test docker login.
Test push and pull.
Avoid Argo CD prune.
```

---

## Week 4 Completion Checklist

```text
[ ] homelab-api app exists.
[ ] Dockerfile exists.
[ ] App builds locally.
[ ] App runs locally.
[ ] Build workflow exists.
[ ] Build workflow scans image with Trivy.
[ ] Image publishing works on main branch.
[ ] Harbor README exists.
[ ] Harbor values.yaml exists.
[ ] Harbor MetalLB IP is documented as 192.168.178.215.
[ ] Harbor is not blindly GitOps-managed before backup and restore planning.
```

---

## Next Steps After Week 4

Recommended next steps:

```text
Create Kubernetes manifests for homelab-api.
Deploy homelab-api with Argo CD.
Manually deploy Harbor with MetalLB IP 192.168.178.215.
Test Docker login to Harbor.
Push and pull a test image.
Document Harbor backup and restore.
Move Harbor to Argo CD only after successful manual validation.
```
